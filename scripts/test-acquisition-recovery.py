"""Exercise real worker crashes and recovery in an isolated Docker network.

Creates and removes its own PostgreSQL container. Never accepts a database URL,
never mounts credentials, and never contacts a real source or hosted database.
Requires Docker and the local community-orgs-acquisition:local image.
"""
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'tools/ingestion/python'
SUFFIX = uuid.uuid4().hex[:10]
NETWORK = 'acquisition-recovery-' + SUFFIX
DATABASE = NETWORK + '-db'
IMAGE = 'community-orgs-acquisition:local'
RESOURCE = 'eb1e6be4-5b13-4feb-b28e-388bf7c26f93'
ACTOR = '00000000-0000-4000-8000-000000000093'
containers = []
checks = []


def command(args, input=None, timeout=60):
    result = subprocess.run(args, input=input, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'{args[0:3]} failed:\n{result.stderr[-6000:]}\n{result.stdout[-1000:]}')
    return result.stdout.strip()


def sql(query):
    return command(['docker', 'exec', '-i', DATABASE, 'psql', '-U', 'postgres',
                    '-X', '-qAt', '-v', 'ON_ERROR_STOP=1'], input=query)


def state(job):
    return json.loads(sql(f"select row_to_json(j) from ingestion.acquisition_jobs j where id='{job}';"))


def enqueue():
    return sql(f"select ingestion.enqueue_acnc('{RESOURCE}','manual',null);")


def worker(mode, detached=False):
    name = NETWORK + '-' + mode + '-' + uuid.uuid4().hex[:5]
    containers.append(name)
    args = ['docker', 'run', '--name', name, '--network', NETWORK,
            '--read-only', '--cap-drop=ALL', '--security-opt=no-new-privileges',
            '-e', 'PGHOST=recovery-db', '-e', 'PGUSER=community_orgs_acquisition',
            '-e', 'PGDATABASE=postgres', '-e', 'PGSSLMODE=disable',
            '-e', 'ACQUISITION_DISPOSABLE_TEST=1', '-e', 'PYTHONPATH=/fixture-src',
            '-v', f'{PACKAGE}:/fixture-src:ro', '-w', '/fixture-src',
            '--entrypoint', 'python3']
    if detached:
        args.append('-d')
    args += [IMAGE, 'tests/recovery_worker_fixture.py', mode]
    output = command(args)
    return name if detached else json.loads(output.splitlines()[-1])


def expect_marker(name, marker):
    end = time.monotonic() + 25
    while time.monotonic() < end:
        logs = command(['docker', 'logs', name])
        if marker in logs:
            return
        time.sleep(0.2)
    raise AssertionError('Worker did not reach ' + marker)


def snapshot():
    return sql("""select jsonb_build_object(
      'organisations',(select jsonb_agg(to_jsonb(x) order by org_id) from community_orgs.organisations x),
      'contacts',(select jsonb_agg(to_jsonb(x) order by contact_id) from community_orgs.contact_info x),
      'publications',(select count(*) from ingestion.publications))::text;""")


def record(name, **details):
    checks.append({'check': name, 'result': 'pass', **details})
    print(json.dumps(checks[-1]), flush=True)


try:
    command(['docker', 'image', 'inspect', IMAGE])
    command(['docker', 'network', 'create', '--internal', NETWORK])
    containers.append(DATABASE)
    command(['docker', 'run', '-d', '--name', DATABASE, '--network', NETWORK,
             '--network-alias', 'recovery-db', '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:16'])
    for attempt in range(50):
        ready = subprocess.run(['docker', 'exec', DATABASE, 'pg_isready', '-U', 'postgres'], capture_output=True)
        if ready.returncode == 0:
            break
        time.sleep(0.2)
    else:
        raise AssertionError('Disposable database did not start')
    setup = command([sys.executable, str(ROOT / 'scripts/build-ingestion-test-sql.py')])
    sql(setup)
    record('full_ingestion_sql_suites', coverage='manual edits, stale approvals, withdrawal replay, access, queue recovery')
    sql((ROOT / 'supabase/migrations/20260917040000_acquisition_worker_login.sql').read_text())
    sql(f"""insert into auth.users values('{ACTOR}');
      insert into ingestion.operators(user_id) values('{ACTOR}');
      insert into ingestion.sources(source_id,resource_id,metadata,enabled)
      values('acnc-register','{RESOURCE}','{{"test":"isolated-network-fixtures"}}',true);
      insert into ingestion.acquisition_configs(resource_id,postcode,licence_title,updated_by)
      values('{RESOURCE}','2730','Creative Commons Attribution 3.0 Australia','{ACTOR}');""")

    for mode, marker, resume in [('mid_fetch', 'after_first_page', 'complete'),
                                  ('after_checkpoint', 'checkpoint_committed', 'resume_checkpoint')]:
        job = enqueue()
        name = worker(mode, detached=True)
        expect_marker(name, marker)
        before = state(job)
        assert before['status'] == 'running' and before['attempts'] == 1
        assert (before['checkpoint'] is not None) == (mode == 'after_checkpoint')
        assert before['run_id'] is None
        command(['docker', 'kill', '--signal=KILL', name])
        assert command(['docker', 'inspect', name, '--format', '{{.State.ExitCode}}']) == '137'
        assert worker('complete')['status'] == 'idle', 'A live lease must prevent replacement'
        # Advance only the disposable row's expiry; do not wait five real minutes.
        sql(f"update ingestion.acquisition_jobs set lease_until=now()-interval '1 second' where id='{job}';")
        result = worker(resume)
        after = state(job)
        assert result['status'] == 'complete' and after['attempts'] == 2
        assert sql(f"select count(*) from ingestion.ingestion_runs where run_key='acnc-job-{job}';") == '1'
        assert after['checkpoint']['counts']['accepted'] == 2
        if mode == 'after_checkpoint':
            assert after['checkpoint'] == before['checkpoint'], 'Checkpoint/observation changed'
        else:
            assert after['checkpoint']['qualification']['http_requests'] == 4
        sql(f"""do $$ begin
          begin perform ingestion.finish_acquisition('{job}','{before['lease_token']}');
          raise exception 'Old worker token accepted';
          exception when serialization_failure then null; end;
        end $$;""")
        record(mode, attempts=2, staged_runs=1, source_refetched=mode == 'mid_fetch')

    baseline_run = result['run_id']
    # Publish synthetic records with real RPCs, then make a protected human edit
    # and suppress a field / withdraw the other organisation.
    sql(f"""select set_config('request.jwt.claims','{{"sub":"{ACTOR}","aal":"aal2"}}',false);
      do $$ declare v record; fields jsonb; a uuid; org uuid; f jsonb; begin
       for v in select sv.id,sr.native_id from ingestion.run_records rr
        join ingestion.source_record_versions sv on sv.id=rr.version_id
        join ingestion.source_records sr on sr.id=sv.record_id where rr.run_id={baseline_run} loop
        perform community_orgs.save_ingestion_review('{baseline_run}',v.id::text,0,'create',null,'Recovery fixture');
        select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview('{baseline_run}',v.id::text)->'fields') x
         where x->>'field' in ('entity_name','website') and x->>'status'='new';
        a:=community_orgs.approve_ingestion_fields('{baseline_run}',v.id::text,1,fields);
        org:=community_orgs.publish_ingestion_fields(a);
        if v.native_id='1' then
         update community_orgs.organisations set entity_name='Protected human correction' where org_id=org;
         select x into f from jsonb_array_elements(community_orgs.ingestion_field_preview('{baseline_run}',v.id::text,org)->'fields') x where x->>'field'='website';
         perform community_orgs.suppress_ingestion_content('{baseline_run}',v.id::text,'website','Fixture withdrawal',jsonb_build_object('organisation_id',org,'field',f));
        else
         perform community_orgs.suppress_ingestion_content('{baseline_run}',v.id::text,'*','Fixture whole withdrawal',jsonb_build_object('organisation_id',org));
        end if;
       end loop;
      end $$;""")
    enqueue()
    refreshed = worker('changed')
    assert refreshed['status'] == 'complete'
    sql(f"""select set_config('request.jwt.claims','{{"sub":"{ACTOR}","aal":"aal2"}}',false);
      do $$ declare v record; fields jsonb; facts jsonb; begin
       for v in select sv.id,sr.native_id,l.organisation_id as org from ingestion.run_records rr
        join ingestion.source_record_versions sv on sv.id=rr.version_id
        join ingestion.source_records sr on sr.id=sv.record_id
        join ingestion.source_links l on l.record_id=sr.id where rr.run_id={refreshed['run_id']} loop
        fields:=community_orgs.ingestion_field_preview('{refreshed['run_id']}',v.id::text,v.org)->'fields';
        if v.native_id='1' then
         if not fields @> '[{{"field":"entity_name","status":"conflict","protected":true}},{{"field":"website","status":"suppressed"}}]' then raise exception 'Lost conflict/suppression'; end if;
         if (select entity_name from community_orgs.organisations where org_id=v.org)<>'Protected human correction' then raise exception 'Human correction overwritten'; end if;
        end if;
        set local role anon;
        facts:=community_orgs.organisation_register_facts(v.org);
        if v.native_id='1' and facts @> '[{{"field":"website"}}]' then raise exception 'Suppressed field leaked'; end if;
        if v.native_id='2' and (jsonb_array_length(facts)<>0 or exists(select 1 from community_orgs.organisations where org_id=v.org)) then raise exception 'Withdrawn organisation restored'; end if;
        reset role;
       end loop;
       if (select count(*) from ingestion.source_links l join ingestion.source_records s on s.id=l.record_id where s.resource_id='{RESOURCE}')<>2 then raise exception 'Identity links changed'; end if;
      end $$;""")
    record('protected_edit_and_withdrawal_after_changed_refresh', linked_organisations=2)

    for mode, accepted in [('failed', 0), ('partial', 1)]:
        before = snapshot()
        versions = set(sql('select id from ingestion.source_record_versions;').splitlines())
        enqueue()
        outcome = worker(mode)
        assert outcome['status'] == mode
        assert snapshot() == before, 'Incomplete acquisition altered public data'
        assert versions <= set(sql('select id from ingestion.source_record_versions;').splitlines()), 'Retained versions removed'
        counts = json.loads(sql(f"select envelope->'counts' from ingestion.ingestion_runs where id={outcome['run_id']};"))
        assert counts['accepted'] == accepted
        if mode == 'partial':
            sql(f"""select set_config('request.jwt.claims','{{"sub":"{ACTOR}","aal":"aal2"}}',false);
              do $$ declare ver text; fields jsonb; begin
               select version_id::text into ver from ingestion.run_records where run_id={outcome['run_id']};
               perform community_orgs.save_ingestion_review('{outcome['run_id']}',ver,0,'create',null,'Partial-source fixture');
               select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview('{outcome['run_id']}',ver)->'fields') x
                where x->>'field'='entity_name' and x->>'status'='new';
               if jsonb_array_length(fields) is distinct from 1 then raise exception 'Eligible fixture missing'; end if;
               begin perform community_orgs.approve_ingestion_fields('{outcome['run_id']}',ver,1,fields);
                raise exception 'Incomplete run approved';
               exception when invalid_parameter_value then
                if sqlerrm<>'Complete enabled source required' then raise exception 'Wrong rejection: %',sqlerrm; end if;
               end;
              end $$;""")
        assert sql(f"select count(*) from ingestion.change_sets where run_id={outcome['run_id']};") == '0'
        record(mode + '_source', accepted=accepted, public_state_unchanged=True)
    print(json.dumps({'result': 'pass', 'checks': checks, 'isolation': 'internal Docker network; synthetic HTTP only'}), flush=True)
finally:
    for name in reversed(containers):
        subprocess.run(['docker', 'rm', '-f', name], capture_output=True)
    subprocess.run(['docker', 'network', 'rm', NETWORK], capture_output=True)

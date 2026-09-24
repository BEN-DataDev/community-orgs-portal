"""Run portal access/governance regressions against real migrations in disposable PostGIS.

No host ports, mounts, credentials or external database URLs. Only auth users,
factors and JWT helpers are emulated; capability functions and RLS are unmodified.
Requires the locally available postgis/postgis:17-3.5 image. Removes its container.
"""
from pathlib import Path
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
NAME = 'portal-p07-' + uuid.uuid4().hex[:10]


def command(args, input=None):
    result = subprocess.run(args, input=input, text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(f'{args[:3]} failed:\n{result.stderr[-6000:]}\n{result.stdout[-1000:]}')
    return result.stdout


try:
    command(['docker', 'run', '--pull=never', '-d', '--name', NAME, '--network=none',
             '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgis/postgis:17-3.5'])
    for _ in range(100):
        result = subprocess.run(['docker', 'exec', NAME, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres'], capture_output=True)
        if result.returncode == 0:
            break
        time.sleep(0.2)
    else:
        raise RuntimeError('Disposable database did not start')
    # A fresh database avoids the image's preinstalled public-schema PostGIS.
    command(['docker', 'exec', NAME, 'createdb', '-U', 'postgres', '-T', 'template0', 'p07'])

    def sql(query):
        return command(['docker', 'exec', '-i', NAME, 'psql', '-U', 'postgres', '-d', 'p07',
                        '-X', '-q', '-v', 'ON_ERROR_STOP=1'], input=query)

    sql('''create role anon; create role authenticated; create role service_role;
      create schema auth; create schema extensions;
      create table auth.users(id uuid primary key, email text, email_confirmed_at timestamptz,
        is_anonymous boolean default false,
        created_at timestamptz, updated_at timestamptz);
      create table auth.mfa_factors(id uuid primary key default gen_random_uuid(),
        user_id uuid references auth.users, status text, factor_type text, created_at timestamptz, updated_at timestamptz);
      create function auth.jwt() returns jsonb language sql as $$
        select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
      create function auth.uid() returns uuid language sql as $$ select (auth.jwt()->>'sub')::uuid $$;
      grant usage on schema auth to anon,authenticated,service_role;
    ''')
    # Account storage, sessions, orphan public tables and hosted extensions are
    # unrelated to this boundary; do not substitute simplified organisation RLS.
    excluded = {
        '20260905031452_drop_unsupported_pgjwt_extension.sql',
        '20260905033816_enable_rls_on_orphan_public_tables.sql',
        '20260913033010_enable_pg_graphql_extension.sql',
        '20260914223810_persistent_account_avatars.sql',
        '20260915035236_account_session_management.sql',
    }
    migrations = [p for p in sorted((ROOT / 'supabase/migrations').glob('*.sql')) if p.name not in excluded]
    for path in migrations:
        if path.name == "20260918021340_deterministic_identity.sql":
            sql((ROOT / "scripts/identity-inventory.sql").read_text())
        sql(path.read_text())
    print(f'Applied {len(migrations)} unmodified portal/access/ingestion migrations.', flush=True)
    for name in ['p2_admin_access_regression.sql', 'platform_administrators.sql',
                 'portal_identity_lifecycle.sql',
                 'portal_scope_revisions.sql',
                 'portal_capabilities_and_stewardship.sql',
                 'organisation_invitations.sql',
                 'stewardship_administration_queue.sql',
                 'publication_releases.sql',
                 'campaign_orchestration.sql',
                 'operator_access.sql', 'organisation_role_management.sql', 'p1_access_regression.sql', 'ingestion_review.sql', 'ingestion_publication.sql', 'private_raw_retention.sql', 'deterministic_identity.sql', 'ingestion_change_report.sql', 'registry_seed_candidates.sql']:
        print(sql((ROOT / 'supabase/tests' / name).read_text()).strip(), flush=True)
        print(f'{name}: passed', flush=True)
        if name == 'portal_scope_revisions.sql':
            sql("""
              insert into portal.configuration(
                portal_id,portal_key,display_name,short_name,sponsor_name,establishment_reason
              ) values (
                '10000000-0000-4000-8000-000000000004','test-harness',
                'Test Harness Portal','Test Harness','Test Sponsor','Disposable suite scope'
              );
              with revision as (
                insert into portal.scope_revisions(
                  portal_id,revision,inclusion_policy_version,impact_assessment,
                  requires_rebaseline,reason
                ) values (
                  '10000000-0000-4000-8000-000000000004',1,'test-v1',
                  'Disposable test harness boundary',false,'Test harness setup'
                ) returning id
              ), postcode as (
                insert into portal.scope_postcodes(scope_revision_id,postcode)
                select id,'2730' from revision returning scope_revision_id
              )
              update portal.configuration set current_scope_revision_id=postcode.scope_revision_id
              from postcode where singleton;
            """)
    print(sql(command(['python3', str(ROOT / 'scripts/build-csv-test-sql.py')])).strip(), flush=True)
    print('Approved CSV integration: passed', flush=True)
    # P10: exercise all mapped fields and public visibility against the current
    # migration chain, using parser-generated fixtures in each suite's session.
    fixture_sql = command(['python3', '-c',
        'import runpy, sys; from pathlib import Path; '
        'p = Path(sys.argv[1]); sys.path.insert(0, str(p)); '
        'runpy.run_path(str(p / "tests/emit_complete_fixture.py")); '
        'runpy.run_path(str(p / "tests/emit_bulk_fixture.py")); '
        'runpy.run_path(str(p / "tests/emit_reprocessing_fixture.py"))',
        str(ROOT / 'tools/ingestion/python')])
    for name in ['ingestion_staging.sql', 'ingestion_field_preview.sql',
                 'ingestion_complete_fields.sql', 'acnc_register_details.sql',
                 'public_register_facts.sql', 'acnc_reprocessing.sql',
                 'acnc_website_normalisation.sql', 'acnc_bulk.sql']:
        # Public-page suites also emit large synthetic browser exports. Keep
        # successful output concise; command() retains diagnostics on failure.
        sql(fixture_sql + (ROOT / 'supabase/tests' / name).read_text())
        print(f'{name}: passed', flush=True)
    # P14: two operator transactions contend for the same exact key.
    sql("""
      insert into auth.users(id) values('00000000-0000-4000-8000-000000001490');
      insert into ingestion.operators(user_id) values('00000000-0000-4000-8000-000000001490');
      insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values
        ('00000000-0000-4000-8000-000000001491','Concurrent identity one','p14-race-one',false),
        ('00000000-0000-4000-8000-000000001492','Concurrent identity two','p14-race-two',false);
      set request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000001490","aal":"aal2"}';
      select community_orgs.review_entity_identity('00000000-0000-4000-8000-000000001491',1,'legal_entity','{"reference":"fixture"}');
      select community_orgs.review_entity_identity('00000000-0000-4000-8000-000000001492',1,'legal_entity','{"reference":"fixture"}');
    """)
    identity_prefix = """begin; set local role authenticated;
      set local request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000001490","aal":"aal2"}';
    """
    def claim(org, revision):
        return f"""select community_orgs.review_identifier_identity(
          '00000000-0000-4000-8000-{org}','abn','AU','51824753556',{revision},'verified',
          '{{"reference":"synthetic","authority":"fixture","holder_name":"fixture","qualified_registry_review":true,"observed_at":"2026-09-18T00:00:00Z"}}');"""
    contender = subprocess.Popen(['docker','exec','-i',NAME,'psql','-U','postgres','-d','p07',
        '-X','-q','-A','-t','-v','ON_ERROR_STOP=1'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True)
    try:
        contender.stdin.write(identity_prefix + claim('000000001491', 0) + "select pg_sleep(2); commit;")
        contender.stdin.close()
        if 'verified' not in contender.stdout.readline():
            raise RuntimeError('First identity contender failed')
        try:
            sql(identity_prefix + claim('000000001492', 0) + 'commit;')
        except RuntimeError as exc:
            if 'Identifier changed; reload' not in str(exc):
                raise
        else:
            raise RuntimeError('Both concurrent identifier holders accepted')
        contender.wait(timeout=15)
        if contender.returncode:
            raise RuntimeError(contender.stderr.read())
        conflict = sql(identity_prefix + claim('000000001492', 1) + 'commit;')
        if 'conflict' not in conflict or '000000001491' not in conflict:
            raise RuntimeError('Conflict retry did not retain original reservation')
        sql("""do $$ begin
          if (select count(*) from ingestion.identifier_keys where scheme='abn')<>1
            or (select state from ingestion.identifier_keys where scheme='abn')<>'disputed' then
            raise exception 'Concurrent reservation invariant failed'; end if;
        end $$;""")
        print('Concurrent identity claims: one holder; stale contender refused; reviewed retry retained as conflict.', flush=True)
    finally:
        if contender.poll() is None:
            contender.kill()
            contender.wait()

    # Two administrators race to revoke the two remaining owners. The second
    # transaction must see the committed first revocation after taking the lock.
    sql("""
      insert into auth.users(id) values
        ('00000000-0000-4000-8000-000000000901'),
        ('00000000-0000-4000-8000-000000000902'),
        ('00000000-0000-4000-8000-000000000903');
      insert into community_orgs.organisations(org_id,entity_name,slug,is_public)
        values('00000000-0000-4000-8000-000000000911','Concurrent owners','p08-concurrent',false);
      insert into platform_access.administrators(user_id,reason)
        values('00000000-0000-4000-8000-000000000903','P08 concurrency');
      insert into community_orgs.user_organisation_roles(user_id,organisation_id,role_id)
        select u.id,'00000000-0000-4000-8000-000000000911',r.id from auth.users u
        cross join community_orgs.roles r where r.name='owner' and u.id in
        ('00000000-0000-4000-8000-000000000901','00000000-0000-4000-8000-000000000902');
    """)
    prefix = """begin; set local role authenticated;
      set local request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000903","aal":"aal1"}';
    """
    def revoke(owner):
        return f"""do $$ begin perform community_orgs.revoke_user_role(
          '00000000-0000-4000-8000-{owner}', '00000000-0000-4000-8000-000000000911',
          (select id from community_orgs.roles where name='owner'),auth.uid()); end $$;"""
    first = subprocess.Popen(['docker','exec','-i',NAME,'psql','-U','postgres','-d','p07',
        '-X','-q','-A','-t','-v','ON_ERROR_STOP=1'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True)
    try:
        first.stdin.write(prefix + revoke('000000000901') + "select 'LOCKED'; select pg_sleep(2); commit;")
        first.stdin.close()
        if first.stdout.readline().strip() != 'LOCKED':
            raise RuntimeError('First revocation did not acquire lock')
        try:
            sql(prefix + revoke('000000000902') + 'commit;')
        except RuntimeError as exc:
            if 'grant another non-expiring owner' not in str(exc):
                raise
        else:
            raise RuntimeError('Concurrent revocations removed both owners')
        first.wait(timeout=15)
        if first.returncode:
            raise RuntimeError(first.stderr.read())
        print('Concurrent owner revocations: second transaction refused; one owner retained.', flush=True)
    finally:
        if first.poll() is None:
            first.kill()
            first.wait()

finally:
    subprocess.run(['docker', 'rm', '-f', NAME], capture_output=True)

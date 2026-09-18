"""Emit P12 integration checks using the real parser; rollback-only database verification."""
import argparse
import copy
import csv
import hashlib
import io
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/ingestion/python'))
from ingestion.approved_csv import extract, COLUMNS
from ingestion.staging_sql import expression

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--hosted', action='store_true', help='Management connection: inspect worker grants without SET ROLE ingestion_worker')
args = parser.parse_args()

fixture = ROOT / 'tools/ingestion/python/tests/fixtures/csv-pilot-v1'
m = json.loads((fixture / 'manifest.json').read_text())
e = extract((fixture / 'organisations.csv').read_bytes(), m)
# Simulate a qualified provider inside the rolled-back test transaction only.
rows = list(csv.reader(io.StringIO((fixture / 'organisations.csv').read_text())))[1:3]
out = io.StringIO(newline='')
w = csv.writer(out)
w.writerow(COLUMNS)
w.writerows(rows)
data = out.getvalue().encode()
approved = copy.deepcopy(m)
approved.update(synthetic=False, access_status='approved', approved_by='Disposable test',
                approved_at=m['observed_at'], access_evidence_ref='test:only', row_count=2)
approved['files']['organisations.csv'] = hashlib.sha256(data).hexdigest()
clean = extract(data, approved)
print('begin;')
print("insert into ingestion.sources values ('synthetic-community-csv','csv-pilot-v1'," + expression({'csv_qualification': m}) + ',true);')
print("insert into auth.users(id,email,created_at,updated_at) values ('00000000-0000-4000-8000-000000000881','p12-verification@example.invalid',now(),now());")
print("insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000881');")
test_sql = 'do $$ declare e jsonb := ' + expression(e) + '; clean jsonb := ' + expression(clean) + ''';
 r bigint; v text; fields jsonb; approval uuid; org uuid; n bigint; versions bigint;
begin
 select count(*) into n from community_orgs.organisations;
 if not has_function_privilege('ingestion_worker','ingestion.stage_csv(jsonb)','EXECUTE')
 or has_function_privilege('authenticated','ingestion.stage_csv(jsonb)','EXECUTE')
 or has_function_privilege('ingestion_worker','ingestion.stage_csv_records(jsonb)','EXECUTE')
 or has_function_privilege('anon','ingestion.stage_csv(jsonb)','EXECUTE') then
 raise exception 'CSV grants too broad'; end if;
 set local role ingestion_worker;
 r := ingestion.stage_csv(e);
 if ingestion.stage_csv(e)<>r then raise exception 'Replay duplicated run'; end if;
 reset role;
 if (select count(*) from ingestion.run_records where run_id=r)<>6 then raise exception 'Wrong accepted count'; end if;
 if (select jsonb_array_length(envelope->'quarantine') from ingestion.ingestion_runs where id=r)<>3 then raise exception 'Quarantine lost'; end if;
 select count(*) into versions from ingestion.source_record_versions;
 e:=jsonb_set(e,'{run_id}','"second-observation"');
 e:=jsonb_set(e,'{records}',(select jsonb_agg(jsonb_set(x,'{run_id}','"second-observation"')) from jsonb_array_elements(e->'records') x));
 perform ingestion.stage_csv(e);
 if (select count(*) from ingestion.source_record_versions)<>versions then raise exception 'Replay duplicated versions'; end if;
 if (select count(*) from community_orgs.organisations)<>n then raise exception 'Staging published'; end if;
 select rr.version_id::text into v from ingestion.run_records rr
 join ingestion.source_record_versions sv on sv.id=rr.version_id
 join ingestion.source_records sr on sr.id=sv.record_id
 where rr.run_id=r and sr.native_id='csv-001';
 set local role authenticated;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000881","aal":"aal2"}',true);
 perform community_orgs.save_ingestion_review(r::text,v,0,'create',null,'Fixture review');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r::text,v)->'fields') x where x->>'field'='entity_name';
 begin perform community_orgs.approve_ingestion_fields(r::text,v,1,fields);
 raise exception 'Partial fixture approved'; exception when invalid_parameter_value then null; end;
 reset role;
 begin perform ingestion.stage_csv(clean); raise exception 'Unqualified file accepted';
 exception when raise_exception then if sqlerrm='Unqualified file accepted' then raise; end if; end;
 update ingestion.sources set metadata=jsonb_build_object('csv_qualification',clean->'qualification')
 where source_id='synthetic-community-csv';
 r:=ingestion.stage_csv(clean);
 if ingestion.stage_csv(clean)<>r then raise exception 'Clean replay duplicated run'; end if;
 begin perform ingestion.stage_csv(jsonb_set(clean,'{scope,kind}','"tampered"'));
 raise exception 'Mismatched scope accepted';
 exception when raise_exception then if sqlerrm='Mismatched scope accepted' then raise; end if; end;
 update ingestion.sources set enabled=false where source_id='synthetic-community-csv';
 begin perform ingestion.stage_csv(clean); raise exception 'Disabled source accepted';
 exception when raise_exception then if sqlerrm='Disabled source accepted' then raise; end if; end;
 update ingestion.sources set enabled=true where source_id='synthetic-community-csv';
 select rr.version_id::text into v from ingestion.run_records rr
 join ingestion.source_record_versions sv on sv.id=rr.version_id
 join ingestion.source_records sr on sr.id=sv.record_id
 where rr.run_id=r and sr.native_id='csv-002';
 set local role authenticated;
 perform community_orgs.save_ingestion_review(r::text,v,0,'create',null,'Verified distinct identity and pilot scope');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r::text,v)->'fields') x where x->>'field' in ('entity_name','abn','website');
 approval:=community_orgs.approve_ingestion_fields(r::text,v,1,fields);
 reset role;
 if (select count(*) from community_orgs.organisations)<>n then raise exception 'Approval published'; end if;
 set local role authenticated;
 org:=community_orgs.publish_ingestion_fields(approval);
 if community_orgs.publish_ingestion_fields(approval)<>org then raise exception 'Publication replay failed'; end if;
 reset role;
 if (select count(*) from community_orgs.organisations)<>n+1 then raise exception 'Publication duplicated'; end if;
 if exists(select 1 from community_orgs.user_organisation_roles where organisation_id=org) then raise exception 'Importer gained ownership'; end if;
 if (select website from community_orgs.contact_info where org_id=org)<>'https://example.org/arts' then raise exception 'Website not published'; end if;
 -- P09 expiry replay does not restore removed evidence; changed content is refused.
 update ingestion.ingestion_runs set raw_removed_at=now(),envelope='{}' where id=r;
 if ingestion.stage_csv(clean)<>r then raise exception 'Expired replay failed'; end if;
 begin perform ingestion.stage_csv(jsonb_set(clean,'{counts,accepted}','999'));
 raise exception 'Mutated replay accepted';
 exception when raise_exception then if sqlerrm='Mutated replay accepted' then raise; end if; end;
 raise notice 'CSV qualification, quarantine, private grants, replay, review, publication and expiry passed';
end $$;
rollback;
'''
if args.hosted:
    test_sql = test_sql.replace(' set local role ingestion_worker;\n', '')
print(test_sql)

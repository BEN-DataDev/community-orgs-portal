-- Run as postgres after staging/review migrations. Synthetic fixtures roll back.
begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000001');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000001');
insert into community_orgs.organisations(org_id,entity_name,slug) values
 ('00000000-0000-4000-8000-000000000011','Review fixture','review-fixture'),
 ('00000000-0000-4000-8000-000000000012','Review branch','review-branch');
insert into community_orgs.legal_details(org_id,abn) values
 ('00000000-0000-4000-8000-000000000011','00000000000'),
 ('00000000-0000-4000-8000-000000000012','00000000000');
insert into ingestion.sources values ('acnc-register','review-fixture','{}',true);
do $$
declare
 e jsonb := '{"contract_version":"1.0","source_id":"acnc-register","resource_id":"review-fixture","run_id":"review-one","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","completion":"partial","publication_eligible":false,"scope":{},"quarantine":[],"errors":[],"records":[{"source_id":"acnc-register","resource_id":"review-fixture","run_id":"review-one","native_id":"1","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","raw":{},"assertions":[{"field":"entity_name","value":"Review fixture"},{"field":"abn","value":"00000000000"}]}]}';
 r text; v text; q jsonb; initial_count bigint;
begin
 select count(*) into initial_count from community_orgs.organisations;
 if has_table_privilege('authenticated','ingestion.reviews','INSERT') or
 has_table_privilege('authenticated','ingestion.operators','INSERT') or
 has_function_privilege('anon','community_orgs.ingestion_review_queue(text,text,integer,text)','EXECUTE') then raise exception 'Unexpected grant'; end if;
 r := ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 set local role authenticated;
 perform set_config('request.jwt.claims','{}',true);
 begin perform community_orgs.ingestion_review_queue(); raise exception 'Expected denial'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002"}',true);
 begin perform community_orgs.save_ingestion_review(r,v,0,'defer',null,'Denied'); raise exception 'Expected denial'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","is_anonymous":true}',true);
 begin perform community_orgs.ingestion_review_queue(); raise exception 'Expected guest denial'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
 q := community_orgs.ingestion_review_queue(r,v);
 if jsonb_array_length(q->'candidates')<>2 or q->'records'->0->>'decision'<>'pending' then raise exception 'Shared ABN candidates/pending status missing'; end if;
 perform community_orgs.save_ingestion_review(r,v,0,'link','00000000-0000-4000-8000-000000000011','Verified scope');
 begin perform community_orgs.save_ingestion_review(r,v,0,'reject',null,'Stale'); raise exception 'Expected stale denial'; exception when serialization_failure then null; end;
 begin perform community_orgs.save_ingestion_review('999999999',v,1,'reject',null,'Wrong run'); raise exception 'Expected run denial'; exception when no_data_found then null; end;
 begin perform community_orgs.save_ingestion_review(r,v,1,'link',null,'No organisation'); raise exception 'Expected input denial'; exception when invalid_parameter_value then null; end;
 perform community_orgs.save_ingestion_review(r,v,1,'defer',null,'Investigate branch');
 q := community_orgs.ingestion_review_queue(r,v);
 if q->'detail'->'review'->>'revision'<>'2' then raise exception 'Revision not updated'; end if;
 reset role;
 if (select count(*) from ingestion.review_events where version_id=v::bigint)<>2 then raise exception 'Audit missing'; end if;
 if (select count(*) from community_orgs.organisations)<>initial_count then raise exception 'Review published data'; end if;
 delete from ingestion.operators where user_id='00000000-0000-4000-8000-000000000001';
 set local role authenticated;
 begin perform community_orgs.ingestion_review_queue(r,v); raise exception 'Revoked operator retained access'; exception when insufficient_privilege then null; end;
 reset role;
 raise notice 'Operator denial, shared ABNs, run scope, revisions, history and no publication passed';
end $$;
rollback;

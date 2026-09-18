begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000079');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000079');
insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values
 ('00000000-0000-4000-8000-000000000078','Existing human name','publication-fixture',false);
insert into ingestion.sources values ('acnc-register','publication-fixture','{}',true);
do $$
declare
 target uuid := '00000000-0000-4000-8000-000000000078';
 e jsonb := '{"contract_version":"1.0","source_id":"acnc-register","resource_id":"publication-fixture","run_id":"one","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{},"quarantine":[],"errors":[],"records":[{"source_id":"acnc-register","resource_id":"publication-fixture","run_id":"one","native_id":"1","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","raw":{},"assertions":[{"field":"entity_name","value":"Source name"},{"field":"website","value":"https://source.example"},{"field":"abn","value":"00000000000"}]}]}';
 r text; v text; fields jsonb; approval uuid; stale uuid; created uuid; before_count bigint;
begin
 r := ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 set local role authenticated;
 perform set_config('request.jwt.claims','{}',true);
 begin perform community_orgs.publish_ingestion_fields(gen_random_uuid()); raise exception 'Expected operator denial'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000079","aal":"aal2"}',true);
 perform community_orgs.save_ingestion_review(r,v,0,'link',target,'Verified entity scope');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v,target)->'fields') x where x->>'field'='entity_name';
 begin perform community_orgs.approve_ingestion_fields(r,v,1,fields,target); raise exception 'Protected approval accepted'; exception when serialization_failure then null; end;
 select jsonb_agg(x order by x->>'field') into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v,target)->'fields') x where x->>'field' in ('abn','website');
 begin perform community_orgs.approve_ingestion_fields(r,v,1,fields,null); raise exception 'Wrong target accepted'; exception when serialization_failure then null; end;
 approval := community_orgs.approve_ingestion_fields(r,v,1,fields,target);
 reset role;
 -- Failure on the second field must roll back the first field and all bookkeeping.
 alter table community_orgs.contact_info add constraint publication_test_failure check(website <> 'https://source.example');
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Expected write failure'; exception when check_violation then null; end;
 if exists(select 1 from community_orgs.legal_details where org_id=target) or exists(select 1 from ingestion.publications where change_set_id=approval) then raise exception 'Partial publication leaked'; end if;
 alter table community_orgs.contact_info drop constraint publication_test_failure;
 set local role authenticated;
 if community_orgs.publish_ingestion_fields(approval)<>target then raise exception 'Wrong publication target'; end if;
 reset role;
 if (select is_public from community_orgs.organisations where org_id=target) then raise exception 'Visibility changed'; end if;
 if (select entity_name from community_orgs.organisations where org_id=target)<>'Existing human name' then raise exception 'Unselected field overwritten'; end if;
 update community_orgs.contact_info set website='https://human.example' where org_id=target;
 perform community_orgs.publish_ingestion_fields(approval);
 if (select website from community_orgs.contact_info where org_id=target)<>'https://human.example' then raise exception 'Replay overwrote human correction'; end if;
 if (select count(*) from ingestion.publications where change_set_id=approval)<>1 then raise exception 'Replay duplicated event'; end if;
 -- A later human edit invalidates an approval, including a manual clear.
 insert into community_orgs.organisations(org_id,entity_name,slug,is_public)
 values('00000000-0000-4000-8000-000000000077','Another target','another-publication-fixture',false);
 -- P14 now refuses source retargeting at review, before approval/publication.
 if to_regprocedure('ingestion.match_identity(bigint)') is not null then
  begin perform community_orgs.save_ingestion_review(r,v,1,'link','00000000-0000-4000-8000-000000000077','Wrong target');
   raise exception 'Source link retarget accepted'; exception when serialization_failure then null; end;
 end if;
 -- Use an independent source to isolate the manual-clear stale-field case.
 e := jsonb_set(jsonb_set(jsonb_set(e,'{run_id}','"manual-clear"'),'{records,0,run_id}','"manual-clear"'),'{records,0,native_id}','"manual-clear"');
 r := ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 perform community_orgs.save_ingestion_review(r,v,0,'link','00000000-0000-4000-8000-000000000077','Rechecked target');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v,'00000000-0000-4000-8000-000000000077')->'fields') x where x->>'field'='website';
 stale := community_orgs.approve_ingestion_fields(r,v,1,fields,'00000000-0000-4000-8000-000000000077');
 insert into community_orgs.contact_info(org_id,website) values('00000000-0000-4000-8000-000000000077','https://manual.example');
 update community_orgs.contact_info set website=null where org_id='00000000-0000-4000-8000-000000000077';
 begin perform community_orgs.publish_ingestion_fields(stale); raise exception 'Stale field accepted'; exception when serialization_failure then null; end;
 -- New source identity, create review and two approvals of the same immutable source.
 e := jsonb_set(jsonb_set(jsonb_set(e,'{run_id}','"two"'),'{records,0,run_id}','"two"'),'{records,0,native_id}','"2"');
 r := ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 perform community_orgs.save_ingestion_review(r,v,0,'create',null,'New distinct group');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v)->'fields') x where x->>'status' in ('new','changed');
 approval := community_orgs.approve_ingestion_fields(r,v,1,fields);
 stale := community_orgs.approve_ingestion_fields(r,v,1,fields);
 select count(*) into before_count from community_orgs.organisations;
 update ingestion.sources set enabled=false where resource_id='publication-fixture';
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Disabled source published'; exception when invalid_parameter_value then null; end;
 update ingestion.sources set enabled=true where resource_id='publication-fixture';
 created := community_orgs.publish_ingestion_fields(approval);
 if (select count(*) from community_orgs.organisations)<>before_count+1 or not (select is_public from community_orgs.organisations where org_id=created) then raise exception 'New public organisation missing'; end if;
 if exists(select 1 from community_orgs.user_organisation_roles where organisation_id=created) then raise exception 'Import granted ownership'; end if;
 insert into community_orgs.organisations(org_id,entity_name,slug) values('00000000-0000-4000-8000-000000000076','Normal creation','normal-publication-fixture');
 if not exists(select 1 from community_orgs.user_organisation_roles where organisation_id='00000000-0000-4000-8000-000000000076' and user_id=auth.uid()) then raise exception 'Normal owner grant broken'; end if;
 begin perform community_orgs.publish_ingestion_fields(stale); raise exception 'Duplicate creation accepted'; exception when serialization_failure then null; end;
 -- An approval becomes stale after a review revision changes, even if target stays the same.
 e := jsonb_set(jsonb_set(jsonb_set(e,'{run_id}','"three"'),'{records,0,run_id}','"three"'),'{records,0,native_id}','"3"');
 r := ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 perform community_orgs.save_ingestion_review(r,v,0,'create',null,'Initial review');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v)->'fields') x where x->>'status' in ('new','changed');
 approval := community_orgs.approve_ingestion_fields(r,v,1,fields);
 perform community_orgs.save_ingestion_review(r,v,1,'reject',null,'Reconsidered');
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Stale review accepted'; exception when serialization_failure then null; end;
 e := jsonb_set(jsonb_set(jsonb_set(jsonb_set(e,'{run_id}','"partial"'),'{records,0,run_id}','"partial"'),'{records,0,native_id}','"4"'),'{completion}','"partial"');
 r := ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 perform community_orgs.save_ingestion_review(r,v,0,'create',null,'Partial run evidence');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v)->'fields') x where x->>'status' in ('new','changed');
 begin perform community_orgs.approve_ingestion_fields(r,v,1,fields); raise exception 'Partial run approved'; exception when invalid_parameter_value then null; end;
 if has_table_privilege('authenticated','ingestion.change_sets','UPDATE') or has_function_privilege('anon','community_orgs.publish_ingestion_fields(uuid)','EXECUTE') then raise exception 'Unexpected grants'; end if;
 raise notice 'Publication access, protected fields, target mismatch, atomic rollback, visibility, replay, source identity and stale reviews passed';
end $$;
rollback;

-- Rollback-only P29/P30 guarded rollback and second-cycle checks.
begin;
set local lock_timeout='3s';
set local statement_timeout='20s';
insert into auth.users(id) values ('00000000-0000-4000-8000-000000002930');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000002930');
insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values
 ('00000000-0000-4000-8000-000000002931','Existing P29 name','p29-existing',true);
insert into ingestion.sources(source_id,resource_id,metadata,enabled)
 values('acnc-register','p29-second-cycle','{"synthetic":true}',true);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000002930","aal":"aal2"}',true);

do $$
declare
 org uuid := '00000000-0000-4000-8000-000000002931'::uuid;
 e jsonb := '{"contract_version":"1.0","source_id":"acnc-register","resource_id":"p29-second-cycle","run_id":"one","parser_version":"v1","observed_at":"2026-09-20T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{},"quarantine":[],"errors":[],"records":[{"source_id":"acnc-register","resource_id":"p29-second-cycle","run_id":"one","native_id":"1","parser_version":"v1","observed_at":"2026-09-20T00:00:00Z","raw":{"_id":"1"},"assertions":[{"field":"entity_name","value":"Source P29 name"},{"field":"website","value":"https://one.example"},{"field":"abn","value":"11111111111"}]}]}';
 r1 text; v1 text; r2 text; v2 text; r3 text; v3 text; failed_run text; withdrawn_run text; withdrawn_ver text;
 fields jsonb; first_approval uuid; second_approval uuid; rollback_result jsonb; queue jsonb; snapshot jsonb;
begin
 r1:=ingestion.stage_acnc(e)::text;
 select version_id::text into v1 from ingestion.run_records where run_id=r1::bigint;
 set local role authenticated;
 perform community_orgs.save_ingestion_review(r1,v1,0,'link',org,'Verified existing target');
 select jsonb_agg(x order by x->>'field') into fields
 from jsonb_array_elements(community_orgs.ingestion_field_preview(r1,v1,org)->'fields') x
 where x->>'field' in ('abn','website');
 first_approval:=community_orgs.approve_ingestion_fields(r1,v1,1,fields,org);
 perform community_orgs.publish_ingestion_fields(first_approval);
 if (select abn from community_orgs.legal_details where org_id=org)<>'11111111111'
  or (select website from community_orgs.contact_info where org_id=org)<>'https://one.example' then
  raise exception 'Initial import did not publish selected fields';
 end if;

 -- Unchanged replay in the second cycle creates no eligible field changes.
 reset role;
 e:=jsonb_set(jsonb_set(e,'{run_id}','"two"'),'{records,0,run_id}','"two"');
 r2:=ingestion.stage_acnc(e)::text;
 select version_id::text into v2 from ingestion.run_records where run_id=r2::bigint;
 set local role authenticated;
 if v2 is distinct from v1 then raise exception 'Unchanged replay did not reuse source version'; end if;
 if exists(select 1 from jsonb_array_elements(community_orgs.ingestion_field_preview(r2,v2,org)->'fields') x
  where x->>'field' in ('abn','website') and x->>'status'<>'unchanged') then
  raise exception 'Unchanged replay produced a field change';
 end if;

 -- A legitimate source change is reviewable and publishable.
 reset role;
 e:=jsonb_set(jsonb_set(e,'{run_id}','"three"'),'{records,0,run_id}','"three"');
 e:=jsonb_set(e,'{records,0,assertions,1,value}','"https://two.example"');
 r3:=ingestion.stage_acnc(e)::text;
 select version_id::text into v3 from ingestion.run_records where run_id=r3::bigint;
 set local role authenticated;
 perform community_orgs.save_ingestion_review(r3,v3,0,'link',org,'Legitimate website change');
 select jsonb_agg(x) into fields
 from jsonb_array_elements(community_orgs.ingestion_field_preview(r3,v3,org)->'fields') x
 where x->>'field'='website';
 second_approval:=community_orgs.approve_ingestion_fields(r3,v3,1,fields,org);
 perform community_orgs.publish_ingestion_fields(second_approval);
 if (select website from community_orgs.contact_info where org_id=org)<>'https://two.example' then
  raise exception 'Legitimate source change was not published';
 end if;

 -- Later human edit creates a rollback conflict; untouched ABN rolls back.
 update community_orgs.contact_info set website='https://human.example' where org_id=org;
 rollback_result:=community_orgs.rollback_ingestion_publication(first_approval,'Bad upstream ABN import; keep later manual website');
 if rollback_result->>'status'<>'partial_conflict'
  or rollback_result->>'reversed'<>'1' or rollback_result->>'conflicts'<>'1' then
  raise exception 'Unexpected rollback result: %',rollback_result;
 end if;
 if (select abn from community_orgs.legal_details where org_id=org) is not null then
  raise exception 'Clean ABN import was not reversed';
 end if;
 if (select website from community_orgs.contact_info where org_id=org)<>'https://human.example' then
  raise exception 'Rollback overwrote later human website';
 end if;
 queue:=community_orgs.ingestion_rollback_queue(first_approval);
 if not queue @> '[{"field":"website","action":"conflict"}]'::jsonb then
  raise exception 'Manual conflict was not queued: %',queue;
 end if;

 -- Source failure cannot create a publishable second-cycle change.
 reset role;
 e:=jsonb_set(jsonb_set(e,'{run_id}','"failed"'),'{completion}','"failed"');
 e:=jsonb_set(e,'{records}','[]');
 e:=jsonb_set(e,'{errors}','[{"code":"upstream_failed","message":"Synthetic outage"}]');
 failed_run:=ingestion.stage_acnc(e)::text;
 if exists(select 1 from ingestion.run_records where run_id=failed_run::bigint) then
  raise exception 'Failed source run unexpectedly staged records';
 end if;

 -- Withdrawal removes public visibility and blocks a later replay from restoring it.
 set local role authenticated;
 select x into snapshot from jsonb_array_elements(community_orgs.ingestion_field_preview(r3,v3,org)->'fields') x
 where x->>'field'='website';
 perform community_orgs.suppress_ingestion_content(r3,v3,'*','Second-cycle withdrawal notice',jsonb_build_object('organisation_id',org,'field',snapshot));
 if (select is_public from community_orgs.organisations where org_id=org) then
  raise exception 'Withdrawal did not hide organisation';
 end if;
 reset role;
 e:=jsonb_set(jsonb_set(e,'{run_id}','"withdrawn-replay"'),'{completion}','"complete"');
 e:=jsonb_set(e,'{errors}','[]');
 e:=jsonb_set(e,'{records}',jsonb_build_array(jsonb_build_object(
  'source_id','acnc-register','resource_id','p29-second-cycle','run_id','withdrawn-replay',
  'native_id','1','parser_version','v1','observed_at','2026-09-20T00:00:00Z','raw',jsonb_build_object('_id','1'),
  'assertions',jsonb_build_array(jsonb_build_object('field','website','value','https://restore.example')))));
 withdrawn_run:=ingestion.stage_acnc(e)::text;
 select version_id::text into withdrawn_ver from ingestion.run_records where run_id=withdrawn_run::bigint;
 set local role authenticated;
 if not community_orgs.ingestion_field_preview(withdrawn_run,withdrawn_ver,org)->'fields'
  @> '[{"field":"website","status":"suppressed"}]'::jsonb then
  raise exception 'Withdrawal replay was not suppressed';
 end if;

 reset role;
 if has_function_privilege('anon','community_orgs.rollback_ingestion_publication(uuid,text)','execute')
  or has_function_privilege('ingestion_worker','community_orgs.rollback_ingestion_publication(uuid,text)','execute')
  or has_table_privilege('authenticated','ingestion.rollback_events','select') then
  raise exception 'Unexpected rollback grants';
 end if;
 perform set_config('test.p29_p30_result',
  'Guarded rollback reversed unchanged import fields, queued manual conflicts, and second-cycle replay/change/failure/withdrawal checks passed',true);
end $$;
select current_setting('test.p29_p30_result') as result;
rollback;

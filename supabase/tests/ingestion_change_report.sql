begin;
insert into auth.users(id,email,created_at,updated_at) values ('00000000-0000-4000-8000-000000001501','p15-sql-fixture@example.invalid',now(),now());
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000001501');
insert into community_orgs.organisations(org_id,entity_name,slug) values
 ('00000000-0000-4000-8000-000000001511','Same','p15-same'),
 ('00000000-0000-4000-8000-000000001512','Protected','p15-protected'),
 ('00000000-0000-4000-8000-000000001513','Old name','p15-changed');
-- Synthetic importer-owned state allows a changed value without a manual conflict.
update ingestion.field_state set protected=false where org_id='00000000-0000-4000-8000-000000001513';
insert into ingestion.sources values ('acnc-register','p15','{}',true);
do $$
declare e jsonb; old_run text; new_run text; partial_run text; q jsonb; v text; before_count bigint; fields jsonb; approval uuid;
begin
 e:='{"contract_version":"1.0","source_id":"acnc-register","resource_id":"p15","run_id":"p15-old","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{"postcode":"2100","complete_snapshot":false},"quarantine":[],"errors":[],"records":[]}';
 e:=jsonb_set(e,'{records}',(select jsonb_agg(jsonb_build_object('source_id','acnc-register','resource_id','p15',
  'run_id','p15-old','native_id',n,'parser_version','v1','observed_at','2026-09-16T00:00:00Z','raw','{}'::jsonb,
  'assertions',jsonb_build_array(jsonb_build_object('field','entity_name','value',case n when 'same' then 'Same' else 'Incoming' end))))
  from unnest(array['same','conflict','missing','reject','new','changed','hold']) n));
 e:=jsonb_set(e,'{records}',(select jsonb_agg(case when x->>'native_id'='hold' then
  jsonb_set(x,'{assertions}',x->'assertions' || '[{"field":"csv_entity_kind","value":"branch"}]') else x end)
  from jsonb_array_elements(e->'records') x));
 old_run:=ingestion.stage_acnc(e)::text;
 insert into ingestion.source_links(record_id,organisation_id)
 select id,case native_id when 'same' then '00000000-0000-4000-8000-000000001511'::uuid when 'changed' then '00000000-0000-4000-8000-000000001513'::uuid else '00000000-0000-4000-8000-000000001512'::uuid end
 from ingestion.source_records where resource_id='p15' and native_id in ('same','conflict','changed');
 e:=jsonb_set(e,'{run_id}','"p15-new"');
 e:=jsonb_set(e,'{observed_at}','"2026-09-17T00:00:00Z"');
 e:=jsonb_set(e,'{records}',(select jsonb_agg(x || '{"run_id":"p15-new","observed_at":"2026-09-17T00:00:00Z"}') from jsonb_array_elements(e->'records') x where x->>'native_id'<>'missing'));
 new_run:=ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records rr join ingestion.source_record_versions sv on sv.id=rr.version_id
 join ingestion.source_records sr on sr.id=sv.record_id where rr.run_id=new_run::bigint and sr.native_id='reject';
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000001501","aal":"aal2"}',true);
 perform community_orgs.save_ingestion_review(new_run,v,0,'reject',null,'Not in scope');
 select count(*) into before_count from community_orgs.organisations;
 set local role authenticated;
 q:=community_orgs.ingestion_change_report(new_run,old_run);
 if q->'counts' <> '{"new":1,"unchanged":1,"changed":1,"conflicting":2,"rejected":1,"missing":1}'::jsonb then raise exception 'Wrong report counts: %',q->'counts'; end if;
 if q is distinct from community_orgs.ingestion_change_report(new_run,old_run) then raise exception 'Report not deterministic'; end if;
 if not exists(select 1 from jsonb_array_elements(q->'records') x where x->>'native_id'='same' and x->'prior_observation'->>'run_id'=old_run
  and exists(select 1 from jsonb_array_elements(x->'fields') f where f->>'field'='entity_name' and f->'prior_source'->>'value'='Same' and f->>'revision'<>'0')) then raise exception 'Prior source/revision absent'; end if;
 if (community_orgs.ingestion_change_report(new_run)->'missing_assessment'->>'assessed')::boolean then raise exception 'Implicit baseline'; end if;
 begin perform community_orgs.ingestion_change_report(old_run,new_run); raise exception 'Future baseline accepted'; exception when invalid_parameter_value then null; end;
 if not exists(select 1 from jsonb_array_elements(q->'records') x where x->>'native_id'='hold'
  and x->'identity_match'->>'status'='hold' and x->>'status'='conflicting') then raise exception 'Identity hold lost'; end if;
 if not exists(select 1 from jsonb_array_elements(q->'records') x, jsonb_array_elements(x->'fields') f
  where x->>'native_id'='same' and f->>'field'='website' and f->>'status'='missing' and f->>'source_value' is null) then raise exception 'Missing field became a deletion'; end if;
 perform set_config('request.jwt.claims','{}',true);
 begin perform community_orgs.ingestion_change_report(new_run); raise exception 'No operator check'; exception when insufficient_privilege then null; end;
 reset role;
 e:=jsonb_set(e,'{run_id}','"p15-partial"');
 e:=jsonb_set(e,'{completion}','"partial"');
 e:=jsonb_set(e,'{observed_at}','"2026-09-18T00:00:00Z"');
 e:=jsonb_set(e,'{records}','[]');
 e:=jsonb_set(e,'{quarantine}','[{"native_id":"same","reason":"invalid fixture","raw":{"example":true}}]');
 partial_run:=ingestion.stage_acnc(e)::text;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000001501","aal":"aal2"}',true);
 q:=community_orgs.ingestion_change_report(partial_run,old_run);
 if q->'counts'->>'missing'<>'0' or q->'counts'->>'rejected'<>'1' or q->'missing_assessment'->>'assessed'<>'false' then raise exception 'Partial/quarantine classification failed'; end if;
 update ingestion.ingestion_runs set envelope=jsonb_set(envelope,'{scope}','{"postcode":"9999"}') where id=partial_run::bigint;
 begin perform community_orgs.ingestion_change_report(partial_run,old_run); raise exception 'Different scope accepted'; exception when invalid_parameter_value then null; end;
 update ingestion.ingestion_runs set raw_removed_at=now() where id=new_run::bigint;
 if community_orgs.ingestion_change_report(new_run,old_run)->'missing_assessment'->>'assessed'<>'false' then raise exception 'Purged run assessed'; end if;
 if (select count(*) from community_orgs.organisations)<>before_count or exists(select 1 from ingestion.change_sets where run_id in (old_run::bigint,new_run::bigint)) then raise exception 'Report wrote public changes/approval'; end if;
 if has_function_privilege('anon','community_orgs.ingestion_change_report(text,text)','EXECUTE')
  or has_function_privilege('ingestion_worker','community_orgs.ingestion_change_report(text,text)','EXECUTE') then raise exception 'Unexpected grants'; end if;
 -- Real approval/publication writes retain exact changes and approved revisions in the report.
 update ingestion.ingestion_runs set raw_removed_at=null where id=new_run::bigint;
 select version_id::text into v from ingestion.run_records rr join ingestion.source_record_versions sv on sv.id=rr.version_id
 join ingestion.source_records sr on sr.id=sv.record_id where rr.run_id=new_run::bigint and sr.native_id='changed';
 perform community_orgs.save_ingestion_review(new_run,v,0,'link','00000000-0000-4000-8000-000000001513','P15 fixture');
 select jsonb_agg(f) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(new_run,v,'00000000-0000-4000-8000-000000001513')->'fields') f where f->>'field'='entity_name';
 approval:=community_orgs.approve_ingestion_fields(new_run,v,1,fields,'00000000-0000-4000-8000-000000001513');
 perform community_orgs.publish_ingestion_fields(approval);
 q:=community_orgs.ingestion_change_report(new_run,old_run);
 if not exists(select 1 from jsonb_array_elements(q->'records') x, jsonb_array_elements(x->'fields') f
  where x->>'native_id'='changed' and x->>'status'='unchanged' and f->>'field'='entity_name'
  and f->'publication_history'->0->>'change_set_id'=approval::text
  and f->'publication_history'->0->>'approved_revision'=fields->0->>'revision') then raise exception 'Publication history/replay absent'; end if;
 raise notice 'P15 report classifications, evidence, deterministic reads, absence guards and authorization passed';
end $$;
rollback;

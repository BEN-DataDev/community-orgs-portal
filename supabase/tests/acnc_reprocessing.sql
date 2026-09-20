-- Synthetic, rollback-only. The real Python replay is supplied by the test builder.
begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000f05');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000f05');
insert into ingestion.sources values ('acnc-register','f05-synthetic','{"synthetic":true}',true,0);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000f05","aal":"aal2"}',true);
do $$
declare parent bigint; replay bigint; ver text; newver text; e jsonb:=current_setting('test.f05_replay')::jsonb;
 original jsonb:=current_setting('test.f05_parent')::jsonb; bad jsonb; approval uuid; stale uuid;
 org uuid; rec bigint; fields jsonb; f jsonb; report jsonb; snapshot jsonb;
begin
 parent:=ingestion.stage_acnc(original);
 select version_id::text into ver from ingestion.run_records where run_id=parent;
 select record_id into rec from ingestion.source_record_versions where id=ver::bigint;
 perform community_orgs.save_ingestion_review(parent::text,ver,0,'create',null,'Synthetic old parser approval');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(parent::text,ver)->'fields') x
 where x->>'field' in ('entity_name','abn','website');
 approval:=community_orgs.approve_ingestion_fields(parent::text,ver,1,fields);
 stale:=community_orgs.approve_ingestion_fields(parent::text,ver,1,fields);
 org:=community_orgs.publish_ingestion_fields(approval);
 update community_orgs.organisations set entity_name='Human correction' where org_id=org;
 snapshot:=to_jsonb((select v from ingestion.source_record_versions v where id=ver::bigint));
 e:=jsonb_set(e,'{reprocessing,parent_run_id}',to_jsonb(parent));
 set local role ingestion_worker;
 replay:=ingestion.stage_acnc_reprocessing(parent,e);
 if ingestion.stage_acnc_reprocessing(parent,e)<>replay then raise exception 'Replay duplicated run'; end if;
 reset role;
 select version_id::text into newver from ingestion.run_records where run_id=replay;
 if newver=ver or (select count(*) from ingestion.source_records where resource_id='f05-synthetic')<>1
  or (select organisation_id from ingestion.source_links where record_id=rec)<>org
  or (select envelope from ingestion.ingestion_runs where id=parent)<>original
  or to_jsonb((select v from ingestion.source_record_versions v where id=ver::bigint))<>snapshot
  or exists(select 1 from ingestion.change_sets where version_id=newver::bigint)
 then raise exception 'Replay altered evidence, approvals or identity'; end if;
 set local role authenticated;
 report:=community_orgs.ingestion_review_queue(replay::text,newver);
 if report->'detail'->>'linked_organisation_id'<>org::text or report->'reprocessing'->>'parent_run_id'<>parent::text then raise exception 'Link/lineage missing in review'; end if;
 fields:=community_orgs.ingestion_field_preview(replay::text,newver,org)->'fields';
 if not fields @> '[{"field":"website","status":"unchanged"},{"field":"entity_name","status":"conflict","protected":true},{"field":"abn","status":"unchanged"}]' then
  raise exception 'Replay lost protection or unchanged values'; end if;
 select x into f from jsonb_array_elements(fields) x where x->>'field'='website';
 perform community_orgs.suppress_ingestion_content(replay::text,newver,'website','Synthetic withdrawal',jsonb_build_object('organisation_id',org,'field',f));
 begin perform community_orgs.publish_ingestion_fields(stale); raise exception 'Old approval accepted';
 exception when serialization_failure or insufficient_privilege then null; end;
 perform community_orgs.save_ingestion_review(replay::text,newver,0,'link',org,'Fresh review of replay');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(replay::text,newver,org)->'fields') x where x->>'status'='new';
 approval:=community_orgs.approve_ingestion_fields(replay::text,newver,1,fields,org);
 perform community_orgs.publish_ingestion_fields(approval);
 perform community_orgs.publish_ingestion_fields(approval);
 report:=community_orgs.ingestion_reprocessing_report(replay::text);
 if not report->'records'->0->'fields' @> '[{"field":"website","suppressed":true,"previously_published":true,"published":false},{"field":"pbi","approved":true,"published":true}]' then raise exception 'Coverage states incorrect'; end if;
 reset role;
 if (select count(*) from community_orgs.acnc_register_details where org_id=org)<>1 then raise exception 'Duplicate projection'; end if;
 set local role anon;
 if community_orgs.organisation_register_facts(org) @> '[{"field":"website"}]' then raise exception 'Withdrawn field leaked'; end if;
 reset role;
 -- Whole-record withdrawal remains effective across a second deterministic replay.
 perform community_orgs.suppress_ingestion_content(replay::text,newver,'*','Synthetic whole withdrawal',jsonb_build_object('organisation_id',org));
 bad:=jsonb_set(e,'{run_id}','"f05-retry"');
 bad:=jsonb_set(bad,'{records}',(select jsonb_agg(jsonb_set(x,'{run_id}','"f05-retry"')) from jsonb_array_elements(e->'records') x));
 begin perform ingestion.stage_acnc_reprocessing(parent,bad); raise exception 'Withdrawn evidence replay accepted' using errcode='XX000';
 exception when raise_exception then
  if sqlerrm<>'Replay identity or evidence differs from retained version' then raise; end if;
 end;
 set local role anon;
 if jsonb_array_length(community_orgs.organisation_register_facts(org))<>0 or exists(select 1 from community_orgs.organisations where org_id=org) then raise exception 'Replay restored withdrawn organisation'; end if;
 reset role;
 -- Each corruption must fail before any staging writes.
 for bad in select x from (values
  (jsonb_set(e,'{observed_at}','"2026-09-17T00:00:00Z"')),
  (jsonb_set(e,'{records,0,raw,ABN}','"11111111111"')),
  (jsonb_set(e,'{records,0,raw_sha256}','"tampered"')),
  (jsonb_set(e,'{records,0,native_id}','"other"')),
  (jsonb_set(e,'{records}','[]')),
  (jsonb_set(e,'{pages}','[]'))
 ) b(x) loop
  begin perform ingestion.stage_acnc_reprocessing(parent,bad); raise exception 'Bad replay accepted' using errcode='XX000';
  exception when raise_exception then null; end;
 end loop;
 if has_function_privilege('anon','community_orgs.ingestion_reprocessing_report(text)','execute')
  or has_function_privilege('authenticated','ingestion.stage_acnc_reprocessing(bigint,jsonb)','execute')
  or has_table_privilege('anon','ingestion.reprocessing_runs','select') then raise exception 'Replay evidence exposed'; end if;
 raise notice 'F05 lineage, immutable evidence, fresh approvals, identity reuse, protection, withdrawal, coverage and replay passed';
end $$;
rollback;

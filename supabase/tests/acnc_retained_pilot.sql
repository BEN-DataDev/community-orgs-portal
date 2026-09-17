-- DISPOSABLE DATABASE ONLY. Real retained evidence is supplied privately through
-- test.pilot_parent, test.pilot_replay and test.pilot_source. Never commit raw data.
-- Caller starts a transaction; this suite rolls every write back.
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000f06');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000f06');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000f06","aal":"aal2"}',true);
do $$
declare original jsonb:=current_setting('test.pilot_parent')::jsonb;
 e jsonb:=current_setting('test.pilot_replay')::jsonb; s jsonb:=current_setting('test.pilot_source')::jsonb;
 parent bigint; replay bigint; ver text; newver text; org uuid; fields jsonb; approval uuid; report jsonb;
 before_versions jsonb;
begin
 if original->>'parser_version'<>'acnc-ckan-v1' or jsonb_array_length(original->'records')<>6
  or not original->'records' @> '[{"raw":{"ABN":"75349327058"}}]' then raise exception 'Unexpected pilot evidence'; end if;
 insert into ingestion.sources(source_id,resource_id,metadata,enabled) values(s->>'source_id',s->>'resource_id',s->'metadata',true);
 parent:=ingestion.stage_acnc(original);
 select jsonb_agg(to_jsonb(v) order by v.id) into before_versions from ingestion.source_record_versions v
  join ingestion.run_records rr on rr.version_id=v.id where rr.run_id=parent;
 select v.id::text into ver from ingestion.source_record_versions v join ingestion.run_records rr on rr.version_id=v.id
  where rr.run_id=parent and v.payload->'raw'->>'ABN'='75349327058';
 -- Reproduce the existing reviewed link without importing production users or approvals.
 perform community_orgs.save_ingestion_review(parent::text,ver,0,'create',null,'Isolated pilot reproduction');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(parent::text,ver)->'fields') x
  where x->>'field' in ('entity_name','abn');
 approval:=community_orgs.approve_ingestion_fields(parent::text,ver,1,fields);
 org:=community_orgs.publish_ingestion_fields(approval);
 e:=jsonb_set(e,'{reprocessing,parent_run_id}',to_jsonb(parent));
 set local role ingestion_worker;
 replay:=ingestion.stage_acnc_reprocessing(parent,e);
 if ingestion.stage_acnc_reprocessing(parent,e)<>replay then raise exception 'Pilot retry duplicated run'; end if;
 reset role;
 if (select count(*) from ingestion.run_records where run_id=replay)<>5
  or (select completion from ingestion.ingestion_runs where id=replay)<>'partial'
  or jsonb_array_length(e->'quarantine')<>1
  or e->'quarantine'->0->>'reason' not like 'Charity_Website:%'
  or (select count(*) from ingestion.source_records where resource_id=original->>'resource_id')<>6
  or (select jsonb_agg(to_jsonb(v) order by v.id) from ingestion.source_record_versions v
   join ingestion.run_records rr on rr.version_id=v.id where rr.run_id=parent)<>before_versions
  or (select envelope from ingestion.ingestion_runs where id=parent)<>original
 then raise exception 'Pilot evidence, quarantine or identity checks failed'; end if;
 select v.id::text into newver from ingestion.source_record_versions v join ingestion.run_records rr on rr.version_id=v.id
  where rr.run_id=replay and v.payload->'raw'->>'ABN'='75349327058';
 set local role authenticated;
 if community_orgs.ingestion_review_queue(replay::text,newver)->'detail'->>'linked_organisation_id'<>org::text then raise exception 'Pilot link lost'; end if;
 perform community_orgs.save_ingestion_review(replay::text,newver,0,'link',org,'Isolated replay review');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(replay::text,newver,org)->'fields') x where x->>'status'='new';
 begin perform community_orgs.approve_ingestion_fields(replay::text,newver,1,fields,org); raise exception 'Partial pilot approved';
 exception when invalid_parameter_value then null; end;
 report:=community_orgs.ingestion_reprocessing_report(replay::text);
 if jsonb_array_length(report->'records')<>5 or exists(select 1 from jsonb_array_elements(report->'records') r,
  jsonb_array_elements(r->'fields') f where f->'approved'='true' or f->'published'='true') then raise exception 'Old approval transferred'; end if;
 perform set_config('test.pilot_report',report::text,true);
 set local role anon;
 if jsonb_array_length(community_orgs.organisation_register_facts(org))<>2 then raise exception 'Replay exposed unapproved facts'; end if;
 reset role;
 if exists(select 1 from community_orgs.acnc_register_details where org_id=org) then raise exception 'Unapproved child projection'; end if;
 raise notice 'Retained six-record pilot: five accepted, one quarantined, original evidence and link preserved, no transferred approvals or public expansion';
end $$;
select current_setting('test.pilot_report')::jsonb as pilot_report;
rollback;

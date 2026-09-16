-- Run through an administrative connection after staging the synthetic sample.
-- Set test.ingestion_operator to an existing platform-admin/operator UUID first.
-- All review/publication changes roll back; the staged fixture remains untouched.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
do $$
declare r text; v text; fields jsonb; approved uuid; duplicate uuid; org uuid; snapshot jsonb;
 baseline bigint;
begin
 select id::text into r from ingestion.ingestion_runs
 where resource_id='synthetic-acnc-resource-v1' and run_key='offline-acnc-sample-v1';
 select rr.version_id::text into v from ingestion.run_records rr
 join ingestion.source_record_versions sv on sv.id=rr.version_id
 join ingestion.source_records sr on sr.id=sv.record_id
 where rr.run_id=r::bigint and sr.native_id='1';
 if r is null or v is null then raise exception 'Stage the synthetic sample first'; end if;
 if exists(select 1 from ingestion.reviews where version_id=v::bigint) then
  raise exception 'Fixture already reviewed; use an untouched synthetic fixture'; end if;
 select count(*) into baseline from community_orgs.organisations;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.ingestion_operator'),'role','authenticated','is_anonymous',false,'aal','aal2')::text,true);
 set local role authenticated;
 if not community_orgs.is_ingestion_operator() then raise exception 'Operator access missing'; end if;
 snapshot := community_orgs.ingestion_review_queue(r,v);
 if (snapshot->>'total')::int<>2 then raise exception 'Expected two synthetic records'; end if;
 perform community_orgs.save_ingestion_review(r,v,0,'create',null,'Synthetic rollback-only verification');
 begin perform community_orgs.save_ingestion_review(r,v,0,'reject',null,'Stale revision');
  raise exception 'Stale review accepted'; exception when serialization_failure then null; end;
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v)->'fields') x
 where x->>'field' in ('entity_name','website');
 approved := community_orgs.approve_ingestion_fields(r,v,1,fields);
 duplicate := community_orgs.approve_ingestion_fields(r,v,1,fields);
 org := community_orgs.publish_ingestion_fields(approved);
 if community_orgs.publish_ingestion_fields(approved)<>org then raise exception 'Replay target changed'; end if;
 if not exists(select 1 from community_orgs.organisations where org_id=org and is_public and entity_name='Synthetic Valley Community Centre') then raise exception 'Published organisation inaccessible or incorrect'; end if;
 begin perform community_orgs.publish_ingestion_fields(duplicate); raise exception 'Duplicate creation accepted'; exception when serialization_failure then null; end;
 update community_orgs.contact_info set website='https://human.example' where org_id=org;
 perform community_orgs.publish_ingestion_fields(approved);
 if not exists(select 1 from community_orgs.contact_info where org_id=org and website='https://human.example') then raise exception 'Replay lost human correction'; end if;
 snapshot := community_orgs.ingestion_field_preview(r,v,org);
 if not snapshot->'fields' @> '[{"field":"website","status":"conflict","protected":true}]'::jsonb then raise exception 'Human edit not protected'; end if;
 reset role;
 if exists(select 1 from community_orgs.user_organisation_roles where organisation_id=org) then raise exception 'Import granted ownership'; end if;
 if exists(select 1 from community_orgs.legal_details where org_id=org and abn is not null) then raise exception 'Unselected ABN published'; end if;
 if (select count(*) from community_orgs.organisations)<>baseline+1 then raise exception 'Unexpected creation count'; end if;
 if (select count(*) from ingestion.publications where change_set_id=approved)<>1 then raise exception 'Publication audit missing or duplicated'; end if;
 perform set_config('test.ingestion_result',jsonb_build_object('run',r,'version',v,'records',2,'review','passed','publication','passed','retry','passed','manual_protection','passed','no_ownership','passed','rollback',true)::text,true);
end $$;
select current_setting('test.ingestion_result')::jsonb as verification;
rollback;

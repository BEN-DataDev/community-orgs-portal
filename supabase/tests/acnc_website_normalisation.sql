begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000f07');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000f07');
insert into ingestion.sources values ('acnc-register','f05-synthetic','{"synthetic":true}',true,0);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000f07","aal":"aal2"}',true);
do $$
declare parent bigint; old_run bigint; new_run bigint; ver text; e jsonb:=current_setting('test.website_replay')::jsonb;
 old jsonb; r jsonb; fields jsonb; approval uuid; org uuid;
begin
 parent:=ingestion.stage_acnc(current_setting('test.website_parent')::jsonb);
 e:=jsonb_set(e,'{reprocessing,parent_run_id}',to_jsonb(parent));
 -- Retain the old strict v2 quarantine result independently of the new v3 run.
 r:=e->'records'->0;
 old:=e || jsonb_build_object('run_id','website-v2','parser_version','acnc-ckan-v2','completion','partial',
  'records','[]'::jsonb,'quarantine',jsonb_build_array(jsonb_build_object('native_id',r->>'native_id',
   'raw',r->'raw','raw_sha256',r->>'raw_sha256','reason','Charity_Website: absolute URL required')));
 old:=jsonb_set(old,'{counts,accepted}','0');
 old:=jsonb_set(old,'{counts,quarantined}','1');
 old:=jsonb_set(old,'{reprocessing,mapping_version}','"acnc-register-fields-v2"');
 old_run:=ingestion.stage_acnc_reprocessing(parent,old);
 new_run:=ingestion.stage_acnc_reprocessing(parent,e);
 if new_run=old_run or (select envelope from ingestion.ingestion_runs where id=old_run)<>old then raise exception 'Old replay altered'; end if;
 select version_id::text into ver from ingestion.run_records where run_id=new_run;
 set local role authenticated;
 perform community_orgs.save_ingestion_review(new_run::text,ver,0,'create',null,'Synthetic inferred scheme review');
 fields:=community_orgs.ingestion_field_preview(new_run::text,ver)->'fields';
 if not fields @> '[{"field":"website","status":"new","source_value":"https://example.org","source_values":{"Charity_Website":"example.org"},"mapping_version":"acnc-register-fields-v3"}]' then
  raise exception 'Inferred URL or original evidence missing from preview'; end if;
 select jsonb_agg(x) into fields from jsonb_array_elements(fields) x where x->>'field' in ('entity_name','website');
 approval:=community_orgs.approve_ingestion_fields(new_run::text,ver,1,fields);
 org:=community_orgs.publish_ingestion_fields(approval);
 reset role;
 if not exists(select 1 from community_orgs.contact_info where org_id=org and website='https://example.org') then raise exception 'URL storage round-trip failed'; end if;
 set local role anon;
 if not community_orgs.organisation_register_facts(org) @> '[{"field":"website","value":"https://example.org"}]' then raise exception 'Approved URL round-trip failed'; end if;
 reset role;
 if ingestion.stage_acnc_reprocessing(parent,e)<>new_run then raise exception 'v3 retry duplicated run'; end if;
 if (select count(*) from ingestion.source_records where resource_id='f05-synthetic')<>1 then raise exception 'Identity duplicated'; end if;
 raise notice 'Website v3: retained v2 quarantine, original evidence in preview, fresh approval, URL publication and retry passed';
end $$;
rollback;

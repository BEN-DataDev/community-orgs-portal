-- Load emit_complete_fixture.py output in this same session first. Rollback-only.
begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000f03');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000f03');
insert into ingestion.sources(source_id,resource_id,metadata,enabled)
 values ('acnc-register','f03-complete','{"synthetic":true}',true);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000f03","aal":"aal2"}',true);

do $$
declare e jsonb:=current_setting('test.f03_envelope')::jsonb; run text; ver text; rec bigint;
 fields jsonb; preview jsonb; approval uuid; stale uuid; org uuid; m ingestion.field_mappings; actual jsonb;
 expr text; f jsonb; run2 text; ver2 text; changed jsonb; empty_org uuid;
begin
 run:=ingestion.stage_acnc(e)::text;
 select version_id::text into ver from ingestion.run_records where run_id=run::bigint;
 select record_id into rec from ingestion.source_record_versions where id=ver::bigint;
 set local role authenticated;
 perform community_orgs.save_ingestion_review(run,ver,0,'create',null,'Full synthetic field review');
 fields:=community_orgs.ingestion_field_preview(run,ver)->'fields';
 if jsonb_array_length(fields)<>62 or exists(select 1 from jsonb_array_elements(fields) x where x->>'status'<>'new') then
  raise exception 'Expected 62 eligible review units: %',fields; end if;
 approval:=community_orgs.approve_ingestion_fields(run,ver,1,fields);
 stale:=community_orgs.approve_ingestion_fields(run,ver,1,fields);
 -- Saving approval alone must have no public effect.
 reset role;
 if exists(select 1 from community_orgs.acnc_register_details) then raise exception 'Approval published data'; end if;
 -- Force a late write failure; every earlier write and its protection state must roll back.
 alter table community_orgs.acnc_register_details add constraint f03_fail check(responsible_person_count is null);
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Expected write failure'; exception when check_violation then null; end;
 if exists(select 1 from ingestion.publications) or exists(select 1 from ingestion.creation_targets) or exists(select 1 from community_orgs.organisations) then
  raise exception 'Partial publication leaked'; end if;
 alter table community_orgs.acnc_register_details drop constraint f03_fail;
 set local role authenticated;
 org:=community_orgs.publish_ingestion_fields(approval);
 if community_orgs.publish_ingestion_fields(approval)<>org then raise exception 'Replay changed identity'; end if;
 begin perform community_orgs.publish_ingestion_fields(stale); raise exception 'Duplicate create accepted'; exception when serialization_failure then null; end;
 reset role;
 -- All scalar types and each JSON flag/path must round-trip exactly, including false.
 for f in select value from jsonb_array_elements(fields) loop
  select * into m from ingestion.field_mappings where field=f->>'field';
  expr:=format('to_jsonb(x.%I)',m.column_name);
  if m.path is not null then expr:=format('(%s)->%L',expr,m.path); end if;
  execute format('select %s from community_orgs.%I x where org_id=$1',expr,m.table_name) into actual using org;
  if actual is distinct from f->'source_value' then raise exception 'Round-trip failed: %',m.field; end if;
 end loop;
 if (select count(*) from community_orgs.acnc_register_details where org_id=org)<>1 then raise exception 'Duplicate child rows'; end if;
 if exists(select 1 from community_orgs.user_organisation_roles where organisation_id=org) then raise exception 'Unexpected ownership'; end if;
 if jsonb_array_length(community_orgs.organisation_source_attribution(org))<>62 then raise exception 'Missing attribution'; end if;
 if exists(select 1 from jsonb_array_elements(community_orgs.organisation_source_attribution(org)) a where a->'unchanged_since_import'<>'true') then raise exception 'Incorrect imported revision'; end if;

 -- Stage a revised record. Assertions omitted in later versions never clear facts.
 changed:=e->'records'->0;
 changed:=jsonb_set(changed,'{run_id}','"f03-update"');
 changed:=jsonb_set(changed,'{assertions}',(select jsonb_agg(case
  when x->>'field'='administrative_address' then jsonb_set(x,'{value}','{"line_1":"Updated first line"}')
  when x->>'field'='purposes.advancing_health' then jsonb_set(x,'{value}','false')
  when x->>'field'='charity_size' then jsonb_set(x,'{value}','"Large"')
  else x end) from jsonb_array_elements(changed->'assertions') x where x->>'field'<>'pbi'));
 e:=jsonb_set(jsonb_set(e,'{run_id}','"f03-update"'),'{records}',jsonb_build_array(changed));
 run2:=ingestion.stage_acnc(e)::text;
 select version_id::text into ver2 from ingestion.run_records where run_id=run2::bigint;
 perform community_orgs.save_ingestion_review(run2,ver2,0,'link',org,'Reviewed source update');
 preview:=community_orgs.ingestion_field_preview(run2,ver2,org);
 if not preview->'fields' @> '[{"field":"pbi","status":"missing"},{"field":"charity_size","status":"changed","protected":false}]' then raise exception 'Missing/change semantics wrong'; end if;
 select jsonb_agg(x) into fields from jsonb_array_elements(preview->'fields') x where x->>'field' in ('administrative_address','purposes.advancing_health');
 approval:=community_orgs.approve_ingestion_fields(run2,ver2,1,fields,org);
 perform community_orgs.publish_ingestion_fields(approval);
 if not exists(select 1 from community_orgs.acnc_register_details where org_id=org and administrative_address->>'line_1'='Updated first line'
  and administrative_address->>'line_2'='Synthetic Address Line 2' and administrative_address->>'postcode'='0800'
  and purposes->'advancing_health'='false' and purposes->'advancing_culture'='true' and pbi=false and charity_size='Small') then
  raise exception 'Partial approval cleared or published unselected facts'; end if;

 -- A manual visibility change invalidates approvals and cannot be undone by import.
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(run2,ver2,org)->'fields') x where x->>'field'='charity_size';
 approval:=community_orgs.approve_ingestion_fields(run2,ver2,1,fields,org);
 update community_orgs.acnc_register_details set is_public=false where org_id=org;
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Hidden projection restored'; exception when serialization_failure then null; end;
 if not community_orgs.ingestion_field_preview(run2,ver2,org)->'fields' @> '[{"field":"charity_size","status":"conflict","protected":true}]' then raise exception 'Hidden projection not protected'; end if;
 update community_orgs.acnc_register_details set is_public=true where org_id=org;

 -- Mapping and source configuration changes invalidate saved snapshots.
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(run2,ver2,org)->'fields') x where x->>'field'='charity_size';
 approval:=community_orgs.approve_ingestion_fields(run2,ver2,1,fields,org);
 update ingestion.field_mappings set mapping_version='future' where field='charity_size';
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Changed mapping accepted'; exception when serialization_failure then null; end;
 update ingestion.field_mappings set mapping_version='acnc-register-fields-v2' where field='charity_size';
 update ingestion.sources set approval_revision=approval_revision+1 where resource_id='f03-complete';
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Changed source config accepted'; exception when serialization_failure then null; end;
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(run2,ver2,org)->'fields') x where x->>'field'='charity_size';
 approval:=community_orgs.approve_ingestion_fields(run2,ver2,1,fields,org);
 -- Editing away and back invalidates approval even when the value is identical.
 update community_orgs.acnc_register_details set charity_size='Human correction' where org_id=org;
 update community_orgs.acnc_register_details set charity_size='Small' where org_id=org;
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Human edit overwritten'; exception when serialization_failure then null; end;
 if not community_orgs.ingestion_field_preview(run2,ver2,org)->'fields' @> '[{"field":"charity_size","status":"conflict","protected":true}]' then raise exception 'Manual edit not protected'; end if;

 -- Every suppression unit clears its value and blocks direct restoration.
 for m in select * from ingestion.field_mappings where field<>'entity_name' loop
  preview:=community_orgs.ingestion_field_preview(run2,ver2,org);
  select x into f from jsonb_array_elements(preview->'fields') x where x->>'field'=m.field;
  perform community_orgs.suppress_ingestion_content(run2,ver2,m.field,'Synthetic field suppression',jsonb_build_object('organisation_id',org,'field',f));
  expr:=format('to_jsonb(x.%I)',m.column_name);
  if m.path is not null then expr:=format('(%s)->%L',expr,m.path); end if;
  execute format('select %s from community_orgs.%I x where org_id=$1',expr,m.table_name) into actual using org;
  if nullif(actual,'null'::jsonb) is not null then raise exception 'Suppression failed: %',m.field; end if;
  begin
   perform ingestion.write_field(org,rec,m.field,f->'current_value');
   raise exception 'Restoration accepted: %',m.field;
  exception when insufficient_privilege then null; end;
 end loop;
 if jsonb_array_length(community_orgs.organisation_source_attribution(org))<>1 then raise exception 'Suppressed attribution leaked'; end if;
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Suppressed approval replayed'; exception when insufficient_privilege then null; end;
 preview:=community_orgs.ingestion_field_preview(run2,ver2,org);
 select x into f from jsonb_array_elements(preview->'fields') x where x->>'field'='entity_name';
 perform community_orgs.suppress_ingestion_content(run2,ver2,'entity_name','Synthetic name withdrawal',jsonb_build_object('organisation_id',org,'field',f));
 if (select is_public from community_orgs.organisations where org_id=org) then raise exception 'Name withdrawal leaked'; end if;
 begin update community_orgs.organisations set is_public=true where org_id=org; raise exception 'Withdrawn organisation restored'; exception when insufficient_privilege then null; end;
 if community_orgs.organisation_source_attribution(org)<>'[]' then raise exception 'Withdrawal attribution leaked'; end if;

 -- A different source identity cannot silently merge, even with the same ABN/name.
 changed:=jsonb_set(changed,'{native_id}','"different-identity"');
 changed:=jsonb_set(changed,'{run_id}','"f03-independent"');
 e:=jsonb_set(jsonb_set(e,'{run_id}','"f03-independent"'),'{records}',jsonb_build_array(changed));
 run:=ingestion.stage_acnc(e)::text;
 select version_id::text into ver from ingestion.run_records where run_id=run::bigint;
 perform community_orgs.save_ingestion_review(run,ver,0,'create',null,'Distinct source identity');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(run,ver)->'fields') x where x->>'field'='entity_name';
 approval:=community_orgs.approve_ingestion_fields(run,ver,1,fields);
 empty_org:=community_orgs.publish_ingestion_fields(approval);
 if empty_org=org then raise exception 'Automatic identity merge'; end if;
 if exists(select 1 from community_orgs.acnc_register_details where org_id=empty_org) then raise exception 'Unselected register facts published'; end if;
 -- Function/table access cannot bypass operator checks.
 if has_function_privilege('anon','community_orgs.publish_ingestion_fields(uuid)','execute')
 or has_function_privilege('authenticated','ingestion.write_field(uuid,bigint,text,jsonb)','execute')
 or has_table_privilege('authenticated','ingestion.field_mappings','update') then raise exception 'Unexpected grants'; end if;
 -- The full migration runner uses the real MFA helper and factor table; the
 -- older isolated harness emulates enrollment with the test_enrolled claim.
 if to_regclass('auth.mfa_factors') is not null then
  execute 'insert into auth.mfa_factors(user_id,status) values ($1,''verified'')'
   using '00000000-0000-4000-8000-000000000f03'::uuid;
 end if;
 set local role authenticated;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000f03","aal":"aal1","test_enrolled":true}',true);
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'MFA bypass'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{}',true);
 begin perform community_orgs.ingestion_field_preview(run,ver); raise exception 'Nonoperator preview'; exception when insufficient_privilege then null; end;
 reset role;
 raise notice 'F03 complete-field round trips, atomicity, selection, stale snapshots, protection, suppression, replay and access passed';
end $$;
-- Invalid typed assertions, unsupported parser versions and source-scoped facts.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000f03","aal":"aal2"}',true);
do $$
declare e jsonb:=current_setting('test.f03_envelope')::jsonb; row jsonb; run text; ver text; org uuid;
 fields jsonb; f jsonb; approval uuid; old_approval uuid; snapshot jsonb; rec bigint; second_rec bigint;
begin
 row:=jsonb_set(e->'records'->0,'{native_id}','"edge-cases"');
 row:=jsonb_set(row,'{run_id}','"f03-edge"');
 row:=jsonb_set(row,'{assertions}', '[{"field":"entity_name","value":"Edge case"},
  {"field":"pbi","value":"N"},{"field":"acnc_registered_date","value":"2024-02-31"},
  {"field":"financial_year_end","value":{"month":2,"day":30}},
  {"field":"responsible_person_count","value":-1},{"field":"website","value":"https://user:password@example.org"},
  {"field":"administrative_address","value":{"line_1":"test","postcode":"800","visibility":true}},
  {"field":"future_unknown","value":"Review me"}]');
 e:=jsonb_set(jsonb_set(e,'{run_id}','"f03-edge"'),'{records}',jsonb_build_array(row));
 run:=ingestion.stage_acnc(e)::text;
 select version_id::text into ver from ingestion.run_records where run_id=run::bigint;
 select record_id into rec from ingestion.source_record_versions where id=ver::bigint;
 perform community_orgs.save_ingestion_review(run,ver,0,'create',null,'Edge values');
 fields:=community_orgs.ingestion_field_preview(run,ver)->'fields';
 if (select count(*) from jsonb_array_elements(fields) x where x->>'status'='invalid')<>6
  or not fields @> '[{"field":"future_unknown","status":"unmapped"}]' then raise exception 'Invalid/unmapped fields hidden'; end if;
 select jsonb_agg(x) into f from jsonb_array_elements(fields) x where x->>'field'='pbi';
 begin perform community_orgs.approve_ingestion_fields(run,ver,1,f); raise exception 'Invalid value approved'; exception when serialization_failure then null; end;
 select jsonb_agg(x) into fields from jsonb_array_elements(fields) x where x->>'field'='entity_name';
 approval:=community_orgs.approve_ingestion_fields(run,ver,1,fields);
 -- A saved approval lacking the F03 snapshot cannot authorise publication.
 old_approval:=community_orgs.approve_ingestion_fields(run,ver,1,fields);
 update ingestion.change_sets c set fields=jsonb_build_array((c.fields->0)-'mapping_token') where id=old_approval;
 begin perform community_orgs.publish_ingestion_fields(old_approval); raise exception 'Pre-F03 snapshot accepted'; exception when serialization_failure then null; end;
 row:=jsonb_set(row,'{run_id}','"f03-edge-new"');
 row:=jsonb_set(row,'{raw}', '{"changed":true}');
 e:=jsonb_set(jsonb_set(e,'{run_id}','"f03-edge-new"'),'{records}',jsonb_build_array(row));
 perform ingestion.stage_acnc(e);
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'New source version did not stale approval'; exception when serialization_failure then null; end;
 -- Review can deliberately approve the older evidence again, with the new state visible.
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(run,ver)->'fields') x where x->>'field'='entity_name';
 approval:=community_orgs.approve_ingestion_fields(run,ver,1,fields);
 org:=community_orgs.publish_ingestion_fields(approval);
 -- New source identity explicitly linked to the same org gets an independent projection.
 row:=jsonb_set(jsonb_set(row,'{native_id}','"second-source"'),'{run_id}','"f03-second"');
 row:=jsonb_set(row,'{assertions}','[{"field":"pbi","value":false},{"field":"hpc","value":true}]');
 e:=jsonb_set(jsonb_set(e,'{run_id}','"f03-second"'),'{records}',jsonb_build_array(row));
 run:=ingestion.stage_acnc(e)::text;
 select version_id::text into ver from ingestion.run_records where run_id=run::bigint;
 select record_id into second_rec from ingestion.source_record_versions where id=ver::bigint;
 perform community_orgs.save_ingestion_review(run,ver,0,'link',org,'Explicit identity link');
 select jsonb_agg(x) into fields from jsonb_array_elements(community_orgs.ingestion_field_preview(run,ver,org)->'fields') x where x->>'status'='new';
 approval:=community_orgs.approve_ingestion_fields(run,ver,1,fields,org);
 perform community_orgs.publish_ingestion_fields(approval);
 -- A separate source projection may disagree, and is not overwritten by the other.
 perform ingestion.write_field(org,rec,'pbi','true');
 update community_orgs.acnc_register_details set is_public=true where org_id=org and source_record_id=rec;
 if (select count(*) from community_orgs.acnc_register_details where org_id=org)<>2 then raise exception 'Source projections merged'; end if;
 snapshot:=community_orgs.ingestion_field_preview(run,ver,org);
 select x into f from jsonb_array_elements(snapshot->'fields') x where x->>'field'='pbi';
 if f->'current_value'<>'false' then raise exception 'Preview read the wrong source projection'; end if;
 perform community_orgs.suppress_ingestion_content(run,ver,'pbi','Target-scoped suppression',jsonb_build_object('organisation_id',org,'field',f));
 if exists(select 1 from community_orgs.acnc_register_details where org_id=org and pbi is not null) then raise exception 'Other source leaked suppressed fact'; end if;
 begin perform ingestion.write_field(org,rec,'pbi','true'); raise exception 'Other source restored suppressed fact'; exception when insufficient_privilege then null; end;
 -- A replayed/reprocessed version of the same source is still suppressed.
 row:=jsonb_set(row,'{run_id}','"f03-second-replay"');
 e:=jsonb_set(jsonb_set(e,'{run_id}','"f03-second-replay"'),'{records}',jsonb_build_array(row));
 run:=ingestion.stage_acnc(e)::text;
 snapshot:=community_orgs.ingestion_field_preview(run,ver,org);
 if not snapshot->'fields' @> '[{"field":"pbi","status":"suppressed"}]' then raise exception 'Replay bypassed suppression'; end if;
 -- Withhold the entire record; anonymous reads must expose neither projection.
 perform community_orgs.suppress_ingestion_content(run,ver,'*','Record withdrawal',jsonb_build_object('organisation_id',org));
 set local role anon;
 if exists(select org_id from community_orgs.acnc_register_details) then raise exception 'Withdrawn projections publicly readable'; end if;
 reset role;
 raise notice 'Invalid values, unknown fields, old approvals, source-version changes, source scoping and withdrawal checks passed';
end $$;

rollback;

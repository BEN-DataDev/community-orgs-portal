-- Set test.ingestion_operator to an existing operator UUID. Rollback-only.
begin;
set local lock_timeout='3s';
set local statement_timeout='20s';
insert into ingestion.sources values ('acnc-register','suppression-fixture','{"synthetic":true,"public_title":"Example source","public_url":"https://example.org/source","public_licence":"Synthetic fixture"}',true);
do $$
declare
 e jsonb := '{"contract_version":"1.0","source_id":"acnc-register","resource_id":"suppression-fixture","run_id":"one","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{},"quarantine":[],"errors":[],"records":[{"source_id":"acnc-register","resource_id":"suppression-fixture","run_id":"one","native_id":"1","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","raw":{},"assertions":[{"field":"entity_name","value":"Synthetic suppression example"},{"field":"website","value":"https://source.example"},{"field":"abn","value":"00000000000"}]}]}';
 r text; v text; org uuid; approval uuid; fields jsonb; snapshot jsonb; claims text;
begin
 r:=ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 claims:=jsonb_build_object('sub',current_setting('test.ingestion_operator'),'role','authenticated','aal','aal2')::text;
 perform set_config('request.jwt.claims',claims,true);
 set local role authenticated;
 perform community_orgs.save_ingestion_review(r,v,0,'create',null,'Synthetic suppression test');
 fields:=community_orgs.ingestion_field_preview(r,v)->'fields';
 approval:=community_orgs.approve_ingestion_fields(r,v,1,fields);
 org:=community_orgs.publish_ingestion_fields(approval);
 reset role;
 set local role anon;
 perform set_config('request.jwt.claims','{}',true);
 snapshot:=community_orgs.organisation_source_attribution(org);
 if jsonb_array_length(snapshot)<>3 or not snapshot @> '[{"field":"website","unchanged_since_import":true}]'::jsonb then raise exception 'Public attribution incorrect: %',snapshot; end if;
 if snapshot::text like '%source_value%' or snapshot::text like '%raw%' then raise exception 'Private evidence exposed'; end if;
 reset role;
 perform set_config('request.jwt.claims',claims,true);
 select x into snapshot from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v,org)->'fields') x where x->>'field'='website';
 update community_orgs.contact_info set website='https://human.example' where org_id=org;
 if not community_orgs.organisation_source_attribution(org) @> '[{"field":"website","unchanged_since_import":false}]'::jsonb then raise exception 'Manual edit not distinguished'; end if;
 set local role authenticated;
 begin perform community_orgs.suppress_ingestion_content(r,v,'website','Remove correction',jsonb_build_object('organisation_id',org,'field',snapshot)); raise exception 'Stale removal accepted'; exception when serialization_failure then null; end;
 select x into snapshot from jsonb_array_elements(community_orgs.ingestion_field_preview(r,v,org)->'fields') x where x->>'field'='website';
 perform community_orgs.suppress_ingestion_content(r,v,'website','Explicit correction removal',jsonb_build_object('organisation_id',org,'field',snapshot));
 begin perform community_orgs.publish_ingestion_fields(approval); raise exception 'Suppressed replay accepted'; exception when insufficient_privilege then null; end;
 reset role;
 if exists(select 1 from community_orgs.contact_info where org_id=org and website is not null) then raise exception 'Field not removed'; end if;
 begin update community_orgs.contact_info set website='https://restore.example' where org_id=org; raise exception 'Direct restore accepted'; exception when insufficient_privilege then null; end;
 if exists(select 1 from jsonb_array_elements(community_orgs.organisation_source_attribution(org)) x where x->>'field'='website') then raise exception 'Suppressed attribution exposed'; end if;
 -- A changed version of the same source identity remains suppressed.
 e:=jsonb_set(jsonb_set(e,'{run_id}','"two"'),'{records,0,run_id}','"two"');
 e:=jsonb_set(e,'{records,0,assertions,1,value}','"https://new-source.example"');
 r:=ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 if not community_orgs.ingestion_field_preview(r,v,org)->'fields' @> '[{"field":"website","status":"suppressed"}]'::jsonb then raise exception 'New version bypassed suppression'; end if;
 perform community_orgs.suppress_ingestion_content(r,v,'*','Whole organisation withdrawal',jsonb_build_object('organisation_id',org));
 if (select is_public from community_orgs.organisations where org_id=org) then raise exception 'Withdrawal did not hide organisation'; end if;
 begin update community_orgs.organisations set is_public=true where org_id=org; raise exception 'Re-publication accepted'; exception when insufficient_privilege then null; end;
 set local role anon;
 perform set_config('request.jwt.claims','{}',true);
 if exists(select 1 from community_orgs.organisations where org_id=org) then raise exception 'Withdrawn organisation visible to anonymous user'; end if;
 if community_orgs.organisation_source_attribution(org)<>'[]'::jsonb then raise exception 'Withdrawn attribution leaked'; end if;
 reset role;
 perform set_config('request.jwt.claims','{}',true);
 begin perform community_orgs.suppress_ingestion_content(r,v,'*','Unauthorised',jsonb_build_object('organisation_id',org)); raise exception 'Unauthorised removal accepted'; exception when insufficient_privilege then null; end;
 perform set_config('test.suppression_result','Public attribution, safe projection, changed-value status, stale-removal denial, replay/direct restore blocks, future-version suppression and withdrawal passed',true);
end $$;
select current_setting('test.suppression_result') as result;
rollback;

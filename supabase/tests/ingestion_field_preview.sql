-- Synthetic fixtures; run as postgres on a disposable database after migrations.
begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000099');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000099');
insert into community_orgs.organisations(org_id,entity_name,slug) values
 ('00000000-0000-4000-8000-000000000098','Original name','field-preview-fixture');
insert into community_orgs.contact_info(org_id,website) values
 ('00000000-0000-4000-8000-000000000098','https://human.example');
insert into ingestion.sources values ('acnc-register','field-fixture','{}',true);
do $$
declare
 org uuid := '00000000-0000-4000-8000-000000000098';
 e jsonb := '{"contract_version":"1.0","source_id":"acnc-register","resource_id":"field-fixture","run_id":"one","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{},"quarantine":[],"errors":[],"records":[{"source_id":"acnc-register","resource_id":"field-fixture","run_id":"one","native_id":"1","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","raw":{},"assertions":[{"field":"entity_name","value":"Original name"},{"field":"website","value":"https://source.example"},{"field":"date_established_source","value":"01/02/1990"}]}]}';
 r text; v text; q jsonb; before_rev bigint;
begin
 r := ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 set local role authenticated;
 perform set_config('request.jwt.claims','{}',true);
 begin perform community_orgs.ingestion_field_preview(r,v,org); raise exception 'Expected denial'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000099","aal":"aal2"}',true);
 q := community_orgs.ingestion_field_preview(r,v,org);
 if not q->'fields' @> '[{"field":"entity_name","status":"unchanged"},{"field":"website","status":"conflict","protected":true},{"field":"abn","status":"missing"},{"field":"date_established_source","status":"unmapped"}]'::jsonb then raise exception 'Incorrect initial preview: %',q; end if;
 q := community_orgs.ingestion_field_preview(r,v);
 if not q->'fields' @> '[{"field":"entity_name","status":"new","protected":false}]'::jsonb then raise exception 'New preview incorrect'; end if;
 begin perform community_orgs.ingestion_field_preview('99999999',v,org); raise exception 'Expected run denial'; exception when no_data_found then null; end;
 reset role;
 select revision into before_rev from ingestion.field_state where org_id=org and field='website';
 update community_orgs.contact_info set website=website where org_id=org;
 if (select revision from ingestion.field_state where org_id=org and field='website')<>before_rev then raise exception 'No-op advanced revision'; end if;
 update community_orgs.contact_info set website=null where org_id=org;
 if (select revision from ingestion.field_state where org_id=org and field='website')<>before_rev+1 then raise exception 'Clear not tracked'; end if;
 q := community_orgs.ingestion_field_preview(r,v,org);
 if not q->'fields' @> '[{"field":"website","status":"conflict","protected":true,"current_value":null}]'::jsonb then raise exception 'Manual clear lost protection'; end if;
 delete from community_orgs.contact_info where org_id=org;
 q := community_orgs.ingestion_field_preview(r,v,org);
 if not q->'fields' @> '[{"field":"website","status":"conflict","target_rows":0}]'::jsonb then raise exception 'Deleted field lost protection'; end if;
 insert into community_orgs.contact_info(org_id,website) values (org,'https://one.example'),(org,'https://two.example');
 q := community_orgs.ingestion_field_preview(r,v,org);
 if not q->'fields' @> '[{"field":"website","status":"ambiguous","target_rows":2}]'::jsonb then raise exception 'Ambiguous rows not blocked'; end if;
 update community_orgs.organisations set entity_name='Human correction' where org_id=org;
 q := community_orgs.ingestion_field_preview(r,v,org);
 if not q->'fields' @> '[{"field":"entity_name","status":"conflict","current_value":"Human correction"}]'::jsonb then raise exception 'Human correction lost'; end if;
 e := jsonb_set(jsonb_set(e,'{run_id}','"two"'),'{records,0,run_id}','"two"');
 e := jsonb_set(e,'{records,0,assertions}','[{"field":"entity_name","value":{}},{"field":"website","value":null}]');
 r := ingestion.stage_acnc(e)::text;
 select version_id::text into v from ingestion.run_records where run_id=r::bigint;
 q := community_orgs.ingestion_field_preview(r,v,org);
 if not q->'fields' @> '[{"field":"entity_name","status":"invalid"},{"field":"website","status":"missing"}]'::jsonb then raise exception 'Invalid/null source values not withheld'; end if;
 if has_table_privilege('authenticated','ingestion.field_state','UPDATE') then raise exception 'Client can unlock fields'; end if;
 raise notice 'Preview access, missing/unmapped/new values, protected edits/clears/deletes, no-ops and ambiguous targets passed';
end $$;
rollback;

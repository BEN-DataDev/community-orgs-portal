begin;
create or replace function community_orgs.is_platform_admin() returns boolean language sql as $$
 select coalesce(auth.jwt()->>'test_admin','false')='true' $$;
insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000002701'),
 ('00000000-0000-4000-8000-000000002702');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000002701');
insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values
 ('00000000-0000-4000-8000-000000002711','Still Listed','p27-still-listed',true),
 ('00000000-0000-4000-8000-000000002712','Now Missing','p27-now-missing',true),
 ('00000000-0000-4000-8000-000000002713','Suppression Only','p27-suppression-only',true);
insert into ingestion.sources(source_id,resource_id,metadata,enabled) values
 ('acnc-register','p27-complete','{"synthetic":true}',true),
 ('acnc-register','p27-filtered','{"synthetic":true}',true);

do $$
declare
 e jsonb; old_run text; new_run text; partial_run text; failed_run text; filtered_old text; filtered_new text;
 q jsonb; expected jsonb; action_id uuid;
begin
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000002702","aal":"aal2","test_admin":true}',true);
 perform community_orgs.qualify_complete_snapshot_source(
  'acnc-register','p27-complete',
  '{"kind":"complete-snapshot","complete_snapshot":true,"snapshot_series":"acnc-monthly-register","release":"2026-09"}',
  '{"native_id_stable":true,"identity_basis":"provider immutable record id across releases"}',
  'Synthetic P27 complete-snapshot qualification');
 begin
  perform community_orgs.qualify_complete_snapshot_source(
   'acnc-register','p27-filtered',
   '{"kind":"filtered-resource","complete_snapshot":true,"filters":{"Postcode":"2730"}}',
   '{"native_id_stable":true,"identity_basis":"bad filtered fixture"}',
   'Should fail');
  raise exception 'Filtered complete-snapshot qualification accepted';
 exception when invalid_parameter_value then null; end;

 e:='{"contract_version":"1.0","source_id":"acnc-register","resource_id":"p27-complete","run_id":"p27-old","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{"kind":"complete-snapshot","complete_snapshot":true,"snapshot_series":"acnc-monthly-register","release":"2026-08"},"quarantine":[],"errors":[],"records":[]}';
 e:=jsonb_set(e,'{records}',(select jsonb_agg(jsonb_build_object('source_id','acnc-register','resource_id','p27-complete',
  'run_id','p27-old','native_id',n,'parser_version','v1','observed_at','2026-09-16T00:00:00Z','raw',jsonb_build_object('_id',n),
  'assertions',jsonb_build_array(jsonb_build_object('field','entity_name','value',case n when 'still' then 'Still Listed' when 'missing' then 'Now Missing' else 'Suppression Only' end))))
  from unnest(array['still','missing','suppress']) n));
 old_run:=ingestion.stage_acnc(e)::text;
 insert into ingestion.source_links(record_id,organisation_id)
 select id,case native_id when 'still' then '00000000-0000-4000-8000-000000002711'::uuid
  when 'missing' then '00000000-0000-4000-8000-000000002712'::uuid
  else '00000000-0000-4000-8000-000000002713'::uuid end
 from ingestion.source_records where resource_id='p27-complete';

 e:=jsonb_set(e,'{run_id}','"p27-new"');
 e:=jsonb_set(e,'{observed_at}','"2026-09-17T00:00:00Z"');
 e:=jsonb_set(e,'{scope,release}','"2026-09"');
 e:=jsonb_set(e,'{records}',(select jsonb_agg(x || '{"run_id":"p27-new","observed_at":"2026-09-17T00:00:00Z"}')
  from jsonb_array_elements(e->'records') x where x->>'native_id'='still'));
 new_run:=ingestion.stage_acnc(e)::text;

 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000002701","aal":"aal2"}',true);
 set local role authenticated;
 q:=community_orgs.complete_snapshot_reconciliation_report(new_run,old_run);
 if q->>'assessed'<>'true' or q->'counts'->>'missing'<>'2' then raise exception 'Missing candidates not assessed: %',q; end if;
 if (q->>'implies_deletion')::boolean then raise exception 'Report implied deletion'; end if;
 select jsonb_build_object('run_id',new_run,'baseline_run',old_run,'record_id',x->>'record_id',
  'organisation_id',x->>'organisation_id','scope',q->'scope') into expected
 from jsonb_array_elements(q->'records') x where x->>'native_id'='missing';
 action_id:=community_orgs.approve_reconciliation_action(new_run,old_run,expected->>'record_id','closure','Operator verified complete source disappearance',expected);
 reset role;
 if not exists(select 1 from ingestion.reconciliation_actions a where a.id=action_id and a.action='closure' and a.applied_at is not null) then raise exception 'Closure action not recorded'; end if;
 if exists(select 1 from community_orgs.organisations where org_id='00000000-0000-4000-8000-000000002712' and is_public) then raise exception 'Closure did not unpublish organisation'; end if;
 if not exists(select 1 from ingestion.suppressions where organisation_id='00000000-0000-4000-8000-000000002712' and field='*') then raise exception 'Closure suppression missing'; end if;

 select jsonb_build_object('run_id',new_run,'baseline_run',old_run,'record_id',x->>'record_id',
  'organisation_id',x->>'organisation_id','scope',q->'scope') into expected
 from jsonb_array_elements(q->'records') x where x->>'native_id'='suppress';
 set local role authenticated;
 perform community_orgs.approve_reconciliation_action(new_run,old_run,expected->>'record_id','suppress','Withhold stale source-derived projection pending investigation',expected);
 reset role;
 if not exists(select 1 from community_orgs.organisations where org_id='00000000-0000-4000-8000-000000002713' and is_public) then raise exception 'Suppress should not close organisation'; end if;
 if not exists(select 1 from ingestion.suppressions where organisation_id='00000000-0000-4000-8000-000000002713' and field='*') then raise exception 'Suppress action missing'; end if;
 set local role authenticated;
 begin
  perform community_orgs.approve_reconciliation_action(new_run,old_run,expected->>'record_id','remove','Stale expected','{}');
  raise exception 'Stale expected accepted';
 exception when serialization_failure then null; end;

 reset role;
 e:=jsonb_set(e,'{run_id}','"p27-partial"');
 e:=jsonb_set(e,'{completion}','"partial"');
 e:=jsonb_set(e,'{observed_at}','"2026-09-18T00:00:00Z"');
 e:=jsonb_set(e,'{records}','[]');
 e:=jsonb_set(e,'{quarantine}','[{"native_id":"still","reason":"fixture quarantine","raw":{"_id":"still"}}]');
 partial_run:=ingestion.stage_acnc(e)::text;
 set local role authenticated;
 q:=community_orgs.complete_snapshot_reconciliation_report(partial_run,old_run);
 if q->>'assessed'<>'false' or q->'counts'->>'missing'<>'0' then raise exception 'Partial run assessed: %',q; end if;
 begin
  perform community_orgs.approve_reconciliation_action(partial_run,old_run,expected->>'record_id','closure','Bad partial closure',expected);
  raise exception 'Partial closure accepted';
 exception when invalid_parameter_value then null; end;
 reset role;

 e:=jsonb_set(e,'{run_id}','"p27-failed"');
 e:=jsonb_set(e,'{completion}','"failed"');
 e:=jsonb_set(e,'{observed_at}','"2026-09-19T00:00:00Z"');
 e:=jsonb_set(e,'{quarantine}','[]');
 e:=jsonb_set(e,'{errors}','[{"code":"upstream_failed","message":"fixture failure"}]');
 failed_run:=ingestion.stage_acnc(e)::text;
 set local role authenticated;
 q:=community_orgs.complete_snapshot_reconciliation_report(failed_run,old_run);
 if q->>'assessed'<>'false' or q->'counts'->>'missing'<>'0' then raise exception 'Failed run assessed: %',q; end if;
 begin
  perform community_orgs.approve_reconciliation_action(failed_run,old_run,expected->>'record_id','remove','Bad failed-run removal',expected);
  raise exception 'Failed-run removal accepted';
 exception when invalid_parameter_value then null; end;
 reset role;

 e:='{"contract_version":"1.0","source_id":"acnc-register","resource_id":"p27-filtered","run_id":"p27-filtered-old","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","completion":"complete","publication_eligible":false,"scope":{"kind":"filtered-resource","filters":{"Postcode":"2730"},"complete_snapshot":false},"quarantine":[],"errors":[],"records":[]}';
 e:=jsonb_set(e,'{records}','[{"source_id":"acnc-register","resource_id":"p27-filtered","run_id":"p27-filtered-old","native_id":"filtered-missing","parser_version":"v1","observed_at":"2026-09-16T00:00:00Z","raw":{"_id":"filtered-missing"},"assertions":[{"field":"entity_name","value":"Now Missing"}]}]');
 filtered_old:=ingestion.stage_acnc(e)::text;
 insert into ingestion.source_links(record_id,organisation_id)
 select id,'00000000-0000-4000-8000-000000002712' from ingestion.source_records where resource_id='p27-filtered';
 e:=jsonb_set(e,'{run_id}','"p27-filtered-new"');
 e:=jsonb_set(e,'{observed_at}','"2026-09-17T00:00:00Z"');
 e:=jsonb_set(e,'{records}','[]');
 filtered_new:=ingestion.stage_acnc(e)::text;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000002701","aal":"aal2"}',true);
 set local role authenticated;
 q:=community_orgs.complete_snapshot_reconciliation_report(filtered_new,filtered_old);
 if q->>'assessed'<>'false' or q->>'reason' <> 'Source scope is not qualified as a complete snapshot' then
  raise exception 'Filtered scope became reconcilable: %',q;
 end if;
 if has_function_privilege('anon','community_orgs.complete_snapshot_reconciliation_report(text,text)','EXECUTE')
  or has_function_privilege('ingestion_worker','community_orgs.approve_reconciliation_action(text,text,text,text,text,jsonb)','EXECUTE') then
  raise exception 'Unexpected P27 grants';
 end if;
 raise notice 'P27 complete-snapshot reconciliation guards and review-gated actions passed';
end $$;
rollback;

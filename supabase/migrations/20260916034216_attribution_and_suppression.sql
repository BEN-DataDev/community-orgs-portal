-- Suppression is persistent, private and scoped to source identity and target.
create table ingestion.suppressions (
 record_id bigint not null references ingestion.source_records,
 field text not null check(field in ('*','abn','website')),
 organisation_id uuid references community_orgs.organisations,
 reason text not null check(length(trim(reason)) between 1 and 2000),
 suppressed_by uuid not null references auth.users,
 suppressed_at timestamptz not null default now(),
 primary key(record_id,field)
);
alter table ingestion.suppressions enable row level security;
revoke all on ingestion.suppressions from public,anon,authenticated,service_role;

create function ingestion.assert_not_suppressed(p_version bigint,p_org uuid,p_fields jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from ingestion.suppressions s where
 (s.record_id=(select record_id from ingestion.source_record_versions where id=p_version) or s.organisation_id=p_org)
 and (s.field='*' or exists(select 1 from jsonb_array_elements(p_fields) f where f->>'field'=s.field))) then
 raise exception 'Source or target is suppressed' using errcode='42501'; end if;
end $$;
revoke all on function ingestion.assert_not_suppressed(bigint,uuid,jsonb) from public,anon,authenticated,service_role;

create function ingestion.enforce_suppression() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_TABLE_NAME='organisations' then
  if NEW.is_public and exists(select 1 from ingestion.suppressions where organisation_id=NEW.org_id and field='*') then
   raise exception 'Withdrawn organisation cannot be made public' using errcode='42501'; end if;
 else
  if (to_jsonb(NEW)->TG_ARGV[0]) is distinct from 'null'::jsonb
  and exists(select 1 from ingestion.suppressions where organisation_id=NEW.org_id and field in ('*',TG_ARGV[0]))
  and (TG_OP='INSERT' or to_jsonb(NEW)->TG_ARGV[0] is distinct from to_jsonb(OLD)->TG_ARGV[0]) then
   raise exception 'Suppressed field cannot be restored' using errcode='42501'; end if;
 end if;
 return NEW;
end $$;
revoke all on function ingestion.enforce_suppression() from public,anon,authenticated,service_role;
create trigger enforce_import_withdrawal before insert or update on community_orgs.organisations
 for each row execute function ingestion.enforce_suppression();
create trigger enforce_abn_suppression before insert or update on community_orgs.legal_details
 for each row execute function ingestion.enforce_suppression('abn');
create trigger enforce_website_suppression before insert or update on community_orgs.contact_info
 for each row execute function ingestion.enforce_suppression('website');

create function community_orgs.ingestion_withdrawal_status(p_version text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare rec bigint; org uuid;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select record_id into rec from ingestion.source_record_versions where id=p_version::bigint;
 if not found then raise exception 'Version not found' using errcode='P0002'; end if;
 select organisation_id into org from ingestion.source_links where record_id=rec;
 return jsonb_build_object('organisation_id',org,'suppressions',
 (select coalesce(jsonb_agg(jsonb_build_object('field',field,'reason',reason,'suppressed_at',suppressed_at) order by suppressed_at),'[]')
 from ingestion.suppressions where record_id=rec or organisation_id=org));
end $$;

create function community_orgs.suppress_ingestion_content(p_run text,p_version text,p_field text,p_reason text,p_expected jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare rec bigint; org uuid; snapshot jsonb;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 if p_field is null or p_field not in ('*','abn','website') or p_reason is null or length(trim(p_reason)) not between 1 and 2000 then raise exception 'Invalid suppression' using errcode='22023'; end if;
 lock table community_orgs.organisations,community_orgs.legal_details,community_orgs.contact_info in share row exclusive mode;
 select sv.record_id into rec from ingestion.run_records rr join ingestion.source_record_versions sv on sv.id=rr.version_id
 where rr.run_id=p_run::bigint and rr.version_id=p_version::bigint;
 if not found then raise exception 'Record not in run' using errcode='P0002'; end if;
 select organisation_id into org from ingestion.source_links where record_id=rec;
 if p_expected->>'organisation_id' is distinct from org::text then raise exception 'Target changed; reload' using errcode='40001'; end if;
 if p_field<>'*' and org is not null then
  snapshot := community_orgs.ingestion_field_preview(p_run,p_version,org);
  if not exists(select 1 from jsonb_array_elements(snapshot->'fields') f where f=p_expected->'field' and f->>'field'=p_field and (f->>'target_rows')::int<=1) then
   raise exception 'Target field changed or ambiguous; reload' using errcode='40001'; end if;
 end if;
 insert into ingestion.suppressions(record_id,field,organisation_id,reason,suppressed_by)
 values(rec,p_field,org,trim(p_reason),auth.uid()) on conflict do nothing;
 if org is not null then
  case p_field
   when '*' then update community_orgs.organisations set is_public=false where org_id=org;
   when 'abn' then update community_orgs.legal_details set abn=null where org_id=org;
   when 'website' then update community_orgs.contact_info set website=null where org_id=org;
  end case;
 end if;
end $$;

create function community_orgs.organisation_source_attribution(p_organisation uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not community_orgs.can_view_org(p_organisation) or
 (community_orgs.user_has_verified_mfa() and (auth.jwt()->>'aal') is distinct from 'aal2') then return '[]'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.published_at desc),'[]') from (
 select s.source_id, s.resource_id,
 case when s.metadata->>'synthetic'='true' then 'Synthetic test data' else coalesce(s.metadata->>'public_title',s.source_id) end as title,
 s.metadata->>'public_url' as url,s.metadata->>'public_licence' as licence,s.metadata->>'public_licence_url' as licence_url,
 i.observed_at,p.published_at,f->>'field' as field,
 coalesce(fs.revision=(f->>'revision')::bigint+1,false) as unchanged_since_import
 from ingestion.publications p join ingestion.change_sets c on c.id=p.change_set_id
 join ingestion.ingestion_runs i on i.id=c.run_id join ingestion.sources s using(source_id,resource_id)
 join ingestion.source_record_versions sv on sv.id=c.version_id
 cross join lateral jsonb_array_elements(p.changes) f
 left join ingestion.field_state fs on fs.org_id=p.organisation_id and fs.table_name=f->>'table' and fs.field=f->>'field'
 where p.organisation_id=p_organisation and not exists(select 1 from ingestion.suppressions z
 where (z.record_id=sv.record_id or z.organisation_id=p.organisation_id) and z.field in ('*',f->>'field'))
 ) x);
end $$;
revoke all on function community_orgs.organisation_source_attribution(uuid) from public;
grant execute on function community_orgs.organisation_source_attribution(uuid) to anon,authenticated;
revoke all on function community_orgs.ingestion_withdrawal_status(text),community_orgs.suppress_ingestion_content(text,text,text,text,jsonb) from public,anon,service_role;
grant execute on function community_orgs.ingestion_withdrawal_status(text),community_orgs.suppress_ingestion_content(text,text,text,text,jsonb) to authenticated;

create or replace function community_orgs.approve_ingestion_fields(p_run text,p_version text,p_revision integer,p_fields jsonb,p_organisation uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare r ingestion.reviews; snapshot jsonb; f jsonb; approved jsonb := '[]'; result uuid;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into r from ingestion.reviews where version_id=p_version::bigint for update;
 if not found or r.revision is distinct from p_revision or r.organisation_id is distinct from p_organisation or r.decision not in ('link','create') then
  raise exception 'Review changed or not approved for a target' using errcode='40001'; end if;
 if jsonb_typeof(p_fields) is distinct from 'array' or jsonb_array_length(p_fields) not between 1 and 3 then
  raise exception 'Select one to three fields' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(p_fields) x group by x->>'field' having count(*)>1) then
  raise exception 'Duplicate fields' using errcode='22023'; end if;
 perform ingestion.assert_not_suppressed(p_version::bigint,r.organisation_id,p_fields);
 snapshot := community_orgs.ingestion_field_preview(p_run,p_version,r.organisation_id);
 for f in select value from jsonb_array_elements(p_fields) loop
  -- Compare the entire displayed snapshot, including target value/count/revision.
  if not exists(select 1 from jsonb_array_elements(snapshot->'fields') x where x=f and x->>'status' in ('new','changed') and x->'protected'='false'::jsonb) then
   raise exception 'Field changed or is not eligible; reload preview' using errcode='40001'; end if;
  if f->>'field'='abn' and (f->>'source_value') !~ '^[0-9]{11}$' then raise exception 'Invalid ABN format' using errcode='22023'; end if;
  if f->>'field'='website' and ((f->>'source_value') !~ '^https?://' or length(f->>'source_value')>255) then raise exception 'Invalid website' using errcode='22023'; end if;
  approved := approved || jsonb_build_array(f);
 end loop;
 if r.decision='create' and not approved @> '[{"field":"entity_name"}]'::jsonb then raise exception 'New organisation requires name' using errcode='22023'; end if;
 if not exists(select 1 from ingestion.ingestion_runs i join ingestion.sources s using(source_id,resource_id)
  where i.id=p_run::bigint and i.completion='complete' and s.enabled) then raise exception 'Complete enabled source required' using errcode='22023'; end if;
 insert into ingestion.change_sets(run_id,version_id,review_revision,organisation_id,fields,approved_by)
 values(p_run::bigint,p_version::bigint,r.revision,r.organisation_id,approved,auth.uid()) returning id into result;
 return result;
end $$;

create or replace function community_orgs.publish_ingestion_fields(p_change_set uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c ingestion.change_sets; r ingestion.reviews; f jsonb; snapshot jsonb; org uuid; rec bigint; linked uuid; name text;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 -- Pilot-scale coarse locks also exclude child-row inserts (including absent
 -- rows), deletes and human edits. Always acquire in the same order.
 lock table community_orgs.organisations, community_orgs.legal_details, community_orgs.contact_info in share row exclusive mode;
 select * into c from ingestion.change_sets where id=p_change_set for update;
 if not found then raise exception 'Approval not found' using errcode='P0002'; end if;
 perform ingestion.assert_not_suppressed(c.version_id,c.organisation_id,c.fields);
 select organisation_id into org from ingestion.publications where change_set_id=c.id;
 if found then return org; end if; -- Retry never writes again, even after human edits.
 select * into r from ingestion.reviews where version_id=c.version_id for update;
 if r.revision is distinct from c.review_revision or r.organisation_id is distinct from c.organisation_id or r.decision not in ('link','create') then
  raise exception 'Review changed; approve again' using errcode='40001'; end if;
 perform 1 from ingestion.sources s join ingestion.ingestion_runs i using(source_id,resource_id)
  where i.id=c.run_id and i.completion='complete' and s.enabled for share of s;
 if not found then raise exception 'Complete enabled source required' using errcode='22023'; end if;
 snapshot := community_orgs.ingestion_field_preview(c.run_id::text,c.version_id::text,c.organisation_id);
 for f in select value from jsonb_array_elements(c.fields) loop
  if not exists(select 1 from jsonb_array_elements(snapshot->'fields') x where x=f and x->>'status' in ('new','changed') and x->'protected'='false'::jsonb) then
   raise exception 'Target changed or protected; approve again' using errcode='40001'; end if;
 end loop;
 select record_id into rec from ingestion.source_record_versions where id=c.version_id;
 select organisation_id into linked from ingestion.source_links where record_id=rec;
 if linked is not null and linked is distinct from c.organisation_id then raise exception 'Source already linked to another target' using errcode='40001'; end if;
 org := c.organisation_id;
 if org is null then
  select x->>'source_value' into name from jsonb_array_elements(c.fields) x where x->>'field'='entity_name';
  org := gen_random_uuid();
  insert into ingestion.creation_targets(change_set_id,org_id) values(c.id,org);
  insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values(org,name,'import-'||org::text,true);
 end if;
 for f in select value from jsonb_array_elements(c.fields) loop
  case f->>'field'
   when 'entity_name' then update community_orgs.organisations set entity_name=f->>'source_value' where org_id=org;
   when 'abn' then
    update community_orgs.legal_details set abn=f->>'source_value' where org_id=org;
    if not found then insert into community_orgs.legal_details(org_id,abn) values(org,f->>'source_value'); end if;
   when 'website' then
    update community_orgs.contact_info set website=f->>'source_value' where org_id=org;
    if not found then insert into community_orgs.contact_info(org_id,website) values(org,f->>'source_value'); end if;
   else raise exception 'Unsupported field' using errcode='22023';
  end case;
 end loop;
 insert into ingestion.source_links values(rec,org) on conflict (record_id) do nothing;
 insert into ingestion.publications(change_set_id,organisation_id,published_by,changes) values(c.id,org,auth.uid(),c.fields);
 return org;
end $$;


create or replace function community_orgs.ingestion_field_preview(p_run text, p_version text, p_organisation uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a record; t text; current_value jsonb; n bigint; state ingestion.field_state;
 result jsonb := '[]'; status text; supported boolean; target_name text;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Ingestion operator access required' using errcode='42501';
 end if;
 if not exists(select 1 from ingestion.run_records where run_id=p_run::bigint and version_id=p_version::bigint) then
  raise exception 'Record not in selected run' using errcode='P0002';
 end if;
 if p_organisation is not null then
  select entity_name into target_name from community_orgs.organisations where org_id=p_organisation;
  if not found then raise exception 'Organisation not found' using errcode='P0002'; end if;
 end if;
 -- Include missing mapped assertions explicitly: absence is never a deletion.
 for a in
  select f.field, f.value, true as present from ingestion.field_assertions f where version_id=p_version::bigint
  union all
  select f, null::jsonb, false from unnest(array['entity_name','abn','website']) f
   where not exists(select 1 from ingestion.field_assertions x where x.version_id=p_version::bigint and x.field=f)
  order by 1
 loop
  t := case a.field when 'entity_name' then 'organisations' when 'abn' then 'legal_details' when 'website' then 'contact_info' end;
  current_value := null; n := 0; state := null;
  supported := t is not null;
  if supported and p_organisation is not null then
   -- Both identifiers are from the closed mapping above, never source input.
   execute format('select count(*), (jsonb_agg(to_jsonb(x.%I)))->0 from community_orgs.%I x where org_id=$1',a.field,t)
    into n,current_value using p_organisation;
   select * into state from ingestion.field_state where org_id=p_organisation and table_name=t and field=a.field;
  end if;
  status := case
   when exists(select 1 from ingestion.suppressions z where (z.record_id=(select record_id from ingestion.source_record_versions where id=p_version::bigint) or z.organisation_id=p_organisation) and z.field in ('*',a.field)) then 'suppressed'
   when not supported then 'unmapped'
   when not a.present or a.value='null'::jsonb then 'missing'
   when jsonb_typeof(a.value)<>'string' or length(trim(a.value #>> '{}'))=0 then 'invalid'
   when n>1 then 'ambiguous'
   when current_value is not distinct from a.value then 'unchanged'
   when coalesce(state.protected,false) then 'conflict'
   when current_value is null or current_value='null'::jsonb then 'new'
   else 'changed' end;
  result := result || jsonb_build_array(jsonb_build_object(
   'field',a.field,'table',t,'source_value',a.value,'current_value',case when n>1 then null else current_value end,
   'status',status,'protected',coalesce(state.protected,false),'revision',coalesce(state.revision,0)::text,
   'target_rows',n,'changed_at',state.changed_at));
 end loop;
 return jsonb_build_object('organisation_id',p_organisation,'organisation_name',target_name,'fields',result);
end $$;
revoke all on function community_orgs.ingestion_field_preview(text,text,uuid) from public, anon, service_role;
grant execute on function community_orgs.ingestion_field_preview(text,text,uuid) to authenticated;

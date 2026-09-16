create table ingestion.change_sets (
 id uuid primary key default gen_random_uuid(),
 run_id bigint not null references ingestion.ingestion_runs,
 version_id bigint not null references ingestion.source_record_versions,
 review_revision integer not null,
 organisation_id uuid references community_orgs.organisations,
 fields jsonb not null,
 approved_by uuid not null references auth.users,
 approved_at timestamptz not null default now()
);
create table ingestion.publications (
 change_set_id uuid primary key references ingestion.change_sets,
 organisation_id uuid not null references community_orgs.organisations,
 published_by uuid not null references auth.users,
 published_at timestamptz not null default now(),
 changes jsonb not null
);
create table ingestion.source_links (
 record_id bigint primary key references ingestion.source_records,
 organisation_id uuid not null references community_orgs.organisations
);
alter table ingestion.change_sets enable row level security;
alter table ingestion.publications enable row level security;
alter table ingestion.source_links enable row level security;
revoke all on ingestion.change_sets, ingestion.publications, ingestion.source_links from public, anon, authenticated, service_role;

-- A private, transactionally written marker distinguishes an imported creation
-- from the normal portal flow. No JWT/GUC flag that a caller could forge.
create table ingestion.creation_targets (
 change_set_id uuid primary key references ingestion.change_sets,
 org_id uuid unique not null
);
alter table ingestion.creation_targets enable row level security;
revoke all on ingestion.creation_targets from public, anon, authenticated, service_role;
create or replace function community_orgs.grant_owner_on_organisation_insert()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_owner_role_id uuid;
begin
 if auth.uid() is null or exists(select 1 from ingestion.creation_targets where org_id=NEW.org_id) then return NEW; end if;
 select id into v_owner_role_id from community_orgs.roles where name='owner' limit 1;
 if v_owner_role_id is null then return NEW; end if;
 insert into community_orgs.user_organisation_roles(user_id,organisation_id,role_id,granted_by,is_active)
 values(auth.uid(),NEW.org_id,v_owner_role_id,auth.uid(),true) on conflict do nothing;
 return NEW;
end $$;
revoke all on function community_orgs.grant_owner_on_organisation_insert() from public, anon, authenticated, service_role;

create function community_orgs.approve_ingestion_fields(p_run text,p_version text,p_revision integer,p_fields jsonb,p_organisation uuid default null)
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

create function community_orgs.publish_ingestion_fields(p_change_set uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c ingestion.change_sets; r ingestion.reviews; f jsonb; snapshot jsonb; org uuid; rec bigint; linked uuid; name text;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 -- Pilot-scale coarse locks also exclude child-row inserts (including absent
 -- rows), deletes and human edits. Always acquire in the same order.
 lock table community_orgs.organisations, community_orgs.legal_details, community_orgs.contact_info in share row exclusive mode;
 select * into c from ingestion.change_sets where id=p_change_set for update;
 if not found then raise exception 'Approval not found' using errcode='P0002'; end if;
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

create function community_orgs.ingestion_field_approvals(p_version text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.approved_at desc),'[]') from (
  select c.id,c.review_revision,c.organisation_id,c.fields,c.approved_at,p.published_at,p.organisation_id as published_organisation
  from ingestion.change_sets c left join ingestion.publications p on p.change_set_id=c.id
  where c.version_id=p_version::bigint order by c.approved_at desc limit 20
 ) x);
end $$;
revoke all on function community_orgs.approve_ingestion_fields(text,text,integer,jsonb,uuid), community_orgs.publish_ingestion_fields(uuid), community_orgs.ingestion_field_approvals(text) from public, anon, service_role;
grant execute on function community_orgs.approve_ingestion_fields(text,text,integer,jsonb,uuid), community_orgs.publish_ingestion_fields(uuid), community_orgs.ingestion_field_approvals(text) to authenticated;

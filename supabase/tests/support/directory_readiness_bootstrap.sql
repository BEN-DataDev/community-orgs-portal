-- Isolated PostgreSQL harness only; never apply to a deployed database.
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create schema extensions;
create schema community_orgs;
create table auth.users(id uuid primary key);
create function auth.jwt() returns jsonb language sql as $$
 select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
create function auth.uid() returns uuid language sql as $$ select (auth.jwt()->>'sub')::uuid $$;
create table community_orgs.organisations(
 org_id uuid primary key,entity_name text not null,slug text not null,description text,
 date_established date,is_public boolean not null
);
create table community_orgs.aliases(
 alias_id uuid primary key,org_id uuid references community_orgs.organisations,
 alias_type text,alias text
);
create table community_orgs.legal_details(
 legal_id uuid primary key,org_id uuid references community_orgs.organisations,
 entity_type text,abn text
);
create table community_orgs.contact_info(
 contact_id uuid primary key,org_id uuid references community_orgs.organisations,
 phone jsonb,email text
);
create table community_orgs.user_organisation_roles(
 user_id uuid,organisation_id uuid references community_orgs.organisations,
 is_active boolean,expires_at timestamptz
);
create function community_orgs.can_view_org(p_org_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from community_orgs.organisations o where o.org_id=p_org_id
  and (o.is_public or exists(select 1 from community_orgs.user_organisation_roles r
   where r.organisation_id=o.org_id and r.user_id=auth.uid() and r.is_active
    and (r.expires_at is null or r.expires_at>now())))) $$;
grant usage on schema community_orgs to anon,authenticated,service_role;
grant usage on schema auth to anon,authenticated;
grant select on community_orgs.organisations,community_orgs.aliases,
 community_orgs.legal_details,community_orgs.contact_info to anon,authenticated;
alter table community_orgs.organisations enable row level security;
alter table community_orgs.aliases enable row level security;
alter table community_orgs.legal_details enable row level security;
alter table community_orgs.contact_info enable row level security;
create policy "read visible organisations" on community_orgs.organisations for select
 using (community_orgs.can_view_org(org_id));
create policy "read visible aliases" on community_orgs.aliases for select
 using (community_orgs.can_view_org(org_id));
create policy "registered users read visible legal details" on community_orgs.legal_details
 for select using (auth.uid() is not null and community_orgs.can_view_org(org_id));
create policy "registered users read visible contact details" on community_orgs.contact_info
 for select using (auth.uid() is not null and community_orgs.can_view_org(org_id));

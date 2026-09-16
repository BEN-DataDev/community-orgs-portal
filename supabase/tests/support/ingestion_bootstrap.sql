-- Isolated PostgreSQL harness only; never apply to a deployed database.
-- Auth helpers emulate JWT/MFA claims; the real ingestion operator RPC is tested.
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create schema extensions;
create schema community_orgs;
create extension "uuid-ossp" with schema extensions;
create table auth.users(id uuid primary key);
create function auth.jwt() returns jsonb language sql as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
create function auth.uid() returns uuid language sql as $$ select (auth.jwt()->>'sub')::uuid $$;
create function community_orgs.user_has_verified_mfa() returns boolean language sql as $$ select coalesce((auth.jwt()->>'test_enrolled')::boolean,false) $$;
create function community_orgs.is_platform_admin() returns boolean language sql as $$ select false $$;
create table if not exists community_orgs.organisations (
    entity_name text not null,
    date_established date,
    created_at timestamp without time zone default current_timestamp,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    slug text not null,
    description text,
    org_id uuid default extensions.uuid_generate_v4() not null,
    is_public boolean default true not null,
    constraint organisations_pkey primary key (org_id),
    constraint organisations_slug_key unique (slug)
);
create table if not exists community_orgs.legal_details (
    entity_type text,
    abn text,
    acn text,
    acnc_status boolean,
    tax_concession_endorsement date,
    insurance_details jsonb,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    legal_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    charity_type text,
    incorporation_number text,
    incorporation_status boolean,
    incorporation_registration_date date,
    abn_status boolean,
    abn_activated date,
    abn_last_updated date,
    acnc_registered boolean,
    acnc_registered_date date,
    gst_concession_endorsement_date text,
    dgr_endorsement boolean,
    constraint legal_details_pkey primary key (legal_id)
);
create table if not exists community_orgs.contact_info (
    physical_address text,
    postal_address text,
    phone jsonb,
    email text,
    website character varying(255),
    social_media jsonb,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    contact_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint contact_info_pkey primary key (contact_id)
);
create table community_orgs.roles(id uuid primary key default gen_random_uuid(),name text);
create table community_orgs.user_organisation_roles(user_id uuid,organisation_id uuid,role_id uuid,granted_by uuid,is_active boolean);
create function community_orgs.can_view_org(p_org uuid) returns boolean language sql as $$ select exists(select 1 from community_orgs.organisations where org_id=p_org and is_public) $$;
grant usage on schema auth,community_orgs to anon,authenticated;
grant select,insert,update,delete on all tables in schema community_orgs to authenticated;
grant select on community_orgs.organisations to anon;
-- Model the public visibility policy used by register-details reads.
alter table community_orgs.organisations enable row level security;
create policy public_org_read on community_orgs.organisations for select to anon using(is_public);
create policy test_authenticated_org on community_orgs.organisations to authenticated using(true) with check(true);

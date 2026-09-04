-- Baseline schema for the `community_orgs` schema.
--
-- Everything in this file already existed in the live database before any
-- migration in this directory was written: the tables were created by hand
-- through the Supabase dashboard and never captured in version control. Audit
-- finding 02 ("the database schema and its RLS policies are not in version
-- control") is what this file closes. It is dated ahead of every other
-- migration so that `supabase db reset` builds the schema in the right order:
-- this file first, then the incremental migrations that follow.
--
-- It is registered as already-applied on the linked project, so it will not be
-- re-run there. It exists to make a fresh environment reproducible.
--
-- Reconstructed from the live catalogs (pg_class, pg_constraint, pg_indexes,
-- pg_proc, pg_trigger, pg_policies, pg_class.relacl) rather than dumped with
-- `supabase db pull`, which needs a direct database password this project does
-- not have on hand. Two deliberate departures from a literal dump:
--
--   1. `uuid_generate_v4()` and the PostGIS types are schema-qualified as
--      `extensions.*`. The live defaults are unqualified, which only resolves
--      because of the session search_path. Qualifying them makes this file
--      correct under `set search_path = ''`.
--   2. Objects created by the later migrations are NOT repeated here — the
--      `documents` and `locations` tables, `financial_info.last_audit_date`,
--      `legal_details.last_annual_return_date`, the `can_view_org` /
--      `can_edit_org` / `org_id_for_legal` helpers, the owner-grant trigger,
--      and every policy added from 20260904111936 onward.
--
-- KNOWN-BROKEN LEGACY, reproduced as-is rather than silently fixed. These
-- predate the migration history and none of them are called by the
-- application; correcting or dropping them belongs in its own migration:
--
--   * `set_organization_slug` (US spelling) reads NEW.name; the column is
--     entity_name. No trigger uses it — `set_organisation_slug` is the live one.
--   * `get_user_all_roles` and `get_user_organisations_with_roles` select
--     o.id / o.name from organisations, whose columns are org_id / entity_name.
--   * `expire_roles`, `grant_user_role` and `revoke_user_role` write
--     role_audit_log.organisation_id; the column is spelled organization_id.
--     `expire_roles` also selects from `community_orgs.expired_roles`, which is
--     a CTE and cannot be schema-qualified.
--   * `user_has_inherited_permission` reads an unqualified `roles`, which will
--     not resolve under a locked search_path.
--   * `resources_assets` carries two identical last_edited_at triggers.

create schema if not exists community_orgs;

create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists postgis with schema extensions;


-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

do $$
begin
    if not exists (
        select 1 from pg_type t
        join pg_namespace n on n.oid = t.typnamespace
        where n.nspname = 'community_orgs' and t.typname = 'alias_type_enum'
    ) then
        create type community_orgs.alias_type_enum as enum ('Business Name', 'Trading Name');
    end if;
end
$$;


-- ---------------------------------------------------------------------------
-- Tables
--
-- Columns are in physical order, which is the order the live tables have them.
-- Foreign keys are added at the end of this section so the tables can be
-- created in any order.
-- ---------------------------------------------------------------------------

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

create table if not exists community_orgs.roles (
    id uuid default gen_random_uuid() not null,
    name text not null,
    description text,
    permissions jsonb default '{}'::jsonb,
    hierarchy_level integer default 0,
    is_system_role boolean default false,
    created_at timestamp with time zone default now(),
    constraint roles_pkey primary key (id)
);

create table if not exists community_orgs.user_organisation_roles (
    id uuid default gen_random_uuid() not null,
    user_id uuid not null,
    organisation_id uuid not null,
    role_id uuid not null,
    granted_by uuid,
    granted_at timestamp with time zone default now(),
    expires_at timestamp with time zone,
    is_active boolean default true,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),
    constraint user_organisation_roles_pkey primary key (id),
    constraint user_organisation_roles_user_id_organisation_id_role_id_key
        unique (user_id, organisation_id, role_id)
);

create table if not exists community_orgs.role_audit_log (
    id uuid default gen_random_uuid() not null,
    user_id uuid not null,
    organization_id uuid not null,
    role_id uuid not null,
    action text not null,
    performed_by uuid,
    reason text,
    created_at timestamp with time zone default now(),
    constraint role_audit_log_pkey primary key (id),
    constraint role_audit_log_action_check
        check (action = any (array['granted'::text, 'revoked'::text, 'expired'::text]))
);

create table if not exists community_orgs.role_requests (
    id uuid default gen_random_uuid() not null,
    user_id uuid not null,
    organisation_id uuid not null,
    role_id uuid not null,
    message text,
    status text default 'pending'::text,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),
    constraint role_requests_pkey primary key (id),
    constraint role_requests_status_check
        check (status = any (array['pending'::text, 'approved'::text, 'rejected'::text]))
);

create table if not exists community_orgs.accreditation (
    certification_type text,
    issuing_body text,
    valid_from date,
    valid_until date,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    accreditation_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint accreditation_pkey primary key (accreditation_id)
);

create table if not exists community_orgs.aliases (
    alias_type community_orgs.alias_type_enum,
    alias text,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    alias_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint aliases_pkey primary key (alias_id)
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

-- One endorsement per legal record, hence the unique constraint on legal_id.
create table if not exists community_orgs.dgr_endorsement (
    endorsement_start_date date,
    endorsement_end_date date,
    dgr_items text,
    dgr_funds text,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    endorsement_id uuid default extensions.uuid_generate_v4() not null,
    legal_id uuid,
    constraint dgr_endorsement_pkey primary key (endorsement_id),
    constraint dgr_endorsement_legal_id_key unique (legal_id)
);

create table if not exists community_orgs.financial_info (
    funding_sources text[],
    annual_budget numeric(15, 2),
    financial_year_end date,
    auditor_details jsonb,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    finance_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint financial_info_pkey primary key (finance_id)
);

create table if not exists community_orgs.governance (
    board_structure jsonb,
    constitution text,
    org_chart text,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    governance_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint governance_pkey primary key (governance_id)
);

create table if not exists community_orgs.historical_info (
    founding_members text[],
    milestone_date date,
    milestone_description text,
    structural_changes jsonb,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    history_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint historical_info_pkey primary key (history_id)
);

create table if not exists community_orgs.operational_details (
    service_area text,
    target_demographics text,
    operating_hours jsonb,
    staff_count_paid integer,
    staff_count_volunteer integer,
    languages_supported text[],
    accessibility_features text[],
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    op_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint operational_details_pkey primary key (op_id)
);

create table if not exists community_orgs.org_members (
    user_id uuid,
    role text,
    created_at timestamp with time zone default current_timestamp,
    member_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    constraint org_members_pkey primary key (member_id),
    constraint org_members_role_check
        check (role = any (array['admin'::text, 'member'::text, 'viewer'::text]))
);

create table if not exists community_orgs.org_visibility (
    visibility_type text,
    allowed_org_ids integer[],
    created_at timestamp with time zone default current_timestamp,
    visibility_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    constraint org_visibility_pkey primary key (visibility_id),
    constraint org_visibility_visibility_type_check
        check (visibility_type = any (array['public'::text, 'limited'::text, 'restricted'::text]))
);

create table if not exists community_orgs.performance_metrics (
    metric_type text,
    metric_value jsonb,
    measurement_date date,
    reporting_period text,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    metric_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint performance_metrics_pkey primary key (metric_id)
);

create table if not exists community_orgs.programs_services (
    program_name text,
    description text,
    fee_structure jsonb,
    delivery_location text[],
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    program_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint programs_services_pkey primary key (program_id)
);

create table if not exists community_orgs.relationships (
    partner_org text,
    relationship_type text,
    start_date date,
    end_date date,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    relationship_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint relationships_pkey primary key (relationship_id)
);

create table if not exists community_orgs.resources_assets (
    asset_type text,
    asset_description text,
    acquisition_date date,
    asset_value numeric(15, 2),
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid,
    last_edited_by uuid,
    asset_id uuid default extensions.uuid_generate_v4() not null,
    org_id uuid,
    constraint resources_assets_pkey primary key (asset_id)
);

-- Slugs the application must never hand out, enforced by check_slug_not_reserved.
create table if not exists community_orgs.reserved_slugs (
    slug text not null,
    constraint reserved_slugs_pkey primary key (slug)
);


-- ---------------------------------------------------------------------------
-- Foreign keys
--
-- `organizations_*_fkey` on organisations keeps the US spelling the live
-- database has. Renaming it is a behaviour-free change that still does not
-- belong in a baseline.
-- ---------------------------------------------------------------------------

do $$
declare
    t text;
begin
    -- Every content table hangs off organisations and carries the same two
    -- audit-user foreign keys, so they are added in a loop rather than spelled
    -- out sixteen times.
    foreach t in array array[
        'accreditation', 'aliases', 'contact_info', 'financial_info',
        'governance', 'historical_info', 'legal_details', 'operational_details',
        'org_members', 'org_visibility', 'performance_metrics',
        'programs_services', 'relationships', 'resources_assets'
    ]
    loop
        if not exists (
            select 1 from pg_constraint con
            join pg_class c on c.oid = con.conrelid
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'community_orgs' and c.relname = t
              and con.conname = t || '_org_id_fkey'
        ) then
            execute format(
                'alter table community_orgs.%I add constraint %I '
                'foreign key (org_id) references community_orgs.organisations (org_id)',
                t, t || '_org_id_fkey');
        end if;

        if not exists (
            select 1 from pg_constraint con
            join pg_class c on c.oid = con.conrelid
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'community_orgs' and c.relname = t
              and con.conname = t || '_inserted_by_fkey'
        ) then
            execute format(
                'alter table community_orgs.%I add constraint %I '
                'foreign key (inserted_by) references auth.users (id)',
                t, t || '_inserted_by_fkey');
        end if;

        if not exists (
            select 1 from pg_constraint con
            join pg_class c on c.oid = con.conrelid
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'community_orgs' and c.relname = t
              and con.conname = t || '_last_edited_by_fkey'
        ) then
            execute format(
                'alter table community_orgs.%I add constraint %I '
                'foreign key (last_edited_by) references auth.users (id)',
                t, t || '_last_edited_by_fkey');
        end if;
    end loop;
end
$$;

do $$
begin
    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'organizations_inserted_by_fkey') then
        alter table community_orgs.organisations
            add constraint organizations_inserted_by_fkey
            foreign key (inserted_by) references auth.users (id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'organizations_last_edited_by_fkey') then
        alter table community_orgs.organisations
            add constraint organizations_last_edited_by_fkey
            foreign key (last_edited_by) references auth.users (id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'dgr_endorsement_legal_id_fkey') then
        alter table community_orgs.dgr_endorsement
            add constraint dgr_endorsement_legal_id_fkey
            foreign key (legal_id) references community_orgs.legal_details (legal_id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'dgr_endorsement_inserted_by_fkey') then
        alter table community_orgs.dgr_endorsement
            add constraint dgr_endorsement_inserted_by_fkey
            foreign key (inserted_by) references auth.users (id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'dgr_endorsement_last_edited_by_fkey') then
        alter table community_orgs.dgr_endorsement
            add constraint dgr_endorsement_last_edited_by_fkey
            foreign key (last_edited_by) references auth.users (id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'user_organisation_roles_user_id_fkey') then
        alter table community_orgs.user_organisation_roles
            add constraint user_organisation_roles_user_id_fkey
            foreign key (user_id) references auth.users (id) on delete cascade;
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'user_organisation_roles_organisation_id_fkey') then
        alter table community_orgs.user_organisation_roles
            add constraint user_organisation_roles_organisation_id_fkey
            foreign key (organisation_id) references community_orgs.organisations (org_id) on delete cascade;
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'user_organisation_roles_role_id_fkey') then
        alter table community_orgs.user_organisation_roles
            add constraint user_organisation_roles_role_id_fkey
            foreign key (role_id) references community_orgs.roles (id) on delete cascade;
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'user_organisation_roles_granted_by_fkey') then
        alter table community_orgs.user_organisation_roles
            add constraint user_organisation_roles_granted_by_fkey
            foreign key (granted_by) references auth.users (id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'role_audit_log_user_id_fkey') then
        alter table community_orgs.role_audit_log
            add constraint role_audit_log_user_id_fkey
            foreign key (user_id) references auth.users (id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'role_audit_log_organization_id_fkey') then
        alter table community_orgs.role_audit_log
            add constraint role_audit_log_organization_id_fkey
            foreign key (organization_id) references community_orgs.organisations (org_id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'role_audit_log_role_id_fkey') then
        alter table community_orgs.role_audit_log
            add constraint role_audit_log_role_id_fkey
            foreign key (role_id) references community_orgs.roles (id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'role_audit_log_performed_by_fkey') then
        alter table community_orgs.role_audit_log
            add constraint role_audit_log_performed_by_fkey
            foreign key (performed_by) references auth.users (id);
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'role_requests_user_id_fkey') then
        alter table community_orgs.role_requests
            add constraint role_requests_user_id_fkey
            foreign key (user_id) references auth.users (id) on delete cascade;
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'role_requests_organisation_id_fkey') then
        alter table community_orgs.role_requests
            add constraint role_requests_organisation_id_fkey
            foreign key (organisation_id) references community_orgs.organisations (org_id) on delete cascade;
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'role_requests_role_id_fkey') then
        alter table community_orgs.role_requests
            add constraint role_requests_role_id_fkey
            foreign key (role_id) references community_orgs.roles (id) on delete cascade;
    end if;

    if not exists (select 1 from pg_constraint con join pg_class c on c.oid = con.conrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'community_orgs' and con.conname = 'role_requests_reviewed_by_fkey') then
        alter table community_orgs.role_requests
            add constraint role_requests_reviewed_by_fkey
            foreign key (reviewed_by) references auth.users (id);
    end if;
end
$$;


-- ---------------------------------------------------------------------------
-- Indexes
--
-- These are the three the live database has beyond the constraint-backed ones.
-- The org_id foreign keys on the content tables are notably unindexed; adding
-- them is a real improvement but a change, not a baseline.
-- ---------------------------------------------------------------------------

create index if not exists idx_org_legal_name on community_orgs.organisations using btree (entity_name);
create index if not exists idx_org_date on community_orgs.organisations using btree (date_established);
create index if not exists idx_organisations_public on community_orgs.organisations using btree (is_public) where (is_public = true);
create index if not exists idx_org_abn on community_orgs.legal_details using btree (abn);


-- ---------------------------------------------------------------------------
-- Functions
-- ---------------------------------------------------------------------------

-- Stamps last_edited_at on every update.
create or replace function community_orgs.update_last_edited_at()
returns trigger
language plpgsql
as $function$
BEGIN
    NEW.last_edited_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$function$;

-- Sets the audit-user columns from the session rather than the request body.
create or replace function community_orgs.update_user_tracking()
returns trigger
language plpgsql
as $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.inserted_by = auth.uid();
        NEW.last_edited_by = auth.uid();
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.last_edited_by = auth.uid();
    END IF;
    RETURN NEW;
END;
$function$;

create or replace function community_orgs.check_slug_not_reserved()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
BEGIN
  IF EXISTS (SELECT 1 FROM community_orgs.reserved_slugs WHERE slug = NEW.slug) THEN
    RAISE EXCEPTION 'The slug "%" is reserved and cannot be used', NEW.slug;
  END IF;
  RETURN NEW;
END;
$function$;

-- Replaced in 20260904114029 to add SECURITY DEFINER and a locked search_path.
create or replace function community_orgs.generate_unique_slug(base_slug text)
returns text
language plpgsql
as $function$
DECLARE
    counter INTEGER := 0;
    test_slug TEXT := base_slug;
BEGIN
    WHILE EXISTS (SELECT 1 FROM community_orgs.organisations WHERE slug = test_slug) LOOP
        counter := counter + 1;
        test_slug := base_slug || '-' || counter;
    END LOOP;

    RETURN test_slug;
END;
$function$;

-- Replaced in 20260904114029, which fixes NEW.name -> NEW.entity_name.
create or replace function community_orgs.set_organisation_slug()
returns trigger
language plpgsql
security definer
as $function$
BEGIN
    IF NEW.slug IS NULL OR NEW.slug = '' THEN
        NEW.slug := community_orgs.generate_unique_slug(
            regexp_replace(
                lower(trim(NEW.name)),
                '[^a-z0-9]+',
                '-',
                'g'
            )
        );
    END IF;
    RETURN NEW;
END;
$function$;

-- Legacy US-spelled duplicate of the above. No trigger references it.
create or replace function community_orgs.set_organization_slug()
returns trigger
language plpgsql
security definer
as $function$
BEGIN
    IF NEW.slug IS NULL OR NEW.slug = '' THEN
        NEW.slug := community_orgs.generate_unique_slug(
            regexp_replace(
                lower(trim(NEW.name)),
                '[^a-z0-9]+',
                '-',
                'g'
            )
        );
    END IF;
    RETURN NEW;
END;
$function$;

-- The permission test the RLS helpers and the application both go through.
create or replace function community_orgs.user_has_permission(p_user_id uuid, p_organisation_id uuid, p_permission text)
returns boolean
language plpgsql
security definer
as $function$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM community_orgs.user_organisation_roles uor
        JOIN community_orgs.roles r ON uor.role_id = r.id
        WHERE uor.user_id = p_user_id
        AND uor.organisation_id = p_organisation_id
        AND uor.is_active = true
        AND (uor.expires_at IS NULL OR uor.expires_at > NOW())
        AND r.permissions->>p_permission = 'true'
    );
END;
$function$;

create or replace function community_orgs.user_has_inherited_permission(p_user_id uuid, p_organisation_id uuid, p_permission text)
returns boolean
language plpgsql
security definer
as $function$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM community_orgs.user_organisation_roles uor
        JOIN community_orgs.roles r ON uor.role_id = r.id
        WHERE uor.user_id = p_user_id
        AND uor.organisation_id = p_organisation_id
        AND uor.is_active = true
        AND (uor.expires_at IS NULL OR uor.expires_at > NOW())
        AND (
            r.permissions->>p_permission = 'true' OR
            r.hierarchy_level >= (
                SELECT MIN(r2.hierarchy_level)
                FROM roles r2
                WHERE r2.permissions->>p_permission = 'true'
            )
        )
    );
END;
$function$;

create or replace function community_orgs.user_max_role_level(p_user_id uuid, p_organisation_id uuid)
returns integer
language plpgsql
security definer
as $function$
BEGIN
    RETURN COALESCE(
        (SELECT MAX(r.hierarchy_level)
         FROM community_orgs.user_organisation_roles uor
         JOIN community_orgs.roles r ON uor.role_id = r.id
         WHERE uor.user_id = p_user_id
         AND uor.organisation_id = p_organisation_id
         AND uor.is_active = true
         AND (uor.expires_at IS NULL OR uor.expires_at > NOW())),
        0
    );
END;
$function$;

create or replace function community_orgs.get_user_all_roles(p_user_id uuid)
returns table(organisation_id uuid, organisation_name text, role_id uuid, role_name text, permissions jsonb, hierarchy_level integer, granted_at timestamp with time zone, expires_at timestamp with time zone)
language plpgsql
security definer
as $function$
BEGIN
    RETURN QUERY
    SELECT
        o.id,
        o.name,
        r.id,
        r.name,
        r.permissions,
        r.hierarchy_level,
        uor.granted_at,
        uor.expires_at
    FROM community_orgs.user_organisation_roles uor
    JOIN community_orgs.organisations o ON uor.organisation_id = o.id
    JOIN community_orgs.roles r ON uor.role_id = r.id
    WHERE uor.user_id = p_user_id
    AND uor.is_active = true
    AND (uor.expires_at IS NULL OR uor.expires_at > NOW())
    ORDER BY o.name, r.hierarchy_level DESC;
END;
$function$;

create or replace function community_orgs.get_user_organisations_with_roles(p_user_id uuid)
returns table(organisation_id uuid, organisation_name text, organisation_slug text, role_names text[], permissions jsonb, max_hierarchy_level integer)
language plpgsql
security definer
as $function$
BEGIN
    RETURN QUERY
    SELECT
        o.id,
        o.name,
        o.slug,
        ARRAY_AGG(r.name) as role_names,
        JSONB_OBJECT_AGG(r.name, r.permissions) as permissions,
        MAX(r.hierarchy_level) as max_hierarchy_level
    FROM community_orgs.organisations o
    JOIN community_orgs.user_organisation_roles uor ON o.id = uor.organisation_id
    JOIN community_orgs.roles r ON uor.role_id = r.id
    WHERE uor.user_id = p_user_id
    AND uor.is_active = true
    AND (uor.expires_at IS NULL OR uor.expires_at > NOW())
    GROUP BY o.id, o.name, o.slug
    ORDER BY o.name;
END;
$function$;

create or replace function community_orgs.grant_user_role(p_user_id uuid, p_organisation_id uuid, p_role_id uuid, p_granted_by uuid, p_expires_at timestamp with time zone default null::timestamp with time zone)
returns uuid
language plpgsql
security definer
as $function$
DECLARE
    v_role_assignment_id UUID;
BEGIN
    -- Insert or update role assignment
    INSERT INTO community_orgs.user_organisation_roles (user_id, organisation_id, role_id, granted_by, expires_at)
    VALUES (p_user_id, p_organisation_id, p_role_id, p_granted_by, p_expires_at)
    ON CONFLICT (user_id, organisation_id, role_id)
    DO UPDATE SET
        is_active = true,
        granted_by = p_granted_by,
        expires_at = p_expires_at,
        updated_at = NOW()
    RETURNING id INTO v_role_assignment_id;

    -- Log the action
    INSERT INTO community_orgs.role_audit_log (user_id, organisation_id, role_id, action, performed_by)
    VALUES (p_user_id, p_organisation_id, p_role_id, 'granted', p_granted_by);

    RETURN v_role_assignment_id;
END;
$function$;

create or replace function community_orgs.revoke_user_role(p_user_id uuid, p_organisation_id uuid, p_role_id uuid, p_revoked_by uuid, p_reason text default null::text)
returns boolean
language plpgsql
security definer
as $function$
BEGIN
    -- Deactivate role
    UPDATE community_orgs.user_organisation_roles
    SET is_active = false, updated_at = NOW()
    WHERE user_id = p_user_id
    AND organisation_id = p_organisation_id
    AND role_id = p_role_id;

    -- Log the revocation
    INSERT INTO community_orgs.role_audit_log (user_id, organisation_id, role_id, action, performed_by, reason)
    VALUES (p_user_id, p_organisation_id, p_role_id, 'revoked', p_revoked_by, p_reason);

    RETURN FOUND;
END;
$function$;

create or replace function community_orgs.expire_roles()
returns integer
language plpgsql
as $function$
DECLARE
    v_expired_count INTEGER;
BEGIN
    WITH expired_roles AS (
        UPDATE community_orgs.user_organisation_roles
        SET is_active = false, updated_at = NOW()
        WHERE expires_at < NOW() AND is_active = true
        RETURNING user_id, organisation_id, role_id
    )
    INSERT INTO community_orgs.role_audit_log (user_id, organisation_id, role_id, action, performed_by)
    SELECT user_id, organisation_id, role_id, 'expired', NULL
    FROM community_orgs.expired_roles;

    GET DIAGNOSTICS v_expired_count = ROW_COUNT;
    RETURN v_expired_count;
END;
$function$;

create or replace function community_orgs.request_role(p_user_id uuid, p_organisation_id uuid, p_role_id uuid, p_message text default null::text)
returns uuid
language plpgsql
security definer
as $function$
DECLARE
    v_request_id UUID;
BEGIN
    INSERT INTO community_orgs.role_requests (user_id, organisation_id, role_id, message)
    VALUES (p_user_id, p_organisation_id, p_role_id, p_message)
    RETURNING id INTO v_request_id;

    RETURN v_request_id;
END;
$function$;

create or replace function community_orgs.process_role_request(p_request_id uuid, p_reviewer_id uuid, p_status text, p_expires_at timestamp with time zone default null::timestamp with time zone)
returns boolean
language plpgsql
security definer
as $function$
DECLARE
    v_request community_orgs.role_requests%ROWTYPE;
BEGIN
    -- Get request details
    SELECT * INTO v_request FROM community_orgs.role_requests WHERE id = p_request_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Update request status
    UPDATE community_orgs.role_requests
    SET status = p_status, reviewed_by = p_reviewer_id, reviewed_at = NOW()
    WHERE id = p_request_id;

    -- If approved, grant the role
    IF p_status = 'approved' THEN
        PERFORM grant_user_role(
            v_request.user_id,
            v_request.organisation_id,
            v_request.role_id,
            p_reviewer_id,
            p_expires_at
        );
    END IF;

    RETURN TRUE;
END;
$function$;


-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

do $$
declare
    t text;
begin
    -- Every table with audit columns gets the same pair.
    foreach t in array array[
        'accreditation', 'contact_info', 'financial_info', 'governance',
        'historical_info', 'legal_details', 'operational_details',
        'org_members', 'org_visibility', 'organisations',
        'performance_metrics', 'programs_services', 'relationships',
        'resources_assets'
    ]
    loop
        execute format('drop trigger if exists track_%s_users on community_orgs.%I', t, t);
        execute format(
            'create trigger track_%s_users before insert or update on community_orgs.%I '
            'for each row execute function community_orgs.update_user_tracking()', t, t);

        execute format('drop trigger if exists update_%s_timestamp on community_orgs.%I', t, t);
        execute format(
            'create trigger update_%s_timestamp before update on community_orgs.%I '
            'for each row execute function community_orgs.update_last_edited_at()', t, t);
    end loop;
end
$$;

-- A second, redundant copy of update_resources_assets_timestamp that the live
-- database carries under a misleading name.
drop trigger if exists update_alias_timestamp on community_orgs.resources_assets;
create trigger update_alias_timestamp
    before update on community_orgs.resources_assets
    for each row execute function community_orgs.update_last_edited_at();

drop trigger if exists organisation_slug_trigger on community_orgs.organisations;
create trigger organisation_slug_trigger
    before insert or update on community_orgs.organisations
    for each row execute function community_orgs.set_organisation_slug();

drop trigger if exists enforce_slug_not_reserved on community_orgs.organisations;
create trigger enforce_slug_not_reserved
    before insert or update on community_orgs.organisations
    for each row execute function community_orgs.check_slug_not_reserved();


-- ---------------------------------------------------------------------------
-- Row-level security as it stood before the migration history began.
--
-- Only these three tables had RLS on. The other twenty were reachable in full
-- through PostgREST with the anon key until 20260904114055 turned RLS on for
-- them; that is audit finding 01/02 and is fixed there, not here.
--
-- `role_requests` has RLS enabled and no policy at all, which denies every
-- client. Its request/approve path runs through SECURITY DEFINER functions.
-- ---------------------------------------------------------------------------

alter table community_orgs.organisations enable row level security;

drop policy if exists "Public organisations are viewable by everyone" on community_orgs.organisations;
create policy "Public organisations are viewable by everyone"
    on community_orgs.organisations
    for select
    using (is_public = true);

-- Superseded in 20260904111936 by a SECURITY DEFINER equivalent: this version
-- selects from user_organisation_roles, whose own policy then selected from
-- user_organisation_roles, giving 42P17 infinite recursion.
drop policy if exists "organisation members can view private organisations" on community_orgs.organisations;
create policy "organisation members can view private organisations"
    on community_orgs.organisations
    for select
    using (
        (not is_public)
        and exists (
            select 1
            from community_orgs.user_organisation_roles
            where user_organisation_roles.organisation_id = organisations.org_id
              and user_organisation_roles.user_id = auth.uid()
              and user_organisation_roles.is_active = true
        )
    );

alter table community_orgs.user_organisation_roles enable row level security;

drop policy if exists "Users can view their own roles" on community_orgs.user_organisation_roles;
create policy "Users can view their own roles"
    on community_orgs.user_organisation_roles
    for select
    using (user_id = auth.uid());

alter table community_orgs.role_requests enable row level security;


-- ---------------------------------------------------------------------------
-- Grants
--
-- The Supabase default: usage on the schema and full DML to the three API
-- roles, with row-level security — not the grants — deciding what each role can
-- actually see. Without these, PostgREST cannot reach the schema at all.
-- ---------------------------------------------------------------------------

grant usage on schema community_orgs to anon, authenticated, service_role;

grant all on all tables in schema community_orgs to anon, authenticated, service_role;
grant all on all sequences in schema community_orgs to anon, authenticated, service_role;
grant all on all functions in schema community_orgs to anon, authenticated, service_role;

alter default privileges in schema community_orgs
    grant all on tables to anon, authenticated, service_role;
alter default privileges in schema community_orgs
    grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema community_orgs
    grant execute on functions to anon, authenticated, service_role;


-- ---------------------------------------------------------------------------
-- Reference data
--
-- Not sample data: the application depends on both of these. The owner-grant
-- trigger added in 20260904114029 looks up the 'owner' row by name, and
-- `user_has_permission` reads the permissions payloads. `roles.name` has no
-- unique constraint, so the inserts guard themselves instead of using
-- ON CONFLICT.
-- ---------------------------------------------------------------------------

insert into community_orgs.roles (name, description, permissions, hierarchy_level, is_system_role)
select v.name, v.description, v.permissions::jsonb, v.hierarchy_level, false
from (values
    ('owner', 'organisation owner', '{"can_manage_members": true, "can_view_community": true, "can_moderate_content": true, "can_delete_organisation": true}', 4),
    ('admin', 'organisation administrator', '{"can_manage_members": true, "can_view_community": true, "can_moderate_content": true}', 3),
    ('moderator', 'Community moderator', '{"can_view_community": true, "can_moderate_content": true}', 2),
    ('member', 'Basic member access', '{"can_view_community": true}', 1)
) as v(name, description, permissions, hierarchy_level)
where not exists (
    select 1 from community_orgs.roles r where r.name = v.name
);

insert into community_orgs.reserved_slugs (slug)
values ('admin'), ('api'), ('create'), ('delete'), ('edit'),
       ('ftp'), ('mail'), ('new'), ('settings'), ('www')
on conflict (slug) do nothing;

-- Documents attached to an organisation (constitutions, certificates, policies).
-- Backs the "Legal Documents" list that the UI previously read from a
-- non-existent `legal_details.documents` column.
create table if not exists community_orgs.documents (
    document_id uuid primary key default extensions.uuid_generate_v4(),
    org_id uuid references community_orgs.organisations (org_id) on delete cascade,
    category text not null default 'legal',
    name text not null,
    url text not null,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid references auth.users (id),
    last_edited_by uuid references auth.users (id)
);

create index if not exists documents_org_id_idx on community_orgs.documents (org_id);

-- Physical locations an organisation operates from. Backs the operations map,
-- which previously read a `locations` embed that had no table behind it.
--
-- `longitude` / `latitude` are what the application writes; `geom` is derived
-- from them so PostGIS spatial queries and the GIST index work without the
-- client having to construct geometry.
create table if not exists community_orgs.locations (
    location_id uuid primary key default extensions.uuid_generate_v4(),
    org_id uuid references community_orgs.organisations (org_id) on delete cascade,
    name text not null,
    address text,
    location_type text,
    longitude double precision,
    latitude double precision,
    geom extensions.geometry (Point, 4326) generated always as (
        extensions.st_setsrid(extensions.st_makepoint(longitude, latitude), 4326)
    ) stored,
    inserted_at timestamp without time zone default current_timestamp,
    last_edited_at timestamp without time zone default current_timestamp,
    inserted_by uuid references auth.users (id),
    last_edited_by uuid references auth.users (id)
);

create index if not exists locations_org_id_idx on community_orgs.locations (org_id);
create index if not exists locations_geom_idx on community_orgs.locations using gist (geom);

-- Scalar dates the UI showed but the schema had no column for.
alter table community_orgs.financial_info
    add column if not exists last_audit_date date;

alter table community_orgs.legal_details
    add column if not exists last_annual_return_date date;

-- F02 storage only. Publication and per-fact attribution/suppression wiring follow in F03.
-- Browser roles cannot write or enable visibility; acquisition workers cannot access this table.
create function community_orgs.acnc_object_valid(value jsonb, allowed text[], kind text)
returns boolean language sql immutable set search_path = '' as $$
 select jsonb_typeof(value) = 'object' and not exists (
   select 1 from jsonb_each(case when jsonb_typeof(value) = 'object' then value else '{}' end) e
   where not (e.key = any(allowed)) or jsonb_typeof(e.value) not in (kind, 'null')
 );
$$;
create function community_orgs.acnc_calendar_valid(value jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
begin
 if value is null then return true; end if;
 if jsonb_typeof(value) <> 'object' or not (value ?& array['month','day'])
    or value - 'month' - 'day' <> '{}'::jsonb
    or (value->>'month') !~ '^[0-9]+$' or (value->>'day') !~ '^[0-9]+$'
    or jsonb_typeof(value->'month') <> 'number' or jsonb_typeof(value->'day') <> 'number'
 then return false; end if;
 perform make_date(2000, (value->>'month')::integer, (value->>'day')::integer);
 return true;
exception when others then return false;
end;
$$;
create table community_orgs.acnc_register_details (
 org_id uuid not null references community_orgs.organisations(org_id) on delete cascade,
 source_record_id bigint not null references ingestion.source_records(id),
 is_public boolean not null default false,
 other_names_text text,
 charity_size text,
 responsible_person_count integer check (responsible_person_count >= 0),
 financial_year_end jsonb check (community_orgs.acnc_calendar_valid(financial_year_end)),
 operating_countries_text text,
 pbi boolean,
 hpc boolean,
 administrative_address jsonb check (community_orgs.acnc_object_valid(administrative_address, array['type', 'line_1', 'line_2', 'line_3', 'locality', 'state', 'postcode', 'country'], 'string')),
 operating_jurisdictions jsonb check (community_orgs.acnc_object_valid(operating_jurisdictions, array['act', 'nsw', 'nt', 'qld', 'sa', 'tas', 'vic', 'wa'], 'boolean')),
 purposes jsonb check (community_orgs.acnc_object_valid(purposes, array['preventing_or_relieving_suffering_of_animals', 'advancing_culture', 'advancing_education', 'advancing_health', 'advocacy_for_charitable_purposes', 'advancing_natural_environment', 'promoting_or_protecting_human_rights', 'other_charitable_purposes', 'promoting_reconciliation_mutual_respect_and_tolerance', 'advancing_religion', 'advancing_social_or_public_welfare', 'advancing_security_or_safety_of_australia_or_australian_public'], 'boolean')),
 beneficiaries jsonb check (community_orgs.acnc_object_valid(beneficiaries, array['aboriginal_or_tsi', 'adults', 'aged_persons', 'children', 'communities_overseas', 'early_childhood', 'ethnic_groups', 'families', 'females', 'financially_disadvantaged', 'lgbtiqa_plus', 'general_community_in_australia', 'males', 'migrants_refugees_or_asylum_seekers', 'other_beneficiaries', 'other_charities', 'people_at_risk_of_homelessness', 'people_with_chronic_illness', 'people_with_disabilities', 'pre_post_release_offenders', 'rural_regional_remote_communities', 'unemployed_person', 'veterans_or_their_families', 'victims_of_crime', 'victims_of_disasters', 'youth', 'animals', 'environment', 'other_gender_identities'], 'boolean')),
 primary key (org_id, source_record_id),
 check (administrative_address->>'postcode' is null or administrative_address->>'postcode' ~ '^[0-9]{4}$')
);
alter table community_orgs.acnc_register_details enable row level security;
revoke all on community_orgs.acnc_register_details from public, anon, authenticated, ingestion_worker;
-- Only explicitly published projections on public organisations can be read.
create policy acnc_public_read on community_orgs.acnc_register_details for select to anon, authenticated
 using (is_public and exists (select 1 from community_orgs.organisations o
   where o.org_id = acnc_register_details.org_id and o.is_public));
grant select (org_id, other_names_text, charity_size, responsible_person_count,
 financial_year_end, operating_countries_text, pbi, hpc, administrative_address,
 operating_jurisdictions, purposes, beneficiaries)
 on community_orgs.acnc_register_details to anon, authenticated;
comment on table community_orgs.acnc_register_details is
 'Reviewed ACNC projections per organisation/source identity. F02 adds storage only; default private until F03 publication, provenance and suppression support.';

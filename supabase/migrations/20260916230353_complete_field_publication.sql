-- F03: a private, closed publication allowlist, never populated from source data.
create table ingestion.field_mappings (
 field text primary key, table_name text not null, column_name text not null,
 path text, kind text not null, section text not null, label text not null,
 mapping_version text not null
);
alter table ingestion.field_mappings enable row level security;
revoke all on ingestion.field_mappings from public, anon, authenticated, service_role, ingestion_worker;
insert into ingestion.field_mappings
select * from jsonb_to_recordset($mapping$
[
 {
  "field": "abn",
  "table_name": "legal_details",
  "column_name": "abn",
  "path": null,
  "kind": "string",
  "section": "Legal",
  "label": "ABN",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "entity_name",
  "table_name": "organisations",
  "column_name": "entity_name",
  "path": null,
  "kind": "string",
  "section": "Overview",
  "label": "Registered legal name",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "other_names_text",
  "table_name": "acnc_register_details",
  "column_name": "other_names_text",
  "path": null,
  "kind": "string",
  "section": "Overview",
  "label": "Other Organisation Names",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "administrative_address",
  "table_name": "acnc_register_details",
  "column_name": "administrative_address",
  "path": null,
  "kind": "address",
  "section": "Contact",
  "label": "Administrative address (all supplied components)",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "website",
  "table_name": "contact_info",
  "column_name": "website",
  "path": null,
  "kind": "string",
  "section": "Contact",
  "label": "Charity Website",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "acnc_registered_date",
  "table_name": "legal_details",
  "column_name": "acnc_registered_date",
  "path": null,
  "kind": "date",
  "section": "Legal",
  "label": "Registration Date",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "date_established",
  "table_name": "organisations",
  "column_name": "date_established",
  "path": null,
  "kind": "date",
  "section": "Overview",
  "label": "Date Organisation Established",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "charity_size",
  "table_name": "acnc_register_details",
  "column_name": "charity_size",
  "path": null,
  "kind": "string",
  "section": "Legal",
  "label": "Charity Size",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "responsible_person_count",
  "table_name": "acnc_register_details",
  "column_name": "responsible_person_count",
  "path": null,
  "kind": "integer",
  "section": "Governance",
  "label": "Number of Responsible Persons",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "financial_year_end",
  "table_name": "acnc_register_details",
  "column_name": "financial_year_end",
  "path": null,
  "kind": "month_day",
  "section": "Finance",
  "label": "Financial Year End",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "operating_jurisdictions.act",
  "table_name": "acnc_register_details",
  "column_name": "operating_jurisdictions",
  "path": "act",
  "kind": "boolean",
  "section": "Operations",
  "label": "Operates in ACT",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "operating_jurisdictions.nsw",
  "table_name": "acnc_register_details",
  "column_name": "operating_jurisdictions",
  "path": "nsw",
  "kind": "boolean",
  "section": "Operations",
  "label": "Operates in NSW",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "operating_jurisdictions.nt",
  "table_name": "acnc_register_details",
  "column_name": "operating_jurisdictions",
  "path": "nt",
  "kind": "boolean",
  "section": "Operations",
  "label": "Operates in NT",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "operating_jurisdictions.qld",
  "table_name": "acnc_register_details",
  "column_name": "operating_jurisdictions",
  "path": "qld",
  "kind": "boolean",
  "section": "Operations",
  "label": "Operates in QLD",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "operating_jurisdictions.sa",
  "table_name": "acnc_register_details",
  "column_name": "operating_jurisdictions",
  "path": "sa",
  "kind": "boolean",
  "section": "Operations",
  "label": "Operates in SA",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "operating_jurisdictions.tas",
  "table_name": "acnc_register_details",
  "column_name": "operating_jurisdictions",
  "path": "tas",
  "kind": "boolean",
  "section": "Operations",
  "label": "Operates in TAS",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "operating_jurisdictions.vic",
  "table_name": "acnc_register_details",
  "column_name": "operating_jurisdictions",
  "path": "vic",
  "kind": "boolean",
  "section": "Operations",
  "label": "Operates in VIC",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "operating_jurisdictions.wa",
  "table_name": "acnc_register_details",
  "column_name": "operating_jurisdictions",
  "path": "wa",
  "kind": "boolean",
  "section": "Operations",
  "label": "Operates in WA",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "operating_countries_text",
  "table_name": "acnc_register_details",
  "column_name": "operating_countries_text",
  "path": null,
  "kind": "string",
  "section": "Operations",
  "label": "Operating Countries",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "pbi",
  "table_name": "acnc_register_details",
  "column_name": "pbi",
  "path": null,
  "kind": "boolean",
  "section": "Legal",
  "label": "PBI",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "hpc",
  "table_name": "acnc_register_details",
  "column_name": "hpc",
  "path": null,
  "kind": "boolean",
  "section": "Legal",
  "label": "HPC",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.preventing_or_relieving_suffering_of_animals",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "preventing_or_relieving_suffering_of_animals",
  "kind": "boolean",
  "section": "Operations",
  "label": "Preventing or relieving suffering of animals",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.advancing_culture",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "advancing_culture",
  "kind": "boolean",
  "section": "Operations",
  "label": "Advancing Culture",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.advancing_education",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "advancing_education",
  "kind": "boolean",
  "section": "Operations",
  "label": "Advancing Education",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.advancing_health",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "advancing_health",
  "kind": "boolean",
  "section": "Operations",
  "label": "Advancing Health",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.advocacy_for_charitable_purposes",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "advocacy_for_charitable_purposes",
  "kind": "boolean",
  "section": "Operations",
  "label": "Advocacy for charitable purposes",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.advancing_natural_environment",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "advancing_natural_environment",
  "kind": "boolean",
  "section": "Operations",
  "label": "Advancing natural environment",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.promoting_or_protecting_human_rights",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "promoting_or_protecting_human_rights",
  "kind": "boolean",
  "section": "Operations",
  "label": "Promoting or protecting human rights",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.other_charitable_purposes",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "other_charitable_purposes",
  "kind": "boolean",
  "section": "Operations",
  "label": "Other charitable purposes",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.promoting_reconciliation_mutual_respect_and_tolerance",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "promoting_reconciliation_mutual_respect_and_tolerance",
  "kind": "boolean",
  "section": "Operations",
  "label": "Promoting reconciliation  mutual respect and tolerance",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.advancing_religion",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "advancing_religion",
  "kind": "boolean",
  "section": "Operations",
  "label": "Advancing Religion",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.advancing_social_or_public_welfare",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "advancing_social_or_public_welfare",
  "kind": "boolean",
  "section": "Operations",
  "label": "Advancing social or public welfare",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "purposes.advancing_security_or_safety_of_australia_or_australian_public",
  "table_name": "acnc_register_details",
  "column_name": "purposes",
  "path": "advancing_security_or_safety_of_australia_or_australian_public",
  "kind": "boolean",
  "section": "Operations",
  "label": "Advancing security or safety of Australia or Australian public",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.aboriginal_or_tsi",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "aboriginal_or_tsi",
  "kind": "boolean",
  "section": "Operations",
  "label": "Aboriginal or TSI",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.adults",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "adults",
  "kind": "boolean",
  "section": "Operations",
  "label": "Adults",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.aged_persons",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "aged_persons",
  "kind": "boolean",
  "section": "Operations",
  "label": "Aged Persons",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.children",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "children",
  "kind": "boolean",
  "section": "Operations",
  "label": "Children",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.communities_overseas",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "communities_overseas",
  "kind": "boolean",
  "section": "Operations",
  "label": "Communities Overseas",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.early_childhood",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "early_childhood",
  "kind": "boolean",
  "section": "Operations",
  "label": "Early Childhood",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.ethnic_groups",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "ethnic_groups",
  "kind": "boolean",
  "section": "Operations",
  "label": "Ethnic Groups",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.families",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "families",
  "kind": "boolean",
  "section": "Operations",
  "label": "Families",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.females",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "females",
  "kind": "boolean",
  "section": "Operations",
  "label": "Females",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.financially_disadvantaged",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "financially_disadvantaged",
  "kind": "boolean",
  "section": "Operations",
  "label": "Financially Disadvantaged",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.lgbtiqa_plus",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "lgbtiqa_plus",
  "kind": "boolean",
  "section": "Operations",
  "label": "Lgbtiqa plus",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.general_community_in_australia",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "general_community_in_australia",
  "kind": "boolean",
  "section": "Operations",
  "label": "General Community in Australia",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.males",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "males",
  "kind": "boolean",
  "section": "Operations",
  "label": "Males",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.migrants_refugees_or_asylum_seekers",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "migrants_refugees_or_asylum_seekers",
  "kind": "boolean",
  "section": "Operations",
  "label": "Migrants Refugees or Asylum Seekers",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.other_beneficiaries",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "other_beneficiaries",
  "kind": "boolean",
  "section": "Operations",
  "label": "Other Beneficiaries",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.other_charities",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "other_charities",
  "kind": "boolean",
  "section": "Operations",
  "label": "Other Charities",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.people_at_risk_of_homelessness",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "people_at_risk_of_homelessness",
  "kind": "boolean",
  "section": "Operations",
  "label": "People at risk of homelessness",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.people_with_chronic_illness",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "people_with_chronic_illness",
  "kind": "boolean",
  "section": "Operations",
  "label": "People with Chronic Illness",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.people_with_disabilities",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "people_with_disabilities",
  "kind": "boolean",
  "section": "Operations",
  "label": "People with Disabilities",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.pre_post_release_offenders",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "pre_post_release_offenders",
  "kind": "boolean",
  "section": "Operations",
  "label": "Pre Post Release Offenders",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.rural_regional_remote_communities",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "rural_regional_remote_communities",
  "kind": "boolean",
  "section": "Operations",
  "label": "Rural Regional Remote Communities",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.unemployed_person",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "unemployed_person",
  "kind": "boolean",
  "section": "Operations",
  "label": "Unemployed Person",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.veterans_or_their_families",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "veterans_or_their_families",
  "kind": "boolean",
  "section": "Operations",
  "label": "Veterans or their families",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.victims_of_crime",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "victims_of_crime",
  "kind": "boolean",
  "section": "Operations",
  "label": "Victims of crime",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.victims_of_disasters",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "victims_of_disasters",
  "kind": "boolean",
  "section": "Operations",
  "label": "Victims of Disasters",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.youth",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "youth",
  "kind": "boolean",
  "section": "Operations",
  "label": "Youth",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.animals",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "animals",
  "kind": "boolean",
  "section": "Operations",
  "label": "animals",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.environment",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "environment",
  "kind": "boolean",
  "section": "Operations",
  "label": "environment",
  "mapping_version": "acnc-register-fields-v2"
 },
 {
  "field": "beneficiaries.other_gender_identities",
  "table_name": "acnc_register_details",
  "column_name": "beneficiaries",
  "path": "other_gender_identities",
  "kind": "boolean",
  "section": "Operations",
  "label": "other gender identities",
  "mapping_version": "acnc-register-fields-v2"
 }
]
$mapping$::jsonb)
 as x(field text, table_name text, column_name text, path text, kind text, section text, label text, mapping_version text);

-- Scope register facts by source identity; shared portal scalars use scope zero.
alter table ingestion.field_state add column record_id bigint not null default 0;
alter table ingestion.field_state drop constraint field_state_pkey;
alter table ingestion.field_state add primary key(org_id, table_name, field, record_id);
alter table ingestion.suppressions drop constraint suppressions_field_check;
-- Valid suppression keys are checked by the operator RPC against field_mappings.
-- URLs are text facts; do not truncate a valid supplied URL to an old UI limit.
alter table community_orgs.contact_info alter column website type text;

create function ingestion.valid_field_value(m ingestion.field_mappings, v jsonb)
returns boolean language plpgsql stable set search_path='' as $$
declare s text := v #>> '{}'; d date;
begin
 if v is null or v='null'::jsonb then return false; end if;
 case m.kind
 when 'boolean' then return jsonb_typeof(v)='boolean';
 when 'integer' then return jsonb_typeof(v)='number' and s ~ '^[0-9]+$' and s::numeric <= 2147483647;
 when 'date' then
  if jsonb_typeof(v)<>'string' or s !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return false; end if;
  d:=s::date; return to_char(d,'YYYY-MM-DD')=s;
 when 'month_day' then return community_orgs.acnc_calendar_valid(v);
 when 'address' then
  return community_orgs.acnc_object_valid(v,array['type','line_1','line_2','line_3','locality','state','postcode','country'],'string')
   and v<>'{}'::jsonb and not exists(select 1 from jsonb_each(v) e where e.value='null'::jsonb or length(trim(e.value #>> '{}'))=0)
   and (not v ? 'postcode' or v->>'postcode' ~ '^[0-9]{4}$');
 when 'string' then
  if jsonb_typeof(v)<>'string' or length(trim(s))=0 then return false; end if;
  if m.field='abn' then return s ~ '^[0-9]{11}$'; end if;
  if m.field='website' then
   return s ~ '^https?://[^/@[:space:]?#:]+(:[0-9]{1,5})?([/?#].*)?$'
    and s !~ '[[:space:][:cntrl:]\\]' and not s ~ '^https?://[^/?#]*@'
    and coalesce((substring(s from '^https?://[^/:?#]+:([0-9]+)'))::integer <= 65535,true);
  end if;
  return true;
 else return false;
 end case;
exception when others then return false;
end $$;
revoke all on function ingestion.valid_field_value(ingestion.field_mappings,jsonb) from public,anon,authenticated,service_role;

-- A full trigger covers each mapped scalar/path. Import RPCs clear protection only
-- for fields they actually wrote, after the ordinary revision triggers have run.
create or replace function ingestion.protect_portal_fields() returns trigger
language plpgsql security definer set search_path='' as $$
declare old_row jsonb; new_row jsonb; org uuid; scope bigint:=0; m ingestion.field_mappings; before_value jsonb; after_value jsonb;
begin
 if TG_OP<>'INSERT' then old_row:=to_jsonb(OLD); end if;
 if TG_OP<>'DELETE' then new_row:=to_jsonb(NEW); end if;
 if TG_OP='UPDATE' and (old_row->'org_id' is distinct from new_row->'org_id'
  or old_row->'source_record_id' is distinct from new_row->'source_record_id') then
  raise exception 'Identity reassignment requires a reviewed migration' using errcode='22023'; end if;
 org:=coalesce((new_row->>'org_id')::uuid,(old_row->>'org_id')::uuid);
 if org is null or not exists(select 1 from community_orgs.organisations where org_id=org) then return null; end if;
 if TG_TABLE_NAME='acnc_register_details' then scope:=coalesce((new_row->>'source_record_id')::bigint,(old_row->>'source_record_id')::bigint); end if;
 for m in select * from ingestion.field_mappings where table_name=TG_TABLE_NAME loop
  before_value:=old_row->m.column_name; after_value:=new_row->m.column_name;
  if m.path is not null then before_value:=before_value->m.path; after_value:=after_value->m.path; end if;
  if TG_OP='DELETE' or nullif(before_value,'null'::jsonb) is distinct from nullif(after_value,'null'::jsonb) then
   insert into ingestion.field_state(org_id,table_name,field,record_id,changed_by)
   values(org,TG_TABLE_NAME,m.field,scope,auth.uid())
   on conflict(org_id,table_name,field,record_id) do update set
    revision=ingestion.field_state.revision+1,protected=true,changed_by=auth.uid(),changed_at=clock_timestamp();
  end if;
 end loop;
 return null;
end $$;
create trigger ingestion_protect_register after insert or update or delete on community_orgs.acnc_register_details
 for each row execute function ingestion.protect_portal_fields();
-- Backfill newly mapped existing values as protected, including pre-F03 projections.
do $$ declare m ingestion.field_mappings; expr text; scope text;
begin
 for m in select * from ingestion.field_mappings loop
  expr:=format('to_jsonb(x.%I)',m.column_name);
  if m.path is not null then expr:=format('(%s)->%L',expr,m.path); end if;
  scope:=case when m.table_name='acnc_register_details' then 'x.source_record_id' else '0' end;
  execute format('insert into ingestion.field_state(org_id,table_name,field,record_id)
   select distinct x.org_id,%L,%L,%s from community_orgs.%I x join community_orgs.organisations o using(org_id)
   where nullif(%s,''null''::jsonb) is not null on conflict do nothing',m.table_name,m.field,scope,m.table_name,expr);
 end loop;
end $$;

create or replace function community_orgs.ingestion_field_preview(p_run text,p_version text,p_organisation uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a record; m ingestion.field_mappings; sv ingestion.source_record_versions; state ingestion.field_state;
 current_value jsonb; proposed jsonb; n bigint; scope bigint; expr text; predicate text;
 result jsonb:='[]'; status text; supported boolean; target_name text; token text; raw_keys jsonb;
 register_public boolean; is_protected boolean;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select v.* into sv from ingestion.source_record_versions v join ingestion.run_records rr on rr.version_id=v.id
 where rr.run_id=p_run::bigint and v.id=p_version::bigint;
 if not found then raise exception 'Record not in selected run' using errcode='P0002'; end if;
 if p_organisation is not null then
  select entity_name into target_name from community_orgs.organisations where org_id=p_organisation;
  if not found then raise exception 'Organisation not found' using errcode='P0002'; end if;
 end if;
 select md5(jsonb_build_array(to_jsonb(sv),to_jsonb(s),i.observed_at,i.completion,
   (select max(id) from ingestion.source_record_versions where record_id=sv.record_id))::text)
 into token from ingestion.ingestion_runs i join ingestion.sources s using(source_id,resource_id) where i.id=p_run::bigint;
 for a in
  select f.field,f.value,true as present from ingestion.field_assertions f where version_id=sv.id
  union all select fm.field,null::jsonb,false from ingestion.field_mappings fm
  where not exists(select 1 from ingestion.field_assertions f where f.version_id=sv.id and f.field=fm.field)
  order by 1
 loop
  select * into m from ingestion.field_mappings where field=a.field;
  supported:=m.field is not null and (a.field in ('entity_name','abn','website')
   or (sv.parser_version='acnc-ckan-v2' and sv.payload->>'mapping_version'=m.mapping_version));
  scope:=case when m.table_name='acnc_register_details' then sv.record_id else 0 end;
  current_value:=null; n:=0; state:=null; register_public:=null;
  if m.field is not null and p_organisation is not null then
   expr:=format('to_jsonb(x.%I)',m.column_name);
   if m.path is not null then expr:=format('(%s)->%L',expr,m.path); end if;
   predicate:=case when scope=0 then '' else ' and source_record_id=$2' end;
   execute format('select count(*),(jsonb_agg(%s))->0 from community_orgs.%I x where org_id=$1%s',expr,m.table_name,predicate)
    into n,current_value using p_organisation,scope;
   select * into state from ingestion.field_state where org_id=p_organisation and table_name=m.table_name and field=m.field and record_id=scope;
  end if;
  if scope<>0 and p_organisation is not null then
   select is_public into register_public from community_orgs.acnc_register_details
    where org_id=p_organisation and source_record_id=scope;
  end if;
  is_protected:=coalesce(state.protected,false) or register_public=false;
  is_protected:=coalesce(is_protected,false);
  proposed:=a.value;
  -- An address is one explicit atomic merge: absent components never delete old ones.
  if m.kind='address' and jsonb_typeof(a.value)='object' then
   proposed:=coalesce(nullif(current_value,'null'::jsonb),'{}') || a.value;
  end if;
  status:=case
   when exists(select 1 from ingestion.suppressions z where (z.record_id=sv.record_id or z.organisation_id=p_organisation) and z.field in ('*',a.field)) then 'suppressed'
   when not a.present or a.value='null'::jsonb then 'missing'
   when not supported then 'unmapped'
   when ingestion.valid_field_value(m,a.value) is distinct from true then 'invalid'
   when n>1 then 'ambiguous'
   when current_value is not distinct from proposed then 'unchanged'
   when is_protected then 'conflict'
   when nullif(current_value,'null'::jsonb) is null then 'new'
   else 'changed' end;
  select x->'source_values' into raw_keys from jsonb_array_elements(sv.payload->'assertions') x where x->>'field'=a.field;
  result:=result || jsonb_build_array(jsonb_build_object(
   'field',a.field,'table',m.table_name,'section',coalesce(m.section,'Unmapped'),'label',coalesce(m.label,a.field),
   'atomic_group',m.kind='address','input_value',a.value,'source_value',proposed,'current_value',case when n>1 then null else current_value end,
   'status',status,'protected',is_protected,'projection_public',register_public,'revision',coalesce(state.revision,0)::text,
   'target_rows',n,'changed_at',state.changed_at,'record_id',scope::text,
   'source_token',token,'mapping_token',md5(coalesce(to_jsonb(m)::text,'unmapped')||':f03-v1'),
   'source_version',sv.id::text,'mapping_version',m.mapping_version,'source_values',raw_keys));
 end loop;
 return jsonb_build_object('organisation_id',p_organisation,'organisation_name',target_name,'fields',result);
end $$;

create or replace function community_orgs.approve_ingestion_fields(p_run text,p_version text,p_revision integer,p_fields jsonb,p_organisation uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare r ingestion.reviews; snapshot jsonb; f jsonb; result uuid;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into r from ingestion.reviews where version_id=p_version::bigint for update;
 if not found or r.revision is distinct from p_revision or r.organisation_id is distinct from p_organisation or r.decision not in ('link','create') then
  raise exception 'Review changed or not approved for a target' using errcode='40001'; end if;
 if jsonb_typeof(p_fields) is distinct from 'array' or jsonb_array_length(p_fields) not between 1 and 100 then
  raise exception 'Select eligible fields' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(p_fields) x group by x->>'field' having count(*)>1) then
  raise exception 'Duplicate fields' using errcode='22023'; end if;
 perform ingestion.assert_not_suppressed(p_version::bigint,r.organisation_id,p_fields);
 snapshot:=community_orgs.ingestion_field_preview(p_run,p_version,r.organisation_id);
 for f in select value from jsonb_array_elements(p_fields) loop
  if not exists(select 1 from jsonb_array_elements(snapshot->'fields') x where x=f and x->>'status' in ('new','changed') and x->'protected'='false'::jsonb) then
   raise exception 'Field changed or is not eligible; reload preview' using errcode='40001'; end if;
 end loop;
 if r.decision='create' and not p_fields @> '[{"field":"entity_name"}]' then raise exception 'New organisation requires name' using errcode='22023'; end if;
 if not exists(select 1 from ingestion.ingestion_runs i join ingestion.sources s using(source_id,resource_id)
  where i.id=p_run::bigint and i.completion='complete' and s.enabled) then raise exception 'Complete enabled source required' using errcode='22023'; end if;
 insert into ingestion.change_sets(run_id,version_id,review_revision,organisation_id,fields,approved_by)
 values(p_run::bigint,p_version::bigint,r.revision,r.organisation_id,p_fields,auth.uid()) returning id into result;
 return result;
end $$;

-- Only definer RPCs call this writer. Identifiers/casts come from the private allowlist.
create function ingestion.write_field(p_org uuid,p_record bigint,p_field text,p_value jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare m ingestion.field_mappings; expr text; predicate text; typ text;
begin
 select * into m from ingestion.field_mappings where field=p_field;
 if not found then raise exception 'Unsupported field' using errcode='22023'; end if;
 if p_value is not null and ingestion.valid_field_value(m,p_value) is distinct from true then
  raise exception 'Invalid field value' using errcode='22023'; end if;
 if m.table_name='acnc_register_details' then
  insert into community_orgs.acnc_register_details(org_id,source_record_id) values(p_org,p_record) on conflict do nothing;
 elsif m.table_name='legal_details' and not exists(select 1 from community_orgs.legal_details where org_id=p_org) then
  insert into community_orgs.legal_details(org_id) values(p_org);
 elsif m.table_name='contact_info' and not exists(select 1 from community_orgs.contact_info where org_id=p_org) then
  insert into community_orgs.contact_info(org_id) values(p_org);
 end if;
 if m.path is not null then
  expr:=format('case when $2 is null then %I - %L else jsonb_set(coalesce(%I,''{}''),array[%L],$2,true) end',m.column_name,m.path,m.column_name,m.path);
 else
  typ:=case m.kind when 'date' then 'date' when 'integer' then 'integer' when 'boolean' then 'boolean' else 'text' end;
  expr:=case when m.kind in ('address','month_day') then '$2' else format('($2 #>> ''{}'')::%s',typ) end;
 end if;
 predicate:=case when m.table_name='acnc_register_details' then ' and source_record_id=$3' else '' end;
 execute format('update community_orgs.%I set %I=%s where org_id=$1%s',m.table_name,m.column_name,expr,predicate) using p_org,p_value,p_record;
end $$;
revoke all on function ingestion.write_field(uuid,bigint,text,jsonb) from public,anon,authenticated,service_role,ingestion_worker;

create or replace function community_orgs.publish_ingestion_fields(p_change_set uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c ingestion.change_sets; r ingestion.reviews; f jsonb; snapshot jsonb; org uuid; rec bigint; linked uuid; name text; register_existed boolean;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 -- Shared lock order with suppression; include absent child rows, configuration and staging.
 lock table community_orgs.organisations,community_orgs.legal_details,community_orgs.contact_info,community_orgs.acnc_register_details in share row exclusive mode;
 lock table ingestion.field_mappings,ingestion.source_record_versions,ingestion.field_assertions,ingestion.run_records in share mode;
 select * into c from ingestion.change_sets where id=p_change_set for update;
 if not found then raise exception 'Approval not found' using errcode='P0002'; end if;
 select record_id into rec from ingestion.source_record_versions where id=c.version_id;
 select organisation_id into linked from ingestion.source_links where record_id=rec;
 perform ingestion.assert_not_suppressed(c.version_id,coalesce(c.organisation_id,linked),c.fields);
 select organisation_id into org from ingestion.publications where change_set_id=c.id;
 if found then return org; end if;
 select * into r from ingestion.reviews where version_id=c.version_id for update;
 if r.revision is distinct from c.review_revision or r.organisation_id is distinct from c.organisation_id or r.decision not in ('link','create') then
  raise exception 'Review changed; approve again' using errcode='40001'; end if;
 perform 1 from ingestion.sources s join ingestion.ingestion_runs i using(source_id,resource_id)
  where i.id=c.run_id and i.completion='complete' and s.enabled for share of s,i;
 if not found then raise exception 'Complete enabled source required' using errcode='22023'; end if;
 snapshot:=community_orgs.ingestion_field_preview(c.run_id::text,c.version_id::text,c.organisation_id);
 for f in select value from jsonb_array_elements(c.fields) loop
  if not exists(select 1 from jsonb_array_elements(snapshot->'fields') x where x=f and x->>'status' in ('new','changed') and x->'protected'='false'::jsonb) then
   raise exception 'Source, mapping or target changed; approve again' using errcode='40001'; end if;
 end loop;
 if linked is not null and linked is distinct from c.organisation_id then raise exception 'Source already linked to another target' using errcode='40001'; end if;
 org:=c.organisation_id;
 if org is null then
  select x->>'source_value' into name from jsonb_array_elements(c.fields) x where x->>'field'='entity_name';
  if name is null then raise exception 'New organisation requires name' using errcode='22023'; end if;
  org:=gen_random_uuid();
  insert into ingestion.creation_targets(change_set_id,org_id) values(c.id,org);
  insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values(org,name,'import-'||org::text,true);
 end if;
 select exists(select 1 from community_orgs.acnc_register_details where org_id=org and source_record_id=rec) into register_existed;
 for f in select value from jsonb_array_elements(c.fields) loop
  perform ingestion.write_field(org,rec,f->>'field',f->'source_value');
  update ingestion.field_state set protected=false where org_id=org and table_name=f->>'table'
   and field=f->>'field' and record_id=(f->>'record_id')::bigint;
 end loop;
 -- Only newly created projections become visible. Existing hidden projections
 -- are protected in preview and cannot have visibility restored by an import.
 if not register_existed then
  update community_orgs.acnc_register_details set is_public=true where org_id=org and source_record_id=rec;
 end if;
 insert into ingestion.source_links values(rec,org) on conflict(record_id) do nothing;
 insert into ingestion.publications(change_set_id,organisation_id,published_by,changes) values(c.id,org,auth.uid(),c.fields);
 return org;
end $$;

-- Defence in depth: direct writes cannot restore suppressed facts or visibility.
create or replace function ingestion.enforce_suppression() returns trigger
language plpgsql security definer set search_path='' as $$
declare m ingestion.field_mappings; old_row jsonb; new_row jsonb:=to_jsonb(NEW); old_value jsonb; new_value jsonb; rec bigint;
begin
 if TG_OP='UPDATE' then old_row:=to_jsonb(OLD); end if;
 if TG_TABLE_NAME='acnc_register_details' then rec:=NEW.source_record_id; end if;
 if new_row->'is_public'='true'::jsonb and exists(select 1 from ingestion.suppressions
  where (organisation_id=NEW.org_id or record_id=rec) and field in ('*','entity_name')) then
  raise exception 'Withdrawn content cannot be made public' using errcode='42501'; end if;
 for m in select * from ingestion.field_mappings where table_name=TG_TABLE_NAME loop
  old_value:=old_row->m.column_name; new_value:=new_row->m.column_name;
  if m.path is not null then old_value:=old_value->m.path; new_value:=new_value->m.path; end if;
  if nullif(new_value,'null'::jsonb) is not null and new_value is distinct from old_value
   and exists(select 1 from ingestion.suppressions where (organisation_id=NEW.org_id or record_id=rec) and field in ('*',m.field)) then
   raise exception 'Suppressed field cannot be restored' using errcode='42501'; end if;
 end loop;
 return NEW;
end $$;
create trigger enforce_register_suppression before insert or update on community_orgs.acnc_register_details
 for each row execute function ingestion.enforce_suppression();

create or replace function community_orgs.suppress_ingestion_content(p_run text,p_version text,p_field text,p_reason text,p_expected jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare rec bigint; org uuid; snapshot jsonb; m ingestion.field_mappings; target_record bigint;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into m from ingestion.field_mappings where field=p_field;
 if p_field is null or (p_field<>'*' and m.field is null) or p_reason is null or length(trim(p_reason)) not between 1 and 2000 then
  raise exception 'Invalid suppression' using errcode='22023'; end if;
 lock table community_orgs.organisations,community_orgs.legal_details,community_orgs.contact_info,community_orgs.acnc_register_details in share row exclusive mode;
 select sv.record_id into rec from ingestion.run_records rr join ingestion.source_record_versions sv on sv.id=rr.version_id
 where rr.run_id=p_run::bigint and rr.version_id=p_version::bigint;
 if not found then raise exception 'Record not in run' using errcode='P0002'; end if;
 select organisation_id into org from ingestion.source_links where record_id=rec;
 if p_expected->>'organisation_id' is distinct from org::text then raise exception 'Target changed; reload' using errcode='40001'; end if;
 if p_field<>'*' and org is not null then
  snapshot:=community_orgs.ingestion_field_preview(p_run,p_version,org);
  if not exists(select 1 from jsonb_array_elements(snapshot->'fields') f where f=p_expected->'field' and f->>'field'=p_field and (f->>'target_rows')::int<=1) then
   raise exception 'Target field changed or ambiguous; reload' using errcode='40001'; end if;
 end if;
 insert into ingestion.suppressions(record_id,field,organisation_id,reason,suppressed_by)
 values(rec,p_field,org,trim(p_reason),auth.uid()) on conflict do nothing;
 if org is not null then
  if p_field in ('*','entity_name') then
   -- The name is mandatory: suppress its entire public organisation instead of inventing a name.
   update community_orgs.organisations set is_public=false where org_id=org;
   update community_orgs.acnc_register_details set is_public=false where org_id=org;
  elsif m.table_name='acnc_register_details' then
   -- Target-level suppression must clear every source projection of this fact.
   for target_record in select source_record_id from community_orgs.acnc_register_details where org_id=org loop
    perform ingestion.write_field(org,target_record,p_field,null);
   end loop;
  else perform ingestion.write_field(org,rec,p_field,null);
  end if;
 end if;
end $$;

create or replace function community_orgs.organisation_source_attribution(p_organisation uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not community_orgs.can_view_org(p_organisation) or
 (community_orgs.user_has_verified_mfa() and (auth.jwt()->>'aal') is distinct from 'aal2') then return '[]'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x) order by x.published_at desc),'[]') from (
 select s.source_id,s.resource_id,
 case when s.metadata->>'synthetic'='true' then 'Synthetic test data' else coalesce(s.metadata->>'public_title',s.source_id) end as title,
 s.metadata->>'public_url' as url,s.metadata->>'public_licence' as licence,s.metadata->>'public_licence_url' as licence_url,
 i.observed_at,p.published_at,f->>'field' as field,
 f->>'mapping_version' as mapping_version,
 coalesce(fs.revision=(f->>'revision')::bigint+1,false) as unchanged_since_import
 from ingestion.publications p join ingestion.change_sets c on c.id=p.change_set_id
 join ingestion.ingestion_runs i on i.id=c.run_id join ingestion.sources s using(source_id,resource_id)
 join ingestion.source_record_versions sv on sv.id=c.version_id
 cross join lateral jsonb_array_elements(p.changes) f
 left join ingestion.field_state fs on fs.org_id=p.organisation_id and fs.table_name=f->>'table' and fs.field=f->>'field'
  and fs.record_id=coalesce((f->>'record_id')::bigint,0)
 where p.organisation_id=p_organisation
 and (f->>'table'<>'acnc_register_details' or exists(select 1 from community_orgs.acnc_register_details d
   where d.org_id=p.organisation_id and d.source_record_id=sv.record_id and d.is_public))
 and not exists(select 1 from ingestion.suppressions z
  where (z.record_id=sv.record_id or z.organisation_id=p.organisation_id) and z.field in ('*','entity_name',f->>'field'))
 ) x);
end $$;

comment on table community_orgs.acnc_register_details is
 'Reviewed ACNC facts per organisation/source identity; selected publication, revision protection and persistent suppression are enforced by F03 RPCs.';

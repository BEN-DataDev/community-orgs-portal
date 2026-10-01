-- Organisations created by the full seed union never received ingestion.publications
-- rows, so organisation_register_facts returned nothing for them even though their
-- ACNC and NSW Incorporated Associations observations were published. The seed is now
-- a second observation path: ACNC facts follow source_links and NSW facts follow the
-- verified identifier key holder, so both survive merges. Where a reviewed change set
-- covers the same source record and field, the change set wins.
begin;

create index full_seed_items_acnc_version_idx
  on ingestion.full_seed_items(((source_refs->>'acnc_version_id')::bigint))
  where source_refs ? 'acnc_version_id';
create index full_seed_items_nsw_incorporation_idx
  on ingestion.full_seed_items(incorporation_number)
  where source_refs ? 'nsw_version_id';

create or replace function community_orgs.organisation_register_facts(p_organisation uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from community_orgs.organisations where org_id=p_organisation and is_public)
  or (community_orgs.user_has_verified_mfa() and (auth.jwt()->>'aal') is distinct from 'aal2') then
  return '[]';
 end if;
 return (
 with published as (
  select distinct on (sv.record_id,f->>'field')
   sv.record_id::text source_key,sv.record_id,f->>'field' field,f->'source_value' value,f->'input_value' input_value,
   m.section,m.label,m.kind,s.source_id,s.resource_id,s.metadata,i.observed_at,p.published_at,
   coalesce(fs.revision=(f->>'revision')::bigint+1,false) as unchanged_since_import,0 origin
  from ingestion.publications p
  join ingestion.change_sets c on c.id=p.change_set_id
  join ingestion.source_record_versions sv on sv.id=c.version_id
  join ingestion.ingestion_runs i on i.id=c.run_id
  join ingestion.sources s using(source_id,resource_id)
  cross join lateral jsonb_array_elements(p.changes) f
  join ingestion.field_mappings m on m.field=f->>'field'
  left join ingestion.field_state fs on fs.org_id=p.organisation_id and fs.table_name=m.table_name
   and fs.field=m.field and fs.record_id=case when m.table_name='acnc_register_details' then sv.record_id else 0 end
  where p.organisation_id=p_organisation
   and (m.table_name<>'acnc_register_details' or exists(
    select 1 from community_orgs.acnc_register_details d
    where d.org_id=p_organisation and d.source_record_id=sv.record_id and d.is_public))
  -- Field revisions order writes even when transaction timestamps are identical.
  order by sv.record_id,f->>'field',(f->>'revision')::bigint desc,p.published_at desc,p.change_set_id desc
 ),
 seed_acnc as (
  select v.record_id::text,v.record_id,a->>'field',a->'value',null::jsonb,
   m.section,m.label,m.kind,s.source_id,s.resource_id,s.metadata,r.observed_at,item.applied_at,
   -- Revision 1 is the import itself; later system projections of the same import keep it.
   coalesce(fs.revision,0)<=1 or fs.changed_at<=item.applied_at,1
  from ingestion.source_links l
  join ingestion.source_record_versions v on v.record_id=l.record_id
  join ingestion.full_seed_items item on (item.source_refs->>'acnc_version_id')::bigint=v.id
   and item.source_refs ? 'acnc_version_id'
  join ingestion.full_seed_publications pub on pub.publication_id=item.publication_id and pub.status='published'
  join ingestion.ingestion_runs r on r.id=pub.acnc_run_id
  join ingestion.source_records sr on sr.id=v.record_id
  join ingestion.sources s on s.source_id=sr.source_id and s.resource_id=sr.resource_id
  cross join lateral jsonb_array_elements(v.payload->'assertions') a
  join ingestion.field_mappings m on m.field=a->>'field'
  left join ingestion.field_state fs on fs.org_id=p_organisation and fs.table_name=m.table_name
   and fs.field=m.field and fs.record_id=case when m.table_name='acnc_register_details' then v.record_id else 0 end
  where l.organisation_id=p_organisation and item.applied_at is not null
   and (m.table_name<>'acnc_register_details' or exists(
    select 1 from community_orgs.acnc_register_details d
    where d.org_id=p_organisation and d.source_record_id=v.record_id and d.is_public))
 ),
 seed_nsw as (
  -- Only the register's public fields. The holder may be a merge target carrying another
  -- source's values, so "unchanged" compares the portal value rather than field revisions.
  select 'nsw:'||c.id,null::bigint,x.field,x.value,null::jsonb,
   x.section,x.label,x.kind,s.source_id,s.resource_id,s.metadata,rel.observed_at,item.applied_at,x.unchanged,1
  from ingestion.identifier_keys k
  join ingestion.full_seed_items item on item.incorporation_number=k.normalized_value
   and item.source_refs ? 'nsw_version_id'
  join ingestion.full_seed_publications pub on pub.publication_id=item.publication_id and pub.status='published'
  join ingestion.registry_seed_releases rel on rel.id=pub.nsw_release_id
  join ingestion.registry_seed_candidate_versions cv on cv.id=(item.source_refs->>'nsw_version_id')::bigint
  join ingestion.registry_seed_candidates c on c.id=cv.candidate_id
  join ingestion.sources s on s.source_id=c.source_id and s.resource_id=c.resource_id
  left join community_orgs.organisations o on o.org_id=p_organisation
  left join community_orgs.legal_details ld on ld.org_id=p_organisation
  cross join lateral (select jsonb_object_agg(a->>'field',a->'value') v
   from jsonb_array_elements(cv.payload->'assertions') a) asserted
  -- The register displays d/m/yyyy; the seed left incorporation_registration_date empty.
  cross join lateral (select regexp_match(asserted.v->>'nsw_date_registered','^(\d{1,2})/(\d{1,2})/(\d{4})$') p) dm
  cross join lateral (select coalesce(item.incorporation_registration_date,case
   when dm.p is null or dm.p[3]::int<1 or dm.p[2]::int not between 1 and 12 then null
   when dm.p[1]::int between 1 and extract(day from make_date(dm.p[3]::int,dm.p[2]::int,1)+interval '1 month -1 day')
    then make_date(dm.p[3]::int,dm.p[2]::int,dm.p[1]::int) end) registered) reg
  cross join lateral (values
   ('entity_name','Overview','Registered name','string',
    to_jsonb(item.entity_name),o.entity_name is not distinct from item.entity_name),
   ('incorporation_number','Legal','Incorporation number','string',
    to_jsonb(item.incorporation_number),ld.incorporation_number is not distinct from item.incorporation_number),
   ('incorporation_registration_date','Legal','Registration date','date',
    to_jsonb(reg.registered),
    ld.incorporation_registration_date is null or ld.incorporation_registration_date=reg.registered),
   ('nsw_association_status','Legal','Registration status','string',asserted.v->'nsw_association_status',true),
   ('nsw_association_type','Legal','Organisation type','string',asserted.v->'nsw_association_type',true),
   ('nsw_registered_office_address','Contact','Registered office (as displayed)','string',
    asserted.v->'nsw_registered_office_address',true)
  ) x(field,section,label,kind,value,unchanged)
  where k.holder=p_organisation and k.scheme='incorporated_association' and k.jurisdiction='AU-NSW'
   and k.state='verified' and item.applied_at is not null
   and x.value is not null and jsonb_typeof(x.value)<>'null'
 ),
 latest as (
  select distinct on (source_key,field) *
  from (select * from published union all select * from seed_acnc union all select * from seed_nsw) observed
  where not exists(select 1 from ingestion.suppressions z
   where (z.record_id=observed.record_id or z.organisation_id=p_organisation) and z.field in ('*','entity_name',observed.field))
  order by source_key,field,origin,published_at desc
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'field',field,'section',section,'label',case field
   when 'pbi' then 'Public Benevolent Institution (PBI)'
   when 'hpc' then 'Health Promotion Charity (HPC)'
   when 'other_names_text' then 'Other names (unclassified)'
   when 'responsible_person_count' then 'Responsible-person count'
   when 'beneficiaries.lgbtiqa_plus' then 'LGBTIQA+'
   else label end,
  'kind',kind,'value',value,
  'source_title',case when metadata->>'synthetic'='true' then 'Synthetic test data'
   else coalesce(metadata->>'public_title',source_id) end,
  'source_url',metadata->>'public_url','resource_id',resource_id,
  'licence',metadata->>'public_licence','licence_url',metadata->>'public_licence_url',
  'attribution',metadata->>'attribution',
  'observed_at',observed_at,'published_at',published_at,
  'effective_date',case when kind='date' then value#>>'{}' end,
  'unchanged_since_import',unchanged_since_import,
  'retained_address_components',case when kind='address' and jsonb_typeof(input_value)='object'
   then coalesce((select jsonb_agg(k order by k) from jsonb_object_keys(value) k
     where not input_value ? k),'[]'::jsonb) else '[]'::jsonb end
 ) order by section,field,source_id,resource_id,source_key),'[]'::jsonb)
 from latest);
end $$;
revoke all on function community_orgs.organisation_register_facts(uuid) from public,service_role;
grant execute on function community_orgs.organisation_register_facts(uuid) to anon,authenticated;
comment on function community_orgs.organisation_register_facts(uuid) is
 'Latest approved source observations per field/source identity for public organisations, from reviewed change sets and the full seed union (ACNC via source links, NSW Incorporated Associations via the verified identifier holder). Suppressed/hidden sources and private ingestion metadata are excluded; source disagreements remain separate.';

commit;

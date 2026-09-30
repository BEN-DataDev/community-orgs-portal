-- Public, allowlisted observations only. Never return staging envelopes, actor IDs,
-- internal record/version IDs, review notes, approval snapshots or raw source values.
create function community_orgs.organisation_register_facts(p_organisation uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from community_orgs.organisations where org_id=p_organisation and is_public)
  or (community_orgs.user_has_verified_mfa() and (auth.jwt()->>'aal') is distinct from 'aal2') then
  return '[]';
 end if;
 return (
 with latest as (
  select distinct on (sv.record_id,f->>'field')
   sv.record_id,p.published_at,i.observed_at,s.source_id,s.resource_id,s.metadata,f,
   m.field,m.section,m.label,m.kind,m.table_name,m.column_name,m.path,
   coalesce(fs.revision=(f->>'revision')::bigint+1,false) as unchanged_since_import
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
   and not exists(select 1 from ingestion.suppressions z
    where (z.record_id=sv.record_id or z.organisation_id=p_organisation) and z.field in ('*','entity_name',m.field))
   and (m.table_name<>'acnc_register_details' or exists(
    select 1 from community_orgs.acnc_register_details d
    where d.org_id=p_organisation and d.source_record_id=sv.record_id and d.is_public))
  -- Field revisions order writes even when transaction timestamps are identical.
  order by sv.record_id,f->>'field',(f->>'revision')::bigint desc,p.published_at desc,p.change_set_id desc
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'field',field,'section',section,'label',case field
   when 'pbi' then 'Public Benevolent Institution (PBI)'
   when 'hpc' then 'Health Promotion Charity (HPC)'
   when 'other_names_text' then 'Other names (unclassified)'
   when 'responsible_person_count' then 'Responsible-person count'
   when 'beneficiaries.lgbtiqa_plus' then 'LGBTIQA+'
   else label end,
  'kind',kind,'value',f->'source_value',
  'source_title',case when metadata->>'synthetic'='true' then 'Synthetic test data'
   else coalesce(metadata->>'public_title','ACNC Charity Register') end,
  'source_url',metadata->>'public_url','resource_id',resource_id,
  'licence',metadata->>'public_licence','licence_url',metadata->>'public_licence_url',
  'observed_at',observed_at,'published_at',published_at,
  'effective_date',case when kind='date' then f->>'source_value' end,
  'unchanged_since_import',unchanged_since_import,
  'retained_address_components',case when kind='address' and jsonb_typeof(f->'input_value')='object'
   then coalesce((select jsonb_agg(k order by k) from jsonb_object_keys(f->'source_value') k
     where not (f->'input_value') ? k),'[]'::jsonb) else '[]'::jsonb end
 ) order by section,field,source_id,resource_id,record_id),'[]'::jsonb)
 from latest);
end $$;
revoke all on function community_orgs.organisation_register_facts(uuid) from public,service_role;
grant execute on function community_orgs.organisation_register_facts(uuid) to anon,authenticated;
comment on function community_orgs.organisation_register_facts(uuid) is
 'Latest approved source observations per field/source identity for public organisations. Suppressed/hidden sources and private ingestion metadata are excluded; source disagreements remain separate.';

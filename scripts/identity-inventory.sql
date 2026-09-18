-- P14 read-only pre/post inventory. Keep the returned identifiers private.
-- One result makes this usable through both psql and the Supabase MCP server.
begin transaction isolation level repeatable read read only;
with legal as (
 select org_id,legal_id,abn,acn,incorporation_number,
 count(*) over(partition by org_id) as legal_rows_for_org,
 case when abn is null then 'absent' when replace(btrim(abn),' ','') ~ '^[0-9]{11}$' then 'shape only; checksum and registry review required' else 'malformed or empty' end as abn_review,
 case when incorporation_number is not null then 'unscoped; do not infer jurisdiction' end as incorporation_review
 from community_orgs.legal_details
), collisions as (
 select replace(btrim(abn),' ','') as normalized_display_abn,
 jsonb_agg(jsonb_build_object('org_id',org_id,'legal_id',legal_id)) as competing_rows
 from community_orgs.legal_details where nullif(btrim(abn),'') is not null
 group by replace(btrim(abn),' ','') having count(*)>1
), links as (
 select l.record_id,l.organisation_id,r.source_id,r.resource_id,r.native_id
 from ingestion.source_links l join ingestion.source_records r on r.id=l.record_id
), entities as (
 select o.org_id,o.entity_name,
 (select count(*) from community_orgs.programs_services p where p.org_id=o.org_id) as existing_services
 from community_orgs.organisations o
)
select jsonb_build_object(
 'counts',jsonb_build_object(
 'organisations',(select count(*) from community_orgs.organisations),
 'legal_rows',(select count(*) from community_orgs.legal_details),
 'roles',(select count(*) from community_orgs.user_organisation_roles),
 'relationships',(select count(*) from community_orgs.relationships),
 'services',(select count(*) from community_orgs.programs_services),
 'publications',(select count(*) from ingestion.publications),
 'suppressions',(select count(*) from ingestion.suppressions),
 'source_links',(select count(*) from ingestion.source_links)),
 'fingerprints',jsonb_build_object(
 'organisations',(select md5(coalesce(jsonb_agg(to_jsonb(o) order by org_id)::text,'')) from community_orgs.organisations o),
 'legal',(select md5(coalesce(jsonb_agg(to_jsonb(l) order by legal_id)::text,'')) from community_orgs.legal_details l),
 'roles',(select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,'')) from community_orgs.user_organisation_roles r),
 'relationships',(select md5(coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text)::text,'')) from community_orgs.relationships r),
 'services',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by program_id)::text,'')) from community_orgs.programs_services p),
 'publications',(select md5(coalesce(jsonb_agg(to_jsonb(p) order by change_set_id)::text,'')) from ingestion.publications p),
 'suppressions',(select md5(coalesce(jsonb_agg(to_jsonb(s) order by to_jsonb(s)::text)::text,'')) from ingestion.suppressions s),
 'links',(select md5(coalesce(jsonb_agg(to_jsonb(l) order by record_id)::text,'')) from links l)),
 'legal',(select coalesce(jsonb_agg(to_jsonb(l) order by org_id,legal_id),'[]') from legal l),
 'collisions',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from collisions c),
 'links',(select coalesce(jsonb_agg(to_jsonb(l) order by record_id),'[]') from links l),
 'entities',(select coalesce(jsonb_agg(to_jsonb(e) order by org_id),'[]') from entities e)
) as inventory;
rollback;

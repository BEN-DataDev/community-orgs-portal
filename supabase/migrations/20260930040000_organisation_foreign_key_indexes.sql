-- Parent deletion and ordinary organisation lookups require indexes on populated
-- child foreign keys. The baseline constraints did not create these automatically.
begin;

create index if not exists legal_details_org_id_idx
  on community_orgs.legal_details(org_id);
create index if not exists contact_info_org_id_idx
  on community_orgs.contact_info(org_id);
create index if not exists aliases_org_id_idx
  on community_orgs.aliases(org_id);
create index if not exists source_links_organisation_id_idx
  on ingestion.source_links(organisation_id);
create index if not exists publications_organisation_id_idx
  on ingestion.publications(organisation_id);
create index if not exists change_sets_organisation_id_idx
  on ingestion.change_sets(organisation_id);
create index if not exists identifier_claims_org_id_idx
  on ingestion.identifier_claims(org_id);
create index if not exists reviews_organisation_id_idx
  on ingestion.reviews(organisation_id);
create index if not exists suppressions_organisation_id_idx
  on ingestion.suppressions(organisation_id);

commit;

-- Foreign keys that parent deletes and review/report joins walk, flagged
-- unindexed by the performance advisor. The *_by user references stay
-- unindexed: users are never deleted in bulk and nothing joins on them.
begin;

create index if not exists run_records_version_id_idx
  on ingestion.run_records(version_id);
create index if not exists change_sets_run_id_idx
  on ingestion.change_sets(run_id);
create index if not exists change_sets_version_id_idx
  on ingestion.change_sets(version_id);
create index if not exists validation_issues_candidate_version_id_idx
  on ingestion.validation_issues(candidate_version_id);
create index if not exists registry_seed_candidate_facets_candidate_id_idx
  on ingestion.registry_seed_candidate_facets(candidate_id);
create index if not exists acnc_register_details_source_record_id_idx
  on community_orgs.acnc_register_details(source_record_id);

commit;

begin;

create index full_seed_items_organisation_idx
  on ingestion.full_seed_items(organisation_id);

commit;

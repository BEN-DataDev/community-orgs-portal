-- The only holder index is partial (verified ABN keys), so the
-- identifier_keys_holder_fkey check scanned every identifier key for each deleted
-- organisation. Index the foreign key itself.
begin;

create index if not exists identifier_keys_holder_idx
  on ingestion.identifier_keys(holder);

commit;

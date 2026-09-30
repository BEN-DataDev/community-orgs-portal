-- Complete-snapshot reconciliation (P27) was never deployed, so this function
-- referenced objects that do not exist and had no callers. A future reconciliation
-- migration can reintroduce it alongside its tables; run_portal_scope_revision stays.
begin;

drop function ingestion.reconciliation_missing_reason(bigint, bigint);

commit;

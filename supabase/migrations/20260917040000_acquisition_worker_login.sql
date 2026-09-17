-- Password is provisioned separately into the selected worker host's secret store.
-- NOINHERIT requires the worker's explicit SET LOCAL ROLE ingestion_worker.
create role community_orgs_acquisition login noinherit nosuperuser nocreatedb
 nocreaterole noreplication nobypassrls connection limit 2;
grant ingestion_worker to community_orgs_acquisition;
alter role community_orgs_acquisition set statement_timeout='30s';
alter role community_orgs_acquisition set lock_timeout='10s';
alter role community_orgs_acquisition set idle_in_transaction_session_timeout='30s';

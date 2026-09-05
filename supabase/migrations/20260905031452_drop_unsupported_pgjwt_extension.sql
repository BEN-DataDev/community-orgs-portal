-- pgjwt is unsupported on newer Postgres images and blocks the platform upgrade.
-- It arrived from Supabase's old default project template, not from any migration
-- in this repo.
--
-- Nothing in this database depends on it: no user-defined function outside
-- pg_catalog/information_schema references sign/verify/url_encode/url_decode/
-- algorithm_sign, and the extension owns only its own six functions.
--
-- Deliberately not CASCADE, so an unexpected dependency fails loudly.
drop extension if exists pgjwt;

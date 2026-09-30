-- Catalog-only ACL regression check. Reads pg_proc and privileges; writes nothing,
-- so it may run against any fully migrated database.
do $$
declare exposed text;
begin
  -- Renamed predecessors (rename-and-wrap pattern) must only be reachable
  -- through their wrapper, never directly by a client role.
  select string_agg(n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ')
    into exposed
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('community_orgs', 'ingestion', 'portal')
    and p.proname ~ '_before_'
    and (has_function_privilege('anon', p.oid, 'execute')
      or has_function_privilege('authenticated', p.oid, 'execute')
      or has_function_privilege('service_role', p.oid, 'execute'));
  if exposed is not null then
    raise exception 'Superseded functions executable by a client role: %', exposed;
  end if;

  select string_agg(p.oid::regprocedure::text, ', ') into exposed
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'community_orgs'
    and p.proname in ('prepare_full_seed_union', 'apply_full_seed_union_batch', 'full_seed_union_status')
    and (has_function_privilege('anon', p.oid, 'execute')
      or has_function_privilege('authenticated', p.oid, 'execute')
      or has_function_privilege('service_role', p.oid, 'execute'));
  if exposed is not null then
    raise exception 'Retired or internal functions executable by a client role: %', exposed;
  end if;

  -- Referenced never-deployed P27 objects; dropped by 20260930232653.
  if to_regprocedure('ingestion.reconciliation_missing_reason(bigint,bigint)') is not null then
    raise exception 'Broken reconciliation_missing_reason still exists';
  end if;

  if to_regprocedure('community_orgs.configure_acnc_acquisition(text,text[],text,integer,text)') is not null then
    raise exception 'Superseded five-argument configure_acnc_acquisition still exists';
  end if;

  if pg_get_functiondef('community_orgs.revise_publication_release(uuid,integer,jsonb,text)'::regprocedure)
     !~ 'is_data_steward\(\)' then
    raise exception 'revise_publication_release must require a Data Steward';
  end if;
end
$$;

-- Hosted Postgres rejects UPDATE statements without a WHERE clause. Identity
-- audit uses a singleton clock, so scope the increment explicitly.
begin;

create or replace function ingestion.identity_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update ingestion.identity_clock set revision = revision + 1 where singleton;
  insert into ingestion.identity_events(action, subject, before_value, after_value, actor)
  values (
    TG_OP,
    TG_TABLE_NAME,
    case when TG_OP <> 'INSERT' then to_jsonb(old) end,
    case when TG_OP <> 'DELETE' then to_jsonb(new) end,
    auth.uid()
  );
  return coalesce(new, old);
end
$$;

commit;

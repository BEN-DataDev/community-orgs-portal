-- Four tables in `public` had RLS switched off while `anon` held SELECT *and*
-- INSERT -- the advisor's only ERROR-level findings. Nothing in this repo
-- creates or references them (no migration, no call site in src/), and they
-- carry no data: all four are empty apart from a single health_status row.
-- They look like leftovers from something that previously used this project.
--
-- Enabling RLS without policies makes them deny-all for anon and authenticated
-- while service_role, which holds BYPASSRLS, keeps full access. That closes an
-- open write endpoint without dropping tables whose provenance is unclear.
--
-- If one of these turns out to back a live feature, the fix is to add the
-- policy it needs, not to switch RLS back off. `health_status` in particular
-- may be read by an uptime check; if so it wants an explicit
-- `for select to anon using (true)` policy rather than blanket exposure.

-- Guarded, because these four tables belong to the sibling bendev-web project,
-- which shares this Postgres instance. Nothing in this repository creates them,
-- so an unconditional ALTER makes the migration set unappliable to a fresh
-- database -- `supabase migration up` against an empty local stack fails here
-- with 42P01, which is the reproducibility problem finding 02 was about.
--
-- Skipping absent tables is the honest behaviour: on a database where they do
-- not exist, there is no open write endpoint to close.

do $$
declare
    t text;
begin
    foreach t in array array[
        'public.address_users',
        'public.conversation_messages',
        'public.health_status',
        'public.projects'
    ] loop
        if to_regclass(t) is null then
            raise notice 'skipping %, not present in this database', t;
        else
            execute format('alter table %s enable row level security', t);
        end if;
    end loop;
end;
$$;

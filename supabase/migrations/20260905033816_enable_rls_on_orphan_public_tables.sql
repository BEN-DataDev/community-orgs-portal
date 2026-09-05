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

alter table public.address_users enable row level security;
alter table public.conversation_messages enable row level security;
alter table public.health_status enable row level security;
alter table public.projects enable row level security;

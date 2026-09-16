-- App-level administration, independent of organisation membership and ingestion.
create schema platform_access;
revoke all on schema platform_access from public, anon, authenticated, service_role;
create table platform_access.administrators (
 user_id uuid primary key references auth.users(id) on delete cascade,
 granted_at timestamptz not null default now(),
 reason text not null
);
alter table platform_access.administrators enable row level security;
revoke all on platform_access.administrators from public, anon, authenticated, service_role;

create function community_orgs.is_platform_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and (auth.jwt()->>'is_anonymous')::boolean is not true
 and (not community_orgs.user_has_verified_mfa() or coalesce(auth.jwt()->>'aal'='aal2',false))
 and exists(select 1 from platform_access.administrators where user_id=auth.uid());
$$;
revoke all on function community_orgs.is_platform_admin() from public, anon;
grant execute on function community_orgs.is_platform_admin() to authenticated;

create or replace function community_orgs.user_has_permission(p_user_id uuid,p_organisation_id uuid,p_permission text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_user_id=auth.uid() and community_orgs.is_platform_admin() and exists(select 1 from community_orgs.organisations where org_id=p_organisation_id) then return true; end if;
 return exists(select 1 from community_orgs.user_organisation_roles uor join community_orgs.roles r on r.id=uor.role_id
  where uor.user_id=p_user_id and uor.organisation_id=p_organisation_id and uor.is_active
  and (uor.expires_at is null or uor.expires_at>now()) and r.permissions->>p_permission='true');
end $$;
create or replace function community_orgs.user_max_role_level(p_user_id uuid,p_organisation_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
begin
 if p_user_id=auth.uid() and community_orgs.is_platform_admin() and exists(select 1 from community_orgs.organisations where org_id=p_organisation_id) then return 4; end if;
 return coalesce((select max(r.hierarchy_level) from community_orgs.user_organisation_roles uor join community_orgs.roles r on r.id=uor.role_id
  where uor.user_id=p_user_id and uor.organisation_id=p_organisation_id and uor.is_active and (uor.expires_at is null or uor.expires_at>now())),0);
end $$;
create or replace function community_orgs.can_view_org(p_org_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from community_orgs.organisations o where o.org_id=p_org_id and
 (o.is_public or community_orgs.is_platform_admin() or exists(select 1 from community_orgs.user_organisation_roles uor
 where uor.organisation_id=o.org_id and uor.user_id=auth.uid() and uor.is_active and (uor.expires_at is null or uor.expires_at>now()))));
$$;
create policy "platform admin read" on community_orgs.organisations for select to authenticated using ((select community_orgs.is_platform_admin()));
create policy "platform admin delete" on community_orgs.organisations for delete to authenticated using ((select community_orgs.is_platform_admin()));
create policy "platform admin roles" on community_orgs.roles for all to authenticated using ((select community_orgs.is_platform_admin())) with check ((select community_orgs.is_platform_admin()));
create policy "platform admin slugs" on community_orgs.reserved_slugs for all to authenticated using ((select community_orgs.is_platform_admin())) with check ((select community_orgs.is_platform_admin()));
-- If ingestion is already deployed, integrate the capability without deploying it.
do $migration$
begin
 if to_regprocedure('community_orgs.is_ingestion_operator()') is not null then
 execute $sql$create or replace function community_orgs.is_ingestion_operator() returns boolean
 language sql stable security definer set search_path='' as $body$
 select community_orgs.is_platform_admin() or (
 auth.uid() is not null and (auth.jwt()->>'is_anonymous')::boolean is not true
 and (not community_orgs.user_has_verified_mfa() or coalesce(auth.jwt()->>'aal'='aal2',false))
 and exists(select 1 from ingestion.operators where user_id=auth.uid()));
 $body$ $sql$;
 end if;
end $migration$;

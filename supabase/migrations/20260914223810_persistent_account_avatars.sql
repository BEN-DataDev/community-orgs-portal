-- Keep provider URLs independent of the application's persistent avatar choice.
alter table public.users
    add column avatar_path text,
    add column avatar_source text not null default 'provider',
    add column avatar_revision integer not null default 0,
    add constraint users_avatar_source_check check (avatar_source in ('provider', 'upload', 'initials')),
    add constraint users_avatar_path_check check (
        (avatar_source = 'upload' and avatar_path is not null
         and avatar_path ~ ('^' || id::text || '/avatar-[0-9a-f-]{36}\.webp$'))
        or (avatar_source <> 'upload' and avatar_path is null)
    );

-- A restrictive policy composes with existing owner-only policies rather than
-- accidentally granting access through an additional permissive policy.
create policy "account profile requires permanent verified session" on public.users
as restrictive to authenticated
using (
    coalesce((select auth.jwt()->>'is_anonymous'), 'true') = 'false'
    and (not community_orgs.user_has_verified_mfa() or (select auth.jwt()->>'aal') = 'aal2')
)
with check (
    coalesce((select auth.jwt()->>'is_anonymous'), 'true') = 'false'
    and (not community_orgs.user_has_verified_mfa() or (select auth.jwt()->>'aal') = 'aal2')
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Preserve legacy owner read/insert policies, but constrain every avatar access
-- even if another permissive storage policy is added later.
create policy "avatar access requires owner and verified permanent session" on storage.objects
as restrictive to authenticated
using (
    bucket_id <> 'avatars' or (
        (storage.foldername(name))[1] = (select auth.uid())::text
        and coalesce((select auth.jwt()->>'is_anonymous'), 'true') = 'false'
        and (not community_orgs.user_has_verified_mfa() or (select auth.jwt()->>'aal') = 'aal2')
    )
)
with check (
    bucket_id <> 'avatars' or (
        (storage.foldername(name))[1] = (select auth.uid())::text
        and coalesce((select auth.jwt()->>'is_anonymous'), 'true') = 'false'
        and (not community_orgs.user_has_verified_mfa() or (select auth.jwt()->>'aal') = 'aal2')
    )
);
create policy "avatar owner reads" on storage.objects for select to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatar owner uploads" on storage.objects for insert to authenticated
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatar owner deletes" on storage.objects for delete to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- The daily job deletes these through the Storage API, never by deleting SQL
-- metadata. Only filenames created by this feature are eligible. A 24-hour
-- grace period protects uploads which have not yet committed their profile.
create function community_orgs.abandoned_account_avatars()
returns table (path text)
language sql stable security definer set search_path = ''
as $$
    select o.name from storage.objects o
    where o.bucket_id = 'avatars'
      and o.name ~ '^[0-9a-f-]{36}/avatar-[0-9a-f-]{36}\.webp$'
      and o.created_at < now() - interval '24 hours'
      and not exists (select 1 from public.users u where u.avatar_path = o.name)
    order by o.created_at limit 100;
$$;
revoke all on function community_orgs.abandoned_account_avatars() from public, anon, authenticated;
grant execute on function community_orgs.abandoned_account_avatars() to service_role;

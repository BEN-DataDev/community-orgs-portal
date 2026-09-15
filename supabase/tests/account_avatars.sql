-- Run as postgres; fixtures, Storage metadata and profile changes roll back.
begin;
-- Permit deletion of synthetic Storage metadata only inside this rolled-back test.
set local storage.allow_delete_query = 'true';
do $$
declare
    actor uuid := gen_random_uuid();
    stranger uuid := gen_random_uuid();
    object_path text;
    affected integer;
    blocked boolean;
begin
    insert into auth.users(id, email, created_at, updated_at)
    values (actor, actor || '@example.invalid', now(), now()),
           (stranger, stranger || '@example.invalid', now(), now());
    object_path := actor::text || '/avatar-' || gen_random_uuid()::text || '.webp';
    perform set_config('request.jwt.claims', jsonb_build_object('sub',actor,'role','authenticated','is_anonymous',false,'aal','aal1')::text, true);
    set local role authenticated;
    insert into storage.objects(bucket_id,name,owner_id) values ('avatars',object_path,actor::text);
    update public.users set avatar_source='upload', avatar_path=object_path, avatar_revision=1 where id=actor;
    get diagnostics affected = row_count;
    if affected <> 1 then raise exception 'Owner avatar update failed'; end if;
    update public.users set avatar_source='initials', avatar_path=null where id=stranger;
    get diagnostics affected = row_count;
    if affected <> 0 then raise exception 'Cross-user profile update succeeded'; end if;
    blocked := false;
    begin
        insert into storage.objects(bucket_id,name) values ('avatars',stranger::text || '/other.webp');
    exception when insufficient_privilege then blocked := true;
    end;
    if not blocked then raise exception 'Cross-user upload succeeded'; end if;
    reset role;

    -- Provider refreshes never mutate the explicitly chosen upload.
    update auth.users set raw_user_meta_data='{"avatar_url":"https://example.invalid/new.png"}' where id=actor;
    if (select avatar_path from public.users where id=actor) is distinct from object_path then
        raise exception 'Auth metadata update replaced upload';
    end if;

    perform set_config('request.jwt.claims', jsonb_build_object('sub',actor,'role','authenticated','is_anonymous',true,'aal','aal1')::text, true);
    set local role authenticated;
    if exists(select 1 from storage.objects where bucket_id='avatars' and name=object_path) then raise exception 'Guest read avatar'; end if;
    update public.users set avatar_source='initials', avatar_path=null where id=actor;
    get diagnostics affected = row_count;
    if affected <> 0 then raise exception 'Guest changed profile'; end if;
    blocked := false;
    begin
        insert into storage.objects(bucket_id,name) values ('avatars',actor::text || '/guest.webp');
    exception when insufficient_privilege then blocked := true;
    end;
    if not blocked then raise exception 'Guest upload succeeded'; end if;
    reset role;

    insert into auth.mfa_factors(id,user_id,friendly_name,factor_type,status,secret,created_at,updated_at)
    values(gen_random_uuid(),actor,'avatar-test','totp','verified','fixture',now(),now());
    perform set_config('request.jwt.claims', jsonb_build_object('sub',actor,'role','authenticated','is_anonymous',false,'aal','aal1')::text, true);
    set local role authenticated;
    if exists(select 1 from storage.objects where bucket_id='avatars' and name=object_path) then raise exception 'MFA bypass read'; end if;
    delete from storage.objects where bucket_id='avatars' and name=object_path;
    get diagnostics affected = row_count;
    if affected <> 0 then raise exception 'MFA bypass delete'; end if;
    reset role;
    perform set_config('request.jwt.claims', jsonb_build_object('sub',actor,'role','authenticated','is_anonymous',false,'aal','aal2')::text, true);
    set local role authenticated;
    if not exists(select 1 from storage.objects where bucket_id='avatars' and name=object_path) then raise exception 'Verified owner cannot read'; end if;
    -- Compare-and-swap: stale revision must not overwrite current avatar.
    update public.users set avatar_source='initials',avatar_path=null,avatar_revision=2 where id=actor and avatar_revision=0;
    get diagnostics affected = row_count;
    if affected <> 0 then raise exception 'Stale revision overwrote avatar'; end if;
    update public.users set avatar_source='initials',avatar_path=null,avatar_revision=2 where id=actor and avatar_revision=1;
    get diagnostics affected = row_count;
    if affected <> 1 then raise exception 'Owner removal failed'; end if;
    delete from storage.objects where bucket_id='avatars' and name=object_path;
    get diagnostics affected = row_count;
    if affected <> 1 then raise exception 'Owner cannot delete old avatar'; end if;
    reset role;

    -- Only old, unreferenced, managed filenames may be cleaned up.
    insert into storage.objects(bucket_id,name,created_at)
    values ('avatars',object_path,now()-interval '2 days');
    if not exists(select 1 from community_orgs.abandoned_account_avatars() where path=object_path) then raise exception 'Orphan not eligible'; end if;
    update public.users set avatar_source='upload',avatar_path=object_path where id=actor;
    if exists(select 1 from community_orgs.abandoned_account_avatars() where path=object_path) then raise exception 'Live avatar eligible for cleanup'; end if;
    update public.users set avatar_source='initials',avatar_path=null where id=actor;
    update storage.objects set created_at=now() where bucket_id='avatars' and name=object_path;
    if exists(select 1 from community_orgs.abandoned_account_avatars() where path=object_path) then raise exception 'Fresh upload eligible for cleanup'; end if;
    if has_function_privilege('authenticated', 'community_orgs.abandoned_account_avatars()', 'execute') then raise exception 'Cleanup exposed'; end if;
end;
$$;
rollback;

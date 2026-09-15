-- Auth remains the source of truth. Do not expose auth.sessions, refresh_tokens,
-- or the unrelated legacy public.sessions table through the Data API.
create function community_orgs.require_account_management_session()
returns uuid language plpgsql stable security definer set search_path = ''
as $$
declare current_session uuid;
begin
    if auth.uid() is null or coalesce(auth.jwt()->>'is_anonymous','true') <> 'false' then
        raise exception 'A permanent account is required' using errcode='42501';
    end if;
    if community_orgs.user_has_verified_mfa() and (auth.jwt()->>'aal') is distinct from 'aal2' then
        raise exception 'Complete multi-factor authentication' using errcode='42501';
    end if;
    current_session := nullif(auth.jwt()->>'session_id','')::uuid;
    if not exists(select 1 from auth.sessions s where s.id=current_session and s.user_id=auth.uid()
                  and (s.not_after is null or s.not_after > now())) then
        raise exception 'A current session is required' using errcode='42501';
    end if;
    return current_session;
end;
$$;
revoke all on function community_orgs.require_account_management_session() from public, anon, authenticated;

create function community_orgs.get_account_sessions()
returns table(session_id uuid, is_current boolean, signed_in_at timestamptz,
              last_refreshed_at timestamptz, expires_at timestamptz, user_agent text, total_count bigint)
language plpgsql stable security definer set search_path = ''
as $$
declare current_session uuid;
begin
    current_session := community_orgs.require_account_management_session();
    return query
        select s.id, s.id=current_session, s.created_at,
               s.refreshed_at at time zone 'UTC', s.not_after,
               left(s.user_agent,512), count(*) over ()
        from auth.sessions s
        where s.user_id=auth.uid() and (s.not_after is null or s.not_after > now())
        order by (s.id=current_session) desc, coalesce(s.refreshed_at at time zone 'UTC',s.created_at) desc, s.id
        limit 100;
end;
$$;
revoke all on function community_orgs.get_account_sessions() from public, anon;
grant execute on function community_orgs.get_account_sessions() to authenticated;

-- There is no per-session-ID logout method in the installed Auth SDK. Deleting
-- an owned Auth session mirrors Supabase logout; refresh_tokens cascade via its
-- existing FK. Never select or return those tokens. No Auth schema DDL is used.
create function community_orgs.revoke_account_session(p_session_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare current_session uuid;
begin
    current_session := community_orgs.require_account_management_session();
    if p_session_id = current_session then
        raise exception 'Use sign out for the current session' using errcode='22023';
    end if;
    delete from auth.sessions where id=p_session_id and user_id=auth.uid();
    return found;
end;
$$;
revoke all on function community_orgs.revoke_account_session(uuid) from public, anon;
grant execute on function community_orgs.revoke_account_session(uuid) to authenticated;

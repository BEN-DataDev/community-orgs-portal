-- Run as postgres. All fixtures and revocations roll back.
begin;
do $$
declare
 actor uuid := gen_random_uuid(); stranger uuid := gen_random_uuid();
 current_id uuid := gen_random_uuid(); other_id uuid := gen_random_uuid(); foreign_id uuid := gen_random_uuid();
 blocked boolean; n integer;
begin
 insert into auth.users(id,email,created_at,updated_at) values
 (actor,actor||'@example.invalid',now(),now()),(stranger,stranger||'@example.invalid',now(),now());
 insert into auth.sessions(id,user_id,created_at,updated_at) values
 (current_id,actor,now(),now()),(other_id,actor,now(),now()),(foreign_id,stranger,now(),now());
 insert into auth.refresh_tokens(token,user_id,session_id,created_at,updated_at)
 values(gen_random_uuid()::text,actor::text,other_id,now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','is_anonymous',false,'aal','aal1','session_id',current_id)::text,true);
 set local role authenticated;
 select count(*) into n from community_orgs.get_account_sessions();
 if n <> 2 then raise exception 'Session ownership filter failed'; end if;
 if (select session_id from community_orgs.get_account_sessions() limit 1) <> current_id then raise exception 'Current session not first'; end if;
 if community_orgs.revoke_account_session(foreign_id) then raise exception 'Cross-user revocation succeeded'; end if;
 blocked := false;
 begin perform community_orgs.revoke_account_session(current_id); exception when invalid_parameter_value then blocked := true; end;
 if not blocked then raise exception 'Current session revocable through RPC'; end if;
 if not community_orgs.revoke_account_session(other_id) then raise exception 'Owner revocation failed'; end if;
 if community_orgs.revoke_account_session(other_id) then raise exception 'Missing session not idempotent'; end if;
 reset role;
 if exists(select 1 from auth.refresh_tokens where session_id=other_id) then raise exception 'Refresh tokens did not cascade'; end if;
 if not exists(select 1 from auth.sessions where id=foreign_id) then raise exception 'Foreign session deleted'; end if;
 -- Guests and callers with no live session cannot list or revoke sessions.
 for n in 1..3 loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','is_anonymous',n=1,'aal','aal1','session_id',case when n=2 then other_id else current_id end)::text,true);
  if n=3 then update auth.sessions set not_after=now()-interval '1 second' where id=current_id; end if;
  set local role authenticated;
  blocked := false;
  begin perform community_orgs.get_account_sessions(); exception when insufficient_privilege then blocked := true; end;
  if not blocked then raise exception 'Invalid caller listed sessions: %',n; end if;
  blocked := false;
  begin perform community_orgs.revoke_account_session(foreign_id); exception when insufficient_privilege then blocked := true; end;
  if not blocked then raise exception 'Invalid caller reached revocation: %',n; end if;
  reset role;
 end loop;
 update auth.sessions set not_after=null where id=current_id;
 insert into auth.mfa_factors(id,user_id,friendly_name,factor_type,status,secret,created_at,updated_at)
 values(gen_random_uuid(),actor,'session-test','totp','verified','fixture',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','is_anonymous',false,'aal','aal1','session_id',current_id)::text,true);
 set local role authenticated;
 blocked := false;
 begin perform community_orgs.get_account_sessions(); exception when insufficient_privilege then blocked := true; end;
 if not blocked then raise exception 'MFA bypass'; end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','is_anonymous',false,'aal','aal2','session_id',current_id)::text,true);
 insert into auth.sessions(id,user_id,created_at,updated_at) select gen_random_uuid(),actor,now(),now() from generate_series(1,105);
 set local role authenticated;
 select count(*) into n from community_orgs.get_account_sessions();
 if n <> 100 then raise exception 'Session limit failed'; end if;
 if (select total_count from community_orgs.get_account_sessions() limit 1) <> 106 then raise exception 'Session total failed'; end if;
 if (select session_id from community_orgs.get_account_sessions() limit 1) <> current_id then raise exception 'Current session truncated'; end if;
 reset role;
 if has_function_privilege('anon','community_orgs.get_account_sessions()','execute') then raise exception 'Anonymous listing allowed'; end if;
 if has_function_privilege('anon','community_orgs.revoke_account_session(uuid)','execute') then raise exception 'Anonymous revocation allowed'; end if;
 if has_function_privilege('authenticated','community_orgs.require_account_management_session()','execute') then raise exception 'Internal helper exposed'; end if;
end;
$$;
rollback;

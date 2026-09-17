begin;
create function pg_temp.refused(command text) returns void language plpgsql as $$
begin
 begin execute command;
 exception when others then return;
 end;
 raise exception 'Unexpected success: %',command;
end $$;
insert into auth.users(id) select ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(801,807) n;
update auth.users set is_anonymous=true where id='00000000-0000-4000-8000-000000000807';
insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values
 ('00000000-0000-4000-8000-000000000811','P08 A','p08-a',false),
 ('00000000-0000-4000-8000-000000000812','P08 B','p08-b',false);
insert into platform_access.administrators(user_id,reason) values ('00000000-0000-4000-8000-000000000805','P08');
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000806');
insert into community_orgs.user_organisation_roles(user_id,organisation_id,role_id)
 select ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'00000000-0000-4000-8000-000000000811',r.id
 from (values (801,'owner'),(802,'admin'),(803,'member')) a(n,name) join community_orgs.roles r on r.name=a.name;
do $$
declare
 org uuid:='00000000-0000-4000-8000-000000000811'; other_org uuid:='00000000-0000-4000-8000-000000000812';
 owner_id uuid:='00000000-0000-4000-8000-000000000801'; admin_id uuid:='00000000-0000-4000-8000-000000000802';
 target uuid:='00000000-0000-4000-8000-000000000804'; platform_id uuid:='00000000-0000-4000-8000-000000000805';
 member uuid; owner_role uuid; test_role uuid; actor uuid; result jsonb; assignment uuid;
begin
 select id into member from community_orgs.roles where name='member';
 select id into owner_role from community_orgs.roles where name='owner';
 -- Reader, member, moderator, expired and inactive managers, operator, guest.
 for test_role in select id from community_orgs.roles where name in ('member','moderator','admin') loop
  delete from community_orgs.user_organisation_roles where user_id='00000000-0000-4000-8000-000000000803';
  insert into community_orgs.user_organisation_roles(user_id,organisation_id,role_id,expires_at)
  select '00000000-0000-4000-8000-000000000803',org,r.id,case when r.name='admin' then now()-interval '1 day' else null end from community_orgs.roles r where r.id=test_role;
  for actor in select ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid from generate_series(803,807) n loop
   if actor='00000000-0000-4000-8000-000000000805' then continue; end if;
   set local role authenticated;
   perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'aal','aal1','is_anonymous',actor='00000000-0000-4000-8000-000000000807')::text,true);
   perform pg_temp.refused(format('select community_orgs.organisation_role_assignments(%L)',org));
   perform pg_temp.refused(format('select community_orgs.grant_user_role(%L,%L,%L,%L)',target,org,test_role,owner_id));
   perform pg_temp.refused(format('select community_orgs.revoke_user_role(%L,%L,%L,%L)',owner_id,org,member,owner_id));
   reset role;
  end loop;
 end loop;
 set local role anon;
 perform set_config('request.jwt.claims','{}',true);
 perform pg_temp.refused(format('select community_orgs.organisation_role_assignments(%L)',org));
 reset role;
 set local role authenticated;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'aal','aal1')::text,true);
 result:=community_orgs.organisation_role_assignments(org);
 if jsonb_array_length(result->'assignments')<>3 or (result->>'level')::int<>3 then raise exception 'Roster incomplete'; end if;
 perform pg_temp.refused(format('select community_orgs.organisation_role_assignments(%L)',other_org));
 perform pg_temp.refused(format('select community_orgs.grant_user_role(%L,%L,%L,%L)',target,other_org,member,admin_id));
 perform pg_temp.refused(format('select community_orgs.grant_user_role(%L,%L,%L,%L)',target,org,owner_role,admin_id));
 perform pg_temp.refused(format('select community_orgs.grant_user_role(%L,%L,%L,%L)',owner_id,org,member,admin_id));
 perform pg_temp.refused(format('select community_orgs.revoke_user_role(%L,%L,%L,%L)',owner_id,org,member,admin_id));
 perform pg_temp.refused(format('select community_orgs.grant_user_role(%L,%L,%L,%L)', '00000000-0000-4000-8000-000000000807',org,member,admin_id));
 assignment:=community_orgs.grant_user_role(target,org,member,owner_id);
 if not exists(select 1 from community_orgs.role_audit_log where user_id=target and performed_by=admin_id and action='granted') then raise exception 'Forged audit actor'; end if;
 if community_orgs.grant_user_role(target,org,member,owner_id)<>assignment then raise exception 'Replay duplicated'; end if;
 if not community_orgs.revoke_user_role(target,org,member,owner_id,'test') then raise exception 'Revoke failed'; end if;
 if community_orgs.revoke_user_role(target,org,member,owner_id,'test') then raise exception 'Repeated revoke succeeded'; end if;
 perform pg_temp.refused(format('insert into community_orgs.user_organisation_roles(user_id,organisation_id,role_id) values(%L,%L,%L)',target,org,member));
 perform pg_temp.refused('update community_orgs.user_organisation_roles set is_active=false');
 perform pg_temp.refused('delete from community_orgs.user_organisation_roles');
 -- Expiry/revocation removes authority even for an existing session.
 reset role;
 update community_orgs.user_organisation_roles set expires_at=now()-interval '1 day' where user_id=admin_id;
 set local role authenticated;
 perform pg_temp.refused(format('select community_orgs.organisation_role_assignments(%L)',org));
 perform pg_temp.refused(format('select community_orgs.grant_user_role(%L,%L,%L,%L)',target,org,member,admin_id));
 reset role;
 update community_orgs.user_organisation_roles set expires_at=null,is_active=false where user_id=admin_id;
 set local role authenticated;
 perform pg_temp.refused(format('select community_orgs.organisation_role_assignments(%L)',org));
 -- Owner cannot self-revoke, add expiring owner, or expire an assignment in the past.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'aal','aal1')::text,true);
 perform pg_temp.refused(format('select community_orgs.revoke_user_role(%L,%L,%L,%L)',owner_id,org,owner_role,owner_id));
 perform pg_temp.refused(format('select community_orgs.grant_user_role(%L,%L,%L,%L,now()+interval ''1 day'')',target,org,owner_role,owner_id));
 perform pg_temp.refused(format('select community_orgs.grant_user_role(%L,%L,%L,%L,now()-interval ''1 day'')',target,org,member,owner_id));
 -- Independent platform authority still cannot remove the sole owner.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',platform_id,'aal','aal1')::text,true);
 perform community_orgs.organisation_role_assignments(other_org);
 perform pg_temp.refused(format('select community_orgs.revoke_user_role(%L,%L,%L,%L)',owner_id,org,owner_role,platform_id));
 perform community_orgs.grant_user_role(target,org,owner_role,owner_id);
 if not community_orgs.revoke_user_role(owner_id,org,owner_role,owner_id,'Transfer') then raise exception 'Transfer failed'; end if;
 perform pg_temp.refused(format('select community_orgs.revoke_user_role(%L,%L,%L,%L)',target,org,owner_role,platform_id));
 -- MFA at AAL1, absent assurance, then AAL2 for both reads and writes.
 reset role;
 insert into auth.mfa_factors(user_id,status) values(platform_id,'verified');
 set local role authenticated;
 for result in select jsonb_build_object('sub',platform_id,'aal','aal1') union all select jsonb_build_object('sub',platform_id) loop
  perform set_config('request.jwt.claims',result::text,true);
  perform pg_temp.refused(format('select community_orgs.organisation_role_assignments(%L)',org));
  perform pg_temp.refused(format('select community_orgs.grant_user_role(%L,%L,%L,%L)',target,org,member,owner_id));
  perform pg_temp.refused(format('select community_orgs.revoke_user_role(%L,%L,%L,%L)',target,org,member,owner_id));
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',platform_id,'aal','aal2')::text,true);
 perform community_orgs.organisation_role_assignments(org);
 perform community_orgs.grant_user_role(target,org,member,owner_id);
 perform community_orgs.revoke_user_role(target,org,member,owner_id);
 reset role;
end $$;
rollback;

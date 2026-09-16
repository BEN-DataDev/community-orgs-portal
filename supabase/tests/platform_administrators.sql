begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000088');
insert into platform_access.administrators(user_id,reason) values ('00000000-0000-4000-8000-000000000088','Synthetic test');
insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values ('00000000-0000-4000-8000-000000000087','Private fixture','platform-test',false);
do $$
begin
 set local role authenticated;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000088","aal":"aal2"}',true);
 if not community_orgs.is_platform_admin() or community_orgs.user_max_role_level(auth.uid(),'00000000-0000-4000-8000-000000000087')<>4 or not community_orgs.can_edit_org('00000000-0000-4000-8000-000000000087') then raise exception 'Admin capability missing'; end if;
 if not exists(select 1 from community_orgs.organisations where org_id='00000000-0000-4000-8000-000000000087') then raise exception 'Private RLS read failed'; end if;
 if community_orgs.user_has_permission('00000000-0000-4000-8000-000000000089','00000000-0000-4000-8000-000000000087','can_manage_members') then raise exception 'Other-user privilege leaked'; end if;
 begin insert into platform_access.administrators values(auth.uid(),now(),'self'); raise exception 'Self grant allowed'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000088","is_anonymous":true,"aal":"aal2"}',true);
 if community_orgs.is_platform_admin() then raise exception 'Anonymous allowed'; end if;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000089","aal":"aal2"}',true);
 if community_orgs.is_platform_admin() or exists(select 1 from community_orgs.organisations where org_id='00000000-0000-4000-8000-000000000087') then raise exception 'Non-admin allowed'; end if;
 reset role;
 delete from platform_access.administrators where user_id='00000000-0000-4000-8000-000000000088';
 set local role authenticated;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000088","aal":"aal2"}',true);
 if community_orgs.is_platform_admin() then raise exception 'Revocation failed'; end if;
 reset role;
end $$;
rollback;

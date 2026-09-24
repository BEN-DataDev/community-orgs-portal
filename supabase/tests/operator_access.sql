-- Run as postgres after all portal/ingestion migrations. All fixtures roll back.
begin;
create function pg_temp.expect_access_denied(command text) returns void
language plpgsql as $$
begin
 execute command;
 raise exception 'Unexpected access: %', command;
exception when insufficient_privilege then null;
end $$;

insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000000701'),
 ('00000000-0000-4000-8000-000000000702'),
 ('00000000-0000-4000-8000-000000000703');
insert into community_orgs.organisations(org_id,entity_name,slug,is_public) values
 ('00000000-0000-4000-8000-000000000711','P07 private A','p07-a',false),
 ('00000000-0000-4000-8000-000000000712','P07 private B','p07-b',false);
insert into ingestion.operators(user_id) values ('00000000-0000-4000-8000-000000000702');
insert into platform_access.administrators(user_id,reason)
 values ('00000000-0000-4000-8000-000000000703','P07 synthetic administrator');

-- Every exposed ingestion read/mutation must deny before inspecting its inputs.
-- Successful operator workflows are exercised by ingestion_review/publication.sql.
create function pg_temp.expect_no_ingestion_access() returns void language plpgsql as $$
declare command text;
begin
 if community_orgs.is_ingestion_operator() or community_orgs.is_platform_admin() then
  raise exception 'Unexpected global capability';
 end if;
 foreach command in array array[
  'select community_orgs.ingestion_review_queue()',
  'select community_orgs.ingestion_reprocessing_report(''1'')',
  'select community_orgs.ingestion_field_preview(''1'',''1'')',
  'select community_orgs.ingestion_field_approvals(''1'')',
  'select community_orgs.ingestion_withdrawal_status(''1'')',
  'select community_orgs.save_ingestion_review(''1'',''1'',0,''defer'',null,''P07'')',
  'select community_orgs.approve_ingestion_fields(''1'',''1'',1,''[]'')',
  'select community_orgs.publish_ingestion_fields(''00000000-0000-4000-8000-000000000799'')',
  'select community_orgs.suppress_ingestion_content(''1'',''1'',''*'',''P07'',''{}'')',
  'select community_orgs.acquisition_dashboard()',
  'select community_orgs.enqueue_acnc_acquisition(''p07'')',
  'select community_orgs.ingestion_source_approvals()',
  'select community_orgs.set_ingestion_source_enabled(''acnc-register'',''p07'',true,''bad'',''P07'')',
  'select community_orgs.configure_acnc_acquisition(''p07'',array[''2730''],''P07'',null,''0'')'
 ] loop
  perform pg_temp.expect_access_denied(command);
 end loop;
end $$;

do $$
declare
 actor uuid := '00000000-0000-4000-8000-000000000701';
 operator_id uuid := '00000000-0000-4000-8000-000000000702';
 admin_id uuid := '00000000-0000-4000-8000-000000000703';
 org_a uuid := '00000000-0000-4000-8000-000000000711';
 org_b uuid := '00000000-0000-4000-8000-000000000712';
 resource text := '00000000-0000-4000-8000-000000000790';
 token text; job text; scenario text; expected integer; actual integer; uid uuid; rel record; fn record;
begin
 -- Default grants and future migrations must not expose private tables/functions.
 for rel in select c.oid,c.relname,n.nspname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('ingestion','platform_access') and c.relkind in ('r','p') loop
  if has_table_privilege('authenticated',rel.oid,'SELECT,INSERT,UPDATE,DELETE')
   or has_table_privilege('anon',rel.oid,'SELECT,INSERT,UPDATE,DELETE') then
   raise exception 'Private table grant leaked: %.%',rel.nspname,rel.relname;
  end if;
 end loop;
 for fn in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='ingestion' loop
  if has_function_privilege('authenticated',fn.oid,'EXECUTE') or has_function_privilege('anon',fn.oid,'EXECUTE') then
   raise exception 'Private function grant leaked: %',fn.proname;
  end if;
 end loop;
 foreach scenario in array array['none','member','moderator','admin','owner','expired','inactive'] loop
  delete from community_orgs.user_organisation_roles where user_id=actor;
  expected := case scenario when 'member' then 1 when 'moderator' then 2 when 'admin' then 3 when 'owner' then 4 else 0 end;
  if scenario <> 'none' then
   insert into community_orgs.user_organisation_roles(user_id,organisation_id,role_id,is_active,expires_at)
   select actor,org_a,id,scenario<>'inactive',case when scenario='expired' then now()-interval '1 day' end
   from community_orgs.roles where name=case when scenario in ('expired','inactive') then 'owner' else scenario end;
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'aal','aal1','is_anonymous',false)::text,true);
  set local role authenticated;
  perform pg_temp.expect_no_ingestion_access();
  if community_orgs.user_max_role_level(actor,org_a)<>expected
   or community_orgs.can_edit_org(org_a) is distinct from (expected>=3)
   or community_orgs.can_view_org(org_a) is distinct from (expected>0)
   or community_orgs.can_edit_org(org_b) or community_orgs.can_view_org(org_b) then
   raise exception 'Organisation scope/role mismatch: %',scenario;
  end if;
  select count(*) into actual from community_orgs.organisations where org_id in (org_a,org_b);
  if actual<>(case when expected>0 then 1 else 0 end) then raise exception 'Private organisation RLS mismatch: %',scenario; end if;
  update community_orgs.organisations set description='P07 permitted correction' where org_id=org_a;
  get diagnostics actual=row_count;
  if actual<>(case when expected>=3 then 1 else 0 end) then raise exception 'Edit RLS mismatch: %',scenario; end if;
  update community_orgs.organisations set description='P07 forbidden correction' where org_id=org_b;
  get diagnostics actual=row_count;
  if actual<>0 then raise exception 'Cross-organisation edit'; end if;
  reset role;
 end loop;

 -- Test conditional MFA using the real helper reading auth.mfa_factors, not JWT test flags.
 foreach uid in array array[operator_id,admin_id] loop
  foreach scenario in array array['unenrolled','aal1','missing','aal2','guest','no_subject'] loop
   delete from auth.mfa_factors where user_id=uid;
   if scenario<>'unenrolled' then insert into auth.mfa_factors(user_id,status) values(uid,'verified'); end if;
   perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object(
    'sub',case when scenario='no_subject' then null else uid end,
    'aal',case when scenario='missing' then null when scenario in ('unenrolled','aal1') then 'aal1' else 'aal2' end,
    'is_anonymous',scenario='guest'))::text,true);
   set local role authenticated;
   if scenario in ('unenrolled','aal2') then
    if community_orgs.is_ingestion_operator()<>(uid=operator_id)
       or community_orgs.is_platform_admin()<>(uid=admin_id) then
     raise exception 'Appointment/MFA capability mismatch: %, %',uid,scenario;
    end if;
    if uid=operator_id then
     perform community_orgs.ingestion_review_queue();
     perform community_orgs.acquisition_dashboard();
     if community_orgs.can_view_org(org_a) or community_orgs.can_edit_org(org_a) then raise exception 'Operator obtained ordinary organisation access'; end if;
     perform pg_temp.expect_access_denied('select community_orgs.ingestion_source_approvals()');
     perform pg_temp.expect_access_denied('select community_orgs.set_ingestion_source_enabled(''acnc-register'',''p07'',true,''bad'',''P07'')');
     perform pg_temp.expect_access_denied('select community_orgs.configure_acnc_acquisition(''p07'',array[''2730''],''P07'',null,''0'')');
    else
     perform pg_temp.expect_access_denied('select community_orgs.ingestion_review_queue()');
     perform pg_temp.expect_access_denied('select community_orgs.acquisition_dashboard()');
     perform community_orgs.ingestion_source_approvals();
     if community_orgs.user_max_role_level(uid,org_b)<>4 or not community_orgs.can_edit_org(org_b) then raise exception 'Administrator lacks effective owner authority'; end if;
     select count(*) into actual from community_orgs.organisations where org_id in (org_a,org_b);
     if actual<>2 then raise exception 'Administrator private RLS failed'; end if;
    end if;
    perform pg_temp.expect_access_denied('insert into ingestion.operators(user_id) values(auth.uid())');
    perform pg_temp.expect_access_denied('insert into platform_access.administrators(user_id,reason) values(auth.uid(),''self'')');
    perform pg_temp.expect_access_denied('select * from ingestion.source_record_versions');
    perform pg_temp.expect_access_denied('select ingestion.stage_acnc(''{}'')');
    perform pg_temp.expect_access_denied('select community_orgs.enqueue_due_acquisitions()');
   else
    perform pg_temp.expect_no_ingestion_access();
   end if;
   reset role;
  end loop;
  delete from auth.mfa_factors where user_id=uid;
 end loop;

 -- Exercise actual administrator configuration and operator enqueue, without a worker.
 insert into ingestion.sources(source_id,resource_id,metadata,enabled)
 values('acnc-register',resource,'{"test":"P07 disposable fixture"}',false);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'aal','aal1')::text,true);
 set local role authenticated;
 select x->>'token' into token from jsonb_array_elements(community_orgs.ingestion_source_approvals()) x
 where x->>'resource_id'=resource;
 perform community_orgs.set_ingestion_source_enabled('acnc-register',resource,true,token,'P07 fixture approval');
 perform community_orgs.configure_acnc_acquisition(resource,array['2730'],'P07 fixture licence',null,'0');
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',operator_id,'aal','aal1')::text,true);
 set local role authenticated;
 job := community_orgs.enqueue_acnc_acquisition(resource);
 if job is null or community_orgs.enqueue_acnc_acquisition(resource)<>job then raise exception 'Operator enqueue/reuse failed'; end if;
 reset role;
 if not exists(select 1 from ingestion.acquisition_jobs where id=job::uuid and requested_by=operator_id)
  or not exists(select 1 from ingestion.source_approval_events where resource_id=resource and changed_by=admin_id)
  or not exists(select 1 from ingestion.acquisition_config_events where resource_id=resource and changed_by=admin_id) then
  raise exception 'Global action actor audit mismatch';
 end if;

 -- Revocation takes effect with the same JWT, preserving an independent org role.
 insert into community_orgs.user_organisation_roles(user_id,organisation_id,role_id,is_active)
 select operator_id,org_a,id,true from community_orgs.roles where name='admin';
 delete from ingestion.operators where user_id=operator_id;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',operator_id,'aal','aal1')::text,true);
 set local role authenticated;
 perform pg_temp.expect_no_ingestion_access();
 if not community_orgs.can_edit_org(org_a) then raise exception 'Operator revocation lost independent org role'; end if;
 reset role;
 delete from platform_access.administrators where user_id=admin_id;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'aal','aal1')::text,true);
 set local role authenticated;
 perform pg_temp.expect_no_ingestion_access();
 if community_orgs.can_edit_org(org_a) then raise exception 'Revoked administrator retained effective owner'; end if;
 reset role;

 -- Signed-out calls cannot execute global API functions, even without the portal.
 set local role anon;
 perform set_config('request.jwt.claims','{}',true);
 perform pg_temp.expect_access_denied('select community_orgs.is_platform_admin()');
 perform pg_temp.expect_access_denied('select community_orgs.is_ingestion_operator()');
 perform pg_temp.expect_access_denied('select community_orgs.ingestion_review_queue()');
 perform pg_temp.expect_access_denied('select community_orgs.publish_ingestion_fields(null)');
 reset role;
end $$;
rollback;
select 'P07 role scope, global RPC denial, private grants, conditional MFA and appointment revocation passed' as result;

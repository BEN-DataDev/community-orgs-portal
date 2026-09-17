-- Disposable harness only. All fixture writes roll back.
begin;
grant usage on schema community_orgs to service_role;
create or replace function community_orgs.is_platform_admin() returns boolean language sql as $$
 select coalesce(auth.jwt()->>'test_admin','false')='true' $$;
insert into auth.users values('00000000-0000-4000-8000-000000000091');
insert into ingestion.operators(user_id) values('00000000-0000-4000-8000-000000000091');
insert into ingestion.sources(source_id,resource_id,metadata,enabled) values
 ('acnc-register','00000000-0000-4000-8000-000000000090','{}',true);
do $$
declare resource text:='00000000-0000-4000-8000-000000000090'; v_job uuid; j jsonb; k jsonb; e jsonb; r bigint; n bigint; token uuid;
begin
 select count(*) into n from community_orgs.organisations;
 if has_function_privilege('authenticated','ingestion.claim_acquisition()','EXECUTE')
 or has_function_privilege('authenticated','community_orgs.enqueue_due_acquisitions()','EXECUTE')
 or has_function_privilege('service_role','ingestion.finish_acquisition(uuid,uuid)','EXECUTE')
 or has_table_privilege('ingestion_worker','ingestion.acquisition_jobs','UPDATE')
 or has_table_privilege('anon','ingestion.acquisition_jobs','SELECT') then raise exception 'Excess privileges'; end if;
 set local role authenticated;
 perform set_config('request.jwt.claims','{}',true);
 begin perform community_orgs.acquisition_dashboard(); raise exception 'Expected denial'; exception when insufficient_privilege then null; end;
 begin perform community_orgs.enqueue_acnc_acquisition(resource); raise exception 'Expected denial'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000091"}',true);
 begin perform community_orgs.configure_acnc_acquisition(resource,'2730','Reviewed licence',null,'0'); raise exception 'Expected admin denial'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000091","test_admin":true}',true);
 perform community_orgs.configure_acnc_acquisition(resource,'2730','Reviewed licence',null,'0');
 begin perform community_orgs.configure_acnc_acquisition(resource,'2730','Reviewed licence',null,'0'); raise exception 'Expected stale denial'; exception when serialization_failure then null; end;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000091"}',true);
 v_job:=community_orgs.enqueue_acnc_acquisition(resource)::uuid;
 if community_orgs.enqueue_acnc_acquisition(resource)::uuid<>v_job then raise exception 'Duplicate job'; end if;
 reset role;
 set local role ingestion_worker;
 j:=ingestion.claim_acquisition(); token:=(j->>'lease_token')::uuid;
 if (j->>'id')::uuid<>v_job or ingestion.claim_acquisition() is not null then raise exception 'Overlapping claim'; end if;
 begin perform ingestion.heartbeat_acquisition(v_job,gen_random_uuid()); raise exception 'Expected token denial'; exception when serialization_failure then null; end;
 e:=jsonb_build_object('contract_version','1.0','source_id','acnc-register','resource_id',resource,'run_id','acnc-job-'||v_job::text,
 'parser_version','acnc-ckan-v3','observed_at',now(),'completion','complete','publication_eligible',false,'synthetic',false,
 'scope',jsonb_build_object('kind','filtered-resource','filters',jsonb_build_object('Postcode','2730')),
 'records','[]'::jsonb,'quarantine','[]'::jsonb,'errors','[]'::jsonb,'pages','[]'::jsonb,'qualification',jsonb_build_object('limits',j->'config'));
 begin perform ingestion.checkpoint_acquisition(v_job,token,jsonb_set(e,'{resource_id}','"wrong"')); raise exception 'Expected envelope denial'; exception when invalid_parameter_value then null; end;
 perform ingestion.checkpoint_acquisition(v_job,token,e);
 reset role;
 update ingestion.acquisition_jobs set lease_until=now()-interval '1 second' where acquisition_jobs.id=v_job;
 set local role ingestion_worker;
 k:=ingestion.claim_acquisition();
 if k->'checkpoint' is distinct from e or k->>'attempt'<>'2' then raise exception 'Checkpoint not recovered'; end if;
 begin perform ingestion.finish_acquisition(v_job,token); raise exception 'Expected stale worker denial'; exception when serialization_failure then null; end;
 r:=ingestion.finish_acquisition(v_job,(k->>'lease_token')::uuid);
 reset role;
 if not exists(select 1 from ingestion.acquisition_jobs where acquisition_jobs.id=v_job and status='complete' and run_id=r) then raise exception 'Atomic finish missing'; end if;
 if (select count(*) from ingestion.ingestion_runs where run_key='acnc-job-'||v_job::text)<>1 then raise exception 'Duplicate staged run'; end if;
 -- Source pause/re-enable invalidates a running lease and its checkpoint.
 v_job:=community_orgs.enqueue_acnc_acquisition(resource)::uuid;
 j:=ingestion.claim_acquisition();
 update ingestion.sources set enabled=false,approval_revision=approval_revision+1 where resource_id=resource;
 begin perform ingestion.heartbeat_acquisition(v_job,(j->>'lease_token')::uuid); raise exception 'Expected pause denial'; exception when object_not_in_prerequisite_state then null; end;
 begin perform community_orgs.enqueue_acnc_acquisition(resource); raise exception 'Expected enqueue pause denial'; exception when object_not_in_prerequisite_state then null; end;
 update ingestion.sources set enabled=true,approval_revision=approval_revision+1 where resource_id=resource;
 if ingestion.claim_acquisition() is not null then raise exception 'Resumed obsolete job'; end if;
 -- Retry delay and terminal cap.
 v_job:=community_orgs.enqueue_acnc_acquisition(resource)::uuid;
 for i in 1..3 loop
  j:=ingestion.claim_acquisition();
  perform ingestion.fail_acquisition(v_job,(j->>'lease_token')::uuid);
  if ingestion.claim_acquisition() is not null then raise exception 'Retry ignored backoff'; end if;
  update ingestion.acquisition_jobs set available_at=now()-interval '1 second' where acquisition_jobs.id=v_job;
 end loop;
 if not exists(select 1 from ingestion.acquisition_jobs where acquisition_jobs.id=v_job and status='failed' and attempts=3) then raise exception 'Retry cap missing'; end if;
 -- Scheduling starts off, is bounded, and never stages/publishes in the cron transaction.
 if community_orgs.enqueue_due_acquisitions()<>0 then raise exception 'Schedule enabled by default'; end if;
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000091","test_admin":true}',true);
 perform community_orgs.configure_acnc_acquisition(resource,'2730','Reviewed licence',24,'1');
 update ingestion.acquisition_configs set next_due_at=now()-interval '1 day';
 set local role service_role;
 if community_orgs.enqueue_due_acquisitions()<>1 or community_orgs.enqueue_due_acquisitions()<>0 then raise exception 'Schedule duplicate'; end if;
 reset role;
 v_job:=(select acquisition_jobs.id from ingestion.acquisition_jobs where status='queued' and resource_id=resource);
 perform community_orgs.configure_acnc_acquisition(resource,'2731','Reviewed licence',null,'2');
 if not exists(select 1 from ingestion.acquisition_jobs where acquisition_jobs.id=v_job and status='cancelled') then raise exception 'Config change failed to cancel'; end if;
 if (select count(*) from community_orgs.organisations)<>n then raise exception 'Acquisition published data'; end if;
 if (select count(*) from ingestion.acquisition_config_events where resource_id=resource)<>3 then raise exception 'Configuration audit missing'; end if;
 raise notice 'Acquisition permissions, fencing, checkpoints, retries, pause, configuration and scheduling passed';
end $$;
rollback;

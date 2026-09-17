-- Bounded acquisition queue. No publication privileges or public evidence access.
create table ingestion.acquisition_configs (
 source_id text not null default 'acnc-register' check(source_id='acnc-register'),
 resource_id text not null,
 postcode text not null check(postcode ~ '^[0-9]{4}$'),
 licence_title text not null check(length(trim(licence_title)) between 1 and 300),
 interval_hours integer check(interval_hours in (24,168,720)),
 next_due_at timestamptz,
 revision bigint not null default 1,
 updated_by uuid not null,
 updated_at timestamptz not null default now(),
 primary key(source_id,resource_id),
 foreign key(source_id,resource_id) references ingestion.sources
);
create table ingestion.acquisition_jobs (
 id uuid primary key default gen_random_uuid(),
 source_id text not null,
 resource_id text not null,
 config_revision bigint not null,
 source_revision bigint not null,
 config jsonb not null,
 origin text not null check(origin in ('manual','schedule')),
 requested_by uuid,
 status text not null default 'queued' check(status in ('queued','running','complete','partial','failed','cancelled')),
 attempts integer not null default 0 check(attempts between 0 and 3),
 available_at timestamptz not null default now(),
 lease_token uuid,
 lease_until timestamptz,
 checkpoint jsonb,
 run_id bigint references ingestion.ingestion_runs,
 message text,
 created_at timestamptz not null default now(),
 finished_at timestamptz,
 foreign key(source_id,resource_id) references ingestion.acquisition_configs
);
create unique index acquisition_one_active on ingestion.acquisition_jobs(source_id,resource_id)
 where status in ('queued','running');
create index acquisition_ready on ingestion.acquisition_jobs(available_at) where status in ('queued','running');
create table ingestion.acquisition_config_events (
 id bigint generated always as identity primary key,
 source_id text not null, resource_id text not null, revision bigint not null,
 configuration jsonb not null, changed_by uuid not null, changed_at timestamptz not null default now()
);
alter table ingestion.acquisition_configs enable row level security;
alter table ingestion.acquisition_jobs enable row level security;
alter table ingestion.acquisition_config_events enable row level security;
revoke all on ingestion.acquisition_configs,ingestion.acquisition_jobs,ingestion.acquisition_config_events from public,anon,authenticated,service_role,ingestion_worker;
revoke all on sequence ingestion.acquisition_config_events_id_seq from public,anon,authenticated,service_role,ingestion_worker;

create function community_orgs.configure_acnc_acquisition(p_resource text,p_postcode text,p_licence text,p_interval integer,p_revision text)
returns void language plpgsql security definer set search_path='' as $$
declare c ingestion.acquisition_configs; s ingestion.sources;
begin
 if community_orgs.is_platform_admin() is distinct from true then raise exception 'Administrator required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(17093000);
 select * into s from ingestion.sources where source_id='acnc-register' and resource_id=p_resource for share;
 if not found or coalesce(s.metadata->>'synthetic','false')<>'false' then raise exception 'Live ACNC source required' using errcode='22023'; end if;
 perform p_resource::uuid;
 if p_postcode is null or p_postcode !~ '^[0-9]{4}$' or p_licence is null or length(trim(p_licence)) not between 1 and 300
 or (p_interval is not null and p_interval not in (24,168,720)) then raise exception 'Invalid acquisition configuration' using errcode='22023'; end if;
 select * into c from ingestion.acquisition_configs where source_id='acnc-register' and resource_id=p_resource for update;
 if coalesce(c.revision,0)::text is distinct from p_revision then raise exception 'Configuration changed' using errcode='40001'; end if;
 insert into ingestion.acquisition_configs(resource_id,postcode,licence_title,interval_hours,next_due_at,updated_by)
 values(p_resource,p_postcode,trim(p_licence),p_interval,case when p_interval is not null then now()+make_interval(hours=>p_interval) end,auth.uid())
 on conflict(source_id,resource_id) do update set postcode=excluded.postcode,licence_title=excluded.licence_title,
 interval_hours=excluded.interval_hours,next_due_at=excluded.next_due_at,revision=ingestion.acquisition_configs.revision+1,
 updated_by=excluded.updated_by,updated_at=now();
 insert into ingestion.acquisition_config_events(source_id,resource_id,revision,configuration,changed_by)
 select source_id,resource_id,revision,to_jsonb(x),auth.uid() from ingestion.acquisition_configs x where source_id='acnc-register' and resource_id=p_resource;
 update ingestion.acquisition_jobs set status='cancelled',finished_at=now(),lease_token=null,lease_until=null,message='Acquisition configuration changed.'
 where source_id='acnc-register' and resource_id=p_resource and status in ('queued','running');
end $$;

-- Only called by the authorised entry points below. Source lock serialises pauses.
create function ingestion.enqueue_acnc(p_resource text,p_origin text,p_actor uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare c ingestion.acquisition_configs; s ingestion.sources; job uuid;
begin
 perform pg_advisory_xact_lock(17093000);
 select * into s from ingestion.sources where source_id='acnc-register' and resource_id=p_resource for share;
 if not found or not s.enabled then raise exception 'Source paused' using errcode='55000'; end if;
 select * into c from ingestion.acquisition_configs where source_id=s.source_id and resource_id=s.resource_id;
 if not found then raise exception 'Configure acquisition first' using errcode='55000'; end if;
 -- A pause/re-enable invalidates previously queued work, even if no worker ran meanwhile.
 update ingestion.acquisition_jobs set status='cancelled',finished_at=now(),message='Source approval changed.',lease_token=null,lease_until=null
 where source_id=s.source_id and resource_id=s.resource_id and status in ('queued','running') and source_revision<>s.approval_revision;
 select id into job from ingestion.acquisition_jobs where source_id=s.source_id and resource_id=s.resource_id and status in ('queued','running');
 if job is not null then return job; end if;
 insert into ingestion.acquisition_jobs(source_id,resource_id,config_revision,source_revision,config,origin,requested_by)
 values(s.source_id,s.resource_id,c.revision,s.approval_revision,jsonb_build_object(
 'enabled',true,'resource_id',c.resource_id,'postcode',c.postcode,'expected_licence_title',c.licence_title,
 'page_size',100,'max_pages',5,'timeout_seconds',10,'deadline_seconds',120,'max_response_bytes',2097152),p_origin,p_actor)
 returning id into job;
 return job;
end $$;
create function community_orgs.enqueue_acnc_acquisition(p_resource text) returns text
language plpgsql security definer set search_path='' as $$
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 return ingestion.enqueue_acnc(p_resource,'manual',auth.uid())::text;
end $$;

create function community_orgs.enqueue_due_acquisitions() returns integer
language plpgsql security definer set search_path='' as $$
declare c record; n integer:=0;
begin
 perform pg_advisory_xact_lock(17093000);
 for c in select a.* from ingestion.acquisition_configs a join ingestion.sources s using(source_id,resource_id)
 where a.interval_hours is not null and a.next_due_at<=now() and s.enabled order by a.next_due_at limit 20 loop
  perform ingestion.enqueue_acnc(c.resource_id,'schedule',null);
  update ingestion.acquisition_configs set next_due_at=now()+make_interval(hours=>c.interval_hours)
   where source_id=c.source_id and resource_id=c.resource_id;
  n:=n+1;
 end loop;
 return n;
end $$;

create function community_orgs.acquisition_dashboard() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 return jsonb_build_object('sources',coalesce((select jsonb_agg(jsonb_build_object(
 'resource_id',s.resource_id,'enabled',s.enabled,'title',coalesce(s.metadata->>'public_title',s.source_id),
 'postcode',c.postcode,'licence_title',coalesce(c.licence_title,s.metadata->>'public_licence',''),
 'interval_hours',c.interval_hours,'next_due_at',c.next_due_at,'revision',coalesce(c.revision,0)::text)
 order by s.resource_id) from ingestion.sources s left join ingestion.acquisition_configs c using(source_id,resource_id)
 where s.source_id='acnc-register' and coalesce(s.metadata->>'synthetic','false')='false'),'[]'::jsonb),
 'jobs',coalesce((select jsonb_agg(to_jsonb(j)) from (select id::text,resource_id,status,origin,attempts,created_at,available_at,lease_until,
 finished_at,run_id::text,message,checkpoint is not null as acquired from ingestion.acquisition_jobs order by created_at desc limit 50) j),'[]'::jsonb));
end $$;

create function ingestion.claim_acquisition() returns jsonb
language plpgsql security definer set search_path='' as $$
declare j ingestion.acquisition_jobs;
begin
 perform pg_advisory_xact_lock(17093000);
 update ingestion.acquisition_jobs x set status='cancelled',finished_at=now(),message='Source paused or approval changed.',lease_token=null,lease_until=null
 from ingestion.sources s where x.source_id=s.source_id and x.resource_id=s.resource_id and x.status in ('queued','running')
 and (not s.enabled or x.source_revision<>s.approval_revision);
 update ingestion.acquisition_jobs set status='failed',finished_at=now(),message='Worker lease expired after three attempts.',lease_token=null,lease_until=null
 where status='running' and lease_until<=now() and attempts>=3;
 select * into j from ingestion.acquisition_jobs where (status='queued' and available_at<=now()) or (status='running' and lease_until<=now())
 order by available_at,created_at limit 1 for update;
 if not found then return null; end if;
 update ingestion.acquisition_jobs set status='running',attempts=attempts+1,lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes',message=null
 where id=j.id returning * into j;
 return jsonb_build_object('id',j.id,'lease_token',j.lease_token,'config',j.config,'checkpoint',j.checkpoint,'attempt',j.attempts);
end $$;

-- Fencing token, expiry, configuration and approval must all still match on every write.
create function ingestion.lock_acquisition(p_job uuid,p_token uuid) returns ingestion.acquisition_jobs
language plpgsql security definer set search_path='' as $$
declare j ingestion.acquisition_jobs; s ingestion.sources;
begin
 perform pg_advisory_xact_lock(17093000);
 select * into j from ingestion.acquisition_jobs where id=p_job for update;
 if not found or j.status<>'running' or j.lease_token is distinct from p_token or j.lease_until<=now() then
 raise exception 'Worker lease lost' using errcode='40001'; end if;
 select * into s from ingestion.sources where source_id=j.source_id and resource_id=j.resource_id for share;
 if not s.enabled or s.approval_revision<>j.source_revision then raise exception 'Source paused or approval changed' using errcode='55000'; end if;
 if not exists(select 1 from ingestion.acquisition_configs where source_id=j.source_id and resource_id=j.resource_id and revision=j.config_revision)
 then raise exception 'Configuration changed' using errcode='40001'; end if;
 return j;
end $$;
create function ingestion.heartbeat_acquisition(p_job uuid,p_token uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform ingestion.lock_acquisition(p_job,p_token);
 update ingestion.acquisition_jobs set lease_until=now()+interval '5 minutes' where id=p_job;
end $$;
create function ingestion.checkpoint_acquisition(p_job uuid,p_token uuid,p_envelope jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare j ingestion.acquisition_jobs;
begin
 j:=ingestion.lock_acquisition(p_job,p_token);
 if p_envelope->>'run_id' is distinct from 'acnc-job-'||j.id::text
 or p_envelope->>'source_id' is distinct from j.source_id or p_envelope->>'resource_id' is distinct from j.resource_id
 or p_envelope->'scope' is distinct from jsonb_build_object('kind','filtered-resource','filters',jsonb_build_object('Postcode',j.config->>'postcode'))
 or p_envelope->'qualification'->'limits' is distinct from j.config
 or p_envelope->'publication_eligible' is distinct from 'false'::jsonb
 or coalesce(p_envelope->>'completion','') not in ('complete','partial','failed')
 or p_envelope->>'parser_version' is distinct from 'acnc-ckan-v3'
 or coalesce((p_envelope->>'synthetic')::boolean,true)
 or (p_envelope->>'observed_at')::timestamptz < j.created_at
 or (p_envelope->>'observed_at')::timestamptz > now()+interval '1 minute'
 or p_envelope->>'observed_at' is null
 then raise exception 'Envelope does not match job' using errcode='22023'; end if;
 if j.checkpoint is not null and j.checkpoint is distinct from p_envelope then raise exception 'Checkpoint immutable' using errcode='40001'; end if;
 update ingestion.acquisition_jobs set checkpoint=p_envelope,lease_until=now()+interval '5 minutes' where id=p_job;
end $$;
create function ingestion.finish_acquisition(p_job uuid,p_token uuid) returns bigint
language plpgsql security definer set search_path='' as $$
declare j ingestion.acquisition_jobs; r bigint;
begin
 j:=ingestion.lock_acquisition(p_job,p_token);
 if j.checkpoint is null then raise exception 'Acquisition checkpoint required'; end if;
 r:=ingestion.stage_acnc(j.checkpoint);
 update ingestion.acquisition_jobs set status=j.checkpoint->>'completion',run_id=r,finished_at=now(),lease_token=null,lease_until=null,
 message=case when j.checkpoint->>'completion'='complete' then 'Ready for review.' else 'Incomplete acquisition; inspect the retained import errors. Publication is blocked.' end
 where id=p_job;
 return r;
end $$;
create function ingestion.fail_acquisition(p_job uuid,p_token uuid) returns void
language plpgsql security definer set search_path='' as $$
declare j ingestion.acquisition_jobs;
begin
 j:=ingestion.lock_acquisition(p_job,p_token);
 update ingestion.acquisition_jobs set status=case when attempts<3 then 'queued' else 'failed' end,
 available_at=now()+make_interval(secs=>60 * (2 ^ attempts)::integer),lease_token=null,lease_until=null,
 finished_at=case when attempts>=3 then now() end,
 message=case when attempts<3 then 'Worker could not finish. Retry queued.' else 'Worker could not finish after three attempts. Check worker diagnostics.' end
 where id=p_job;
end $$;

-- Restrict every entry point explicitly (including Supabase default grants).
revoke all on function community_orgs.configure_acnc_acquisition(text,text,text,integer,text),
 community_orgs.enqueue_acnc_acquisition(text),community_orgs.acquisition_dashboard(),community_orgs.enqueue_due_acquisitions()
 from public,anon,authenticated,service_role;
grant execute on function community_orgs.configure_acnc_acquisition(text,text,text,integer,text),
 community_orgs.enqueue_acnc_acquisition(text),community_orgs.acquisition_dashboard() to authenticated;
grant execute on function community_orgs.enqueue_due_acquisitions() to service_role;
revoke all on function ingestion.enqueue_acnc(text,text,uuid),ingestion.lock_acquisition(uuid,uuid),ingestion.claim_acquisition(),
 ingestion.heartbeat_acquisition(uuid,uuid),ingestion.checkpoint_acquisition(uuid,uuid,jsonb),
 ingestion.finish_acquisition(uuid,uuid),ingestion.fail_acquisition(uuid,uuid)
 from public,anon,authenticated,service_role,ingestion_worker;
grant execute on function ingestion.claim_acquisition(),ingestion.heartbeat_acquisition(uuid,uuid),
 ingestion.checkpoint_acquisition(uuid,uuid,jsonb),ingestion.finish_acquisition(uuid,uuid),ingestion.fail_acquisition(uuid,uuid) to ingestion_worker;

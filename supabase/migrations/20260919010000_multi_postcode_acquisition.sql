-- Expand ACNC acquisition from one postcode to a bounded canonical postcode cohort.
alter table ingestion.acquisition_configs
 drop constraint acquisition_configs_postcode_check;
alter table ingestion.acquisition_configs rename column postcode to postcodes;
alter table ingestion.acquisition_configs
 alter column postcodes type text[] using array[postcodes];
alter table ingestion.acquisition_configs
 add constraint acquisition_configs_postcodes_check check (
  cardinality(postcodes) between 1 and 50
  and array_position(postcodes,null) is null
  and array_to_string(postcodes,',') ~ '^[0-9]{4}(,[0-9]{4})*$'
 );

drop function community_orgs.configure_acnc_acquisition(text,text,text,integer,text);
create function community_orgs.configure_acnc_acquisition(
 p_resource text,p_postcodes text[],p_licence text,p_interval integer,p_revision text
) returns void language plpgsql security definer set search_path='' as $$
declare c ingestion.acquisition_configs; s ingestion.sources; canonical text[];
begin
 if community_orgs.is_platform_admin() is distinct from true then raise exception 'Administrator required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(17093000);
 select * into s from ingestion.sources where source_id='acnc-register' and resource_id=p_resource for share;
 if not found or coalesce(s.metadata->>'synthetic','false')<>'false' then raise exception 'Live ACNC source required' using errcode='22023'; end if;
 perform p_resource::uuid;
 select array_agg(x order by x) into canonical from (select distinct unnest(p_postcodes) x) v;
 if p_postcodes is null or cardinality(p_postcodes) not between 1 and 50
 or array_position(p_postcodes,null) is not null
 or exists(select 1 from unnest(p_postcodes) x where x !~ '^[0-9]{4}$')
 or p_postcodes is distinct from canonical
 or p_licence is null or length(trim(p_licence)) not between 1 and 300
 or (p_interval is not null and p_interval not in (24,168,720)) then raise exception 'Invalid acquisition configuration' using errcode='22023'; end if;
 select * into c from ingestion.acquisition_configs where source_id='acnc-register' and resource_id=p_resource for update;
 if coalesce(c.revision,0)::text is distinct from p_revision then raise exception 'Configuration changed' using errcode='40001'; end if;
 insert into ingestion.acquisition_configs(resource_id,postcodes,licence_title,interval_hours,next_due_at,updated_by)
 values(p_resource,p_postcodes,trim(p_licence),p_interval,case when p_interval is not null then now()+make_interval(hours=>p_interval) end,auth.uid())
 on conflict(source_id,resource_id) do update set postcodes=excluded.postcodes,licence_title=excluded.licence_title,
 interval_hours=excluded.interval_hours,next_due_at=excluded.next_due_at,revision=ingestion.acquisition_configs.revision+1,
 updated_by=excluded.updated_by,updated_at=now();
 insert into ingestion.acquisition_config_events(source_id,resource_id,revision,configuration,changed_by)
 select source_id,resource_id,revision,to_jsonb(x),auth.uid() from ingestion.acquisition_configs x where source_id='acnc-register' and resource_id=p_resource;
 update ingestion.acquisition_jobs set status='cancelled',finished_at=now(),lease_token=null,lease_until=null,message='Acquisition configuration changed.'
 where source_id='acnc-register' and resource_id=p_resource and status in ('queued','running');
end $$;

create or replace function ingestion.enqueue_acnc(p_resource text,p_origin text,p_actor uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare c ingestion.acquisition_configs; s ingestion.sources; job uuid;
begin
 perform pg_advisory_xact_lock(17093000);
 select * into s from ingestion.sources where source_id='acnc-register' and resource_id=p_resource for share;
 if not found or not s.enabled then raise exception 'Source paused' using errcode='55000'; end if;
 select * into c from ingestion.acquisition_configs where source_id=s.source_id and resource_id=s.resource_id;
 if not found then raise exception 'Configure acquisition first' using errcode='55000'; end if;
 update ingestion.acquisition_jobs set status='cancelled',finished_at=now(),message='Source approval changed.',lease_token=null,lease_until=null
 where source_id=s.source_id and resource_id=s.resource_id and status in ('queued','running') and source_revision<>s.approval_revision;
 select id into job from ingestion.acquisition_jobs where source_id=s.source_id and resource_id=s.resource_id and status in ('queued','running');
 if job is not null then return job; end if;
 insert into ingestion.acquisition_jobs(source_id,resource_id,config_revision,source_revision,config,origin,requested_by)
 values(s.source_id,s.resource_id,c.revision,s.approval_revision,jsonb_build_object(
 'enabled',true,'resource_id',c.resource_id,'postcodes',to_jsonb(c.postcodes),'expected_licence_title',c.licence_title,
 'page_size',100,'max_pages',10,'timeout_seconds',10,'deadline_seconds',120,'max_response_bytes',2097152),p_origin,p_actor)
 returning id into job;
 return job;
end $$;

create or replace function community_orgs.acquisition_dashboard() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 return jsonb_build_object('sources',coalesce((select jsonb_agg(jsonb_build_object(
 'resource_id',s.resource_id,'enabled',s.enabled,'title',coalesce(s.metadata->>'public_title',s.source_id),
 'postcodes',c.postcodes,'licence_title',coalesce(c.licence_title,s.metadata->>'public_licence',''),
 'interval_hours',c.interval_hours,'next_due_at',c.next_due_at,'revision',coalesce(c.revision,0)::text)
 order by s.resource_id) from ingestion.sources s left join ingestion.acquisition_configs c using(source_id,resource_id)
 where s.source_id='acnc-register' and coalesce(s.metadata->>'synthetic','false')='false'),'[]'::jsonb),
 'jobs',coalesce((select jsonb_agg(to_jsonb(j)) from (select id::text,resource_id,status,origin,attempts,created_at,available_at,lease_until,
 finished_at,run_id::text,message,checkpoint is not null as acquired from ingestion.acquisition_jobs order by created_at desc limit 50) j),'[]'::jsonb));
end $$;

create or replace function ingestion.checkpoint_acquisition(p_job uuid,p_token uuid,p_envelope jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare j ingestion.acquisition_jobs;
begin
 j:=ingestion.lock_acquisition(p_job,p_token);
 if p_envelope->>'run_id' is distinct from 'acnc-job-'||j.id::text
 or p_envelope->>'source_id' is distinct from j.source_id or p_envelope->>'resource_id' is distinct from j.resource_id
 or p_envelope->'scope' is distinct from jsonb_build_object('kind','filtered-resource','filters',jsonb_build_object('Postcode',j.config->'postcodes'))
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

revoke all on function community_orgs.configure_acnc_acquisition(text,text[],text,integer,text)
 from public,anon,authenticated,service_role;
grant execute on function community_orgs.configure_acnc_acquisition(text,text[],text,integer,text) to authenticated;

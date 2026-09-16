-- Source controls remain private; only platform administrators can use these RPCs.
alter table ingestion.sources add column approval_revision bigint not null default 0;
create table ingestion.source_approval_events (
 id bigint generated always as identity primary key,
 source_id text not null,
 resource_id text not null,
 enabled boolean not null,
 reason text not null,
 changed_by uuid not null,
 changed_at timestamptz not null default now(),
 revision bigint not null,
 foreign key (source_id,resource_id) references ingestion.sources,
 unique(source_id,resource_id,revision)
);
alter table ingestion.source_approval_events enable row level security;
revoke all on ingestion.source_approval_events from public, anon, authenticated;

create function community_orgs.ingestion_source_approvals() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
 if not community_orgs.is_platform_admin() then
  raise exception 'Platform administrator required' using errcode='42501';
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'source_id',s.source_id,'resource_id',s.resource_id,'enabled',s.enabled,
  'metadata',s.metadata,'token',md5(to_jsonb(s)::text),
  'runs',coalesce((select jsonb_agg(r) from (
    select id::text,run_key,completion,observed_at from ingestion.ingestion_runs
    where source_id=s.source_id and resource_id=s.resource_id order by id desc limit 10
  ) r),'[]'::jsonb),
  'history',coalesce((select jsonb_agg(e) from (
    select enabled,reason,changed_at,changed_by from ingestion.source_approval_events
    where source_id=s.source_id and resource_id=s.resource_id order by id desc limit 10
  ) e),'[]'::jsonb)
 ) order by s.source_id,s.resource_id) from ingestion.sources s),'[]'::jsonb);
end $$;

create function community_orgs.set_ingestion_source_enabled(
 p_source text,p_resource text,p_enabled boolean,p_token text,p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare s ingestion.sources;
begin
 if not community_orgs.is_platform_admin() then
  raise exception 'Platform administrator required' using errcode='42501';
 end if;
 if p_enabled is null or p_reason is null or length(trim(p_reason)) not between 1 and 2000 then
  raise exception 'A reason and status are required' using errcode='22023';
 end if;
 select * into s from ingestion.sources where source_id=p_source and resource_id=p_resource for update;
 if not found then raise exception 'Source not found' using errcode='P0002'; end if;
 if p_token is distinct from md5(to_jsonb(s)::text) or s.enabled=p_enabled then
  raise exception 'Source changed; reload before saving' using errcode='40001';
 end if;
 update ingestion.sources set enabled=p_enabled,approval_revision=approval_revision+1
 where source_id=p_source and resource_id=p_resource;
 insert into ingestion.source_approval_events(source_id,resource_id,enabled,reason,changed_by,revision)
 values(p_source,p_resource,p_enabled,trim(p_reason),auth.uid(),s.approval_revision+1);
end $$;
revoke all on function community_orgs.ingestion_source_approvals() from public,anon;
revoke all on function community_orgs.set_ingestion_source_enabled(text,text,boolean,text,text) from public,anon;
grant execute on function community_orgs.ingestion_source_approvals() to authenticated;
grant execute on function community_orgs.set_ingestion_source_enabled(text,text,boolean,text,text) to authenticated;

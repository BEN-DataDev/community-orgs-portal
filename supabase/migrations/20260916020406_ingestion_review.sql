-- Operators are appointed by a database administrator, never by organisation roles.
create table ingestion.operators (
 user_id uuid primary key references auth.users(id) on delete cascade,
 granted_at timestamptz not null default now()
);
create table ingestion.reviews (
 version_id bigint primary key references ingestion.source_record_versions,
 revision integer not null default 1,
 decision text not null check (decision in ('link','create','defer','reject')),
 organisation_id uuid references community_orgs.organisations(org_id),
 note text not null check (length(note) between 1 and 2000),
 reviewed_by uuid not null references auth.users(id),
 reviewed_at timestamptz not null default now(),
 check ((decision = 'link') = (organisation_id is not null))
);
create table ingestion.review_events (
 id bigint generated always as identity primary key,
 version_id bigint not null references ingestion.source_record_versions,
 revision integer not null,
 decision text not null,
 organisation_id uuid,
 note text not null,
 reviewed_by uuid not null,
 reviewed_at timestamptz not null,
 unique(version_id, revision)
);
alter table ingestion.operators enable row level security;
alter table ingestion.reviews enable row level security;
alter table ingestion.review_events enable row level security;
revoke all on ingestion.operators, ingestion.reviews, ingestion.review_events from public, anon, authenticated, service_role;

create function community_orgs.is_ingestion_operator() returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare platform_admin boolean := false;
begin
 if to_regprocedure('community_orgs.is_platform_admin()') is not null then
  execute 'select community_orgs.is_platform_admin()' into platform_admin;
 end if;
 return platform_admin or (auth.uid() is not null
 and coalesce((auth.jwt()->>'is_anonymous')::boolean,false) = false
 and (not community_orgs.user_has_verified_mfa() or coalesce(auth.jwt()->>'aal' = 'aal2', false))
 and exists(select 1 from ingestion.operators where user_id=auth.uid()));
end $$;
revoke all on function community_orgs.is_ingestion_operator() from public, anon;
grant execute on function community_orgs.is_ingestion_operator() to authenticated;

create function community_orgs.ingestion_review_queue(
 p_run text default null, p_version text default null, p_offset integer default 0,
 p_search text default ''
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 v_run bigint; v_version bigint; v_detail jsonb; v_name text; v_abn text;
 v_candidates jsonb := '[]'; v_runs jsonb; v_records jsonb; v_total bigint;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Ingestion operator access required' using errcode='42501';
 end if;
 if p_offset < 0 or p_offset > 1000000 or length(p_search)>100 then
  raise exception 'Invalid filter' using errcode='22023';
 end if;
 if p_run is null then select max(id) into v_run from ingestion.ingestion_runs;
 else v_run := p_run::bigint; end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_id desc),'[]') into v_runs from (
  select id::text as id, id as sort_id, source_id, resource_id, run_key, completion, observed_at
  from ingestion.ingestion_runs order by id desc limit 50
 ) x;
 if v_run is not null and not exists(select 1 from ingestion.ingestion_runs where id=v_run) then
  raise exception 'Run not found' using errcode='P0002';
 end if;
 select count(*) into v_total from ingestion.run_records where run_id=v_run;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_id),'[]') into v_records from (
  select v.id::text as id, v.id as sort_id, r.native_id,
   coalesce((select value #>> '{}' from ingestion.field_assertions
    where version_id=v.id and field='entity_name'),r.native_id) as name,
   coalesce(rv.decision,'pending') as decision
  from ingestion.run_records rr join ingestion.source_record_versions v on v.id=rr.version_id
  join ingestion.source_records r on r.id=v.record_id
  left join ingestion.reviews rv on rv.version_id=v.id
  where rr.run_id=v_run order by v.id limit 50 offset p_offset
 ) x;
 if p_version is not null then
  v_version := p_version::bigint;
  if not exists(select 1 from ingestion.run_records where run_id=v_run and version_id=v_version) then
   raise exception 'Record not in selected run' using errcode='P0002';
  end if;
  select jsonb_build_object('id',v.id::text,'native_id',r.native_id,
   'payload',v.payload,'review',case when rv.version_id is null then null else to_jsonb(rv) end)
  into v_detail from ingestion.source_record_versions v
  join ingestion.source_records r on r.id=v.record_id
  left join ingestion.reviews rv on rv.version_id=v.id where v.id=v_version;
  select value #>> '{}' into v_name from ingestion.field_assertions where version_id=v_version and field='entity_name';
  select value #>> '{}' into v_abn from ingestion.field_assertions where version_id=v_version and field='abn';
  select coalesce(jsonb_agg(to_jsonb(x) order by x.rank,x.entity_name),'[]') into v_candidates from (
   select o.org_id, o.entity_name, o.date_established, o.description,
    l.abn, c.website, c.physical_address, c.postal_address,
    case when v_abn is not null and l.abn=v_abn then 'Exact ABN (verify entity/branch scope)'
     when lower(o.entity_name)=lower(v_name) then 'Exact name (not proof of identity)'
     else 'Manual name search' end as reason,
    case when v_abn is not null and l.abn=v_abn then 0
     when lower(o.entity_name)=lower(v_name) then 1 else 2 end as rank
   from community_orgs.organisations o
   left join community_orgs.legal_details l on l.org_id=o.org_id
   left join community_orgs.contact_info c on c.org_id=o.org_id
   where (v_abn is not null and l.abn=v_abn) or lower(o.entity_name)=lower(v_name)
    or (length(trim(p_search))>=2 and position(lower(trim(p_search)) in lower(o.entity_name))>0)
   order by rank,o.entity_name,o.org_id limit 20
  ) x;
 end if;
 return jsonb_build_object('runs',v_runs,'run',v_run::text,'records',v_records,
  'total',v_total,'detail',v_detail,'candidates',v_candidates);
end $$;
revoke all on function community_orgs.ingestion_review_queue(text,text,integer,text) from public, anon;
grant execute on function community_orgs.ingestion_review_queue(text,text,integer,text) to authenticated;

create function community_orgs.save_ingestion_review(
 p_run text, p_version text, p_revision integer, p_decision text,
 p_organisation uuid default null, p_note text default ''
) returns void language plpgsql security definer set search_path = '' as $$
declare v_review ingestion.reviews;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then
  raise exception 'Ingestion operator access required' using errcode='42501';
 end if;
 if p_revision is null or p_revision<0 or p_decision is null
  or p_decision not in ('link','create','defer','reject')
  or p_note is null or length(trim(p_note)) not between 1 and 2000
  or ((p_decision='link') <> (p_organisation is not null)) then
  raise exception 'Invalid review decision' using errcode='22023';
 end if;
 if not exists(select 1 from ingestion.run_records where run_id=p_run::bigint and version_id=p_version::bigint) then
  raise exception 'Record not in selected run' using errcode='P0002';
 end if;
 -- A revision greater than zero must update an existing decision, never create one.
 if p_revision=0 then
  insert into ingestion.reviews(version_id,decision,organisation_id,note,reviewed_by)
   values(p_version::bigint,p_decision,p_organisation,trim(p_note),auth.uid())
   on conflict do nothing returning * into v_review;
 else
  update ingestion.reviews set decision=p_decision, organisation_id=p_organisation,
   note=trim(p_note), reviewed_by=auth.uid(), reviewed_at=now(), revision=revision+1
   where version_id=p_version::bigint and revision=p_revision returning * into v_review;
 end if;
 if v_review.version_id is null then
  raise exception 'Review changed; reload before saving' using errcode='40001';
 end if;
 insert into ingestion.review_events(version_id,revision,decision,organisation_id,note,reviewed_by,reviewed_at)
 values(v_review.version_id,v_review.revision,v_review.decision,v_review.organisation_id,
 v_review.note,v_review.reviewed_by,v_review.reviewed_at);
end $$;
revoke all on function community_orgs.save_ingestion_review(text,text,integer,text,uuid,text) from public, anon;
grant execute on function community_orgs.save_ingestion_review(text,text,integer,text,uuid,text) to authenticated;

revoke all on all sequences in schema ingestion from public, anon, authenticated, service_role;

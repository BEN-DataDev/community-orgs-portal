-- P34a: private, cross-source validation issues, revision-fenced decisions and
-- worker-executed derived runs. Nothing in this migration writes portal data.

create table ingestion.validation_issues (
 id bigint generated always as identity primary key,
 ingestion_run_id bigint references ingestion.ingestion_runs on delete restrict,
 registry_seed_release_id bigint references ingestion.registry_seed_releases on delete restrict,
 candidate_version_id bigint references ingestion.registry_seed_candidate_versions on delete restrict,
 subject_native_id text,
 source_row integer check(source_row is null or source_row>=0),
 source_key text,
 canonical_key text,
 code text not null check(code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
 category text not null check(category in ('field_format','missing_required_field','duplicate_identity',
  'record_integrity','record_scope','source_schema','mapping_unknown','acquisition_error','licence_or_qualification')),
 severity text not null check(severity in ('warning','blocking')),
 source_value jsonb,
 raw_evidence_hash text not null check(raw_evidence_hash ~ '^[0-9a-f]{64}$'),
 validator_name text not null check(length(trim(validator_name)) between 1 and 100),
 validator_version text not null check(length(trim(validator_version)) between 1 and 100),
 allowed_resolutions text[] not null default '{}',
 detail text not null check(length(trim(detail)) between 1 and 2000),
 created_at timestamptz not null default now(),
 redacted_at timestamptz,
 check(num_nonnulls(ingestion_run_id,registry_seed_release_id)=1),
 check(candidate_version_id is null or registry_seed_release_id is not null),
 check(allowed_resolutions <@ array['correct','omit','defer','reject_record']::text[]),
 check(category not in ('record_scope','source_schema','mapping_unknown','acquisition_error','licence_or_qualification')
  or allowed_resolutions='{}'::text[])
);
create unique index validation_issue_run_identity on ingestion.validation_issues(
 ingestion_run_id,coalesce(subject_native_id,''),coalesce(source_row,-1),coalesce(source_key,''),code,raw_evidence_hash)
 where ingestion_run_id is not null;
create unique index validation_issue_release_identity on ingestion.validation_issues(
 registry_seed_release_id,coalesce(candidate_version_id,0),coalesce(subject_native_id,''),coalesce(source_key,''),code,raw_evidence_hash)
 where registry_seed_release_id is not null;

create table ingestion.validation_resolutions (
 issue_id bigint primary key references ingestion.validation_issues on delete restrict,
 revision integer not null default 1 check(revision>0),
 decision text not null check(decision in ('correct','omit','defer','reject_record')),
 proposed_value jsonb,
 canonical_value jsonb,
 validator_name text,
 validator_version text,
 evidence_reference text check(evidence_reference is null or length(evidence_reference)<=2000),
 note text not null check(length(trim(note)) between 1 and 2000),
 resolved_by uuid not null references auth.users,
 resolved_at timestamptz not null default now(),
 redacted_at timestamptz,
 check(redacted_at is not null or (decision='correct')=(proposed_value is not null and canonical_value is not null)),
 check(redacted_at is not null or (decision='correct')=(validator_name is not null and validator_version is not null))
);
create table ingestion.validation_resolution_events (
 id bigint generated always as identity primary key,
 issue_id bigint not null references ingestion.validation_issues on delete restrict,
 revision integer not null check(revision>0),
 decision text not null,
 proposed_value jsonb,
 canonical_value jsonb,
 validator_name text,
 validator_version text,
 evidence_reference text,
 note text not null,
 resolved_by uuid not null,
 resolved_at timestamptz not null,
 redacted_at timestamptz,
 unique(issue_id,revision)
);
create table ingestion.validation_attempts (
 id bigint generated always as identity primary key,
 issue_id bigint not null references ingestion.validation_issues on delete restrict,
 proposed_value jsonb,
 valid boolean not null,
 canonical_value jsonb,
 validator_name text not null,
 validator_version text not null,
 message text not null,
 attempted_by uuid not null references auth.users,
 attempted_at timestamptz not null default now(),
 redacted_at timestamptz,
 check(redacted_at is not null or valid=(canonical_value is not null))
);
create table ingestion.validation_replays (
 id uuid primary key default gen_random_uuid(),
 parent_run_id bigint references ingestion.ingestion_runs on delete restrict,
 parent_release_id bigint references ingestion.registry_seed_releases on delete restrict,
 derived_run_id bigint references ingestion.ingestion_runs on delete restrict,
 derived_release_id bigint references ingestion.registry_seed_releases on delete restrict,
 resolution_revisions jsonb not null check(jsonb_typeof(resolution_revisions)='array'),
 requested_by uuid not null references auth.users,
 requested_at timestamptz not null default now(),
 status text not null default 'queued' check(status in ('queued','running','complete','partial','failed','cancelled')),
 attempts integer not null default 0 check(attempts between 0 and 3),
 available_at timestamptz not null default now(),
 lease_token uuid,
 lease_until timestamptz,
 message text,
 finished_at timestamptz,
 check(num_nonnulls(parent_run_id,parent_release_id)=1),
 check(num_nonnulls(derived_run_id,derived_release_id)<=1)
);
create unique index validation_one_active_replay on ingestion.validation_replays(parent_run_id)
 where parent_run_id is not null and status in ('queued','running');
create index validation_issue_run_filter on ingestion.validation_issues(ingestion_run_id,category,severity,id);
create index validation_issue_release_filter on ingestion.validation_issues(registry_seed_release_id,category,severity,id);
create index validation_replay_ready on ingestion.validation_replays(available_at)
 where status in ('queued','running');

alter table ingestion.validation_issues enable row level security;
alter table ingestion.validation_resolutions enable row level security;
alter table ingestion.validation_resolution_events enable row level security;
alter table ingestion.validation_attempts enable row level security;
alter table ingestion.validation_replays enable row level security;
revoke all on ingestion.validation_issues,ingestion.validation_resolutions,
 ingestion.validation_resolution_events,ingestion.validation_attempts,ingestion.validation_replays
 from public,anon,authenticated,service_role,ingestion_worker;
revoke all on sequence ingestion.validation_issues_id_seq,
 ingestion.validation_resolution_events_id_seq,ingestion.validation_attempts_id_seq
 from public,anon,authenticated,service_role,ingestion_worker;

create function ingestion.reject_immutable_validation_change() returns trigger
language plpgsql set search_path='' as $$
begin
 if current_setting('ingestion.validation_redaction',true)='on' and TG_OP='UPDATE' then return NEW; end if;
 raise exception 'Validation evidence and history are immutable' using errcode='55000';
end $$;
create trigger validation_issues_immutable before update or delete on ingestion.validation_issues
 for each row execute function ingestion.reject_immutable_validation_change();
create trigger validation_events_immutable before update or delete on ingestion.validation_resolution_events
 for each row execute function ingestion.reject_immutable_validation_change();
create trigger validation_attempts_immutable before update or delete on ingestion.validation_attempts
 for each row execute function ingestion.reject_immutable_validation_change();

create function ingestion.validation_category_overridable(p_category text) returns boolean
language sql immutable set search_path='' as $$
 select p_category in ('field_format','missing_required_field','duplicate_identity','record_integrity')
$$;

create function ingestion.valid_validation_issue(p_issue jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare allowed text[];
begin
 if jsonb_typeof(p_issue)<>'object' or coalesce(p_issue->>'code','') !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
  or p_issue->>'category' not in ('field_format','missing_required_field','duplicate_identity','record_integrity',
   'record_scope','source_schema','mapping_unknown','acquisition_error','licence_or_qualification')
  or p_issue->>'severity' not in ('warning','blocking')
  or jsonb_typeof(p_issue->'validator')<>'object'
  or coalesce(p_issue->'validator'->>'name','')='' or coalesce(p_issue->'validator'->>'version','')=''
  or jsonb_typeof(p_issue->'allowed_resolutions')<>'array' or coalesce(p_issue->>'detail','')='' then return false; end if;
 select coalesce(array_agg(value order by value),'{}') into allowed from jsonb_array_elements_text(p_issue->'allowed_resolutions');
 if allowed && array(select unnest(allowed) except select unnest(array['correct','omit','defer','reject_record']::text[]))
  or cardinality(allowed)<>(select count(distinct x) from unnest(allowed) x)
  or (not ingestion.validation_category_overridable(p_issue->>'category') and cardinality(allowed)>0)
 then return false; end if;
 return true;
exception when others then return false;
end $$;

create function ingestion.materialise_validation_issues(p_run bigint,p_envelope jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare issue jsonb; item jsonb; inserted integer:=0; issue_count integer:=0;
begin
 if not exists(select 1 from ingestion.ingestion_runs where id=p_run and envelope_sha256=
  encode(sha256(convert_to(p_envelope::text,'UTF8')),'hex')) then raise exception 'Run evidence differs'; end if;
 if p_envelope ? 'issues' and jsonb_typeof(p_envelope->'issues')<>'array' then raise exception 'Invalid issues array'; end if;
 for issue in select value from jsonb_array_elements(coalesce(p_envelope->'issues','[]')) loop
  issue_count:=issue_count+1;
  if not ingestion.valid_validation_issue(issue) then raise exception 'Invalid structured validation issue'; end if;
  insert into ingestion.validation_issues(ingestion_run_id,subject_native_id,source_row,source_key,canonical_key,
   code,category,severity,source_value,raw_evidence_hash,validator_name,validator_version,allowed_resolutions,detail)
  values(p_run,issue->'subject'->>'native_id',(issue->'subject'->>'row')::integer,
   issue->'field'->>'source_key',issue->'field'->>'canonical_key',issue->>'code',issue->>'category',
   issue->>'severity',issue->'source_value',issue->>'raw_evidence_hash',issue->'validator'->>'name',
   issue->'validator'->>'version',array(select jsonb_array_elements_text(issue->'allowed_resolutions')),issue->>'detail')
  on conflict do nothing;
  get diagnostics inserted=row_count; issue_count:=issue_count+inserted-1;
 end loop;
 -- Compatibility: legacy diagnostics remain visible and non-resolvable. Adapters
 -- that emit structured issues are not duplicated here.
 if jsonb_array_length(coalesce(p_envelope->'issues','[]'))=0 then
  for item in
   select value from jsonb_array_elements(coalesce(p_envelope->'quarantine','[]'))
   union all select value from jsonb_array_elements(coalesce(p_envelope->'errors','[]'))
  loop
   insert into ingestion.validation_issues(ingestion_run_id,subject_native_id,source_row,source_key,canonical_key,
    code,category,severity,source_value,raw_evidence_hash,validator_name,validator_version,allowed_resolutions,detail)
   values(p_run,coalesce(item->>'native_id',item->'raw'->>'_id'),(item->>'row')::integer,
    case when item->>'reason' like 'Charity_Website:%' then 'Charity_Website' end,
    case when item->>'reason' like 'Charity_Website:%' then 'website' end,
    case when item->>'reason' like 'Charity_Website:%' then 'website.format' else 'legacy.unstructured' end,
    case when item->>'reason' like 'Charity_Website:%' then 'field_format'
     when item ? 'offset' then 'acquisition_error' else 'record_integrity' end,'blocking',
    case when item->>'reason' like 'Charity_Website:%' then item->'raw'->'Charity_Website' else item end,
    encode(sha256(convert_to((case when item->>'reason' like 'Charity_Website:%'
     then item->'raw'->'Charity_Website' else item end)::text,'UTF8')),'hex'),
    case when item->>'reason' like 'Charity_Website:%' then 'http_url' else 'legacy_diagnostic' end,
    case when item->>'reason' like 'Charity_Website:%' then coalesce(p_envelope->>'parser_version','legacy') else '1' end,
    case when item->>'reason' like 'Charity_Website:%' then array['correct','omit','defer','reject_record'] else '{}'::text[] end,
    coalesce(nullif(item->>'reason',''),'Legacy validation failure; retained raw evidence is not field-addressable.'))
   on conflict do nothing;
   get diagnostics inserted=row_count; issue_count:=issue_count+inserted;
  end loop;
 end if;
 return issue_count;
end $$;

-- Existing stage entry points keep their contracts and now materialise structured
-- issues atomically when a v1.1-capable adapter supplies them.
alter function ingestion.stage_acnc(jsonb) rename to stage_acnc_before_validation_issues;
create function ingestion.stage_acnc(p_envelope jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare r bigint; retained jsonb; removed timestamptz;
begin
 r:=ingestion.stage_acnc_before_validation_issues(p_envelope);
 select envelope,raw_removed_at into retained,removed from ingestion.ingestion_runs where id=r;
 if removed is null then perform ingestion.materialise_validation_issues(r,retained); end if;
 return r;
end $$;
revoke all on function ingestion.stage_acnc(jsonb),ingestion.stage_acnc_before_validation_issues(jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;
grant execute on function ingestion.stage_acnc(jsonb) to ingestion_worker;

alter function ingestion.stage_csv(jsonb) rename to stage_csv_before_validation_issues;
create function ingestion.stage_csv(p_envelope jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare r bigint; retained jsonb; removed timestamptz;
begin
 r:=ingestion.stage_csv_before_validation_issues(p_envelope);
 select envelope,raw_removed_at into retained,removed from ingestion.ingestion_runs where id=r;
 if removed is null then perform ingestion.materialise_validation_issues(r,retained); end if;
 return r;
end $$;
revoke all on function ingestion.stage_csv(jsonb),ingestion.stage_csv_before_validation_issues(jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;
grant execute on function ingestion.stage_csv(jsonb) to ingestion_worker;

create function ingestion.stage_registry_seed_validation_issues(p_release bigint,p_issues jsonb) returns integer
language plpgsql security definer set search_path='' as $$
declare issue jsonb; n integer:=0; added integer;
begin
 if not exists(select 1 from ingestion.registry_seed_releases where id=p_release) or jsonb_typeof(p_issues)<>'array'
  then raise exception 'Invalid registry seed issue batch'; end if;
 for issue in select value from jsonb_array_elements(p_issues) loop
  if not ingestion.valid_validation_issue(issue) then raise exception 'Invalid structured validation issue'; end if;
  if nullif(issue->'subject'->>'candidate_version_id','') is not null and not exists(
   select 1 from ingestion.registry_seed_release_candidates where release_id=p_release
    and version_id=(issue->'subject'->>'candidate_version_id')::bigint) then
   raise exception 'Validation issue candidate is not in the release'; end if;
  insert into ingestion.validation_issues(registry_seed_release_id,candidate_version_id,subject_native_id,source_row,
   source_key,canonical_key,code,category,severity,source_value,raw_evidence_hash,validator_name,validator_version,
   allowed_resolutions,detail)
  values(p_release,nullif(issue->'subject'->>'candidate_version_id','')::bigint,issue->'subject'->>'native_id',
   (issue->'subject'->>'row')::integer,issue->'field'->>'source_key',issue->'field'->>'canonical_key',
   issue->>'code',issue->>'category',issue->>'severity',issue->'source_value',issue->>'raw_evidence_hash',
   issue->'validator'->>'name',issue->'validator'->>'version',
   array(select jsonb_array_elements_text(issue->'allowed_resolutions')),issue->>'detail') on conflict do nothing;
  get diagnostics added=row_count; n:=n+added;
 end loop;
 return n;
end $$;
revoke all on function ingestion.materialise_validation_issues(bigint,jsonb),
 ingestion.stage_registry_seed_validation_issues(bigint,jsonb),ingestion.valid_validation_issue(jsonb),
 ingestion.validation_category_overridable(text),ingestion.reject_immutable_validation_change()
 from public,anon,authenticated,service_role,ingestion_worker;
grant execute on function ingestion.stage_registry_seed_validation_issues(bigint,jsonb) to ingestion_worker;

-- Materialise retained legacy evidence during rollout. Known ACNC website
-- diagnostics become field-addressable; unknown diagnostics remain visible but
-- deliberately non-resolvable rather than being guessed.
do $$ declare run record;
begin
 for run in select id,envelope from ingestion.ingestion_runs where raw_removed_at is null order by id loop
  perform ingestion.materialise_validation_issues(run.id,run.envelope);
 end loop;
end $$;

create function ingestion.validate_proposed_issue_value(p_issue ingestion.validation_issues,p_value jsonb)
returns jsonb language plpgsql stable set search_path='' as $$
declare mapping ingestion.field_mappings; valid boolean:=false; canonical jsonb:=p_value; s text:=p_value#>>'{}'; d date; months text[]:=array['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
begin
 if not 'correct'=any(p_issue.allowed_resolutions) then
  return jsonb_build_object('valid',false,'message','Correction is not permitted for this issue.'); end if;
 if p_issue.validator_name in ('http_url','website_url') then
  valid:=jsonb_typeof(p_value)='string' and (p_value#>>'{}') ~ '^https?://[^/@[:space:]?#:]+(:[0-9]{1,5})?([/?#].*)?$'
   and (p_value#>>'{}') !~ '[[:space:][:cntrl:]\\]' and (p_value#>>'{}') !~ '^https?://[^/?#]*@';
  begin valid:=valid and coalesce((substring(p_value#>>'{}' from '^https?://[^/:?#]+:([0-9]+)'))::integer<=65535,true);
  exception when others then valid:=false; end;
 elsif p_issue.validator_name in ('text','other_names','countries','required_text') then
  valid:=jsonb_typeof(p_value)='string' and length(trim(s))>0; canonical:=to_jsonb(trim(s));
 elsif p_issue.validator_name='identifier' then
  valid:=jsonb_typeof(p_value)='string' and trim(s)~'^[0-9]{11}$'; canonical:=to_jsonb(trim(s));
 elsif p_issue.validator_name='postcode' then
  valid:=jsonb_typeof(p_value)='string' and trim(s)~'^[0-9]{4}$'; canonical:=to_jsonb(trim(s));
 elsif p_issue.validator_name='count' then
  valid:=jsonb_typeof(p_value)='string' and trim(s)~'^[0-9]+$' and trim(s)::numeric<=2147483647;
  if valid then canonical:=to_jsonb(trim(s)::integer); end if;
 elsif p_issue.validator_name='flag' then
  valid:=jsonb_typeof(p_value)='string' and trim(s) in ('Y','N');
  if valid then canonical:=to_jsonb(trim(s)='Y'); end if;
 elsif p_issue.validator_name='date' then
  valid:=jsonb_typeof(p_value)='string' and trim(s)~'^[0-9]{2}/[0-9]{2}/[0-9]{4}$';
  begin d:=to_date(trim(s),'DD/MM/YYYY'); valid:=valid and to_char(d,'DD/MM/YYYY')=trim(s);
   if valid then canonical:=to_jsonb(to_char(d,'YYYY-MM-DD')); end if; exception when others then valid:=false; end;
 elsif p_issue.validator_name='calendar' then
  valid:=jsonb_typeof(p_value)='string' and trim(s)~'^[0-9]{2}-[A-Z][a-z]{2}$'
   and substring(trim(s),4,3)=any(months);
  begin d:=make_date(2000,array_position(months,substring(trim(s),4,3)),substring(trim(s),1,2)::integer);
   if valid then canonical:=jsonb_build_object('month',extract(month from d)::integer,'day',extract(day from d)::integer); end if;
   exception when others then valid:=false; end;
 elsif p_issue.validator_name='approved_csv_field' then
  valid:=jsonb_typeof(p_value)='string';
  if p_issue.source_key='abn' then valid:=valid and trim(s)~'^[0-9]{11}$';
  elsif p_issue.source_key='postcode' then valid:=valid and trim(s)~'^[0-9]{4}$';
  elsif p_issue.source_key='state' then valid:=valid and trim(s) in ('NSW','VIC','QLD','SA','WA','TAS','NT','ACT');
  elsif p_issue.source_key='entity_kind' then valid:=valid and trim(s) in ('legal_entity','community_group','branch','service');
  elsif p_issue.source_key='scope_basis' then valid:=valid and trim(s) in ('located_in','serves_area','unknown');
  elsif p_issue.source_key='website' then
   valid:=valid and s ~ '^https?://[^/@[:space:]?#:]+(:[0-9]{1,5})?([/?#].*)?$'
    and s !~ '[[:space:][:cntrl:]\\]' and s !~ '^https?://[^/?#]*@';
   begin valid:=valid and coalesce((substring(s from '^https?://[^/:?#]+:([0-9]+)'))::integer<=65535,true);
    exception when others then valid:=false; end;
  else valid:=valid and length(trim(s))>0; end if;
  canonical:=to_jsonb(trim(s));
 elsif p_issue.canonical_key is not null then
  select * into mapping from ingestion.field_mappings where field=p_issue.canonical_key;
  valid:=found and ingestion.valid_field_value(mapping,p_value);
 else valid:=false;
 end if;
 return jsonb_build_object('valid',valid,'canonical_value',case when valid then canonical else null end,
  'validator',jsonb_build_object('name',p_issue.validator_name,'version',p_issue.validator_version),
  'message',case when valid then 'Value passed the authoritative server validator.' else 'Value did not pass the authoritative server validator.' end);
end $$;
revoke all on function ingestion.validate_proposed_issue_value(ingestion.validation_issues,jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;

create function community_orgs.validation_issue_queue(
 p_issue text default null,p_run text default null,p_release text default null,p_category text default '',
 p_decision text default '',p_offset integer default 0
) returns jsonb language plpgsql security definer set search_path='' as $$
declare selected bigint; detail jsonb; total bigint; issues jsonb; counts jsonb;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 if p_offset<0 or p_offset>1000000 or p_category not in ('','field_format','missing_required_field','duplicate_identity',
  'record_integrity','record_scope','source_schema','mapping_unknown','acquisition_error','licence_or_qualification')
  or p_decision not in ('','unresolved','correct','omit','defer','reject_record') then
  raise exception 'Invalid validation filter' using errcode='22023'; end if;
 selected:=nullif(p_issue,'')::bigint;
 select count(*) into total from ingestion.validation_issues i left join ingestion.validation_resolutions r on r.issue_id=i.id
  where (p_run is null or i.ingestion_run_id=p_run::bigint) and (p_release is null or i.registry_seed_release_id=p_release::bigint)
   and (p_category='' or i.category=p_category) and (p_decision='' or (p_decision='unresolved' and r.issue_id is null) or r.decision=p_decision);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_id),'[]') into issues from (
  select i.id::text id,i.id sort_id,i.ingestion_run_id::text run_id,i.registry_seed_release_id::text release_id,
   i.subject_native_id,i.source_row,i.source_key,i.canonical_key,i.code,i.category,i.severity,i.detail,
   coalesce(r.decision,'unresolved') decision,coalesce(r.revision,0) revision
  from ingestion.validation_issues i left join ingestion.validation_resolutions r on r.issue_id=i.id
  where (p_run is null or i.ingestion_run_id=p_run::bigint) and (p_release is null or i.registry_seed_release_id=p_release::bigint)
   and (p_category='' or i.category=p_category) and (p_decision='' or (p_decision='unresolved' and r.issue_id is null) or r.decision=p_decision)
  order by i.id limit 50 offset p_offset) x;
 select jsonb_build_object('total',count(*),'blocking',count(*) filter(where severity='blocking'),
  'unresolved',count(*) filter(where r.issue_id is null),'deferred',count(*) filter(where r.decision='defer'),
  'non_resolvable',count(*) filter(where cardinality(allowed_resolutions)=0)) into counts
 from ingestion.validation_issues i left join ingestion.validation_resolutions r on r.issue_id=i.id
 where (p_run is null or i.ingestion_run_id=p_run::bigint) and (p_release is null or i.registry_seed_release_id=p_release::bigint)
  and (p_category='' or i.category=p_category) and (p_decision='' or (p_decision='unresolved' and r.issue_id is null) or r.decision=p_decision);
 if selected is not null then
  select to_jsonb(x) into detail from (
   select i.id::text id,i.ingestion_run_id::text run_id,i.registry_seed_release_id::text release_id,
    i.subject_native_id,i.source_row,i.source_key,i.canonical_key,i.code,i.category,i.severity,i.source_value,
    i.raw_evidence_hash,i.validator_name,i.validator_version,i.allowed_resolutions,i.detail,i.created_at,
    case when r.issue_id is null then null else to_jsonb(r) end resolution,
    coalesce((select jsonb_agg(to_jsonb(e) order by e.revision) from ingestion.validation_resolution_events e where e.issue_id=i.id),'[]') history,
    coalesce((select jsonb_agg(to_jsonb(a) order by a.attempted_at desc) from ingestion.validation_attempts a where a.issue_id=i.id),'[]') attempts
   from ingestion.validation_issues i left join ingestion.validation_resolutions r on r.issue_id=i.id where i.id=selected) x;
  if detail is null then raise exception 'Validation issue not found' using errcode='P0002'; end if;
 end if;
 return jsonb_build_object('total',total,'counts',counts,'issues',issues,'detail',detail);
end $$;

create function community_orgs.validate_issue_value(p_issue text,p_value jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare issue ingestion.validation_issues; result jsonb;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into issue from ingestion.validation_issues where id=p_issue::bigint;
 if not found then raise exception 'Validation issue not found' using errcode='P0002'; end if;
 result:=ingestion.validate_proposed_issue_value(issue,p_value);
 insert into ingestion.validation_attempts(issue_id,proposed_value,valid,canonical_value,validator_name,validator_version,message,attempted_by)
 values(issue.id,p_value,(result->>'valid')::boolean,nullif(result->'canonical_value','null'::jsonb),issue.validator_name,issue.validator_version,result->>'message',auth.uid());
 return result;
end $$;

create function community_orgs.save_validation_resolution(p_issue text,p_revision integer,p_decision text,
 p_proposed_value jsonb default null,p_note text default '',p_evidence_reference text default null) returns void
language plpgsql security definer set search_path='' as $$
declare issue ingestion.validation_issues; current ingestion.validation_resolutions; checked jsonb;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into issue from ingestion.validation_issues where id=p_issue::bigint for share;
 if not found then raise exception 'Validation issue not found' using errcode='P0002'; end if;
 if p_revision<0 or p_decision is null or not p_decision=any(issue.allowed_resolutions)
  or length(trim(p_note)) not between 1 and 2000 or coalesce(length(p_evidence_reference),0)>2000
  or ((p_decision='correct')<>(p_proposed_value is not null)) then raise exception 'Invalid resolution' using errcode='22023'; end if;
 if p_decision='correct' then
  checked:=ingestion.validate_proposed_issue_value(issue,p_proposed_value);
  if checked->'valid' is distinct from 'true'::jsonb then raise exception 'Proposed value is invalid' using errcode='22023'; end if;
 end if;
 if p_revision=0 then
  insert into ingestion.validation_resolutions(issue_id,decision,proposed_value,canonical_value,validator_name,
   validator_version,evidence_reference,note,resolved_by)
  values(issue.id,p_decision,p_proposed_value,checked->'canonical_value',
   case when p_decision='correct' then issue.validator_name end,case when p_decision='correct' then issue.validator_version end,
   nullif(trim(p_evidence_reference),''),trim(p_note),auth.uid()) on conflict do nothing returning * into current;
 else
  update ingestion.validation_resolutions set revision=revision+1,decision=p_decision,proposed_value=p_proposed_value,
   canonical_value=checked->'canonical_value',validator_name=case when p_decision='correct' then issue.validator_name end,
   validator_version=case when p_decision='correct' then issue.validator_version end,
   evidence_reference=nullif(trim(p_evidence_reference),''),note=trim(p_note),resolved_by=auth.uid(),resolved_at=now()
  where issue_id=issue.id and revision=p_revision returning * into current;
 end if;
 if current.issue_id is null then raise exception 'Resolution changed; reload before saving' using errcode='40001'; end if;
 insert into ingestion.validation_resolution_events(issue_id,revision,decision,proposed_value,canonical_value,
  validator_name,validator_version,evidence_reference,note,resolved_by,resolved_at)
 select issue_id,revision,decision,proposed_value,canonical_value,validator_name,validator_version,
  evidence_reference,note,resolved_by,resolved_at from ingestion.validation_resolutions where issue_id=issue.id;
end $$;

create function community_orgs.create_corrected_run(p_run text) returns text
language plpgsql security definer set search_path='' as $$
declare parent ingestion.ingestion_runs; snapshot jsonb; replay uuid;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select * into parent from ingestion.ingestion_runs where id=p_run::bigint for share;
 if not found then raise exception 'Run not found' using errcode='P0002'; end if;
 if parent.raw_removed_at is not null then raise exception 'Raw evidence expired' using errcode='22023'; end if;
 if jsonb_array_length(coalesce(parent.envelope->'errors','[]'))>0 then raise exception 'Acquisition failures require a new acquisition' using errcode='22023'; end if;
 if not exists(select 1 from ingestion.validation_issues where ingestion_run_id=parent.id) then
  raise exception 'No validation issues exist for this run' using errcode='22023'; end if;
 if exists(select 1 from ingestion.validation_issues i left join ingestion.validation_resolutions r on r.issue_id=i.id
  where i.ingestion_run_id=parent.id and i.severity='blocking' and
   (not ingestion.validation_category_overridable(i.category) or r.issue_id is null or r.decision in ('defer','reject_record'))) then
  raise exception 'Blocking issues remain unresolved or non-overridable' using errcode='22023'; end if;
 select jsonb_agg(jsonb_build_object('issue_id',i.id::text,'revision',r.revision,'decision',r.decision,
  'native_id',i.subject_native_id,'row',i.source_row,'source_key',i.source_key,'canonical_key',i.canonical_key,
  'source_value',i.source_value,'raw_evidence_hash',i.raw_evidence_hash,'proposed_value',r.proposed_value,
  'canonical_value',r.canonical_value,'validator_name',coalesce(r.validator_name,i.validator_name),
  'validator_version',coalesce(r.validator_version,i.validator_version)) order by i.id)
 into snapshot from ingestion.validation_issues i join ingestion.validation_resolutions r on r.issue_id=i.id
 where i.ingestion_run_id=parent.id;
 insert into ingestion.validation_replays(parent_run_id,resolution_revisions,requested_by)
 values(parent.id,snapshot,auth.uid()) returning id into replay;
 return replay::text;
exception when unique_violation then raise exception 'A corrected run is already queued' using errcode='40001';
end $$;

create function ingestion.claim_validation_replay() returns jsonb
language plpgsql security definer set search_path='' as $$
declare replay ingestion.validation_replays; parent ingestion.ingestion_runs;
begin
 update ingestion.validation_replays set status='failed',finished_at=now(),message='Replay lease expired after three attempts.',
  lease_token=null,lease_until=null where status='running' and lease_until<=now() and attempts>=3;
 select * into replay from ingestion.validation_replays where (status='queued' and available_at<=now())
  or (status='running' and lease_until<=now()) order by available_at,requested_at limit 1 for update skip locked;
 if not found then return null; end if;
 update ingestion.validation_replays set status='running',attempts=attempts+1,lease_token=gen_random_uuid(),
  lease_until=now()+interval '5 minutes',message=null where id=replay.id returning * into replay;
 select * into parent from ingestion.ingestion_runs where id=replay.parent_run_id;
 if parent.raw_removed_at is not null or parent.envelope_sha256 is distinct from encode(sha256(convert_to(parent.envelope::text,'UTF8')),'hex') then
  update ingestion.validation_replays set status='failed',finished_at=now(),message='Raw evidence unavailable or changed.',lease_token=null,lease_until=null where id=replay.id;
  return null;
 end if;
 return jsonb_build_object('id',replay.id,'lease_token',replay.lease_token,'parent_run_id',parent.id,
  'parent_envelope_sha256',parent.envelope_sha256,'envelope',parent.envelope,'resolutions',replay.resolution_revisions);
end $$;

create function ingestion.finish_validation_replay(p_replay uuid,p_token uuid,p_envelope jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare replay ingestion.validation_replays; parent ingestion.ingestion_runs; derived bigint; expected jsonb;
begin
 select * into replay from ingestion.validation_replays where id=p_replay for update;
 if not found or replay.status<>'running' or replay.lease_token is distinct from p_token or replay.lease_until<=now()
  then raise exception 'Replay lease lost' using errcode='40001'; end if;
 select * into parent from ingestion.ingestion_runs where id=replay.parent_run_id for share;
 select jsonb_agg(jsonb_build_object('issue_id',i.id::text,'revision',r.revision,'decision',r.decision,
  'native_id',i.subject_native_id,'row',i.source_row,'source_key',i.source_key,'canonical_key',i.canonical_key,
  'source_value',i.source_value,'raw_evidence_hash',i.raw_evidence_hash,'proposed_value',r.proposed_value,
  'canonical_value',r.canonical_value,'validator_name',coalesce(r.validator_name,i.validator_name),
  'validator_version',coalesce(r.validator_version,i.validator_version)) order by i.id) into expected
 from ingestion.validation_issues i join ingestion.validation_resolutions r on r.issue_id=i.id where i.ingestion_run_id=parent.id;
 if expected is distinct from replay.resolution_revisions or parent.raw_removed_at is not null
  or p_envelope->>'run_id' is distinct from 'validation-replay-'||replay.id::text
  or p_envelope->>'source_id' is distinct from parent.source_id or p_envelope->>'resource_id' is distinct from parent.resource_id
  or p_envelope->'observed_at' is distinct from parent.envelope->'observed_at'
  or p_envelope->'scope' is distinct from parent.envelope->'scope'
  or p_envelope->'qualification' is distinct from parent.envelope->'qualification'
  or p_envelope->'pages' is distinct from parent.envelope->'pages'
  or p_envelope->'errors' is distinct from '[]'::jsonb or p_envelope->>'completion'<>'complete'
  or jsonb_array_length(coalesce(p_envelope->'quarantine','[]'))<>0
  or p_envelope->'publication_eligible' is distinct from 'false'::jsonb
  then raise exception 'Derived run does not preserve replay evidence or pass all gates' using errcode='22023'; end if;
 if parent.source_id='acnc-register' then derived:=ingestion.stage_acnc(p_envelope);
 elsif parent.envelope->>'parser_version'='approved-csv-v1' then derived:=ingestion.stage_csv(p_envelope);
 else raise exception 'No qualified replay adapter for source' using errcode='22023'; end if;
 insert into ingestion.reprocessing_runs(run_id,parent_run_id,processed_at,mapping_version)
 values(derived,parent.id,now(),p_envelope->>'mapping_version') on conflict do nothing;
 update ingestion.validation_replays set status='complete',derived_run_id=derived,finished_at=now(),lease_token=null,
  lease_until=null,message='Corrected private run created; identity and field review remain required.' where id=replay.id;
 return derived;
end $$;

create function ingestion.fail_validation_replay(p_replay uuid,p_token uuid) returns void
language plpgsql security definer set search_path='' as $$
declare replay ingestion.validation_replays;
begin
 select * into replay from ingestion.validation_replays where id=p_replay and status='running'
  and lease_token=p_token and lease_until>now() for update;
 if not found then raise exception 'Replay lease lost' using errcode='40001'; end if;
 update ingestion.validation_replays set status=case when attempts<3 then 'queued' else 'failed' end,
  available_at=now()+make_interval(secs=>60*(2^attempts)::integer),finished_at=case when attempts>=3 then now() end,
  lease_token=null,lease_until=null,message=case when attempts<3 then 'Replay retry queued.' else 'Replay failed after three attempts.' end
 where id=replay.id;
end $$;

-- Registry candidates with unresolved blocking issues cannot be promoted. Preserve
-- the existing implementation behind a gated wrapper.
alter function community_orgs.promote_registry_seed_candidates(text,text[],text)
 rename to promote_registry_seed_candidates_before_validation;
create function community_orgs.promote_registry_seed_candidates(p_release text,p_versions text[],p_reason text)
returns text language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from ingestion.validation_issues i left join ingestion.validation_resolutions r on r.issue_id=i.id
  where i.registry_seed_release_id=p_release::bigint and i.severity='blocking'
   and (i.candidate_version_id is null or i.candidate_version_id=any(p_versions::bigint[]))
   and (not ingestion.validation_category_overridable(i.category) or r.issue_id is null or r.decision in ('defer','reject_record')))
 then raise exception 'Registry seed candidates have unresolved validation issues' using errcode='22023'; end if;
 return community_orgs.promote_registry_seed_candidates_before_validation(p_release,p_versions,p_reason);
end $$;

revoke all on function community_orgs.validation_issue_queue(text,text,text,text,text,integer),
 community_orgs.validate_issue_value(text,jsonb),
 community_orgs.save_validation_resolution(text,integer,text,jsonb,text,text),
 community_orgs.create_corrected_run(text),
 community_orgs.promote_registry_seed_candidates_before_validation(text,text[],text),
 community_orgs.promote_registry_seed_candidates(text,text[],text)
 from public,anon,authenticated,service_role;
grant execute on function community_orgs.validation_issue_queue(text,text,text,text,text,integer),
 community_orgs.validate_issue_value(text,jsonb),
 community_orgs.save_validation_resolution(text,integer,text,jsonb,text,text),
 community_orgs.create_corrected_run(text),community_orgs.promote_registry_seed_candidates(text,text[],text)
 to authenticated;
revoke all on function ingestion.claim_validation_replay(),
 ingestion.finish_validation_replay(uuid,uuid,jsonb),ingestion.fail_validation_replay(uuid,uuid)
 from public,anon,authenticated,service_role,ingestion_worker;
grant execute on function ingestion.claim_validation_replay(),
 ingestion.finish_validation_replay(uuid,uuid,jsonb),ingestion.fail_validation_replay(uuid,uuid)
 to ingestion_worker;

-- Retention and suppression remove validation payloads while retaining issue,
-- decision and replay audit facts. The guarded setting is private to these
-- security-definer paths and only permits UPDATE, never deletion.
create function ingestion.redact_validation_issue_set(p_issues bigint[]) returns integer
language plpgsql security definer set search_path='' as $$
declare n integer:=0; changed integer;
begin
 if coalesce(cardinality(p_issues),0)=0 then return 0; end if;
 perform set_config('ingestion.validation_redaction','on',true);
 update ingestion.validation_issues set source_value=null,detail='Private validation evidence redacted.',redacted_at=coalesce(redacted_at,now())
 where id=any(p_issues) and redacted_at is null;
 get diagnostics n=row_count;
 update ingestion.validation_resolutions set proposed_value=null,canonical_value=null,evidence_reference=null,
  note='Private resolution evidence redacted.',redacted_at=coalesce(redacted_at,now()) where issue_id=any(p_issues);
 update ingestion.validation_resolution_events set proposed_value=null,canonical_value=null,evidence_reference=null,
  note='Private resolution evidence redacted.',redacted_at=coalesce(redacted_at,now()) where issue_id=any(p_issues);
 update ingestion.validation_attempts set proposed_value=null,canonical_value=null,message='Private validation attempt redacted.',
  redacted_at=coalesce(redacted_at,now()) where issue_id=any(p_issues);
 update ingestion.validation_replays vr set resolution_revisions=coalesce((select jsonb_agg(jsonb_build_object(
   'issue_id',x->>'issue_id','revision',x->'revision','decision',x->>'decision') order by x->>'issue_id')
  from jsonb_array_elements(vr.resolution_revisions) x),'[]'::jsonb),
  status=case when status in ('queued','running') then 'cancelled' else status end,
  finished_at=case when status in ('queued','running') then now() else finished_at end,
  lease_token=case when status in ('queued','running') then null else lease_token end,
  lease_until=case when status in ('queued','running') then null else lease_until end,
  message=case when status in ('queued','running') then 'Replay cancelled because retained evidence was redacted.' else message end
 where exists(select 1 from jsonb_array_elements(vr.resolution_revisions) x where (x->>'issue_id')::bigint=any(p_issues));
 return n;
end $$;
revoke all on function ingestion.redact_validation_issue_set(bigint[])
 from public,anon,authenticated,service_role,ingestion_worker;

alter function ingestion.expire_raw_evidence(text,text,boolean) rename to expire_raw_evidence_before_validation;
create function ingestion.expire_raw_evidence(p_source text,p_resource text,p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; issues bigint[];
begin
 result:=ingestion.expire_raw_evidence_before_validation(p_source,p_resource,p_apply);
 if coalesce((result->>'applied')::boolean,false) then
  select coalesce(array_agg(i.id),'{}') into issues from ingestion.validation_issues i
  join ingestion.ingestion_runs r on r.id=i.ingestion_run_id
  where r.source_id=p_source and r.resource_id=p_resource and r.raw_removed_at is not null and i.redacted_at is null;
  perform ingestion.redact_validation_issue_set(issues);
 end if;
 return result;
end $$;
revoke all on function ingestion.expire_raw_evidence(text,text,boolean),
 ingestion.expire_raw_evidence_before_validation(text,text,boolean)
 from public,anon,authenticated,service_role,ingestion_worker;

-- Wrap the stable operator API rather than the private retained-evidence helper.
-- Older hosted baselines do not have that helper, while all supported baselines
-- expose suppress_ingestion_content with this signature.
alter function community_orgs.suppress_ingestion_content(text,text,text,text,jsonb)
 rename to suppress_ingestion_content_before_validation;
create function community_orgs.suppress_ingestion_content(
 p_run text,p_version text,p_field text,p_reason text,p_expected jsonb
) returns void language plpgsql security definer set search_path='' as $$
declare record ingestion.source_records; issues bigint[];
begin
 perform community_orgs.suppress_ingestion_content_before_validation(
  p_run,p_version,p_field,p_reason,p_expected
 );
 select sr.* into record
 from ingestion.run_records rr
 join ingestion.source_record_versions sv on sv.id=rr.version_id
 join ingestion.source_records sr on sr.id=sv.record_id
 where rr.run_id=p_run::bigint and rr.version_id=p_version::bigint;
 select coalesce(array_agg(i.id),'{}') into issues from ingestion.validation_issues i
 join ingestion.ingestion_runs r on r.id=i.ingestion_run_id
 where r.source_id=record.source_id and r.resource_id=record.resource_id
  and i.subject_native_id=record.native_id and (p_field='*' or i.canonical_key=p_field)
  and i.redacted_at is null;
 perform ingestion.redact_validation_issue_set(issues);
end $$;
revoke all on function
 community_orgs.suppress_ingestion_content_before_validation(text,text,text,text,jsonb)
 from public,anon,authenticated,service_role,ingestion_worker;
revoke all on function community_orgs.suppress_ingestion_content(text,text,text,text,jsonb)
 from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.suppress_ingestion_content(text,text,text,text,jsonb)
 to authenticated;

alter function community_orgs.expire_registry_seed_raw(text,boolean)
 rename to expire_registry_seed_raw_before_validation;
create function community_orgs.expire_registry_seed_raw(p_release text,p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; issues bigint[];
begin
 result:=community_orgs.expire_registry_seed_raw_before_validation(p_release,p_apply);
 if coalesce((result->>'applied')::boolean,false) then
  select coalesce(array_agg(id),'{}') into issues from ingestion.validation_issues
   where registry_seed_release_id=p_release::bigint and redacted_at is null;
  perform ingestion.redact_validation_issue_set(issues);
 end if;
 return result;
end $$;
revoke all on function community_orgs.expire_registry_seed_raw(text,boolean),
 community_orgs.expire_registry_seed_raw_before_validation(text,boolean)
 from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.expire_registry_seed_raw(text,boolean) to authenticated;

comment on table ingestion.validation_issues is 'Immutable private field/record validation evidence for one staged artifact.';
comment on table ingestion.validation_replays is 'Fenced worker queue and immutable resolution snapshot for separately versioned corrected runs.';

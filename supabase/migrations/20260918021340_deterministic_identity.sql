-- P14: private reviewed identity; legacy display values never establish ownership.
create table ingestion.identity_clock (singleton boolean primary key default true check(singleton), revision bigint not null default 0);
insert into ingestion.identity_clock values(true,0);
create table ingestion.entity_classifications (
 org_id uuid primary key references community_orgs.organisations on delete cascade,
 kind text not null default 'unknown' check(kind in ('unknown','legal_entity','community_group','branch')),
 revision integer not null default 1,
 evidence jsonb not null default '{}', reviewed_by uuid references auth.users, reviewed_at timestamptz
);
insert into ingestion.entity_classifications(org_id) select org_id from community_orgs.organisations;
create table ingestion.identity_events (
 id bigint generated always as identity primary key,
 action text not null, subject text not null, before_value jsonb, after_value jsonb,
 actor uuid references auth.users, occurred_at timestamptz not null default now()
);
create table ingestion.identifier_claims (
 id bigint generated always as identity primary key,
 origin_key text unique not null, org_id uuid references community_orgs.organisations,
 version_id bigint references ingestion.source_record_versions,
 scheme text not null check(scheme in ('abn','acn','incorporated_association')),
 jurisdiction text, raw_value text not null, normalized_value text,
 normalizer_version text not null default 'p14-v1',
 validation text not null check(validation in ('unchecked','valid','invalid')),
 verification text not null default 'unverified' check(verification in ('unverified','verified','disputed','withdrawn')),
 evidence jsonb not null, observed_at timestamptz, recorded_at timestamptz not null default now()
);
create table ingestion.identifier_keys (
 id bigint generated always as identity primary key,
 scheme text not null check(scheme in ('abn','incorporated_association')),
 jurisdiction text not null, normalized_value text not null,
 holder uuid not null references community_orgs.organisations,
 state text not null check(state in ('verified','disputed','withdrawn')),
 revision integer not null default 1,
 evidence jsonb not null, reviewed_by uuid not null references auth.users, reviewed_at timestamptz not null default now(),
 unique(scheme,jurisdiction,normalized_value)
);
create unique index identity_one_active_abn on ingestion.identifier_keys(holder) where scheme='abn' and state='verified';
create table ingestion.branch_links (
 id bigint generated always as identity primary key,
 branch_id uuid not null references community_orgs.organisations,
 parent_id uuid not null references community_orgs.organisations,
 valid_from timestamptz not null, valid_until timestamptz,
 evidence jsonb not null, reviewed_by uuid not null references auth.users,
 reviewed_at timestamptz not null default now(),
 check(branch_id<>parent_id), check(valid_until is null or valid_until>valid_from)
);
alter table ingestion.source_links alter column organisation_id drop not null;
alter table ingestion.source_links add column service_id uuid references community_orgs.programs_services(program_id);
alter table ingestion.source_links add constraint source_link_exactly_one_target check(num_nonnulls(organisation_id,service_id)=1);
alter table ingestion.change_sets add column identity_revision bigint;

-- Spaces are the only permitted display separator. Do not coerce through numeric types.
create function ingestion.normalize_identifier(s text,j text,v text) returns text
language plpgsql immutable set search_path='' as $$
declare n text; total integer:=0; weights integer[]:=array[10,1,3,5,7,9,11,13,15,17,19]; i integer;
begin
 if v is null then return null; end if;
 n:=btrim(v);
 if s in ('abn','acn') and j='AU' then
  n:=replace(n,' ','');
  if s='acn' then return null; end if; -- ACN qualification intentionally not enabled.
  if n !~ '^[0-9]{11}$' or n='00000000000' then return null; end if;
  for i in 1..11 loop total:=total+((substr(n,i,1)::integer)-case when i=1 then 1 else 0 end)*weights[i]; end loop;
  if total%89<>0 then return null; end if;
  return n;
 elsif s='incorporated_association' and j='AU-NSW' and length(n) between 1 and 100 and n !~ '[[:cntrl:]]' then
  return n;
 end if;
 return null;
end $$;

alter table ingestion.identifier_keys add constraint canonical_identifier_valid check(
 ingestion.normalize_identifier(scheme,jurisdiction,normalized_value) is not null and
 normalized_value=ingestion.normalize_identifier(scheme,jurisdiction,normalized_value));

create function ingestion.identity_audit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 update ingestion.identity_clock set revision=revision+1;
 insert into ingestion.identity_events(action,subject,before_value,after_value,actor)
 values(TG_OP,TG_TABLE_NAME,case when TG_OP<>'INSERT' then to_jsonb(old) end,
 case when TG_OP<>'DELETE' then to_jsonb(new) end,auth.uid());
 return coalesce(new,old);
end $$;
create trigger identity_classification_audit after insert or update or delete on ingestion.entity_classifications for each row execute function ingestion.identity_audit();
create trigger identity_key_audit after insert or update or delete on ingestion.identifier_keys for each row execute function ingestion.identity_audit();
create trigger identity_branch_audit after insert or update or delete on ingestion.branch_links for each row execute function ingestion.identity_audit();
create trigger identity_link_audit after insert or update or delete on ingestion.source_links for each row execute function ingestion.identity_audit();

create function ingestion.classify_new_organisation() returns trigger
language plpgsql security definer set search_path='' as $$
begin insert into ingestion.entity_classifications(org_id) values(new.org_id); return new; end $$;
create trigger identity_new_organisation after insert on community_orgs.organisations for each row execute function ingestion.classify_new_organisation();

-- All identity writers take the same portal lock before any identity/review locks.
-- This pilot-scale serialization also fences concurrent approval/publication.
create function community_orgs.review_entity_identity(p_org uuid,p_revision integer,p_kind text,p_evidence jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 lock table community_orgs.organisations in share row exclusive mode;
 if p_kind is null or p_kind not in ('unknown','legal_entity','community_group','branch') or
  jsonb_typeof(p_evidence) is distinct from 'object' or coalesce(length(btrim(p_evidence->>'reference')),0)=0 then
  raise exception 'Classification and evidence reference required' using errcode='22023'; end if;
 if p_kind<>'legal_entity' and exists(select 1 from ingestion.identifier_keys where holder=p_org) then
  raise exception 'Reserved identifiers require a legal entity' using errcode='22023'; end if;
 if exists(select 1 from ingestion.branch_links where
  (branch_id=p_org and p_kind<>'branch') or (parent_id=p_org and p_kind<>'legal_entity')) then
  raise exception 'Classification conflicts with branch history' using errcode='22023'; end if;
 update ingestion.entity_classifications set kind=p_kind,revision=revision+1,evidence=p_evidence,reviewed_by=auth.uid(),reviewed_at=now()
 where org_id=p_org and revision=p_revision;
 if not found then raise exception 'Classification changed; reload' using errcode='40001'; end if;
end $$;

create function community_orgs.review_identifier_identity(p_org uuid,p_scheme text,p_jurisdiction text,p_value text,p_revision integer,p_state text,p_evidence jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare n text; k ingestion.identifier_keys; result bigint;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 lock table community_orgs.organisations in share row exclusive mode;
 n:=ingestion.normalize_identifier(p_scheme,p_jurisdiction,p_value);
 if n is null or p_state is null or p_state not in ('verified','disputed','withdrawn') or p_revision is null or p_revision<0
  or jsonb_typeof(p_evidence) is distinct from 'object'
  or coalesce(length(btrim(p_evidence->>'reference')),0)=0
  or coalesce(length(btrim(p_evidence->>'authority')),0)=0
  or coalesce(length(btrim(p_evidence->>'holder_name')),0)=0
  or (p_evidence->>'qualified_registry_review') is distinct from 'true'
  or (p_evidence->>'observed_at')::timestamptz is null then
  raise exception 'Valid scoped identifier and qualified registry evidence required' using errcode='22023'; end if;
 if not exists(select 1 from ingestion.entity_classifications where org_id=p_org and kind='legal_entity') then
  raise exception 'Reviewed legal entity required' using errcode='22023'; end if;
 select * into k from ingestion.identifier_keys where scheme=p_scheme and jurisdiction=p_jurisdiction and normalized_value=n for update;
 if coalesce(k.revision,0)<>p_revision then raise exception 'Identifier changed; reload' using errcode='40001'; end if;
 -- Competing claims are retained and disable matching; reservations never transfer.
 insert into ingestion.identifier_claims(origin_key,org_id,scheme,jurisdiction,raw_value,normalized_value,validation,verification,evidence,observed_at)
 values('review:'||gen_random_uuid(),p_org,p_scheme,p_jurisdiction,p_value,n,'valid',
 case when k.holder is not null and k.holder<>p_org then 'disputed' else p_state end,p_evidence,(p_evidence->>'observed_at')::timestamptz);
 if k.holder is not null and k.holder<>p_org then
  update ingestion.identifier_keys set state='disputed',revision=revision+1,reviewed_by=auth.uid(),reviewed_at=now() where id=k.id;
  return jsonb_build_object('status','conflict','key_id',k.id::text,'holder',k.holder);
 end if;
 if p_state='verified' and p_scheme='abn' and exists(select 1 from ingestion.identifier_keys
  where holder=p_org and scheme='abn' and state='verified' and id is distinct from k.id) then
  raise exception 'Legal entity already has an accepted ABN' using errcode='22023'; end if;
 if k.id is null then
  insert into ingestion.identifier_keys(scheme,jurisdiction,normalized_value,holder,state,evidence,reviewed_by)
  values(p_scheme,p_jurisdiction,n,p_org,p_state,p_evidence,auth.uid()) returning id into result;
 else
  update ingestion.identifier_keys set state=p_state,evidence=p_evidence,revision=revision+1,reviewed_by=auth.uid(),reviewed_at=now()
  where id=k.id returning id into result;
 end if;
 return jsonb_build_object('status',p_state,'key_id',result::text,'holder',p_org);
end $$;

create function community_orgs.review_branch_identity(p_branch uuid,p_parent uuid,p_from timestamptz,p_until timestamptz,p_evidence jsonb)
returns bigint language plpgsql security definer set search_path='' as $$
declare result bigint;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 lock table community_orgs.organisations in share row exclusive mode;
 if not exists(select 1 from ingestion.entity_classifications where org_id=p_branch and kind='branch')
  or not exists(select 1 from ingestion.entity_classifications where org_id=p_parent and kind='legal_entity')
  or p_from is null or p_branch=p_parent or (p_until is not null and p_until<=p_from)
  or coalesce(length(btrim(p_evidence->>'reference')),0)=0 then
  raise exception 'Evidenced branch and legal parent required' using errcode='22023'; end if;
 if exists(select 1 from ingestion.branch_links where branch_id=p_branch
  and tstzrange(valid_from,valid_until,'[)') && tstzrange(p_from,p_until,'[)')) then
  raise exception 'Overlapping branch parent' using errcode='22023'; end if;
 -- Only legal entities can be parents and only branches children: cycles impossible.
 insert into ingestion.branch_links(branch_id,parent_id,valid_from,valid_until,evidence,reviewed_by)
 values(p_branch,p_parent,p_from,p_until,p_evidence,auth.uid()) returning id into result;
 return result;
end $$;

-- Repeatable legacy evidence capture; it never chooses a legal row or jurisdiction.
create function ingestion.backfill_identity_evidence() returns bigint
language plpgsql security definer set search_path='' as $$
declare result bigint;
begin
 insert into ingestion.identifier_claims(origin_key,org_id,scheme,jurisdiction,raw_value,normalized_value,validation,evidence)
 select 'legacy:'||l.legal_id||':'||x.scheme||':'||md5(x.value),l.org_id,x.scheme,
 case when x.scheme in ('abn','acn') then 'AU' end,x.value,
 ingestion.normalize_identifier(x.scheme,case when x.scheme in ('abn','acn') then 'AU' end,x.value),
 case when x.scheme<>'abn' then 'unchecked' when ingestion.normalize_identifier('abn','AU',x.value) is null then 'invalid' else 'valid' end,
 jsonb_build_object('origin','legacy legal_details','legal_id',l.legal_id)
 from community_orgs.legal_details l cross join lateral (values ('abn',l.abn),('acn',l.acn),('incorporated_association',l.incorporation_number)) x(scheme,value)
 where x.value is not null on conflict(origin_key) do nothing;
 get diagnostics result=row_count; return result;
end $$;
select ingestion.backfill_identity_evidence();

-- Display changes withdraw matching confidence, not the holder reservation.
create function ingestion.dispute_edited_identity() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' and (new.abn,new.acn,new.incorporation_number,new.org_id) is not distinct from
  (old.abn,old.acn,old.incorporation_number,old.org_id) then return new; end if;
 -- Writing the same accepted value (including import projection and display
 -- spacing) does not dispute registry evidence. Clears, changed values, moves
 -- and deletion of identifier-bearing rows do.
 update ingestion.identifier_keys k set state='disputed',revision=revision+1
 where k.state='verified' and (
  (TG_OP<>'INSERT' and k.holder=old.org_id and
   (TG_OP='DELETE' or old.org_id is distinct from new.org_id) and
   case k.scheme when 'abn' then old.abn is not null else old.incorporation_number is not null end)
  or (TG_OP<>'DELETE' and k.holder=new.org_id and
   case k.scheme when 'abn' then
    (case when TG_OP='INSERT' then new.abn is not null else new.abn is distinct from old.abn or new.org_id is distinct from old.org_id end)
    and ingestion.normalize_identifier('abn','AU',new.abn) is distinct from k.normalized_value
   else
    (case when TG_OP='INSERT' then new.incorporation_number is not null else new.incorporation_number is distinct from old.incorporation_number or new.org_id is distinct from old.org_id end)
    and btrim(new.incorporation_number) is distinct from k.normalized_value
   end));
 return coalesce(new,old);
end $$;
create trigger identity_legal_edit after insert or update or delete on community_orgs.legal_details for each row execute function ingestion.dispute_edited_identity();

create function ingestion.match_identity(p_version bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a jsonb; rec bigint; linked uuid; service uuid; targets uuid[]:='{}'; k ingestion.identifier_keys;
 abn text; inc text; v_jurisdiction text; scope text; reason text; target uuid; previous_abn text;
begin
 select record_id into rec from ingestion.source_record_versions where id=p_version;
 if not found then raise exception 'Version not found' using errcode='P0002'; end if;
 select coalesce(jsonb_object_agg(field,value),'{}') into a from ingestion.field_assertions where version_id=p_version;
 scope:=a->>'csv_entity_kind';
 select organisation_id,service_id into linked,service from ingestion.source_links where record_id=rec;
 if linked is not null then targets:=array_append(targets,linked); end if;
 abn:=ingestion.normalize_identifier('abn','AU',a->>'abn');
 v_jurisdiction:=case a->>'csv_incorporation_jurisdiction' when 'NSW' then 'AU-NSW' else a->>'csv_incorporation_jurisdiction' end;
 inc:=ingestion.normalize_identifier('incorporated_association',v_jurisdiction,a->>'csv_incorporation_number');
 for k in select * from ingestion.identifier_keys where
  (scheme='abn' and jurisdiction='AU' and normalized_value=abn) or
  (scheme='incorporated_association' and identifier_keys.jurisdiction=v_jurisdiction and normalized_value=inc)
 loop
  targets:=array_append(targets,k.holder);
  if k.state<>'verified' then reason:='Identifier ownership is disputed or withdrawn'; end if;
 end loop;
 if (select count(distinct t) from unnest(targets) t)>1 then reason:='Strong identifiers or source link point to different organisations'; end if;
 if linked is not null then
  -- A changed ABN on a linked native ID requires review even if the new value has no canonical holder.
  select f.value #>> '{}' into previous_abn from ingestion.publications p
   join ingestion.change_sets c on c.id=p.change_set_id join ingestion.source_record_versions v on v.id=c.version_id
   join ingestion.field_assertions f on f.version_id=v.id and f.field='abn'
   where v.record_id=rec and v.id<>p_version order by p.published_at desc limit 1;
  if previous_abn is not null and a->>'abn' is distinct from previous_abn then reason:='Linked source ABN changed; investigate native-ID reuse'; end if;
  if exists(select 1 from ingestion.identifier_keys where holder=linked and scheme='abn'
   and a->>'abn' is not null and normalized_value is distinct from abn) then reason:='Source ABN contradicts the reserved holder identity'; end if;
 end if;
 if scope='community_group' and exists(select 1 from ingestion.identifier_keys where holder=any(targets)) then
  reason:='Community-group scope contradicts a registered legal identity';
 end if;
 if scope in ('branch','service','unknown') or service is not null or exists(
  select 1 from ingestion.entity_classifications where org_id=any(targets) and kind='branch') then
  reason:='Branch, service or unresolved scope requires entity review';
 end if;
 if reason is not null then return jsonb_build_object('status','hold','organisation_id',null,'reason',reason); end if;
 target:=targets[1];
 if target is not null then return jsonb_build_object('status','match','organisation_id',target,
  'reason',case when linked is not null then 'Existing source link' when abn is not null and exists(
   select 1 from ingestion.identifier_keys where scheme='abn' and normalized_value=abn and holder=target and state='verified')
   then 'Verified exact ABN' else 'Verified jurisdiction-scoped incorporation number' end); end if;
 return jsonb_build_object('status','review','organisation_id',null,'reason','No verified match; review candidates or explicitly create');
end $$;

create function ingestion.assert_identity_target(p_version bigint,p_org uuid) returns void
language plpgsql security definer set search_path='' as $$
declare m jsonb;
begin
 m:=ingestion.match_identity(p_version);
 if m->>'status'='hold' then raise exception 'Identity hold: %',m->>'reason' using errcode='22023'; end if;
 if m->>'status'='match' and (m->>'organisation_id')::uuid is distinct from p_org then
  raise exception 'Verified identity requires its existing target; reload review' using errcode='40001'; end if;
 if exists(select 1 from ingestion.identifier_keys k join ingestion.field_assertions a
  on a.version_id=p_version and a.field='abn' where k.holder=p_org and k.scheme='abn'
  and ingestion.normalize_identifier('abn','AU',a.value #>> '{}') is distinct from k.normalized_value) then
  raise exception 'Selected target has a contradictory reserved ABN' using errcode='22023'; end if;
 if exists(select 1 from ingestion.entity_classifications where org_id=p_org and kind='branch') then
  raise exception 'Branch publication remains held' using errcode='22023'; end if;
end $$;

-- Keep existing validation, run membership and optimistic review revision behavior.
alter function community_orgs.save_ingestion_review(text,text,integer,text,uuid,text) rename to save_ingestion_review_before_identity;
create function community_orgs.save_ingestion_review(p_run text,p_version text,p_revision integer,p_decision text,p_organisation uuid default null,p_note text default '')
returns void language plpgsql security definer set search_path='' as $$
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 lock table community_orgs.organisations in share row exclusive mode;
 if p_decision in ('link','create') then perform ingestion.assert_identity_target(p_version::bigint,p_organisation); end if;
 perform community_orgs.save_ingestion_review_before_identity(p_run,p_version,p_revision,p_decision,p_organisation,p_note);
end $$;

alter function community_orgs.approve_ingestion_fields(text,text,integer,jsonb,uuid) rename to approve_ingestion_fields_before_identity;
create function community_orgs.approve_ingestion_fields(p_run text,p_version text,p_revision integer,p_fields jsonb,p_organisation uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 lock table community_orgs.organisations in share row exclusive mode;
 perform ingestion.assert_identity_target(p_version::bigint,p_organisation);
 result:=community_orgs.approve_ingestion_fields_before_identity(p_run,p_version,p_revision,p_fields,p_organisation);
 update ingestion.change_sets set identity_revision=(select revision from ingestion.identity_clock) where id=result;
 return result;
end $$;

alter function community_orgs.publish_ingestion_fields(uuid) rename to publish_ingestion_fields_before_identity;
create function community_orgs.publish_ingestion_fields(p_change_set uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare c ingestion.change_sets;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 lock table community_orgs.organisations in share row exclusive mode;
 select * into c from ingestion.change_sets where id=p_change_set;
 if not found then raise exception 'Approval not found' using errcode='P0002'; end if;
 if not exists(select 1 from ingestion.publications where change_set_id=c.id) then
  if c.identity_revision is distinct from (select revision from ingestion.identity_clock) then
   raise exception 'Identity changed; approve again' using errcode='40001'; end if;
  perform ingestion.assert_identity_target(c.version_id,c.organisation_id);
 end if;
 return community_orgs.publish_ingestion_fields_before_identity(p_change_set);
end $$;

alter function community_orgs.ingestion_review_queue(text,text,integer,text) rename to ingestion_review_queue_before_identity;
create function community_orgs.ingestion_review_queue(p_run text default null,p_version text default null,p_offset integer default 0,p_search text default '')
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; m jsonb; candidate jsonb;
begin
 result:=community_orgs.ingestion_review_queue_before_identity(p_run,p_version,p_offset,p_search);
 if result->'detail'<>'null'::jsonb then
  m:=ingestion.match_identity((result->'detail'->>'id')::bigint);
  result:=jsonb_set(result,'{detail,identity_match}',m);
  if m->>'status'='match' then
   select jsonb_build_object('org_id',org_id,'entity_name',entity_name,'abn',null,'website',null,
    'physical_address',null,'postal_address',null,'reason',m->>'reason') into candidate
   from community_orgs.organisations where org_id=(m->>'organisation_id')::uuid;
   result:=jsonb_set(result,'{candidates}',jsonb_build_array(candidate)||coalesce((
    select jsonb_agg(x) from jsonb_array_elements(result->'candidates') x where x->>'org_id'<>m->>'organisation_id'),'[]'));
  end if;
 end if;
 return result;
end $$;

-- Operator inventory/read handoff for classification and exact registry reviews.
create function community_orgs.ingestion_identity_inventory() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 return jsonb_build_object('revision',(select revision::text from ingestion.identity_clock),
  'classifications',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from ingestion.entity_classifications c),
  'identifiers',(select coalesce(jsonb_agg(to_jsonb(k)),'[]') from ingestion.identifier_keys k),
  'claims',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from ingestion.identifier_claims c),
  'branches',(select coalesce(jsonb_agg(to_jsonb(b)),'[]') from ingestion.branch_links b));
end $$;

-- New tables/functions do not inherit browser or worker privileges.
alter table ingestion.identity_clock enable row level security;
alter table ingestion.entity_classifications enable row level security;
alter table ingestion.identity_events enable row level security;
alter table ingestion.identifier_claims enable row level security;
alter table ingestion.identifier_keys enable row level security;
alter table ingestion.branch_links enable row level security;
revoke all on ingestion.identity_clock,ingestion.entity_classifications,ingestion.identity_events,ingestion.identifier_claims,ingestion.identifier_keys,ingestion.branch_links from public,anon,authenticated,service_role,ingestion_worker;
revoke all on all sequences in schema ingestion from public,anon,authenticated,service_role,ingestion_worker;
revoke all on function ingestion.normalize_identifier(text,text,text),ingestion.identity_audit(),ingestion.classify_new_organisation(),ingestion.backfill_identity_evidence(),ingestion.dispute_edited_identity(),ingestion.match_identity(bigint),ingestion.assert_identity_target(bigint,uuid) from public,anon,authenticated,service_role,ingestion_worker;
revoke all on function community_orgs.save_ingestion_review_before_identity(text,text,integer,text,uuid,text),community_orgs.approve_ingestion_fields_before_identity(text,text,integer,jsonb,uuid),community_orgs.publish_ingestion_fields_before_identity(uuid),community_orgs.ingestion_review_queue_before_identity(text,text,integer,text) from public,anon,authenticated,service_role,ingestion_worker;
revoke all on function community_orgs.review_entity_identity(uuid,integer,text,jsonb),community_orgs.review_identifier_identity(uuid,text,text,text,integer,text,jsonb),community_orgs.review_branch_identity(uuid,uuid,timestamptz,timestamptz,jsonb),community_orgs.ingestion_identity_inventory(),community_orgs.save_ingestion_review(text,text,integer,text,uuid,text),community_orgs.approve_ingestion_fields(text,text,integer,jsonb,uuid),community_orgs.publish_ingestion_fields(uuid),community_orgs.ingestion_review_queue(text,text,integer,text) from public,anon,service_role,ingestion_worker;
grant execute on function community_orgs.review_entity_identity(uuid,integer,text,jsonb),community_orgs.review_identifier_identity(uuid,text,text,text,integer,text,jsonb),community_orgs.review_branch_identity(uuid,uuid,timestamptz,timestamptz,jsonb),community_orgs.ingestion_identity_inventory(),community_orgs.save_ingestion_review(text,text,integer,text,uuid,text),community_orgs.approve_ingestion_fields(text,text,integer,jsonb,uuid),community_orgs.publish_ingestion_fields(uuid),community_orgs.ingestion_review_queue(text,text,integer,text) to authenticated;

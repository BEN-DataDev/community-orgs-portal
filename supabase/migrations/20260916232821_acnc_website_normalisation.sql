-- Parser v3 qualifies bare DNS website values. Keep the v2 replay contract for
-- retained versions; changing mapping tokens invalidates unconsumed approvals.
update ingestion.field_mappings set mapping_version='acnc-register-fields-v3';

create or replace function community_orgs.ingestion_field_preview(p_run text,p_version text,p_organisation uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a record; m ingestion.field_mappings; sv ingestion.source_record_versions; state ingestion.field_state;
 current_value jsonb; proposed jsonb; n bigint; scope bigint; expr text; predicate text;
 result jsonb:='[]'; status text; supported boolean; target_name text; token text; raw_keys jsonb;
 register_public boolean; is_protected boolean;
begin
 if community_orgs.is_ingestion_operator() is distinct from true then raise exception 'Operator required' using errcode='42501'; end if;
 select v.* into sv from ingestion.source_record_versions v join ingestion.run_records rr on rr.version_id=v.id
 where rr.run_id=p_run::bigint and v.id=p_version::bigint;
 if not found then raise exception 'Record not in selected run' using errcode='P0002'; end if;
 if p_organisation is not null then
  select entity_name into target_name from community_orgs.organisations where org_id=p_organisation;
  if not found then raise exception 'Organisation not found' using errcode='P0002'; end if;
 end if;
 select md5(jsonb_build_array(to_jsonb(sv),to_jsonb(s),i.observed_at,i.completion,
   (select max(id) from ingestion.source_record_versions where record_id=sv.record_id))::text)
 into token from ingestion.ingestion_runs i join ingestion.sources s using(source_id,resource_id) where i.id=p_run::bigint;
 for a in
  select f.field,f.value,true as present from ingestion.field_assertions f where version_id=sv.id
  union all select fm.field,null::jsonb,false from ingestion.field_mappings fm
  where not exists(select 1 from ingestion.field_assertions f where f.version_id=sv.id and f.field=fm.field)
  order by 1
 loop
  select * into m from ingestion.field_mappings where field=a.field;
  supported:=m.field is not null and (a.field in ('entity_name','abn','website')
   or ((sv.parser_version,sv.payload->>'mapping_version') in (('acnc-ckan-v2','acnc-register-fields-v2'),('acnc-ckan-v3','acnc-register-fields-v3'))));
  scope:=case when m.table_name='acnc_register_details' then sv.record_id else 0 end;
  current_value:=null; n:=0; state:=null; register_public:=null;
  if m.field is not null and p_organisation is not null then
   expr:=format('to_jsonb(x.%I)',m.column_name);
   if m.path is not null then expr:=format('(%s)->%L',expr,m.path); end if;
   predicate:=case when scope=0 then '' else ' and source_record_id=$2' end;
   execute format('select count(*),(jsonb_agg(%s))->0 from community_orgs.%I x where org_id=$1%s',expr,m.table_name,predicate)
    into n,current_value using p_organisation,scope;
   select * into state from ingestion.field_state where org_id=p_organisation and table_name=m.table_name and field=m.field and record_id=scope;
  end if;
  if scope<>0 and p_organisation is not null then
   select is_public into register_public from community_orgs.acnc_register_details
    where org_id=p_organisation and source_record_id=scope;
  end if;
  is_protected:=coalesce(state.protected,false) or register_public=false;
  is_protected:=coalesce(is_protected,false);
  proposed:=a.value;
  -- An address is one explicit atomic merge: absent components never delete old ones.
  if m.kind='address' and jsonb_typeof(a.value)='object' then
   proposed:=coalesce(nullif(current_value,'null'::jsonb),'{}') || a.value;
  end if;
  status:=case
   when exists(select 1 from ingestion.suppressions z where (z.record_id=sv.record_id or z.organisation_id=p_organisation) and z.field in ('*',a.field)) then 'suppressed'
   when not a.present or a.value='null'::jsonb then 'missing'
   when not supported then 'unmapped'
   when ingestion.valid_field_value(m,a.value) is distinct from true then 'invalid'
   when n>1 then 'ambiguous'
   when current_value is not distinct from proposed then 'unchanged'
   when is_protected then 'conflict'
   when nullif(current_value,'null'::jsonb) is null then 'new'
   else 'changed' end;
  select x->'source_values' into raw_keys from jsonb_array_elements(sv.payload->'assertions') x where x->>'field'=a.field;
  result:=result || jsonb_build_array(jsonb_build_object(
   'field',a.field,'table',m.table_name,'section',coalesce(m.section,'Unmapped'),'label',coalesce(m.label,a.field),
   'atomic_group',m.kind='address','input_value',a.value,'source_value',proposed,'current_value',case when n>1 then null else current_value end,
   'status',status,'protected',is_protected,'projection_public',register_public,'revision',coalesce(state.revision,0)::text,
   'target_rows',n,'changed_at',state.changed_at,'record_id',scope::text,
   'source_token',token,'mapping_token',md5(coalesce(to_jsonb(m)::text,'unmapped')||':f03-v1'),
   'source_version',sv.id::text,'mapping_version',m.mapping_version,'source_values',raw_keys));
 end loop;
 return jsonb_build_object('organisation_id',p_organisation,'organisation_name',target_name,'fields',result);
end $$;

create or replace function ingestion.stage_acnc_reprocessing(p_parent bigint,p_envelope jsonb)
returns bigint language plpgsql security definer set search_path='' as $$
declare parent ingestion.ingestion_runs; r jsonb; old jsonb; run bigint; seen text[]:='{}';
 meta jsonb:=p_envelope->'reprocessing'; quarantined boolean;
begin
 select * into parent from ingestion.ingestion_runs where id=p_parent for share;
 if not found or parent.completion<>'complete' then raise exception 'Complete parent acquisition required'; end if;
 if meta->>'parent_run_id' is distinct from p_parent::text
  or meta->>'parent_run_key' is distinct from parent.run_key
  or meta->>'parent_parser_version' is distinct from parent.envelope->>'parser_version'
  or coalesce(meta->>'processed_at','')=''
  or not coalesce((p_envelope->>'parser_version',meta->>'mapping_version') in
   (('acnc-ckan-v2','acnc-register-fields-v2'),('acnc-ckan-v3','acnc-register-fields-v3')),false)
  or p_envelope->>'parser_version' is not distinct from parent.envelope->>'parser_version'
  or p_envelope->>'run_id' is not distinct from parent.run_key
  or p_envelope->>'source_id' is distinct from parent.source_id
  or p_envelope->>'resource_id' is distinct from parent.resource_id
  or p_envelope->'observed_at' is distinct from parent.envelope->'observed_at'
  or p_envelope->'scope' is distinct from parent.envelope->'scope'
  or p_envelope->'pages' is distinct from parent.envelope->'pages'
  or p_envelope->'qualification' is distinct from parent.envelope->'qualification'
  or p_envelope->'synthetic' is distinct from parent.envelope->'synthetic'
  or p_envelope->'errors' is distinct from '[]'::jsonb
  or jsonb_typeof(p_envelope->'records') is distinct from 'array'
  or jsonb_typeof(p_envelope->'quarantine') is distinct from 'array'
 then raise exception 'Replay metadata must preserve parent acquisition evidence'; end if;
 for r,quarantined in
  select value,false from jsonb_array_elements(p_envelope->'records')
  union all select value,true from jsonb_array_elements(p_envelope->'quarantine')
 loop
  if coalesce(r->>'native_id','')='' or r->>'native_id'=any(seen) then raise exception 'Duplicate/missing replay identity'; end if;
  seen:=array_append(seen,r->>'native_id');
  select value into old from jsonb_array_elements(parent.envelope->'records') where value->>'native_id'=r->>'native_id';
  if not found or r->'raw' is distinct from old->'raw'
   or r->>'raw_sha256' is distinct from old->>'raw_sha256'
   or r->'raw'->>'_id' is distinct from r->>'native_id'
   or not exists(select 1 from ingestion.run_records rr join ingestion.source_record_versions v on v.id=rr.version_id
    join ingestion.source_records sr on sr.id=v.record_id
    where rr.run_id=p_parent and sr.source_id=parent.source_id and sr.resource_id=parent.resource_id
     and sr.native_id=r->>'native_id' and v.payload->'raw'=r->'raw'
     and v.payload->>'raw_sha256'=r->>'raw_sha256')
  then raise exception 'Replay identity or evidence differs from retained version'; end if;
  if quarantined then
   if coalesce(r->>'reason','')='' then raise exception 'Quarantine reason required'; end if;
  elsif r->'source_url' is distinct from old->'source_url'
   or r->'source_modified_at' is distinct from old->'source_modified_at'
   or r->>'mapping_version' is distinct from meta->>'mapping_version' then
   raise exception 'Replay source metadata changed';
  end if;
 end loop;
 if cardinality(seen)<>jsonb_array_length(parent.envelope->'records')
  or (p_envelope->'counts'->>'accepted')::integer is distinct from jsonb_array_length(p_envelope->'records')
  or (p_envelope->'counts'->>'quarantined')::integer is distinct from jsonb_array_length(p_envelope->'quarantine')
  or p_envelope->'counts'->'source_total' is distinct from parent.envelope->'counts'->'source_total'
  or p_envelope->'counts'->'pages' is distinct from parent.envelope->'counts'->'pages'
  or p_envelope->>'completion' is distinct from (case when jsonb_array_length(p_envelope->'quarantine')=0 then 'complete' else 'partial' end)
 then raise exception 'Replay must account for every original record'; end if;
 run:=ingestion.stage_acnc(p_envelope);
 insert into ingestion.reprocessing_runs values(run,p_parent,(meta->>'processed_at')::timestamptz,meta->>'mapping_version')
 on conflict(run_id) do nothing;
 return run;
end $$;
revoke all on function ingestion.stage_acnc_reprocessing(bigint,jsonb) from public,anon,authenticated,service_role;
grant execute on function ingestion.stage_acnc_reprocessing(bigint,jsonb) to ingestion_worker;


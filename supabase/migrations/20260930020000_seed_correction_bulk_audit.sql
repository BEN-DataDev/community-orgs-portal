-- The over-broad seed correction removes more than 150,000 freshly imported
-- identity rows. Preserve item-level correction evidence while collapsing the
-- identity clock/event side effect to one event per management-only batch.
begin;

create or replace function ingestion.identity_audit() returns trigger
language plpgsql security definer set search_path='' as $$
declare bulk_correction text;
begin
 bulk_correction:=current_setting('community_orgs.seed_correction_bulk',true);
 if session_user='postgres' and bulk_correction is not null
    and bulk_correction ~ '^[0-9a-f-]{36}$'
    and exists(select 1 from ingestion.seed_publication_corrections
      where correction_id=bulk_correction::uuid and status='applying') then
   return coalesce(new,old);
 end if;
 update ingestion.identity_clock set revision=revision+1 where singleton;
 insert into ingestion.identity_events(action,subject,before_value,after_value,actor)
 values(TG_OP,TG_TABLE_NAME,case when TG_OP<>'INSERT' then to_jsonb(old) end,
 case when TG_OP<>'DELETE' then to_jsonb(new) end,auth.uid());
 return coalesce(new,old);
end $$;

create function ingestion.apply_seed_publication_correction_managed_batch(
  p_correction uuid,p_limit integer default 2000
) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if session_user<>'postgres' then raise exception 'Management database session required' using errcode='42501'; end if;
  perform set_config('community_orgs.seed_correction_bulk',p_correction::text,true);
  result:=ingestion.apply_seed_publication_correction_batch(p_correction,p_limit);
  update ingestion.identity_clock set revision=revision+1 where singleton;
  insert into ingestion.identity_events(action,subject,before_value,after_value,actor)
  values('BULK_SEED_CORRECTION','seed_publication_correction',null,
    jsonb_build_object('correction_id',p_correction,'batch_applied',result->'applied',
      'pending',result->'pending','status',result->'status'),null);
  perform set_config('community_orgs.seed_correction_bulk','',true);
  return result;
end $$;

revoke all on function ingestion.apply_seed_publication_correction_managed_batch(uuid,integer)
  from public,anon,authenticated,service_role,ingestion_worker;

commit;

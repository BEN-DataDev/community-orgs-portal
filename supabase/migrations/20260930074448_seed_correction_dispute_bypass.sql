-- During the management-only correction, each removed organisation's identifier
-- keys are deleted before its legal details, so disputing them on the following
-- legal-details delete has nothing to mark. Skip that per-row scan of
-- identifier_keys; all ordinary writes retain the existing dispute behaviour.
begin;

create or replace function ingestion.dispute_edited_identity() returns trigger
language plpgsql security definer set search_path='' as $$
declare bulk_correction text;
begin
 bulk_correction:=current_setting('community_orgs.seed_correction_bulk',true);
 if TG_OP='DELETE' and session_user='postgres' and bulk_correction is not null
    and bulk_correction ~ '^[0-9a-f-]{36}$'
    and exists(select 1 from ingestion.seed_publication_corrections
      where correction_id=bulk_correction::uuid and status='applying') then
   return old;
 end if;
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

commit;

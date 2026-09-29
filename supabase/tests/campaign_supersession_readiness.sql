begin;

do $$
begin
  if to_regprocedure('ingestion.campaign_readiness_before_supersession(uuid)') is null then
    raise exception 'Campaign readiness predecessor is missing';
  end if;
  if to_regprocedure('ingestion.campaign_readiness(uuid)') is null then
    raise exception 'Supersession-aware campaign readiness is missing';
  end if;
end
$$;

rollback;

select 'Campaign supersession readiness boundary exists' as result;

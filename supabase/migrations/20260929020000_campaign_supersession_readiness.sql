-- A replacement campaign is an immutable declaration that its predecessor must
-- never cross the publication boundary, even if every other readiness counter clears.
begin;

alter function ingestion.campaign_readiness(uuid)
  rename to campaign_readiness_before_supersession;

create function ingestion.campaign_readiness(p_campaign uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  result jsonb;
  successor portal.campaigns;
begin
  result := ingestion.campaign_readiness_before_supersession(p_campaign);

  select * into successor
  from portal.campaigns
  where replaces_campaign_id = p_campaign
  order by created_at desc, campaign_id desc
  limit 1;

  if found then
    result := jsonb_set(result, '{ready}', 'false'::jsonb);
    result := jsonb_set(result, '{state}', '"blocked"'::jsonb);
    result := jsonb_set(
      result,
      '{blockers}',
      coalesce(result->'blockers', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
        'code', 'campaign_superseded',
        'stage', 'campaign',
        'message', 'A replacement campaign supersedes this campaign.',
        'responsible_role', 'data_steward',
        'replacement_campaign_id', successor.campaign_id,
        'replacement_campaign_name', successor.name
      ))
    );
  end if;

  return result;
end
$$;

revoke all on function ingestion.campaign_readiness_before_supersession(uuid),
  ingestion.campaign_readiness(uuid)
  from public, anon, authenticated, service_role, ingestion_worker;

comment on function ingestion.campaign_readiness(uuid) is
  'Derived campaign readiness; a campaign with an immutable replacement is permanently blocked.';

commit;

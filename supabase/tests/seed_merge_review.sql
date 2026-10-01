-- Hosted-data check for 20261001025644_seed_merge_review. Uses the applied
-- community-entities-v1 correction and a current Data Steward, confirms one
-- pending merge and splits another, asserts the result, then rolls back.
begin;

do $$
declare
  steward uuid;
  q jsonb;
  conf uuid;
  spl uuid;
  tgt uuid;
  pending int;
begin
  select a.user_id into steward from portal.capability_appointments a
  where a.capability = 'data_steward' and a.starts_at <= now()
    and (a.expires_at is null or a.expires_at > now())
    and not exists (select 1 from portal.capability_appointment_events e
      where e.appointment_id = a.appointment_id and e.event_type = 'revoked')
  limit 1;
  if steward is null then raise exception 'No current Data Steward to run as'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', steward, 'role', 'authenticated',
    'aal', 'aal1', 'is_anonymous', false)::text, true);
  set local role authenticated;

  q := community_orgs.seed_merge_review_queue('pending', 'trigram_name_similarity', 0, 1);
  pending := (q->'counts'->>'pending')::int;
  spl := (q->'items'->0->>'source_organisation_id')::uuid;
  tgt := (q->'items'->0->>'target_organisation_id')::uuid;
  q := community_orgs.seed_merge_review_queue('pending', 'unique_normalised_name', 0, 1);
  conf := (q->'items'->0->>'source_organisation_id')::uuid;
  if spl is null or conf is null then raise exception 'Needs one pending merge of each method'; end if;

  perform community_orgs.review_seed_merge(conf, 'confirmed', null);
  begin
    perform community_orgs.review_seed_merge(spl, 'split', '  ');
    raise exception 'Split without a note was accepted';
  exception when sqlstate '22023' then null; end;
  perform community_orgs.review_seed_merge(spl, 'split', 'Rollback test split');
  begin
    perform community_orgs.review_seed_merge(conf, 'split', 'again');
    raise exception 'A second decision was accepted';
  exception when sqlstate '40001' then null; end;
  q := community_orgs.seed_merge_review_queue('all', null, 0, 1);
  if (q->'counts'->>'pending')::int <> pending - 2 then raise exception 'Pending count did not drop by two'; end if;
  reset role;

  -- Split: the association is back, unclaimed and ownerless, holding its own key.
  if not exists (select 1 from community_orgs.organisations where org_id = spl and is_public) then
    raise exception 'Split did not restore the association'; end if;
  if (select state from community_orgs.organisation_stewardship where organisation_id = spl) <> 'unclaimed' then
    raise exception 'Restored association is not unclaimed'; end if;
  if exists (select 1 from community_orgs.user_organisation_roles where organisation_id = spl) then
    raise exception 'Restored association received an owner'; end if;
  if not exists (select 1 from ingestion.identifier_keys where holder = spl and state = 'verified'
      and evidence ? 'merge_review' and not evidence ? 'seed_scope_correction_id') then
    raise exception 'NSW key did not move back'; end if;
  -- ...and the ABN entity is as the full seed left it, with no disputed key.
  if exists (select 1 from community_orgs.legal_details where org_id = tgt and incorporation_number is not null) then
    raise exception 'ABN entity kept the NSW incorporation number'; end if;
  if exists (select 1 from ingestion.identifier_keys where holder in (spl, tgt) and state <> 'verified') then
    raise exception 'Split disputed a key'; end if;
  if exists (select 1 from community_orgs.aliases a join ingestion.seed_publication_correction_items ci
      on ci.source_organisation_id = spl where a.org_id = tgt and lower(a.alias) = lower(ci.source_name)) then
    raise exception 'Merge alias was kept'; end if;

  -- Confirm: the key stays with the ABN entity and records the review.
  if not exists (select 1 from ingestion.identifier_keys k join ingestion.seed_publication_correction_items ci
      on ci.source_organisation_id = conf and k.holder = ci.target_organisation_id
      where k.evidence->'merge_review'->>'decision' = 'confirmed') then
    raise exception 'Confirmation not recorded on the key'; end if;
end $$;

rollback;

select 'Seed merge review confirm and split passed' as result;

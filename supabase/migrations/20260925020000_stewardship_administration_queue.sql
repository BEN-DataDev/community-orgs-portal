-- Phase 4: task-focused portal stewardship and invitation administration.

create function community_orgs.stewardship_administration_queue(
  p_search text default '',
  p_state text default '',
  p_invitation_status text default '',
  p_offset integer default 0
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  expired_invitation uuid;
  normalised_search text := btrim(coalesce(p_search, ''));
begin
  if community_orgs.is_portal_administrator() is distinct from true then
    raise exception 'Portal Administrator required' using errcode = '42501';
  end if;
  if length(normalised_search) > 100 or p_offset < 0 or p_offset > 1000000
     or coalesce(p_state, '') not in ('', 'unclaimed', 'invitation_pending', 'self_managed', 'portal_managed', 'co_managed', 'suspended')
     or coalesce(p_invitation_status, '') not in ('', 'pending', 'accepted', 'cancelled', 'expired') then
    raise exception 'Invalid administration queue filter' using errcode = '22023';
  end if;

  -- Reviewing this queue materialises elapsed invitations through the existing
  -- no-grant transition, keeping the current stewardship projection accurate.
  for expired_invitation in
    select i.invitation_id
    from community_orgs.organisation_invitations i
    where i.expires_at <= now()
      and not exists (
        select 1 from community_orgs.organisation_invitation_events e
        where e.invitation_id = i.invitation_id and e.event_type <> 'issued'
      )
  loop
    perform community_orgs.finish_organisation_invitation_without_grant(
      expired_invitation, 'expired', auth.uid(), 'Invitation expiry recorded during administration review'
    );
  end loop;

  return jsonb_build_object(
    'stewardshipTotal', (
      select count(*) from community_orgs.organisation_stewardship s
      join community_orgs.organisations o on o.org_id = s.organisation_id
      where (coalesce(p_state, '') = '' or s.state::text = p_state)
        and (normalised_search = '' or o.entity_name ilike '%' || normalised_search || '%'
          or o.org_id::text = normalised_search)
    ),
    'stewardshipCounts', (
      select coalesce(jsonb_object_agg(state, amount), '{}'::jsonb)
      from (select state::text state, count(*) amount
        from community_orgs.organisation_stewardship group by state) counts
    ),
    'organisations', coalesce((
      select jsonb_agg(item order by item->>'name') from (
        select jsonb_build_object(
          'organisationId', o.org_id,
          'name', o.entity_name,
          'isPublic', o.is_public,
          'state', s.state,
          'revision', s.revision,
          'updatedAt', s.updated_at,
          'reason', e.reason,
          'approvalReference', e.approval_reference,
          'note', e.note,
          'relatedReference', e.related_reference
        ) item
        from community_orgs.organisation_stewardship s
        join community_orgs.organisations o on o.org_id = s.organisation_id
        join community_orgs.organisation_stewardship_events e on e.event_id = s.current_event_id
        where (coalesce(p_state, '') = '' or s.state::text = p_state)
          and (normalised_search = '' or o.entity_name ilike '%' || normalised_search || '%'
            or o.org_id::text = normalised_search)
        order by o.entity_name, o.org_id limit 50 offset p_offset
      ) rows
    ), '[]'::jsonb),
    'invitationTotal', (
      select count(*)
      from community_orgs.organisation_invitations i
      left join community_orgs.organisation_invitation_events terminal
        on terminal.invitation_id = i.invitation_id and terminal.event_type <> 'issued'
      left join community_orgs.organisations o on o.org_id = i.organisation_id
      where (coalesce(p_invitation_status, '') = ''
          or coalesce(terminal.event_type::text, 'pending') = p_invitation_status)
        and (normalised_search = '' or i.email ilike '%' || normalised_search || '%'
          or o.entity_name ilike '%' || normalised_search || '%'
          or i.organisation_id::text = normalised_search)
    ),
    'invitations', coalesce((
      select jsonb_agg(item order by item->>'invitedAt' desc) from (
        select jsonb_build_object(
          'id', i.invitation_id,
          'organisationId', i.organisation_id,
          'organisationName', coalesce(o.entity_name, 'Deleted organisation'),
          'email', i.email,
          'targetStewardship', i.target_stewardship,
          'invitedAt', i.invited_at,
          'expiresAt', i.expires_at,
          'status', coalesce(terminal.event_type::text, 'pending'),
          'closedAt', terminal.occurred_at,
          'canCancel', terminal.event_id is null
        ) item
        from community_orgs.organisation_invitations i
        left join community_orgs.organisation_invitation_events terminal
          on terminal.invitation_id = i.invitation_id and terminal.event_type <> 'issued'
        left join community_orgs.organisations o on o.org_id = i.organisation_id
        where (coalesce(p_invitation_status, '') = ''
            or coalesce(terminal.event_type::text, 'pending') = p_invitation_status)
          and (normalised_search = '' or i.email ilike '%' || normalised_search || '%'
            or o.entity_name ilike '%' || normalised_search || '%'
            or i.organisation_id::text = normalised_search)
        order by i.invited_at desc, i.invitation_id limit 50 offset p_offset
      ) rows
    ), '[]'::jsonb)
  );
end
$$;

revoke all on function community_orgs.stewardship_administration_queue(text,text,text,integer)
  from public, anon, service_role;
grant execute on function community_orgs.stewardship_administration_queue(text,text,text,integer)
  to authenticated;

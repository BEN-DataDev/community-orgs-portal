-- Groundwork for enabling row-level security on the community_orgs tables.
--
-- Every helper here is SECURITY DEFINER with a locked search_path. That is what
-- keeps the policies from re-entering RLS on organisations /
-- user_organisation_roles, which is the fault that previously produced
-- "42P17 infinite recursion detected in policy".

-- Can the caller see this organisation? Public, or they hold an active role.
create or replace function community_orgs.can_view_org(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from community_orgs.organisations o
        where o.org_id = p_org_id
          and (
              o.is_public
              or exists (
                  select 1
                  from community_orgs.user_organisation_roles uor
                  where uor.organisation_id = o.org_id
                    and uor.user_id = auth.uid()
                    and uor.is_active
                    and (uor.expires_at is null or uor.expires_at > now())
              )
          )
    );
$$;

-- Can the caller change this organisation's records? Admin or owner.
create or replace function community_orgs.can_edit_org(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select community_orgs.user_has_permission(auth.uid(), p_org_id, 'can_manage_members');
$$;

-- dgr_endorsement hangs off legal_details rather than carrying org_id itself.
create or replace function community_orgs.org_id_for_legal(p_legal_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select ld.org_id from community_orgs.legal_details ld where ld.legal_id = p_legal_id;
$$;

-- `generate_unique_slug` reads organisations.slug to find a free slug. Called
-- directly by the application it ran under RLS, so it could not see private
-- organisations' slugs and would happily return one already taken — a unique
-- violation on insert. SECURITY DEFINER lets it see them all.
create or replace function community_orgs.generate_unique_slug(base_slug text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
DECLARE
    counter INTEGER := 0;
    test_slug TEXT := base_slug;
BEGIN
    WHILE EXISTS (SELECT 1 FROM community_orgs.organisations WHERE slug = test_slug) LOOP
        counter := counter + 1;
        test_slug := base_slug || '-' || counter;
    END LOOP;

    RETURN test_slug;
END;
$$;

-- This trigger referenced NEW.name, which is not a column on organisations
-- (the column is entity_name), so any insert that left slug blank failed with
-- "record new has no field name".
create or replace function community_orgs.set_organisation_slug()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
BEGIN
    IF NEW.slug IS NULL OR NEW.slug = '' THEN
        NEW.slug := community_orgs.generate_unique_slug(
            regexp_replace(lower(trim(NEW.entity_name)), '[^a-z0-9]+', '-', 'g')
        );
    END IF;
    RETURN NEW;
END;
$$;

-- Without this, enabling RLS would leave whoever creates an organisation with
-- no role on it, and therefore no way to edit the record they just made.
create or replace function community_orgs.grant_owner_on_organisation_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
DECLARE
    v_owner_role_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id INTO v_owner_role_id
    FROM community_orgs.roles
    WHERE name = 'owner'
    LIMIT 1;

    IF v_owner_role_id IS NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO community_orgs.user_organisation_roles
        (user_id, organisation_id, role_id, granted_by, is_active)
    VALUES
        (auth.uid(), NEW.org_id, v_owner_role_id, auth.uid(), true)
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$;

drop trigger if exists grant_owner_on_insert on community_orgs.organisations;

create trigger grant_owner_on_insert
    after insert on community_orgs.organisations
    for each row execute function community_orgs.grant_owner_on_organisation_insert();

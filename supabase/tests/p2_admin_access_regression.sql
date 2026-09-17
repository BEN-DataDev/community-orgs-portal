-- Run as postgres. Organisation rank must never confer platform/admin access.
-- All fixtures and mutations are rolled back, including auth profile triggers.
BEGIN;
DO $$
DECLARE
    actor uuid := gen_random_uuid();
    org uuid := gen_random_uuid();
    role_id uuid := gen_random_uuid();
    scenario text;
    actual_level integer;
    expected_level integer;
    qualifies boolean;
    org_name text;
    org_slug text;
BEGIN
    INSERT INTO auth.users (id, email, created_at, updated_at)
    VALUES (actor, actor || '@example.invalid', now(), now());
    INSERT INTO community_orgs.organisations (org_id, entity_name, slug, is_public)
    VALUES (org, 'P2 regression fixture', 'p2-test-' || org, false);
    INSERT INTO community_orgs.roles (id, name, permissions, hierarchy_level)
    VALUES (role_id, 'p2-role-' || role_id, '{}', 1);

    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub',actor,'role','authenticated','is_anonymous',false,'aal','aal1'
    )::text, true);

    FOREACH scenario IN ARRAY ARRAY['no_role','member','admin','owner','expired','inactive'] LOOP
        DELETE FROM community_orgs.user_organisation_roles WHERE user_id=actor;
        expected_level := CASE scenario WHEN 'member' THEN 1 WHEN 'admin' THEN 3
                          WHEN 'owner' THEN 4 ELSE 0 END;
        UPDATE community_orgs.roles SET hierarchy_level =
            CASE WHEN scenario IN ('expired','inactive') THEN 4 ELSE expected_level END
        WHERE id=role_id;
        IF scenario <> 'no_role' THEN
            INSERT INTO community_orgs.user_organisation_roles
                (user_id, organisation_id, role_id, is_active, expires_at)
            VALUES (actor, org, role_id, scenario <> 'inactive',
                CASE WHEN scenario='expired' THEN now()-interval '1 day' ELSE NULL END);
        END IF;

        SET LOCAL ROLE authenticated;
        -- This RPC describes organisation membership, not global admin authority.
        SELECT coalesce(max(r.max_hierarchy_level),0),
               coalesce(bool_or(r.max_hierarchy_level >= 3),false),
               max(r.organisation_name), max(r.organisation_slug)
        INTO actual_level, qualifies, org_name, org_slug
        FROM community_orgs.get_user_organisations_with_roles(actor) r;
        IF community_orgs.is_platform_admin() OR community_orgs.is_ingestion_operator() THEN
            RAISE EXCEPTION 'Organisation scenario % granted global authority', scenario;
        END IF;
        RESET ROLE;

        IF actual_level <> expected_level OR qualifies <> (expected_level >= 3) THEN
            RAISE EXCEPTION 'Organisation rank failed for %: level %, qualifies %',
                scenario, actual_level, qualifies;
        END IF;
        IF expected_level > 0 AND
           (org_name IS DISTINCT FROM 'P2 regression fixture'
            OR org_slug IS DISTINCT FROM 'p2-test-' || org) THEN
            RAISE EXCEPTION 'RPC returned incorrect organisation fields for %', scenario;
        END IF;
    END LOOP;

    IF has_function_privilege('anon',
        'community_orgs.get_user_organisations_with_roles(uuid)', 'execute') THEN
        RAISE EXCEPTION 'Unauthenticated callers can execute the admin lookup';
    END IF;
END;
$$;
ROLLBACK;
SELECT 'P2 admin access regression checks passed; all fixtures rolled back' AS result;

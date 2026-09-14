-- Run as postgres through Supabase SQL tooling. All fixtures and changes roll back.
BEGIN;
DO $$
DECLARE
    actor uuid := gen_random_uuid();
    target uuid := gen_random_uuid();
    org uuid := gen_random_uuid();
    manager uuid := gen_random_uuid();
    member uuid := gen_random_uuid();
BEGIN
    PERFORM set_config('test.actor', actor::text, true);
    PERFORM set_config('test.target', target::text, true);
    PERFORM set_config('test.org', org::text, true);
    PERFORM set_config('test.manager', manager::text, true);
    PERFORM set_config('test.member', member::text, true);
    INSERT INTO auth.users (id, email, created_at, updated_at)
    VALUES (actor, actor || '@example.invalid', now(), now()),
           (target, target || '@example.invalid', now(), now());
    INSERT INTO community_orgs.organisations (org_id, entity_name, slug, is_public)
    VALUES (org, 'P1 regression fixture', 'p1-test-' || org, true);
    INSERT INTO community_orgs.contact_info (org_id, email) VALUES (org, 'fixture@example.invalid');
    INSERT INTO community_orgs.roles (id, name, permissions, hierarchy_level)
    VALUES (manager, 'p1-manager-' || manager, '{"can_manage_members":true}', 4),
           (member, 'p1-member-' || member, '{}', 1);
    INSERT INTO community_orgs.user_organisation_roles (user_id, organisation_id, role_id)
    VALUES (actor, org, manager);
    INSERT INTO auth.mfa_factors (id, user_id, factor_type, status, created_at, updated_at)
    VALUES (gen_random_uuid(), actor, 'totp', 'verified', now(), now());
END;
$$;

SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
DO $$
DECLARE t text; n bigint;
BEGIN
    FOREACH t IN ARRAY ARRAY['contact_info','financial_info','legal_details','dgr_endorsement',
        'documents','governance','org_members','role_audit_log','role_requests','user_organisation_roles']
    LOOP
        EXECUTE format('select count(*) from community_orgs.%I', t) INTO n;
        IF n <> 0 THEN RAISE EXCEPTION 'anon can read %', t; END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM community_orgs.organisations WHERE org_id=current_setting('test.org')::uuid)
    THEN RAISE EXCEPTION 'public browsing broken'; END IF;
END;
$$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $$
DECLARE
    actor uuid := current_setting('test.actor')::uuid;
    org uuid := current_setting('test.org')::uuid;
    member uuid := current_setting('test.member')::uuid;
    scenario text;
    call_sql text;
    t text;
    n bigint;
    expected_message text;
BEGIN
    FOREACH scenario IN ARRAY ARRAY['guest','aal1','missing_aal'] LOOP
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub',actor,'role','authenticated',
            'is_anonymous',scenario='guest','aal',CASE WHEN scenario='missing_aal' THEN NULL ELSE 'aal1' END)::text, true);
        expected_message := CASE WHEN scenario='guest' THEN 'A registered account is required'
                            ELSE 'Multi-factor authentication is required' END;
        IF scenario='guest' THEN
            FOREACH t IN ARRAY ARRAY['contact_info','financial_info','legal_details','dgr_endorsement',
                'documents','governance','org_members','role_audit_log','role_requests','user_organisation_roles'] LOOP
                EXECUTE format('select count(*) from community_orgs.%I', t) INTO n;
                IF n <> 0 THEN RAISE EXCEPTION 'guest can read %', t; END IF;
            END LOOP;
        END IF;
        FOREACH call_sql IN ARRAY ARRAY[
            format('select community_orgs.grant_user_role(%L,%L,%L,%L)',actor,org,member,actor),
            format('select community_orgs.revoke_user_role(%L,%L,%L,%L)',actor,org,member,actor),
            format('select community_orgs.request_role(%L,%L,%L)',actor,org,member),
            format('select community_orgs.process_role_request(%L,%L,''approved'')',gen_random_uuid(),actor)
        ] LOOP
            BEGIN
                EXECUTE call_sql;
                RAISE EXCEPTION 'RPC accepted %: %', scenario, call_sql;
            EXCEPTION WHEN insufficient_privilege THEN
                IF SQLERRM <> expected_message THEN RAISE; END IF;
            END;
        END LOOP;
    END LOOP;
END;
$$;
RESET ROLE;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM community_orgs.role_requests WHERE organisation_id=current_setting('test.org')::uuid)
       OR EXISTS (SELECT 1 FROM community_orgs.role_audit_log WHERE organisation_id=current_setting('test.org')::uuid)
       OR (SELECT count(*) FROM community_orgs.user_organisation_roles WHERE organisation_id=current_setting('test.org')::uuid) <> 1
    THEN RAISE EXCEPTION 'rejected calls changed records'; END IF;
END;
$$;

-- Run successful mutations once at aal2, then without an enrolled factor at aal1.
DO $$
DECLARE
    scenario text;
    actor uuid := current_setting('test.actor')::uuid;
    target uuid := current_setting('test.target')::uuid;
    org uuid := current_setting('test.org')::uuid;
    member uuid := current_setting('test.member')::uuid;
    req uuid;
BEGIN
    FOREACH scenario IN ARRAY ARRAY['aal2','no_mfa'] LOOP
        IF scenario='no_mfa' THEN DELETE FROM auth.mfa_factors WHERE user_id=actor; END IF;
        PERFORM set_config('request.jwt.claims', jsonb_build_object('sub',actor,'role','authenticated',
            'is_anonymous',false,'aal',CASE WHEN scenario='aal2' THEN 'aal2' ELSE 'aal1' END)::text, true);
        SET LOCAL ROLE authenticated;
        IF NOT EXISTS (SELECT 1 FROM community_orgs.contact_info WHERE org_id=org)
        THEN RAISE EXCEPTION 'registered reads broken'; END IF;
        PERFORM community_orgs.grant_user_role(target,org,member,actor);
        IF NOT community_orgs.revoke_user_role(target,org,member,actor)
        THEN RAISE EXCEPTION 'revoke failed'; END IF;
        req := community_orgs.request_role(actor,org,member);
        IF NOT community_orgs.process_role_request(req,actor,'approved')
        THEN RAISE EXCEPTION 'approval failed'; END IF;
        RESET ROLE;
        IF NOT EXISTS (SELECT 1 FROM community_orgs.role_requests WHERE id=req AND status='approved')
        THEN RAISE EXCEPTION 'approval not persisted'; END IF;
        -- Allow the next scenario to request the same role without a unique conflict.
        DELETE FROM community_orgs.role_requests WHERE id=req;
    END LOOP;
END;
$$;
ROLLBACK;
SELECT 'P1 access regression checks passed; all fixtures rolled back' AS result;

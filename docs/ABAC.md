# Schema changes needed to implement the full ABAC system:

```sql
    -- Core ABAC tables
    CREATE TABLE community_orgs.resource_attributes (
        resource_id serial PRIMARY KEY,
        type text NOT NULL CHECK (type IN ('organisation', 'contact', 'financial', 'governance', 'legal', 'operational', 'program', 'relationship', 'asset')),
        data_classification text NOT NULL CHECK (data_classification IN ('public', 'internal', 'confidential')),
        status text NOT NULL CHECK (status IN ('active', 'inactive', 'pending')),
        created_by uuid,
        last_modified_by uuid,
        attributes jsonb DEFAULT '{}'::jsonb,
        created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE community_orgs.subject_attributes (
        subject_id uuid PRIMARY KEY,
        roles text[] CHECK (roles <@ ARRAY['system_admin', 'org_admin', 'org_member', 'viewer']),
        org_memberships integer[],
        clearance_level text CHECK (clearance_level IN ('basic', 'elevated', 'admin')),
        department text CHECK (department IN ('management', 'operations', 'support')),
        is_verified boolean DEFAULT false,
        access_level text CHECK (access_level IN ('full', 'limited', 'basic')),
        attributes jsonb DEFAULT '{}'::jsonb,
        created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE community_orgs.action_records (
        action_id serial PRIMARY KEY,
        operation text NOT NULL CHECK (operation IN ('create', 'read', 'update', 'delete', 'list')),
        scope text NOT NULL CHECK (scope IN ('all', 'org_only', 'self_only')),
        batch text NOT NULL CHECK (batch IN ('single', 'multiple')),
        requires_approval boolean DEFAULT false,
        audit_level text CHECK (audit_level IN ('none', 'basic', 'detailed')),
        created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE community_orgs.environment_context (
        context_id serial PRIMARY KEY,
        client_type text CHECK (client_type IN ('web', 'mobile', 'api')),
        session_type text CHECK (session_type IN ('regular', 'elevated')),
        maintenance_mode boolean DEFAULT false,
        request_origin text CHECK (request_origin IN ('internal', 'external')),
        security_level text CHECK (security_level IN ('normal', 'high')),
        ip_address inet,
        created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
    );

    -- Link tables to connect resources with their attributes
    CREATE TABLE community_orgs.resource_attribute_links (
        link_id serial PRIMARY KEY,
        resource_type text NOT NULL,
        resource_id integer NOT NULL,
        attribute_id integer REFERENCES community_orgs.resource_attributes(resource_id),
        created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
    );

    -- Access policy table
    CREATE TABLE community_orgs.access_policies (
        policy_id serial PRIMARY KEY,
        name text NOT NULL,
        description text,
        subject_conditions jsonb,
        resource_conditions jsonb,
        action_conditions jsonb,
        environment_conditions jsonb,
        effect text CHECK (effect IN ('ALLOW', 'DENY')),
        priority integer DEFAULT 0,
        created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
    );

    -- Audit log for access decisions
    CREATE TABLE community_orgs.access_logs (
        log_id serial PRIMARY KEY,
        subject_id uuid,
        resource_id integer,
        action_id integer,
        context_id integer,
        decision boolean,
        policy_id integer,
        timestamp timestamp with time zone DEFAULT CURRENT_TIMESTAMP
    );

    -- Add indexes for performance
    CREATE INDEX idx_resource_attrs_type ON community_orgs.resource_attributes(type);
    CREATE INDEX idx_subject_attrs_roles ON community_orgs.subject_attributes USING gin(roles);
    CREATE INDEX idx_subject_attrs_org_memberships ON community_orgs.subject_attributes USING gin(org_memberships);
    CREATE INDEX idx_access_logs_subject ON community_orgs.access_logs(subject_id);
    CREATE INDEX idx_access_policies_priority ON community_orgs.access_policies(priority);
```

These tables work together to:
    - Store and manage attribute definitions
    - Link attributes to resources
    - Define access policies
    - Log access decisions
    - Support efficient querying through indexes

The system is now ready to implement access control decisions using these attributes through the policy evaluation function we created earlier.

Next steps would be to:
- Create triggers to automatically populate attribute tables
- Define default policies
- Create helper functions for common access patterns
- Set up audit logging

# Here are the triggers to automatically populate attribute tables:

```sql
    -- Function to manage resource attributes
    CREATE OR REPLACE FUNCTION community_orgs.manage_resource_attributes()
    RETURNS TRIGGER AS $$
    BEGIN
        INSERT INTO community_orgs.resource_attributes (
            type,
            data_classification,
            status,
            created_by,
            attributes
        ) VALUES (
            TG_ARGV[0], -- table name passed as trigger argument
            CASE 
                WHEN TG_TABLE_NAME = 'financial_info' THEN 'confidential'
                WHEN TG_TABLE_NAME = 'legal_details' THEN 'confidential'
                ELSE 'internal'
            END,
            'active',
            auth.uid(),
            jsonb_build_object(
                'org_id', NEW.org_id,
                'table', TG_TABLE_NAME,
                'created_at', CURRENT_TIMESTAMP
            )
        );

        -- Link the resource with its attributes
        INSERT INTO community_orgs.resource_attribute_links (
            resource_type,
            resource_id,
            attribute_id
        ) VALUES (
            TG_TABLE_NAME,
            NEW.org_id,
            currval('community_orgs.resource_attributes_resource_id_seq')
        );

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- Create triggers for each table
    CREATE TRIGGER tr_organisations_attributes
        AFTER INSERT ON community_orgs.organisations
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.manage_resource_attributes('organisation');

    CREATE TRIGGER tr_contact_info_attributes
        AFTER INSERT ON community_orgs.contact_info
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.manage_resource_attributes('contact');

    CREATE TRIGGER tr_financial_info_attributes
        AFTER INSERT ON community_orgs.financial_info
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.manage_resource_attributes('financial');

    -- Function to update subject attributes when org_members changes
    CREATE OR REPLACE FUNCTION community_orgs.manage_subject_attributes()
    RETURNS TRIGGER AS $$
    BEGIN
        INSERT INTO community_orgs.subject_attributes (
            subject_id,
            roles,
            org_memberships,
            clearance_level,
            access_level,
            is_verified
        ) 
        VALUES (
            NEW.user_id,
            ARRAY[NEW.role],
            ARRAY[NEW.org_id],
            CASE 
                WHEN NEW.role = 'admin' THEN 'elevated'
                ELSE 'basic'
            END,
            CASE 
                WHEN NEW.role = 'admin' THEN 'full'
                WHEN NEW.role = 'member' THEN 'limited'
                ELSE 'basic'
            END,
            true
        )
        ON CONFLICT (subject_id) DO UPDATE 
        SET 
            roles = array_append(subject_attributes.roles, NEW.role),
            org_memberships = array_append(subject_attributes.org_memberships, NEW.org_id),
            last_modified_at = CURRENT_TIMESTAMP;

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- Create trigger for org_members
    CREATE TRIGGER tr_org_members_subject_attributes
        AFTER INSERT OR UPDATE ON community_orgs.org_members
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.manage_subject_attributes();

    -- Function to log access decisions
    CREATE OR REPLACE FUNCTION community_orgs.log_access_decision()
    RETURNS TRIGGER AS $$
    BEGIN
        INSERT INTO community_orgs.access_logs (
            subject_id,
            resource_id,
            action_id,
            context_id,
            decision,
            policy_id
        ) VALUES (
            auth.uid(),
            NEW.org_id,
            (SELECT action_id FROM community_orgs.action_records WHERE operation = TG_OP LIMIT 1),
            (SELECT context_id FROM community_orgs.environment_context ORDER BY created_at DESC LIMIT 1),
            true,
            NULL
        );
        
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- Create access logging triggers
    CREATE TRIGGER tr_log_organisation_access
        AFTER INSERT OR UPDATE OR DELETE ON community_orgs.organisations
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.log_access_decision();
``` 

These triggers:
    - Automatically create and link resource attributes when new records are created
    - Update subject attributes when organization memberships change
    - Log all access decisions for audit purposes
    - Handle data classification automatically based on resource type
    - Maintain relationship between resources and their attributes
The triggers ensure the ABAC system stays current and consistent as data changes in the application.

# Here's how to test the triggers:

```sql
    -- Test resource attribute creation
    INSERT INTO community_orgs.organisations (
        legal_name,
        trading_name
    ) VALUES (
        'Test Organization',
        'TestOrg'
    ) RETURNING org_id;

    -- Verify resource attributes were created
    SELECT * FROM community_orgs.resource_attributes 
    WHERE type = 'organisation' 
    ORDER BY created_at DESC 
    LIMIT 1;

    -- Test subject attribute creation
    INSERT INTO community_orgs.org_members (
        org_id,
        user_id,
        role
    ) VALUES (
        1,  -- Use the org_id from previous insert
        auth.uid(),
        'admin'
    );

    -- Verify subject attributes were created
    SELECT * FROM community_orgs.subject_attributes 
    WHERE subject_id = auth.uid();

    -- Test access logging
    SELECT * FROM community_orgs.access_logs 
    WHERE subject_id = auth.uid() 
    ORDER BY timestamp DESC 
    LIMIT 1;
```

# Here are powerful additional triggers for specific scenarios:

```sql
    -- Trigger to handle financial data classification changes
    CREATE OR REPLACE FUNCTION community_orgs.handle_financial_sensitivity()
    RETURNS TRIGGER AS $$
    BEGIN
        IF NEW.annual_budget > 1000000 THEN
            UPDATE community_orgs.resource_attributes 
            SET data_classification = 'confidential',
                attributes = attributes || jsonb_build_object(
                    'high_value', true,
                    'requires_audit', true
                )
            WHERE resource_id IN (
                SELECT attribute_id 
                FROM community_orgs.resource_attribute_links 
                WHERE resource_id = NEW.org_id
            );
        END IF;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    CREATE TRIGGER tr_financial_sensitivity
        AFTER INSERT OR UPDATE ON community_orgs.financial_info
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.handle_financial_sensitivity();

    -- Trigger to manage program visibility based on funding sources
    CREATE OR REPLACE FUNCTION community_orgs.manage_program_visibility()
    RETURNS TRIGGER AS $$
    BEGIN
        IF EXISTS (
            SELECT 1 FROM community_orgs.financial_info
            WHERE org_id = NEW.org_id 
            AND 'government' = ANY(funding_sources)
        ) THEN
            INSERT INTO community_orgs.org_visibility (
                org_id,
                visibility_type
            ) VALUES (
                NEW.org_id,
                'public'
            )
            ON CONFLICT (org_id) DO UPDATE 
            SET visibility_type = 'public';
        END IF;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    CREATE TRIGGER tr_program_visibility
        AFTER INSERT OR UPDATE ON community_orgs.programs_services
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.manage_program_visibility();

    -- Trigger to handle relationship-based access changes
    CREATE OR REPLACE FUNCTION community_orgs.manage_relationship_access()
    RETURNS TRIGGER AS $$
    BEGIN
        -- When a new partnership is formed, update visibility
        IF NEW.relationship_type IN ('partner', 'affiliate') THEN
            -- Add partner org to allowed_org_ids
            UPDATE community_orgs.org_visibility
            SET visibility_type = 'limited',
                allowed_org_ids = array_append(allowed_org_ids, 
                    (SELECT org_id FROM community_orgs.organisations 
                    WHERE legal_name = NEW.partner_org)
                )
            WHERE org_id = NEW.org_id;
            
            -- Update resource attributes
            INSERT INTO community_orgs.resource_attributes (
                type,
                data_classification,
                status,
                attributes
            ) VALUES (
                'relationship',
                'internal',
                'active',
                jsonb_build_object(
                    'partnership_level', NEW.relationship_type,
                    'auto_share_enabled', true
                )
            );
        END IF;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    CREATE TRIGGER tr_relationship_access
        AFTER INSERT OR UPDATE ON community_orgs.relationships
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.manage_relationship_access();

    -- Trigger to handle temporal access patterns
    CREATE OR REPLACE FUNCTION community_orgs.manage_temporal_access()
    RETURNS TRIGGER AS $$
    BEGIN
        -- Create time-based access attributes
        INSERT INTO community_orgs.resource_attributes (
            type,
            data_classification,
            status,
            attributes
        ) VALUES (
            TG_TABLE_NAME,
            CASE 
                WHEN NEW.valid_until IS NOT NULL THEN 'internal'
                ELSE 'public'
            END,
            CASE 
                WHEN NEW.valid_until < CURRENT_DATE THEN 'inactive'
                ELSE 'active'
            END,
            jsonb_build_object(
                'temporal_access', true,
                'valid_from', NEW.valid_from,
                'valid_until', NEW.valid_until
            )
        );
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    CREATE TRIGGER tr_temporal_access
        AFTER INSERT OR UPDATE ON community_orgs.accreditation
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.manage_temporal_access();
```

These triggers handle:
    - Financial data sensitivity adjustments
    - Automatic program visibility based on funding sources
    - Partnership-based access modifications
    - Time-based access controls
    - Relationship-driven attribute updates

# Here are powerful custom attribute handlers for specific business rules:

```sql
    -- Handler for geographic service area restrictions
    CREATE OR REPLACE FUNCTION community_orgs.handle_service_area_attributes()
    RETURNS TRIGGER AS $$
    BEGIN
        -- Create geographically-aware access attributes
        INSERT INTO community_orgs.resource_attributes (
            type,
            data_classification,
            status,
            attributes
        ) VALUES (
            'operational',
            'internal',
            'active',
            jsonb_build_object(
                'service_area', NEW.service_area,
                'geo_restricted', true,
                'allowed_regions', (
                    SELECT array_agg(DISTINCT unnest(string_to_array(NEW.service_area, ',')))
                )
            )
        );
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    CREATE TRIGGER tr_service_area_attributes
        AFTER INSERT OR UPDATE OF service_area ON community_orgs.operational_details
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.handle_service_area_attributes();

    -- Handler for staff-size based access levels
    CREATE OR REPLACE FUNCTION community_orgs.handle_staff_size_attributes()
    RETURNS TRIGGER AS $$
    BEGIN
        UPDATE community_orgs.resource_attributes 
        SET attributes = attributes || jsonb_build_object(
            'org_size', CASE 
                WHEN (NEW.staff_count_paid + NEW.staff_count_volunteer) > 100 THEN 'large'
                WHEN (NEW.staff_count_paid + NEW.staff_count_volunteer) > 20 THEN 'medium'
                ELSE 'small'
            END,
            'requires_board', (NEW.staff_count_paid > 50)
        )
        WHERE resource_id IN (
            SELECT attribute_id 
            FROM community_orgs.resource_attribute_links 
            WHERE resource_id = NEW.org_id
        );
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    CREATE TRIGGER tr_staff_size_attributes
        AFTER INSERT OR UPDATE OF staff_count_paid, staff_count_volunteer 
        ON community_orgs.operational_details
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.handle_staff_size_attributes();

    -- Handler for language-based access restrictions
    CREATE OR REPLACE FUNCTION community_orgs.handle_language_attributes()
    RETURNS TRIGGER AS $$
    BEGIN
        INSERT INTO community_orgs.resource_attributes (
            type,
            data_classification,
            status,
            attributes
        ) VALUES (
            'operational',
            'internal',
            'active',
            jsonb_build_object(
                'supported_languages', NEW.languages_supported,
                'multilingual_access', array_length(NEW.languages_supported, 1) > 1,
                'translation_required', NOT ('en' = ANY(NEW.languages_supported))
            )
        );
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    CREATE TRIGGER tr_language_attributes
        AFTER INSERT OR UPDATE OF languages_supported ON community_orgs.operational_details
        FOR EACH ROW
        EXECUTE FUNCTION community_orgs.handle_language_attributes();
```

# Here's how to implement attribute-based queries using the handlers:

```sql
    -- Query organizations based on service area access
    CREATE OR REPLACE FUNCTION community_orgs.get_organizations_by_region(
        user_region text,
        user_id uuid
    ) RETURNS TABLE (
        org_id integer,
        legal_name text,
        access_level text
    ) AS $$
    BEGIN
        RETURN QUERY
        SELECT 
            o.org_id,
            o.legal_name,
            CASE 
                WHEN ra.attributes->>'geo_restricted' = 'true' 
                AND user_region = ANY(ra.attributes->'allowed_regions') THEN 'full'
                WHEN ra.attributes->>'geo_restricted' = 'true' THEN 'limited'
                ELSE 'public'
            END as access_level
        FROM community_orgs.organisations o
        JOIN community_orgs.resource_attribute_links ral ON o.org_id = ral.resource_id
        JOIN community_orgs.resource_attributes ra ON ral.attribute_id = ra.resource_id
        WHERE ra.type = 'operational';
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- Query based on organization size and staff attributes
    CREATE OR REPLACE FUNCTION community_orgs.get_large_organizations_requiring_board()
    RETURNS TABLE (
        org_id integer,
        legal_name text,
        staff_total integer,
        requires_board boolean
    ) AS $$
    BEGIN
        RETURN QUERY
        SELECT 
            o.org_id,
            o.legal_name,
            (op.staff_count_paid + op.staff_count_volunteer) as staff_total,
            (ra.attributes->>'requires_board')::boolean as requires_board
        FROM community_orgs.organisations o
        JOIN community_orgs.operational_details op ON o.org_id = op.org_id
        JOIN community_orgs.resource_attribute_links ral ON o.org_id = ral.resource_id
        JOIN community_orgs.resource_attributes ra ON ral.attribute_id = ra.resource_id
        WHERE ra.attributes->>'org_size' = 'large'
        AND (ra.attributes->>'requires_board')::boolean = true;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    -- Complex query combining multiple attributes
    CREATE OR REPLACE FUNCTION community_orgs.get_accessible_organizations(
        p_user_id uuid,
        p_region text,
        p_language text
    ) RETURNS TABLE (
        org_id integer,
        legal_name text,
        access_level text,
        translation_needed boolean
    ) AS $$
    BEGIN
        RETURN QUERY
        WITH user_permissions AS (
            SELECT 
                sa.roles,
                sa.clearance_level
            FROM community_orgs.subject_attributes sa
            WHERE sa.subject_id = p_user_id
        )
        SELECT DISTINCT
            o.org_id,
            o.legal_name,
            CASE 
                WHEN 'admin' = ANY((SELECT roles FROM user_permissions)) THEN 'full'
                WHEN ra.attributes->>'geo_restricted' = 'true' 
                    AND p_region = ANY(ra.attributes->'allowed_regions') THEN 'regional'
                ELSE 'limited'
            END as access_level,
            (ra2.attributes->>'translation_required')::boolean as translation_needed
        FROM community_orgs.organisations o
        JOIN community_orgs.resource_attribute_links ral ON o.org_id = ral.resource_id
        JOIN community_orgs.resource_attributes ra ON ral.attribute_id = ra.resource_id
        JOIN community_orgs.operational_details op ON o.org_id = op.org_id
        JOIN community_orgs.resource_attributes ra2 ON ra2.type = 'operational'
        WHERE (
            ra.status = 'active'
            AND (
                ra.attributes->>'geo_restricted' = 'false'
                OR p_region = ANY(ra.attributes->'allowed_regions')
            )
            AND (
                p_language = ANY(op.languages_supported)
                OR ra2.attributes->>'multilingual_access' = 'true'
            )
        );
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;

    attribute_based_queries.sql
    Usage examples:

    -- Get organizations in a specific region
    SELECT * FROM community_orgs.get_organizations_by_region('NSW', auth.uid());

    -- Get large organizations that require a board
    SELECT * FROM community_orgs.get_large_organizations_requiring_board();

    -- Get accessible organizations with complex criteria
    SELECT * FROM community_orgs.get_accessible_organizations(
        auth.uid(),
        'VIC',
        'en'
    );
```
These queries demonstrate how to:
    - Combine multiple attribute conditions
    - Handle geographic restrictions
    - Process language requirements
    - Apply user-specific permissions
    - Implement complex business rules

# Here are the default policies for your community organizations ABAC system:

```sql
    -- Insert default system-wide policies
    INSERT INTO community_orgs.access_policies (
        name,
        description,
        subject_conditions,
        resource_conditions,
        action_conditions,
        environment_conditions,
        effect,
        priority
    ) VALUES 
    -- System Admin Policy
    (
        'system_admin_full_access',
        'System administrators have full access to all resources',
        '{"roles": ["system_admin"]}',
        '{"type": ["organisation", "contact", "financial", "governance", "legal", "operational", "program", "relationship", "asset"]}',
        '{"operation": ["create", "read", "update", "delete", "list"]}',
        '{"security_level": ["normal", "high"]}',
        'ALLOW',
        1000
    ),
    -- Organization Admin Policy
    (
        'org_admin_own_org',
        'Organization administrators have full access to their own organization',
        '{"roles": ["org_admin"]}',
        '{"type": ["organisation", "contact", "financial", "governance", "legal", "operational", "program", "relationship", "asset"]}',
        '{"operation": ["create", "read", "update", "delete"], "scope": "org_only"}',
        '{"security_level": "normal"}',
        'ALLOW',
        900
    ),
    -- Member Read Access
    (
        'member_read_access',
        'Organization members can read their organization data',
        '{"roles": ["org_member"]}',
        '{"type": ["organisation", "contact", "operational", "program"], "data_classification": ["public", "internal"]}',
        '{"operation": ["read", "list"], "scope": "org_only"}',
        '{"security_level": "normal"}',
        'ALLOW',
        800
    ),
    -- Public Access Policy
    (
        'public_org_info',
        'Public access to basic organization information',
        '{"access_level": "basic"}',
        '{"type": ["organisation"], "data_classification": "public"}',
        '{"operation": ["read"], "scope": "all"}',
        '{"security_level": "normal"}',
        'ALLOW',
        100
    ),
    -- Financial Data Protection
    (
        'financial_data_protection',
        'Restrict access to financial information',
        '{"roles": ["system_admin", "org_admin"]}',
        '{"type": ["financial"], "data_classification": "confidential"}',
        '{"operation": ["read", "update"], "scope": "org_only"}',
        '{"security_level": "high"}',
        'ALLOW',
        950
    ),
    -- Partnership Access
    (
        'partnership_access',
        'Allow partner organizations to access shared resources',
        '{"roles": ["org_admin", "org_member"]}',
        '{"type": ["program", "relationship"], "attributes": {"partnership_level": ["partner", "affiliate"]}}',
        '{"operation": ["read"], "scope": "all"}',
        '{"security_level": "normal"}',
        'ALLOW',
        700
    );

    -- Create helper function to check policy
    CREATE OR REPLACE FUNCTION community_orgs.check_access_policy(
        p_subject_id uuid,
        p_resource_type text,
        p_operation text,
        p_org_id integer DEFAULT NULL
    ) RETURNS boolean AS $$
    DECLARE
        v_subject_attrs jsonb;
        v_resource_attrs jsonb;
        v_allowed boolean;
    BEGIN
        -- Get subject attributes
        SELECT jsonb_build_object(
            'roles', roles,
            'access_level', access_level,
            'clearance_level', clearance_level
        )
        INTO v_subject_attrs
        FROM community_orgs.subject_attributes
        WHERE subject_id = p_subject_id;

        -- Get resource attributes
        SELECT jsonb_build_object(
            'type', type,
            'data_classification', data_classification,
            'attributes', attributes
        )
        INTO v_resource_attrs
        FROM community_orgs.resource_attributes ra
        JOIN community_orgs.resource_attribute_links ral ON ra.resource_id = ral.attribute_id
        WHERE ral.resource_type = p_resource_type
        AND (p_org_id IS NULL OR ral.resource_id = p_org_id)
        LIMIT 1;

        -- Check policies
        SELECT EXISTS (
            SELECT 1
            FROM community_orgs.access_policies
            WHERE effect = 'ALLOW'
            AND (subject_conditions IS NULL OR v_subject_attrs @> subject_conditions)
            AND (resource_conditions IS NULL OR v_resource_attrs @> resource_conditions)
            AND (action_conditions->>'operation' = p_operation)
            ORDER BY priority DESC
            LIMIT 1
        ) INTO v_allowed;

        RETURN v_allowed;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;
```

These policies provide:
    - Hierarchical access control
    - Data classification protection
    - Role-based permissions
    - Partnership-aware sharing
    - Public access controls

### 5. Implement Access Control in SvelteKit
Here's how to use these policies in your SvelteKit application:

```typescript
// src/lib/server/auth.ts
    import { createServerClient } from '@supabase/ssr'
    import type { Database } from '$lib/types/supabase'

    export async function checkAccess(
        supabase: ReturnType<typeof createServerClient<Database>>,
        resourceType: string,
        operation: string,
        orgId?: number
    ) {
        const { data, error } = await supabase.rpc('check_access_policy', {
            p_subject_id: (await supabase.auth.getUser()).data.user?.id,
            p_resource_type: resourceType,
            p_operation: operation,
            p_org_id: orgId
        })
        return { allowed: data, error }
    }
```

```typescript
// src/routes/orgs/[id]/+page.server.ts
    import { error, fail } from '@sveltejs/kit'
    import { checkAccess } from '$lib/server/auth'

    export const load = async ({ params, locals: { supabase } }) => {
        const { allowed } = await checkAccess(supabase, 'organisation', 'read', parseInt(params.id))
        
        if (!allowed) {
            throw error(403, 'Access denied')
        }

        const { data: org } = await supabase
            .from('organisations')
            .select(`
                *,
                contact_info (*),
                operational_details (*)
            `)
            .eq('org_id', params.id)
            .single()

        return { org }
    }

    export const actions = {
        update: async ({ request, params, locals: { supabase } }) => {
            const { allowed } = await checkAccess(supabase, 'organisation', 'update', parseInt(params.id))
            
            if (!allowed) {
                return fail(403, { message: 'Not authorized to update this organization' })
            }

            const formData = await request.formData()
            const updates = Object.fromEntries(formData)

            const { error: updateError } = await supabase
                .from('organisations')
                .update(updates)
                .eq('org_id', params.id)

            if (updateError) {
                return fail(500, { message: 'Failed to update organization' })
            }

            return { success: true }
        }
    }
```
```typescript
    //server.ts
    import { json } from '@sveltejs/kit'

    export async function GET({ url, locals: { supabase } }) {
        const { allowed } = await checkAccess(supabase, 'organisation', 'list')
        
        if (!allowed) {
            return new Response('Forbidden', { status: 403 })
        }

        const { data: orgs } = await supabase
            .from('organisations')
            .select('*')
            .order('legal_name')

        return json(orgs)
    }
```
/
```svelte
    //server.ts
    <script lang="ts">
        export let data
        
        $: ({ org } = data)
    </script>

    <div class="org-details">
        <h1>{org.legal_name}</h1>
        {#if org.contact_info}
            <section class="contact">
                <h2>Contact Information</h2>
                <p>{org.contact_info.physical_address}</p>
                <p>{org.contact_info.email}</p>
            </section>
        {/if}
        
        {#if org.operational_details}
            <section class="operations">
                <h2>Operations</h2>
                <p>Service Area: {org.operational_details.service_area}</p>
                <p>Staff: {org.operational_details.staff_count_paid} paid, 
                {org.operational_details.staff_count_volunteer} volunteers</p>
            </section>
        {/if}
    </div>
```
This implementation:
    - Centralizes access control checks
    - Enforces policies at the server level
    - Provides type safety with TypeScript
    - Handles both API and page routes
    - Integrates with SvelteKit's form actions


# Here are powerful helper functions for common access patterns:

```typescript
// permissions.ts
    import type { SupabaseClient } from '@supabase/supabase-js'
    import type { Database } from '$lib/types/supabase'

    export class PermissionManager {
        constructor(private supabase: SupabaseClient<Database>) {}

        // Check if user can manage an organization
        async canManageOrg(orgId: number) {
            const { data } = await this.supabase.rpc('check_access_policy', {
                p_resource_type: 'organisation',
                p_operation: 'update',
                p_org_id: orgId
            })
            return !!data
        }

        // Check if user can view financial data
        async canViewFinancials(orgId: number) {
            const { data } = await this.supabase.rpc('check_access_policy', {
                p_resource_type: 'financial',
                p_operation: 'read',
                p_org_id: orgId
            })
            return !!data
        }

        // Check multiple permissions at once
        async checkMultiplePermissions(orgId: number, operations: string[]) {
            const checks = operations.map(op => 
                this.supabase.rpc('check_access_policy', {
                    p_resource_type: 'organisation',
                    p_operation: op,
                    p_org_id: orgId
                })
            )
            const results = await Promise.all(checks)
            return Object.fromEntries(
                operations.map((op, i) => [op, !!results[i].data])
            )
        }

        // Get all organizations user can access
        async getAccessibleOrgs() {
            const { data } = await this.supabase
                .from('organisations')
                .select(`
                    org_id,
                    legal_name,
                    trading_name,
                    org_visibility (visibility_type, allowed_org_ids)
                `)
            
            return data?.filter(org => 
                org.org_visibility.visibility_type === 'public' ||
                (org.org_visibility.visibility_type === 'limited' && 
                org.org_visibility.allowed_org_ids?.includes(org.org_id))
            )
        }
    }
```
```typescript
    // roles.ts
    export class RoleManager {
        constructor(private supabase: SupabaseClient<Database>) {}

        // Check if user has specific role for organization
        async hasRole(orgId: number, role: string) {
            const { data } = await this.supabase
                .from('org_members')
                .select('role')
                .eq('org_id', orgId)
                .single()
            
            return data?.role === role
        }

        // Get all roles for user across organizations
        async getUserRoles() {
            const { data } = await this.supabase
                .from('org_members')
                .select(`
                    org_id,
                    role,
                    organisations (legal_name)
                `)
            
            return data
        }
    }
```

## Usage in SvelteKit routes:

```svelte
// +page.server.ts
    import { PermissionManager } from '$lib/server/permissions'
    import { RoleManager } from '$lib/server/roles'

    export async function load({ params, locals: { supabase } }) {
        const permManager = new PermissionManager(supabase)
        const roleManager = new RoleManager(supabase)

        const [permissions, roles] = await Promise.all([
            permManager.checkMultiplePermissions(parseInt(params.id), ['read', 'update', 'delete']),
            roleManager.getUserRoles()
        ])

        const orgData = permissions.read ? await loadOrgData(params.id) : null

        return {
            permissions,
            roles,
            org: orgData
        }
    }
```
```svelte
// hooks.server.ts
    import { PermissionManager } from '$lib/server/permissions'

    export const handle = async ({ event, resolve }) => {
        if (event.locals.supabase) {
            event.locals.permissions = new PermissionManager(event.locals.supabase)
        }
        
        return resolve(event)
    }
```

These helpers provide:
    - Reusable permission checks
    - Role management utilities
    - Batch permission checking
    - Organization visibility handling
    - Type-safe access patterns

# Here are advanced permission patterns that extend our existing system:

```typescript
    // advanced-permissions.ts
    import type { SupabaseClient } from '@supabase/supabase-js'
    import type { Database } from '$lib/types/supabase'

    export class AdvancedPermissionManager {
        constructor(private supabase: SupabaseClient<Database>) {}

        // Hierarchical Permission Checking
        async checkHierarchicalAccess(orgId: number) {
            const { data: hierarchy } = await this.supabase
                .from('organisations')
                .select(`
                    org_id,
                    parent_org_id,
                    child_orgs:organisations!child_org_fk(org_id)
                `)
                .eq('org_id', orgId)
                .single()

            return {
                canAccessParent: await this.checkAccess(hierarchy.parent_org_id),
                canAccessChildren: await Promise.all(
                    hierarchy.child_orgs.map(child => 
                        this.checkAccess(child.org_id)
                    )
                )
            }
        }

        // Time-based Permission Patterns
        async checkTemporalAccess(orgId: number) {
            const now = new Date()
            const { data: schedule } = await this.supabase
                .from('operational_details')
                .select('operating_hours')
                .eq('org_id', orgId)
                .single()

            const currentHours = schedule.operating_hours[now.getDay()]
            const isWithinHours = this.isTimeWithinRange(
                now,
                currentHours.start,
                currentHours.end
            )

            return {
                isWithinOperatingHours: isWithinHours,
                nextAvailableTime: this.getNextAvailableTime(schedule.operating_hours)
            }
        }

        // Geographic Permission Boundaries
        async checkGeographicAccess(orgId: number, userLocation: { lat: number; lng: number }) {
            const { data: serviceArea } = await this.supabase
                .from('operational_details')
                .select('service_area')
                .eq('org_id', orgId)
                .single()

            return {
                isInServiceArea: this.isPointInPolygon(userLocation, serviceArea.boundaries),
                nearestServiceLocation: this.findNearestLocation(userLocation, serviceArea.locations)
            }
        }

        // Dynamic Team-based Permissions
        async checkTeamAccess(orgId: number, teamId: number) {
            const { data: teamPermissions } = await this.supabase
                .from('team_permissions')
                .select(`
                    permissions,
                    inheritance_rules,
                    delegated_access
                `)
                .eq('team_id', teamId)
                .single()

            return {
                directAccess: teamPermissions.permissions,
                inheritedAccess: await this.resolveInheritedPermissions(
                    teamPermissions.inheritance_rules
                ),
                delegatedAccess: await this.resolveDelegatedAccess(
                    teamPermissions.delegated_access
                )
            }
        }

        // Attribute-based Dynamic Rules
        async evaluateComplexRules(orgId: number) {
            const { data: attributes } = await this.supabase
                .from('resource_attributes')
                .select('*')
                .eq('org_id', orgId)

            return {
                financialAccess: this.evaluateFinancialRules(attributes.financial),
                sensitiveDataAccess: this.evaluateSensitivityRules(attributes.sensitivity),
                complianceLevel: this.evaluateComplianceRules(attributes.compliance)
            }
        }

        // Workflow-based Permissions
        async checkWorkflowStageAccess(workflowId: number) {
            const { data: workflow } = await this.supabase
                .from('workflows')
                .select(`
                    current_stage,
                    stage_permissions,
                    required_approvals,
                    completion_criteria
                `)
                .eq('workflow_id', workflowId)
                .single()

            return {
                canProgress: await this.evaluateWorkflowProgress(workflow),
                requiredApprovals: this.getPendingApprovals(workflow),
                nextStageRequirements: this.getNextStageRequirements(workflow)
            }
        }
    }
```

## Usage in a complex scenario:

```ts
    // +page.server.ts
    export async function load({ params, locals: { supabase } }) {
        const advancedPerms = new AdvancedPermissionManager(supabase)
        
        const [
            hierarchyAccess,
            temporalAccess,
            workflowAccess
        ] = await Promise.all([
            advancedPerms.checkHierarchicalAccess(parseInt(params.id)),
            advancedPerms.checkTemporalAccess(parseInt(params.id)),
            advancedPerms.checkWorkflowStageAccess(parseInt(params.id))
        ])

        return {
            hierarchyAccess,
            temporalAccess,
            workflowAccess,
            permissionMatrix: {
                canAccessHierarchy: hierarchyAccess.canAccessParent && 
                                hierarchyAccess.canAccessChildren.every(access => access),
                isOperational: temporalAccess.isWithinOperatingHours,
                workflowStatus: workflowAccess.canProgress
            }
        }
    }
```

These patterns enable:
    - Hierarchical organization access control
    - Time-based permission restrictions
    - Geographic boundary enforcement
    - Team-based permission inheritance
    - Complex attribute-based rules
    - Workflow stage permissions

# Frontend Components
Here are the frontend components that consume the advanced permission patterns:

<script lang="ts">
    import type { HierarchyAccess } from '$lib/types/permissions'
    
    export let hierarchyAccess: HierarchyAccess
    
    $: ({ canAccessParent, canAccessChildren } = hierarchyAccess)
</script>

<div class="hierarchy-tree">
    {#if canAccessParent}
        <div class="parent-org">
            <h3>Parent Organization</h3>
            <slot name="parent" />
        </div>
    {/if}
    
    <div class="current-org">
        <slot />
    </div>
    
    {#if canAccessChildren.length}
        <div class="child-orgs">
            <h3>Child Organizations</h3>
            {#each canAccessChildren as childAccess, i}
                {#if childAccess}
                    <slot name="child" {i} />
                {/if}
            {/each}
        </div>
    {/if}
</div>

HierarchyAccess.svelte
<script lang="ts">
    import { onMount } from 'svelte'
    import type { TemporalAccess } from '$lib/types/permissions'
    
    export let temporalAccess: TemporalAccess
    
    $: ({ isWithinOperatingHours, nextAvailableTime } = temporalAccess)
    
    let timeRemaining: string
    
    onMount(() => {
        const timer = setInterval(() => {
            timeRemaining = calculateTimeRemaining(nextAvailableTime)
        }, 1000)
        
        return () => clearInterval(timer)
    })
</script>

<div class="temporal-access">
    {#if isWithinOperatingHours}
        <div class="status-active">
            <span class="indicator" />
            Currently Operating
        </div>
    {:else}
        <div class="status-inactive">
            <span class="indicator" />
            Outside Operating Hours
            <p>Next Available: {timeRemaining}</p>
        </div>
    {/if}
</div>

TemporalAccess.svelte
<script lang="ts">
    import type { WorkflowAccess } from '$lib/types/permissions'
    
    export let workflowAccess: WorkflowAccess
    
    $: ({ canProgress, requiredApprovals, nextStageRequirements } = workflowAccess)
</script>

<div class="workflow-status">
    <div class="approvals">
        <h4>Required Approvals</h4>
        {#each requiredApprovals as approval}
            <div class="approval-item">
                <span class={approval.status} />
                {approval.approverRole}: {approval.status}
            </div>
        {/each}
    </div>
    
    {#if canProgress}
        <button on:click>Advance to Next Stage</button>
    {:else}
        <div class="requirements">
            <h4>Requirements for Next Stage</h4>
            <ul>
                {#each nextStageRequirements as req}
                    <li class={req.met ? 'met' : 'pending'}>
                        {req.description}
                    </li>
                {/each}
            </ul>
        </div>
    {/if}
</div>

WorkflowAccess.svelte
Usage in a page component:

<script lang="ts">
    import HierarchyAccess from '$lib/components/permissions/HierarchyAccess.svelte'
    import TemporalAccess from '$lib/components/permissions/TemporalAccess.svelte'
    import WorkflowAccess from '$lib/components/permissions/WorkflowAccess.svelte'
    
    export let data
    
    $: ({ hierarchyAccess, temporalAccess, workflowAccess } = data)
</script>

<div class="org-dashboard">
    <HierarchyAccess {hierarchyAccess}>
        <div slot="parent">
            <h2>{data.parentOrg.name}</h2>
        </div>
        
        <div>Current Organization Details</div>
        
        <div slot="child" let:i>
            <h2>{data.childOrgs[i].name}</h2>
        </div>
    </HierarchyAccess>
    
    <TemporalAccess {temporalAccess} />
    
    <WorkflowAccess {workflowAccess} />
</div>

+page.svelte
These components provide:
    - Visual hierarchy representation
    - Real-time operational status
    - Workflow progress tracking
    - Dynamic permission updates
    - Interactive user feedback

# Interactive Features
Here are powerful interactive permission features that enhance user experience and control:

<script lang="ts">
    import { createEventDispatcher } from 'svelte'
    import type { PermissionMatrix } from '$lib/types/permissions'
    
    const dispatch = createEventDispatcher()
    
    export let permissions: PermissionMatrix
    
    function updatePermission(resource: string, action: string, value: boolean) {
        dispatch('update', { resource, action, value })
    }
</script>

<div class="permission-matrix">
    {#each Object.entries(permissions) as [resource, actions]}
        <div class="resource-group">
            <h3>{resource}</h3>
            <div class="actions-grid">
                {#each Object.entries(actions) as [action, enabled]}
                    <label class="toggle-wrapper">
                        <input
                            type="checkbox"
                            checked={enabled}
                            on:change={(e) => updatePermission(resource, action, e.target.checked)}
                        />
                        <span class="toggle-label">{action}</span>
                    </label>
                {/each}
            </div>
        </div>
    </div>
</div>

PermissionEditor.svelte
<script lang="ts">
    import { DragDropList } from '$lib/components/DragDrop'
    import type { Permission } from '$lib/types/permissions'
    
    export let availablePermissions: Permission[]
    export let selectedPermissions: Permission[]
    
    function handleDrop(event: CustomEvent) {
        const { item, target } = event.detail
        dispatch('permissionChange', { added: item, target })
    }
</script>

<div class="role-builder">
    <DragDropList
        items={availablePermissions}
        on:drop={handleDrop}
    >
        <div slot="item" let:item>
            <div class="permission-card">
                <h4>{item.name}</h4>
                <p>{item.description}</p>
                <span class="scope">{item.scope}</span>
            </div>
        </div>
    </DragDropList>
    
    <div class="selected-permissions">
        {#each selectedPermissions as permission}
            <div class="selected-permission">
                {permission.name}
                <button on:click={() => dispatch('remove', permission)}>
                    Remove
                </button>
            </div>
        {/each}
    </div>
</div>

RoleBuilder.svelte
<script lang="ts">
    import { Calendar } from '$lib/components/Calendar'
    import type { Schedule } from '$lib/types/permissions'
    
    export let schedule: Schedule
    
    function handleTimeSlotSelect(event: CustomEvent) {
        const { day, time } = event.detail
        dispatch('scheduleUpdate', {
            day,
            time,
            action: 'add'
        })
    }
</script>

<div class="access-scheduler">
    <Calendar
        value={schedule}
        on:select={handleTimeSlotSelect}
        selectionMode="multiple"
    >
        <div slot="timeSlot" let:slot>
            <div class="time-slot" class:active={slot.isActive}>
                {slot.time}
                {#if slot.isActive}
                    <button on:click={() => dispatch('scheduleUpdate', {
                        day: slot.day,
                        time: slot.time,
                        action: 'remove'
                    })}>
                        Remove
                    </button>
                {/if}
            </div>
        </div>
    </Calendar>
</div>

AccessScheduler.svelte
Usage in an admin interface:

<script lang="ts">
    import PermissionEditor from '$lib/components/permissions/PermissionEditor.svelte'
    import RoleBuilder from '$lib/components/permissions/RoleBuilder.svelte'
    import AccessScheduler from '$lib/components/permissions/AccessScheduler.svelte'
    
    export let data
    
    async function handlePermissionUpdate(event: CustomEvent) {
        const { resource, action, value } = event.detail
        await updatePermission(resource, action, value)
    }
    
    async function handleScheduleUpdate(event: CustomEvent) {
        const { day, time, action } = event.detail
        await updateSchedule(day, time, action)
    }
</script>

<div class="admin-dashboard">
    <section class="permissions">
        <h2>Permission Management</h2>
        <PermissionEditor
            permissions={data.permissionMatrix}
            on:update={handlePermissionUpdate}
        />
    </section>
    
    <section class="roles">
        <h2>Role Configuration</h2>
        <RoleBuilder
            availablePermissions={data.availablePermissions}
            selectedPermissions={data.selectedPermissions}
            on:permissionChange={handleRoleUpdate}
        />
    </section>
    
    <section class="scheduling">
        <h2>Access Scheduling</h2>
        <AccessScheduler
            schedule={data.accessSchedule}
            on:scheduleUpdate={handleScheduleUpdate}
        />
    </section>
</div>

+page.svelte
These features provide:
    - Visual permission management
    - Drag-and-drop role building
    - Time-based access scheduling
    - Real-time permission updates
    - Interactive configuration tools

# Backend Implementations
Here are the backend implementations that support the interactive permission features:

import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '$lib/types/permissions'

export class InteractivePermissionManager {
    constructor(private supabase: SupabaseClient<Database>) {}

    // Update permission matrix
    async updatePermission(resource: string, action: string, value: boolean) {
        const { data, error } = await this.supabase
            .from('access_policies')
            .upsert({
                resource_type: resource,
                action_type: action,
                enabled: value,
                updated_at: new Date().toISOString()
            })
            .select()

        return { data, error }
    }

    // Manage role permissions
    async updateRolePermissions(roleId: string, permissions: string[]) {
        const { data, error } = await this.supabase
            .from('role_permissions')
            .upsert(
                permissions.map(permissionId => ({
                    role_id: roleId,
                    permission_id: permissionId,
                    granted_at: new Date().toISOString()
                }))
            )
            .select()

        return { data, error }
    }

    // Schedule access windows
    async updateAccessSchedule(orgId: number, schedule: AccessSchedule) {
        const { data, error } = await this.supabase
            .from('access_schedules')
            .upsert({
                org_id: orgId,
                schedule_data: schedule,
                effective_from: new Date().toISOString()
            })
            .select()

        return { data, error }
    }

    // Batch permission updates
    async batchUpdatePermissions(updates: PermissionUpdate[]) {
        const { data, error } = await this.supabase
            .rpc('batch_update_permissions', {
                updates: updates
            })

        return { data, error }
    }

    // Get effective permissions
    async getEffectivePermissions(userId: string, orgId: number) {
        const { data, error } = await this.supabase
            .rpc('get_effective_permissions', {
                p_user_id: userId,
                p_org_id: orgId
            })

        return { data, error }
    }
}

interactive-permissions.ts
-- Function to batch update permissions
CREATE OR REPLACE FUNCTION community_orgs.batch_update_permissions(
    updates jsonb[]
) RETURNS jsonb AS $$
DECLARE
    result jsonb = '[]'::jsonb;
    update_record jsonb;
BEGIN
    FOR update_record IN SELECT * FROM jsonb_array_elements(updates)
    LOOP
        -- Update the permission
        INSERT INTO community_orgs.access_policies (
            name,
            subject_conditions,
            resource_conditions,
            action_conditions,
            effect
        ) VALUES (
            update_record->>'name',
            update_record->'subject_conditions',
            update_record->'resource_conditions',
            update_record->'action_conditions',
            update_record->>'effect'
        )
        ON CONFLICT (name) DO UPDATE
        SET 
            subject_conditions = EXCLUDED.subject_conditions,
            resource_conditions = EXCLUDED.resource_conditions,
            action_conditions = EXCLUDED.action_conditions,
            effect = EXCLUDED.effect
        RETURNING jsonb_build_object(
            'name', name,
            'status', 'updated'
        ) INTO result;
    END LOOP;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get effective permissions
CREATE OR REPLACE FUNCTION community_orgs.get_effective_permissions(
    p_user_id uuid,
    p_org_id integer
) RETURNS jsonb AS $$
DECLARE
    result jsonb;
BEGIN
    WITH user_roles AS (
        SELECT array_agg(role) as roles
        FROM community_orgs.org_members
        WHERE user_id = p_user_id
        AND org_id = p_org_id
    ),
    applicable_policies AS (
        SELECT 
            ap.name,
            ap.effect,
            ap.priority
        FROM community_orgs.access_policies ap
        CROSS JOIN user_roles ur
        WHERE ap.subject_conditions->>'roles' <@ ur.roles::text[]
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'policy_name', name,
            'effect', effect,
            'priority', priority
        )
    ) INTO result
    FROM applicable_policies
    ORDER BY priority DESC;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

06_interactive_functions.sql
Usage in SvelteKit endpoints:

import { json } from '@sveltejs/kit'
import { InteractivePermissionManager } from '$lib/server/interactive-permissions'

export async function POST({ request, locals: { supabase } }) {
    const permManager = new InteractivePermissionManager(supabase)
    const updates = await request.json()

    const { data, error } = await permManager.batchUpdatePermissions(updates)

    if (error) {
        return new Response(JSON.stringify({ error }), { status: 400 })
    }

    return json(data)
}

+server.ts
These implementations provide:
    Real-time permission updates
    Batch processing capabilities
    Role-based permission management
    Scheduled access control
    Effective permission calculation

# Advanced Backend Patterns

Here are powerful advanced backend patterns for sophisticated permission management:

import { Redis } from '@upstash/redis'
import type { PermissionKey } from '$lib/types/permissions'

export class PermissionCache {
    private redis: Redis
    private readonly TTL = 3600 // 1 hour

    constructor() {
        this.redis = new Redis({
            url: process.env.UPSTASH_REDIS_URL,
            token: process.env.UPSTASH_REDIS_TOKEN
        })
    }

    async getCachedPermission(key: PermissionKey) {
        return this.redis.get(`perm:${JSON.stringify(key)}`)
    }

    async setCachedPermission(key: PermissionKey, value: any) {
        await this.redis.set(
            `perm:${JSON.stringify(key)}`,
            value,
            { ex: this.TTL }
        )
    }
}

PermissionCache.ts
import type { RealtimeChannel } from '@supabase/supabase-js'

export class PermissionObserver {
    private channels: Map<string, RealtimeChannel> = new Map()

    constructor(private supabase: SupabaseClient) {}

    observePermissionChanges(orgId: number, callback: (payload: any) => void) {
        const channel = this.supabase
            .channel(`org-permissions-${orgId}`)
            .on(
                'postgres_changes',
                {
                    event: '*',
                    schema: 'community_orgs',
                    table: 'access_policies'
                },
                callback
            )
            .subscribe()

        this.channels.set(`org-${orgId}`, channel)
        return () => this.cleanup(orgId)
    }

    private cleanup(orgId: number) {
        const channel = this.channels.get(`org-${orgId}`)
        if (channel) {
            channel.unsubscribe()
            this.channels.delete(`org-${orgId}`)
        }
    }
}

PermissionObserver.ts
export class PermissionAggregator {
    async aggregatePermissions(userId: string, context: PermissionContext) {
        const [
            rolePermissions,
            teamPermissions,
            temporalPermissions,
            locationPermissions
        ] = await Promise.all([
            this.getRolePermissions(userId),
            this.getTeamPermissions(userId),
            this.getTemporalPermissions(context.timestamp),
            this.getLocationPermissions(context.location)
        ])

        return this.mergePermissions([
            rolePermissions,
            teamPermissions,
            temporalPermissions,
            locationPermissions
        ])
    }

    private mergePermissions(permissionSets: Permission[][]): Permission[] {
        return permissionSets.reduce((acc, curr) => {
            return this.resolveConflicts(acc, curr)
        }, [])
    }
}

PermissionAggregator.ts
export class PermissionMetrics {
    async recordDecision(decision: PermissionDecision) {
        await this.supabase
            .from('permission_metrics')
            .insert({
                user_id: decision.userId,
                resource_type: decision.resourceType,
                action: decision.action,
                granted: decision.granted,
                evaluation_time_ms: decision.evaluationTime,
                context: decision.context
            })
    }

    async getMetrics(timeframe: TimeFrame) {
        const { data } = await this.supabase
            .rpc('get_permission_metrics', {
                start_time: timeframe.start,
                end_time: timeframe.end
            })
        return data
    }
}

PermissionMetrics.ts
Integration with the main permission manager:

export class AdvancedPermissionManager {
    private cache: PermissionCache
    private observer: PermissionObserver
    private aggregator: PermissionAggregator
    private metrics: PermissionMetrics

    constructor(private supabase: SupabaseClient) {
        this.cache = new PermissionCache()
        this.observer = new PermissionObserver(supabase)
        this.aggregator = new PermissionAggregator()
        this.metrics = new PermissionMetrics()
    }

    async checkPermission(request: PermissionRequest) {
        const startTime = performance.now()
        
        // Try cache first
        const cached = await this.cache.getCachedPermission(request.key)
        if (cached) return cached

        // Aggregate permissions
        const permissions = await this.aggregator.aggregatePermissions(
            request.userId,
            request.context
        )

        // Evaluate decision
        const decision = this.evaluatePermissions(permissions, request)
        
        // Record metrics
        await this.metrics.recordDecision({
            ...decision,
            evaluationTime: performance.now() - startTime
        })

        // Cache result
        await this.cache.setCachedPermission(request.key, decision)

        return decision
    }
}

AdvancedPermissionManager.ts
These patterns provide:

Permission caching for performance
Real-time permission updates
Complex permission aggregation
Metrics and monitoring
Conflict resolution
Would you like to see how to implement the frontend components that utilize these advanced patterns or explore specific use cases?

Try again with different context
Add context...
Avatar for alankeown-uhbjv
Alan Keown
I would you like to see how to implement the frontend components that utilize these advanced patterns and explore specific use cases.

Claude 3.5 Sonnet (New)
Here are the frontend components that utilize the advanced patterns, along with specific use cases:

<script lang="ts">
    import { onMount } from 'svelte'
    import { PermissionObserver } from '$lib/client/PermissionObserver'
    import type { Permission } from '$lib/types/permissions'
    
    export let orgId: number
    
    let permissions: Permission[] = []
    let observer: PermissionObserver
    
    onMount(() => {
        observer = new PermissionObserver()
        
        return observer.observePermissionChanges(orgId, (updates) => {
            permissions = updates
        })
    })
</script>

<div class="permission-monitor">
    <div class="real-time-updates">
        {#each permissions as permission}
            <div class="permission-update" class:active={permission.active}>
                <span class="status-indicator" />
                {permission.name}: {permission.status}
            </div>
        {/each}
    </div>
</div>

AdvancedPermissionMonitor.svelte
<script lang="ts">
    import { LineChart } from '$lib/components/charts'
    import type { PermissionMetrics } from '$lib/types/permissions'
    
    export let metrics: PermissionMetrics
    
    $: chartData = transformMetricsData(metrics)
</script>

<div class="metrics-dashboard">
    <LineChart
        data={chartData}
        xAxis="timestamp"
        yAxis="count"
        series={['granted', 'denied']}
    />
    
    <div class="metrics-summary">
        <div class="metric-card">
            <h3>Success Rate</h3>
            <p>{metrics.successRate}%</p>
        </div>
        <div class="metric-card">
            <h3>Average Response Time</h3>
            <p>{metrics.avgResponseTime}ms</p>
        </div>
    </div>
</div>

PermissionMetricsDisplay.svelte
Use case implementation:

import { AdvancedPermissionManager } from '$lib/server/AdvancedPermissionManager'

export async function load({ params, locals: { supabase } }) {
    const permManager = new AdvancedPermissionManager(supabase)
    
    const [permissions, metrics] = await Promise.all([
        permManager.checkPermission({
            userId: locals.user.id,
            resourceId: params.id,
            action: 'view',
            context: {
                location: locals.userLocation,
                timestamp: new Date(),
                deviceType: locals.deviceType
            }
        }),
        permManager.getMetrics({
            orgId: params.id,
            timeframe: 'last_7_days'
        })
    ])
    
    return {
        permissions,
        metrics
    }
}

+page.server.ts
<script lang="ts">
    import AdvancedPermissionMonitor from '$lib/components/permissions/AdvancedPermissionMonitor.svelte'
    import PermissionMetricsDisplay from '$lib/components/permissions/PermissionMetricsDisplay.svelte'
    
    export let data
</script>

<div class="permission-dashboard">
    <h1>Permission Management</h1>
    
    <section class="real-time-monitoring">
        <h2>Real-time Permission Updates</h2>
        <AdvancedPermissionMonitor orgId={data.orgId} />
    </section>
    
    <section class="metrics">
        <h2>Permission Metrics</h2>
        <PermissionMetricsDisplay metrics={data.metrics} />
    </section>
</div>

+page.svelte
These components and use cases demonstrate:

Real-time permission monitoring
Performance metrics visualization
Context-aware permission checks
Interactive dashboards
Data-driven decision making
Would you like to explore more complex use cases or see how to implement additional interactive features?

Try again with different context
Add context...
Avatar for alankeown-uhbjv
Alan Keown
Can you show me how to 'Set up audit logging'?

Claude 3.5 Sonnet (New)
Here's how to set up comprehensive audit logging for your permission system:

-- Create detailed audit log table
CREATE TABLE community_orgs.audit_logs (
    log_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    timestamp timestamptz DEFAULT CURRENT_TIMESTAMP,
    user_id uuid REFERENCES auth.users(id),
    org_id integer REFERENCES community_orgs.organisations(org_id),
    action text NOT NULL,
    resource_type text NOT NULL,
    resource_id text NOT NULL,
    changes jsonb,
    context jsonb,
    ip_address inet,
    user_agent text,
    success boolean,
    error_message text
);

-- Create audit logging function
CREATE OR REPLACE FUNCTION community_orgs.log_audit_event()
RETURNS trigger AS $$
BEGIN
    INSERT INTO community_orgs.audit_logs (
        user_id,
        org_id,
        action,
        resource_type,
        resource_id,
        changes,
        context
    ) VALUES (
        auth.uid(),
        NEW.org_id,
        TG_OP,
        TG_TABLE_NAME,
        NEW.org_id::text,
        jsonb_build_object(
            'old_value', row_to_json(OLD),
            'new_value', row_to_json(NEW)
        ),
        current_setting('app.context', true)::jsonb
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

07_audit_logging.sql
export class AuditLogger {
    constructor(private supabase: SupabaseClient) {}

    async logEvent({
        action,
        resourceType,
        resourceId,
        changes,
        context,
        success = true,
        errorMessage = null
    }: AuditEvent) {
        const { data, error } = await this.supabase
            .from('audit_logs')
            .insert({
                action,
                resource_type: resourceType,
                resource_id: resourceId,
                changes,
                context: {
                    ...context,
                    ip_address: context.ip,
                    user_agent: context.userAgent
                },
                success,
                error_message: errorMessage
            })

        return { data, error }
    }

    async getAuditTrail(filters: AuditFilters) {
        const query = this.supabase
            .from('audit_logs')
            .select('*')
            
        if (filters.orgId) {
            query.eq('org_id', filters.orgId)
        }
        
        if (filters.dateRange) {
            query.gte('timestamp', filters.dateRange.start)
                .lte('timestamp', filters.dateRange.end)
        }

        return query
    }
}

AuditLogger.ts
import { AuditLogger } from '$lib/server/AuditLogger'

export const handle = async ({ event, resolve }) => {
    // Set context for audit logging
    const requestContext = {
        ip: event.getClientAddress(),
        userAgent: event.request.headers.get('user-agent'),
        path: event.url.pathname,
        method: event.request.method
    }

    event.locals.auditLogger = new AuditLogger(event.locals.supabase)
    event.locals.requestContext = requestContext

    return resolve(event)
}

hooks.server.ts
Usage in routes:

export async function PUT({ params, request, locals }) {
    const updates = await request.json()
    
    try {
        const { data, error } = await locals.supabase
            .from('organisations')
            .update(updates)
            .eq('org_id', params.id)
            .single()

        if (error) throw error

        await locals.auditLogger.logEvent({
            action: 'UPDATE',
            resourceType: 'organisation',
            resourceId: params.id,
            changes: {
                before: data,
                after: updates
            },
            context: locals.requestContext
        })

        return json(data)
    } catch (error) {
        await locals.auditLogger.logEvent({
            action: 'UPDATE',
            resourceType: 'organisation',
            resourceId: params.id,
            success: false,
            errorMessage: error.message,
            context: locals.requestContext
        })

        throw error
    }
}

+server.ts
This audit logging system provides:

Detailed event tracking
User action history
Change tracking
Error logging
Context preservation
Would you like to see how to create audit log visualizations or explore more advanced audit logging patterns?

Try again with different context
Add context...
Avatar for alankeown-uhbjv
Alan Keown
I would you like to see how to create audit log visualizations and explore more advanced audit logging patterns

Claude 3.5 Sonnet (New)
Here are powerful audit log visualizations and advanced patterns:

<script lang="ts">
    import { DataTable } from '$lib/components/table'
    import { TimelineView } from '$lib/components/timeline'
    import type { AuditLog } from '$lib/types/audit'
    
    export let logs: AuditLog[]
    
    let viewMode: 'table' | 'timeline' = 'table'
    
    const columns = [
        { key: 'timestamp', title: 'Time', sortable: true },
        { key: 'user_id', title: 'User' },
        { key: 'action', title: 'Action' },
        { key: 'resource_type', title: 'Resource' },
        { key: 'success', title: 'Status' }
    ]
</script>

<div class="audit-viewer">
    <div class="view-controls">
        <button 
            class:active={viewMode === 'table'} 
            on:click={() => viewMode = 'table'}
        >
            Table View
        </button>
        <button 
            class:active={viewMode === 'timeline'} 
            on:click={() => viewMode = 'timeline'}
        >
            Timeline View
        </button>
    </div>

    {#if viewMode === 'table'}
        <DataTable {columns} data={logs} />
    {:else}
        <TimelineView 
            events={logs}
            groupBy="resource_type"
        />
    {/if}
</div>

AuditLogViewer.svelte
<script lang="ts">
    import { PieChart, BarChart } from '$lib/components/charts'
    import type { AuditMetrics } from '$lib/types/audit'
    
    export let metrics: AuditMetrics
    
    $: actionDistribution = transformActionMetrics(metrics.actions)
    $: userActivity = transformUserMetrics(metrics.users)
</script>

<div class="audit-metrics">
    <div class="chart-container">
        <h3>Actions Distribution</h3>
        <PieChart
            data={actionDistribution}
            labelKey="action"
            valueKey="count"
        />
    </div>
    
    <div class="chart-container">
        <h3>User Activity</h3>
        <BarChart
            data={userActivity}
            xAxis="user"
            yAxis="actions"
            series={['success', 'failure']}
        />
    </div>
</div>

AuditMetrics.svelte
Advanced Audit Patterns:

export class AdvancedAuditLogger {
    constructor(private supabase: SupabaseClient) {}

    async logWithDiff(before: any, after: any, context: AuditContext) {
        const diff = this.generateDiff(before, after)
        
        await this.supabase.from('audit_logs').insert({
            ...context,
            changes: diff,
            severity: this.calculateSeverity(diff),
            risk_score: this.calculateRiskScore(context, diff)
        })
    }

    async getAnomalies(timeframe: string) {
        const { data } = await this.supabase.rpc('detect_audit_anomalies', {
            p_timeframe: timeframe
        })
        return data
    }

    async generateComplianceReport(orgId: number) {
        const { data } = await this.supabase.rpc('generate_compliance_report', {
            p_org_id: orgId
        })
        return data
    }
}

AdvancedAuditLogger.ts
Usage in a dashboard:

<script lang="ts">
    import AuditLogViewer from '$lib/components/audit/AuditLogViewer.svelte'
    import AuditMetrics from '$lib/components/audit/AuditMetrics.svelte'
    import { onMount } from 'svelte'
    
    export let data

    let selectedTimeframe = '7d'
    let anomalies = []
    
    onMount(async () => {
        anomalies = await loadAnomalies(selectedTimeframe)
    })
</script>

<div class="audit-dashboard">
    <header class="dashboard-header">
        <h1>Audit Dashboard</h1>
        <div class="timeframe-selector">
            <select bind:value={selectedTimeframe}>
                <option value="24h">Last 24 Hours</option>
                <option value="7d">Last 7 Days</option>
                <option value="30d">Last 30 Days</option>
            </select>
        </div>
    </header>

    <div class="dashboard-grid">
        <AuditMetrics metrics={data.metrics} />
        
        <div class="anomalies-panel">
            <h2>Detected Anomalies</h2>
            {#each anomalies as anomaly}
                <div class="anomaly-card" class:high-risk={anomaly.risk_score > 0.8}>
                    <h3>{anomaly.type}</h3>
                    <p>{anomaly.description}</p>
                    <span class="risk-score">Risk: {anomaly.risk_score}</span>
                </div>
            {/each}
        </div>

        <AuditLogViewer logs={data.logs} />
    </div>
</div>

+page.svelte
These implementations provide:

Interactive audit log visualization
Real-time metrics tracking
Anomaly detection
Risk scoring
Compliance reporting
Multiple view options
Advanced filtering capabilities
Would you like to explore specific security patterns or see how to implement real-time alerting for audit events?

Try again with different context
Add context...
Avatar for alankeown-uhbjv
Alan Keown
I would like to explore more advanced UI patterns in the context of interactive permission features.

Claude 3.5 Sonnet (New)
Here are powerful advanced UI patterns for interactive permission features:

<script lang="ts">
    import { FlowEditor } from '$lib/components/flow'
    import type { PermissionFlow } from '$lib/types/permissions'
    
    export let initialFlow: PermissionFlow
    
    const nodeTypes = {
        role: RoleNode,
        condition: ConditionNode,
        action: ActionNode,
        decision: DecisionNode
    }
    
    function handleFlowUpdate(flow: PermissionFlow) {
        dispatch('update', { flow })
    }
</script>

<div class="flow-builder">
    <FlowEditor
        nodes={initialFlow.nodes}
        edges={initialFlow.edges}
        {nodeTypes}
        onUpdate={handleFlowUpdate}
    >
        <div slot="toolbar" class="flow-toolbar">
            <button on:click={() => addNode('role')}>Add Role</button>
            <button on:click={() => addNode('condition')}>Add Condition</button>
            <button on:click={() => addNode('action')}>Add Action</button>
        </div>
    </FlowEditor>
</div>

PermissionFlowBuilder.svelte
<script lang="ts">
    import { QueryBuilder } from '$lib/components/query'
    import type { PermissionRule } from '$lib/types/permissions'
    
    export let rules: PermissionRule[]
    
    const operators = {
        equals: 'Equals',
        contains: 'Contains',
        greaterThan: 'Greater Than',
        lessThan: 'Less Than',
        in: 'In List'
    }
    
    function handleRuleChange(rule: PermissionRule) {
        dispatch('ruleChange', { rule })
    }
</script>

<div class="rule-builder">
    <QueryBuilder
        {rules}
        {operators}
        onChange={handleRuleChange}
    >
        <div slot="preview" let:query>
            <pre>{JSON.stringify(query, null, 2)}</pre>
        </div>
    </QueryBuilder>
</div>

DynamicRuleBuilder.svelte
<script lang="ts">
    import PermissionFlowBuilder from '$lib/components/permissions/PermissionFlowBuilder.svelte'
    import DynamicRuleBuilder from '$lib/components/permissions/DynamicRuleBuilder.svelte'
    import { PermissionSimulator } from '$lib/components/permissions/PermissionSimulator.svelte'
    
    let currentFlow = {
        nodes: [],
        edges: []
    }
    
    let rules = []
    
    async function handleFlowSave() {
        const result = await savePermissionFlow({
            flow: currentFlow,
            rules
        })
        
        if (result.success) {
            notify.success('Permission flow saved successfully')
        }
    }
</script>

<div class="permission-builder">
    <header class="builder-header">
        <h1>Permission Flow Builder</h1>
        <div class="actions">
            <button on:click={handleFlowSave}>Save Flow</button>
            <button on:click={() => PermissionSimulator.show(currentFlow)}>
                Test Flow
            </button>
        </div>
    </header>

    <div class="builder-grid">
        <section class="flow-section">
            <h2>Visual Flow</h2>
            <PermissionFlowBuilder
                initialFlow={currentFlow}
                on:update={({ detail }) => currentFlow = detail.flow}
            />
        </section>

        <section class="rules-section">
            <h2>Dynamic Rules</h2>
            <DynamicRuleBuilder
                {rules}
                on:ruleChange={({ detail }) => rules = detail.rules}
            />
        </section>
    </div>
</div>

<style>
    .permission-builder {
        display: flex;
        flex-direction: column;
        gap: 2rem;
        padding: 2rem;
    }

    .builder-grid {
        display: grid;
        grid-template-columns: 2fr 1fr;
        gap: 2rem;
    }

    .builder-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
    }

    .actions {
        display: flex;
        gap: 1rem;
    }
</style>

+page.svelte
These patterns provide:

Visual flow building for permissions
Dynamic rule creation
Real-time preview
Interactive testing
Drag-and-drop interface
Complex condition building
Immediate feedback
Would you like to see how to implement the backend logic for these UI patterns or explore more advanced interaction patterns?

Try again with different context
Add context...
Avatar for alankeown-uhbjv
Alan Keown
I would you like to see how to implement the backend logic for these UI patterns

Claude 3.5 Sonnet (New)
Here's the powerful backend logic implementation for the UI patterns:

export class PermissionFlowEngine {
    constructor(private supabase: SupabaseClient) {}

    async saveFlow(flow: PermissionFlow) {
        const { nodes, edges, rules } = flow
        
        // Transaction to save entire flow atomically
        const { data, error } = await this.supabase.rpc('save_permission_flow', {
            p_nodes: nodes,
            p_edges: edges,
            p_rules: rules,
            p_version: new Date().toISOString()
        })

        return { data, error }
    }

    async evaluateFlow(flowId: string, context: EvaluationContext) {
        const flow = await this.loadFlow(flowId)
        const result = await this.executeFlow(flow, context)
        
        await this.logEvaluation({
            flowId,
            context,
            result,
            timestamp: new Date()
        })

        return result
    }

    private async executeFlow(flow: PermissionFlow, context: EvaluationContext) {
        const executor = new FlowExecutor(flow)
        return executor.execute(context)
    }
}

FlowEngine.ts
export class DynamicRuleEngine {
    async evaluateRules(rules: PermissionRule[], context: RuleContext) {
        const results = await Promise.all(
            rules.map(rule => this.evaluateRule(rule, context))
        )
        
        return this.aggregateResults(results)
    }

    private async evaluateRule(rule: PermissionRule, context: RuleContext) {
        const evaluator = this.getEvaluator(rule.type)
        return evaluator.evaluate(rule, context)
    }

    private getEvaluator(type: string): RuleEvaluator {
        const evaluators = {
            condition: new ConditionEvaluator(),
            temporal: new TemporalEvaluator(),
            spatial: new SpatialEvaluator(),
            resource: new ResourceEvaluator()
        }
        
        return evaluators[type]
    }
}

RuleEngine.ts
-- Function to save permission flows
CREATE OR REPLACE FUNCTION community_orgs.save_permission_flow(
    p_nodes jsonb,
    p_edges jsonb,
    p_rules jsonb,
    p_version timestamp
) RETURNS jsonb AS $$
DECLARE
    flow_id uuid;
BEGIN
    -- Create new flow version
    INSERT INTO community_orgs.permission_flows (
        nodes,
        edges,
        rules,
        version,
        status
    ) VALUES (
        p_nodes,
        p_edges,
        p_rules,
        p_version,
        'draft'
    )
    RETURNING id INTO flow_id;

    -- Return the created flow
    RETURN jsonb_build_object(
        'id', flow_id,
        'status', 'draft',
        'version', p_version
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to evaluate permission flows
CREATE OR REPLACE FUNCTION community_orgs.evaluate_permission_flow(
    p_flow_id uuid,
    p_context jsonb
) RETURNS jsonb AS $$
DECLARE
    result jsonb;
BEGIN
    -- Execute flow evaluation
    WITH flow_execution AS (
        SELECT 
            nodes,
            edges,
            rules
        FROM community_orgs.permission_flows
        WHERE id = p_flow_id
    ),
    evaluation AS (
        SELECT 
            community_orgs.evaluate_nodes(nodes, p_context) as node_results,
            community_orgs.evaluate_rules(rules, p_context) as rule_results
        FROM flow_execution
    )
    SELECT jsonb_build_object(
        'allowed', 
        (node_results->>'result')::boolean AND (rule_results->>'result')::boolean,
        'reason',
        COALESCE(node_results->>'reason', rule_results->>'reason', 'Unknown')
    )
    INTO result
    FROM evaluation;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

08_flow_engine.sql
Usage in API endpoints:

import { FlowEngine } from '$lib/server/FlowEngine'
import { RuleEngine } from '$lib/server/RuleEngine'

export async function POST({ request, locals: { supabase } }) {
    const flowEngine = new FlowEngine(supabase)
    const ruleEngine = new RuleEngine()
    
    const { flow, context } = await request.json()
    
    const [flowResult, ruleResult] = await Promise.all([
        flowEngine.evaluateFlow(flow.id, context),
        ruleEngine.evaluateRules(flow.rules, context)
    ])
    
    return json({
        allowed: flowResult.allowed && ruleResult.allowed,
        reasons: [...flowResult.reasons, ...ruleResult.reasons]
    })
}

+server.ts
These implementations provide:

Flow persistence and versioning
Dynamic rule evaluation
Context-aware processing
Transaction safety
Evaluation logging
Multiple evaluator types
Extensible architecture


Here's the refactored PL/pgSQL to implement ABAC claims instead of role-based claims:

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
    claims jsonb;
    user_attributes jsonb;
    effective_permissions jsonb;
begin
    -- Fetch the user's ABAC attributes
    select 
        jsonb_build_object(
            'attributes', attributes,
            'clearance_level', clearance_level,
            'context', context
        ) into user_attributes 
    from community_orgs.subject_attributes 
    where subject_id = (event->>'user_id')::uuid;

    -- Calculate effective permissions
    select jsonb_agg(
        jsonb_build_object(
            'resource', resource_type,
            'action', action_conditions->>'operation',
            'conditions', resource_conditions
        )
    ) into effective_permissions
    from community_orgs.access_policies
    where subject_conditions <@ user_attributes;

    claims := event->'claims';
    
    -- Set ABAC claims
    if user_attributes is not null then
        claims := jsonb_set(
            claims,
            '{abac}',
            jsonb_build_object(
                'attributes', user_attributes,
                'permissions', effective_permissions,
                'version', '1.0'
            )
        );
    else
        claims := jsonb_set(claims, '{abac}', 'null');
    end if;

    return jsonb_set(event, '{claims}', claims);
end;
$$;

grant usage on schema community_orgs to supabase_auth_admin;

grant execute on function public.custom_access_token_hook to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook from authenticated, anon, public;

grant select on community_orgs.subject_attributes to supabase_auth_admin;
grant select on community_orgs.access_policies to supabase_auth_admin;

revoke all on community_orgs.subject_attributes from authenticated, anon, public;
revoke all on community_orgs.access_policies from authenticated, anon, public;

create policy "Allow auth admin to read subject attributes" 
on community_orgs.subject_attributes
as permissive for select
to supabase_auth_admin
using (true);

create policy "Allow auth admin to read access policies" 
on community_orgs.access_policies
as permissive for select
to supabase_auth_admin
using (true);

This implementation:

Fetches ABAC attributes for the user
Calculates effective permissions based on policies
Adds them to the JWT claims
Properly secures access to ABAC tables
Maintains necessary permissions for auth hooks
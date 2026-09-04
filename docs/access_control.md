```sql
    -- Create organization owners table
    CREATE TABLE community_orgs.org_owners (
        org_id INTEGER REFERENCES community_orgs.organizations(org_id),
        user_id UUID REFERENCES auth.users(id),
        assigned_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
        assigned_by UUID REFERENCES auth.users(id),
        PRIMARY KEY (org_id, user_id)
    );

    -- Create role definitions table
    CREATE TABLE community_orgs.role_definitions (
        role_id SERIAL PRIMARY KEY,
        org_id INTEGER REFERENCES community_orgs.organizations(org_id),
        role_name VARCHAR(100),
        description TEXT,
        permissions JSONB,
        created_by UUID REFERENCES auth.users(id),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
    );

    -- Create organization access table with role references
    CREATE TABLE community_orgs.org_access (
        org_id INTEGER REFERENCES community_orgs.organizations(org_id),
        user_id UUID REFERENCES auth.users(id),
        role_id INTEGER REFERENCES community_orgs.role_definitions(role_id),
        granted_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
        granted_by UUID REFERENCES auth.users(id),
        PRIMARY KEY (org_id, user_id)
    );

    -- RLS policies for owners
    CREATE POLICY owners_full_access ON community_orgs.organizations
        FOR ALL
        TO authenticated
        USING (
            EXISTS (
                SELECT 1 FROM community_orgs.org_owners
                WHERE org_id = organizations.org_id
                AND user_id = auth.uid()
            )
        );

    -- Allow owners to manage access
    CREATE POLICY owners_manage_access ON community_orgs.org_access
        FOR ALL
        TO authenticated
        USING (
            EXISTS (
                SELECT 1 FROM community_orgs.org_owners
                WHERE org_id = org_access.org_id
                AND user_id = auth.uid()
            )
        );

    -- Role-based access policy
    CREATE POLICY role_based_access ON community_orgs.organizations
        FOR ALL
        TO authenticated
        USING (
            EXISTS (
                SELECT 1
                FROM community_orgs.org_access oa
                JOIN community_orgs.role_definitions rd
                ON oa.role_id = rd.role_id
                WHERE oa.org_id = organizations.org_id
                AND oa.user_id = auth.uid()
                AND rd.permissions->>'organizations'->>'read' = 'true'
            )
        );

    -- Create indexes for performance
    CREATE INDEX idx_org_owners_user ON community_orgs.org_owners(user_id);
    CREATE INDEX idx_org_access_user ON community_orgs.org_access(user_id);
    CREATE INDEX idx_role_definitions_org ON community_orgs.role_definitions(org_id);
```

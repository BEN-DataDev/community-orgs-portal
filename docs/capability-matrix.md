# P06 capability matrix

Version: 1.0. Completed: 17 September 2026.

This defines the pilot access contract for [P07/P08](implementation-plan.md)
using the [P05 journeys](core-journeys.md). It preserves existing organisation
roles and the separate platform capabilities. The implementation notes below
refer to repository code and migrations; they are not a fresh verification of
hosted policies. P06 is a documentation milestone.

## Actors and scope

| Actor | Authority | Source of authority |
| --- | --- | --- |
| Public reader | Published organisation data only | Signed out or Supabase anonymous guest session |
| Registered reader | Public records and registered-user reads permitted by table policy; own account and own role requests | Registered account; no organisation assignment required |
| Organisation member | Read permitted records within the assigned organisation | Active, unexpired `user_organisation_roles` assignment; level 1 |
| Organisation moderator | Member access; existing moderation permission retained | Organisation assignment; level 2; no general organisation editing authority |
| Organisation admin | Edit records and manage assignments within the assigned organisation | Organisation assignment; level 3 and seeded `can_manage_members` permission |
| Organisation owner | Organisation admin access with level 4 assignment authority | Organisation assignment; level 4 |
| Ingestion operator | Global acquisition/review/publication work through bounded RPCs | Private `ingestion.operators` appointment |
| Platform administrator | Global administration, effective organisation owner access, and ingestion capabilities | Private `platform_access.administrators` appointment |

The [P07 verification record](scoped-operator-access.md) documents the expired-role
RLS correction and the independent creator read policy for base organisation rows.

Organisation scope is the exact `org_id` UUID, not a name, ABN, relationship,
parent organisation or service area. Membership does not propagate to related
organisations. Inactive or expired assignments confer no authority. Multiple
assignments combine their applicable permissions; the highest active level
sets the hierarchy ceiling. Platform appointments are independent of that
hierarchy. A person may hold both an organisation role and an operator appointment.

## Capability matrix

**Own org** means an active assignment for the target organisation. **Global**
means platform-wide scope, still subject to the action's data and session gates.
**No** means this role alone grants no such capability. All registered actors
retain registered-reader access. Moderator follows member in this table.

| Capability | Public | Member | Org admin | Org owner | Operator | Platform admin |
| --- | --- | --- | --- | --- | --- | --- |
| Read public organisation pages and approved register facts/attribution | Yes | Yes | Yes | Yes | Yes | Yes |
| Read private organisation pages and permitted child records | No | Own org | Own org | Own org | No; review candidates only | Global |
| Correct organisation facts through existing edit forms | No | No | Own org | Own org | No | Global |
| Create an organisation through the registered-user submission flow | No | Yes | Yes | Yes | Yes | Yes |
| Read own role assignments/requests | No | Self | Self | Self | Self | Self |
| List all assignments, requests and role audit records for an organisation | No | No | Own org | Own org | No | Global |
| Grant/revoke existing organisation roles through authorised RPCs | No | No | Own org, ceiling 3 | Own org, ceiling 4 | No | Global, ceiling 4 |
| Review an organisation role request | No | No | Own org | Own org | No | Global |
| Open Admin task hub | No | No | No | No | Yes | Yes |
| Inspect private import evidence, runs, matching candidates and review history | No | No | No | No | Global | Global |
| Queue an acquisition with approved configuration; inspect jobs/failures | No | No | No | No | Global | Global |
| Link/create/defer/reject a source-record proposal | No | No | No | No | Global | Global |
| Approve selected eligible fields and explicitly publish saved approval | No | No | No | No | Global | Global |
| Suppress an imported field or withdraw a linked organisation through review | No | No | No | No | Global | Global |
| Enable/pause sources and inspect source approval history | No | No | No | No | No | Global |
| Configure acquisition scope/licence and refresh schedule | No | No | No | No | No | Global |
| Use other platform admin tasks, including role definitions and reserved slugs | No | No | No | No | No | Global |
| Appoint/revoke operators or platform administrators through the application | No | No | No | No | No | No |
| Directly write staging, approval, publication or appointment tables from a browser | No | No | No | No | No | No |

The creation row is a registered-account capability, also available to a registered
reader without assignments. The normal creation trigger grants its creator an
owner assignment. Imported publication explicitly avoids that grant; publishing
never turns an operator into an organisation owner.

Public visibility is not blanket access to every child table. Contact, financial,
legal, document, governance, membership and access-management records retain their
specific policies. Registered readers can read some sensitive child records of
public organisations under current policy without becoming members; access records
remain self/manager scoped. Approved public register facts use a narrow public RPC
and public projections. Raw evidence, internal identities, review notes, actor IDs
and suppression reasons are excluded from that public surface.

An operator's matching RPC can disclose candidate details for private organisations
across the portal. This is intentional review access and requires a trusted global
appointment; it does not grant unrestricted private-page access or ordinary editing.
Platform administrators currently receive effective owner access on all existing
organisations and inherit operator capability, without requiring either assignment.

## Session, assignment and action rules

1. Privileged actions require a registered account. A guest's `authenticated`
   database role does not make it a registered user. Identity comes from the
   verified session and `auth.uid()`, never a submitted actor ID.
2. Current MFA enforcement is conditional: if the actor has a verified factor,
   the session must be `aal2`. An enrolled actor with AAL1 or missing assurance
   fails the privileged checks. An account without a verified factor can currently
   act at AAL1. Mandatory enrolment for all operators/admins would be a separate
   policy change, not an existing guarantee.
3. Role requests are for the caller only and confer nothing until approved.
   Granting requires `can_manage_members` on the requested organisation and a
   target role no higher than the actor. Revoking also compares the target user's
   maximum active level: an admin cannot revoke even a lower assignment from a
   user who currently ranks as owner. Actors cannot forge the audit identity.
4. [P08](organisation-role-management.md) implements role-management RPCs with
   current scope and MFA checks, blocks self-revocation and requires another
   non-expiring owner before revoking an active owner. New owner grants cannot
   expire. These safeguards are deployed and verified through hosted SQL and
   signed-in production checks. Request/review UI and custom role builders remain
   separate from the minimum assignment workflow.
5. Operator authority does not bypass complete/enabled-source requirements,
   selected-field approval, target revision checks, manual-edit protection,
   projection visibility or suppression. A source enablement/configuration change
   does not itself publish. The pilot permits one operator to approve and publish;
   there is no implemented two-person approval requirement.
6. A review rejection holds a source record; suppression blocks restoration of a
   fact; withdrawal hides the organisation. Ordinary editing/visibility changes
   must not be described as durable import suppression. Hard deletion is outside
   this pilot removal workflow. The seeded owner's `can_delete_organisation` flag
   alone is not evidence of a working deletion route or RLS policy.
7. Platform appointments are controlled deployment operations. Neither organisation
   role RPCs nor platform-admin status permits browser writes to appointment tables.
   Record the authorising operator, target account, scope, reason and time for each
   grant/revocation in deployment evidence. Current tables are not a complete audit
   trail: administrators store a reason and grant time; operators store grant time;
   deletion does not retain revocation history. An application appointment workflow
   would require separate audited implementation.

## Enforcement and implementation evidence

Navigation is a convenience. Every protected read/action must independently check
its capability on the server and in RLS or an authorised database RPC. RPC errors
must fail closed. Browser handlers use the caller's client, not a service-role key.

| Boundary | Repository evidence | Follow-up |
| --- | --- | --- |
| Organisation levels and editor gate | [Role levels](../src/lib/role-levels.ts), [server authorization](../src/lib/server/authorization.ts), [RLS helpers](../supabase/migrations/20260904114029_rls_helpers_and_owner_grant.sql) | P07/P08 verify level checks agree with permission JSON and deployed role definitions |
| Separate platform administration | [Platform migration](../supabase/migrations/20260916015048_platform_administrators.sql), [request guard](../src/hooks.server.ts) | P07 verify global tasks cannot be entered with organisation authority alone |
| Separate operator and candidate access | [Review migration](../supabase/migrations/20260916020406_ingestion_review.sql), [review actions](../src/routes/admin/ingestion/+page.server.ts) | P07 exercise both route and direct-RPC denial paths |
| Role actor, hierarchy and MFA checks | [Role RPC migration](../supabase/migrations/20260914071835_fix_p1_sensitive_reads_and_role_rpc_mfa.sql), [assignment reads](../supabase/migrations/20260904111936_fix_user_organisation_roles_policy_recursion.sql), [request reads](../supabase/migrations/20260905033915_role_requests_read_policies.sql) | P08 build minimum assignment UI and validate actor/target scope |
| Public facts and private review separation | [Public facts RPC](../supabase/migrations/20260916090000_public_register_facts.sql), [journey removal contract](core-journeys.md) | Preserve allowlisting, visibility and suppression gates |
| Source and job authority | [Source approval migration](../supabase/migrations/20260916060046_source_approval.sql), [acquisition RPCs](../supabase/migrations/20260917030000_acquisition_jobs.sql) | Preserve operator queue versus administrator configuration split |

The acquisition worker is a separate machine identity. Its restricted database login
assumes `ingestion_worker` and executes granted lease/checkpoint/staging RPCs; it
cannot approve, publish, appoint users or configure sources. Cron uses a protected
server endpoint and its granted scheduling/maintenance functions. Neither identity
is an interactive platform administrator. See [worker deployment](acquisition-jobs.md).

## P07/P08 acceptance scenarios

Use synthetic actors and two organisations in a disposable database. Existing
[platform tests](../supabase/tests/platform_administrators.sql),
[access regressions](../supabase/tests/p1_access_regression.sql) and
[review tests](../supabase/tests/ingestion_review.sql) are starting evidence;
this documentation change does not rerun or certify their coverage.

| Scenario | Required result |
| --- | --- |
| Signed-out reader and anonymous guest | Public approved facts readable; private evidence, role records and all mutations denied |
| Registered reader without assignments | Registered reads/self-request allowed; private organisation and global controls denied |
| Member/moderator in A, no assignment in B | Permitted private reads in A; no editing or management in either organisation |
| Admin in A, no assignment in B | Edit/manage A within ceiling; deny edit/manage B and all ingestion/global admin actions |
| Owner in A | Grant existing roles through owner level in A; no platform appointment or ingestion authority |
| Expired/revoked assignment, including mixed active assignments | Ignore invalid assignments; retain only independently valid authority |
| Operator without organisation membership | Review/queue/publish eligible data; private candidates available only through review; source configuration and ordinary editing denied |
| Platform administrator without memberships | Effective global owner and ingestion access; browser appointment-table writes still denied |
| Enrolled actor at AAL1, AAL2 and missing AAL; unenrolled actor at AAL1 | Conditional MFA enforced by direct RPC/table access as well as application routes |
| Forged actor/org/role IDs; admin targeting an owner; direct role-table writes | Reject unauthorised change; audit successful RPC actions with actual caller |
| Approved publication followed by stale replay or manual edit | No duplicate publication, silent overwrite or creator-owner grant |
| Appointment revoked while user retains a session | Next protected operation loses that appointment's authority; independent roles still apply |

P06 is complete when this matrix and its boundaries are recorded. [P07 implementation and hosted verification](scoped-operator-access.md) records
that deployed boundary; P08 owns minimum organisation role management.
Broader ABAC, custom permission hierarchies and appointment-management UI remain
deferred. Historical examples in [roles](roles.md), [access control](access_control.md)
and [ABAC](ABAC.md) are reference proposals, not this pilot's access contract.

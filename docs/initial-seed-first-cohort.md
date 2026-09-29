# Initial-seed first cohort — superseded

Decision date: 29 September 2026

Status: superseded, excluded and retained only as immutable audit evidence. Nothing
from this campaign was published.

## Original frozen boundary

- Campaign: `f3856dbc-8ec1-4c87-87f5-dd487e78e22f`
- ABR registry-seed release: 2
- Derived ACNC run: 34
- NSW registered-only release: 3
- Selection version: `initial-seed-first-cohort-v1`
- Cohort manifest: [initial-seed-first-cohort.json](initial-seed-first-cohort.json)
- Manifest SHA-256: `fb6e5c09c65acc730f7a45824e21427bed0384969ff89afb712509d34656664e`
- Server selection SHA-256: `3fe204141684e903e8da477db729177d00e87a26782db233a54010dc720ec2a1`

## Why it was superseded

The 20 candidates were sampled using the broad 23-postcode acquisition geometry.
The portal owner subsequently confirmed that none was within the intended
locality/service scope. A discovery postcode had been mistaken for local-relevance
evidence. Exact cross-source identity, entity type, name similarity and a DGR
source flag do not answer whether an organisation operates in or serves Snowy
Valleys.

The Data Steward therefore revised all 20 cohort triage decisions to `exclude` at
revision 2. The original revision-1 decisions and both immutable events per
candidate remain in the audit trail.

## Derived private work

Ten candidates had entered non-publication-eligible, non-snapshot private run 35.
Their identity decisions were revised from `create` to `reject` at revision 2. This
made all ten associated revision-1 field change sets stale. Run 35 has zero
publications, and no publication release was created for the campaign.

The hosted readiness function now blocks this campaign with
`campaign_superseded`. Replacement campaign
`1079eb35-e8e0-46a4-8583-1af77f3d23ce` uses the
[confirmed-local v2 cohort](initial-seed-local-cohort-v2.md).

# Pilot inclusion policy

Version: 1.0. Effective: 17 September 2026. Implements P01.

This policy defines which candidates operators may include in the initial portal
pilot. It is an operator review policy; automated geographic classification and
additional source adapters are separate implementation work.

## Geographic scope

The pilot covers the **Snowy Valleys local government area, NSW**. Include an
organisation or community group if evidence establishes either:

- **Located in:** it has a physical operating location within that LGA.
- **Serves area:** it delivers a named service or recurring community activity
  within that LGA, even if its headquarters are elsewhere.

An address or service location must be checked against an authoritative council
or government locality/boundary source where LGA membership is uncertain. Record
the evidence URL or retained source reference and the date checked. Do not infer
service coverage from a postal address, national registration, or generic claims
to serve all of Australia.

Neighbouring LGAs are not included merely because they are nearby. Organisations
there qualify only through evidenced service delivery within Snowy Valleys.
Widening the target area requires a versioned policy change and a separate review
of acquisition scope.

The existing ACNC postcode **2730** query is a bounded discovery sample, not the
pilot boundary or proof of eligibility. Other postcodes within the LGA may qualify;
neither this policy nor completion of P01 changes deployed acquisition settings.

The [Snowy Valleys postcode discovery scope](snowy-valleys-postcode-scope.md)
records 13 Postal Areas that overlap the LGA and 10 that directly touch its
boundary. These 23 postcodes define a broader candidate-search cohort only.
Records found through an adjacent postcode remain outside the pilot unless there
is evidence that the organisation serves Snowy Valleys.

## Community purpose and categories

Candidates must have an identifiable community purpose in at least one category:

| Category | Included activities |
| --- | --- |
| Sport and recreation | Community clubs, participation and recreation groups |
| Arts, culture and heritage | Community arts, cultural groups and historical societies |
| Environment | Landcare, conservation and community gardens |
| Neighbourhood and community centres | Local centres, resident and progress associations |
| Welfare and community support | Food relief, transport, family support and disaster assistance |
| Health and wellbeing | Community health, peer support and hospital auxiliaries |
| Education and learning | Community education, early childhood and learning groups |
| Service clubs and volunteering | Service clubs, volunteer groups and community fundraising |
| Faith and religious community | Congregations and religious groups with local community activity |
| Other community purpose | An operator documents the purpose and why existing categories do not fit |

Multiple categories are allowed. Preserve source categories alongside the review
mapping. Charity registration, an ABN or incorporation alone does not establish
local relevance. Unincorporated groups and groups without ABNs are eligible.
Council-operated community services are eligible; a commercial sponsor or supplier
does not qualify solely because it funds or sells to a community organisation.

## Entity, group, service and location distinctions

| Concept | Treatment |
| --- | --- |
| Legal entity | Record the registered organisation and its supported identifiers. |
| Community group or branch | Keep its local identity distinct from its parent; a shared ABN does not prove two groups are the same. |
| Service or program | Associate it with the delivering organisation; do not create a second legal entity from a service name. |
| Location or venue | Treat it as a place associated with an organisation or service, not automatically as another organisation. |

Match against existing source links and supported identifiers before proposing a
new organisation. Name similarity is a review signal, not permission to merge.
Where the current schema cannot represent a branch or service accurately, retain
the candidate privately with the unresolved mapping noted rather than flattening
it into a duplicate organisation. P11 owns the schema/matching implementation.

## Evidence and review decisions

Use enabled, qualified sources whose recorded terms permit the intended use.
Each candidate review must record the policy version, source/native identifier
(where available), evidence reference and observation date, geographic basis,
community category, entity/group/service classification, and decision with reason.
Use existing review notes for these details until structured fields are available.
Unverified examples in `Content.md` are research leads, not inclusion evidence.

| Decision | Rule |
| --- | --- |
| Include | Identity, community purpose and geographic relevance are supported, source use is approved, and matching is resolved. Proceed through normal field approval/publication. |
| Hold for review | Evidence is missing, ambiguous or contradictory; source permissions, activity status or entity mapping remain unresolved. Keep private. |
| Exclude | Evidence establishes that the candidate is outside scope or belongs to an excluded class. Record the reason. |

Exclude individual people, standalone events, directory category pages, venues
without an identified operating group, and ordinary commercial businesses without
a qualifying community purpose. Do not create new active listings for confirmed
closed or dissolved organisations. An amalgamation or changed registration needs
identity review; do not automatically merge it into a successor.

Missing from a refresh does not establish closure. Preserve existing publication,
manual-edit and suppression controls; source reappearance does not override a
withdrawal. Applying this policy to an existing listing requires review, not bulk
deletion or automatic unpublication.

## Pilot cohort and completion

Aim for **50–100 reviewed organisation/group records**, including existing records
and new candidates across several categories. Include test cases with no ABN,
possible duplicates, a branch/shared identifier, and an external provider with
evidenced local service delivery. Held and excluded candidates are retained as
review evidence, not counted as published coverage. The six-record ACNC sample
does not by itself meet this broader cohort target.

Operators must apply the same criteria to every source. Source administrators
qualify access and reuse separately; source approval does not approve a candidate
or publish its fields. Record future scope changes with a new policy version and
reason before expanding acquisition. P01 is complete as a written policy; cohort
recruitment, source qualification and enforcement remain their own plan tasks.

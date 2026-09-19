# Snowy Valleys postcode discovery scope

Generated: 19 September 2026. Geography vintage: ABS ASGS 2021.

This is the postcode cohort for discovering organisations located within or near
the Snowy Valleys local government area (LGA). It is an acquisition aid, not an
eligibility boundary: every candidate still requires review under the
[pilot inclusion policy](pilot-inclusion-policy.md).

## Postcode cohort

The 23-postcode discovery cohort is:

`2582, 2611, 2620, 2624, 2627, 2628, 2629, 2640, 2642, 2644, 2649, 2650, 2652, 2653, 2720, 2722, 2727, 2729, 2730, 3707, 3708, 3709, 3900`

| Relationship to Snowy Valleys LGA                                     | Postcodes                                                                                              | Count |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ----: |
| Postal Area overlaps the LGA                                          | `2611`, `2627`, `2629`, `2640`, `2642`, `2649`, `2652`, `2653`, `2720`, `2722`, `2729`, `2730`, `3707` |    13 |
| Postal Area touches the LGA boundary without overlapping its interior | `2582`, `2620`, `2624`, `2628`, `2644`, `2650`, `2727`, `3708`, `3709`, `3900`                         |    10 |

The overlap group includes Postal Areas that only partly lie in Snowy Valleys.
The adjacent group includes any boundary contact represented by the source
geometry, including point contact. Cross-border Postal Areas are retained.

## Method

The list is the result of comparing the ABS ASGS 2021 Snowy Valleys LGA polygon
(`LGA_CODE_2021 = 17080`) with ASGS 2021 Postal Area polygons:

1. Select Postal Areas whose geometry intersects the LGA geometry.
2. Classify `esriSpatialRelTouches` results as adjacent.
3. Classify the remaining intersecting results as overlapping the LGA interior.
4. Sort and de-duplicate the four-digit codes as strings.

Sources:

- [ABS Local Government Areas](https://www.abs.gov.au/statistics/standards/australian-statistical-geography-standard-asgs-edition-3/jul2021-jun2026/non-abs-structures/local-government-areas)
- [ABS Postal Areas](https://www.abs.gov.au/statistics/standards/australian-statistical-geography-standard-asgs/edition-3-july-2021-june-2026/non-abs-structures/postal-areas)
- [ABS ASGS 2021 LGA spatial service](https://geo.abs.gov.au/arcgis/rest/services/ASGS2021/LGA/MapServer/0)
- [ABS ASGS 2021 Postal Area spatial service](https://geo.abs.gov.au/arcgis/rest/services/ASGS2021/POA/MapServer/0)

ABS Postal Areas are statistical approximations of postcodes, and ABS LGA
boundaries approximate gazetted boundaries. Recalculate this list when either
geography vintage changes; do not manually infer additions from locality names.

## Review rule

A postcode match only places a record in the private review queue. For an
overlapping postcode, confirm that the organisation's actual operating location
is inside Snowy Valleys or that it serves the LGA. For an adjacent postcode,
require evidence of service delivery or recurring community activity within
Snowy Valleys. A registered, postal or administrative address alone is not proof
of either condition.

The application configuration, worker and bulk fallback support this bounded
postcode list. The multi-postcode migration, portal and worker image were deployed
on 19 September 2026. Hosted configuration revision 3 contains all 23 postcodes,
retains the 720-hour schedule and remains due at `2026-10-19T03:18:23Z`. Run a
fresh bounded acquisition and capacity review before publishing the expanded
cohort.

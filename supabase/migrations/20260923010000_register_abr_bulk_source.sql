-- Register the real ABR bulk dataset as a disabled private registry-seed source.
-- A platform administrator must review this metadata and explicitly enable the
-- source before ingestion.stage_registry_seed will accept a release.
insert into ingestion.sources(source_id,resource_id,metadata,enabled)
values (
 'abr-bulk',
 '5bd7fcab-e315-42cb-8daf-50b7efc2027e',
 $metadata${
  "public_title":"ABN Lookup bulk extract",
  "public_url":"https://abr.business.gov.au/Tools/BulkExtract",
  "public_licence":"Creative Commons Attribution 3.0 Australia",
  "public_licence_url":"https://creativecommons.org/licenses/by/3.0/au/",
  "publisher":"Australian Business Register",
  "dataset_url":"https://data.gov.au/data/dataset/5bd7fcab-e315-42cb-8daf-50b7efc2027e",
  "resource_list_url":"https://data.gov.au/data/dataset/5bd7fcab-e315-42cb-8daf-50b7efc2027e/resource/469c8c2c-0be5-45b2-90d7-c42f637f3323/download/abn-bulk-extract-resources.csv",
  "part_resource_ids":[
   "0ae4d427-6fa8-4d40-8e76-c6909b5a071b",
   "635fcb95-7864-4509-9fa7-a62a6e32b62d"
  ],
  "expected_member_count":20,
  "cadence":"weekly",
  "scope":{
   "snapshot_series":"abr-weekly-snowy-valleys",
   "postcodes":["2582","2611","2620","2624","2627","2628","2629","2640","2642","2644","2649","2650","2652","2653","2720","2722","2727","2729","2730","3707","3708","3709","3900"]
  },
  "approval_reference":"P33-WS-2026-09-23",
  "registration_status":"disabled_pending_platform_admin_review"
 }$metadata$::jsonb,
 false
);

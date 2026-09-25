-- Phase 7: register the public NSW incorporated-associations search as a disabled
-- private seed source. Enabling requires recorded access/reuse approval and a
-- separately qualified bounded acquisition; this migration performs no scraping.
insert into ingestion.sources(source_id, resource_id, metadata, enabled)
values (
  'nsw-incorporated-associations',
  'public-register-search',
  $metadata${
    "public_title": "NSW Incorporated Associations Register",
    "public_url": "https://applications.fairtrading.nsw.gov.au/assocregister/",
    "publisher": "NSW Fair Trading",
    "public_fields": ["name", "incorporation number", "incorporation date", "registration status"],
    "access_mode": "ordinary unauthenticated postcode search",
    "jurisdiction": "AU-NSW",
    "native_identity": "incorporation number",
    "cadence": "manual until recurring-operation approval",
    "approval_reference": null,
    "registration_status": "disabled_pending_access_reuse_and_live_markup_qualification"
  }$metadata$::jsonb,
  false
);

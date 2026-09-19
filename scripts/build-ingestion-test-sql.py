"""Emit an isolated PostgreSQL test setup and rollback-only ingestion suites.

Output is intended for an empty disposable database, never a deployed database.
No database connection or network request is made by this script.
"""
from pathlib import Path
import runpy
import sys

root = Path(__file__).resolve().parents[1]
package = root / 'tools/ingestion/python'
sys.path.insert(0, str(package))
print((root / 'supabase/tests/support/ingestion_bootstrap.sql').read_text())
for name in [
    '20260916020403_private_ingestion_staging.sql',
    '20260916020406_ingestion_review.sql',
    '20260916020408_ingestion_field_preview.sql',
    '20260916020409_ingestion_publication.sql',
    '20260916034216_attribution_and_suppression.sql',
    '20260916060046_source_approval.sql',
    '20260916070000_acnc_register_details.sql',
    '20260916080000_complete_field_publication.sql',
    '20260916090000_public_register_facts.sql',
    '20260917010000_acnc_reprocessing.sql',
    '20260917020000_acnc_website_normalisation.sql',
    '20260917030000_acquisition_jobs.sql',
    '20260917071152_private_raw_retention.sql',
    '20260919010000_multi_postcode_acquisition.sql',
]:
    print((root / 'supabase/migrations' / name).read_text())
print((root / 'supabase/tests/support/ingestion_post_migration.sql').read_text())
runpy.run_path(str(package / 'tests/emit_complete_fixture.py'))
runpy.run_path(str(package / 'tests/emit_reprocessing_fixture.py'))
for name in ['ingestion_staging.sql', 'ingestion_review.sql', 'ingestion_field_preview.sql',
             'ingestion_publication.sql', 'ingestion_complete_fields.sql', 'acnc_register_details.sql', 'public_register_facts.sql', 'acnc_reprocessing.sql', 'acnc_website_normalisation.sql', 'acquisition_jobs.sql', 'private_raw_retention.sql']:
    print((root / 'supabase/tests' / name).read_text())

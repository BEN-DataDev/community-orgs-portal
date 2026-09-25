import copy
import unittest

from ingestion.adapters.nsw_associations import NSWAssociationsExtractor, form_fields, parse_page
from ingestion.live_nsw_associations import acquire, configuration


def page(records=(), next_target=None, *, result_style=""):
    rows = []
    for record in records:
        rows.append(f"""
        <div class="row">
          <div class="col-md-10">
            <a href="PublicRegisterDetails.aspx?Organisationid={record['id']}">{record['name']}</a>
            <div class="row text-secondary">
              <div>Organisation Number: {record['number']}</div>
              <div>Organisation Type: ASSOCIATION</div>
              <div>Date Registered: 23/06/1988</div>
              <div>Registered Office Address: EXAMPLE NSW {record['postcode']}</div>
            </div>
          </div>
          <div class="col-md-2"><figcaption><span>REGISTERED</span></figcaption></div>
        </div>""")
    next_link = (
        f"<a id='ctl00_MainArea_PageNextLink' "
        f"href=\"javascript:__doPostBack('{next_target}','')\">Next</a>"
        if next_target else
        "<a id='ctl00_MainArea_PageNextLink' style='display:none' "
        "href=\"javascript:__doPostBack('next','')\">Next</a>"
    )
    return f"""<!doctype html><html><body><form id="aspnetForm">
      <input type="hidden" name="__VIEWSTATE" value="state">
      <input type="hidden" name="__EVENTVALIDATION" value="validation">
      <div id="ctl00_MainArea_SearchResultDiv" style="{result_style}">
        <span id="ctl00_MainArea_ResultDataList">{''.join(rows)}</span>{next_link}
      </div></form></body></html>"""


ONE = {"id": "101", "name": "SNOWY EXAMPLE INC", "number": "Y0123456", "postcode": "2730"}
TWO = {"id": "102", "name": "SECOND EXAMPLE INC", "number": "INC2100276", "postcode": "2720"}


class NSWAssociationTests(unittest.TestCase):
    def test_form_and_result_contract(self):
        html = page([ONE], "ctl00$MainArea$PageNextLink")
        self.assertEqual(form_fields(html)["__VIEWSTATE"], "state")
        rows, target = parse_page(html)
        self.assertEqual(rows[0]["organisation_number"], "Y0123456")
        self.assertEqual(rows[0]["registered_office_address"], "EXAMPLE NSW 2730")
        self.assertEqual(target, "ctl00$MainArea$PageNextLink")

    def test_complete_pagination_uses_scoped_identity_and_no_name_merge(self):
        pages = iter([page([ONE], "next"), page([TWO])])
        extractor = NSWAssociationsExtractor(lambda _: next(pages), lambda _: next(pages))
        inventory, candidates, errors, complete = extractor.extract(
            postcodes=["2720", "2730"], release_id="fixture-1",
            observed_at="2026-09-25T00:00:00Z")
        self.assertTrue(complete)
        self.assertEqual(errors, [])
        self.assertEqual([p["record_count"] for p in inventory], [1, 1])
        self.assertEqual([c["native_id"] for c in candidates],
                         ["AU-NSW:Y0123456", "AU-NSW:INC2100276"])
        self.assertNotIn("name", candidates[0]["selection"])

    def test_markup_change_duplicate_and_page_budget_fail_closed(self):
        broken = page([ONE]).replace("ctl00_MainArea_ResultDataList", "changed")
        with self.assertRaisesRegex(ValueError, "result"):
            parse_page(broken)
        pages = iter([page([ONE], "next"), page([ONE])])
        result = NSWAssociationsExtractor(lambda _: next(pages), lambda _: next(pages)).extract(
            postcodes=["2730"], release_id="fixture", observed_at="2026-09-25T00:00:00Z")
        self.assertFalse(result[3])
        self.assertIn("duplicate", result[2][0]["message"])
        limited = NSWAssociationsExtractor(
            lambda _: page([ONE], "next"), lambda _: page([TWO], "next"), max_pages=1
        )
        inventory, _, errors, complete = limited.extract(
            postcodes=["2730"], release_id="fixture", observed_at="2026-09-25T00:00:00Z")
        self.assertFalse(complete)
        self.assertEqual(inventory[-1]["status"], "failed")
        self.assertIn("budget", errors[-1]["message"])

    def test_landing_page_is_not_an_empty_snapshot(self):
        with self.assertRaisesRegex(ValueError, "not a completed"):
            parse_page(page([], result_style="display: none;"))

    def test_live_orchestration_emits_registry_seed_contract(self):
        config = configuration({
            "config_version": "nsw-associations-live-v1", "enabled": False,
            "approved_access_reuse": True, "source_id": "nsw-incorporated-associations",
            "resource_id": "public-register-search", "postcodes": ["2730"],
            "approval_reference": "synthetic-test", "portal_scope_revision_id": "1",
            "snapshot_series": "nsw-synthetic", "attribution": "Synthetic fixture",
            "user_agent": "CommunityOrgsTest/1.0 (mailto:test@example.invalid)",
            "max_pages_per_postcode": 2, "timeout_seconds": 5, "deadline_seconds": 30,
            "delay_seconds": 2, "max_response_bytes": 100000,
            "retention": {"class": "hold", "basis": "Synthetic test"},
        })

        class FakeTransport:
            def __init__(self, _):
                self.requests = 1
            def initial(self, _):
                return page([ONE])
            def next(self, _):
                raise AssertionError("no next page")

        manifest, candidates = acquire(config, FakeTransport, release_id="fixture-release",
                                       observed_at="2026-09-25T00:00:00Z")
        self.assertEqual(manifest["completion"], "complete")
        self.assertTrue(manifest["scope"]["complete_snapshot"])
        self.assertEqual(manifest["scope"]["portal_scope_revision_id"], "1")
        self.assertEqual(len(candidates), 1)

    def test_configuration_keeps_live_source_disabled_and_approved(self):
        base = {
            "config_version": "nsw-associations-live-v1", "enabled": False,
            "approved_access_reuse": False, "source_id": "nsw-incorporated-associations",
            "resource_id": "public-register-search", "postcodes": ["2730"],
            "approval_reference": "pending", "portal_scope_revision_id": "1",
            "snapshot_series": "nsw", "attribution": "NSW Fair Trading",
            "user_agent": "CommunityOrgs/1.0 (mailto:operator@example.invalid)",
            "max_pages_per_postcode": 2, "timeout_seconds": 5, "deadline_seconds": 30,
            "delay_seconds": 2, "max_response_bytes": 100000,
            "retention": {"class": "hold", "basis": "Review pending"},
        }
        self.assertFalse(configuration(base)["approved_access_reuse"])
        bad = copy.deepcopy(base)
        bad["postcodes"] = ["２７３０"]
        with self.assertRaises(ValueError):
            configuration(bad)


if __name__ == "__main__":
    unittest.main()

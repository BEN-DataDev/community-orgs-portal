import copy
import unittest
from datetime import datetime
from urllib.request import Request

from ingestion.adapters.nsw_associations import NSWAssociationsExtractor, form_fields, parse_page
from ingestion.live_nsw_associations import (
    RESULTS_URL,
    RegisterRedirect,
    acquire,
    configuration,
    require_enablement,
    resume_acquire,
)


def page(records=(), next_target=None, *, result_style=""):
    rows = []
    for record in records:
        rows.append(f"""
        <div class="row">
          <div class="col-md-10">
            <div class="row text-secondary">
              <div class="col-md-12 font-weight-bold">
                <a href="PublicRegisterDetails.aspx?Organisationid={record['id']}">
                  {record['name']}
                </a>
              </div>
              <div class="col-md-8">{record['number']}<span>Organisation Number:</span></div>
              <div class="col-md-4">{record.get('date', '3/06/1988')}<span>Date Registered:</span></div>
              <div class="col-md-8">INCORPORATED ASSOCIATION<span>Organisation Type:</span></div>
              <div class="col-md-8">EXAMPLE NSW {record['postcode']}
                <span>Registered Office Address:</span>
              </div>
            </div>
          </div>
          <div class="col-md-2"><figcaption><span>{record.get('status', 'REGISTERED')}</span></figcaption></div>
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


ONE = {"id": "101", "name": "SNOWY EXAMPLE INC", "number": "Y0123456",
       "postcode": "2730", "date": "3/06/1988"}
TWO = {"id": "102", "name": "SECOND EXAMPLE INC", "number": "INC2100276",
       "postcode": "2720", "date": "4/06/1988"}
REGISTERED_QUERY = {"postcode": "2730", "status": "REGISTERED"}
ALL_STATUSES = [
    "AMALG", "CANCELLED", "LIQUIDATIN", "REGISTERED", "TRANSFER", "ADMNSTRATN"
]


class NSWAssociationTests(unittest.TestCase):
    def test_only_qualified_post_results_redirect_is_allowed(self):
        handler = RegisterRedirect()
        request = Request("https://applications.fairtrading.nsw.gov.au/assocregister/", data=b"x=1")
        redirected = handler.redirect_request(request, None, 302, "Found", {}, RESULTS_URL)
        self.assertEqual(redirected.full_url, RESULTS_URL)
        self.assertEqual(redirected.get_method(), "GET")
        with self.assertRaisesRegex(ValueError, "redirect refused"):
            handler.redirect_request(request, None, 302, "Found", {}, "https://example.invalid/")
        with self.assertRaisesRegex(ValueError, "redirect refused"):
            handler.redirect_request(Request(RESULTS_URL), None, 302, "Found", {}, RESULTS_URL)

    def test_form_and_result_contract(self):
        html = page([ONE], "ctl00$MainArea$PageNextLink")
        self.assertEqual(form_fields(html)["__VIEWSTATE"], "state")
        rows, target = parse_page(html)
        self.assertEqual(rows[0]["organisation_number"], "Y0123456")
        self.assertEqual(rows[0]["registered_office_address"], "EXAMPLE NSW 2730")
        self.assertEqual(target, "ctl00$MainArea$PageNextLink")

    def test_qualified_top_and_bottom_next_controls_are_equivalent(self):
        html = page([ONE], "ctl00$MainArea$PageNextLink").replace(
            "</form>",
            "<a id='ctl00_MainArea_PageNextBottomLink' "
            "href=\"javascript:__doPostBack('ctl00$MainArea$PageNextBottomLink','')\">"
            "Next</a></form>",
        )
        _, target = parse_page(html)
        self.assertEqual(target, "ctl00$MainArea$PageNextLink")
        changed = html.replace(
            "ctl00$MainArea$PageNextBottomLink','')", "ctl00$MainArea$Unexpected','')"
        )
        with self.assertRaisesRegex(ValueError, "target changed"):
            parse_page(changed)

    def test_complete_pagination_uses_scoped_identity_and_no_name_merge(self):
        pages = iter([page([ONE], "ctl00$MainArea$PageNextLink"), page([TWO])])
        extractor = NSWAssociationsExtractor(lambda _: next(pages), lambda _: next(pages))
        inventory, candidates, errors, complete = extractor.extract(
            query=REGISTERED_QUERY, postcodes=["2720", "2730"], release_id="fixture-1",
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
        pages = iter([page([ONE], "ctl00$MainArea$PageNextLink"), page([ONE])])
        result = NSWAssociationsExtractor(lambda _: next(pages), lambda _: next(pages)).extract(
            query=REGISTERED_QUERY, postcodes=["2730"], release_id="fixture",
            observed_at="2026-09-25T00:00:00Z")
        self.assertFalse(result[3])
        self.assertIn("duplicate", result[2][0]["message"])
        limited = NSWAssociationsExtractor(
            lambda _: page([ONE], "ctl00$MainArea$PageNextLink"),
            lambda _: page([TWO], "ctl00$MainArea$PageNextLink"), max_pages=1
        )
        inventory, _, errors, complete = limited.extract(
            query=REGISTERED_QUERY, postcodes=["2730"], release_id="fixture",
            observed_at="2026-09-25T00:00:00Z")
        self.assertFalse(complete)
        self.assertEqual(inventory[-1]["status"], "failed")
        self.assertIn("budget", errors[-1]["message"])

    def test_landing_page_is_not_an_empty_snapshot(self):
        with self.assertRaisesRegex(ValueError, "not a completed"):
            parse_page(page([], result_style="display: none;"))

    def test_qualified_visible_refine_state_is_an_empty_result(self):
        html = page([]).replace(
            '<span id="ctl00_MainArea_ResultDataList"></span>',
            '<fieldset id="ctl00_MainArea_RefineSearchSection"></fieldset>',
        )
        rows, target = parse_page(html)
        self.assertEqual(rows, [])
        self.assertIsNone(target)
        changed = page([], "ctl00$MainArea$PageNextLink").replace(
            '<span id="ctl00_MainArea_ResultDataList"></span>',
            '<fieldset id="ctl00_MainArea_RefineSearchSection"></fieldset>',
        )
        with self.assertRaisesRegex(ValueError, "empty result state"):
            parse_page(changed)

    def test_live_orchestration_emits_registry_seed_contract(self):
        config = configuration({
            "config_version": "nsw-associations-live-v1", "enabled": False,
            "approved_access_reuse": True, "source_id": "nsw-incorporated-associations",
            "resource_id": "public-register-search", "postcodes": ["2730"],
            "statuses": ["REGISTERED"],
            "approval_reference": "synthetic-test", "portal_scope_revision_id": "1",
            "snapshot_series": "nsw-synthetic", "attribution": "Synthetic fixture",
            "user_agent": "CommunityOrgsTest/1.0 (mailto:test@community.example.org)",
            "max_pages_per_postcode": 2, "timeout_seconds": 5, "deadline_seconds": 30,
            "delay_seconds": 2, "max_response_bytes": 100000, "provider_result_cap": 200,
            "retention": {"class": "hold", "basis": "Synthetic test"},
        })

        class FakeTransport:
            def __init__(self, _):
                self.requests = 1
            def initial(self, query):
                return page([ONE] if query["status"] == "REGISTERED" else [])
            def next(self, _):
                raise AssertionError("no next page")

        manifest, candidates = acquire(config, FakeTransport, release_id="fixture-release",
                                       observed_at="2026-09-25T00:00:00Z",
                                       sleep=lambda _: None)
        self.assertEqual(manifest["completion"], "complete")
        self.assertTrue(manifest["scope"]["complete_snapshot"])
        self.assertEqual(manifest["scope"]["portal_scope_revision_id"], "1")
        self.assertEqual(manifest["scope"]["selection"]["statuses"], ["REGISTERED"])
        self.assertEqual(len(manifest["parts"]), 1)
        self.assertEqual(len(candidates), 1)

    def test_configuration_accepts_finite_large_postcode_page_budget(self):
        raw = {
            "config_version": "nsw-associations-live-v1", "enabled": False,
            "approved_access_reuse": False, "source_id": "nsw-incorporated-associations",
            "resource_id": "public-register-search", "postcodes": ["2730"],
            "statuses": ["REGISTERED"],
            "approval_reference": "pending", "portal_scope_revision_id": "1",
            "snapshot_series": "nsw", "attribution": "NSW Fair Trading",
            "user_agent": "CommunityOrgs/1.0 (+https://example.org/project)",
            "max_pages_per_postcode": 100, "timeout_seconds": 5, "deadline_seconds": 30,
            "delay_seconds": 2, "max_response_bytes": 100000, "provider_result_cap": 200,
            "retention": {"class": "hold", "basis": "Review pending"},
        }
        self.assertEqual(configuration(raw)["max_pages_per_postcode"], 100)
        invalid = copy.deepcopy(raw)
        invalid["statuses"] = ["REGISTERED", "CANCELLED"]
        with self.assertRaisesRegex(ValueError, "statuses"):
            configuration(invalid)
        invalid["statuses"] = []
        with self.assertRaisesRegex(ValueError, "statuses"):
            configuration(invalid)
        raw["max_pages_per_postcode"] = 101
        with self.assertRaisesRegex(ValueError, "max_pages_per_postcode"):
            configuration(raw)

    def test_provider_result_cap_is_completed_with_date_partitions(self):
        config = {
            "postcodes": ["2730"], "statuses": ["REGISTERED"],
            "max_pages_per_postcode": 2,
            "timeout_seconds": 5, "deadline_seconds": 30, "delay_seconds": 2,
            "max_response_bytes": 100000, "provider_result_cap": 2,
            "user_agent": "CommunityOrgsTest/1.0", "snapshot_series": "nsw",
            "portal_scope_revision_id": "1",
            "retention": {"class": "hold", "basis": "Synthetic test"},
            "attribution": "Synthetic", "approval_reference": "synthetic-test",
        }

        class FakeTransport:
            def __init__(self, _):
                self.requests = 2
            def initial(self, query):
                if query["status"] != "REGISTERED":
                    return page([])
                if not query.get("date_from"):
                    return page([ONE, TWO])
                start = datetime.strptime(query["date_from"], "%d/%m/%Y").date()
                end = datetime.strptime(query["date_to"], "%d/%m/%Y").date()
                records = [record for record in (ONE, TWO)
                           if start <= datetime.strptime(record["date"], "%d/%m/%Y").date() <= end]
                return page(records)
            def next(self, _):
                raise AssertionError("no next page")

        manifest, candidates = acquire(config, FakeTransport, release_id="cap-test",
                                       observed_at="2026-09-27T00:00:00Z",
                                       sleep=lambda _: None)
        self.assertEqual(len(candidates), 2)
        self.assertEqual(manifest["completion"], "complete")
        self.assertTrue(manifest["scope"]["complete_snapshot"])
        self.assertGreater(len(manifest["source"]["partition_splits"]), 0)
        self.assertTrue(all(part["record_count"] < 2 for part in manifest["parts"]))

    def test_missing_date_is_allowed_uncapped_but_blocks_date_partitioning(self):
        no_date = {**ONE, "date": "-"}
        config = {
            "postcodes": ["2730"], "statuses": ["REGISTERED"],
            "max_pages_per_postcode": 2,
            "timeout_seconds": 5, "deadline_seconds": 30, "delay_seconds": 2,
            "max_response_bytes": 100000, "provider_result_cap": 2,
            "user_agent": "CommunityOrgsTest/1.0", "snapshot_series": "nsw",
            "portal_scope_revision_id": "1",
            "retention": {"class": "hold", "basis": "Synthetic test"},
            "attribution": "Synthetic", "approval_reference": "synthetic-test",
        }

        class FakeTransport:
            def __init__(self, _):
                self.requests = 1
            def initial(self, query):
                if query["status"] != "REGISTERED":
                    return page([])
                return page([no_date, TWO])
            def next(self, _):
                raise AssertionError("no next page")

        manifest, _ = acquire(config, FakeTransport, release_id="missing-date-cap",
                              observed_at="2026-09-27T00:00:00Z", sleep=lambda _: None)
        self.assertEqual(manifest["completion"], "partial")
        self.assertIn("without a registration date", manifest["errors"][0]["message"])

        config["provider_result_cap"] = 3
        manifest, candidates = acquire(config, FakeTransport, release_id="missing-date-ok",
                                       observed_at="2026-09-27T00:00:00Z",
                                       sleep=lambda _: None)
        self.assertEqual(manifest["completion"], "complete")
        self.assertEqual(len(candidates), 2)

    def test_resume_reuses_only_wholly_complete_postcode_prefix(self):
        config = {
            "postcodes": ["2720", "2730"], "statuses": ALL_STATUSES,
            "max_pages_per_postcode": 2,
            "timeout_seconds": 5, "deadline_seconds": 30, "delay_seconds": 2,
            "max_response_bytes": 100000, "provider_result_cap": 200,
            "user_agent": "CommunityOrgsTest/1.0",
            "snapshot_series": "nsw", "portal_scope_revision_id": "1",
            "retention": {"class": "hold", "basis": "Synthetic test"},
            "attribution": "Synthetic", "approval_reference": "synthetic-test",
        }
        prior_manifest = {
            "contract_version": "registry-seed-v1", "source_id": "nsw-incorporated-associations",
            "resource_id": "public-register-search", "release_id": "resume-test",
            "parser_version": "nsw-associations-html-v2",
            "observed_at": "2026-09-27T00:00:00Z", "completion": "partial",
            "scope": {"selection": {"postcodes": ["2720", "2730"],
                                     "statuses": ALL_STATUSES,
                                     "query_plan_version":
                                     "incorporated-association-status-date-v1"}},
            "parts": [
                *[
                    {"part_id": f"postcode-2720-status-{status}-page-1", "ordinal": index,
                     "status": "complete", "record_count": 1 if status == "REGISTERED" else 0,
                     "detail": {"postcode": "2720", "status": status, "next": False}}
                    for index, status in enumerate(
                        ("AMALG", "CANCELLED", "LIQUIDATIN", "REGISTERED", "TRANSFER",
                         "ADMNSTRATN"), 1)
                ],
                {"part_id": "postcode-2730-status-AMALG-page-1", "ordinal": 7,
                 "status": "complete", "record_count": 0,
                 "detail": {"postcode": "2730", "status": "AMALG", "next": False,
                            "date_from": None, "date_to": None}},
                {"part_id": "postcode-2730-status-CANCELLED-page-1", "ordinal": 8,
                 "status": "failed",
                 "detail": {"postcode": "2730", "status": "CANCELLED",
                            "message": "timeout", "date_from": None, "date_to": None}},
            ],
            "source": {"http_requests": 4},
        }
        kept = {"native_id": "AU-NSW:KEPT"}
        discarded = {"native_id": "AU-NSW:DISCARDED"}

        class FakeTransport:
            def __init__(self, _):
                self.requests = 2
            def initial(self, query):
                return page([ONE] if query["status"] == "REGISTERED" else [])
            def next(self, _):
                raise AssertionError("no next page")

        mismatched = copy.deepcopy(prior_manifest)
        mismatched["scope"]["selection"]["statuses"] = ["REGISTERED"]
        with self.assertRaisesRegex(ValueError, "does not match"):
            resume_acquire(
                config, mismatched, [kept, discarded], FakeTransport, sleep=lambda _: None
            )
        manifest, candidates = resume_acquire(
            config, prior_manifest, [kept, discarded], FakeTransport, sleep=lambda _: None
        )
        self.assertEqual(manifest["completion"], "complete")
        self.assertTrue(manifest["scope"]["complete_snapshot"])
        self.assertEqual(manifest["scope"]["selection"]["postcodes"], ["2720", "2730"])
        self.assertEqual(candidates[0], kept)
        self.assertNotIn(discarded, candidates)
        self.assertEqual([p["ordinal"] for p in manifest["parts"]], list(range(1, 13)))
        self.assertEqual(manifest["source"]["http_requests"], 14)
        self.assertEqual(manifest["source"]["resume_attempts"], 1)

    def test_resume_queues_failed_date_leaf_and_unvisited_sibling(self):
        config = {
            "postcodes": ["2730"], "statuses": ALL_STATUSES,
            "max_pages_per_postcode": 2,
            "timeout_seconds": 5, "deadline_seconds": 30, "delay_seconds": 2,
            "max_response_bytes": 100000, "provider_result_cap": 200,
            "user_agent": "CommunityOrgsTest/1.0", "snapshot_series": "nsw",
            "portal_scope_revision_id": "1",
            "retention": {"class": "hold", "basis": "Synthetic test"},
            "attribution": "Synthetic", "approval_reference": "synthetic-test",
        }
        root = {"postcode": "2730", "status": "REGISTERED"}
        right = {**root, "date_from": "17/05/1913", "date_to": "27/09/2026"}
        parts = []
        for ordinal, status in enumerate(("AMALG", "CANCELLED", "LIQUIDATIN"), 1):
            parts.append({
                "part_id": f"postcode-2730-status-{status}-page-1", "ordinal": ordinal,
                "status": "complete", "record_count": 0,
                "detail": {"postcode": "2730", "status": status, "date_from": None,
                           "date_to": None, "next": False},
            })
        parts.extend([
            {"part_id": "registered-old-page-1", "ordinal": 4, "status": "complete",
             "record_count": 0, "detail": {"postcode": "2730", "status": "REGISTERED",
             "date_from": "01/01/1800", "date_to": "16/05/1913", "next": False}},
            {"part_id": "registered-failed-page-1", "ordinal": 5, "status": "failed",
             "detail": {"postcode": "2730", "status": "REGISTERED",
             "date_from": "17/05/1913", "date_to": "21/01/1970", "message": "timeout"}},
        ])
        prior_manifest = {
            "contract_version": "registry-seed-v1", "source_id": "nsw-incorporated-associations",
            "resource_id": "public-register-search", "release_id": "leaf-resume",
            "parser_version": "nsw-associations-html-v2",
            "observed_at": "2026-09-27T00:00:00Z", "completion": "partial",
            "scope": {"selection": {"postcodes": ["2730"],
                                     "statuses": ALL_STATUSES,
                                     "query_plan_version":
                                     "incorporated-association-status-date-v1"}},
            "parts": parts,
            "errors": [{"postcode": "2730", "status": "REGISTERED",
                        "date_from": "17/05/1913", "date_to": "21/01/1970",
                        "message": "timeout"}],
            "source": {"http_requests": 9, "partition_splits": [
                {"query": root, "records_observed": 200, "page_hashes": []},
                {"query": right, "records_observed": 200, "page_hashes": []},
            ]},
        }
        calls = []

        class FakeTransport:
            def __init__(self, _):
                self.requests = 1
            def initial(self, query):
                calls.append(query)
                return page([])
            def next(self, _):
                raise AssertionError("no next page")

        manifest, candidates = resume_acquire(
            config, prior_manifest, [], FakeTransport, sleep=lambda _: None
        )
        self.assertEqual(manifest["completion"], "complete")
        self.assertEqual(candidates, [])
        self.assertEqual(
            [(query["status"], query.get("date_from"), query.get("date_to"))
             for query in calls],
            [
                ("REGISTERED", "17/05/1913", "21/01/1970"),
                ("REGISTERED", "22/01/1970", "27/09/2026"),
                ("TRANSFER", None, None),
                ("ADMNSTRATN", None, None),
            ],
        )

    def test_configuration_keeps_live_source_disabled_and_approved(self):
        base = {
            "config_version": "nsw-associations-live-v1", "enabled": False,
            "approved_access_reuse": False, "source_id": "nsw-incorporated-associations",
            "resource_id": "public-register-search", "postcodes": ["2730"],
            "statuses": ["REGISTERED"],
            "approval_reference": "pending", "portal_scope_revision_id": "1",
            "snapshot_series": "nsw", "attribution": "NSW Fair Trading",
            "user_agent": "CommunityOrgs/1.0 (mailto:operator@example.invalid)",
            "max_pages_per_postcode": 2, "timeout_seconds": 5, "deadline_seconds": 30,
            "delay_seconds": 2, "max_response_bytes": 100000, "provider_result_cap": 200,
            "retention": {"class": "hold", "basis": "Review pending"},
        }
        self.assertFalse(configuration(base)["approved_access_reuse"])
        bad = copy.deepcopy(base)
        bad["postcodes"] = ["２７３０"]
        with self.assertRaises(ValueError):
            configuration(bad)

    def test_live_enablement_requires_approval_config_and_explicit_flag(self):
        base = {
            "config_version": "nsw-associations-live-v1", "enabled": False,
            "approved_access_reuse": False, "source_id": "nsw-incorporated-associations",
            "resource_id": "public-register-search", "postcodes": ["2730"],
            "statuses": ["REGISTERED"],
            "approval_reference": "pending", "portal_scope_revision_id": "1",
            "snapshot_series": "nsw", "attribution": "NSW Fair Trading",
            "user_agent": "CommunityOrgs/1.0 (mailto:operator@example.invalid)",
            "max_pages_per_postcode": 2, "timeout_seconds": 5, "deadline_seconds": 30,
            "delay_seconds": 2, "max_response_bytes": 100000, "provider_result_cap": 200,
            "retention": {"class": "hold", "basis": "Review pending"},
        }
        with self.assertRaisesRegex(ValueError, "approval is not recorded"):
            require_enablement(configuration(base), True)
        approved = copy.deepcopy(base)
        approved.update({
            "enabled": True,
            "approved_access_reuse": True,
            "approval_reference": "DCS-APPROVAL-123",
            "user_agent": "CommunityOrgs/1.0 (+https://example.org/community-orgs)",
        })
        config = configuration(approved)
        with self.assertRaisesRegex(ValueError, "explicit --enable"):
            require_enablement(config, False)
        require_enablement(config, True)
        approved["approval_reference"] = "NOT-APPROVED-TECHNICAL-QUALIFICATION"
        with self.assertRaisesRegex(ValueError, "placeholder"):
            configuration(approved)
        approved["approval_reference"] = "DCS-APPROVAL-123"
        approved["user_agent"] = "CommunityOrgs/1.0"
        with self.assertRaisesRegex(ValueError, "stable contact"):
            configuration(approved)


if __name__ == "__main__":
    unittest.main()

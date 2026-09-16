import copy
import json
from pathlib import Path
import unittest

from ingestion.adapters.acnc import ACNCExtractor, digest, normalise

FIXTURE = json.loads((Path(__file__).parent / "fixtures/acnc-pages.json").read_text())


class ACNCTests(unittest.TestCase):
    def run_extract(self, pages=None, max_pages=100):
        self.calls = []
        pages = copy.deepcopy(FIXTURE["pages"] if pages is None else pages)

        def fetch(params):
            self.calls.append(params)
            value = pages[str(params["offset"])]
            if isinstance(value, Exception):
                raise value
            return value

        return ACNCExtractor(fetch, FIXTURE["resource_id"], 1, max_pages).extract(
            filters=FIXTURE["filters"], run_id=FIXTURE["run_id"],
            observed_at=FIXTURE["observed_at"],
        )

    def test_address_lines_survive_null_third_line(self):
        row = FIXTURE["pages"]["0"]["result"]["records"][0]
        address = normalise(row)["assertions"][1]["value"]
        self.assertEqual(address["lines"], ["PO Box 10", "Care of Example Centre"])
        self.assertEqual(address["type"], "Postal")

    def test_all_three_address_lines_and_no_abn(self):
        record = normalise(FIXTURE["pages"]["1"]["result"]["records"][0])
        self.assertEqual(len(record["assertions"][1]["value"]["lines"]), 3)
        self.assertFalse(any(a["field"] == "abn" for a in record["assertions"]))
        self.assertIn("No ABN", record["warnings"][0])

    def test_complete_pagination_and_provenance(self):
        result = self.run_extract()
        self.assertEqual(result["completion"], "complete")
        self.assertEqual([p["offset"] for p in self.calls], [0, 1])
        self.assertEqual(json.loads(self.calls[0]["filters"]), FIXTURE["filters"])
        self.assertEqual(result["records"][0]["raw_sha256"], digest(result["records"][0]["raw"]))
        self.assertFalse(result["publication_eligible"])
        self.assertEqual(result["records"][0]["assertions"][2]["value"], "00000000000")

    def test_postcode_leading_zero(self):
        row = copy.deepcopy(FIXTURE["pages"]["0"]["result"]["records"][0])
        row["Postcode"] = "0800"
        self.assertEqual(normalise(row)["assertions"][1]["value"]["postcode"], "0800")

    def test_numeric_abn_quarantined_not_coerced(self):
        pages = copy.deepcopy(FIXTURE["pages"])
        pages["0"]["result"]["records"][0]["ABN"] = 123
        result = self.run_extract(pages)
        self.assertEqual(result["completion"], "partial")
        self.assertEqual(result["counts"]["quarantined"], 1)

    def test_same_abn_distinct_source_rows_retained(self):
        pages = copy.deepcopy(FIXTURE["pages"])
        pages["1"]["result"]["records"][0]["ABN"] = "00000000000"
        self.assertEqual(len(self.run_extract(pages)["records"]), 2)

    def test_duplicate_source_id_quarantined(self):
        pages = copy.deepcopy(FIXTURE["pages"])
        pages["1"]["result"]["records"][0]["_id"] = 1
        self.assertEqual(self.run_extract(pages)["completion"], "partial")

    def test_empty_success_is_distinct_from_failure(self):
        empty = {"0": {"success": True, "result": {"records": [], "total": 0}}}
        self.assertEqual(self.run_extract(empty)["completion"], "complete")
        self.assertEqual(self.run_extract({"0": OSError("offline failure")})["completion"], "failed")

    def test_later_page_failure_preserves_records_but_not_completion(self):
        pages = copy.deepcopy(FIXTURE["pages"])
        pages["1"] = OSError("interrupted")
        result = self.run_extract(pages)
        self.assertEqual(result["completion"], "partial")
        self.assertEqual(result["counts"]["accepted"], 1)
        self.assertEqual(result["errors"][0]["offset"], 1)

    def test_total_drift_and_truncation(self):
        for replacement in [
            {"success": True, "result": {"records": [], "total": 2}},
            {"success": True, "result": {"records": [], "total": 3}},
        ]:
            with self.subTest(replacement=replacement):
                pages = copy.deepcopy(FIXTURE["pages"])
                pages["1"] = replacement
                self.assertEqual(self.run_extract(pages)["completion"], "partial")

    def test_schema_errors_and_api_errors_fail_closed(self):
        for payload in [{"success": False}, {"success": True, "result": {}}, []]:
            with self.subTest(payload=payload):
                self.assertEqual(self.run_extract({"0": payload})["completion"], "failed")

    def test_page_budget_is_partial(self):
        self.assertEqual(self.run_extract(max_pages=1)["completion"], "partial")

    def test_replay_is_deterministic(self):
        self.assertEqual(self.run_extract(), self.run_extract())

    def test_raw_preserved_and_null_not_asserted(self):
        row = copy.deepcopy(FIXTURE["pages"]["0"]["result"]["records"][0])
        row["Charity_Website"] = None
        original = copy.deepcopy(row)
        self.assertFalse(any(a["field"] == "website" for a in normalise(row)["assertions"]))
        self.assertEqual(row, original)

    def test_scope_and_timestamp_validation(self):
        client = ACNCExtractor(lambda _: self.fail("must not fetch"), "fixture")
        with self.assertRaises(ValueError):
            client.extract(filters={}, run_id="run", observed_at=FIXTURE["observed_at"])
        with self.assertRaises(ValueError):
            client.extract(filters={"State": "NSW"}, run_id="run", observed_at="2026-09-16")


if __name__ == "__main__":
    unittest.main()

import copy
import gzip
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from ingestion import abr_bulk
from ingestion.registry_seed_sql import render

FIXTURE = Path(__file__).parent / "fixtures" / "abr-bulk"


class ABRBulkTests(unittest.TestCase):
    def setUp(self):
        self.config = {
            "config_version": "abr-bulk-local-v1",
            "source_id": "abr-bulk",
            "resource_id": "synthetic-weekly-extract",
            "release_id": "2026-09-21",
            "observed_at": "2026-09-21T02:00:00Z",
            "extract_time": "2026-09-21T00:00:00Z",
            "expected_member_count": 2,
            "publisher": "Australian Business Register",
            "attribution": "Contains synthetic fixture data only",
            "resource_list_url": "https://data.gov.au/data/dataset/abn-bulk-extract",
            "licence": {
                "name": "Creative Commons Attribution 3.0 Australia",
                "url": "https://creativecommons.org/licenses/by/3.0/au/",
            },
            "scope": {
                "snapshot_series": "abr-weekly-snowy-valleys",
                "postcodes": ["2730"],
                "known_abns": ["22000000280"],
            },
            "retention": {"class": "hold", "basis": "Synthetic fixture validation"},
            "parts": [],
        }
        for ordinal, filename in enumerate(["part-1.xml", "part-2.xml"], 1):
            self.config["parts"].append(
                {
                    "part_id": filename,
                    "filename": filename,
                    "ordinal": ordinal,
                    "sha256": hashlib.sha256((FIXTURE / filename).read_bytes()).hexdigest(),
                }
            )

    def test_complete_release_preserves_repeated_values_and_selection(self):
        manifest, candidates = abr_bulk.extract_release(self.config, FIXTURE)
        self.assertEqual(manifest["completion"], "complete")
        self.assertTrue(manifest["scope"]["complete_snapshot"])
        self.assertEqual([part["record_count"] for part in manifest["parts"]], [2, 1])
        self.assertEqual([item["native_id"] for item in candidates], ["51824753556", "22000000280"])
        assertions = {item["field"]: item["value"] for item in candidates[0]["assertions"]}
        self.assertEqual(len(assertions["abr_other_names"]), 2)
        self.assertEqual(len(assertions["abr_dgr"]), 2)
        self.assertEqual(assertions["abr_abn_status"]["from"], "2010-01-02")
        self.assertEqual(assertions["abr_replaced"], "N")
        self.assertEqual(assertions["abr_asic_number_type"], "ACN")
        self.assertEqual(assertions["abr_main_business_location"]["postcode"], "2730")
        self.assertEqual(candidates[1]["selection"]["reasons"], ["explicitly known ABN"])
        self.assertEqual(
            next(
                item for item in candidates[1]["assertions"] if item["field"] == "entity_name"
            )["value"],
            "Dr Casey Example",
        )
        sql = render(manifest, candidates)
        self.assertIn("ingestion.stage_registry_seed", sql)
        self.assertNotIn("Snowy Community Association", sql)

    def test_missing_changed_and_malformed_parts_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "part-1.xml").write_bytes((FIXTURE / "part-1.xml").read_bytes())
            manifest, candidates = abr_bulk.extract_release(self.config, root)
            self.assertEqual(manifest["completion"], "partial")
            self.assertFalse(manifest["scope"]["complete_snapshot"])
            self.assertEqual(manifest["parts"][1]["status"], "failed")
            self.assertEqual(len(candidates), 1)

            (root / "part-2.xml").write_text("<Transfer><ABR>")
            changed = copy.deepcopy(self.config)
            changed["parts"][1]["sha256"] = hashlib.sha256(
                (root / "part-2.xml").read_bytes()
            ).hexdigest()
            manifest, _ = abr_bulk.extract_release(changed, root)
            self.assertEqual(manifest["parts"][1]["status"], "failed")
            self.assertIn("invalid XML", manifest["errors"][0]["message"])

            changed["parts"][1]["sha256"] = "0" * 64
            manifest, _ = abr_bulk.extract_release(changed, root)
            self.assertNotIn("sha256", manifest["parts"][1])
            self.assertIn("observed_sha256", manifest["parts"][1]["detail"])

    def test_zip_gzip_and_checkpoint_reuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checkpoint = root / "checkpoints"
            with zipfile.ZipFile(root / "part-1.zip", "w", zipfile.ZIP_DEFLATED) as archive:
                archive.write(FIXTURE / "part-1.xml", "extract/part-1.xml")
                third = (
                    (FIXTURE / "part-2.xml")
                    .read_text()
                    .replace("<FileSequenceNumber>2", "<FileSequenceNumber>3")
                    .replace("22000000280", "33000000081")
                    .replace("<Postcode>3000", "<Postcode>4000")
                )
                archive.writestr("extract/part-3.xml", third)
            with gzip.open(root / "part-2.xml.gz", "wb") as stream:
                stream.write((FIXTURE / "part-2.xml").read_bytes())
            config = copy.deepcopy(self.config)
            config["expected_member_count"] = 3
            for part, filename in zip(config["parts"], ["part-1.zip", "part-2.xml.gz"]):
                part["filename"] = filename
                part["sha256"] = hashlib.sha256((root / filename).read_bytes()).hexdigest()
            manifest, candidates = abr_bulk.extract_release(config, root, checkpoint)
            self.assertEqual(manifest["completion"], "complete")
            self.assertEqual(len(candidates), 2)
            self.assertEqual(len(manifest["parts"][0]["detail"]["members"]), 2)
            self.assertTrue(
                all(not part["detail"]["checkpoint_reused"] for part in manifest["parts"])
            )
            with mock.patch(
                "ingestion.abr_bulk._parse_stream", side_effect=AssertionError("reparsed")
            ):
                manifest, replay = abr_bulk.extract_release(config, root, checkpoint)
            self.assertEqual(replay, candidates)
            self.assertTrue(all(part["detail"]["checkpoint_reused"] for part in manifest["parts"]))

    def test_duplicate_abn_makes_release_partial_and_is_not_staged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for filename in ["part-1.xml", "part-2.xml"]:
                root.joinpath(filename).write_bytes(FIXTURE.joinpath(filename).read_bytes())
            second = root.joinpath("part-2.xml")
            second.write_text(second.read_text().replace("22000000280", "51824753556"))
            config = copy.deepcopy(self.config)
            config["scope"]["known_abns"] = ["51824753556"]
            config["parts"][1]["sha256"] = hashlib.sha256(second.read_bytes()).hexdigest()
            manifest, candidates = abr_bulk.extract_release(config, root)
            self.assertEqual(manifest["completion"], "partial")
            self.assertEqual(candidates, [])
            self.assertIn("duplicate ABNs", manifest["errors"][0]["message"])

    def test_config_rejects_unbounded_or_ambiguous_inventory(self):
        cases = []
        duplicate = copy.deepcopy(self.config)
        duplicate["parts"][1]["ordinal"] = 1
        cases.append(duplicate)
        traversal = copy.deepcopy(self.config)
        traversal["parts"][0]["filename"] = "../part-1.xml"
        cases.append(traversal)
        invalid_scope = copy.deepcopy(self.config)
        invalid_scope["scope"]["postcodes"] = ["２７３０"]
        cases.append(invalid_scope)
        for config in cases:
            with self.subTest(config=config), self.assertRaises(ValueError):
                abr_bulk.extract_release(config, FIXTURE)

    def test_dtd_is_rejected_without_expansion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xml = (FIXTURE / "part-1.xml").read_text().replace(
                '<Transfer error="">',
                '<!DOCTYPE Transfer [<!ENTITY unsafe "expanded">]><Transfer error="">',
            )
            path = root / "part-1.xml"
            path.write_text(xml)
            config = copy.deepcopy(self.config)
            config["parts"] = [config["parts"][0]]
            config["parts"][0]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            config["expected_member_count"] = 1
            manifest, candidates = abr_bulk.extract_release(config, root)
            self.assertEqual(manifest["completion"], "partial")
            self.assertEqual(candidates, [])
            self.assertIn("DTD", manifest["errors"][0]["message"])

    def test_cli_writes_private_artifacts_and_partial_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config_path = root / "config.json"
            config_path.write_text(json.dumps(self.config))
            output = root / "output"
            command = [
                sys.executable,
                "-m",
                "ingestion.abr_bulk",
                "--config",
                str(config_path),
                "--input-dir",
                str(FIXTURE),
                "--checkpoint-dir",
                str(root / "checkpoints"),
                "--output-dir",
                str(output),
            ]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                json.loads((output / "manifest.json").read_text())["completion"], "complete"
            )
            self.assertEqual((output / "candidates.json").stat().st_mode & 0o777, 0o600)
            replay = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(replay.returncode, 2)


if __name__ == "__main__":
    unittest.main()

import copy
import json
from pathlib import Path
import unittest

from ingestion.staging_sql import render, validate

SAMPLE = json.loads((Path(__file__).parents[1] / "examples/acnc-normalised.json").read_text())


class StagingTests(unittest.TestCase):
    def test_valid_sample_renders_private_transaction(self):
        sql = render(SAMPLE)
        self.assertIn("SET LOCAL ROLE ingestion_worker", sql)
        self.assertIn("ingestion.stage_acnc", sql)
        self.assertNotIn("Synthetic Valley", sql)
        self.assertTrue(sql.endswith("COMMIT;\n"))

    def test_tampering_and_inconsistent_contract_rejected(self):
        mutations = [
            lambda e: e.update(publication_eligible=True),
            lambda e: e["records"][0]["raw"].update(ABN="changed"),
            lambda e: e["records"][0].update(resource_id="other"),
            lambda e: e["records"].append(e["records"][0]),
            lambda e: e["errors"].append({"reason": "incomplete"}),
            lambda e: e["records"][0]["assertions"].append(e["records"][0]["assertions"][0]),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                envelope = copy.deepcopy(SAMPLE)
                mutate(envelope)
                with self.assertRaises(ValueError):
                    validate(envelope)

import json
import tempfile
import unittest
from pathlib import Path

from ingestion.registry_seed_chunked_sql import statements, write


class RegistrySeedChunkedSQLTests(unittest.TestCase):
    def setUp(self):
        self.manifest = {"contract_version": "registry-seed-v1", "completion": "complete"}
        self.candidates = [
            {"native_id": str(index), "raw": {"name": f"Private candidate {index}"}}
            for index in range(5)
        ]

    def test_renders_bounded_resumable_batches_without_plain_source_text(self):
        sql = "".join(statements(self.manifest, self.candidates, 2))
        self.assertEqual(sql.count("append_registry_seed_upload"), 3)
        self.assertIn("begin_registry_seed_upload", sql)
        self.assertIn("finalize_registry_seed_upload", sql)
        self.assertIn("clear_finalized_registry_seed_upload", sql)
        self.assertIn("\\if :p33_finalized", sql)
        self.assertNotIn("Private candidate", sql)

    def test_writes_private_file_once(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "stage-chunked.sql"
            write(output, self.manifest, self.candidates, 2)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                write(output, self.manifest, self.candidates, 2)

    def test_rejects_partial_or_oversized_batch(self):
        partial = json.loads(json.dumps(self.manifest))
        partial["completion"] = "partial"
        with self.assertRaises(ValueError):
            list(statements(partial, self.candidates))
        with self.assertRaises(ValueError):
            list(statements(self.manifest, self.candidates, 501))


if __name__ == "__main__":
    unittest.main()

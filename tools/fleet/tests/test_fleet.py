import json
import tempfile
import unittest
from pathlib import Path

from tools.fleet.control import ControlPlane
from tools.fleet.manifest import ensure_no_inline_secrets, load_manifest
from tools.fleet.provider import CAPABILITIES, FleetProvider, PostgresAdapter


def portal(key="one", suffix="1"):
    return {
        "portal_id": f"10000000-0000-4000-8000-{suffix.zfill(12)}",
        "portal_key": key,
        "display_name": key.title(),
        "short_name": key.title(),
        "sponsor_name": "Test Sponsor",
        "establishment_reason": "Acceptance test",
        "schema_version": "20260925020000",
        "provider": {"adapter": "docker_postgres", "region": "local-test", "container": "unused", "database": key},
        "credentials": {"bootstrap": f"vault:test/{key}/bootstrap@1"},
    }


class ManifestTests(unittest.TestCase):
    def test_rejects_inline_secrets(self):
        with self.assertRaisesRegex(ValueError, "inline secret"):
            ensure_no_inline_secrets({"database_url": "postgres://plaintext"})

    def test_validates_two_isolated_portals(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps({"manifest_version": "fleet-v1", "application_version": "test", "portals": [portal(), portal("two", "2")] }))
            manifest, digest = load_manifest(path)
            self.assertEqual(len(manifest["portals"]), 2)
            self.assertEqual(len(digest), 64)

    def test_provider_capability_contract_is_explicit(self):
        expected = {"postgresql", "verified_identity", "private_storage", "scheduler",
                    "secret_references", "backup_restore", "migrations"}
        self.assertEqual(set(CAPABILITIES), {"supabase_postgres", "docker_postgres"})
        for capabilities in CAPABILITIES.values():
            values = capabilities.as_dict()
            self.assertEqual(set(values), expected)
            self.assertTrue(set(values.values()) <= {"supported", "external", "unsupported"})

    def test_postgres_adapter_satisfies_fleet_provider_protocol_shape(self):
        required = {name for name in FleetProvider.__dict__ if not name.startswith("_")}
        self.assertTrue(required <= set(dir(PostgresAdapter)))


class ControlPlaneTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.control = ControlPlane(Path(self.temp.name) / "control.sqlite3")
        self.one, self.two = portal(), portal("two", "2")
        self.control.sync_manifest("a" * 64, self.one, "test")
        self.control.sync_manifest("a" * 64, self.two, "test")

    def tearDown(self):
        self.control.close()
        self.temp.cleanup()

    def test_operation_only_changes_target_portal(self):
        before = self.control.inventory()[1].copy()
        with self.control.operation(self.one, "provision", "operator@example", "OPS-1") as (op, details):
            details["applied_migrations"] = ["20260925020000"]
            self.control.update_observation(self.one["portal_id"], op, lifecycle="planned",
                                            schema_version="20260925020000",
                                            observed_portal_id=self.one["portal_id"], health="healthy")
        after = self.control.inventory()
        self.assertEqual(after[1], before)
        self.assertEqual(after[0]["health"], "healthy")
        self.assertTrue(self.control.export()["chain_valid"])

    def test_failed_attempt_is_retained_and_history_is_immutable(self):
        with self.assertRaisesRegex(RuntimeError, "provider unavailable"):
            with self.control.operation(self.one, "health", "operator@example", "INC-1"):
                raise RuntimeError("provider unavailable")
        exported = self.control.export()
        self.assertEqual(exported["operations"][0]["result"], "failed")
        with self.assertRaisesRegex(Exception, "append-only"):
            self.control.db.execute("delete from operations")

    def test_rotation_never_stores_a_secret_value(self):
        with self.control.operation(self.one, "rotate_credential", "operator@example", "OPS-2") as (op, details):
            revision = self.control.rotate_ref(self.one["portal_id"], "bootstrap", "vault:test/one/bootstrap@2", op)
            details.update({"secret_ref": "vault:test/one/bootstrap@2", "secret_value_stored": False})
        package = self.control.export()
        self.assertEqual(revision, 1)
        self.assertEqual(package["credential_references"][0]["secret_ref"], "vault:test/one/bootstrap@2")
        self.assertNotIn("password", json.dumps(package).lower())

    def test_failed_rotation_rolls_back_projection_but_retains_attempt(self):
        with self.assertRaisesRegex(RuntimeError, "verification failed"):
            with self.control.operation(self.one, "rotate_credential", "operator@example", "OPS-3") as (op, _):
                self.control.rotate_ref(self.one["portal_id"], "bootstrap", "vault:test/one/bootstrap@2", op)
                raise RuntimeError("verification failed")
        package = self.control.export()
        self.assertEqual(package["credential_references"], [])
        self.assertEqual(package["operations"][0]["result"], "failed")
        self.assertTrue(package["chain_valid"])

    def test_registered_identity_cannot_be_repurposed(self):
        changed = {**self.one, "portal_key": "replacement"}
        with self.assertRaisesRegex(ValueError, "cannot be repurposed"):
            self.control.sync_manifest("b" * 64, changed, "test")


if __name__ == "__main__":
    unittest.main()

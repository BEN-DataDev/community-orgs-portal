#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .control import ControlPlane
from .manifest import SECRET, ensure_no_inline_secrets, load_manifest, portal_by_key
from .provider import CAPABILITIES, create_provider

ROOT = Path(__file__).resolve().parents[2]


def output(value: object) -> None:
    print(json.dumps(value, indent=2, sort_keys=True))


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Operate isolated community portal deployments")
    p.add_argument("--manifest", type=Path, default=ROOT / "fleet/manifest.json")
    p.add_argument("--state", type=Path, default=ROOT / ".fleet/control.sqlite3")
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")
    sub.add_parser("capabilities")
    sub.add_parser("inventory")
    export = sub.add_parser("export-audit"); export.add_argument("--output", type=Path)
    for name in ("provision", "migrate", "health"):
        command = sub.add_parser(name)
        command.add_argument("portal")
        command.add_argument("--operator", required=True)
        command.add_argument("--purpose", required=True)
    rotate = sub.add_parser("rotate-credential")
    rotate.add_argument("portal"); rotate.add_argument("credential", choices=("application", "worker", "bootstrap"))
    rotate.add_argument("--new-secret-ref", required=True)
    rotate.add_argument("--operator", required=True); rotate.add_argument("--purpose", required=True)
    return p


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        manifest, digest = load_manifest(args.manifest)
        ensure_no_inline_secrets(manifest)
        if args.command == "validate":
            output({"valid": True, "manifest_sha256": digest, "portals": len(manifest["portals"])})
            return 0
        if args.command == "capabilities":
            output({name: capabilities.as_dict() for name, capabilities in CAPABILITIES.items()})
            return 0
        control = ControlPlane(args.state)
        try:
            for portal in manifest["portals"]:
                control.sync_manifest(digest, portal, manifest["application_version"])
            if args.command == "inventory":
                output(control.inventory()); return 0
            if args.command == "export-audit":
                package = control.export()
                if args.output:
                    args.output.parent.mkdir(parents=True, exist_ok=True)
                    args.output.write_text(json.dumps(package, indent=2, sort_keys=True) + "\n")
                    output({"output": str(args.output), "chain_valid": package["chain_valid"]})
                else: output(package)
                return 0
            portal = portal_by_key(manifest, args.portal)
            if args.command == "rotate-credential":
                if not SECRET.fullmatch(args.new_secret_ref):
                    raise ValueError("A versioned secret-manager reference is required")
                with control.operation(portal, "rotate_credential", args.operator, args.purpose) as (op, details):
                    revision = control.rotate_ref(portal["portal_id"], args.credential, args.new_secret_ref, op)
                    details.update({"credential": args.credential, "secret_ref": args.new_secret_ref,
                                    "reference_revision": revision, "secret_value_stored": False})
                output({"operation_id": op, "credential": args.credential, "revision": revision}); return 0
            adapter = create_provider(portal)
            with control.operation(portal, args.command, args.operator, args.purpose) as (op, details):
                details["provider_capabilities"] = adapter.capabilities().as_dict()
                if args.command in ("provision", "migrate"):
                    applied = adapter.apply_migrations(ROOT / "supabase/migrations", portal["schema_version"])
                    details["applied_migrations"] = applied
                if args.command == "provision":
                    adapter.establish()
                    details["first_administrator_user_id"] = adapter.bootstrap_administrator()
                health = adapter.health()
                if health["portal_id"] != portal["portal_id"] or health["portal_key"] != portal["portal_key"]:
                    raise RuntimeError("Portal identity does not match the deployment manifest")
                expected = portal["schema_version"]
                details.update({"health": health, "schema_matches": health["schema_version"] == expected})
                health_state = "healthy" if details["schema_matches"] else "schema_drift"
                control.update_observation(portal["portal_id"], op, lifecycle=health["lifecycle"],
                                           schema_version=health["schema_version"],
                                           observed_portal_id=health["portal_id"], health=health_state)
                if args.command in ("provision", "migrate") and not details["schema_matches"]:
                    raise RuntimeError(f"Schema verification failed: expected {expected}, observed {health['schema_version']}")
            output({"operation_id": op, **details}); return 0
        finally:
            control.close()
    except Exception as exc:
        print(f"fleet: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

KEY = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SECRET = re.compile(r"^(env|vault|aws-sm|gcp-sm|azure-kv):[^\s]+$")


def load_manifest(path: Path) -> tuple[dict[str, Any], str]:
    raw = path.read_bytes()
    data = json.loads(raw)
    errors: list[str] = []
    if data.get("manifest_version") != "fleet-v1":
        errors.append("manifest_version must be fleet-v1")
    if not data.get("application_version"):
        errors.append("application_version is required")
    portals = data.get("portals")
    if not isinstance(portals, list) or not portals:
        errors.append("portals must be a non-empty array")
        portals = []
    ids: set[str] = set()
    keys: set[str] = set()
    for index, portal in enumerate(portals):
        label = f"portals[{index}]"
        required = ("portal_id", "portal_key", "display_name", "short_name", "sponsor_name",
                    "establishment_reason", "schema_version", "provider", "credentials")
        for key in required:
            if key not in portal:
                errors.append(f"{label}.{key} is required")
        try:
            import uuid
            uuid.UUID(portal.get("portal_id", ""))
        except ValueError:
            errors.append(f"{label}.portal_id must be a UUID")
        if portal.get("first_administrator_user_id"):
            try:
                uuid.UUID(portal["first_administrator_user_id"])
            except ValueError:
                errors.append(f"{label}.first_administrator_user_id must be a UUID")
        key = portal.get("portal_key", "")
        if not KEY.fullmatch(key):
            errors.append(f"{label}.portal_key is invalid")
        if portal.get("portal_id") in ids or key in keys:
            errors.append(f"{label} duplicates a portal identity or key")
        ids.add(portal.get("portal_id")); keys.add(key)
        if not re.fullmatch(r"\d{14}", portal.get("schema_version", "")):
            errors.append(f"{label}.schema_version must be a 14-digit migration version")
        provider = portal.get("provider", {})
        if provider.get("adapter") not in ("supabase_postgres", "docker_postgres"):
            errors.append(f"{label}.provider.adapter is unsupported")
        if not provider.get("region"):
            errors.append(f"{label}.provider.region is required")
        connection_ref = provider.get("connection_secret_ref")
        if provider.get("adapter") == "supabase_postgres" and not SECRET.fullmatch(connection_ref or ""):
            errors.append(f"{label}.provider.connection_secret_ref must be an approved secret reference")
        if provider.get("adapter") == "docker_postgres" and not all(
            provider.get(value) for value in ("container", "database")
        ):
            errors.append(f"{label}.provider.container and database are required")
        for name, reference in portal.get("credentials", {}).items():
            if name not in ("application", "worker", "bootstrap") or not SECRET.fullmatch(reference or ""):
                errors.append(f"{label}.credentials.{name} is not an approved secret reference")
    if errors:
        raise ValueError("Invalid fleet manifest:\n- " + "\n- ".join(errors))
    return data, hashlib.sha256(raw).hexdigest()


def portal_by_key(manifest: dict[str, Any], key: str) -> dict[str, Any]:
    try:
        return next(portal for portal in manifest["portals"] if portal["portal_key"] == key)
    except StopIteration as exc:
        raise ValueError(f"Portal {key!r} is not in the manifest") from exc


def ensure_no_inline_secrets(data: Any, path: str = "manifest") -> None:
    if isinstance(data, dict):
        for key, value in data.items():
            if any(word in key.lower() for word in ("password", "token", "secret_key", "database_url")):
                raise ValueError(f"{path}.{key} may not contain an inline secret")
            ensure_no_inline_secrets(value, f"{path}.{key}")
    elif isinstance(data, list):
        for index, value in enumerate(data):
            ensure_no_inline_secrets(value, f"{path}[{index}]")

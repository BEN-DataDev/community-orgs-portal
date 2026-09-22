"""Render a registry-seed manifest and candidate array for the private staging RPC."""

import json


def expression(value) -> str:
    # Hex encoding prevents source text being interpreted as SQL or psql commands.
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode().hex()
    return f"convert_from(decode('{encoded}', 'hex'), 'UTF8')::jsonb"


def render(manifest: dict, candidates: list) -> str:
    if manifest.get("contract_version") != "registry-seed-v1":
        raise ValueError("unsupported registry seed manifest")
    if not isinstance(candidates, list):
        raise ValueError("registry seed candidates must be an array")
    return (
        "BEGIN;\nSET LOCAL ROLE ingestion_worker;\n"
        f"SELECT ingestion.stage_registry_seed({expression(manifest)}, {expression(candidates)});\n"
        "COMMIT;\n"
    )

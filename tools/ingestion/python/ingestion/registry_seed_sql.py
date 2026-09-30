"""Render a registry-seed manifest and candidate array for the private staging RPC."""

from ingestion.staging_sql import expression


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

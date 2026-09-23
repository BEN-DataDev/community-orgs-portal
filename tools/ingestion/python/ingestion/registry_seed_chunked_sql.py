"""Render bounded resumable SQL for a large private registry-seed release."""

import argparse
import json
import os
from pathlib import Path


def expression(value) -> str:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode().hex()
    return f"convert_from(decode('{encoded}', 'hex'), 'UTF8')::jsonb"


def statements(manifest: dict, candidates: list, batch_size: int = 250):
    if manifest.get("contract_version") != "registry-seed-v1":
        raise ValueError("unsupported registry seed manifest")
    if manifest.get("completion") != "complete":
        raise ValueError("chunked staging requires a complete release")
    if not isinstance(candidates, list):
        raise ValueError("registry seed candidates must be an array")
    if not 1 <= batch_size <= 500:
        raise ValueError("batch size must be between 1 and 500")
    yield "\\set ON_ERROR_STOP on\n"
    yield "BEGIN;\nSET LOCAL ROLE ingestion_worker;\n"
    yield (
        "SELECT upload_id AS p33_upload_id, finalized AS p33_finalized, "
        "coalesce(release_id,0) AS p33_release_id\n"
        f"FROM ingestion.begin_registry_seed_upload({expression(manifest)},{len(candidates)}) \\gset\n"
        "COMMIT;\n\\if :p33_finalized\n\\else\n"
    )
    for offset in range(0, len(candidates), batch_size):
        batch = candidates[offset : offset + batch_size]
        yield "BEGIN;\nSET LOCAL ROLE ingestion_worker;\n"
        yield (
            "SELECT ingestion.append_registry_seed_upload("
            f":p33_upload_id,{offset},{expression(batch)}) AS p33_received \\gset\n"
        )
        yield "COMMIT;\n"
    yield "BEGIN;\nSET LOCAL ROLE ingestion_worker;\n"
    yield (
        "SELECT ingestion.finalize_registry_seed_upload(:p33_upload_id) "
        "AS p33_release_id \\gset\nCOMMIT;\n"
    )
    yield "BEGIN;\nSET LOCAL ROLE ingestion_worker;\n"
    yield (
        "DO $replay$ BEGIN IF ingestion.finalize_registry_seed_upload(:p33_upload_id) "
        "<> CAST(:p33_release_id AS bigint) THEN RAISE EXCEPTION "
        "'Chunked registry seed replay changed release'; END IF; END $replay$;\n"
        "SELECT ingestion.clear_finalized_registry_seed_upload(:p33_upload_id) "
        "AS p33_cleared \\gset\nCOMMIT;\n\\endif\n"
        "SELECT CAST(:p33_release_id AS bigint);\n"
    )


def write(path: Path, manifest: dict, candidates: list, batch_size: int = 250):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.writelines(statements(manifest, candidates, batch_size))
    except BaseException:
        path.unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--candidates", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=250)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    candidates = json.loads(args.candidates.read_text())
    write(args.output, manifest, candidates, args.batch_size)
    print(f"rendered {len(candidates)} candidates in {(len(candidates) + args.batch_size - 1) // args.batch_size} batches")


if __name__ == "__main__":
    main()

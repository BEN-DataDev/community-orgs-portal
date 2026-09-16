"""Validate an acquisition envelope and emit SQL for the private staging RPC.

No connection is opened. Apply with psql only to an explicitly selected database.
Source enablement is a separate privileged operation.
"""

import argparse
import json
from pathlib import Path

from ingestion.adapters.acnc import digest


def validate(envelope: dict) -> None:
    if envelope.get("contract_version") != "1.0" or envelope.get("source_id") != "acnc-register":
        raise ValueError("unsupported contract/source")
    if envelope.get("publication_eligible") is not False:
        raise ValueError("staging cannot authorize publication")
    if envelope.get("completion") not in {"complete", "partial", "failed"}:
        raise ValueError("invalid completion")
    for key in ["records", "quarantine", "errors", "pages"]:
        if not isinstance(envelope.get(key), list):
            raise ValueError(f"invalid {key}")
    for key in ["run_id", "resource_id", "parser_version", "observed_at"]:
        if not isinstance(envelope.get(key), str) or not envelope[key]:
            raise ValueError(f"missing {key}")
    if not isinstance(envelope.get("scope"), dict):
        raise ValueError("invalid scope")
    if envelope["completion"] == "complete" and (envelope["errors"] or envelope["quarantine"]):
        raise ValueError("complete envelope has rejected data")
    seen = set()
    for record in envelope["records"]:
        for key in ["source_id", "resource_id", "run_id", "parser_version", "observed_at"]:
            if record.get(key) != envelope[key]:
                raise ValueError(f"record {key} mismatch")
        native_id = record.get("native_id")
        if not isinstance(native_id, str) or not native_id or native_id in seen:
            raise ValueError("invalid/duplicate native id")
        seen.add(native_id)
        if not isinstance(record.get("raw"), dict) or record.get("raw_sha256") != digest(record["raw"]):
            raise ValueError("raw record hash mismatch")
        assertions = record.get("assertions")
        if not isinstance(assertions, list):
            raise ValueError("invalid assertions")
        fields = set()
        for assertion in assertions:
            field = assertion.get("field")
            if not isinstance(field, str) or not field or field in fields or "value" not in assertion:
                raise ValueError("invalid/duplicate assertion")
            fields.add(field)


def expression(value: dict) -> str:
    # Hex encoding avoids quoting or interpreting source data as SQL/psql commands.
    encoded = json.dumps(value, ensure_ascii=False).encode().hex()
    return f"convert_from(decode('{encoded}', 'hex'), 'UTF8')::jsonb"


def render(envelope: dict) -> str:
    validate(envelope)
    return ("BEGIN;\nSET LOCAL ROLE ingestion_worker;\n"
            f"SELECT ingestion.stage_acnc({expression(envelope)});\nCOMMIT;\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(render(json.loads(args.input.read_text())))


if __name__ == "__main__":
    main()

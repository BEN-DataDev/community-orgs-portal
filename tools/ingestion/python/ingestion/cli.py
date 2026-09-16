"""Offline fixture reader. Deliberately has no live transport or database writer."""

import argparse
import json
from pathlib import Path

from ingestion.adapters.acnc import ACNCExtractor


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    fixture = json.loads(args.fixture.read_text())
    if fixture.get("synthetic") is not True:
        parser.error("prototype accepts explicitly synthetic fixtures only")

    def fetch_page(params):
        pages = fixture["pages"]
        key = str(params["offset"])
        if key not in pages:
            raise ValueError("fixture page missing at requested offset")
        return pages[key]

    result = ACNCExtractor(fetch_page, fixture["resource_id"], fixture["page_size"]).extract(
        filters=fixture["filters"], run_id=fixture["run_id"], observed_at=fixture["observed_at"]
    )
    result["synthetic"] = True
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(f"{result['completion']}: {result['counts']} -> {args.output}")
    return 0 if result["completion"] == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())

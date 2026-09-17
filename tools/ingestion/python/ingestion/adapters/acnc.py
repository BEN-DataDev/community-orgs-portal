"""Adapted from orgs-sveltekit-etl ACNCCharityService; see upstream-manifest.json.

Retains CKAN filter/offset acquisition, but requires an injected page reader.
One explicit query scope per run avoids conflating overlapping snapshots.
"""

import hashlib
import json
from datetime import datetime
from typing import Callable

from ingestion.acnc_transform import assertions, MAPPING_VERSION

SOURCE_ID = "acnc-register"
PARSER_VERSION = "acnc-ckan-v3"
ENDPOINT = "https://data.gov.au/data/api/3/action/datastore_search"


def digest(value: object) -> str:
    """Hash canonical JSON, independently of key order or whitespace."""
    encoded = json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(encoded.encode()).hexdigest()


def text(row: dict, key: str) -> str | None:
    value = row.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError(f"{key} must be a string or null")
    return value.strip() or None


def normalise(row: dict) -> dict:
    if not isinstance(row, dict):
        raise ValueError("record must be an object")
    native_id = row.get("_id")
    if isinstance(native_id, bool) or not isinstance(native_id, (str, int)):
        raise ValueError("missing or invalid source _id")
    if not str(native_id).strip():
        raise ValueError("empty source _id")
    name = text(row, "Charity_Legal_Name")
    if not name:
        raise ValueError("missing Charity_Legal_Name")
    facts = assertions(row)
    warnings = ["ABN is unverified; format validation is not registry verification"] if row.get("ABN") else ["No ABN supplied; retained for review"]
    for fact in facts:
        if fact['field'] == 'website' and fact['value'] != row['Charity_Website'].strip():
            fact['normalisation'] = {'rule': 'bare-dns-https-v1', 'scheme_inferred': True}
            warnings.append('Website scheme defaulted to HTTPS; source did not specify a scheme. Reachability and ownership are unverified.')
    return {
        "native_id": str(native_id),
        "mapping_version": MAPPING_VERSION,
        "assertions": facts,
        "warnings": warnings,
    }


class ACNCExtractor:
    def __init__(self, fetch_page: Callable[[dict], dict], resource_id: str,
                 page_size: int = 1000, max_pages: int = 100):
        if not resource_id or page_size < 1 or max_pages < 1:
            raise ValueError("resource_id and positive page limits are required")
        self.fetch_page = fetch_page
        self.resource_id = resource_id
        self.page_size = page_size
        self.max_pages = max_pages

    def extract(self, *, filters: dict, run_id: str, observed_at: str) -> dict:
        if not run_id or not filters or any(
            key not in {"Town_City", "State", "Postcode", "ABN"}
            or not isinstance(value, str) or not value.strip()
            for key, value in filters.items()
        ):
            raise ValueError("run_id and explicit nonempty string filters are required")
        stamp = datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            raise ValueError("observed_at must include timezone")
        result = {
            "contract_version": "1.0", "source_id": SOURCE_ID,
            "resource_id": self.resource_id, "run_id": run_id,
            "observed_at": observed_at, "parser_version": PARSER_VERSION,
            "scope": {"filters": dict(filters), "kind": "filtered-resource"},
            "completion": "failed", "publication_eligible": False,
            "records": [], "quarantine": [], "errors": [], "pages": [],
        }
        seen = set()
        offset = 0
        expected_total = None
        for _ in range(self.max_pages):
            try:
                payload = self.fetch_page({
                    "resource_id": self.resource_id, "limit": self.page_size,
                    "offset": offset, "filters": json.dumps(filters, sort_keys=True),
                    "sort": "_id asc",
                })
                if not isinstance(payload, dict) or payload.get("success") is not True:
                    raise ValueError("source response did not report success")
                page = payload.get("result")
                if not isinstance(page, dict) or not isinstance(page.get("records"), list):
                    raise ValueError("invalid result/records schema")
                total = page.get("total")
                if type(total) is not int or total < 0:
                    raise ValueError("invalid or missing total")
                if expected_total is not None and total != expected_total:
                    raise ValueError("source total changed during pagination")
                expected_total = total
                rows = page["records"]
                if len(rows) > self.page_size or offset + len(rows) > total:
                    raise ValueError("source count inconsistent with requested page")
                if not rows and offset < total:
                    raise ValueError("premature empty page")
                result["pages"].append({"offset": offset, "count": len(rows),
                                        "sha256": digest(payload)})
                for index, row in enumerate(rows):
                    try:
                        record = normalise(row)
                        if record["native_id"] in seen:
                            raise ValueError("duplicate source _id across pages")
                        seen.add(record["native_id"])
                        record.update({
                            "source_id": SOURCE_ID, "resource_id": self.resource_id,
                            "run_id": run_id, "observed_at": observed_at,
                            "source_modified_at": None, "parser_version": PARSER_VERSION,
                            "source_url": ENDPOINT + "?resource_id=" + self.resource_id,
                            "raw_sha256": digest(row), "raw": row,
                        })
                        result["records"].append(record)
                    except ValueError as exc:
                        result["quarantine"].append({"row": offset + index,
                                                     "reason": str(exc), "raw": row})
                offset += len(rows)
                if offset == total:
                    result["completion"] = "partial" if result["quarantine"] else "complete"
                    break
            except (OSError, ValueError, TypeError) as exc:
                result["errors"].append({"offset": offset, "reason": str(exc)})
                result["completion"] = "partial" if result["pages"] else "failed"
                break
        else:
            result["errors"].append({"offset": offset, "reason": "page budget exhausted"})
            result["completion"] = "partial" if result["pages"] else "failed"
        result["counts"] = {"accepted": len(result["records"]),
                            "quarantined": len(result["quarantine"]),
                            "pages": len(result["pages"]), "source_total": expected_total}
        return result

"""Bounded NSW association searches producing private registry-seed artifacts only."""

import argparse
import http.cookiejar
import json
import os
import re
import sys
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, HTTPRedirectHandler, Request, build_opener

from ingestion.adapters.nsw_associations import (
    NSWAssociationsExtractor, PARSER_VERSION, REGISTER_URL, RESOURCE_ID, SOURCE_ID, form_fields,
)
from ingestion.registry_seed_sql import render

CONFIG_VERSION = "nsw-associations-live-v1"
RESULTS_URL = REGISTER_URL + "RegistrationSearch.aspx"
ORGANISATION_TYPE = "INCORASSOC"
ORGANISATION_TYPE_LABEL = "INCORPORATED ASSOCIATION"
STATUSES = (
    ("AMALG", "AMALGAMATED"),
    ("CANCELLED", "CANCELLED"),
    ("LIQUIDATIN", "IN LIQUIDATION"),
    ("REGISTERED", "REGISTERED"),
    ("TRANSFER", "TRANSFERRED"),
    ("ADMNSTRATN", "UNDER ADMINISTRATION"),
)
STATUS_LABELS = dict(STATUSES)
QUERY_PLAN_VERSION = "incorporated-association-status-date-v1"
FIELD_PREFIX = "ctl00$MainArea$AdvancedSearchSection$"


def configuration(raw):
    if not isinstance(raw, dict) or raw.get("config_version") != CONFIG_VERSION:
        raise ValueError("unsupported NSW associations configuration")
    if type(raw.get("enabled")) is not bool or type(raw.get("approved_access_reuse")) is not bool:
        raise ValueError("enabled and approved_access_reuse must be booleans")
    if raw.get("source_id") != SOURCE_ID or raw.get("resource_id") != RESOURCE_ID:
        raise ValueError("source/resource identity does not match the adapter")
    postcodes = raw.get("postcodes")
    if (not isinstance(postcodes, list) or not 1 <= len(postcodes) <= 50
            or postcodes != sorted(set(postcodes))
            or any(not isinstance(p, str) or not re.fullmatch(r"[0-9]{4}", p) for p in postcodes)):
        raise ValueError("1 to 50 sorted unique ASCII postcodes are required")
    statuses = raw.get("statuses")
    allowed_statuses = [value for value, _ in STATUSES]
    if (not isinstance(statuses, list) or not statuses
            or any(not isinstance(status, str) or status not in STATUS_LABELS
                   for status in statuses)
            or len(statuses) != len(set(statuses))
            or statuses != [status for status in allowed_statuses if status in statuses]):
        raise ValueError(
            "statuses must be a non-empty unique subset in provider order: "
            + ", ".join(allowed_statuses)
        )
    for key in ("approval_reference", "snapshot_series", "attribution", "user_agent"):
        if not isinstance(raw.get(key), str) or not raw[key].strip():
            raise ValueError(f"{key} is required")
    if ("CommunityOrgs" not in raw["user_agent"]
            or not any(contact in raw["user_agent"] for contact in ("mailto:", "https://"))):
        raise ValueError("user_agent must identify CommunityOrgs and a stable contact")
    placeholders = ("pending", "replace-with", "not-approved", "example.invalid")
    if raw["enabled"] and not raw["approved_access_reuse"]:
        raise ValueError("enabled configuration requires recorded access/reuse approval")
    if raw["approved_access_reuse"] and any(
            marker in (raw["approval_reference"] + " " + raw["user_agent"]).lower()
            for marker in placeholders):
        raise ValueError("approved configuration contains placeholder approval/contact evidence")
    if (not isinstance(raw.get("portal_scope_revision_id"), str)
            or not raw["portal_scope_revision_id"].isdigit()
            or int(raw["portal_scope_revision_id"]) < 1):
        raise ValueError("portal_scope_revision_id must be a positive integer string")
    for key, low, high in (("max_pages_per_postcode", 1, 100), ("timeout_seconds", 1, 30),
                           ("deadline_seconds", 10, 1800), ("delay_seconds", 2, 60),
                           ("max_response_bytes", 1024, 4 * 1024 * 1024),
                           ("provider_result_cap", 1, 10000)):
        value = raw.get(key)
        if type(value) not in {int, float} or not low <= value <= high:
            raise ValueError(f"{key} must be between {low} and {high}")
    retention = raw.get("retention")
    if (not isinstance(retention, dict) or retention.get("class") != "hold"
            or not isinstance(retention.get("basis"), str) or not retention["basis"].strip()
            or "raw_expires_at" in retention):
        raise ValueError("the first cohort requires a reasoned hold retention policy")
    return raw


def require_enablement(config, explicit_enable):
    if not config["approved_access_reuse"]:
        raise ValueError("access/reuse approval is not recorded")
    if not config["enabled"]:
        raise ValueError("source is disabled in configuration")
    if not explicit_enable:
        raise ValueError("live acquisition requires the explicit --enable flag")


class RegisterRedirect(HTTPRedirectHandler):
    """Allow only the register's qualified POST-then-GET results transition."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if code == 302 and req.data is not None and newurl == RESULTS_URL:
            return super().redirect_request(req, fp, code, msg, headers, newurl)
        raise ValueError("redirect refused; requalify the register endpoint")


class Transport:
    def __init__(self, config, opener=None, clock=time.monotonic, sleep=time.sleep):
        self.config, self.clock, self.sleep = config, clock, sleep
        self.end = clock() + config["deadline_seconds"]
        self.opener = opener or build_opener(
            RegisterRedirect(), HTTPCookieProcessor(http.cookiejar.CookieJar())
        )
        self.requests = 0
        self.last_request = None
        self.current_html = None

    def _request(self, data=None):
        if self.clock() >= self.end:
            raise ValueError("HTTP deadline exhausted")
        if self.last_request is not None:
            pause = self.config["delay_seconds"] - (self.clock() - self.last_request)
            if pause > 0:
                if self.clock() + pause >= self.end:
                    raise ValueError("HTTP pacing would exceed deadline")
                self.sleep(pause)
        request = Request(REGISTER_URL, data=data, headers={
            "Accept": "text/html,application/xhtml+xml",
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": self.config["user_agent"],
        })
        try:
            self.last_request = self.clock()
            self.requests += 1
            timeout = min(self.config["timeout_seconds"], self.end - self.clock())
            with self.opener.open(request, timeout=timeout) as response:
                content_type = response.headers.get_content_type()
                if content_type != "text/html":
                    raise ValueError("register returned a non-HTML response")
                data_bytes = response.read(self.config["max_response_bytes"] + 1)
                if len(data_bytes) > self.config["max_response_bytes"]:
                    raise ValueError("register response exceeds byte limit")
                charset = response.headers.get_content_charset() or "utf-8"
                self.current_html = data_bytes.decode(charset)
                return self.current_html
        except HTTPError as exc:
            code = exc.code
            exc.close()
            raise ValueError(f"register returned HTTP {code}; run stopped") from exc
        except TimeoutError as exc:
            raise ValueError("register request timed out; run stopped") from exc
        except (URLError, OSError, UnicodeError) as exc:
            raise ValueError("register request failed; run stopped") from exc

    def initial(self, query):
        landing = self._request()
        fields = form_fields(landing)
        fields[FIELD_PREFIX + "Postcode"] = query["postcode"]
        fields[FIELD_PREFIX + "Organisationtype"] = ORGANISATION_TYPE
        fields[FIELD_PREFIX + "Organisationstatus"] = query["status"]
        if query.get("date_from"):
            fields[FIELD_PREFIX + "Dateregisteredfrom"] = query["date_from"]
            fields[FIELD_PREFIX + "Dateregisteredto"] = query["date_to"]
        fields["__EVENTTARGET"] = FIELD_PREFIX + "AdvancedSearchButton"
        fields["__EVENTARGUMENT"] = ""
        return self._request(urlencode(fields).encode())

    def next(self, target):
        if not target or self.current_html is None:
            raise ValueError("next-page request has no current ASP.NET state")
        fields = form_fields(self.current_html)
        fields["__EVENTTARGET"], fields["__EVENTARGUMENT"] = target, ""
        return self._request(urlencode(fields).encode())


def _date_value(value):
    return datetime.strptime(value, "%d/%m/%Y").date()


def _query_key(query):
    dates = (f"-{query['date_from'].replace('/', '')}-{query['date_to'].replace('/', '')}"
             if query.get("date_from") else "")
    return f"postcode-{query['postcode']}-status-{query['status']}{dates}"


def _split_query(query, observed_date):
    start = _date_value(query["date_from"]) if query.get("date_from") else date(1800, 1, 1)
    end = _date_value(query["date_to"]) if query.get("date_to") else observed_date
    if start >= end:
        return None
    midpoint = start + (end - start) // 2
    left = {**query, "date_from": start.strftime("%d/%m/%Y"),
            "date_to": midpoint.strftime("%d/%m/%Y")}
    right_start = midpoint + timedelta(days=1)
    right = {**query, "date_from": right_start.strftime("%d/%m/%Y"),
             "date_to": end.strftime("%d/%m/%Y")}
    return left, right


def _query_tuple(query):
    return (query.get("postcode"), query.get("status"), query.get("date_from"),
            query.get("date_to"))


def _status_complete(postcode, status, parts, splits, observed_date, errors=()):
    if any(error.get("postcode") == postcode and error.get("status") == status
           for error in errors):
        return False
    groups = {}
    for part in parts:
        detail = part.get("detail", {})
        if detail.get("postcode") == postcode and detail.get("status") == status:
            key = (postcode, status, detail.get("date_from"), detail.get("date_to"))
            groups.setdefault(key, []).append(part)
    split_keys = {_query_tuple(item.get("query", {})) for item in splits}

    def complete_query(query):
        key = _query_tuple(query)
        if key in split_keys:
            children = _split_query(query, observed_date)
            return bool(children) and all(complete_query(child) for child in children)
        query_parts = sorted(groups.get(key, []), key=lambda part: part.get("ordinal", 0))
        return (bool(query_parts)
                and all(part.get("status") == "complete" for part in query_parts)
                and query_parts[-1].get("detail", {}).get("next") is False)

    return complete_query({"postcode": postcode, "status": status})


def _leaf_queries(query, split_keys, observed_date):
    if _query_tuple(query) not in split_keys:
        return [query]
    children = _split_query(query, observed_date)
    if not children:
        raise ValueError("partition split evidence cannot be reproduced")
    leaves = []
    for child in children:
        leaves.extend(_leaf_queries(child, split_keys, observed_date))
    return leaves


def _complete_query_parts(query, parts):
    key = _query_tuple(query)
    query_parts = sorted(
        (part for part in parts
         if _query_tuple(part.get("detail", {})) == key),
        key=lambda part: part.get("ordinal", 0),
    )
    return (query_parts if query_parts
            and all(part.get("status") == "complete" for part in query_parts)
            and query_parts[-1].get("detail", {}).get("next") is False else [])


def _validate_partition_candidates(query, candidates):
    expected_status = STATUS_LABELS[query["status"]]
    start = _date_value(query["date_from"]) if query.get("date_from") else None
    end = _date_value(query["date_to"]) if query.get("date_to") else None
    for candidate in candidates:
        raw = candidate["raw"]
        if raw.get("organisation_type", "").strip().upper() != ORGANISATION_TYPE_LABEL:
            raise ValueError("organisation-type filter was not honoured")
        if raw.get("status", "").strip().upper() != expected_status:
            raise ValueError("organisation-status filter was not honoured")
        if start:
            registered = raw.get("date_registered")
            if not registered:
                raise ValueError("date-partition candidate has no registration date")
            registered_date = _date_value(registered)
            if not start <= registered_date <= end:
                raise ValueError("registration-date filter was not honoured")


def acquire(config, transport_factory=Transport, *, release_id=None, observed_at=None,
            progress=None, sleep=time.sleep, first_status=None, first_queries=None):
    release_id = release_id or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
    observed_at = observed_at or datetime.now(timezone.utc).isoformat()
    all_parts, all_candidates, errors, seen, splits = [], [], [], set(), []
    request_count = 0
    observed_date = datetime.fromisoformat(observed_at.replace("Z", "+00:00")).date()
    prior_query = False
    configured_statuses = config["statuses"]
    for postcode_index, postcode in enumerate(config["postcodes"]):
        postcode_ok = True
        status_start = 0
        if postcode_index == 0 and first_status is not None:
            status_start = configured_statuses.index(first_status)
        for status in configured_statuses[status_start:]:
            pending = (list(first_queries) if postcode_index == 0 and status == first_status
                       and first_queries else [{"postcode": postcode, "status": status}])
            while pending:
                query = pending.pop(0)
                if prior_query:
                    sleep(config["delay_seconds"])
                prior_query = True
                transport = transport_factory(config)
                extractor = NSWAssociationsExtractor(
                    transport.initial, transport.next,
                    max_pages=config["max_pages_per_postcode"])
                parts, candidates, query_errors, query_complete = extractor.extract(
                    query=query, postcodes=[postcode], release_id=release_id,
                    observed_at=observed_at)
                request_count += transport.requests
                try:
                    if query_complete:
                        _validate_partition_candidates(query, candidates)
                except (KeyError, ValueError) as exc:
                    query_errors.append({"page": len(parts), "message": str(exc)})
                    query_complete = False
                if query_complete and len(candidates) >= config["provider_result_cap"]:
                    if not query.get("date_from") and any(
                            not candidate["raw"].get("date_registered")
                            for candidate in candidates):
                        query_errors.append({
                            "page": len(parts),
                            "message": "capped partition contains a record without a registration date",
                        })
                        query_complete = False
                        children = None
                    else:
                        children = _split_query(query, observed_date)
                    if query_complete and children is None:
                        query_errors.append({
                            "page": len(parts),
                            "message": "provider result cap reached in one-day partition",
                        })
                        query_complete = False
                    elif query_complete:
                        splits.append({"query": query, "records_observed": len(candidates),
                                       "page_hashes": [p.get("sha256") for p in parts]})
                        pending[0:0] = children
                        if progress:
                            progress({"postcode": postcode, "status": status,
                                      "partition": _query_key(query), "split": True,
                                      "pages": len(parts), "candidates": len(candidates),
                                      "errors": 0})
                        continue
                query_key = _query_key(query)
                for part in parts:
                    part["part_id"] = f"{query_key}-{part['part_id']}"
                    part["ordinal"] = len(all_parts) + 1
                    part.setdefault("detail", {}).update({
                        "postcode": postcode, "organisation_type": ORGANISATION_TYPE,
                        "status": status, "date_from": query.get("date_from"),
                        "date_to": query.get("date_to"),
                    })
                    all_parts.append(part)
                for candidate in candidates:
                    if candidate["native_id"] in seen:
                        query_errors.append({
                            "page": len(parts),
                            "message": "candidate repeated across query partitions",
                            "native_id": candidate["native_id"],
                        })
                    else:
                        seen.add(candidate["native_id"])
                        all_candidates.append(candidate)
                errors.extend({"postcode": postcode, "status": status,
                               "date_from": query.get("date_from"),
                               "date_to": query.get("date_to"), **error}
                              for error in query_errors)
                if progress:
                    progress({"postcode": postcode, "status": status,
                              "partition": query_key, "complete": query_complete,
                              "pages": len(parts), "candidates": len(candidates),
                              "errors": len(query_errors)})
                if not query_complete or query_errors:
                    postcode_ok = False
                    break
            if not postcode_ok:
                break
        if not postcode_ok:
            break
    complete = (not errors and all(p["status"] == "complete" for p in all_parts)
                and {p["detail"]["postcode"] for p in all_parts} == set(config["postcodes"])
                and all(any(p["detail"]["postcode"] == postcode
                            and p["detail"]["status"] == status for p in all_parts)
                        for postcode in config["postcodes"] for status in configured_statuses))
    manifest = {
        "contract_version": "registry-seed-v1", "source_id": SOURCE_ID,
        "resource_id": RESOURCE_ID, "release_id": release_id,
        "parser_version": PARSER_VERSION, "observed_at": observed_at,
        "completion": "complete" if complete else "partial",
        "scope": {"kind": "configured-registry-scope", "complete_snapshot": complete,
                  "snapshot_series": config["snapshot_series"],
                  "portal_scope_revision_id": config["portal_scope_revision_id"],
                  "selection": {"postcodes": config["postcodes"], "jurisdiction": "AU-NSW",
                                "organisation_type": ORGANISATION_TYPE,
                                "statuses": configured_statuses,
                                "query_plan_version": QUERY_PLAN_VERSION}},
        "parts": all_parts, "errors": errors, "retention": config["retention"],
        "source": {"publisher": "NSW Fair Trading", "url": REGISTER_URL,
                   "attribution": config["attribution"],
                   "approval_reference": config["approval_reference"],
                   "access_mode": "ordinary unauthenticated public register search",
                   "http_requests": request_count, "partition_splits": splits},
    }
    return manifest, all_candidates


def resume_acquire(config, prior_manifest, prior_candidates, transport_factory=Transport,
                   progress=None, sleep=time.sleep):
    """Resume after the last wholly complete query leaf, never within pagination."""
    if (not isinstance(prior_manifest, dict) or not isinstance(prior_candidates, list)
            or prior_manifest.get("contract_version") != "registry-seed-v1"
            or prior_manifest.get("source_id") != SOURCE_ID
            or prior_manifest.get("resource_id") != RESOURCE_ID
            or prior_manifest.get("parser_version") != PARSER_VERSION
            or prior_manifest.get("completion") == "complete"
            or prior_manifest.get("scope", {}).get("selection", {}).get("postcodes")
            != config["postcodes"]
            or prior_manifest.get("scope", {}).get("selection", {}).get("statuses")
            != config["statuses"]
            or prior_manifest.get("scope", {}).get("selection", {}).get("query_plan_version")
            != QUERY_PLAN_VERSION):
        raise ValueError("resume evidence does not match the incomplete configured release")
    parts = prior_manifest.get("parts")
    if not isinstance(parts, list) or not parts:
        raise ValueError("resume evidence has no page inventory")
    observed_date = datetime.fromisoformat(
        prior_manifest["observed_at"].replace("Z", "+00:00")
    ).date()
    prior_splits = prior_manifest.get("source", {}).get("partition_splits", [])
    prefix_parts, prefix_records = [], 0
    kept_split_keys = set()
    next_index, next_status = 0, None
    next_queries = None
    stopped = False
    for index, postcode in enumerate(config["postcodes"]):
        for status in config["statuses"]:
            root = {"postcode": postcode, "status": status}
            status_split_keys = {
                _query_tuple(item.get("query", {})) for item in prior_splits
                if item.get("query", {}).get("postcode") == postcode
                and item.get("query", {}).get("status") == status
            }
            leaves = _leaf_queries(root, status_split_keys, observed_date)
            status_parts = []
            incomplete = None
            incomplete_index = None
            for leaf_index, leaf in enumerate(leaves):
                leaf_parts = _complete_query_parts(leaf, parts)
                leaf_has_error = any(
                    error.get("postcode") == postcode and error.get("status") == status
                    and (error.get("date_from") == leaf.get("date_from")
                         or ("date_from" not in error and any(
                             part.get("detail", {}).get("date_from") == leaf.get("date_from")
                             and part.get("status") == "failed" for part in parts)))
                    for error in prior_manifest.get("errors", [])
                )
                if not leaf_parts or leaf_has_error:
                    incomplete = leaf
                    incomplete_index = leaf_index
                    break
                status_parts.extend(leaf_parts)
            if incomplete is not None:
                prefix_parts.extend(status_parts)
                prefix_records += sum(p.get("record_count", 0) for p in status_parts)
                kept_split_keys.update(status_split_keys)
                next_index, next_status, next_queries, stopped = (
                    index, status, leaves[incomplete_index:], True)
                break
            prefix_parts.extend(status_parts)
            prefix_records += sum(p.get("record_count", 0) for p in status_parts)
            kept_split_keys.update(status_split_keys)
        if stopped:
            break
    if not stopped:
        raise ValueError("incomplete resume evidence has no failed postcode")
    if prefix_records > len(prior_candidates):
        raise ValueError("resume evidence candidate inventory is truncated")
    prefix_candidates = prior_candidates[:prefix_records]
    remaining = {**config, "postcodes": config["postcodes"][next_index:]}
    resumed_manifest, resumed_candidates = acquire(
        remaining, transport_factory,
        release_id=prior_manifest["release_id"], observed_at=prior_manifest["observed_at"],
        progress=progress, sleep=sleep, first_status=next_status, first_queries=next_queries)
    candidates = prefix_candidates + resumed_candidates
    seen, duplicate_errors = set(), []
    for candidate in candidates:
        native_id = candidate.get("native_id")
        if native_id in seen:
            duplicate_errors.append({"message": "candidate repeated across resumed postcode searches",
                                     "native_id": native_id})
        seen.add(native_id)
    combined_parts = prefix_parts + resumed_manifest["parts"]
    for ordinal, part in enumerate(combined_parts, 1):
        part["ordinal"] = ordinal
    resumed_manifest["scope"]["selection"]["postcodes"] = config["postcodes"]
    resumed_manifest["parts"] = combined_parts
    resumed_manifest["errors"].extend(duplicate_errors)
    resumed_manifest["source"]["http_requests"] += prior_manifest.get("source", {}).get(
        "http_requests", 0
    )
    resumed_manifest["source"]["resume_attempts"] = (
        prior_manifest.get("source", {}).get("resume_attempts", 0) + 1
    )
    kept_splits = [item for item in prior_splits
                   if _query_tuple(item.get("query", {})) in kept_split_keys]
    combined_splits = kept_splits + resumed_manifest["source"].get("partition_splits", [])
    resumed_manifest["source"]["partition_splits"] = combined_splits
    complete = (all(_status_complete(postcode, status, combined_parts, combined_splits,
                                     observed_date)
                    for postcode in config["postcodes"] for status in config["statuses"])
                and not resumed_manifest["errors"]
                and all(part["status"] == "complete" for part in combined_parts))
    resumed_manifest["completion"] = "complete" if complete else "partial"
    resumed_manifest["scope"]["complete_snapshot"] = complete
    return resumed_manifest, candidates


def _write(path, value, *, text=False):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
        if text:
            stream.write(value)
        else:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--enable", action="store_true")
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--resume-from", type=Path)
    args = parser.parse_args()
    try:
        config = configuration(json.loads(args.config.read_text()))
        require_enablement(config, args.enable)
        args.output_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
        def report_progress(event):
            print(json.dumps({"progress": event}), file=sys.stderr, flush=True)

        if args.resume_from:
            prior_manifest = json.loads((args.resume_from / "manifest.json").read_text())
            prior_candidates = json.loads((args.resume_from / "candidates.json").read_text())
            manifest, candidates = resume_acquire(
                config, prior_manifest, prior_candidates, progress=report_progress
            )
        else:
            manifest, candidates = acquire(
                config, release_id="nsw-" + str(uuid.uuid4()), progress=report_progress
            )
        _write(args.output_dir / "manifest.json", manifest)
        _write(args.output_dir / "candidates.json", candidates)
        _write(args.output_dir / "stage.sql", render(manifest, candidates), text=True)
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
        parser.exit(2, f"NSW association release rejected: {exc}\n")
    print(json.dumps({"release_id": manifest["release_id"], "completion": manifest["completion"],
                      "candidates": len(candidates), "output": str(args.output_dir)}))
    return 0 if manifest["completion"] == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())

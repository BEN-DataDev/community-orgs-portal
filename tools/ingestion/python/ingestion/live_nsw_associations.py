"""Bounded NSW association searches producing private registry-seed artifacts only."""

import argparse
import http.cookiejar
import json
import os
import re
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, HTTPRedirectHandler, Request, build_opener

from ingestion.adapters.nsw_associations import (
    NSWAssociationsExtractor, PARSER_VERSION, REGISTER_URL, RESOURCE_ID, SOURCE_ID, form_fields,
)
from ingestion.registry_seed_sql import render

CONFIG_VERSION = "nsw-associations-live-v1"


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
    for key in ("approval_reference", "snapshot_series", "attribution", "user_agent"):
        if not isinstance(raw.get(key), str) or not raw[key].strip():
            raise ValueError(f"{key} is required")
    if "CommunityOrgs" not in raw["user_agent"] or "mailto:" not in raw["user_agent"]:
        raise ValueError("user_agent must identify CommunityOrgs and an operator contact")
    if (not isinstance(raw.get("portal_scope_revision_id"), str)
            or not raw["portal_scope_revision_id"].isdigit()
            or int(raw["portal_scope_revision_id"]) < 1):
        raise ValueError("portal_scope_revision_id must be a positive integer string")
    for key, low, high in (("max_pages_per_postcode", 1, 20), ("timeout_seconds", 1, 30),
                           ("deadline_seconds", 10, 1800), ("delay_seconds", 2, 60),
                           ("max_response_bytes", 1024, 4 * 1024 * 1024)):
        value = raw.get(key)
        if type(value) not in {int, float} or not low <= value <= high:
            raise ValueError(f"{key} must be between {low} and {high}")
    retention = raw.get("retention")
    if (not isinstance(retention, dict) or retention.get("class") != "hold"
            or not isinstance(retention.get("basis"), str) or not retention["basis"].strip()
            or "raw_expires_at" in retention):
        raise ValueError("the first cohort requires a reasoned hold retention policy")
    return raw


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("redirect refused; requalify the register endpoint")


class Transport:
    def __init__(self, config, opener=None, clock=time.monotonic, sleep=time.sleep):
        self.config, self.clock, self.sleep = config, clock, sleep
        self.end = clock() + config["deadline_seconds"]
        self.opener = opener or build_opener(
            NoRedirect(), HTTPCookieProcessor(http.cookiejar.CookieJar())
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
        except (URLError, TimeoutError, OSError, UnicodeError) as exc:
            raise ValueError("register request failed; run stopped") from exc

    def initial(self, postcodes):
        landing = self._request()
        fields = form_fields(landing)
        fields["ctl00$MainArea$AdvancedSearchSection$Postcode"] = postcodes[0]
        fields["__EVENTTARGET"] = "ctl00$MainArea$AdvancedSearchSection$AdvancedSearchButton"
        fields["__EVENTARGUMENT"] = ""
        return self._request(urlencode(fields).encode())

    def next(self, target):
        if not target or self.current_html is None:
            raise ValueError("next-page request has no current ASP.NET state")
        fields = form_fields(self.current_html)
        fields["__EVENTTARGET"], fields["__EVENTARGUMENT"] = target, ""
        return self._request(urlencode(fields).encode())


def acquire(config, transport_factory=Transport, *, release_id=None, observed_at=None):
    release_id = release_id or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
    observed_at = observed_at or datetime.now(timezone.utc).isoformat()
    all_parts, all_candidates, errors, seen = [], [], [], set()
    request_count = 0
    for postcode in config["postcodes"]:
        transport = transport_factory(config)
        extractor = NSWAssociationsExtractor(transport.initial, transport.next,
                                              max_pages=config["max_pages_per_postcode"])
        parts, candidates, postcode_errors, complete = extractor.extract(
            postcodes=[postcode], release_id=release_id, observed_at=observed_at)
        for part in parts:
            part["part_id"] = f"postcode-{postcode}-{part['part_id']}"
            part["ordinal"] = len(all_parts) + 1
            part.setdefault("detail", {})["postcode"] = postcode
            all_parts.append(part)
        request_count += transport.requests
        for candidate in candidates:
            if candidate["native_id"] in seen:
                errors.append({
                    "postcode": postcode,
                    "message": "candidate repeated across postcode searches",
                    "native_id": candidate["native_id"],
                })
            else:
                seen.add(candidate["native_id"])
                all_candidates.append(candidate)
        errors.extend({"postcode": postcode, **error} for error in postcode_errors)
        if not complete:
            break
    complete = (len({p["detail"]["postcode"] for p in all_parts if p["status"] == "complete"})
                == len(config["postcodes"]) and not errors
                and all(p["status"] == "complete" for p in all_parts))
    manifest = {
        "contract_version": "registry-seed-v1", "source_id": SOURCE_ID,
        "resource_id": RESOURCE_ID, "release_id": release_id,
        "parser_version": PARSER_VERSION, "observed_at": observed_at,
        "completion": "complete" if complete else "partial",
        "scope": {"kind": "configured-registry-scope", "complete_snapshot": complete,
                  "snapshot_series": config["snapshot_series"],
                  "portal_scope_revision_id": config["portal_scope_revision_id"],
                  "selection": {"postcodes": config["postcodes"], "jurisdiction": "AU-NSW"}},
        "parts": all_parts, "errors": errors, "retention": config["retention"],
        "source": {"publisher": "NSW Fair Trading", "url": REGISTER_URL,
                   "attribution": config["attribution"],
                   "approval_reference": config["approval_reference"],
                   "access_mode": "ordinary unauthenticated public register search",
                   "http_requests": request_count},
    }
    return manifest, all_candidates


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
    args = parser.parse_args()
    try:
        config = configuration(json.loads(args.config.read_text()))
        if not config["approved_access_reuse"]:
            raise ValueError("access/reuse approval is not recorded")
        if not config["enabled"] and not args.enable:
            raise ValueError("source disabled; review configuration and pass --enable")
        args.output_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
        manifest, candidates = acquire(config, release_id="nsw-" + str(uuid.uuid4()))
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

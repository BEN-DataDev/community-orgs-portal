"""Parse bounded NSW Incorporated Associations Register search pages.

The transport is injected. This module never performs HTTP requests, links records,
or writes to the portal. Markup changes fail closed instead of becoming empty data.
"""

import hashlib
import json
import re
from datetime import datetime
from html.parser import HTMLParser

SOURCE_ID = "nsw-incorporated-associations"
RESOURCE_ID = "public-register-search"
PARSER_VERSION = "nsw-associations-html-v1"
REGISTER_URL = "https://applications.fairtrading.nsw.gov.au/assocregister/"
NUMBER = re.compile(r"[A-Z0-9][A-Z0-9 ./_-]{0,99}")
DATE = re.compile(r"\d{2}/\d{2}/\d{4}")
ORG_ID = re.compile(r"(?:Organisationid|OrganisationID)=(\d+)", re.I)


def digest(value):
    encoded = json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(encoded.encode()).hexdigest()


class Node:
    def __init__(self, tag="root", attrs=()):
        self.tag = tag
        self.attrs = dict(attrs)
        self.children = []
        self.text = []

    def content(self):
        values = list(self.text)
        for child in self.children:
            values.append(child.content())
        return " ".join(" ".join(values).split())

    def find_all(self, predicate):
        found = []
        for child in self.children:
            if predicate(child):
                found.append(child)
            found.extend(child.find_all(predicate))
        return found


class TreeParser(HTMLParser):
    VOID = {
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr",
    }

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node()
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in self.VOID:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        self.stack[-1].children.append(Node(tag, attrs))

    def handle_endtag(self, tag):
        for index in range(len(self.stack) - 1, 0, -1):
            if self.stack[index].tag == tag:
                del self.stack[index:]
                return

    def handle_data(self, data):
        if data.strip():
            self.stack[-1].text.append(data)


def _tree(html):
    if not isinstance(html, str) or len(html) < 100:
        raise ValueError("register returned an empty or invalid HTML document")
    parser = TreeParser()
    parser.feed(html)
    return parser.root


def _classes(node):
    return set(node.attrs.get("class", "").split())


def form_fields(html):
    root = _tree(html)
    forms = root.find_all(lambda n: n.tag == "form" and n.attrs.get("id") == "aspnetForm")
    if len(forms) != 1:
        raise ValueError("expected one ASP.NET register form")
    fields = {}
    for node in forms[0].find_all(lambda n: n.tag == "input"):
        name = node.attrs.get("name")
        kind = node.attrs.get("type", "text").lower()
        if name and kind not in {"submit", "button", "image", "file"}:
            fields[name] = node.attrs.get("value", "")
    # The current register has ViewState but does not emit EventValidation. Preserve
    # any additional hidden state without requiring fields the provider omits.
    if "__VIEWSTATE" not in fields:
        raise ValueError("ASP.NET ViewState is missing; markup contract changed")
    return fields


def _label(text, label):
    match = re.search(re.escape(label) + r"\s*:\s*(.*?)(?=\s+[A-Z][A-Za-z ]+\s*:|$)", text)
    return match.group(1).strip() if match else None


def parse_page(html):
    root = _tree(html)
    form_fields(html)  # qualification check applies to every page
    containers = root.find_all(lambda n: n.attrs.get("id") == "ctl00_MainArea_ResultDataList")
    result_region = root.find_all(lambda n: n.attrs.get("id") == "ctl00_MainArea_SearchResultDiv")
    if len(result_region) != 1:
        raise ValueError("search result region is missing; markup contract changed")
    style = result_region[0].attrs.get("style", "").replace(" ", "").lower()
    if "display:none" in style:
        raise ValueError("page is not a completed register search")
    if len(containers) == 1:
        rows = containers[0].find_all(
            lambda n: n.tag == "div" and "row" in _classes(n)
            and any(c.tag == "div" and "col-md-10" in _classes(c) for c in n.children)
        )
    else:
        raise ValueError("expected one result container; markup contract changed")
    records = []
    for row in rows:
        main = next(
            (c for c in row.children if c.tag == "div" and "col-md-10" in _classes(c)), None
        )
        status_box = next(
            (c for c in row.children if c.tag == "div" and "col-md-2" in _classes(c)), None
        )
        links = main.find_all(lambda n: n.tag == "a" and ORG_ID.search(n.attrs.get("href", "")))
        if len(links) != 1 or status_box is None:
            raise ValueError("result row identity/status markup changed")
        org_match = ORG_ID.search(links[0].attrs["href"])
        name = links[0].content()
        text = main.content()
        status = status_box.content()
        record = {
            "organisation_id": org_match.group(1),
            "name": name,
            "organisation_number": _label(text, "Organisation Number"),
            "organisation_type": _label(text, "Organisation Type"),
            "status": status,
            "date_registered": _label(text, "Date Registered"),
            "date_removed": _label(text, "Date Removed"),
            "registered_office_address": _label(text, "Registered Office Address"),
        }
        if not name or not record["organisation_number"] or not status:
            raise ValueError("result row is missing required public fields")
        records.append(record)
    next_links = root.find_all(
        lambda n: n.tag == "a"
        and n.attrs.get("id", "").endswith(("PageNextLink", "PageNextBottomLink"))
    )
    enabled = []
    for link in next_links:
        href = link.attrs.get("href", "")
        style = link.attrs.get("style", "").replace(" ", "").lower()
        parent_disabled = False
        if "display:none" in style or "disabled" in _classes(link):
            continue
        match = re.search(r"__doPostBack\(['\"]([^'\"]+)", href)
        if match and not parent_disabled:
            enabled.append(match.group(1))
    if len(set(enabled)) > 1:
        raise ValueError("top and bottom next-page controls disagree")
    return records, next(iter(set(enabled)), None)


def normalise(raw, *, release_id, observed_at, postcodes):
    number = raw["organisation_number"].strip()
    if not NUMBER.fullmatch(number):
        raise ValueError("invalid incorporation number")
    registered = raw.get("date_registered")
    removed = raw.get("date_removed")
    for label, value in (("registration", registered), ("removal", removed)):
        if value and not DATE.fullmatch(value):
            raise ValueError(f"invalid {label} date")
    postcode_match = re.search(r"\b([0-9]{4})\b", raw.get("registered_office_address") or "")
    postcode = postcode_match.group(1) if postcode_match else None
    assertions = [
        {"field": "entity_name", "value": raw["name"].strip()},
        # These canonical staging keys feed the existing jurisdiction-scoped
        # deterministic matcher after promotion. The native ID remains AU-NSW.
        {"field": "csv_incorporation_jurisdiction", "value": "NSW"},
        {"field": "csv_incorporation_number", "value": number},
        {"field": "nsw_association_status", "value": raw["status"].strip()},
    ]
    for field, value in (("nsw_association_type", raw.get("organisation_type")),
                         ("nsw_date_registered", registered), ("nsw_date_removed", removed),
                         ("nsw_registered_office_address", raw.get("registered_office_address"))):
        if value:
            assertions.append({"field": field, "value": value.strip()})
    reasons = ([f"registered office postcode {postcode}"] if postcode in postcodes
               else ["returned by configured postcode search; address postcode not exposed"])
    return {
        "source_id": SOURCE_ID, "resource_id": RESOURCE_ID, "release_id": release_id,
        "parser_version": PARSER_VERSION, "observed_at": observed_at,
        "native_id": f"AU-NSW:{number}", "raw": raw, "assertions": assertions,
        "selection": {"in_scope": True, "reasons": reasons},
    }


class NSWAssociationsExtractor:
    def __init__(self, fetch_initial, fetch_next, *, max_pages=20):
        if not 1 <= max_pages <= 100:
            raise ValueError("max_pages must be between 1 and 100")
        self.fetch_initial, self.fetch_next, self.max_pages = fetch_initial, fetch_next, max_pages

    def extract(self, *, postcodes, release_id, observed_at):
        if (not postcodes or len(postcodes) > 50 or postcodes != sorted(set(postcodes))
                or any(not re.fullmatch(r"[0-9]{4}", p) for p in postcodes)):
            raise ValueError("1 to 50 sorted unique ASCII postcodes are required")
        parsed_observed_at = datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
        if not release_id or parsed_observed_at.tzinfo is None:
            raise ValueError("release_id and timezone-aware observed_at are required")
        pages, candidates, errors, seen_ids, seen_pages = [], [], [], set(), set()
        target = None
        for page_number in range(1, self.max_pages + 1):
            try:
                html = (
                    self.fetch_initial(postcodes)
                    if page_number == 1 else self.fetch_next(target)
                )
                page_hash = hashlib.sha256(html.encode()).hexdigest()
                if page_hash in seen_pages:
                    raise ValueError("pagination repeated a previous page")
                seen_pages.add(page_hash)
                rows, target = parse_page(html)
                for raw in rows:
                    candidate = normalise(raw, release_id=release_id, observed_at=observed_at,
                                          postcodes=set(postcodes))
                    if candidate["native_id"] in seen_ids:
                        raise ValueError("duplicate incorporation number across result pages")
                    seen_ids.add(candidate["native_id"])
                    candidates.append(candidate)
                pages.append({"part_id": f"page-{page_number}", "ordinal": page_number,
                              "status": "complete", "sha256": page_hash,
                              "record_count": len(rows), "detail": {"next": bool(target)}})
                if not target:
                    break
            except (OSError, TypeError, ValueError) as exc:
                errors.append({"page": page_number, "message": str(exc)})
                pages.append({"part_id": f"page-{page_number}", "ordinal": page_number,
                              "status": "failed", "detail": {"message": str(exc)}})
                break
        else:
            errors.append({"page": self.max_pages + 1, "message": "page budget exhausted"})
            pages.append({"part_id": f"page-{self.max_pages + 1}", "ordinal": self.max_pages + 1,
                          "status": "failed", "detail": {"message": "page budget exhausted"}})
        complete = bool(pages) and pages[-1]["status"] == "complete" and not target and not errors
        return pages, candidates, errors, complete

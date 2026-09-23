"""Stream local ABN bulk-extract parts into the private registry-seed contract.

This command performs no download, database connection, triage, or publication. A
separately inventoried release supplies every expected local part and its SHA-256.
"""

import argparse
import gzip
import hashlib
import json
import os
import re
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree

from ingestion.registry_seed_sql import render

PARSER_VERSION = "abr-bulk-xml-v1"
CONFIG_VERSION = "abr-bulk-local-v1"
SOURCE_ID = "abr-bulk"
CHUNK_SIZE = 1024 * 1024
ABN = re.compile(r"[0-9]{11}")
POSTCODE = re.compile(r"[0-9]{4}")
SHA256 = re.compile(r"[0-9a-f]{64}")
TIMESTAMP = re.compile(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z")
ABN_WEIGHTS = (10, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19)
RECORD_CHILDREN = {
    "ABN",
    "EntityType",
    "MainEntity",
    "LegalEntity",
    "ASICNumber",
    "GST",
    "DGR",
    "OtherEntity",
}


class _SafeXMLStream:
    """Reject DTD/entity declarations while retaining streaming behaviour."""

    def __init__(self, stream):
        self.stream = stream
        self.tail = b""

    def read(self, size=-1):
        chunk = self.stream.read(size)
        inspected = (self.tail + chunk).replace(b"\x00", b"").upper()
        if b"<!DOCTYPE" in inspected or b"<!ENTITY" in inspected:
            raise ValueError("DTD and entity declarations are not supported")
        self.tail = inspected[-16:]
        return chunk


def _timestamp(value):
    if not isinstance(value, str) or not TIMESTAMP.fullmatch(value):
        raise ValueError("observed_at must be an RFC3339 UTC timestamp")
    datetime.fromisoformat(value.replace("Z", "+00:00"))


def _xml_timestamp(value):
    if not isinstance(value, str):
        raise ValueError("extract time must be an ISO 8601 timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("extract time must be an ISO 8601 timestamp") from exc
    # The published XSD uses xsd:dateTime, whose timezone is optional, and the
    # qualified real release omits it. Preserve and compare the provider literal;
    # never invent a timezone for source evidence.
    return parsed


def _required_text(obj, key):
    value = obj.get(key) if isinstance(obj, dict) else None
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"missing {key}")
    return value.strip()


def _validate_config(config):
    if not isinstance(config, dict) or config.get("config_version") != CONFIG_VERSION:
        raise ValueError("unsupported ABN bulk config")
    if config.get("source_id") != SOURCE_ID:
        raise ValueError(f"source_id must be {SOURCE_ID}")
    for key in [
        "resource_id",
        "release_id",
        "observed_at",
        "publisher",
        "attribution",
        "resource_list_url",
        "extract_time",
    ]:
        _required_text(config, key)
    _timestamp(config["observed_at"])
    _xml_timestamp(config["extract_time"])
    if not config["resource_list_url"].startswith("https://data.gov.au/"):
        raise ValueError("resource_list_url must identify the official data.gov.au inventory")
    licence = config.get("licence")
    for key in ["name", "url"]:
        _required_text(licence, key)
    scope = config.get("scope")
    _required_text(scope, "snapshot_series")
    postcodes = scope.get("postcodes") if isinstance(scope, dict) else None
    known_abns = scope.get("known_abns") if isinstance(scope, dict) else None
    if not isinstance(postcodes, list) or not isinstance(known_abns, list):
        raise ValueError("scope postcodes and known_abns must be arrays")
    if len(postcodes) > 500 or len(known_abns) > 10000:
        raise ValueError("configured selection exceeds the bounded limits")
    if any(not isinstance(value, str) or not POSTCODE.fullmatch(value) for value in postcodes):
        raise ValueError("postcodes must contain four ASCII digits")
    if any(not _valid_abn(value) for value in known_abns):
        raise ValueError("known_abns must contain valid eleven-digit ABNs")
    if len(set(postcodes)) != len(postcodes) or len(set(known_abns)) != len(known_abns):
        raise ValueError("scope selections must be unique")
    retention = config.get("retention")
    if not isinstance(retention, dict) or retention.get("class") not in {"hold", "scheduled"}:
        raise ValueError("invalid retention policy")
    _required_text(retention, "basis")
    if retention["class"] == "hold" and "raw_expires_at" in retention:
        raise ValueError("hold retention cannot set raw_expires_at")
    if retention["class"] == "scheduled":
        _timestamp(_required_text(retention, "raw_expires_at"))
        expiry = datetime.fromisoformat(retention["raw_expires_at"].replace("Z", "+00:00"))
        observed = datetime.fromisoformat(config["observed_at"].replace("Z", "+00:00"))
        if expiry <= observed:
            raise ValueError("raw expiry must follow the observation time")
    parts = config.get("parts")
    if not isinstance(parts, list) or not parts:
        raise ValueError("the release must inventory at least one part")
    expected_members = config.get("expected_member_count")
    if (
        not isinstance(expected_members, int)
        or isinstance(expected_members, bool)
        or expected_members <= 0
    ):
        raise ValueError("expected_member_count must be a positive integer")
    part_ids = set()
    ordinals = set()
    filenames = set()
    for part in parts:
        part_id = _required_text(part, "part_id")
        filename = _required_text(part, "filename")
        expected = _required_text(part, "sha256")
        ordinal = part.get("ordinal")
        if not isinstance(ordinal, int) or isinstance(ordinal, bool) or ordinal <= 0:
            raise ValueError("part ordinal must be a positive integer")
        if not SHA256.fullmatch(expected):
            raise ValueError("part sha256 must be lowercase hexadecimal")
        if Path(filename).is_absolute() or ".." in Path(filename).parts:
            raise ValueError("part filename must stay inside the input directory")
        if "member" in part and (not isinstance(part["member"], str) or not part["member"]):
            raise ValueError("zip member must be a non-empty string")
        if part_id in part_ids or ordinal in ordinals or filename in filenames:
            raise ValueError("part ids, ordinals, and filenames must be unique")
        part_ids.add(part_id)
        ordinals.add(ordinal)
        filenames.add(filename)
    if ordinals != set(range(1, len(parts) + 1)):
        raise ValueError("part ordinals must be contiguous from one")


def _digest_file(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK_SIZE):
            value.update(chunk)
    return value.hexdigest()


def _local_name(tag):
    return tag.rsplit("}", 1)[-1]


def _children(element, name):
    return [child for child in element if _local_name(child.tag) == name]


def _descendants(element, name):
    return [
        child
        for child in element.iter()
        if child is not element and _local_name(child.tag) == name
    ]


def _text(element, name, descendants=False):
    matches = _descendants(element, name) if descendants else _children(element, name)
    if not matches:
        return None
    value = "".join(matches[0].itertext()).strip()
    return value or None


def _date(value, label):
    if value in (None, ""):
        return None
    try:
        return datetime.strptime(value, "%Y%m%d").date().isoformat()
    except (TypeError, ValueError) as exc:
        raise ValueError(f"invalid {label} date {value!r}") from exc


def _valid_abn(value):
    if not isinstance(value, str) or not ABN.fullmatch(value):
        return False
    digits = [int(character) for character in value]
    digits[0] -= 1
    return sum(digit * weight for digit, weight in zip(digits, ABN_WEIGHTS)) % 89 == 0


def _raw(element):
    value = {f"@{_local_name(key)}": item for key, item in sorted(element.attrib.items())}
    for child in element:
        key = _local_name(child.tag)
        child_value = _raw(child)
        if key in value:
            if not isinstance(value[key], list):
                value[key] = [value[key]]
            value[key].append(child_value)
        else:
            value[key] = child_value
    text = (element.text or "").strip()
    if not value:
        return text
    if text:
        value["#text"] = text
    return value


def _name_and_location(record):
    main = next(iter(_children(record, "MainEntity")), None)
    legal = next(iter(_children(record, "LegalEntity")), None)
    owner = main if main is not None else legal
    if owner is None:
        raise ValueError("record has neither MainEntity nor LegalEntity")
    if main is not None:
        name = _text(main, "NonIndividualNameText", descendants=True)
    else:
        individual = next(iter(_descendants(legal, "IndividualName")), legal)
        parts = []
        for tag in ["NameTitle", "GivenName", "FamilyName"]:
            parts.extend(
                text
                for node in _descendants(individual, tag)
                if (text := " ".join(node.itertext()).strip())
            )
        name = " ".join(parts) or None
    if not name:
        raise ValueError("record has no legal or main entity name")
    address = next(iter(_descendants(owner, "AddressDetails")), None)
    state = _text(address, "State") if address is not None else None
    postcode = _text(address, "Postcode") if address is not None else None
    if address is None or state not in {
        None,
        "AAT",
        "QLD",
        "ACT",
        "NSW",
        "WA",
        "VIC",
        "NT",
        "TAS",
        "SA",
    }:
        raise ValueError("record has an invalid main business address")
    return name, state, postcode


def _validate_record(record):
    names = [_local_name(child.tag) for child in record]
    unknown = sorted(set(names) - RECORD_CHILDREN)
    if unknown:
        raise ValueError(f"unrecognised ABR record elements: {', '.join(unknown)}")
    for name in ["ABN", "EntityType"]:
        if names.count(name) != 1:
            raise ValueError(f"ABR record requires exactly one {name}")
    if names.count("MainEntity") + names.count("LegalEntity") != 1:
        raise ValueError("ABR record requires exactly one main or legal entity")
    for name in ["ASICNumber", "GST"]:
        if names.count(name) > 1:
            raise ValueError(f"ABR record has repeated {name}")
    if not record.attrib.get("recordLastUpdatedDate") or "replaced" not in record.attrib:
        raise ValueError("ABR record is missing required attributes")


def _candidate(record, common, postcodes, known_abns):
    _validate_record(record)
    abn_node = next(iter(_children(record, "ABN")), None)
    abn = "".join(abn_node.itertext()).strip() if abn_node is not None else ""
    if not _valid_abn(abn):
        raise ValueError(f"invalid ABN {abn!r}")
    if abn_node.attrib.get("status") not in {"ACT", "CAN"}:
        raise ValueError("invalid ABN status")
    name, state, postcode = _name_and_location(record)
    assertions = [{"field": "entity_name", "value": name}, {"field": "abn", "value": abn}]
    status = abn_node.attrib.get("status")
    status_from = _date(abn_node.attrib.get("ABNStatusFromDate"), "ABN status")
    if status or status_from:
        assertions.append(
            {"field": "abr_abn_status", "value": {"status": status, "from": status_from}}
        )
    updated = _date(record.attrib.get("recordLastUpdatedDate"), "record update")
    if updated:
        assertions.append({"field": "abr_record_last_updated_date", "value": updated})
    assertions.append({"field": "abr_replaced", "value": record.attrib["replaced"]})
    entity_type = next(iter(_children(record, "EntityType")), None)
    if entity_type is not None:
        entity_code = _text(entity_type, "EntityTypeInd")
        entity_text = _text(entity_type, "EntityTypeText")
        if not entity_code or not entity_text:
            raise ValueError("record has an incomplete entity type")
        assertions.append(
            {
                "field": "abr_entity_type",
                "value": {
                    "code": entity_code,
                    "text": entity_text,
                },
            }
        )
    if state or postcode:
        assertions.append(
            {"field": "abr_main_business_location", "value": {"state": state, "postcode": postcode}}
        )
    asic = _text(record, "ASICNumber")
    if asic:
        assertions.append({"field": "abr_asic_number", "value": asic})
        asic_node = next(iter(_children(record, "ASICNumber")))
        if asic_node.attrib.get("ASICNumberType"):
            assertions.append(
                {"field": "abr_asic_number_type", "value": asic_node.attrib["ASICNumberType"]}
            )
    gst = next(iter(_children(record, "GST")), None)
    if gst is not None:
        assertions.append(
            {
                "field": "abr_gst",
                "value": {
                    "status": gst.attrib.get("status"),
                    "from": _date(gst.attrib.get("GSTStatusFromDate"), "GST status"),
                },
            }
        )
    other_names = []
    for other in _children(record, "OtherEntity"):
        node = next(iter(_descendants(other, "NonIndividualName")), None)
        name_text = _text(other, "NonIndividualNameText", descendants=True)
        if node is None or not name_text or not node.attrib.get("type"):
            raise ValueError("record has an incomplete other entity name")
        other_names.append({"type": node.attrib["type"], "name": name_text})
    if other_names:
        assertions.append({"field": "abr_other_names", "value": other_names})
    dgr_values = []
    for dgr in _children(record, "DGR"):
        dgr_values.append(
            {
                "status": dgr.attrib.get("status"),
                "from": _date(dgr.attrib.get("DGRStatusFromDate"), "DGR status"),
                "name": _text(dgr, "NonIndividualNameText", descendants=True),
                "type": (
                    next(iter(_descendants(dgr, "NonIndividualName")), None).attrib.get("type")
                    if _descendants(dgr, "NonIndividualName")
                    else None
                ),
            }
        )
    if dgr_values:
        assertions.append({"field": "abr_dgr", "value": dgr_values})
    reasons = []
    if postcode in postcodes:
        reasons.append(f"main business postcode {postcode}")
    if abn in known_abns:
        reasons.append("explicitly known ABN")
    if not reasons:
        return None
    return {
        **common,
        "native_id": abn,
        "raw": _raw(record),
        "assertions": assertions,
        "selection": {"in_scope": True, "reasons": reasons},
    }


def _parse_stream(stream, common, postcodes, known_abns):
    stream = _SafeXMLStream(stream)
    candidates = []
    record_count = 0
    root = None
    root_error = None
    root_has_error_attribute = False
    transfer_info = None
    transfer_info_count = 0
    try:
        for event, element in ElementTree.iterparse(stream, events=("start", "end")):
            if root is None:
                root = element
                root_error = element.attrib.get("error", "")
                root_has_error_attribute = "error" in element.attrib
            if event == "end" and _local_name(element.tag) == "TransferInfo":
                transfer_info_count += 1
                try:
                    transfer_info = {
                        "sequence": int(_text(element, "FileSequenceNumber")),
                        "declared_record_count": int(_text(element, "RecordCount")),
                        "extract_time": _text(element, "ExtractTime"),
                    }
                except (TypeError, ValueError) as exc:
                    raise ValueError("invalid TransferInfo") from exc
                if transfer_info["sequence"] <= 0 or transfer_info["declared_record_count"] < 0:
                    raise ValueError("invalid TransferInfo counts")
            if event == "end" and _local_name(element.tag) == "ABR":
                record_count += 1
                candidate = _candidate(element, common, postcodes, known_abns)
                if candidate is not None:
                    candidates.append(candidate)
                element.clear()
                if root is not element:
                    root.clear()
    except ElementTree.ParseError as exc:
        raise ValueError(f"invalid XML: {exc}") from exc
    if root is None or record_count == 0:
        raise ValueError("XML part contains no ABR records")
    if (
        _local_name(root.tag) != "Transfer"
        or not root_has_error_attribute
        or root_error not in {"", "none"}
    ):
        raise ValueError("invalid Transfer envelope or source-reported error")
    if (
        transfer_info_count != 1
        or transfer_info is None
        or transfer_info["declared_record_count"] != record_count
    ):
        raise ValueError("TransferInfo record count does not match parsed ABR records")
    _xml_timestamp(transfer_info["extract_time"])
    return record_count, candidates, transfer_info


def _parse_part(path, part, common, postcodes, known_abns):
    suffix = path.suffix.lower()
    record_count = 0
    candidates = []
    members = []
    if suffix == ".zip":
        with zipfile.ZipFile(path) as archive:
            files = [
                info
                for info in archive.infolist()
                if not info.is_dir() and info.filename.lower().endswith(".xml")
            ]
            member = part.get("member")
            if member:
                files = [info for info in files if info.filename == member]
            if not files or len({info.filename for info in files}) != len(files):
                raise ValueError("ZIP part must contain uniquely named XML members")
            for info in sorted(files, key=lambda value: value.filename):
                if info.flag_bits & 0x1:
                    raise ValueError("encrypted ZIP members are not supported")
                with archive.open(info) as stream:
                    count, selected, transfer = _parse_stream(stream, common, postcodes, known_abns)
                record_count += count
                candidates.extend(selected)
                members.append({"name": info.filename, "record_count": count, **transfer})
    elif suffix == ".gz":
        with gzip.open(path, "rb") as stream:
            count, candidates, transfer = _parse_stream(stream, common, postcodes, known_abns)
        record_count = count
        members.append({"name": path.name.removesuffix(".gz"), "record_count": count, **transfer})
    elif suffix == ".xml":
        with path.open("rb") as stream:
            count, candidates, transfer = _parse_stream(stream, common, postcodes, known_abns)
        record_count = count
        members.append({"name": path.name, "record_count": count, **transfer})
    else:
        raise ValueError("part must be XML, gzip-compressed XML, or ZIP containing XML")
    return record_count, candidates, members


def _checkpoint_key(config):
    selection = {
        "release_id": config["release_id"],
        "resource_id": config["resource_id"],
        "parser_version": PARSER_VERSION,
        "extract_time": config["extract_time"],
        "expected_member_count": config["expected_member_count"],
        "postcodes": sorted(config["scope"]["postcodes"]),
        "known_abns": sorted(config["scope"]["known_abns"]),
    }
    encoded = json.dumps(selection, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def _load_checkpoint(path, part, file_hash, key):
    if path is None or not path.exists():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    if (
        value.get("checkpoint_version") != "abr-bulk-part-v1"
        or value.get("part_id") != part["part_id"]
        or value.get("sha256") != file_hash
        or value.get("selection_sha256") != key
        or not isinstance(value.get("record_count"), int)
        or not isinstance(value.get("candidates"), list)
    ):
        return None
    return value


def _write_checkpoint(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, separators=(",", ":"))
            stream.write("\n")
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def extract_release(config, input_dir, checkpoint_dir=None):
    _validate_config(config)
    input_dir = Path(input_dir).resolve()
    checkpoint_dir = Path(checkpoint_dir) if checkpoint_dir is not None else None
    postcodes = set(config["scope"]["postcodes"])
    known_abns = set(config["scope"]["known_abns"])
    common = {
        "source_id": SOURCE_ID,
        "resource_id": config["resource_id"],
        "release_id": config["release_id"],
        "parser_version": PARSER_VERSION,
        "observed_at": config["observed_at"],
    }
    checkpoint_key = _checkpoint_key(config)
    inventory = []
    errors = []
    candidates = []
    for part in sorted(config["parts"], key=lambda value: value["ordinal"]):
        path = input_dir / part["filename"]
        failed = {
            "part_id": part["part_id"],
            "ordinal": part["ordinal"],
            "status": "failed",
            "expected_sha256": part["sha256"],
            "detail": {"filename": part["filename"]},
        }
        if not path.is_file():
            inventory.append(failed)
            errors.append({"part_id": part["part_id"], "message": "expected part is missing"})
            continue
        observed_hash = _digest_file(path)
        if observed_hash != part["sha256"]:
            failed["detail"]["observed_sha256"] = observed_hash
            inventory.append(failed)
            errors.append(
                {"part_id": part["part_id"], "message": "part SHA-256 does not match inventory"}
            )
            continue
        checkpoint_path = (
            checkpoint_dir / f"{part['ordinal']:03d}-{part['part_id']}.json"
            if checkpoint_dir is not None
            else None
        )
        checkpoint = _load_checkpoint(checkpoint_path, part, observed_hash, checkpoint_key)
        try:
            if checkpoint is None:
                record_count, selected, members = _parse_part(
                    path, part, common, postcodes, known_abns
                )
                checkpoint = {
                    "checkpoint_version": "abr-bulk-part-v1",
                    "part_id": part["part_id"],
                    "sha256": observed_hash,
                    "selection_sha256": checkpoint_key,
                    "record_count": record_count,
                    "members": members,
                    "candidates": selected,
                }
                if checkpoint_path is not None:
                    _write_checkpoint(checkpoint_path, checkpoint)
                reused = False
            else:
                record_count = checkpoint["record_count"]
                selected = checkpoint["candidates"]
                members = checkpoint.get("members")
                if not isinstance(members, list):
                    raise ValueError("checkpoint has no XML member inventory")
                reused = True
        except (OSError, ValueError, zipfile.BadZipFile) as exc:
            failed["detail"]["observed_sha256"] = observed_hash
            inventory.append(failed)
            errors.append({"part_id": part["part_id"], "message": str(exc)})
            continue
        inventory.append(
            {
                "part_id": part["part_id"],
                "ordinal": part["ordinal"],
                "status": "complete",
                "expected_sha256": part["sha256"],
                "sha256": observed_hash,
                "record_count": record_count,
                "detail": {
                    "filename": part["filename"],
                    "members": members,
                    "selected_count": len(selected),
                    "checkpoint_reused": reused,
                },
            }
        )
        candidates.extend(selected)

    member_inventory = [
        member
        for part in inventory
        if part["status"] == "complete"
        for member in part["detail"]["members"]
    ]
    sequences = [member["sequence"] for member in member_inventory]
    if len(member_inventory) != config["expected_member_count"] or sorted(sequences) != list(
        range(1, config["expected_member_count"] + 1)
    ):
        errors.append({"message": "XML member sequence inventory is incomplete or duplicated"})
    expected_extract_time = _xml_timestamp(config["extract_time"])
    if any(
        _xml_timestamp(member["extract_time"]) != expected_extract_time
        for member in member_inventory
    ):
        errors.append({"message": "XML members do not belong to the configured extract time"})

    unique = {}
    duplicate_ids = set()
    for candidate in candidates:
        native_id = candidate["native_id"]
        if native_id in unique:
            duplicate_ids.add(native_id)
        else:
            unique[native_id] = candidate
    if duplicate_ids:
        errors.append(
            {
                "message": "duplicate ABNs occurred across release parts",
                "native_ids": sorted(duplicate_ids),
            }
        )
    candidates = [
        candidate for native_id, candidate in unique.items() if native_id not in duplicate_ids
    ]
    complete = len(inventory) == len(config["parts"]) and all(
        part["status"] == "complete" for part in inventory
    ) and not errors
    manifest = {
        "contract_version": "registry-seed-v1",
        **common,
        "completion": "complete" if complete else "partial",
        "scope": {
            "kind": "configured-registry-scope",
            "complete_snapshot": complete,
            "snapshot_series": config["scope"]["snapshot_series"],
            "selection": {
                "postcodes": sorted(postcodes),
                "known_abns": sorted(known_abns),
            },
        },
        "parts": inventory,
        "errors": errors,
        "retention": config["retention"],
        "source": {
            "publisher": config["publisher"],
            "attribution": config["attribution"],
            "licence": config["licence"],
            "resource_list_url": config["resource_list_url"],
        },
    }
    return manifest, candidates


def _exclusive_write(path, value, json_value=False):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    with os.fdopen(os.open(path, flags, 0o600), "w", encoding="utf-8") as stream:
        if json_value:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        else:
            stream.write(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--input-dir", required=True, type=Path)
    parser.add_argument("--checkpoint-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text(encoding="utf-8"))
        manifest, candidates = extract_release(config, args.input_dir, args.checkpoint_dir)
        args.output_dir.mkdir(mode=0o700, parents=False, exist_ok=False)
        _exclusive_write(args.output_dir / "manifest.json", manifest, json_value=True)
        _exclusive_write(args.output_dir / "candidates.json", candidates, json_value=True)
        _exclusive_write(args.output_dir / "stage.sql", render(manifest, candidates))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        parser.exit(2, f"ABN bulk release rejected: {exc}\n")
    print(
        f"{manifest['completion']}: {len(candidates)} candidates from "
        f"{sum(part.get('record_count', 0) for part in manifest['parts'])} records"
    )
    return 0 if manifest["completion"] == "complete" else 1


if __name__ == "__main__":
    raise SystemExit(main())

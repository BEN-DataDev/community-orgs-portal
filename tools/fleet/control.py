from __future__ import annotations

import hashlib
import json
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


SCHEMA = """
pragma foreign_keys = on;
create table if not exists portals (
  portal_id text primary key,
  portal_key text not null unique,
  manifest_hash text not null,
  provider_adapter text not null,
  provider_region text not null,
  application_version text not null,
  expected_schema_version text not null,
  lifecycle text not null default 'registered',
  observed_schema_version text,
  observed_portal_id text,
  health text not null default 'unknown',
  last_operation_id text,
  updated_at text not null
);
create table if not exists credential_refs (
  portal_id text not null references portals(portal_id),
  credential text not null,
  secret_ref text not null,
  revision integer not null,
  verified_at text not null,
  operation_id text not null,
  primary key (portal_id, credential)
);
create table if not exists operations (
  sequence integer primary key autoincrement,
  operation_id text not null unique,
  portal_id text not null,
  portal_key text not null,
  operation text not null,
  operator text not null,
  purpose text not null,
  capability text not null,
  started_at text not null,
  finished_at text not null,
  result text not null check(result in ('succeeded','failed')),
  affected_version text,
  details text not null,
  previous_hash text,
  event_hash text not null unique
);
create trigger if not exists operations_no_update
before update on operations begin select raise(abort, 'operation records are append-only'); end;
create trigger if not exists operations_no_delete
before delete on operations begin select raise(abort, 'operation records are append-only'); end;
"""


class ControlPlane:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)
        self._operation_active = False

    def close(self) -> None:
        self.db.close()

    def sync_manifest(self, manifest_hash: str, portal: dict[str, Any], application_version: str) -> None:
        existing = self.db.execute(
            "select portal_id, portal_key from portals where portal_id=? or portal_key=?",
            (portal["portal_id"], portal["portal_key"]),
        ).fetchone()
        if existing and (existing["portal_id"] != portal["portal_id"] or existing["portal_key"] != portal["portal_key"]):
            raise ValueError("A registered portal identity or key cannot be repurposed")
        self.db.execute(
            """insert into portals(portal_id,portal_key,manifest_hash,provider_adapter,
                 provider_region,application_version,expected_schema_version,updated_at)
               values(?,?,?,?,?,?,?,?)
               on conflict(portal_id) do update set manifest_hash=excluded.manifest_hash,
                 provider_adapter=excluded.provider_adapter,provider_region=excluded.provider_region,
                 application_version=excluded.application_version,
                 expected_schema_version=excluded.expected_schema_version,updated_at=excluded.updated_at""",
            (portal["portal_id"], portal["portal_key"], manifest_hash,
             portal["provider"]["adapter"], portal["provider"]["region"],
             application_version, portal["schema_version"], utc_now()),
        )
        if not self._operation_active:
            self.db.commit()

    def update_observation(self, portal_id: str, operation_id: str, *, lifecycle: str | None = None,
                           schema_version: str | None = None, observed_portal_id: str | None = None,
                           health: str | None = None) -> None:
        current = self.db.execute("select * from portals where portal_id=?", (portal_id,)).fetchone()
        if not current:
            raise ValueError("Portal is not registered")
        self.db.execute(
            """update portals set lifecycle=?,observed_schema_version=?,observed_portal_id=?,
                 health=?,last_operation_id=?,updated_at=? where portal_id=?""",
            (lifecycle or current["lifecycle"], schema_version or current["observed_schema_version"],
             observed_portal_id or current["observed_portal_id"], health or current["health"],
             operation_id, utc_now(), portal_id),
        )
        if not self._operation_active:
            self.db.commit()

    def rotate_ref(self, portal_id: str, credential: str, secret_ref: str, operation_id: str) -> int:
        old = self.db.execute(
            "select secret_ref,revision from credential_refs where portal_id=? and credential=?",
            (portal_id, credential),
        ).fetchone()
        if old and old["secret_ref"] == secret_ref:
            raise ValueError("Rotation requires a new versioned secret reference")
        revision = (old["revision"] if old else 0) + 1
        self.db.execute(
            """insert into credential_refs values(?,?,?,?,?,?)
               on conflict(portal_id,credential) do update set secret_ref=excluded.secret_ref,
                 revision=excluded.revision,verified_at=excluded.verified_at,
                 operation_id=excluded.operation_id""",
            (portal_id, credential, secret_ref, revision, utc_now(), operation_id),
        )
        if not self._operation_active:
            self.db.commit()
        return revision

    def _append_operation(self, record: dict[str, Any]) -> None:
        previous = self.db.execute("select event_hash from operations order by sequence desc limit 1").fetchone()
        record["previous_hash"] = previous[0] if previous else None
        event_hash = hashlib.sha256(canonical(record).encode()).hexdigest()
        self.db.execute(
            """insert into operations(operation_id,portal_id,portal_key,operation,operator,purpose,
               capability,started_at,finished_at,result,affected_version,details,previous_hash,event_hash)
               values(?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (record["operation_id"], record["portal_id"], record["portal_key"], record["operation"],
             record["operator"], record["purpose"], record["capability"], record["started_at"],
             record["finished_at"], record["result"], record["affected_version"],
             canonical(record["details"]), record["previous_hash"], event_hash),
        )

    @contextmanager
    def operation(self, portal: dict[str, Any], operation: str, operator: str, purpose: str,
                  capability: str = "fleet_operator") -> Iterator[tuple[str, dict[str, Any]]]:
        if not operator.strip() or not purpose.strip():
            raise ValueError("Operator and purpose/incident reference are required")
        operation_id = str(uuid.uuid4())
        started = utc_now()
        details: dict[str, Any] = {}
        if self._operation_active:
            raise RuntimeError("Nested fleet operations are not supported")
        self._operation_active = True
        self.db.execute("begin")
        try:
            yield operation_id, details
        except Exception as exc:
            self.db.rollback()
            details.setdefault("error", str(exc))
            record = {
                "operation_id": operation_id, "portal_id": portal["portal_id"],
                "portal_key": portal["portal_key"], "operation": operation,
                "operator": operator.strip(), "purpose": purpose.strip(), "capability": capability,
                "started_at": started, "finished_at": utc_now(), "result": "failed",
                "affected_version": portal.get("schema_version"), "details": details,
                "previous_hash": None,
            }
            self._append_operation(record)
            self.db.commit()
            raise
        else:
            record = {
                "operation_id": operation_id, "portal_id": portal["portal_id"],
                "portal_key": portal["portal_key"], "operation": operation,
                "operator": operator.strip(), "purpose": purpose.strip(), "capability": capability,
                "started_at": started, "finished_at": utc_now(), "result": "succeeded",
                "affected_version": portal.get("schema_version"), "details": details,
                "previous_hash": None,
            }
            self._append_operation(record)
            self.db.commit()
        finally:
            self._operation_active = False

    def inventory(self) -> list[dict[str, Any]]:
        return [dict(row) for row in self.db.execute("select * from portals order by portal_key")]

    def export(self) -> dict[str, Any]:
        operations = [dict(row) for row in self.db.execute("select * from operations order by sequence")]
        credentials = [dict(row) for row in self.db.execute(
            "select portal_id,credential,secret_ref,revision,verified_at,operation_id from credential_refs order by portal_id,credential"
        )]
        previous = None
        valid = True
        for row in operations:
            details = json.loads(row["details"])
            expected = {key: row[key] for key in (
                "operation_id", "portal_id", "portal_key", "operation", "operator", "purpose",
                "capability", "started_at", "finished_at", "result", "affected_version"
            )}
            expected["details"] = details
            expected["previous_hash"] = previous
            digest = hashlib.sha256(canonical(expected).encode()).hexdigest()
            valid = valid and row["previous_hash"] == previous and row["event_hash"] == digest
            previous = row["event_hash"]
            row["details"] = details
        return {"exported_at": utc_now(), "chain_valid": valid, "portals": self.inventory(),
                "credential_references": credentials, "operations": operations}

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any


class PostgresAdapter:
    def __init__(self, portal: dict[str, Any]):
        self.portal = portal
        provider = portal["provider"]
        self.adapter = provider["adapter"]
        if self.adapter == "docker_postgres":
            self.prefix = ["docker", "exec", "-i", provider["container"], "psql", "-X", "-q",
                           "-v", "ON_ERROR_STOP=1", "-U", provider.get("user", "postgres"),
                           "-d", provider["database"]]
            self.env = None
        else:
            ref = provider["connection_secret_ref"]
            if not ref.startswith("env:"):
                raise ValueError("This CLI build resolves env: database references; use an external resolver for other stores")
            variable = ref.removeprefix("env:")
            url = os.environ.get(variable)
            if not url:
                raise ValueError(f"Required connection secret environment variable {variable} is not set")
            self.prefix = [provider.get("psql", "psql"), "-X", "-q", "-v", "ON_ERROR_STOP=1", url]
            self.env = {**os.environ, "PGAPPNAME": "community-orgs-fleet"}

    def sql(self, sql: str, *, tuples: bool = False) -> str:
        command = [*self.prefix]
        if tuples:
            command.extend(["-A", "-t"])
        result = subprocess.run(command, input=sql, text=True, capture_output=True, env=self.env, timeout=180)
        if result.returncode:
            message = result.stderr.strip().splitlines()
            raise RuntimeError(message[-1] if message else "PostgreSQL operation failed")
        return result.stdout.strip()

    def prepare_tracking(self) -> None:
        self.sql("""create schema if not exists supabase_migrations;
          revoke all on schema supabase_migrations from public;
          create table if not exists supabase_migrations.schema_migrations(
            version text primary key, statements text[], name text);
          revoke all on supabase_migrations.schema_migrations from public;""")

    def applied_versions(self) -> set[str]:
        self.prepare_tracking()
        output = self.sql("select version from supabase_migrations.schema_migrations order by version", tuples=True)
        return set(output.splitlines()) if output else set()

    def apply_migrations(self, migration_dir: Path, target_version: str) -> list[str]:
        applied = self.applied_versions()
        completed: list[str] = []
        for path in sorted(migration_dir.glob("*.sql")):
            version = path.name.split("_", 1)[0]
            if version > target_version:
                continue
            if version in applied:
                continue
            name = path.stem.removeprefix(version + "_")
            escaped_name = name.replace("'", "''")
            script = ("begin;\n" + path.read_text() + "\ninsert into supabase_migrations.schema_migrations"
                      f"(version,name) values('{version}','{escaped_name}');\ncommit;")
            self.sql(script)
            completed.append(version)
        return completed

    def establish(self) -> None:
        p = self.portal
        values = [p[key].replace("'", "''") for key in
                  ("portal_key", "display_name", "short_name", "sponsor_name", "establishment_reason")]
        self.sql(f"""insert into portal.configuration(
          portal_id,portal_key,display_name,short_name,sponsor_name,establishment_reason)
          values('{p['portal_id']}','{values[0]}','{values[1]}','{values[2]}','{values[3]}','{values[4]}')
          on conflict(singleton) do nothing;
          do $$ begin
            if not exists(select 1 from portal.configuration where portal_id='{p['portal_id']}'
              and portal_key='{values[0]}') then
              raise exception 'Database is already bound to another portal';
            end if;
          end $$;""")

    def bootstrap_administrator(self) -> str | None:
        user_id = self.portal.get("first_administrator_user_id")
        if not user_id:
            return None
        reason = self.portal.get("first_administrator_reason", "Initial fleet bootstrap").replace("'", "''")
        reference = self.portal.get("first_administrator_reference", "fleet-manifest").replace("'", "''")
        self.sql(f"""do $$ begin
          if not exists(select 1 from auth.users where id='{user_id}') then
            raise exception 'First administrator account does not exist in auth.users';
          end if;
          if not exists(select 1 from portal.capability_appointments a
            where a.user_id='{user_id}' and a.capability='portal_administrator'
              and not exists(select 1 from portal.capability_appointment_events e
                where e.appointment_id=a.appointment_id and e.event_type='revoked')) then
            insert into portal.capability_appointments(user_id,capability,appointed_by,reason,
              approval_reference,origin) values('{user_id}','portal_administrator',null,
              '{reason}','{reference}','bootstrap');
          end if;
        end $$;""")
        return user_id

    def health(self) -> dict[str, str]:
        row = self.sql("""select c.portal_id::text || '|' || c.portal_key || '|' || c.lifecycle_state::text
          from portal.configuration c where c.singleton""", tuples=True)
        if not row:
            raise RuntimeError("Portal identity is not established")
        portal_id, portal_key, lifecycle = row.split("|", 2)
        versions = sorted(self.applied_versions())
        return {"portal_id": portal_id, "portal_key": portal_key, "lifecycle": lifecycle,
                "schema_version": versions[-1] if versions else "unversioned"}

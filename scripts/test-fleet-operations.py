"""Exercise the fleet adapter against two isolated disposable portal databases."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.fleet.control import ControlPlane
from tools.fleet.provider import PostgresAdapter


NAME = "portal-fleet-" + uuid.uuid4().hex[:10]
ADMIN_ONE = "00000000-0000-4000-8000-000000000101"
ADMIN_TWO = "00000000-0000-4000-8000-000000000102"
MIGRATION = """
create schema auth;
create schema portal;
create type portal.capability as enum ('portal_administrator', 'data_steward');
create table auth.users(id uuid primary key);
insert into auth.users values
 ('00000000-0000-4000-8000-000000000101'),
 ('00000000-0000-4000-8000-000000000102');
create table portal.configuration(
 singleton boolean primary key default true check(singleton), portal_id uuid unique not null,
 portal_key text unique not null, display_name text not null, short_name text not null,
 sponsor_name text not null, establishment_reason text not null,
 lifecycle_state text not null default 'planned');
create table portal.capability_appointments(
 appointment_id uuid primary key default gen_random_uuid(), user_id uuid references auth.users not null,
 capability portal.capability not null, appointed_by uuid references auth.users,
 reason text not null, approval_reference text not null, origin text not null);
create table portal.capability_appointment_events(
 event_id bigint generated always as identity primary key,
 appointment_id uuid references portal.capability_appointments not null,
 event_type text not null default 'issued');
create function portal.record_issue() returns trigger language plpgsql as $$ begin
 insert into portal.capability_appointment_events(appointment_id) values(new.appointment_id); return new; end $$;
create trigger appointment_issue after insert on portal.capability_appointments
 for each row execute function portal.record_issue();
"""


def command(args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr[-4000:])
    return result.stdout


def portal(key, suffix, database, administrator):
    return {
        "portal_id": f"10000000-0000-4000-8000-{suffix:012d}",
        "portal_key": key,
        "display_name": key.title(), "short_name": key.title(),
        "sponsor_name": "Fleet Acceptance Sponsor",
        "establishment_reason": "Fleet isolation acceptance",
        "schema_version": "20260925020000",
        "first_administrator_user_id": administrator,
        "first_administrator_reason": "Fleet acceptance bootstrap",
        "first_administrator_reference": "TEST-FLEET-1",
        "provider": {"adapter": "docker_postgres", "region": "isolated-test",
                     "container": NAME, "database": database, "user": "postgres"},
        "credentials": {"bootstrap": f"vault:test/{key}/bootstrap@1"},
    }


try:
    command(["docker", "run", "--pull=never", "-d", "--name", NAME, "--network=none",
             "-e", "POSTGRES_HOST_AUTH_METHOD=trust", "postgis/postgis:17-3.5"])
    for _ in range(100):
        if subprocess.run(["docker", "exec", NAME, "pg_isready", "-U", "postgres"],
                          capture_output=True).returncode == 0:
            break
        time.sleep(0.2)
    else:
        raise RuntimeError("Disposable fleet database did not start")
    # The image briefly accepts connections in its init server, then restarts
    # PostgreSQL. Wait for that handoff before creating the isolated databases.
    time.sleep(3)
    command(["docker", "exec", NAME, "pg_isready", "-U", "postgres"])
    command(["docker", "exec", NAME, "createdb", "-U", "postgres", "-T", "template0", "portal_one"])
    command(["docker", "exec", NAME, "createdb", "-U", "postgres", "-T", "template0", "portal_two"])

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        migrations = root / "migrations"
        migrations.mkdir()
        (migrations / "20260925020000_fleet_acceptance.sql").write_text(MIGRATION)
        one = portal("fleet-one", 201, "portal_one", ADMIN_ONE)
        two = portal("fleet-two", 202, "portal_two", ADMIN_TWO)
        control = ControlPlane(root / "control.sqlite3")
        try:
            for item in (one, two):
                control.sync_manifest("f" * 64, item, "acceptance")
            adapter_one = PostgresAdapter(one)
            with control.operation(one, "provision", "fleet-test", "TEST-FLEET-1") as (op, details):
                details["applied_migrations"] = adapter_one.apply_migrations(migrations, one["schema_version"])
                adapter_one.establish()
                details["administrator"] = adapter_one.bootstrap_administrator()
                health = adapter_one.health()
                control.update_observation(one["portal_id"], op, lifecycle=health["lifecycle"],
                                           schema_version=health["schema_version"],
                                           observed_portal_id=health["portal_id"], health="healthy")
            first_before = adapter_one.sql(
                "select portal_id::text||'|'||portal_key from portal.configuration", tuples=True)

            adapter_two = PostgresAdapter(two)
            with control.operation(two, "provision", "fleet-test", "TEST-FLEET-2") as (op, details):
                details["applied_migrations"] = adapter_two.apply_migrations(migrations, two["schema_version"])
                adapter_two.establish()
                details["administrator"] = adapter_two.bootstrap_administrator()
                health = adapter_two.health()
                control.update_observation(two["portal_id"], op, lifecycle=health["lifecycle"],
                                           schema_version=health["schema_version"],
                                           observed_portal_id=health["portal_id"], health="healthy")

            assert adapter_one.sql("select portal_id::text||'|'||portal_key from portal.configuration", tuples=True) == first_before
            assert adapter_one.sql("select count(*) from portal.capability_appointments", tuples=True) == "1"
            assert adapter_two.sql("select count(*) from portal.capability_appointments", tuples=True) == "1"
            assert adapter_one.sql("select count(*) from portal.capability_appointment_events", tuples=True) == "1"
            assert adapter_two.sql("select count(*) from portal.capability_appointment_events", tuples=True) == "1"
            with control.operation(two, "rotate_credential", "fleet-test", "TEST-FLEET-3") as (op, details):
                revision = control.rotate_ref(two["portal_id"], "bootstrap", "vault:test/fleet-two/bootstrap@2", op)
                details.update({"credential": "bootstrap", "revision": revision, "secret_value_stored": False})
            package = control.export()
            assert package["chain_valid"] and len(package["portals"]) == 2
            assert package["portals"][0]["observed_portal_id"] != package["portals"][1]["observed_portal_id"]
            print(json.dumps({"portals": 2, "schema_version": "20260925020000",
                              "first_portal_unchanged": True, "administrators": 2,
                              "credential_rotation_revision": revision,
                              "operation_chain_valid": package["chain_valid"]}, sort_keys=True))
        finally:
            control.close()
finally:
    subprocess.run(["docker", "rm", "-f", NAME], capture_output=True)

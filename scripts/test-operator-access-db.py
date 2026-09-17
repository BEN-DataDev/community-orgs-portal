"""Run P07 against real portal/access/ingestion migrations in disposable PostGIS.

No host ports, mounts, credentials or external database URLs. Only auth users,
factors and JWT helpers are emulated; capability functions and RLS are unmodified.
Requires the locally available postgis/postgis:17-3.5 image. Removes its container.
"""
from pathlib import Path
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
NAME = 'portal-p07-' + uuid.uuid4().hex[:10]


def command(args, input=None):
    result = subprocess.run(args, input=input, text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(f'{args[:3]} failed:\n{result.stderr[-6000:]}\n{result.stdout[-1000:]}')
    return result.stdout


try:
    command(['docker', 'run', '--pull=never', '-d', '--name', NAME, '--network=none',
             '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgis/postgis:17-3.5'])
    for _ in range(100):
        result = subprocess.run(['docker', 'exec', NAME, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres'], capture_output=True)
        if result.returncode == 0:
            break
        time.sleep(0.2)
    else:
        raise RuntimeError('Disposable database did not start')
    # A fresh database avoids the image's preinstalled public-schema PostGIS.
    command(['docker', 'exec', NAME, 'createdb', '-U', 'postgres', '-T', 'template0', 'p07'])

    def sql(query):
        return command(['docker', 'exec', '-i', NAME, 'psql', '-U', 'postgres', '-d', 'p07',
                        '-X', '-q', '-v', 'ON_ERROR_STOP=1'], input=query)

    sql('''create role anon; create role authenticated; create role service_role;
      create schema auth; create schema extensions;
      create table auth.users(id uuid primary key, email text, is_anonymous boolean default false,
        created_at timestamptz, updated_at timestamptz);
      create table auth.mfa_factors(id uuid primary key default gen_random_uuid(),
        user_id uuid references auth.users, status text);
      create function auth.jwt() returns jsonb language sql as $$
        select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
      create function auth.uid() returns uuid language sql as $$ select (auth.jwt()->>'sub')::uuid $$;
      grant usage on schema auth to anon,authenticated,service_role;
    ''')
    # Account storage, sessions, orphan public tables and hosted extensions are
    # unrelated to this boundary; do not substitute simplified organisation RLS.
    excluded = {
        '20260905031452_drop_unsupported_pgjwt_extension.sql',
        '20260905033816_enable_rls_on_orphan_public_tables.sql',
        '20260913033010_enable_pg_graphql_extension.sql',
        '20260914223810_persistent_account_avatars.sql',
        '20260915035236_account_session_management.sql',
    }
    migrations = [p for p in sorted((ROOT / 'supabase/migrations').glob('*.sql')) if p.name not in excluded]
    for path in migrations:
        sql(path.read_text())
    print(f'Applied {len(migrations)} unmodified portal/access/ingestion migrations.', flush=True)
    for name in ['p2_admin_access_regression.sql', 'platform_administrators.sql',
                 'operator_access.sql', 'ingestion_review.sql', 'ingestion_publication.sql']:
        print(sql((ROOT / 'supabase/tests' / name).read_text()).strip(), flush=True)
        print(f'{name}: passed', flush=True)
finally:
    subprocess.run(['docker', 'rm', '-f', NAME], capture_output=True)

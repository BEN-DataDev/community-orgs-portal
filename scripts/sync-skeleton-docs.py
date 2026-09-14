"""Mirror the Svelte pages listed in Skeleton's official LLM index (Python 3.10+)."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'docs' / 'vendor' / 'skeleton'
ORIGIN = 'https://www.skeleton.dev'
INDEX_URL = ORIGIN + '/llms.txt'
LINK = re.compile(r'\[([^\]]+)\]\((/docs/svelte/[a-z0-9/-]+\.md)\)')


def fetch(url):
    with urlopen(url, timeout=30) as response:
        content_type = response.headers.get('Content-Type', '')
        if 'text/plain' not in content_type and 'text/markdown' not in content_type:
            raise ValueError(f'Expected Markdown or plain text from {url}: {content_type}')
        text = response.read().decode('utf-8')
        if not text.lstrip().startswith('#'):
            raise ValueError(f'Missing Markdown heading in {url}')
        return text


def main():
    upstream_index = fetch(INDEX_URL)
    match = re.search(r'^## Svelte\s*\n(.*?)(?=^## |\Z)', upstream_index, re.M | re.S)
    if not match:
        raise ValueError('Official index no longer contains a Svelte section')
    section = match.group(1)
    links = dict((path, title) for title, path in LINK.findall(section))
    migration = '/docs/svelte/get-started/migrate-from-v4.md'
    if migration not in links:
        raise ValueError('Index is no longer the expected Skeleton v5 documentation; review before updating')

    # Fetch everything before changing the snapshot. A failed request leaves it intact.
    with ThreadPoolExecutor(max_workers=6) as pool:
        pages = dict(zip(links, pool.map(lambda path: fetch(ORIGIN + path), links)))
    if 'latest v5 release' not in pages[migration]:
        raise ValueError('Migration guide no longer identifies v5; review before updating')

    fetched_at = datetime.now(timezone.utc).isoformat()
    package = json.loads((ROOT / 'package.json').read_text())
    index = (
        '# Skeleton v5 — Svelte documentation\n\n'
        f'Source: {INDEX_URL}\n\nFetched: {fetched_at}\n\n'
        'Rolling upstream v5 documentation, not a snapshot pinned to the installed patch version.\n'
        'Check package.json and installed package types when APIs differ.\n\n'
        + LINK.sub(lambda m: f'[{m[1]}](.{m[2]})', section)
    )
    manifest = {
        'source': INDEX_URL,
        'fetched_at': fetched_at,
        'installed_skeleton': package['dependencies']['@skeletonlabs/skeleton'],
        'documentation_version': 'rolling v5 (not patch-pinned)',
        'pages': [
            {'path': path.lstrip('/'), 'source': ORIGIN + path,
             'sha256': hashlib.sha256(content.encode()).hexdigest()}
            for path, content in pages.items()
        ],
    }
    for path, content in pages.items():
        destination = OUTPUT / path.lstrip('/')
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content, encoding='utf-8')
    # Remove only stale generated Markdown, never hand-maintained documentation.
    current_paths = {OUTPUT / path.lstrip('/') for path in pages}
    for stale in (OUTPUT / 'docs' / 'svelte').rglob('*.md'):
        if stale not in current_paths:
            stale.unlink()
    (OUTPUT / 'llms.txt').write_text(index, encoding='utf-8')
    (OUTPUT / 'index.md').write_text(index, encoding='utf-8')
    (OUTPUT / 'upstream-llms.txt').write_text(upstream_index, encoding='utf-8')
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'Saved {len(pages)} Skeleton Svelte Markdown pages and local indexes to {OUTPUT}')


if __name__ == '__main__':
    main()

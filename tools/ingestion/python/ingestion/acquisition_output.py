"""Private acquisition artifacts; sidecar hashes canonical envelope JSON."""
import json
import os

from ingestion.acnc_transform import MAPPING_VERSION
from ingestion.adapters.acnc import digest


def manifest(envelope):
    return {'manifest_version': 'acnc-acquisition-v1',
            **{key: envelope[key] for key in ('source_id', 'resource_id', 'run_id',
               'observed_at', 'parser_version', 'scope', 'completion', 'counts', 'qualification')},
            'mapping_version': MAPPING_VERSION, 'envelope_sha256': digest(envelope),
            'publication_eligible': False}


def write_outputs(directory, envelope):
    for filename, value in [('envelope.json', envelope), ('manifest.json', manifest(envelope))]:
        path = directory / filename
        with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write('\n')

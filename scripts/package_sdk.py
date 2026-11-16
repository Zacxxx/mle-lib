#!/usr/bin/env python3
"""Package the Lua SDK and pinned native bridge for a consumer or shared runtime."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

from build_native import build

ROOT = Path(__file__).resolve().parents[1]


def package(destination):
    version = re.search(r'VERSION = "([^"]+)"', (ROOT / 'src/mle_lib/host.lua').read_text()).group(1)
    files = {'Scripts/mle_lib/' + path.name: path.read_bytes() for path in sorted((ROOT / 'src/mle_lib').glob('*.lua'))}
    with tempfile.TemporaryDirectory(prefix='mle-sdk-native-') as temporary:
        build(ROOT / 'src/native', temporary)
        for path in Path(temporary).iterdir():
            files['Native/' + path.name] = path.read_bytes()
    files.update({'State/.keep': b'', 'Control/.keep': b'', 'Assets/Cards/.keep': b''})
    files['README.md'] = (ROOT / 'docs/buildings.md').read_text().replace('../examples/', 'examples/').encode()
    files['LICENSE'] = (ROOT / 'LICENSE').read_bytes()
    for name in ('example_house.lua', 'recipe_panel.lua', 'workshop_yard.lua'):
        files['examples/' + name] = (ROOT / 'examples' / name).read_bytes()
    manifest = {'name': 'MLE Lib', 'version': version,
        'revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
        'target': json.loads((ROOT / 'config/runtime_target.json').read_text()),
        'gameplay_verified': False,
        'working_tree_dirty': bool(subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain'], text=True).strip()),
        'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())}}
    files['MANIFEST.json'] = (json.dumps(manifest, indent=4) + '\n').encode()
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo('MLELib/' + name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    with zipfile.ZipFile(destination) as archive:
        for name, digest in manifest['files'].items():
            assert hashlib.sha256(archive.read('MLELib/' + name)).hexdigest() == digest
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/mle-lib-sdk.zip')
    print(package(parser.parse_args().output))

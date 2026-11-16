#!/usr/bin/env python3
"""Build the pinned Windows building adapter without invoking the game."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build(source, destination):
    source = Path(source)
    destination = Path(destination)
    paths = [source / name for name in ('building_bridge.c', 'building_paths.h', 'building_upgrades.h')]
    digest = hashlib.sha256(Path(__file__).read_bytes() + b''.join(path.read_bytes() for path in paths)).hexdigest()
    name = f'mle_buildings_{digest[:12]}.dll'
    destination.mkdir(parents=True, exist_ok=True)
    compiler = shutil.which('x86_64-w64-mingw32-gcc')
    if not compiler:
        raise RuntimeError('The building bridge requires gcc-mingw-w64-x86-64')
    subprocess.run([compiler, '-shared', '-O2', '-Wall', '-Wextra', '-Werror', '-static-libgcc',
        '-Wl,--no-insert-timestamp,--image-base,0x180000000', '-s', '-frandom-seed=' + digest, '-o', str(destination / name), str(paths[0]), '-ladvapi32'], check=True)
    (destination / 'buildings_name.txt').write_text(name + '\n')
    return name


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/Native')
    args = parser.parse_args()
    print(build(ROOT / 'src/native', args.output))

import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class NativeBuildingLayoutTests(unittest.TestCase):
    def test_top_level_native_path_preserves_strings_and_adjacent_fields(self):
        source = r'''
#include <assert.h>
#include "building_paths.h"
int main(void) {
    unsigned char row[0x1a0] = {0}, snapshot[0x1a0], source[32] = {0};
    uint32_t label = 487, package = 87, asset = 88;
    memcpy(row + 0xc, &label, 4);
    memcpy(source, &package, 4);
    memcpy(source + 8, &asset, 4);
    memset(row + 0x150, 0x5a, 8);
    memset(row + 0x180, 0x8b, 32);
    memset(row + 0x158, 0x93, 24);
    memcpy(snapshot, row, sizeof(row));
    assert(!building_preview_path(row, 99, source));
    assert(!memcmp(row, snapshot, sizeof(row)));
    assert(building_preview_path(row, label, source));
    assert(!memcmp(row, snapshot, 0x158));
    assert(!memcmp(row + 0x170, snapshot + 0x170, 0x30));
    assert(!memcmp(row + 0x160, source, 16));
    for (int i = 0; i < 8; i++) assert(row[0x158 + i] == 0);
    memcpy(snapshot, row, sizeof(row));
    row[0x178] = 1;
    assert(!building_preview_path(row, label, source));
    row[0x178] = 0;
    source[24] = 1;
    assert(!building_preview_path(row, label, source));
    assert(!memcmp(row, snapshot, sizeof(row)));

    unsigned char part[0x48] = {0}, part_snapshot[sizeof(part)];
    uint64_t hard_class = 0xfedcba98;
    source[24] = 0;
    memcpy(part + 0x8, &hard_class, 8);
    memset(part + 0x10, 0xff, 8);
    memcpy(part + 0x38, &label, 4);
    memset(part + 0x40, 0xc3, 8);
    memcpy(part_snapshot, part, sizeof(part));
    assert(!building_construction_path(part, 99, source));
    assert(!memcmp(part, part_snapshot, sizeof(part)));
    assert(building_construction_path(part, label, source));
    assert(!memcmp(part, part_snapshot, 0x10));
    assert(!memcmp(part + 0x28, part_snapshot + 0x28, 0x20));
    assert(!memcmp(part + 0x18, source, 16));
    for (int i = 0; i < 8; i++) assert(part[0x10 + i] == 0);
    assert(building_construction_path(part, label, source));
    memcpy(part_snapshot, part, sizeof(part));
    source[8]++;
    assert(!building_construction_path(part, label, source));
    assert(!memcmp(part, part_snapshot, sizeof(part)));
    source[8]--;
    for (unsigned int offset = 0x18; offset <= 0x68; offset += 0x28) {
        memset(row, 0, sizeof(row)); memcpy(row + 0xc, &label, 4);
        memcpy(snapshot, row, sizeof(row));
        assert(!building_texture_path(row, 99, offset, source));
        assert(!memcmp(row, snapshot, sizeof(row)));
        assert(building_texture_path(row, label, offset, source));
        assert(!memcmp(row + offset + 8, source, 16));
        assert(!memcmp(row, snapshot, offset));
        assert(!memcmp(row + offset + 24, snapshot + offset + 24, sizeof(row) - offset - 24));
    }
    uint32_t package_number = 2, asset_number = 3, label_number = 4;
    memcpy(source + 4, &package_number, 4); memcpy(source + 12, &asset_number, 4);
    memset(row, 0, sizeof(row)); memcpy(row + 0xc, &label, 4); memcpy(row + 0x10, &label_number, 4);
    assert(building_preview_path(row, label, source));
    assert(!memcmp(row + 0x160, source, 16));
    memset(part, 0, sizeof(part)); memcpy(part + 8, &hard_class, 8); memcpy(part + 0x38, &label, 4);
    memcpy(part + 0x3c, &label_number, 4);
    assert(building_construction_path(part, label, source));
    assert(!memcmp(part + 0x18, source, 16));
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "test.c").write_text(source)
            subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror",
                            "-I", str(ROOT / "src/native"), str(path / "test.c"),
                            "-o", str(path / "test")], check=True)
            subprocess.run([str(path / "test")], check=True)

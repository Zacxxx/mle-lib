import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('building_compiler', ROOT / 'scripts/build_native.py')
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)


class NativeBuildingBridgeTests(unittest.TestCase):
    def test_windows_bridge_build_is_reproducible_with_expected_exports(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = compiler.build(ROOT / 'src/native', root / 'first')
            second = compiler.build(ROOT / 'src/native', root / 'second')
            self.assertEqual(first, second)
            self.assertEqual((root / 'first' / first).read_bytes(), (root / 'second' / second).read_bytes())
            symbols = subprocess.check_output(['x86_64-w64-mingw32-objdump', '-p', str(root / 'first' / first)], text=True)
            for name in ('mle_building_paths', 'mle_building_upgrade_bind', 'mle_building_upgrade_unbind'):
                self.assertIn(name, symbols)


if __name__ == '__main__':
    unittest.main()

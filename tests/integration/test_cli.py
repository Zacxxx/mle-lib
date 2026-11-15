import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "scripts" / "mle.py"


class MleToolTests(unittest.TestCase):
    def command(self, *args, expected=0):
        result = subprocess.run([sys.executable, str(CLI), *map(str, args)], cwd=ROOT,
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def test_scaffold_build_and_reproducible_archives(self):
        with tempfile.TemporaryDirectory() as scratch:
            folder = Path(scratch)
            project = folder / "demo"
            self.command("init", project, "--id", "example.cli")
            self.command("init", project, "--id", "example.cli", expected=1)
            self.assertEqual(json.loads(self.command("validate", project).stdout)["order"], ["example.cli"])
            self.command("build", project, "--output", folder / "compiled.lua")
            first = folder / "one.zip"
            second = folder / "two.zip"
            entries = self.command("package", project, "--output", first)
            self.command("package", project, "--output", second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(hashlib.sha256(first.read_bytes()).hexdigest(), json.loads(entries.stdout)["sha256"])
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(sorted(archive.namelist()), ["main.lua", "manifest.lua", "mod.toml"])

    def test_validation_rejects_traversal_and_untrusted_lua_is_never_executed(self):
        with tempfile.TemporaryDirectory() as scratch:
            project = Path(scratch) / "demo"
            self.command("init", project, "--id", "example.cli")
            (project / "main.lua").write_text('error("must not execute during validation")\n')
            self.command("validate", project)
            manifest = project / "mod.toml"
            manifest.write_text(manifest.read_text().replace('["main.lua"]', '["main.lua", "../private.txt"]'))
            failure = json.loads(self.command("validate", project, expected=1).stderr)
            self.assertEqual(failure["code"], "MLE_MANIFEST")
            self.assertIn("Unsafe", failure["message"])

    def test_example_switch_and_unknown_switch(self):
        result = self.command("validate", ROOT / "examples", "--disable", "example.storage")
        self.assertEqual(json.loads(result.stdout)["order"], ["example.balance", "example.seasons"])
        result = self.command("inspect", ROOT / "examples", "--disable", "example.unknown", expected=1)
        self.assertEqual(json.loads(result.stderr)["code"], "MLE_SWITCH")

    def test_package_selects_one_active_entry_with_its_dependency_installed(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            self.command("init", root / "a", "--id", "example.a")
            self.command("init", root / "b", "--id", "example.b")
            manifest = root / "a" / "mod.toml"
            manifest.write_text(manifest.read_text() + '\n[requires]\n"example.b" = "^1.0.0"\n')
            result = self.command("validate", root)
            self.assertEqual(json.loads(result.stdout)["order"], ["example.b", "example.a"])
            archive = root / "a.zip"
            self.command("package", root, "--id", "example.a", "--output", archive)
            with zipfile.ZipFile(archive) as package:
                self.assertEqual(package.read("mod.toml"), manifest.read_bytes())
            self.command("package", root, "--id", "example.a", "--disable", "example.b", "--output", archive,
                         expected=1)


if __name__ == "__main__":
    unittest.main()

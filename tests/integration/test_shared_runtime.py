"""Verify independent archives through the shared Lua host using reflected API fixtures."""
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import mle


class SharedRuntimeTests(unittest.TestCase):
    def test_two_installations_share_hooks_registry_and_serialization(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for folder, increment, capacity in (("First", 1, 2), ("Second", 10, 5)):
                source = root / ("source-" + folder)
                source.mkdir()
                (source / "mod.toml").write_text(f'''id = "fixture.{folder.lower()}"
version = "0.1.0"
engine = ">=0.1.7 <0.2.0"
entry = "entry.lua"
files = ["entry.lua"]
capabilities = ["mle.registry", "mle.hooks", "mle.save"]
''')
                (source / "entry.lua").write_text(f'''return function(context)
    local count = 0
    _G.shared_fixture = _G.shared_fixture or {{}}
    context.services.register({{id = context.id .. ":capacity", schema = 1, patches = {{{{
        target = {{domain = "buildings", id = "72"}}, field = "capacity", op = "add", value = {capacity}
    }}}}}})
    context.services.hooks.add("/Script/ManorLords.PawnCPP:requestSaveFile", function()
        count = count + {increment}
        return "ignored"
    end)
    context.services.save_state(function() return {{count = count}} end, function(saved)
        count = saved and saved.count or 0
        _G.shared_fixture.{folder.lower()} = saved and count or nil
    end)
end
''')
                archive = root / (folder + ".zip")
                package, = mle.load_pack(source, [], ["mle.registry", "mle.hooks", "mle.save"])
                mle.package_archive(source, package, archive)
                with zipfile.ZipFile(archive) as bundle:
                    bundle.extractall(root / folder)
            prefix = f"package.path = {mle.lua_literal(str(ROOT / 'src/?.lua'))} .. ';' .. package.path"
            mle.lua_program(None, "-e", prefix, str(ROOT / "tests/test_shared_runtime.lua"), str(root))

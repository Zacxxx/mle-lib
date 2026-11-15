#!/usr/bin/env python3
"""MLE Lib development commands for offline package preparation."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import zipfile


ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "config" / "runtime_target.json"
FIELDS = {"id", "version", "engine", "entry", "files", "requires", "capabilities", "assets"}
COMPONENT = re.compile(r"[A-Za-z0-9_-][A-Za-z0-9_.-]*")
WINDOWS_RESERVED = {"CON", "PRN", "AUX", "NUL"} | {f"{prefix}{i}" for prefix in ("COM", "LPT") for i in range(1, 10)}


class PackageError(Exception):
    def __init__(self, code, target, reason, remediation):
        self.record = {"code": code, "severity": "error", "target": str(target), "message": reason,
                       "remediation": remediation}
        super().__init__(reason)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_package(directory):
    manifest = directory / "mod.toml"
    try:
        if directory.is_symlink() or manifest.is_symlink():
            raise ValueError("Package directory and manifest must be ordinary filesystem entries")
        with manifest.open("rb") as stream:
            value = tomllib.load(stream)
        if not {"id", "version", "engine", "entry", "files"} <= value.keys() <= FIELDS:
            raise ValueError("Missing required keys or unknown manifest fields")
        if any(not isinstance(value[key], str) for key in ("id", "version", "engine", "entry")):
            raise ValueError("ID, version, engine, and entry require text values")
        if not isinstance(value["files"], list) or not all(isinstance(path, str) for path in value["files"]):
            raise ValueError("File list requires relative paths")
        if len({path.casefold() for path in value["files"]}) != len(value["files"]):
            raise ValueError("Duplicate or case-conflicting file path")
        if value["entry"] not in value["files"] or not value["entry"].endswith(".lua"):
            raise ValueError("Lua entry must appear in the file list")
        if not isinstance(value.get("requires", {}), dict) or any(not isinstance(item, str) for item in value.get("requires", {}).values()):
            raise ValueError("Dependency constraints require text values")
        if not isinstance(value.get("capabilities", []), list) or any(not isinstance(item, str) for item in value.get("capabilities", [])):
            raise ValueError("Capabilities require a list of names")
        if not isinstance(value.get("assets", {}), dict):
            raise ValueError("Assets require a map of relative paths to SHA-256 hashes")
        for path in value["files"]:
            segments = path.split("/")
            if any(not COMPONENT.fullmatch(part) or part.endswith(".")
                   or part.split(".", 1)[0].upper() in WINDOWS_RESERVED for part in segments):
                raise ValueError(f"Unsafe or nonportable path {path!r}")
            if path.casefold() in {"mod.toml", "manifest.lua"}:
                raise ValueError(f"Reserved path {path!r}")
            current = directory
            for part in PurePosixPath(path).parts:
                current = current / part
                if current.is_symlink():
                    raise ValueError(f"Symlink in package file {path!r}")
            if not current.is_file():
                raise ValueError(f"Missing package file {path!r}")
        assets = value.get("assets", {})
        for path in value["files"]:
            if path.lower().endswith((".pak", ".utoc", ".ucas")) and path not in assets:
                raise ValueError(f"Cooked asset {path!r} requires a declared SHA-256 hash")
        for path, digest in assets.items():
            if path not in value["files"] or not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise ValueError(f"Invalid asset declaration {path!r}")
            if sha256(directory / path) != digest:
                raise ValueError(f"Asset hash mismatch for {path!r}")
        return value
    except (OSError, ValueError) as error:
        raise PackageError("MLE_MANIFEST", manifest, str(error), "Fix mod.toml and the files it references") from error


def lua_literal(data):
    """Encode only validated data. Every string byte becomes a fixed Lua escape."""
    if isinstance(data, str):
        return '"' + "".join(f"\\{byte:03}" for byte in data.encode()) + '"'
    if isinstance(data, bool):
        return "true" if data else "false"
    if isinstance(data, list):
        return "{" + ",".join(map(lua_literal, data)) + "}"
    if isinstance(data, dict):
        return "{" + ",".join(f"[{lua_literal(key)}]={lua_literal(data[key])}" for key in sorted(data)) + "}"
    raise TypeError(f"Unsupported Lua manifest value {type(data).__name__}")


def lua_program(program, *args, capture=False):
    binary = shutil.which("lua5.4") or shutil.which("lua")
    if not binary:
        raise PackageError("MLE_TOOLCHAIN", "lua5.4", "Lua 5.4 is unavailable", "Install Lua 5.4 and run doctor")
    environment = dict(os.environ)
    environment.pop("LUA_INIT", None)
    environment.pop("LUA_INIT_5_4", None)
    environment["LUA_PATH"] = str(ROOT / "src" / "?.lua") + ";" + str(ROOT / "src" / "?" / "init.lua") + ";;"
    return subprocess.run([binary, "-E", *args], cwd=ROOT, input=program, text=True,
                          env=environment, capture_output=capture, check=True)


def load_pack(root, disabled, capabilities):
    if not root.is_dir() or root.is_symlink():
        raise PackageError("MLE_PACK", root, "Expected an existing package directory", "Pass a directory containing mod.toml")
    directories = [root] if (root / "mod.toml").is_file() else sorted(
        directory for directory in root.iterdir() if directory.is_dir() and (directory / "mod.toml").is_file()
    )
    if not directories:
        raise PackageError("MLE_PACK", root, "No mod.toml manifests found", "Create a package with init or select its parent")
    packages = [{**read_package(directory), "location": directory.relative_to(root).as_posix()} for directory in directories]
    unknown = set(disabled) - {package["id"] for package in packages}
    if unknown:
        raise PackageError("MLE_SWITCH", root, "Unknown package ID " + ", ".join(sorted(unknown)),
                           "Use an installed package ID in --disable")
    enabled = {package_id: False for package_id in disabled}
    options = {"capabilities": dict.fromkeys(capabilities, True)}
    # Only the library resolver runs here. Lua entry scripts execute under the
    # user's chosen runtime, after the pack passes validation.
    prefix = "package.path = " + lua_literal(str(ROOT / "src" / "?.lua")) + " .. ';' .. package.path\n"
    script = prefix + """
local Host = require("mle_lib.host")
local Json = require("mle_lib.json")
local ordered, failure = Host.plan(PACKAGES, SWITCHES, OPTIONS)
print(Json.encode({order = ordered or {}, failure = failure}))
"""
    script = re.sub(r"\b(PACKAGES|SWITCHES|OPTIONS)\b",
                    lambda match: lua_literal({"PACKAGES": packages, "SWITCHES": enabled, "OPTIONS": options}[match[0]]),
                    script)
    result = json.loads(lua_program(script, "-", capture=True).stdout)
    if "failure" in result:
        failure = result["failure"]
        target = failure.get("id", str(root))
        if failure.get("dependency"):
            target += " -> " + failure["dependency"]
        raise PackageError("MLE_" + failure["code"].upper(), target, failure["message"],
                           "Review package constraints, capabilities and enable switches")
    return list(result["order"] or [])


def package_archive(root, package, output):
    directory = root / package["location"]
    entries = sorted((*package["files"], "mod.toml", "manifest.lua"))
    manifest = ("return " + lua_literal({**package, "location": "."}) + "\n").encode()
    def write_archive(stage):
        with zipfile.ZipFile(stage, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in entries:
                info = zipfile.ZipInfo(path)
                info.compress_type = zipfile.ZIP_DEFLATED
                if path == "manifest.lua":
                    archive.writestr(info, manifest)
                    continue
                with (directory / path).open("rb") as source, archive.open(info, "w", force_zip64=True) as target:
                    digest = hashlib.sha256()
                    while block := source.read(1024 * 1024):
                        digest.update(block)
                        target.write(block)
                expected = package.get("assets", {}).get(path)
                if expected is not None and digest.hexdigest() != expected:
                    raise PackageError("MLE_ASSET", path, "Asset changed during packaging", "Revalidate the asset and retry")
    atomic_output(output, write_archive)
    return {"path": str(output), "sha256": sha256(output)}


def atomic_output(output, write):
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".mle-", dir=output.parent) as directory:
        stage = Path(directory) / "output"
        write(stage)
        stage.replace(output)


def check_output(root, packages, output):
    for package in packages:
        directory = root / package["location"]
        reserved = [(directory / name).resolve() for name in (*package["files"], "mod.toml")]
        if output.resolve() in reserved:
            raise PackageError("MLE_OUTPUT", output, "Output overlaps a package source file", "Choose a generated file path")


def initialize(directory, package_id):
    if not re.fullmatch(r"[a-z][a-z0-9_.-]*[a-z0-9]", package_id) or "." not in package_id or ".." in package_id:
        raise PackageError("MLE_ID", package_id, "Expected a namespaced package ID", "Choose a name such as example.harvest")
    directory.mkdir(parents=True, exist_ok=True)
    if directory.is_symlink() or any((directory / name).exists() or (directory / name).is_symlink()
                                     for name in ("mod.toml", "main.lua")):
        raise PackageError("MLE_EXISTS", directory, "A package manifest or entry already exists", "Choose a new directory")
    manifest = directory / "mod.toml"
    with manifest.open("x", encoding="utf-8") as stream:
        stream.write(f'id = "{package_id}"\nversion = "1.0.0"\nengine = "^0.1.0"\n'
                     'entry = "main.lua"\nfiles = ["main.lua"]\n')
    try:
        with (directory / "main.lua").open("x", encoding="utf-8") as stream:
            stream.write('return function(context)\n    -- Register content and event listeners here.\nend\n')
    except OSError:
        manifest.unlink()
        raise


def doctor(game, ue4ss):
    binary = shutil.which("lua5.4") or shutil.which("lua")
    result = {"python": sys.version.split()[0], "lua": binary,
              "native_toolchain": shutil.which("x86_64-w64-mingw32-gcc"), "game_checked": False}
    if binary:
        result["lua_version"] = subprocess.check_output([binary, "-E", "-e", "print(_VERSION)"], text=True).strip()
    if game or ue4ss:
        if not game or not ue4ss or not PROFILE.is_file():
            raise PackageError("MLE_PROFILE", ROOT, "Missing complete profile input",
                               "Supply both --game-exe and --ue4ss with the exact game profile installed")
        target = json.loads(PROFILE.read_text(encoding="utf-8"))
        verified = sha256(game) == target["executable_sha256"] and sha256(ue4ss) == target["ue4ss_sha256"]
        if not verified:
            raise PackageError("MLE_PROFILE", game.name, "Game or UE4SS hash differs from the supported build",
                               "Use the pinned game and UE4SS build")
        result["game_checked"] = True
        result["build"] = target["steam_build"]
    return result


def test():
    for fixture in sorted((ROOT / "tests").rglob("test_*.lua")):
        prefix = "package.path = " + lua_literal(str(ROOT / "src" / "?.lua")) + " .. ';' .. package.path"
        lua_program(None, "-e", prefix, str(fixture))
    subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests/integration", "-v"], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory() as directory:
        manifest = Path(directory) / "manifest.lua"
        packages = load_pack(ROOT / "examples", [], [])
        manifest.write_text("return " + lua_literal(packages) + "\n", encoding="utf-8")
        prefix = "package.path = " + lua_literal(str(ROOT / "src" / "?.lua")) + " .. ';' .. package.path"
        lua_program(None, "-e", prefix, "examples/run.lua", str(manifest))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("init")
    command.add_argument("root", type=Path)
    command.add_argument("--id", required=True)
    command = commands.add_parser("doctor")
    command.add_argument("--game-exe", type=Path)
    command.add_argument("--ue4ss", type=Path)
    commands.add_parser("test")
    for name in ("inspect", "validate", "build", "package"):
        command = commands.add_parser(name)
        command.add_argument("root", type=Path)
        command.add_argument("--disable", action="append", default=[])
        command.add_argument("--capability", action="append", default=[])
        if name in {"build", "package"}:
            command.add_argument("--output", type=Path, required=True)
        if name == "package":
            command.add_argument("--id", help="Select one active package from a multi-package directory")
    args = parser.parse_args()
    try:
        if args.command == "init":
            initialize(args.root, args.id)
        elif args.command == "test":
            test()
        elif args.command == "doctor":
            print(json.dumps(doctor(args.game_exe, args.ue4ss), indent=2))
        else:
            packages = load_pack(args.root, args.disable, args.capability)
            if args.command in {"build", "package"}:
                check_output(args.root, packages, args.output)
            if args.command == "build":
                manifest = "return " + lua_literal(packages) + "\n"
                atomic_output(args.output, lambda stage: stage.write_text(manifest, encoding="utf-8"))
            elif args.command == "package":
                selected = [item for item in packages if not args.id or item["id"] == args.id]
                if len(selected) != 1:
                    raise PackageError("MLE_PACKAGE", args.root, "Expected one selected active package",
                                       "Select a single package directory or pass an active package --id")
                print(json.dumps(package_archive(args.root, selected[0], args.output)))
            else:
                print(json.dumps({"engine": "MLE Lib", "order": [entry["id"] for entry in packages],
                                  "packages": packages if args.command == "inspect" else len(packages)}, indent=2))
    except PackageError as error:
        print(json.dumps(error.record), file=sys.stderr)
        return 1
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(json.dumps({"code": "MLE_TOOL", "severity": "error", "message": str(error)}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

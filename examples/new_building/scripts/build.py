#!/usr/bin/env python3
"""Prepare, author, cook and package the original Example House; never launch a game.

Tool paths are explicit environment variables. Linux editor/cooker jobs run in a
resource-limited systemd user scope. The tutorial does not install anything.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[3]
EXAMPLE = ROOT / "examples/new_building"
OUTPUT = ROOT / "build/new_building"
PROJECT = OUTPUT / "Project/ExampleBuilding.uproject"
PROFILE = ROOT / "config/render_profiles/manor_lords_0_8_117.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare():
    PROJECT.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EXAMPLE / "config/ExampleBuilding.uproject", PROJECT)
    config = PROJECT.parent / "Config"
    config.mkdir(exist_ok=True)
    values = json.loads(PROFILE.read_text())["cvars"]
    (config / "DefaultEngine.ini").write_text(
        "[/Script/Engine.RendererSettings]\n" + "".join(f"{name}={value}\n" for name, value in values.items())
        + "\n[/Script/WindowsTargetPlatform.WindowsTargetSettings]\nDefaultGraphicsRHI=DefaultGraphicsRHI_DX12\n"
        + "!D3D12TargetedShaderFormats=ClearArray\n+D3D12TargetedShaderFormats=PCD3D_SM6\n"
        + "!D3D11TargetedShaderFormats=ClearArray\n+D3D11TargetedShaderFormats=PCD3D_SM5\n")
    (config / "DefaultGame.ini").write_text("[/Script/UnrealEd.ProjectPackagingSettings]\n"
        "bShareMaterialShaderCode=False\nbSharedMaterialNativeLibraries=False\n")


def limited(command):
    if sys.platform != "linux":
        return command
    if not shutil.which("systemd-run"):
        raise ValueError("Linux tutorial builds require systemd-run for CPU/memory limits")
    cpus = ",".join(map(str, sorted(os.sched_getaffinity(0))[-2:]))
    return ["systemd-run", "--user", "--scope", "--quiet", "--unit=mle-example-" + uuid.uuid4().hex[:12],
            "-p", "MemoryMax=4G", "-p", "MemorySwapMax=0", "-p", "CPUQuota=100%", "-p", "CPUWeight=1",
            "-p", "IOWeight=1", "nice", "-n", "15", "ionice", "-c", "3", "taskset", "-c", cpus, *command]


def editor(action, windows=False):
    if not PROJECT.is_file():
        raise ValueError("Run prepare first")
    tool = os.environ.get("MLE_WINDOWS_EDITOR" if windows else "MLE_UNREAL_EDITOR")
    if not tool or not Path(tool).is_file():
        raise ValueError("Set MLE_WINDOWS_EDITOR or MLE_UNREAL_EDITOR to the appropriate UE 5.5.4 editor executable")
    wine = windows and sys.platform != "win32"
    def host_path(path):
        return "Z:" + str(path.resolve()) if wine else str(path.resolve())
    environment = os.environ.copy()
    environment["MLE_LIB_ROOT"] = host_path(ROOT)
    environment["SDL_VIDEODRIVER"] = "offscreen"
    environment["UE-SharedDataCachePath"] = "None"
    command = [tool, host_path(PROJECT), "-nullrhi", "-unattended", "-nosplash", "-nosound", "-nosourcecontrol",
               "-NoLiveCoding", "-NoZenAutoLaunch", "-notraceserver", "-NoCrashDialog", "-corelimit=2",
               "-ddc=InstalledNoZenLocalFallback", "-stdout", "-FullStdOutLogOutput"]
    if action == "cook":
        editor("verify", windows=True)
        cooked = PROJECT.parent / "Saved/Cooked/Windows"
        if cooked.exists():
            shutil.rmtree(cooked)  # Generated output only, never game files.
        assets = PROJECT.parent / "Content/ExampleBuilding"
        command += ["-run=cook", "-targetplatform=Windows", "-cooksinglepackage", "-CookSkipRequests",
                    "-SkipSoftReferences", "-NoDefaultMaps", "-NoGameAlwaysCook", "-CookCultures=en"]
        command += ["-Package=/Game/ExampleBuilding/" + path.relative_to(assets).with_suffix("").as_posix()
                    for path in sorted(assets.rglob("*.uasset"))]
    else:
        environment["MLE_VERIFY_ONLY"] = "1" if action == "verify" else "0"
        command += ["-run=pythonscript", "-script=" + host_path(EXAMPLE / "scripts/author.py")]
    if wine:
        runner = os.environ.get("MLE_WINE")
        if not runner or not Path(runner).is_file() or not environment.get("WINEPREFIX"):
            raise ValueError("A prepared isolated Wine cooker prefix, MLE_WINE and WINEPREFIX are required")
        environment.update({"WINEDEBUG": "-all", "DISPLAY": "", "WAYLAND_DISPLAY": "",
                            "WINEDLLOVERRIDES": "imagehlp=n;dbghelp=b;winemenubuilder.exe=d"})
        command = [runner, *command, "-ansimalloc"]
    with (OUTPUT / (action + ("-windows" if windows else "") + ".log")).open("w") as log:
        subprocess.run(limited(command), env=environment, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    if action == "cook":
        folder = PROJECT.parent / "Saved/Cooked/Windows/ExampleBuilding/Content/ExampleBuilding"
        receipt = json.loads((OUTPUT / "render-profile.json").read_text())
        assert receipt["host_platform"] == "win32" and receipt["compatible"]
        receipt["files"] = {p.relative_to(folder).as_posix(): digest(p) for p in sorted(folder.rglob("*")) if p.is_file()}
        receipt["renderer_ini_sha256"] = digest(PROJECT.parent / "Config/DefaultEngine.ini")
        (OUTPUT / "cook.json").write_text(json.dumps(receipt, indent=4) + "\n")


def package():
    sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "src")]
    import mle
    from mle_authoring.render_profile import verify_render_environment
    source = PROJECT.parent / "Saved/Cooked/Windows/ExampleBuilding/Content/ExampleBuilding"
    files = {p.relative_to(source).as_posix(): digest(p) for p in sorted(source.rglob("*")) if p.is_file()}
    receipt = json.loads((OUTPUT / "cook.json").read_text())
    verify_render_environment(json.loads(PROFILE.read_text()), receipt["engine_version"], receipt["effective_cvars"])
    assert receipt["host_platform"] == "win32" and files and receipt["files"] == files
    assert receipt["renderer_ini_sha256"] == digest(PROJECT.parent / "Config/DefaultEngine.ini")
    expected = {"BP_ExampleHouse_Assembly", "BP_ExampleHouse_Construction", "Meshes/SM_ExampleHouse",
                "Meshes/SM_ExampleHouse_Foundation", "Meshes/SM_ExampleHouse_Frame", "Meshes/SM_ExampleHouse_Roof",
                "Materials/M_ExampleWood", "Materials/M_ExampleStone", "Textures/ExampleWood", "UI/T_ExampleHouse"}
    assert {p[:-7] for p in files if p.endswith(".uasset")} == expected
    assert set(files) <= {name + extension for name in expected for extension in (".uasset", ".uexp", ".ubulk")}
    assert all(name + ".uexp" in files for name in expected)
    parent = b"/Game/CPP_BP/ConstructionBlueprints/ConstructionBP\0"
    assert parent in (source / "BP_ExampleHouse_Construction.uasset").read_bytes()
    tool = os.environ.get("MLE_UNREALPAK")
    if not tool or not Path(tool).is_file():
        raise ValueError("Set MLE_UNREALPAK to UnrealPak")
    destination = OUTPUT / "Package"
    destination.mkdir(exist_ok=True)
    pak = destination / "ExampleBuilding.pak"
    with tempfile.TemporaryDirectory(dir=OUTPUT) as temporary:
        temp = Path(temporary)
        response = temp / "files.txt"
        response.write_text("".join(f'"{source / name}" "../../../ManorLords/Content/ExampleBuilding/{name}"\n' for name in files))
        subprocess.run(limited([tool, str(pak), "-Create=" + str(response), "-compress", "-compressionformats=Zlib"]),
                       check=True, cwd=temp, stdout=subprocess.DEVNULL)
        subprocess.run(limited([tool, str(pak), "-Test"]), check=True, cwd=temp, stdout=subprocess.DEVNULL)
        if sys.platform == "linux":
            # UE 5.5 extraction joins directory and filename with a Windows separator.
            alias = pak.parent.parent / (pak.parent.name + "\\" + pak.name)
            alias.symlink_to(pak)
        else:
            alias = None
        try:
            subprocess.run(limited([tool, str(pak), "-Extract", str(temp / "readback")]),
                           check=True, cwd=temp, stdout=subprocess.DEVNULL)
            assert {p.relative_to(temp / "readback").as_posix(): digest(p)
                    for p in (temp / "readback").rglob("*") if p.is_file()} == files
        finally:
            if alias:
                alias.unlink()
    receipt.update(pak_sha256=digest(pak), archive_round_trip_verified=True, game_launched=False)
    (destination / "build-receipt.json").write_text(json.dumps(receipt, indent=4) + "\n")
    stage = OUTPUT / "Consumer"
    stage.mkdir(exist_ok=True)
    shutil.copy2(EXAMPLE / "entry.lua", stage / "entry.lua")
    for directory in ("State", "Control", "Assets/Cards"):
        (stage / directory).mkdir(parents=True, exist_ok=True)
        (stage / directory / "keep.txt").touch()
    (stage / "Assets/Cooked").mkdir(parents=True, exist_ok=True)
    shutil.copy2(pak, stage / "Assets/Cooked/ExampleBuilding.pak")
    (stage / "mod.toml").write_text('id = "example.building"\nversion = "0.1.0"\nengine = "=0.1.15"\n'
        'entry = "entry.lua"\ncapabilities = ["mle.buildings", "mle.hooks"]\n'
        'files = ["entry.lua", "State/keep.txt", "Control/keep.txt", "Assets/Cards/keep.txt", "Assets/Cooked/ExampleBuilding.pak"]\n'
        '[assets]\n"Assets/Cooked/ExampleBuilding.pak" = "' + digest(pak) + '"\n')
    descriptor, = mle.load_pack(stage, [], ["mle.buildings", "mle.hooks"])
    mle.package_archive(stage, descriptor, destination / "ExampleBuilding.zip")
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "author", "verify", "cook", "package"))
    parser.add_argument("--windows", action="store_true", help="Use the Windows editor for authoring/verification")
    args = parser.parse_args()
    if args.action == "prepare":
        prepare()
    elif args.action == "package":
        package()
    else:
        editor(args.action, windows=args.windows or args.action == "cook")

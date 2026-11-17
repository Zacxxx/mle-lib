# Example House: original building tutorial

Start with the [complete guide](../../docs/new-building-tutorial.md).
This is a small supply shed using native storage behavior. It demonstrates an
owned 3D model, two materials, UVs, UCX collision, separate preview and staged
construction, shared assembly roles, art/text and independent package registration.
It does not implement residential plotting, seasonal snow shading or every game
mechanic. The name “House” does not change its storage function.

All sample geometry, the wood texture and placeholder UI art are original and
available under the repository's MIT license. No native game model, texture or
third-party mod asset is distributed. The construction parent is an editor-only
stand-in excluded from the package. The player supplies the compatible game.

## Files

* [ExampleHouse.glb](assets/ExampleHouse.glb): textured inspection model.
* `assets/SM_ExampleHouse*.fbx`: complete preview and disjoint source pieces.
* `scripts/model.py`: rebuilds all source assets with Blender.
* `building.py`: shared assembly declaration and part identity.
* `scripts/author.py`: imports sources, builds PBR materials, authors owned assets.
* `scripts/construction.py`: reference native-parent/staged-child authoring helper.
* `entry.lua`: consumer of the independent MLE Lib building API.
* `scripts/build.py`: resource-limited headless author/cook/package workflow.

Use the full Git checkout. The builder reads the repository's `src`, `scripts`
and renderer profile, so copying only this folder is not a complete toolchain.
Require UE 5.5.4, Blender with FBX/glTF exporters, Python 3, and UnrealPak. The
Windows game needs Windows cooked assets even when development happens on Linux.

## Build

From the repository root:

```sh
python3 scripts/mle.py test
python3 examples/new_building/scripts/build.py prepare
blender --background --factory-startup \
  --python examples/new_building/scripts/model.py \
  -- examples/new_building/assets
```

Set absolute tool paths for your installation. On Linux:

```sh
export MLE_UNREAL_EDITOR=/absolute/UE_5.5.4/Engine/Binaries/Linux/UnrealEditor
export MLE_UNREALPAK=/absolute/UE_5.5.4/Engine/Binaries/Linux/UnrealPak
python3 examples/new_building/scripts/build.py author
```

For a **prepared isolated** Windows cooker under Wine on Linux:

```sh
export MLE_WINDOWS_EDITOR=/absolute/WindowsUE_5.5.4/Engine/Binaries/Win64/UnrealEditor-Cmd.exe
export MLE_WINE=/absolute/prepared/wine
export WINEPREFIX=/absolute/isolated/windows-cooker-prefix
python3 examples/new_building/scripts/build.py cook
python3 examples/new_building/scripts/build.py package
```

This tutorial does not download UE or prepare Wine. Use your licensed engine and
existing cooker setup. Do not use a game or audio application's Wine prefix.
On native Windows, set `MLE_WINDOWS_EDITOR` and `MLE_UNREALPAK` to Windows tools;
author with `--windows`, then run `cook` and `package` using Python. No Wine or
Linux systemd scope is used there.

Output is under `build/new_building`, which is excluded from Git:

```text
Project/                 generated UE project, editor assets and cooked output
authoring.json           source authoring/renderer receipt
cook.json                Windows profile and payload hashes
Package/
  ExampleBuilding.pak    only /Game/ExampleBuilding assets
  ExampleBuilding.zip    independently installed content package
  build-receipt.json     profile, exact hashes and acceptance status
```

`prepare` resets only the generated project's configuration. `cook` deletes only
its generated Windows cooked output to force a clean delivery. The builder never
touches a Manor Lords installation or save. Keep editable source in this folder;
do not put irreplaceable work in `build/new_building`.

## Download the example

The [Windows example ZIP](download/ExampleBuilding.zip) contains the content
package and cooked PAK. The [build receipt](download/build-receipt.json) records
the renderer profile and payload hashes. Unreal authoring, Windows cooking and
PAK extraction with hash comparison passed. Placement, construction and
save/reload for this example are pending a test in Manor Lords.

## Install deliberately, with the game closed

1. Verify the compatible game/UE4SS profile with `scripts/mle.py doctor`. Back up
   saves and the files you will change.
2. Install and enable the independent MLE Lib **0.1.15** runtime.
3. Extract `ExampleBuilding.zip` into `ue4ss/Mods/ExampleBuilding` so its
   `manifest.lua` sits directly in that folder. Do not add `enabled.txt` there.
4. Copy `ExampleBuilding.pak` into `ManorLords/Content/Paks/~mods`. The copy inside
   the content ZIP is the same payload; UE does not discover it there automatically.
5. Append `ExampleBuilding` to `MLELib/packages.txt`, preserving existing lines.
   `State` and `Control` folders must remain present and writable.
6. Start at the main menu and check `mle.runtime.status` for `example.building`.
   Then use a separate save and run the guide's placement, construction, visual,
   worker and persistence checks. The example's numeric construction part 19001
   must be available in your install; allocate a different stable part ID and
   rebuild if it collides.

Do not install this example on a valuable world as a substitute for testing.
Deleting a package does not remove its identities from existing saves.

## Change the function or replace the model

Edit `entry.lua` for supported gameplay/template fields. Add recipe/item, behavior,
world-system and UI modules as described in the guide; worker execution and custom
widgets still need compatible implementations. Keep visual asset identities stable
when changing a saved building's artwork. Update `building.py` and the declaration
when splitting pieces, and keep `entry.lua`'s four asset paths consistent.

Replace the FBX/PNG sources while preserving the demonstrated units, pivots,
material slots and disjoint construction groups. If the material graph changes,
update `author.py`, not only the source texture. Run author → Windows cook → package
again, and compare the saved/cooked assets and receipt. Recheck shader usage flags
if the new runtime component differs from a regular static mesh component.

The same visual process applies to other functions, but their placement, workers,
input/output, extensions and save behavior need separate tests.

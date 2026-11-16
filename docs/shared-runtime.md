# Shared MLE Lib runtime

Install the standalone archive so `MLELib` is a direct child of UE4SS's
`Mods` folder. Enable only the runtime through `MLELib/enabled.txt`. Each
content package lives in its own sibling folder and exposes `manifest.lua`
plus a Lua entry that returns an activation function. List the trusted
package folder names, one per line, in `MLELib/packages.txt`. Restart the
game after editing this list. A folder omitted from the list is inactive.
Keep package folders out of UE4SS's own enable list.

The runtime ZIP is disabled by default. To build it with the UE4SS enable
marker included, run `python3 scripts/package_sdk.py --runtime --enable --output dist/mle-lib-runtime.zip`.
At startup, MLE Lib checks the exact supported game and UE4SS binary hashes
before discovering or executing packages.

All package entries execute in the MLE Lib Lua VM. Lua entries are trusted
code. Capability declarations specify the service contract and are not a
sandbox. Mods independently started in another UE4SS Lua VM do not belong to
this host. Mods using the same data rows or reflected hooks outside this host
can still conflict with it.

## Package services

Declare the capabilities your package uses in its manifest. The runtime provides `mle.registry`, `mle.hooks`, `mle.save`, `mle.buildings`, and `mle.items` on the supported profile.

- `context.services.register(definition)` enrolls a package-owned definition
  during activation. The host validates and freezes the combined registry and
  applies its patches at the main menu. The game profile allows the
  `bVisibleInUi` and `storageLimitGeneric` building fields. Registrations can
  also have no patches.
- `context.services.register_item(spec)` and
  `context.services.register_recipe(spec)` collect item and recipe definitions
  across all packages that declare `mle.items`. Call these during activation.
  Use IDs prefixed with the package ID followed by `:`. Recipes may reference
  a different active package's item by that namespaced ID. Declare a dependency
  on the other package when the recipe requires its item. Both functions use the
  descriptor fields shown in the [standalone example](../examples/items_and_recipes.lua).
  Supply an explicit `numeric_id` confirmed usable by your game adapter, or
  omit it to allocate from the range in `MLELib/State/item-range.txt`. The file
  contains two decimal integers separated by whitespace, inclusive first and
  last IDs. No range ships enabled. Choose a range verified for the game build
  and all legacy item providers in the installation before enabling allocation.
  The runtime skips occupied rows and reserved IDs. Existing names retain their
  allocated IDs if the range changes. Exhaustion stops registration. The
  runtime persists ownership in `MLELib/State/items.ids` and rejects collisions
  with existing rows or previously reserved IDs. Keep this ledger with saves.
  Reservations survive failed activation and package disablement to prevent ID
  reuse. This phase coordinates packages that use the shared API. Ruralities
  still restores its legacy item IDs through its own adapter, so shared item
  packages must use IDs compatible with that install. The existing native
  logistics, market and worker systems still need live acceptance.
- `context.services.hooks.add(path, first[, second])` registers an observer
  with the common reflected hook broker. The broker installs one native
  registration per path. Callback return values are ignored. Native hooks
  allow pre and post callbacks, and Blueprint hooks allow a single callback.
  The returned function unsubscribes that observer.
- `context.services.save_state(snapshot, restore)` enrolls one provider per
  package. Supply a snapshot function returning a serializable table or nil.
  Supply a restore function accepting `state, status, save_object`.
  Status is `loaded`, `missing`, or `unreadable`. Reset package state
  when its snapshot is missing. Keep gameplay validation and schema changes
  in the package. The runtime writes its namespaced payload to a native saved
  building's tags and verifies it on read. Saves without a saved building
  cannot carry that payload. Preservation of inactive package data across
  another in-game save depends on the engine carrying forward those tags.
- `context.services.new_building_runtime(options)` opens the native building
  API with the shared identity ledger and bridge. With UI enabled, also
  declare `mle.hooks` so the managed building UI joins the common broker.
- `context.directory` points to the installed package, and
  `context.runtime_directory` points to the independent MLE Lib install.

The native save adapter uses the reflected `IoHandler` save and load functions.
The `mle.runtime.status` console command reports the active packages, registry,
registered hook paths, and serialization counters. `wrote` counts metadata
written to the native save object. `loaded` counts restores with metadata
present. `empty_writes` and `missing_loads` identify callbacks without payloads.
`failed` counts callback failures. The game may still save after a callback
failure. `game_saves_accepted` and `game_saves_rejected` report the game's
boolean return through the reflected post-hook. These counters are independent
of metadata writes, and the post-hook still needs a live test. Use a disposable slot and confirm both packages recover their state
after restarting the game before treating a write as durable.

## Two-package acceptance

1. With the game closed, install and enable MLE Lib. Install Ruralities and
   extract the witness ZIP into a sibling folder called `MLEWitness`. List
   `MLExpandedRural` and `MLEWitness` in `MLELib/packages.txt`.
2. Open Manor Lords 0.8.117. At the main menu, run `mle.runtime.status` and
   check for both package IDs, both registry entries, and one native
   `PawnCPP:requestSaveFile` target once Ruralities startup has finished.
3. Load a disposable copy of a Ruralities world with a constructed building.
   Save As to a new named slot. Record the runtime status and verify a write
   was counted. Exit to desktop.
4. Restart, load the new slot, and check for a nonzero witness counter,
   a successful runtime load, and Ruralities' saved staffing, stock and
   gameplay state. Confirm the relevant workers resume work.
5. Exit and remove only `MLEWitness` from the catalog. Restart, confirm
   Ruralities is still active, and reload the acceptance save.

The packaged offline integration test simulates the reflected calls, uses
both package directories and reconstructs the host for reload. The in-game
steps above are still required to verify engine serialization.

# Building registration API

MLE Lib 0.1.3 supplies the Manor Lords 0.8.117 / UE4SS e3ba1016 building registration profile. `mle_lib.buildings.new` creates the native service when given a mod directory and asset namespace. Native classes, construction references, previews, presentation, upgrade transitions and ID persistence are managed inside the library. An advanced caller can still supply an adapter for another profile.

The implementation has offline regression coverage. Loaded-world acceptance is pending. The existing Ruralities lighting and upgrade reports require fresh gameplay checks; an offline test does not prove their resolution.

## Consumer setup

Bundle the pinned `src/mle_lib/*.lua` modules. Run `python3 scripts/build_native.py --output /path/to/YourMod/Native` from the library checkout, and create `State`, `Control` and `Assets/Cards` beside that Native directory. Include your owned cooked Windows pak in the game's mod pak directory. Keep these deliveries versioned together and install while the game is closed. The native DLL verifies the exact supported executable hash before any memory write or hook installation.

Use the main menu registration phase, on the game thread. A complete example is in [examples/example_house.lua](../examples/example_house.lua). It requires actual authored and cooked assets at its declared paths. The library does not generate original building art or geometry.

```lua
local buildings = require("mle_lib.buildings").new({
    directory = mod_directory,
    asset_root = "/Game/ExampleMod/",
})

buildings.register_building({
    schema = 1,
    owner = "example.mod",
    id = "example.mod:example_house",
    template_id = 72,
    construction_part_id = 19001,
    assets = {
        assembly = "/Game/ExampleMod/Buildings/BP_ExampleHouse.BP_ExampleHouse_C",
        construction = "/Game/ExampleMod/Buildings/BP_ExampleHouseConstruction.BP_ExampleHouseConstruction_C",
        preview = "/Game/ExampleMod/Buildings/SM_ExampleHouse.SM_ExampleHouse",
    },
    presentation = {
        name = {en_US = "Example House", fr_FR = "Maison exemple"},
        description = {en_US = "Stores supplies.", fr_FR = "Stocke des provisions."},
        card = "example_house_card",
        panel = "example_house_panel",
        icon = "/Game/ExampleMod/UI/T_ExampleHouse.T_ExampleHouse",
        worker_role = {en_US = "House Keeper", fr_FR = "Intendant"},
    },
    fields = {storageLimitGeneric = 100, bVisibleInUi = true},
})

local receipts = buildings.apply()
```

This example clones the native storage behavior selected by template 72. Its name does not give it residential behavior. Choose a verified native template and compatible assembly for the gameplay behavior you intend. The supported standalone assembly contract currently uses StaticMeshActor with a `MainBld_<construction_part_id>_GEN_VARIABLE` shell. Construction classes derive from the native Construction class. Asset loading validates the owned namespace, class parents, shell mesh and top-level soft paths. Arbitrary combinations of native residential/manor systems require their own engine capability verification.

## Definitions and stable identities

Definitions use schema 1 and namespaced IDs owned by the declaring package. Numeric building IDs are allocated against the live table and persisted in `State/buildings.ids`. Construction and upgrade identities have separate domains. IDs remain reserved when content is retired. Repeated reservations preserve their numbers; attempts to remap an identity or occupy a foreign native ID fail.

Cooked component tags contain construction part IDs, so reserve that identity before authoring the asset. `buildings.identities.reserve("parts", "example.mod:example_house", 19001)` persists a chosen free part ID. An existing part from a prior content delivery requires an explicit ownership migration. `numeric_id` and `upgrade.id` can also be supplied to seed known stable IDs. `inspect().entries` reports the resolved identities.

`row_prepared = true` supports migrating already-created rows. It requires a matching `native_label` and explicit identity ownership checks. Ruralities uses this path to preserve IDs 487/488 and its earlier State ledgers. New mods can let the library create their rows.

Definition values are copied and frozen on registration. Two definitions cannot share a numeric building or construction part ID. Upgrade targets must exist in the same set, name their parent and form an acyclic chain. The service rejects an active source with a disabled upgrade target.

## Fields, construction and upgrades

Construction costs can be set with `construction_goods = {{Type = 16, amt = 2}}`, and family capacity with `families = 3`. Both receive native readback checks. The native profile has a typed allowlist for common scalar Stat fields. Unknown fields fail preflight. Additional verified fields can be provided through the profile's `fields` option. Fresh rows clear inherited donor upgrade lists and assembly variations, preventing accidental native Storehouse upgrades. Row creation preserves the native template.

Use `upgrade_to` on the source and `upgraded_from` on the target. The source also supplies `upgrade = {template_id = 7, cost = {{Type = 16, amt = 2}, {Type = 17, amt = 8}}}`. The library allocates the action ID, registers its row, links the buildings and dispatches the transition through the pinned native actor path. Native eligibility and material costs are retained. Current profile bounds are 256 native upgrade bindings and 4,096 path entries per request. Transitions invoke the native construction flow; there is no runtime mesh replacement loop.

The native DLL uses owned-pointer checks, executable verification, row labels, path readback and bounded journals. Path writes work with one, two or more buildings. Each successful path operation registers a snapshot undo in the enclosing transaction. Upgrade dispatch supports multiple source/action pairs and delegates other calls to the original entry. Removing a transaction's newly-created binding leaves the pinned dispatcher safely delegating unrelated calls.

`enabled = false` retains compatibility definitions and owned assets for saved actors, while hiding placement, clearing work/family capability and omitting new upgrade binding. Package switches apply before world load. Whole-mod uninstall cannot preserve native saved references by itself. Existing cached actor behavior must be tested on reload for each changed capability.

## Presentation and UI lifecycle

English fallback text is required. Other native language columns use their supplied translation or English fallback. The service creates native name/description rows and optional worker/upgrade wording, and checks existing rows rather than replacing another owner's translations.

Card and panel values may be PNG keys in `Assets/Cards`, or owned cooked Texture2D object paths. Cooked textures bind native Stat image references before world load. PNGs use the library's texture importer and native widget callbacks. Icons use cooked owned textures or explicit allowed native references through `native_references`.

The service installs card, tooltip, inventory, worker-role and upgrade-presentation callbacks after native registration. It shares the hook broker and game-thread dispatcher when provided by the host. UI work is deferred beyond native inventory construction and refreshed after the asynchronous header load callback. `stop_ui()` unsubscribes the library's callbacks and invalidates queued work. `start_ui()` can re-enable presentation. Gameplay data stays registered while saved actors depend on it.

The default scheduler and hook broker work in the consumer Lua VM. When a sibling `MLELib/Native/buildings_name.txt` exists, consumers automatically use that shared runtime folder. They can also set `shared_directory` explicitly to a library runtime folder containing Native, Control and State. They then use the same native dispatcher and ID ledger while retaining their own asset directories and UI scopes. All native commands and ledger reservations run synchronously on the game thread. Shared native delivery must use one pinned library version. Lua callbacks still live in their respective UE4SS VMs.

## Transactions and acceptance

`apply()` runs definition preflight, owned row creation, localization, icon/image binding, world registration, upgrades and UI setup in a transaction. `transaction` can be supplied by a larger registration operation so later failures undo the library's changes too. Partial writes and failed readbacks invoke reverse-order rollback. Failed rollback marks the service as requiring reload. Identity reservations remain persisted to prevent later reinterpretation of saves.

Registration receipts explicitly retain `gameplay_verified = false`. They establish registration/readback integrity. Verify normal placement, slope/road collision, native workers, staged construction, upgrading, destruction and save/reload in the supported game before declaring a content package playable. The library's tests cover simulated multi-building registration and rollback, UI cleanup, stable identities, upgrade rows, the native memory layouts, and reproducible cross-compilation of the Windows bridge.

Run `python3 scripts/mle.py test` and `python3 scripts/build_native.py` for offline verification.

## Reusable templates

MLE Lib 0.1.4 adds templates, behavior modules and panel modules. Register the modules and template before queuing a building that uses them.

```lua
buildings.register_building_template({
    id = "example.mod:supply_room",
    native_base = 72,
    behavior = {id = "mle:native_storage"},
    interface = {
        id = "mle:native_storage_panel",
        sections = {"workers", "storage", "accepted_goods"},
    },
    defaults = {
        families = 2,
        fields = {storageLimitGeneric = 100, needsRoad = true},
    },
})
-- In your building definition, supply template = "example.mod:supply_room".
```

Each template selects a native row baseline on this game profile. Buildings using it supply their own identity, assets and presentation. A building can override template fields by key and replace the template's family count and construction goods. Existing prepared rows may retain their original native baseline during migration. The native storage panel uses the game's existing controls. Its section list describes the native capabilities the template uses.

Custom behavior modules declare status keys and action handlers. Each panel section lists the status and actions it needs. A mismatch fails before building registration. See [the recipe panel example](../examples/recipe_panel.lua) for a complete composition example with a consumer-supplied widget renderer.

Call `attach_instance(building_id, stable_instance_key, actor, saved_state)` from your world integration on placement or reload. Its return value provides `get_status()`, `invoke(action, argument)`, `tick(elapsed)`, `snapshot()` and `detach(reason)`. The host supplies stable placed-building keys, schedules gameplay ticks, persists snapshots alongside its saves and detaches instances when their actors are demolished or the world unloads. The optional behavior callbacks are `validate(options, definition)`, `create(context, saved_state)`, `read(context, state)`, `tick(context, state, elapsed)`, `save(context, state)` and `detach(context, state, reason)`. Actions validate gameplay inputs and own mutations.

A custom panel's `mount(screen, ui)` receives the native Inventory screen, selected sections, panel options and the behavior's status/action interface. It returns a cleanup callback. MLE Lib mounts it when a visible Inventory screen targets an attached actor and cleans it up when that screen closes, switches actors, or the library UI stops. The panel author supplies the widgets and their event bindings. Custom production scheduling and the Oil Press migration are separate from recipe-selection plumbing.

# Building registration API

`mle_lib.buildings` provides a declarative registration service. The current implementation validates ownership, numeric and construction-part identities, required presentation fields, upgrade references and cycles. It freezes input definitions and runs all preflights before starting an atomic registration transaction. It refuses registration after world load.

The native_buildings adapter creates owned rows, applies profile-authorized fields, runs presentation registration and upgrade binding, and verifies the result. building_world registers arbitrary-length lists of owned assembly/construction definitions through injected native path writers. Ruralities now uses these services for its two prepared barn rows. The current native bridge transport in Ruralities still accepts exactly two rows, and its UI callbacks remain consumer integration. Generalizing that transport and extracting the remaining UI and upgrade bridge code are outstanding. Offline tests do not establish loaded-world behavior.

```lua
local Buildings = require("mle_lib.buildings")
local buildings = Buildings.new({
    before_world_load = adapter.before_world_load,
    adapter = adapter,
})

buildings.register_building({
    schema = 1,
    owner = "example.mod",
    id = "example.mod:example_house",
    numeric_id = 600, -- Illustrative. Check against a persisted identity ledger.
    template_id = 72,
    construction_part_id = 19000,
    assets = {
        assembly = "/Game/ExampleMod/Buildings/BP_ExampleHouse.BP_ExampleHouse_C",
        construction = "/Game/ExampleMod/Buildings/BP_ExampleHouseConstruction.BP_ExampleHouseConstruction_C",
        preview = "/Game/ExampleMod/Buildings/SM_ExampleHouse.SM_ExampleHouse",
    },
    presentation = {
        name = {en_US = "Example House", fr_FR = "Maison exemple"},
        description = {en_US = "An example building.", fr_FR = "Un bâtiment exemple."},
        card = "example_house_card",
        panel = "example_house_panel",
        icon = "example_house_icon",
    },
    fields = {storageLimitGeneric = 100},
})

local receipt = buildings.apply()
```

The adapter is mandatory and has three operations.

- `preflight(definition)` returns true after checking game/build compatibility, schema, row availability, fields, assets, presentation resources and native capabilities. Every definition is checked before the first registration write.
- `register(definition, transaction)` applies the definition and returns a receipt. Use `transaction.table(data)` for owned row insertions. Register rollback with `transaction.defer(undo)` before every other mutation. An undo must throw when restoration fails. It must preserve native template rows, live actors and unrelated packages.
- `verify(definition, receipt)` returns true after reading back all registered building references, presentation, upgrade actions and native fields. These checks establish registration integrity. Gameplay acceptance is separate.

No registration is silently skipped. Failed registration leaves the service failed, and a failed registered undo marks it `reload_required`. Repeated apply is refused. Do not remove registered rows from a loaded world to disable a package. Save identity preservation, runtime lifecycle and compatibility-only package resources require the native adapter and package host integration.

`upgrade_to` and `upgraded_from` use namespaced IDs. Both ends must exist in the same registration set and agree. Cycles are rejected. Numeric IDs are caller supplied for now; collision checks against the actual game and persistent allocation belong in native preflight. The service currently accepts opaque asset/presentation references and native fields; their engine type and namespace validation belong in that preflight.

## Remaining acceptance work

1. Extract Ruralities' pinned assembly, construction-part, preview and upgrade writers into the native library adapter. Generalize the current two-barn native protocol before advertising arbitrary building counts.
2. Bind localization, construction cards, badges, tooltips and inventory banners through library-owned UI lifecycles.
3. Integrate persisted numeric identities, independently enabled package resources, save companions and callback cleanup.
4. Move reusable authoring/cooking/packaging checks into SDK tooling while keeping consumer meshes and rules in their packages.
5. Migrate the actual Ruralities barn registration through this API and its production adapter. Repair the reported lighting/upgrade defects and run native construction/upgrade acceptance before claiming complete support.

Run `LUA_PATH='src/?.lua;;' lua tests/test_buildings.lua` and `python3 scripts/mle.py test` for offline verification.

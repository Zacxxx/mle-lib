# Registry and vanilla patches

`mle_lib.registry` records ownership of namespaced definitions and composes typed patches against the original values. The game adapter authorizes a field through the profile allowlist and supplies the functions that read and write it. Adapter functions run synchronously on the game thread when used with Manor Lords.

```lua
local Registry = require("mle_lib.registry")
local registry = Registry.new({
    fields = {buildings = {storage = "integer"}},
    read = adapter.read,
    write = adapter.write,
    can_write = adapter.is_registration_phase,
    exists = adapter.reference_exists,
})

registry:register("example.balance", {
    id = "example.balance:storage/warehouse",
    schema = 1,
    patches = {
        {target = {domain = "buildings", id = "72"}, field = "storage", op = "add", value = 100},
    },
})
registry:freeze()
registry:apply()
```

The example uses a hypothetical `storage` alias. The profile must resolve it to a verified game field before supplying it in the allowlist. The adapter receives row IDs as strings. A write can return `false` to refuse mutation, and the registry verifies all writes through the supplied reader.

Every definition needs an owner package ID, a namespaced ID and a positive integer schema version. The optional `references` array names other registered definitions or native resources recognized by `exists`. The registry checks these links at freeze. On a host with multiple packages, register them in the deterministic activation order returned by the package host.

Supported field types are `integer`, `number`, `boolean`, `string` and `reference_list`. Every type supports `set`. Numeric types support `add` and `multiply`. Reference lists support `append` and `remove` by namespaced key. Different `set` values for the same target produce a conflict report containing the field and all affected owners.

`apply()` returns the number of fields changed and always starts from the baseline captured by the first successful transaction. A verified rollback follows a partial write failure. A later call refuses a field changed by another system. The registry requires a fresh game session after a failed rollback.

`unregister(owner, id)` removes a definition after validating references from remaining definitions. A subsequent `apply()` materializes the remaining patch set. `restore()` restores the known baseline through the same checks and clears the current snapshots. A baseline-restored game field may still affect newly created entities only when the game caches data on existing actors. Each adapter must document the applicable reload behavior.

`inspect()` returns registration state and an ordered list of definition IDs, owners, schemas and patch counts. All registry tests run with `lua tests/test_registry.lua`.

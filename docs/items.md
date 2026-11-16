# Items and recipes

MLE Lib 0.1.6 provides `mle_lib.items` for native item and recipe definitions. The current Manor Lords profile stores both in the same item table and numeric ID space. Use the library from a verified game profile before loading a world. The caller supplies the item table, the main-menu phase guard and persisted numeric IDs.

Register commodities with `register_item` and recipes with `register_recipe`. A recipe can reference an existing numeric item ID or a namespaced item queued on the same service. For assets and fields outside the declared API, rows inherit their native template defaults. The item registration accepts native storage and category values, a raw crafting sentinel and tradeability. A recipe declares its inputs, outputs, row template and crafting metadata template. An optional category template supplies native category fields. A retained retired recipe has empty inputs and outputs.

`apply()` preflights the set, inserts rows, verifies fields and checks the native goods arrays. A failed write rolls back the set. Supply a library row transaction as `apply(transaction)` to compose this with other registration writes. The caller owns committing or rolling back that enclosing transaction.

See [the board recipe example](../examples/items_and_recipes.lua). The example registers a row and its recipe, and the gameplay host decides when and how workers can execute it. Item-specific artwork and localization, a shared allocator across packages, production scheduling, custom actor lifecycles and managed save-aware systems still need dedicated adapters. Existing package lifecycle, hook, scheduler, sidecar and building panel APIs remain available to those adapters.

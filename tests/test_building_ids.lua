local Ids = require("mle_lib.building_ids")
local saved
local api = {read = function() return saved end, write = function(value) saved = value end,
    minimums = {buildings = 486, parts = 18500, upgrades = 116},
    occupied = function(_, id) return id == 487 end}
local ledger = Ids.new(api)
assert(ledger.reserve("buildings", "example.mod:house") == 488)
assert(ledger.reserve("parts", "example.mod:house") == 18501)
assert(Ids.new(api).reserve("buildings", "example.mod:house") == 488)
assert(not pcall(ledger.reserve, "buildings", "example.mod:other", 488))
assert(not pcall(ledger.reserve, "buildings", "example.mod:house", 489))
assert(not pcall(ledger.reserve, "buildings", "example.mod:other", 487))
assert(ledger.reserve("buildings", "example.mod:other") == 489)
print("PASS: persisted building IDs, native collisions, deterministic allocation and no remapping")

local first, second = Ids.new(api), Ids.new(api)
assert(first.reserve("buildings", "other.mod:house") == 490)
assert(second.reserve("buildings", "third.mod:house") == 491)
assert(first.reserve("buildings", "fourth.mod:house") == 492)
print("PASS: shared ledger readers preserve reservations made by other consumers")

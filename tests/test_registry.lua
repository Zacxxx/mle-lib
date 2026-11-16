package.path = "src/?.lua;" .. package.path
local Registry = require("mle_lib.registry")

local function rejected(call, expected)
    local ok, message = pcall(call)
    assert(not ok and tostring(message):find(expected, 1, true), tostring(message))
    return message
end

local function fixture()
    local row = {storage = 100, workers = 2, accepted = {"vanilla:timber", "vanilla:planks"}}
    local counters = {writes = 0, phase = "registration"}
    local registry = Registry.new({
        read = function(target, field)
            assert(target.domain == "buildings" and target.id == "72")
            return row[field]
        end,
        write = function(_, field, value)
            counters.writes = counters.writes + 1
            row[field] = value
            if counters.fail_at == counters.writes then error("interrupted native write") end
        end,
        fields = {buildings = {storage = "integer", workers = "integer", accepted = "reference_list"}},
        exists = function(id) return id == "vanilla:timber" or id == "vanilla:planks" end,
        can_write = function() return counters.phase == "registration" end,
    })
    return registry, row, counters
end

local function patch(field, op, value)
    return {target = {domain = "buildings", id = 72}, field = field, op = op, value = value}
end

local registry, row, counters = fixture()
rejected(function() registry:register("foreign", {id = "example.storage:unclaimed", schema = 1}) end, "MLE_REGISTRY_OWNER")
registry:register("example.crops", {id = "example.crops:items/hay", schema = 1})
registry:register("example.storage", {id = "example.storage:capacity", schema = 1,
    patches = {patch("storage", "add", 50), patch("accepted", "append", "example.crops:items/hay")}})
registry:register("example.balance", {id = "example.balance:warehouse", schema = 1,
    patches = {patch("storage", "multiply", 2), patch("workers", "set", 3), patch("accepted", "remove", "vanilla:planks")}})
rejected(function() registry:apply() end, "MLE_REGISTRY_OPEN")
rejected(function() registry:register("foreign", {id = "example.storage:capacity", schema = 1}) end, "example.storage")
registry:freeze()
rejected(function() registry:register("late", {id = "late:item", schema = 1}) end, "MLE_REGISTRY_FROZEN")
counters.phase = "world"
rejected(function() registry:apply() end, "MLE_PATCH_LIFECYCLE")
assert(counters.writes == 0)
counters.phase = "registration"
assert(registry:apply() == 3 and row.storage == 300 and row.workers == 3)
assert(table.concat(row.accepted, ",") == "vanilla:timber,example.crops:items/hay")
assert(registry:apply() == 0 and row.storage == 300 and counters.writes == 3, "Repeated apply must not multiply the result")
rejected(function() registry:unregister("foreign", "example.balance:warehouse") end, "MLE_REGISTRY_OWNER")
rejected(function() registry:unregister("example.crops", "example.crops:items/hay") end, "MLE_REGISTRY_REFERENCE")
assert(registry:unregister("example.balance", "example.balance:warehouse"))
assert(registry:apply() == 3 and row.storage == 150 and row.workers == 2)
assert(table.concat(row.accepted, ",") == "vanilla:timber,vanilla:planks,example.crops:items/hay")
row.storage = 111
rejected(function() registry:restore() end, "MLE_PATCH_DRIFT")
assert(row.storage == 111 and #row.accepted == 3, "External drift must prevent the whole transaction")
row.storage = 150
assert(registry:restore() == 2 and row.storage == 100 and #row.accepted == 2)
assert(registry:apply() == 2 and row.storage == 150)
assert(registry:inspect().definitions[2].owner == "example.storage")

registry, row, counters = fixture()
for index, owner in ipairs({"alice", "bruno", "carol"}) do
    registry:register(owner, {id = owner .. ":change", schema = 1, patches = {patch("storage", "set", 9 + index)}})
end
local issue = rejected(function() registry:freeze() end, "MLE_PATCH_CONFLICT")
assert(issue:find("alice", 1, true) and issue:find("bruno", 1, true) and issue:find("carol", 1, true))
assert(counters.writes == 0 and row.storage == 100)
rejected(function()
    registry:register("alice", {id = "alice:illegal", schema = 1, patches = {patch("blueprint", "set", "/Game/Foo")}})
end, "MLE_PATCH_FIELD")
assert(registry:unregister("bruno", "bruno:change") and registry:unregister("carol", "carol:change"))
registry:register("alice", {id = "alice:workers", schema = 1, patches = {patch("workers", "add", 3)}})
registry:freeze()
counters.fail_at = 2
rejected(function() registry:apply() end, "interrupted native write")
assert(row.storage == 100 and row.workers == 2, "Rollback must include the partially written field")
assert(registry:apply() == 2 and row.storage == 10 and row.workers == 5)

registry, row, counters = fixture()
row.storage = math.maxinteger
registry:register("one", {id = "one:overflow", schema = 1, patches = {patch("storage", "add", 1)}})
registry:freeze()
rejected(function() registry:apply() end, "MLE_PATCH_RANGE")
assert(counters.writes == 0 and row.storage == math.maxinteger)

print("PASS registered owners and references; composed and restored baseline; rejected conflicts, drift and overflow; rolled back a partial native write")

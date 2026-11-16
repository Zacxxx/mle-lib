local Upgrade = require("mle_lib.building_upgrade")
local Rows = require("mle_lib.rows")
local function array(values)
    values.Empty = function(self) for index = #self, 1, -1 do self[index] = nil end end
    return values
end
local function name(value) return {GetComparisonIndex = function() return value end} end
local source = {DisplayName = name(100), upgrades = array({}), GetStructAddress = function() return 1000 end}
local target = {DisplayName = name(101), upgradedFrom = -1, GetStructAddress = function() return 2000 end}
local actions = {["7"] = {Name = "Native", upgradesInto = 99, cost = array({{Type = 16, amt = 2}})}}
local tables = {buildings = {FindRow = function(_, id) return id == "600" and source or target end},
    upgrades = {FindRow = function(_, id) return actions[id] end,
        AddRow = function(_, id, template)
            actions[id] = {Name = template.Name, upgradesInto = template.upgradesInto, cost = array({}),
                GetStructAddress = function() return 3000 end}
        end,
        RemoveRow = function(_, id) actions[id] = nil end}}
local d = {id = "example.mod:house", numeric_id = 600, native_label = "House", upgrade_to = "example.mod:large_house",
    upgrade = {id = 200, template_id = 7, cost = {{Type = 17, amt = 3}}}}
local definitions = {d, {id = "example.mod:large_house", numeric_id = 601}}
local bound, fail = false, true
local api = {buildings = tables.buildings, upgrades = tables.upgrades, bridge = {
    upgrade = function(entry, tx)
        assert(entry.source == 600 and entry.target == 601 and entry.action == 200)
        tx.defer(function() bound = false end); bound = true
        assert(not fail, "injected hook failure")
    end}}
assert(not pcall(Rows.run, function(tx) Upgrade.install(d, definitions, api, tx) end))
assert(not bound and actions["200"] == nil and #source.upgrades == 0 and target.upgradedFrom == -1)
fail = false
Rows.run(function(tx) Upgrade.install(d, definitions, api, tx) end)
assert(bound and source.upgrades[1] == 200 and target.upgradedFrom == 600 and actions["200"].cost[1].amt == 3)
assert(actions["7"].Name == "Native" and actions["7"].upgradesInto == 99)
print("PASS: generic upgrade creation, native binding, material costs and rollback")

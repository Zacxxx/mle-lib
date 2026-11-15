local Native = require("mle_lib.native_buildings")
local Buildings = require("mle_lib.buildings")
local rows = {["72"] = {DisplayName = "Storehouse", capacity = 250}}
local data = {
    FindRow = function(_, id) return rows[id] end,
    AddRow = function(_, id, source)
        local row = {}; for key, value in pairs(source) do row[key] = value end; rows[id] = row
    end,
    RemoveRow = function(_, id) rows[id] = nil end,
}
local events, fail, profile = {}, false, true
local api = {buildings = data, fields = {capacity = true}, make_name = tostring,
    assert_profile = function() assert(profile, "profile changed") end,
    presentation = function(d, row, transaction)
        transaction.defer(function() row.banner = nil end)
        row.banner = d.presentation.panel
        events[#events + 1] = "presentation"
    end,
    world = function(definitions)
        assert(rows["600"].banner == "panel")
        assert(not fail, "injected world binding failure")
        events[#events + 1] = "world"
        return {mode = "standalone"}
    end,
    upgrade = function() error("Unexpected upgrade") end,
}
local d = {schema = 1, id = "example.mod:house", owner = "example.mod", numeric_id = 600,
    template_id = 72, template_label = "Storehouse", native_label = "ExampleHouse", construction_part_id = 19000,
    assets = {assembly = "assembly", construction = "construction", preview = "preview"},
    presentation = {name = {en_US = "House"}, description = {en_US = "Description"}, card = "card", panel = "panel", icon = "icon"},
    fields = {capacity = 100}}
local function registry()
    local service = Buildings.new({before_world_load = function() return true end, adapter = Native.new(api)})
    service.register_building(d)
    return service
end
fail = true
assert(not pcall(registry().apply) and not rows["600"] and rows["72"].capacity == 250)
fail = false; profile = false
assert(not pcall(registry().apply) and not rows["600"])
profile = true
registry().apply()
assert(rows["600"].capacity == 100 and rows["600"].DisplayName == "ExampleHouse")
assert(rows["72"].DisplayName == "Storehouse" and rows["72"].banner == nil)
assert(not pcall(registry().apply), "Foreign occupied ID must be refused")
print("PASS: native building creation, native template preservation, profile gate, presentation and world rollback")

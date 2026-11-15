local Buildings = require("mle_lib.buildings")
local function definition(id, number)
    return {schema = 1, id = "example.mod:" .. id, owner = "example.mod", numeric_id = number,
        template_id = 72, construction_part_id = number + 1000,
        assets = {assembly = "assembly", construction = "construction", preview = "preview"},
        presentation = {name = {en_US = id}, description = {en_US = "Description"},
            card = "card", panel = "panel", icon = "icon"}}
end
local live, events, reject = {}, {}, nil
local adapter = {
    preflight = function(d) events[#events + 1] = "preflight"; return true end,
    register = function(d, transaction)
        transaction.defer(function() live[d.id] = nil end)
        live[d.id] = d
        events[#events + 1] = "register"
        if reject == "write" then error("injected partial failure") end
        return {id = d.numeric_id}
    end,
    verify = function(d) return reject ~= "verify" and live[d.id].numeric_id == d.numeric_id end,
}
local function service(guard)
    return Buildings.new({adapter = adapter, before_world_load = function() return guard ~= false end})
end
local s = service()
local first, second = definition("house", 600), definition("large_house", 601)
first.upgrade_to, second.upgraded_from = second.id, first.id
s.register_building(first); s.register_building(second)
first.numeric_id = 999
assert(not pcall(s.register_building, definition("other", 600)))
local receipts = s.apply()
assert(live["example.mod:house"].numeric_id == 600 and receipts[second.id].id == 601)
assert(events[1] == "preflight" and events[2] == "preflight" and events[3] == "register")
assert(s.inspect().state == "registered" and not pcall(s.apply))
assert(not pcall(s.register_building, definition("extra", 602)))
for _, failure in ipairs({"write", "verify"}) do
    live, events, reject = {}, {}, failure
    local failed = service(); failed.register_building(definition("house", 600))
    assert(not pcall(failed.apply) and next(live) == nil and failed.inspect().state == "failed")
end
reject = nil
local missing = service(); local d = definition("house",600); d.upgrade_to = "example.mod:absent"
missing.register_building(d); assert(not pcall(missing.apply))
local blocked = service(false); blocked.register_building(definition("house",600)); assert(not pcall(blocked.apply))
local incomplete = definition("house",600); incomplete.presentation.icon = nil
assert(not pcall(service().register_building, incomplete))
local original_undo = adapter.register
adapter.register = function(d,t) t.defer(function() error("undo failed") end); error("write failed") end
local poisoned = service(); poisoned.register_building(definition("house",600)); assert(not pcall(poisoned.apply))
assert(poisoned.inspect().state == "reload_required")
adapter.register = original_undo
print("PASS: building ownership, frozen definitions, preflight, upgrade links, rollback and phase guard")

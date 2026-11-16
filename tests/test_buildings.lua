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

local Rows = require("mle_lib.rows")
local outer_service
assert(not pcall(Rows.run, function(transaction)
    outer_service = Buildings.new({adapter = adapter, transaction = transaction, before_world_load = function() return true end})
    outer_service.register_building(definition("outer", 700))
    outer_service.apply()
    assert(live["example.mod:outer"])
    error("later package failed")
end))
assert(not live["example.mod:outer"] and outer_service.inspect().state == "rolled_back")
print("PASS: enclosing package transaction rolls back building registration and updates its status")

local composed = service()
composed.register_building_behavior({
    id = "example.mod:recipes",
    status = {recipe = true},
    create = function(context, saved) return saved or {recipe = context.options.initial} end,
    read = function(_, state) return state end,
    save = function(_, state) return state end,
    actions = {select_recipe = function(_, state, recipe)
        assert(recipe == "boards" or recipe == "beams", "Unsupported recipe")
        state.recipe = recipe
    end},
})
local panel_api, closed
composed.register_building_panel({
    id = "example.mod:workshop_panel",
    sections = {recipe_picker = {status = {"recipe"}, actions = {"select_recipe"}}},
    mount = function(_, ui)
        panel_api = ui
        return function() closed = true end
    end,
})
local function template(id, behavior)
    return {id = id, native_base = 72, behavior = {id = behavior, options = {initial = "boards"}},
        interface = {id = "example.mod:workshop_panel", sections = {"recipe_picker"}},
        defaults = {families = 2, fields = {needsRoad = true, storageLimitGeneric = 100}}}
end
composed.register_building_template(template("example.mod:bad", "mle:native_storage"))
local workshop = definition("workshop", 701)
workshop.template_id, workshop.template = nil, "example.mod:bad"
local ok, reason = pcall(composed.register_building, workshop)
assert(not ok and reason:find("lacks panel status", 1, true))
composed.register_building_template(template("example.mod:workshop", "example.mod:recipes"))
workshop.template, workshop.fields = "example.mod:workshop", {storageLimitGeneric = 200}
composed.register_building(workshop)
local larger = definition("larger_workshop", 702)
larger.template_id, larger.template = nil, workshop.template
composed.register_building(larger)
composed.apply()
assert(live[workshop.id].fields.storageLimitGeneric == 200 and live[larger.id].fields.storageLimitGeneric == 100)
assert(live[workshop.id].fields.needsRoad and live[workshop.id].families == 2)
local first_shop = composed.attach_instance(701, "site-1")
local second_shop = composed.attach_instance(701, "site-2")
local unmount = composed.mount_panel(701, {}, first_shop)
panel_api.invoke("select_recipe", "beams")
assert(panel_api.get_status().recipe == "beams" and second_shop.get_status().recipe == "boards")
assert(not pcall(panel_api.invoke, "select_recipe", "unknown"))
local save = first_shop.snapshot()
first_shop.detach("save reload")
unmount(); unmount()
assert(closed and not pcall(panel_api.get_status))
assert(composed.attach_instance(701, "site-1", nil, save).get_status().recipe == "beams")
print("PASS: template overrides, capability checks, isolated behavior, panel actions and state restore")

local mixed = service()
local menu, placed, cleaned
local configure = assert(loadfile("examples/workshop_yard.lua"))()
configure(mixed, {
    supports_plot = function(d, options) return d.template_id == 72 and options.road_snap end,
    begin_plot = function(id, context, options)
        assert(id == 703 and context.player and options.road_snap)
        return "preview_started"
    end,
    list_improvements = function(_, options) return options.allowed end,
    place_improvement = function(actor, id, options)
        assert(actor:GetType() == 703 and id == options.allowed[1], "Improvement not allowed")
        placed = id
        return true
    end,
    mount_improvements = function(_, ui)
        menu = ui
        return function() cleaned = true end
    end,
})
local yard_shop = definition("yard_workshop", 703)
yard_shop.template_id, yard_shop.template = nil, "example.mod:workshop_with_yard"
yard_shop.fields = {storageLimitGeneric = 200}
mixed.register_building(yard_shop)
local variant = definition("workshop_without_yard", 704)
variant.template_id, variant.template, variant.yard = nil, yard_shop.template, false
mixed.register_building(variant)
assert(not pcall(mixed.begin_placement, 703, {player = true}))
mixed.apply()
assert(live[yard_shop.id].fields.needsRoad and live[yard_shop.id].families == 2)
assert(live[yard_shop.id].fields.storageLimitGeneric == 200)
assert(mixed.begin_placement(703, {player = true}) == "preview_started")
assert(not mixed.panel_mounts(704))
local actor = {GetType = function() return 703 end, GetAddress = function() return 7003 end}
local instance = mixed.attach_instance(703, "yard-site", actor)
assert(not pcall(mixed.attach_instance, 704, "wrong-site", actor))
local close = mixed.mount_panel(703, {}, instance)
assert(menu.title.en_US == "Yard Improvements" and menu.list()[1] == "example.mod:drying_rack")
assert(not pcall(menu.place, "example.mod:forbidden") and placed == nil)
assert(menu.place("example.mod:drying_rack") and placed == "example.mod:drying_rack")
close()
assert(cleaned and not pcall(menu.list))
assert(mixed.inspect().entries[yard_shop.id].placement == "example.mod:plot")
print("PASS: mixin precedence, placement dispatch, yard menu routing and per-building overrides")

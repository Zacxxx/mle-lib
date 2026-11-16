local Ids = require("mle_lib.building_ids")
local Runtime = require("mle_lib.runtime")

local ledger
local function goods()
    return {Empty = function(self) for index = #self, 1, -1 do self[index] = nil end end}
end
local function boot(reject_patch)
    local native = {Name = "Native", ItemCategory = 2, Subcategory = 0, craftingTool = 2,
        craftingAnim = 3, creationProg = 4, Resources = goods(), craftingOutput = goods()}
    local rows = {["1"] = native, ["503"] = native}
    local ids = Ids.new({
        domains = {"items"}, minimums = {items = 500}, maximums = {items = 504},
        read = function() return ledger end,
        write = function(value) ledger = value end,
        occupied = function(_, number) return rows[tostring(number)] ~= nil end,
    })
    local runtime = Runtime.new({
        register_hook = function() error("unexpected hook") end,
        registry = {
            fields = {buildings = {capacity = "integer"}},
            read = function() return 25 end,
            write = function() assert(not reject_patch, "Injected registry failure") end,
        },
        items = {
            before_world_load = function() return true end,
            reserve = function(id, number) return ids.reserve("items", id, number) end,
            items = {
                FindRow = function(_, id) return rows[id] end,
                RemoveRow = function(_, id) rows[id] = nil end,
                AddRow = function(_, id, template)
                    local row = {}
                    for name, value in pairs(template) do row[name] = value end
                    row.Resources, row.craftingOutput = goods(), goods()
                    rows[id] = row
                end,
            },
        },
    })
    return runtime, rows
end

local function descriptor(id)
    return {id = id, version = "1.0.0", engine = "*", capabilities = {"mle.items", "mle.registry"}}
end

local function item(id, number)
    return {id = id, name = "Timber", numeric_id = number, template_id = 1,
        storage = 0, category = 2, subcategory = 0, crafting_tool = 0, tradeable = true}
end

local function declare(runtime, patch)
    runtime:register(descriptor("test.items"), function(context)
        local register_item = context.services.register_item
        assert(not pcall(register_item, item("test.foreign:timber", 504)))
        assert(register_item(item("test.items:timber", 501)) == 501)
        if patch then
            context.services.register({id = "test.items:patch", schema = 1, patches = {{
                target = {domain = "buildings", id = "1"}, field = "capacity", op = "add", value = 5,
            }}})
        end
    end)
    runtime:register(descriptor("test.recipes"), function(context)
        context.services.register_recipe({id = "test.recipes:craft", name = "Craft",
            template_id = 1, crafting_template_id = 1, inputs = {{item = "test.items:timber", amount = 2}},
            outputs = {{item = 1, amount = 1}}})
    end)
end

local runtime, rows = boot(true)
declare(runtime, true)
assert(runtime:start())
assert(not pcall(runtime.apply_registry, runtime))
assert(not rows["501"] and not rows["502"] and runtime:inspect().item_rows == 0)
assert(runtime:stop())

runtime, rows = boot(false)
declare(runtime)
assert(runtime:start())
runtime:apply_registry()
assert(rows["502"].Resources[1].Type == 501 and runtime:inspect().item_rows == 2)
assert(runtime:stop())
assert(not rows["501"] and not rows["502"])

runtime, rows = boot(false)
runtime:register(descriptor("test.foreign"), function(context)
    context.services.register_item(item("test.foreign:timber", 501))
end)
local active, failure = runtime:start()
assert(not active and failure.message:find("Preferred identity reserved", 1, true))
assert(not rows["501"])

runtime = boot(false)
runtime:register(descriptor("test.items"), function(context)
    context.services.register_item(item("test.items:timber", 505))
end)
active, failure = runtime:start()
assert(not active and failure.message:find("Saved identity cannot be remapped", 1, true))
print("PASS: shared item and recipe registration, rollback, and persistent numeric ownership")

runtime, rows = boot(false)
runtime:register(descriptor("test.later"), function(context)
    assert(context.services.register_item(item("test.later:timber")) == 504)
    local available, reason = pcall(context.services.register_item, item("test.later:extra"))
    assert(not available and reason:find("Identity space exhausted", 1, true))
end)
assert(runtime:start())
runtime:apply_registry()
assert(rows["503"].Name == "Native" and rows["504"] and not rows["501"] and not rows["502"])

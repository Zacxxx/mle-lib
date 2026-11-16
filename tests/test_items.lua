local Items = require("mle_lib.items")
local function goods()
    return {Empty = function(self) for i = #self, 1, -1 do self[i] = nil end end}
end
local native = {Name = "Native", ItemCategory = 12, Subcategory = 0, craftingTool = 2,
    craftingAnim = 3, creationProg = 4, Resources = goods(), craftingOutput = goods()}
local rows, fail = {["1"] = native}, false
local data = {
    FindRow = function(_, id) return rows[id] end,
    AddRow = function(_, id, source)
        local row = {}
        for key, value in pairs(source) do row[key] = value end
        row.Resources, row.craftingOutput = goods(), goods()
        rows[id] = row
        if fail and id == "502" then error("injected native row failure") end
    end,
    RemoveRow = function(_, id) rows[id] = nil end,
}
local function setup(allowed, input)
    local content = Items.new({items = data, before_world_load = function() return allowed end})
    content.register_recipe({id = "example.mod:make", numeric_id = 502, template_id = 1,
        crafting_template_id = 1, name = "Make", inputs = {{item = input, amount = 2}}, outputs = {{item = 1, amount = 1}}})
    content.register_item({id = "example.mod:wood", numeric_id = 501, template_id = 1, name = "Wood",
        storage = 0, category = 2, subcategory = 1, crafting_tool = 0, tradeable = true})
    return content
end
assert(not pcall(setup(false, 1).apply))
assert(not pcall(setup(true, "example.mod:missing").apply))
assert(not rows["501"] and not rows["502"])
fail = true
assert(not pcall(setup(true, "example.mod:wood").apply))
assert(not rows["501"] and not rows["502"])
fail = false
local receipt = setup(true, "example.mod:wood").apply()
assert(receipt.created == 2 and rows["502"].Resources[1].Type == 501)
assert(rows["501"].tradeable and not rows["502"].tradeable and #native.Resources == 0)
assert(not pcall(setup(true, 1).apply))
print("PASS: shared item namespace, recipe reference validation, readback and partial rollback")

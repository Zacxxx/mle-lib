-- Item and recipe rows share a numeric namespace on the Manor Lords profile.
local Rows = require("mle_lib.rows")
local Items = {}

local function text(value) return type(value) == "string" and value or value:ToString() end
local function integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum and value <= 2147483647
end

local function write_goods(target, values)
    target:Empty()
    for index, good in ipairs(values) do target[index] = good end
    assert(#target == #values, "Goods array length mismatch")
    for index, good in ipairs(values) do
        assert(target[index].Type == good.Type and target[index].amt == good.amt, "Goods array readback mismatch")
    end
end

function Items.new(api)
    local data = assert(api.items)
    assert(type(api.before_world_load) == "function", "Content registration requires a phase guard")
    local self, entries, order, reserved = {}, {}, {}, {}
    local state = "collecting"

    local function register(spec, recipe)
        assert(state == "collecting", "Item registrations are frozen")
        assert(type(spec.id) == "string" and spec.id:match("^[a-z][a-z0-9_.%-]*:[a-z][a-z0-9_]*$")
            and not entries[spec.id], "Invalid or duplicate content ID")
        assert((spec.numeric_id == nil and api.reserve) or
            (integer(spec.numeric_id, 1) and not reserved[spec.numeric_id]), "Invalid or duplicate numeric item ID")
        assert(integer(spec.template_id, 1), "Native item template is required")
        assert(type(spec.name) == "string" and #spec.name > 0, "Native item name is required")
        local entry = {
            id = spec.id, numeric_id = spec.numeric_id, template_id = spec.template_id, name = spec.name,
            recipe = recipe, retired = spec.retired == true,
        }
        if recipe then
            assert(integer(spec.crafting_template_id, 1), "Native crafting metadata template is required")
            entry.crafting_template_id = spec.crafting_template_id
            entry.category_template_id = spec.category_template_id or spec.template_id
            for _, key in ipairs({"inputs", "outputs"}) do
                entry[key] = {}
                assert(type(spec[key]) == "table", "Recipe goods must be an array")
                local count = 0
                for index, good in pairs(spec[key]) do
                    assert(integer(index, 1) and index <= #spec[key], "Recipe goods must be a dense array")
                    assert(type(good) == "table" and integer(good.amount, 1)
                        and (integer(good.item, 1) or type(good.item) == "string"), "Invalid recipe good")
                    entry[key][index] = {item = good.item, amount = good.amount}
                    count = count + 1
                end
                assert(count == #spec[key], "Recipe goods must be a dense array")
                if not entry.retired then assert(count > 0, "Active recipes require inputs and outputs") end
            end
        else
            for _, key in ipairs({"storage", "category", "subcategory", "crafting_tool"}) do
                assert(integer(spec[key], key == "crafting_tool" and -1 or 0), "Invalid item field: " .. key)
                entry[key] = spec[key]
            end
            assert(type(spec.tradeable) == "boolean", "Item tradeability must be explicit")
            entry.tradeable = spec.tradeable and not entry.retired
        end
        if api.reserve then
            local id = api.reserve(entry.id, entry.numeric_id)
            assert(integer(id, 1) and not reserved[id], "Allocator returned an invalid or duplicate numeric item ID")
            assert(entry.numeric_id == nil or entry.numeric_id == id, "Allocator remapped an explicit numeric item ID")
            entry.numeric_id = id
        end
        reserved[entry.numeric_id], entries[entry.id] = entry, entry
        order[#order + 1] = entry
        return entry.numeric_id
    end

    function self.register_item(spec) return register(spec, false) end
    function self.register_recipe(spec) return register(spec, true) end

    local function row(id)
        return assert(data:FindRow(tostring(id)), "Missing native item row: " .. tostring(id))
    end

    local function resolve(goods)
        local result, seen = {}, {}
        for index, good in ipairs(goods) do
            local id = good.item
            if type(id) == "string" then id = assert(entries[id], "Unknown item reference: " .. id).numeric_id end
            local owned = reserved[id]
            if owned then assert(not owned.recipe and not owned.retired, "Recipe requires an active item")
            else row(id) end
            assert(not seen[id], "Duplicate recipe good: " .. id)
            seen[id] = true
            result[index] = {Type = id, amt = good.amount}
        end
        return result
    end

    function self.apply(outer)
        assert(state == "collecting", "Item registration already attempted")
        assert(api.before_world_load() == true, "Register items before loading a world")
        local prepared = {}
        for index, entry in ipairs(order) do
            assert(not data:FindRow(tostring(entry.numeric_id)), "Occupied item or recipe ID: " .. entry.numeric_id)
            row(entry.template_id)
            local spec = {entry = entry, fields = {Name = entry.name, tradeable = entry.tradeable or false}, inputs = {}, outputs = {}}
            if entry.recipe then
                local crafting, category = row(entry.crafting_template_id), row(entry.category_template_id)
                for _, key in ipairs({"craftingTool", "craftingAnim", "creationProg"}) do
                    spec.fields[key] = assert(crafting[key], "Missing crafting field: " .. key)
                end
                spec.fields.ItemCategory, spec.fields.Subcategory = category.ItemCategory, category.Subcategory
                if not entry.retired then spec.inputs, spec.outputs = resolve(entry.inputs), resolve(entry.outputs) end
            else
                spec.fields.storageType, spec.fields.craftingTool = entry.storage, entry.crafting_tool
                spec.fields.ItemCategory, spec.fields.Subcategory = entry.category, entry.subcategory
            end
            prepared[index] = spec
        end
        state = "applying"
        local function install(transaction)
            local target = transaction.table(data)
            local receipt = {items = {}, recipes = {}, created = 0}
            for _, spec in ipairs(prepared) do
                local entry = spec.entry
                local id = tostring(entry.numeric_id)
                target:AddRow(id, row(entry.template_id))
                local added = row(id)
                for key, value in pairs(spec.fields) do
                    added[key] = value
                    local actual = key == "Name" and text(added[key]) or added[key]
                    assert(actual == value, "Item field readback failed: " .. key)
                end
                write_goods(added.Resources, spec.inputs)
                write_goods(added.craftingOutput, spec.outputs)
                local group = entry.recipe and receipt.recipes or receipt.items
                group[entry.id] = {id = entry.numeric_id, retired = entry.retired, inputs = spec.inputs, outputs = spec.outputs}
                receipt.created = receipt.created + 1
            end
            return receipt
        end
        local ok, result
        if outer then ok, result = pcall(install, outer)
        else ok, result = pcall(Rows.run, install) end
        state = ok and "registered" or "failed"
        if not ok then error(result, 0) end
        return result
    end
    return self
end
return Items

local Upgrade = {}
local function text(value) return type(value) == "string" and value or value:ToString() end
local function values(array)
    local result = {}; for index = 1, #array do result[index] = array[index] end; return result
end
local function replace(array, content)
    array:Empty(); for index, value in ipairs(content) do array[index] = value end
end
function Upgrade.install(definition, definitions, api, transaction)
    local target
    for _, entry in ipairs(definitions) do if entry.id == definition.upgrade_to then target = entry end end
    assert(target, "Upgrade target is missing")
    local action = assert(definition.upgrade, "Upgrade action configuration missing")
    assert(math.type(action.id) == "integer" and action.id > 45 and action.id <= 4096, "Unsupported native action ID")
    local source_row = assert(api.buildings:FindRow(tostring(definition.numeric_id)))
    local target_row = assert(api.buildings:FindRow(tostring(target.numeric_id)))
    local actions = transaction.table(api.upgrades)
    local row = actions:FindRow(tostring(action.id))
    local reused = row ~= nil
    local name = action.name or definition.native_label .. "_Upgrade"
    if row then
        assert(text(row.Name) == name and row.upgradesInto == target.numeric_id, "Upgrade action collision")
    else
        local template = assert(actions:FindRow(tostring(action.template_id or 7)), "Native upgrade template missing")
        actions:AddRow(tostring(action.id), template)
        row = assert(actions:FindRow(tostring(action.id)))
        row.Name, row.upgradesInto = name, target.numeric_id
        if action.cost then replace(row.cost, action.cost) end
    end
    local previous, parent = values(source_row.upgrades), target_row.upgradedFrom
    transaction.defer(function() replace(source_row.upgrades, previous); target_row.upgradedFrom = parent end)
    local combined = values(source_row.upgrades)
    local found = false
    for _, id in ipairs(combined) do if id == action.id then found = true end end
    if not found then combined[#combined + 1] = action.id end
    replace(source_row.upgrades, combined)
    target_row.upgradedFrom = definition.numeric_id
    assert(row.upgradesInto == target.numeric_id and target_row.upgradedFrom == definition.numeric_id, "Upgrade readback failed")
    api.bridge.upgrade({source = definition.numeric_id, target = target.numeric_id, action = action.id,
        source_row = source_row:GetStructAddress(), target_row = target_row:GetStructAddress(), action_row = row:GetStructAddress(),
        source_label = source_row.DisplayName:GetComparisonIndex(), target_label = target_row.DisplayName:GetComparisonIndex()}, transaction)
    return {method = "native_actor_type_change", action_id = action.id, source_id = definition.numeric_id,
        target_id = target.numeric_id, native_target_id = target.numeric_id, reserved_action_id = action.id,
        reused = reused, gameplay_verified = false}
end
return Upgrade

local Text = require("mle_lib.building_text")
local Rows = require("mle_lib.rows")

local function translation(rows)
    return {
        IsValid = function() return true end,
        RowStruct = {GetFullName = function() return "ScriptStruct /Script/ManorLords.LocalizedText" end},
        FindRow = function(_, key) return rows[key] end,
        GetRowNames = function()
            local keys = {}
            for key in pairs(rows) do keys[#keys + 1] = key end
            return keys
        end,
        AddRow = function(_, key, source)
            local copy = {}
            for language, value in pairs(source) do copy[language] = value end
            rows[key] = copy
        end,
        RemoveRow = function(_, key) rows[key] = nil end,
    }
end

local definition = {numeric_id = 487, template_id = 72, presentation = {
    name = {en_US = "Hay Barn", fr_FR = "Grange à foin"},
    description = {en_US = "Stores hay"},
}}
local names = translation({buildingID_72 = {en_US = "Storehouse"}})
local descriptions = translation({another_building = {en_US = "Vanilla description"}})
local hover = translation({another_building = {en_US = "Vanilla tooltip"}})
local messages = {}
local api = {
    find_object = function(path)
        if path:find("BuildingNames", 1, true) then return names end
        if path:find("BuildingDescriptions", 1, true) then return descriptions end
        return hover
    end,
    report = function(message) messages[#messages + 1] = message end,
}

Rows.run(function(transaction) Text.install(definition, api, transaction) end)
assert(names:FindRow("buildingID_487").fr_FR == "Grange à foin")
assert(descriptions:FindRow("buildingID_487_descr").en_US == "Stores hay")
assert(descriptions:FindRow("another_building").en_US == "Vanilla description")
assert(not hover:FindRow("buildingID_487_descr") and #messages == 2)
assert(messages[2]:find("CDT_HoverTooltip", 1, true) and messages[2]:find("buildingID_72_descr", 1, true))

names:RemoveRow("buildingID_487")
descriptions = translation({})
local ok, reason = pcall(Rows.run, function(transaction) Text.install(definition, api, transaction) end)
assert(not ok and reason:find("DT_Translation_BuildingDescriptions", 1, true))
assert(reason:find("buildingID_487_descr", 1, true) and not names:FindRow("buildingID_487"))
print("PASS: missing optional hover donors preserve Hay Barn registration and missing required text rolls back")

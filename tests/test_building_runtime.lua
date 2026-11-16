local Runtime = require("mle_lib.building_runtime")
local Ids = require("mle_lib.building_ids")
local function valid() return true end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local names, counter = {}, 10
local function name(value)
    if not names[value] then counter = counter + 1; names[value] = counter end
    return {ToString = function() return value end, GetComparisonIndex = function() return names[value] end}
end
local function array(values)
    values = values or {}; values.Empty = function(self) for index = #self, 1, -1 do self[index] = nil end end
    return values
end
local function data(schema, rows, full_name)
    local table = {IsValid = valid, RowStruct = {GetFullName = function() return schema end}, rows = rows,
        GetFullName = function() return full_name end}
    function table:FindRow(id) return self.rows[id] end
    function table:AddRow(id, row)
        self.rows[id] = copy(row)
        self.rows[id].GetStructAddress = function() return tonumber(id) + 100000 end
    end
    function table:RemoveRow(id) self.rows[id] = nil end
    return table
end
local baseline = {DisplayName = name("Storehouse"), upgrades = array(), assemblyBlueprintVariations = array(),
    BlueprintPath = {AssetPath = {PackageName = name("/Game/Native"), AssetName = name("Native_C")}, SubPathString = ""},
    workerTypes = {Y = 3}, constructionGoods = array({{Type = 16, amt = 2}}), storageLimitGeneric = 250, purposeIcon = {GetFullName = function() return "Native icon" end}}
local buildings = data("ScriptStruct /Script/ManorLords.Stat", {["72"] = baseline})
local parts = data("ScriptStruct /Script/ManorLords.ConstructionBP", {},
    "DataTable /Game/NotStronghold/Data/DT_ConstructionBPs.DT_ConstructionBPs")
local upgrades = data("Upgrade", {})
local translations = data("ScriptStruct /Script/ManorLords.LocalizedText", {["buildingID_72"] = {}, ["buildingID_72_descr"] = {}})
local objects = {}
local root = "/Game/ExampleMod/"
local function asset(path, kind)
    return {IsValid = valid, IsChildOf = valid, GetFullName = function() return kind .. " " .. path end,
        GetCDO = function() return {IsValid = valid, IsA = valid} end}
end
local bad_icon = false
local assets = {load_class = function(path) return asset(path, "BlueprintGeneratedClass") end,
    load = function(path) return asset(path, not bad_icon and path:find("/Icons/", 1, true) and "Texture2D" or "StaticMesh") end}
local definitions = {}
for index = 1, 3 do
    local part = 19000 + index
    local prefix = root .. "House" .. index
    definitions[index] = {schema = 1, id = "example.mod:house_" .. index, owner = "example.mod", template_id = 72,
        construction_part_id = part, families = 1, construction_goods = {{Type = 16, amt = index}},
        assets = {assembly = prefix .. ".House" .. index .. "_C", construction = prefix .. "Construction.House" .. index .. "Construction_C",
            preview = prefix .. "Mesh.House" .. index .. "Mesh"},
        presentation = {name = {en_US = "House " .. index}, description = {en_US = "Description " .. index},
            card = "house_card", panel = "house_panel", icon = root .. "Icons/House.House"}, fields = {storageLimitGeneric = 100 + index}}
    local definition = definitions[index]
    if index == 2 then
        definition.assets.main_mesh = prefix .. "Foundation.House2Foundation"
    end
    objects[definition.assets.assembly .. ":MainBld_" .. part .. "_GEN_VARIABLE"] =
        {IsValid = valid, StaticMesh = asset(definition.assets.main_mesh or definition.assets.preview, "StaticMesh")}
end
local function find(path)
    if objects[path] then return objects[path] end
    if path:find("DT_ConstructionBPs", 1, true) then return parts end
    if path:find("Translation", 1, true) then return translations end
    if path == "/Script/Engine.KismetSystemLibrary" then
        return {MakeSoftClassPath = function(_, path)
            local package, object = path:match("^(.*)%.([^%.]+)$")
            return {AssetPath = {PackageName = name(package), AssetName = name(object)}, SubPathString = ""}
        end, MakeSoftObjectPath = function(_, path)
            local package, object = path:match("^(.*)%.([^%.]+)$")
            return {AssetPath = {PackageName = name(package), AssetName = name(object)}, SubPathString = ""}
        end}
    end
    return {IsValid = valid}
end
local saved, calls = nil, {}
local identities = Ids.new({read = function() return saved end, write = function(value) saved = value end,
    minimums = {buildings = 486, parts = 18500, upgrades = 116},
    occupied = function(domain, id) return domain == "buildings" and buildings:FindRow(tostring(id)) ~= nil end})
local function make_service()
return Runtime.new({ui = false, directory = "fixture", asset_root = root, assets = assets, buildings = buildings,
    upgrades = upgrades, items = {FindRow = function(_, id) return id == "16" and {} or nil end}, identities = identities, find_object = find, make_name = name, read_artwork = function() return "PNG" end,
    before_world_load = function() return true end, game_version = function() return "Version 0.8.117" end,
    bridge = {paths = function(kind, entries, transaction)
        assert(#entries == 3, "Building pipeline must support arbitrary counts")
        calls[#calls + 1] = kind
        transaction.defer(function() calls[#calls] = nil end)
    end, upgrade = function() error("Unexpected upgrade") end}})
end
bad_icon = true
local rejected = make_service()
for _, definition in ipairs(definitions) do rejected.register_building(definition) end
assert(not pcall(rejected.apply))
assert(not buildings:FindRow("487") and not translations:FindRow("buildingID_487"), "Invalid icon must roll back registration")
bad_icon = false
local service = make_service()
for _, definition in ipairs(definitions) do service.register_building(definition) end
service.apply()
assert(service.inspect().state == "registered" and calls[1] == 1 and calls[2] == 0)
assert(buildings:FindRow("487").storageLimitGeneric == 101 and buildings:FindRow("489").storageLimitGeneric == 103)
assert(translations:FindRow("buildingID_487").en_US == "House 1")
assert(translations:FindRow("buildingID_489_descr").en_US == "Description 3")
assert(buildings:FindRow("487").workerTypes.Y == 1 and buildings:FindRow("489").constructionGoods[1].amt == 3)
assert(baseline.workerTypes.Y == 3 and baseline.constructionGoods[1].amt == 2)
assert(baseline.storageLimitGeneric == 250 and baseline.BlueprintPath.AssetPath.PackageName:ToString() == "/Game/Native")
print("PASS: complete native building runtime, three declarations, stable allocation, text, icons, assemblies, parts and previews")

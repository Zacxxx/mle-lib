-- Ready-to-use native registration profile for Manor Lords 0.8.117 / UE 5.5.
local Runtime = {}
local default_hooks, default_scheduler
local function read(path)
    local file = io.open(path, "rb"); if not file then return nil end
    local value = file:read("*a"); file:close(); return value
end
local function write(path, value)
    local file = assert(io.open(path .. ".tmp", "wb")); local ok, reason = file:write(value); file:close(); assert(ok, reason)
    assert(read(path .. ".tmp") == value, "Identity staging readback failed")
    -- Keep the previous ledger recoverable if replacement fails.
    if read(path) then
        os.remove(path .. ".bak"); assert(os.rename(path, path .. ".bak"))
    end
    local moved, error = os.rename(path .. ".tmp", path)
    if not moved then os.rename(path .. ".bak", path); assert(moved, error) end
end
function Runtime.new(api)
    local find = api.find_object or StaticFindObject
    local directory = assert(api.directory, "Supply the mod directory with State, Control, Native and Assets subdirectories")
    local shared = api.shared_directory
    if not shared then
        local parent = directory:gsub("\\", "/"):match("^(.*)/[^/]+$")
        local candidate = parent and parent .. "/MLELib"
        shared = candidate and read(candidate .. "/Native/buildings_name.txt") and candidate or directory
    end
    local before = api.before_world_load or function()
        local player = require("UEHelpers").GetPlayer()
        local class = find("/Script/ManorLords.PawnCPP")
        return not (player and player:IsValid() and class and class:IsValid() and player:IsA(class))
    end
    local version = api.game_version or function() return require("UEHelpers").GetGameInstance():GetAppVersion() end
    local assets = api.assets or require("mle_lib.assets").new({asset_root = assert(api.asset_root), find_object = find, references = api.native_references})
    local buildings = api.buildings or assert(find("/Game/NotStronghold/Data/buildingStats.buildingStats"))
    local upgrades = api.upgrades or assert(find("/Game/NotStronghold/Data/DT_Upgrades.DT_Upgrades"))
    local parts = assert(find("/Game/NotStronghold/Data/DT_ConstructionBPs.DT_ConstructionBPs"))
    local make_name = api.make_name or function(value) return FName(value, 1) end
    local bridge = api.bridge or require("mle_lib.building_bridge").open(shared, find, before)
    local kismet = assert(find("/Script/Engine.KismetSystemLibrary"))
    local presentations = {}
    local identities = api.identities or require("mle_lib.building_ids").new({
        minimums = {buildings = 486, parts = 18500, upgrades = 116},
        read = function() return read(shared .. "/State/buildings.ids") or read(shared .. "/State/buildings.ids.bak") end,
        write = function(value) write(shared .. "/State/buildings.ids", value) end,
        occupied = function(domain, id)
            local table = domain == "buildings" and buildings or domain == "parts" and parts or upgrades
            return table:FindRow(tostring(id)) ~= nil
        end,
        owns = api.owns_identity,
    })
    local ui, service
    local native = require("mle_lib.native_buildings").new({buildings = buildings, make_name = make_name,
        fields = api.fields or {storageLimitGeneric = "integer", storageLimitPantry = "integer", bVisibleInUi = "boolean",
            BuildingCategory = "integer", buildingFunction = "integer", constructionCost = "integer", bSize = "number", isWork = "boolean", job = "integer", needsRoad = "boolean", flammable = "boolean",
            canSetWorkArea = "boolean", canRelocate = "boolean", maxHp = "integer"},
        preflight = function(definition)
            for _, cost in ipairs({definition.construction_goods or {}, definition.upgrade and definition.upgrade.cost or {}}) do
                if #cost > 0 then
                    local items = api.items or assert(find("/Game/NotStronghold/Data/DT_Items.DT_Items"))
                    for _, good in ipairs(cost) do assert(items:FindRow(tostring(good.Type)), "Construction item reference missing") end
                end
            end
            assets.load_class(definition.assets.assembly)
            assets.load_class(definition.assets.construction)
            assets.load(definition.assets.preview)
            for _, key in ipairs({"card", "panel"}) do
                local artwork = definition.presentation[key]
                if artwork:sub(1, 6) == "/Game/" then assets.load(artwork)
                else
                    assert(artwork:match("^[a-z_]+$") and (api.read_artwork or read)(directory .. "/Assets/Cards/" .. artwork .. ".png"),
                        "Building illustration is missing")
                end
            end
        end,
        assert_profile = function()
            assert(before(), "Building registration requires the main menu")
            if bridge.verify then bridge.verify() end
            local current = version()
            assert((type(current) == "string" and current or current:ToString()) == "Version 0.8.117", "Unsupported Manor Lords build")
            assert(buildings.RowStruct:GetFullName() == "ScriptStruct /Script/ManorLords.Stat", "Building schema mismatch")
        end,
        presentation = function(definition, row, transaction)
            require("mle_lib.building_text").install(definition, {find_object = find}, transaction)
            local icon
            if api.asset_root and definition.presentation.icon:sub(1, #api.asset_root) == api.asset_root then
                icon = assets.load(definition.presentation.icon)
            else icon = assets.load_reference(definition.presentation.icon) end
            assert(icon:GetFullName() == "Texture2D " .. definition.presentation.icon, "Building icon must be a Texture2D")
            local previous = row.purposeIcon
            transaction.defer(function() row.purposeIcon = previous; presentations[definition.numeric_id] = nil end)
            row.purposeIcon = icon
            assert(row.purposeIcon:GetFullName() == icon:GetFullName(), "Building icon readback failed")
            for _, binding in ipairs({{key = "panel", kind = 2}, {key = "panel", kind = 3}, {key = "card", kind = 4}}) do
                local path = definition.presentation[binding.key]
                if path:sub(1, 6) == "/Game/" then
                    local image = assets.load(path)
                    assert(image:GetFullName() == "Texture2D " .. path, "Cooked building illustration must be a Texture2D")
                    local reference = kismet:MakeSoftObjectPath(path)
                    bridge.paths(binding.kind, {{row = row:GetStructAddress(), label = row.DisplayName:GetComparisonIndex(),
                        package = reference.AssetPath.PackageName:GetComparisonIndex(), asset = reference.AssetPath.AssetName:GetComparisonIndex(), source = reference,
                        path = type(reference.GetStructAddress) == "function" and reference:GetStructAddress() or nil}}, transaction)
                end
            end
            local presentation = {}
            for key, value in pairs(definition.presentation) do presentation[key] = value end
            presentation.upgrade_id = definition.upgrade and definition.upgrade.id
            presentations[definition.numeric_id] = presentation
        end,
        world = function(definitions, transaction)
            return require("mle_lib.building_world").install(buildings, definitions, {
                before_world_load = before, assets = assets, find_object = find, make_name = make_name,
                make_path = function(path) return kismet:MakeSoftClassPath(path) end,
                bind_construction_paths = function(entries, tx) bridge.paths(1, entries, tx) end,
                bind_previews = function(entries, tx)
                    return require("mle_lib.building_preview").install(buildings, entries,
                        {assets = assets, kismet = kismet, bridge = bridge}, tx)
                end,
            }, transaction)
        end,
        after_register = function(_, transaction)
            if api.ui ~= false then
                transaction.defer(function() service.stop_ui() end)
                service.start_ui(api.ui)
            end
        end,
        upgrade = function(definition, definitions, transaction)
            return require("mle_lib.building_upgrade").install(definition, definitions,
                {buildings = buildings, upgrades = upgrades, bridge = bridge}, transaction)
        end,
    })
    function native.prepare(definition)
        local template = assert(buildings:FindRow(tostring(definition.template_id)), "Building template missing")
        definition.template_label = definition.template_label or (type(template.DisplayName) == "string"
            and template.DisplayName or template.DisplayName:ToString())
    end
    service = require("mle_lib.buildings").new({before_world_load = before, adapter = native, identities = identities, transaction = api.transaction})
    service.identities = identities
    function service.start_ui(ui_api)
        ui_api = ui_api or {}
        if not ui_api.schedule then
            if not default_scheduler then
                default_scheduler = require("mle_lib.game_thread").new({loop = LoopInGameThreadWithDelay,
                    log = function(value) print("[MLE Lib] " .. value) end,
                    now = function()
                        local helpers = require("UEHelpers")
                        return helpers.GetGameplayStatics():GetRealTimeSeconds(helpers.GetGameInstance():GetWorld()) * 1000
                    end})
                default_scheduler.start()
            end
            ui_api.schedule = default_scheduler.schedule
        end
        if not ui_api.hooks then
            if not default_hooks then default_hooks = require("mle_lib.hooks").new(RegisterHook) end
            ui_api.hooks = default_hooks
        end
        ui_api.player = ui_api.player or function() return require("UEHelpers").GetPlayer() end
        ui_api.find_all = ui_api.find_all or FindAllOf
        ui_api.translate = ui_api.translate or function(key)
            local value = require("UEHelpers").GetGameInstance():getTranslatedTextFromDataTable(FName(key),
                find("/Game/Translation/HoodedHorse/DT_Translation_BuildingNames.DT_Translation_BuildingNames"))
            return type(value) == "string" and value or value:ToString()
        end
        assert(not ui, "Building UI is already active")
        local texture = require("mle_lib.artwork").new({find_object = find, world_context = ui_api.player,
            directory = directory .. "/Assets/Cards"})
        ui = require("mle_lib.building_ui").new({find_all = ui_api.find_all, find_object = find,
            texture = function(key)
                if key:sub(1, 6) == "/Game/" then return assets.load(key) end
                return texture(key)
            end, schedule = ui_api.schedule, hooks = ui_api.hooks, log = ui_api.log,
            make_text = ui_api.make_text or FText, translate = ui_api.translate, panels = service})
        ui.start(function() return presentations end)
    end
    function service.stop_ui() if ui then ui.stop(); ui = nil end end
    return service
end
return Runtime

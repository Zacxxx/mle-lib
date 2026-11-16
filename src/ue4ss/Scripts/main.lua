local directory = assert(debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/"):match("^(.*)/Scripts/"))
local mods = assert(directory:match("^(.*)/[^/]+$"))
package.path = directory .. "/Scripts/?.lua;" .. package.path
local Catalog = require("mle_lib.catalog")
local Runtime = require("mle_lib.runtime")
local Json = require("mle_lib.json")
local Host = require("mle_lib.host")
local helpers = require("UEHelpers")
local building_table = "/Game/NotStronghold/Data/buildingStats.buildingStats"

local function valid(object) return object and object:IsValid() end
local function log(message) print("[MLELib] " .. tostring(message) .. "\n") end
local function at_main_menu()
    local player, class = helpers.GetPlayer(), StaticFindObject("/Script/ManorLords.PawnCPP")
    return not (valid(player) and valid(class) and player:IsA(class))
end

local function row(target)
    local data = StaticFindObject(building_table)
    assert(valid(data), "Building data table unavailable")
    return assert(data:FindRow(target.id), "Unknown building row " .. target.id)
end

local function start()
    assert(at_main_menu(), "Install or change packages at the main menu before loading a save")
    local file = assert(io.open(directory .. "/packages.txt", "r"))
    local catalog = assert(file:read("*a"))
    file:close()
    local save_class = StaticFindObject("/Script/ManorLords.MLSaveGame")
    local runtime = Runtime.new({directory = directory,
        registry = {
            fields = {buildings = {storageLimitGeneric = "integer", bVisibleInUi = "boolean"}},
            can_write = at_main_menu,
            read = function(target, field) return row(target)[field] end,
            write = function(target, field, value) row(target)[field] = value end,
        },
        register_hook = RegisterHook,
        can_bind_save = function() return valid(save_class)
            and valid(StaticFindObject("/Script/ManorLords.IoHandler:SaveGameToSlot"))
            and valid(StaticFindObject("/Script/ManorLords.IoHandler:LoadGameFromSlot"))
        end,
        is_save = function(value) return valid(value) and valid(save_class) and value:IsA(save_class) end,
        make_name = FName,
        report = function(record) log(Json.encode(record)) end,
    })
    Catalog.load(mods, catalog, runtime)
    local active, failure = runtime:start()
    assert(active, failure and failure.message)
    local ok, reason = pcall(function()
        runtime:bind_save()
        runtime:apply_registry()
    end)
    if not ok then
        local stopped, stop_error = pcall(runtime.stop, runtime)
        if not stopped then log(stop_error) end
        error(reason, 0)
    end
    RegisterConsoleCommandGlobalHandler("mle.runtime.status", function()
        log(Json.encode({version = Host.VERSION, active = active, status = runtime:inspect()}))
        return true
    end)
    log(Json.encode({version = Host.VERSION, active = active}))
end

local done, attempts = false, 0
LoopInGameThreadWithDelay(250, function()
    if done then return end
    attempts = attempts + 1
    local ok, ready = pcall(function()
        local instance = helpers.GetGameInstance()
        if not valid(instance) then return false end
        local version = instance:GetAppVersion()
        version = type(version) == "string" and version or version:ToString()
        assert(version == "Version 0.8.117", "Unsupported Manor Lords build " .. version)
        return valid(StaticFindObject(building_table))
            and valid(StaticFindObject("/Script/ManorLords.IoHandler:LoadGameFromSlot"))
            and valid(StaticFindObject("/Script/ManorLords.IoHandler:SaveGameToSlot"))
            and valid(StaticFindObject("/Script/ManorLords.MLSaveGame"))
    end)
    if ok and not ready and attempts < 80 then return end
    done = true
    if not ok or not ready then log("Startup stopped: " .. (ok and "Native interfaces unavailable" or tostring(ready))); return end
    local started, failure = pcall(start)
    if not started then log("Startup stopped: " .. tostring(failure)) end
end)

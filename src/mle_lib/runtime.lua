local Host = require("mle_lib.host")
local Hooks = require("mle_lib.hooks")
local NativeSave = require("mle_lib.native_save")
local Registry = require("mle_lib.registry")
local Codec = require("mle_lib.state_codec")

local Runtime = {}
local capabilities = {
    ["mle.registry"] = true, ["mle.hooks"] = true, ["mle.save"] = true, ["mle.buildings"] = true,
}
local save_path = "/Script/ManorLords.IoHandler:SaveGameToSlot"
local load_path = "/Script/ManorLords.IoHandler:LoadGameFromSlot"

function Runtime.new(api)
    local runtime = {}
    local registry = Registry.new(api.registry)
    local broker = Hooks.new(api.register_hook)
    local providers = {}
    local report = api.report or function() end
    local host = Host.new({capabilities = capabilities, enabled = api.enabled, report = report})
    local blocked = false
    local cleanup = {}
    local counters = {wrote = 0, loaded = 0, failed = 0, empty_writes = 0, missing_loads = 0}

    local function guarded(id, operation, callback)
        if not callback then return nil end
        return function(...)
            if host:state() ~= "active" then return end
            local ok, failure = pcall(callback, ...)
            if not ok then
                if operation == save_path or operation == load_path then
                    counters.failed = counters.failed + 1
                end
                report({id = id, code = "callback_failed", message = tostring(failure), operation = operation})
            end
        end
    end

    local function visit_providers(callback)
        local ids = {}
        for id in pairs(providers) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do callback(id, providers[id]) end
    end

    function runtime:register(manifest, activate, directory)
        assert(type(activate) == "function")
        local descriptor = {}
        for key, value in pairs(manifest) do descriptor[key] = value end
        descriptor.activate = function(context)
            local services, granted = {}, {}
            local active = true
            context:defer(function() active = false end)
            for _, name in ipairs(manifest.capabilities or {}) do granted[name] = true end
            context.directory, context.runtime_directory = directory, api.directory
            context.services = services
            if granted["mle.registry"] then
                services.register = function(definition)
                    assert(active and host:state() == "activation", "Registry registration requires activation")
                    registry:register(context.id, definition)
                end
            end
            if granted["mle.hooks"] then
                services.hooks = {add = function(path, first, second)
                    assert(active and type(path) == "string" and type(first) == "function"
                        and (second == nil or type(second) == "function"), "Invalid hook subscription")
                    assert(not second or path:match("^/Script/"), "Blueprint hooks have a single callback")
                    local remove = broker.add(path, guarded(context.id, path, first), guarded(context.id, path, second))
                    context:defer(remove)
                    return remove
                end}
            end
            if granted["mle.buildings"] then
                services.new_building_runtime = function(options)
                    assert(active, "Building runtime requires an active package")
                    local config = {}
                    for key, value in pairs(options) do config[key] = value end
                    config.directory, config.shared_directory = directory, api.directory
                    if config.ui ~= false then
                        assert(services.hooks, "Building UI requires mle.hooks")
                        local ui = {}
                        for key, value in pairs(config.ui or {}) do ui[key] = value end
                        ui.hooks, config.ui = services.hooks, ui
                    end
                    local buildings = require("mle_lib.building_runtime").new(config)
                    context:defer(buildings.stop_ui)
                    return buildings
                end
            end
            if granted["mle.save"] then
                services.save_state = function(snapshot, restore)
                    assert(active and host:state() == "activation" and not providers[context.id]
                        and type(snapshot) == "function" and type(restore) == "function", "Invalid save provider")
                    providers[context.id] = {snapshot = snapshot, restore = restore}
                    context:defer(function() providers[context.id] = nil end)
                end
            end
            activate(context)
        end
        host:register(descriptor)
    end

    function runtime:apply_registry()
        assert(host:state() == "active")
        return registry:apply()
    end

    function runtime:inspect()
        return {registry = registry:inspect(), hooks = broker.targets(), lifecycle = host:state(),
            save = {wrote = counters.wrote, loaded = counters.loaded, failed = counters.failed,
                empty_writes = counters.empty_writes, missing_loads = counters.missing_loads, blocked = blocked}}
    end

    local function save(_, object)
        local value = object:get()
        if not api.is_save(value) then return end
        assert(not blocked, "Load a readable save before writing MLE Lib state")
        local previous = NativeSave.read(value, true)
        local next_state = previous or {}
        visit_providers(function(id, provider)
            local snapshot = provider.snapshot()
            assert(snapshot == nil or type(snapshot) == "table", "Save provider " .. id .. " must return a table or nil")
            next_state[id] = snapshot
        end)
        if not next(next_state) and not previous then
            counters.empty_writes = counters.empty_writes + 1
            return
        end
        NativeSave.write(value, next_state, api.make_name)
        counters.wrote = counters.wrote + 1
    end

    local function load(_, returned)
        local value = returned:get()
        if not api.is_save(value) then return end
        blocked = true
        local ok, state = pcall(NativeSave.read, value)
        local stored = ok and state or {}
        local failures = {}
        visit_providers(function(id, provider)
            local restored, reason = pcall(provider.restore, stored[id] and Codec.decode(Codec.encode(stored[id])),
                ok and (stored[id] and "loaded" or "missing") or "unreadable", value)
            if not restored then failures[#failures + 1] = id .. " " .. tostring(reason) end
        end)
        if not ok then error(state, 0) end
        assert(#failures == 0, table.concat(failures, "\n"))
        blocked = false
        if state then counters.loaded = counters.loaded + 1
        else counters.missing_loads = counters.missing_loads + 1 end
    end

    function runtime:bind_save()
        assert(host:state() == "active" and #cleanup == 0, "Save hooks already bound or runtime inactive")
        if not next(providers) then return false end
        if api.can_bind_save then assert(api.can_bind_save(), "Native save interfaces are unavailable") end
        local first = broker.add(save_path, guarded("mle.runtime", save_path, save))
        local ok, second = pcall(broker.add, load_path, function() end, guarded("mle.runtime", load_path, load))
        if not ok then first(); error(second, 0) end
        cleanup = {first, second}
        return true
    end

    function runtime:start()
        local active, failure = host:start()
        if not active then return nil, failure end
        local ok, reason = pcall(registry.freeze, registry)
        if not ok then
            host:stop()
            return nil, {code = "registry_validation", message = tostring(reason)}
        end
        return active
    end

    function runtime:stop()
        registry:restore()
        for _, remove in ipairs(cleanup) do remove() end
        cleanup = {}
        return host:stop()
    end
    return runtime
end

Runtime.capabilities = capabilities
return Runtime

local Host = {VERSION = "0.1.0"}

local function problem(code, message, id, dependency)
    return {code = code, message = message, id = id, dependency = dependency}
end

local function version(value)
    if type(value) ~= "string" then return end
    local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then return end
    local parts = {major, minor, patch}
    for index, part in ipairs(parts) do
        if #part > 9 or (#part > 1 and part:sub(1, 1) == "0") then return end
        parts[index] = tonumber(part)
    end
    return parts
end

local function compare(left, right)
    for index = 1, 3 do
        if left[index] ~= right[index] then
            return left[index] < right[index] and -1 or 1
        end
    end
    return 0
end

local function predicate(operator, minimum, actual)
    local order = compare(actual, minimum)
    if operator == "" or operator == "=" then return order == 0 end
    if operator == ">" then return order > 0 end
    if operator == ">=" then return order >= 0 end
    if operator == "<" then return order < 0 end
    if operator == "<=" then return order <= 0 end
    if operator == "~" then
        return order >= 0 and actual[1] == minimum[1] and actual[2] == minimum[2]
    end
    if operator == "^" then
        local limit = minimum[1] ~= 0 and 1 or minimum[2] ~= 0 and 2 or 3
        for index = 1, limit do
            if actual[index] ~= minimum[index] then return false end
        end
        return order >= 0
    end
end

-- Supported range grammar is stable MAJOR.MINOR.PATCH, exact/comparator,
-- caret/tilde, a whitespace-separated conjunction, or "*".
function Host.matches(actual_version, constraint)
    local actual = version(actual_version)
    if not actual or type(constraint) ~= "string" then return false end
    if constraint == "*" then return true end
    local seen = false
    for token in constraint:gmatch("%S+") do
        local operator, minimum_version = token:match("^([=<>~%^]*)(%d+%.%d+%.%d+)$")
        local minimum = version(minimum_version)
        if not minimum or not predicate(operator, minimum, actual) then return false end
        seen = true
    end
    return seen
end

local function identifier(value)
    return type(value) == "string" and value:match("^[a-z][a-z0-9_.%-]*[a-z0-9]$")
        and value:find(".", 1, true) and not value:find("..", 1, true)
end

local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function array(values)
    if type(values) ~= "table" then return false end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 or key > #values then return false end
        count = count + 1
    end
    return count == #values
end

function Host.plan(packages, enabled, options)
    options = options or {}
    enabled = enabled or options.enabled or {}
    local engine_version = options.version or Host.VERSION
    local capabilities = options.capabilities or {}
    if not array(packages) or type(enabled) ~= "table" or type(capabilities) ~= "table"
            or not version(engine_version) then
        return nil, problem("invalid_profile", "Expected a package array, switches, and valid engine profile")
    end
    local discovered = {}
    for _, package in ipairs(packages) do
        if type(package) ~= "table" or not identifier(package.id) or not version(package.version)
                or type(package.engine) ~= "string" or (package.activate ~= nil and type(package.activate) ~= "function")
                or (package.requires ~= nil and type(package.requires) ~= "table")
                or (package.capabilities ~= nil and not array(package.capabilities)) then
            return nil, problem("invalid_manifest", "Expected a namespaced ID, stable version, and engine constraint")
        end
        if discovered[package.id] then
            return nil, problem("duplicate_package", "Package ID is already registered", package.id)
        end
        discovered[package.id] = package
        for dependency, constraint in pairs(package.requires or {}) do
            if not identifier(dependency) or type(constraint) ~= "string" then
                return nil, problem("invalid_manifest", "Dependencies require a namespaced ID and version constraint", package.id)
            end
        end
        for _, capability in ipairs(package.capabilities or {}) do
            if not identifier(capability) then
                return nil, problem("invalid_manifest", "Capabilities require a namespaced ID", package.id)
            end
        end
    end
    for id, active in pairs(enabled) do
        if not identifier(id) or type(active) ~= "boolean" then
            return nil, problem("invalid_switch", "Package switches require a namespaced ID and a boolean")
        end
    end

    local ordered, marks = {}, {}
    local function visit(id)
        if marks[id] == "done" then return true end
        if marks[id] == "visiting" then
            return nil, problem("dependency_cycle", "Dependency cycle reaches " .. id, id)
        end
        local package = discovered[id]
        marks[id] = "visiting"
        if not Host.matches(engine_version, package.engine) then
            return nil, problem("engine_version", "Engine version " .. engine_version .. " does not satisfy " .. package.engine, id)
        end
        for _, capability in ipairs(package.capabilities or {}) do
            if capabilities[capability] ~= true then
                return nil, problem("missing_capability", "Required capability is unavailable", id, capability)
            end
        end
        for _, dependency in ipairs(sorted_keys(package.requires or {})) do
            if not discovered[dependency] then
                return nil, problem("missing_dependency", "Install the required package", id, dependency)
            end
            if enabled[dependency] == false then
                return nil, problem("disabled_dependency", "Enable the required package or disable its dependent", id, dependency)
            end
            local required_version = package.requires[dependency]
            if not Host.matches(discovered[dependency].version, required_version) then
                return nil, problem("dependency_version", "Dependency does not satisfy " .. required_version, id, dependency)
            end
            local ok, failure = visit(dependency)
            if not ok then return nil, failure end
        end
        marks[id] = "done"
        ordered[#ordered + 1] = package
        return true
    end
    for _, id in ipairs(sorted_keys(discovered)) do
        if enabled[id] ~= false then
            local ok, failure = visit(id)
            if not ok then return nil, failure end
        end
    end
    return ordered
end

function Host.new(options)
    options = options or {}
    local host, packages, owners, listeners = {}, {}, {}, {}
    local lifecycle, sequence = "discovery", 0
    local function report(record)
        if options.report then pcall(options.report, record) end
    end

    local function cleanup()
        local failures = {}
        for index = #owners, 1, -1 do
            local owner = owners[index]
            owner.active = false
            for unsubscribe in pairs(owner.subscriptions) do unsubscribe() end
            for step = #owner.cleanups, 1, -1 do
                local ok, reason = pcall(owner.cleanups[step])
                if not ok then
                    local failure = problem("cleanup_failed", tostring(reason), owner.id)
                    failures[#failures + 1] = failure
                    report(failure)
                end
            end
        end
        owners = {}
        return failures
    end

    function host:state() return lifecycle end

    function host:register(package)
        assert(lifecycle == "discovery", "Package registration is frozen")
        assert(type(package) == "table", "Expected a package manifest")
        packages[#packages + 1] = package
    end

    function host:emit(event, ...)
        assert(lifecycle == "active", "Events require an active host")
        assert(identifier(event), "Expected a namespaced event")
        local delivered, failures = 0, {}
        local snapshot = {table.unpack(listeners[event] or {})}
        for _, listener in ipairs(snapshot) do
            if listener.active then
                local ok, reason = pcall(listener.callback, ...)
                if ok then
                    delivered = delivered + 1
                else
                    local failure = problem("listener_failed", tostring(reason), listener.id, event)
                    failures[#failures + 1] = failure
                    report(failure)
                end
            end
        end
        return delivered, failures
    end

    function host:start()
        assert(lifecycle == "discovery", "Package host already initialized")
        local plan, failure = Host.plan(packages, options.enabled, options)
        if not plan then
            lifecycle = "failed"
            report(failure)
            return nil, failure
        end
        lifecycle = "activation"
        local active = {}
        for _, package in ipairs(plan) do
            local owner = {id = package.id, active = true, subscriptions = {}, cleanups = {}}
            owners[#owners + 1] = owner
            local context = {id = owner.id, services = options.services}
            function context:on(event, callback, priority)
                priority = priority or 0
                assert(owner.active and identifier(event) and type(callback) == "function"
                    and math.type(priority) == "integer", "Invalid event subscription")
                sequence = sequence + 1
                local list = listeners[event] or {}
                listeners[event] = list
                local listener = {callback = callback, id = owner.id, priority = priority,
                    sequence = sequence, active = true}
                list[#list + 1] = listener
                table.sort(list, function(left, right)
                    if left.priority ~= right.priority then return left.priority > right.priority end
                    if left.id ~= right.id then return left.id < right.id end
                    return left.sequence < right.sequence
                end)

                local function unsubscribe()
                    if not listener.active then return false end
                    listener.active = false
                    owner.subscriptions[unsubscribe] = nil
                    for index, current in ipairs(list) do
                        if current == listener then
                            table.remove(list, index)
                            break
                        end
                    end
                    if #list == 0 then listeners[event] = nil end
                    return true
                end
                owner.subscriptions[unsubscribe] = true
                return unsubscribe
            end
            function context:emit(event, ...) return host:emit(event, ...) end
            function context:defer(callback)
                assert(owner.active and type(callback) == "function", "Expected a cleanup callback and an active package")
                owner.cleanups[#owner.cleanups + 1] = callback
            end
            if package.activate then
                local ok, reason = pcall(package.activate, context)
                if not ok then
                    lifecycle = "failed"
                    failure = problem("activation_failed", tostring(reason), owner.id)
                    report(failure)
                    failure.cleanup_errors = cleanup()
                    return nil, failure
                end
            end
            active[#active + 1] = owner.id
        end
        lifecycle = "active"
        return active
    end

    function host:stop()
        if lifecycle ~= "active" then return false end
        lifecycle = "stopped"
        return true, cleanup()
    end

    return host
end

return Host

-- Templates compose native row defaults with optional per-instance behavior and UI.
local Templates = {}
local function identifier(id)
    return type(id) == "string" and id:match("^[a-z][a-z0-9_.%-]*:[a-z][a-z0-9_]*$")
end

function Templates.new(copy)
    local self, templates, behaviors, panels = {}, {}, {}, {}
    local bindings, instances, actors, frozen = {}, {}, {}, false
    local instance_types = {}
    behaviors["mle:native_storage"] = {status = {}, actions = {}}
    panels["mle:native_storage_panel"] = {
        sections = {workers = {}, storage = {}, accepted_goods = {}},
    }

    local mixins, yards = {}, {}
    local function merge_defaults(target, source)
        for key, value in pairs(source or {}) do
            assert(key == "fields" or key == "families" or key == "construction_goods", "Unsupported template default: " .. key)
            if key == "fields" then
                assert(type(value) == "table", "Template fields must be a table")
                for field, setting in pairs(value) do target.fields[field] = copy(setting) end
            else
                target[key] = copy(value)
            end
        end
    end

    local function register(registry, definition)
        assert(not frozen and type(definition) == "table" and identifier(definition.id),
            "Invalid or frozen building component registration")
        assert(not registry[definition.id], "Building component already registered: " .. definition.id)
        registry[definition.id] = copy(definition)
    end
    function self.register_building_behavior(definition) register(behaviors, definition) end
    function self.register_building_panel(definition) register(panels, definition) end
    function self.register_building_template(definition) register(templates, definition) end
    function self.register_building_mixin(definition) register(mixins, definition) end
    function self.register_building_yard(definition)
        assert(type(definition) == "table" and type(definition.list) == "function"
            and type(definition.place) == "function" and type(definition.mount) == "function",
            "Yard provider requires list, place and mount callbacks")
        register(yards, definition)
    end
    function self.freeze() frozen = true end

    function self.resolve(definition)
        if not definition.template then
            assert(not definition.behavior and not definition.interface and not definition.yard,
                "Behavior, interface and yard overrides require a template")
            return definition
        end
        local template = assert(templates[definition.template], "Unknown building template: " .. tostring(definition.template))
        definition.behavior = definition.behavior or copy(template.behavior)
        definition.interface = definition.interface or copy(template.interface)
        if definition.yard == nil then definition.yard = copy(template.yard) end
        assert(type(definition.behavior) == "table" and identifier(definition.behavior.id), "Invalid behavior reference")
        assert(type(definition.interface) == "table" and identifier(definition.interface.id), "Invalid interface reference")
        local behavior = assert(behaviors[definition.behavior.id], "Unknown building behavior")
        local panel = assert(panels[definition.interface.id], "Unknown building panel")
        local sections = definition.interface.sections or {}
        assert(type(sections) == "table", "Panel sections must be an array")
        local seen = {}
        for _, section in ipairs(sections) do
            local requirements = assert((panel.sections or {})[section], "Unknown panel section: " .. section)
            assert(not seen[section], "Duplicate panel section: " .. section)
            seen[section] = true
            for _, key in ipairs(requirements.status or {}) do
                assert((behavior.status or {})[key], "Behavior lacks panel status: " .. key)
            end
            for _, key in ipairs(requirements.actions or {}) do
                assert(type((behavior.actions or {})[key]) == "function", "Behavior lacks panel action: " .. key)
            end
        end
        if definition.yard then
            local yard = definition.yard
            assert(type(yard) == "table" and yards[yard.id], "Unknown building yard provider")
            assert(type(yard.title) == "table" and type(yard.title.en_US) == "string" and #yard.title.en_US > 0,
                "Yard title requires English fallback text")
            assert(yard.options == nil or type(yard.options) == "table", "Invalid yard options")
        end
        local defaults, included = {fields = {}}, {}
        for _, id in ipairs(template.mixins or {}) do
            assert(not included[id], "Duplicate building mixin: " .. id)
            included[id] = true
            merge_defaults(defaults, assert(mixins[id], "Unknown building mixin: " .. id).defaults)
        end
        merge_defaults(defaults, template.defaults)
        definition.placement = definition.placement or copy(template.placement)
        local fields = copy(defaults.fields or {})
        for key, value in pairs(definition.fields or {}) do fields[key] = value end
        definition.fields = fields
        if definition.families == nil then definition.families = defaults.families end
        if definition.construction_goods == nil then definition.construction_goods = copy(defaults.construction_goods) end
        assert(not definition.template_id or definition.row_prepared, "A templated building takes its native base from the template")
        definition.template_id = definition.template_id or template.native_base
        if behavior.validate then behavior.validate(copy(definition.behavior.options or {}), copy(definition)) end
        return definition
    end

    function self.bind(definition, transaction)
        if not definition.template or definition.enabled == false then return end
        local id = definition.numeric_id
        transaction.defer(function() bindings[id] = nil end)
        bindings[id] = {id = definition.template, behavior = definition.behavior,
            interface = definition.interface, yard = definition.yard or nil}
    end

    function self.attach_instance(id, key, actor, saved)
        assert(type(key) == "string" and #key > 0 and not instances[key], "Invalid or occupied building instance key")
        assert(not actor or actor:GetType() == id, "Actor does not match building type")
        local address = actor and actor:GetAddress()
        assert(not address or not actors[address], "Building actor already attached")
        local template = assert(bindings[id], "Building has no active template")
        local behavior = behaviors[template.behavior.id]
        local context = {actor = actor, key = key, building_id = id, options = copy(template.behavior.options or {})}
        local state = behavior.create and behavior.create(context, copy(saved)) or {}
        local instance = {}
        function instance.get_status()
            assert(instances[key] == instance, "Building instance is detached")
            local snapshot = behavior.read and behavior.read(context, state) or {}
            for field in pairs(behavior.status or {}) do assert(snapshot[field] ~= nil, "Missing behavior status: " .. field) end
            return copy(snapshot)
        end
        function instance.invoke(action, argument)
            assert(instances[key] == instance, "Building instance is detached")
            return assert((behavior.actions or {})[action], "Unknown building action")(context, state, copy(argument))
        end
        if template.yard then
            local yard = yards[template.yard.id]
            local options = template.yard.options or {}
            function instance.list_improvements()
                assert(instances[key] == instance, "Building instance is detached")
                return copy(yard.list(context, state, copy(options)))
            end
            function instance.place_improvement(improvement)
                assert(instances[key] == instance, "Building instance is detached")
                assert(identifier(improvement), "Invalid yard improvement ID")
                return yard.place(context, state, improvement, copy(options))
            end
        end
        function instance.snapshot()
            if behavior.save then return copy(behavior.save(context, state)) end
        end
        function instance.detach(reason)
            if instances[key] ~= instance then return end
            instances[key] = nil
            instance_types[instance] = nil
            if address then actors[address] = nil end
            if behavior.detach then behavior.detach(context, state, reason) end
        end
        function instance.tick(elapsed)
            assert(instances[key] == instance, "Building instance is detached")
            if behavior.tick then behavior.tick(context, state, elapsed) end
        end
        instances[key] = instance
        instance_types[instance] = id
        if address then actors[address] = instance end
        return instance
    end

    function self.mount_panel(id, screen, instance)
        local template = assert(bindings[id], "Building has no active template")
        local panel = panels[template.interface.id]
        local yard = template.yard and yards[template.yard.id]
        if not panel.mount and not yard then return function() end end
        assert(instance and instance_types[instance] == id, "Custom building panel requires a matching attached instance")
        local active, cleanups = true, {}
        local function close()
            if not active then return end
            active = false
            local failure
            for index = #cleanups, 1, -1 do
                local ok, reason = pcall(cleanups[index])
                if not ok then failure = failure or reason end
            end
            if failure then error(failure, 0) end
        end
        local function add_cleanup(cleanup)
            assert(type(cleanup) == "function", "Custom building panels must return a cleanup callback")
            cleanups[#cleanups + 1] = cleanup
        end
        local ok, reason = pcall(function()
            if panel.mount then
                add_cleanup(panel.mount(screen, {
                    sections = copy(template.interface.sections or {}),
                    options = copy(template.interface.options or {}),
                    get_status = function() assert(active, "Building panel is closed"); return instance.get_status() end,
                    invoke = function(...) assert(active, "Building panel is closed"); return instance.invoke(...) end,
                }))
            end
            if yard then
                add_cleanup(yard.mount(screen, {
                    title = copy(template.yard.title),
                    list = function() assert(active, "Building panel is closed"); return instance.list_improvements() end,
                    place = function(...) assert(active, "Building panel is closed"); return instance.place_improvement(...) end,
                }))
            end
        end)
        if not ok then
            local cleaned, cleanup_error = pcall(close)
            if not cleaned then error(tostring(reason) .. " (panel cleanup failed: " .. tostring(cleanup_error) .. ")", 0) end
            error(reason, 0)
        end
        return close
    end

    function self.instance_for(actor) return actors[actor:GetAddress()] end

    function self.panel_mounts(id)
        local template = bindings[id]
        return template and (template.yard ~= nil or panels[template.interface.id].mount ~= nil)
    end

    function self.describe(id)
        local template = bindings[id]
        if template then return {template = template.id, behavior = template.behavior.id, interface = template.interface.id, yard = template.yard and template.yard.id} end
    end
    return self
end
return Templates

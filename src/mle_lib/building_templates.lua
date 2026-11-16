-- Templates compose native row defaults with optional per-instance behavior and UI.
local Templates = {}
local function identifier(id)
    return type(id) == "string" and id:match("^[a-z][a-z0-9_.%-]*:[a-z][a-z0-9_]*$")
end

function Templates.new(copy)
    local self, templates, behaviors, panels = {}, {}, {}, {}
    local bindings, instances, actors, frozen = {}, {}, {}, false
    behaviors["mle:native_storage"] = {status = {}, actions = {}}
    panels["mle:native_storage_panel"] = {
        sections = {workers = {}, storage = {}, accepted_goods = {}},
    }

    local function register(registry, definition)
        assert(not frozen and type(definition) == "table" and identifier(definition.id),
            "Invalid or frozen building component registration")
        assert(not registry[definition.id], "Building component already registered: " .. definition.id)
        registry[definition.id] = copy(definition)
    end
    function self.register_building_behavior(definition) register(behaviors, definition) end
    function self.register_building_panel(definition) register(panels, definition) end
    function self.register_building_template(definition) register(templates, definition) end
    function self.freeze() frozen = true end

    function self.resolve(definition)
        if not definition.template then return definition end
        local template = assert(templates[definition.template], "Unknown building template: " .. tostring(definition.template))
        local behavior = assert(behaviors[template.behavior.id], "Unknown building behavior")
        local panel = assert(panels[template.interface.id], "Unknown building panel")
        local sections = template.interface.sections or {}
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
        local defaults = template.defaults or {}
        for key in pairs(defaults) do
            assert(key == "fields" or key == "families" or key == "construction_goods", "Unsupported template default: " .. key)
        end
        local fields = copy(defaults.fields or {})
        for key, value in pairs(definition.fields or {}) do fields[key] = value end
        definition.fields = fields
        if definition.families == nil then definition.families = defaults.families end
        if definition.construction_goods == nil then definition.construction_goods = copy(defaults.construction_goods) end
        assert(not definition.template_id or definition.row_prepared, "A templated building takes its native base from the template")
        definition.template_id = definition.template_id or template.native_base
        if behavior.validate then behavior.validate(copy(template.behavior.options or {}), copy(definition)) end
        return definition
    end

    function self.bind(definition, transaction)
        if not definition.template or definition.enabled == false then return end
        local id = definition.numeric_id
        local template = templates[definition.template]
        transaction.defer(function() bindings[id] = nil end)
        bindings[id] = template
    end

    function self.attach_instance(id, key, actor, saved)
        assert(type(key) == "string" and #key > 0 and not instances[key], "Invalid or occupied building instance key")
        local address = actor and actor:GetAddress()
        assert(not address or not actors[address], "Building actor already attached")
        local template = assert(bindings[id], "Building has no active template")
        local behavior = behaviors[template.behavior.id]
        local context = {actor = actor, key = key, options = copy(template.behavior.options or {})}
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
        function instance.snapshot()
            if behavior.save then return copy(behavior.save(context, state)) end
        end
        function instance.detach(reason)
            if instances[key] ~= instance then return end
            instances[key] = nil
            if address then actors[address] = nil end
            if behavior.detach then behavior.detach(context, state, reason) end
        end
        function instance.tick(elapsed)
            assert(instances[key] == instance, "Building instance is detached")
            if behavior.tick then behavior.tick(context, state, elapsed) end
        end
        instances[key] = instance
        if address then actors[address] = instance end
        return instance
    end

    function self.mount_panel(id, screen, instance)
        local template = assert(bindings[id], "Building has no active template")
        local panel = panels[template.interface.id]
        if not panel.mount then return function() end end
        assert(instance, "Custom building panel requires an attached instance")
        local active = true
        local cleanup = panel.mount(screen, {
            sections = copy(template.interface.sections or {}),
            options = copy(template.interface.options or {}),
            get_status = function() assert(active, "Building panel is closed"); return instance.get_status() end,
            invoke = function(...) assert(active, "Building panel is closed"); return instance.invoke(...) end,
        })
        assert(type(cleanup) == "function", "Custom building panels must return a cleanup callback")
        return function()
            if not active then return end
            active = false
            cleanup()
        end
    end

    function self.instance_for(actor) return actors[actor:GetAddress()] end

    function self.panel_mounts(id)
        local template = bindings[id]
        return template and panels[template.interface.id].mount ~= nil
    end

    function self.describe(id)
        local template = bindings[id]
        if template then return {template = template.id, behavior = template.behavior.id, interface = template.interface.id} end
    end
    return self
end
return Templates

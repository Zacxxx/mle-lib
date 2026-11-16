-- Placement providers own the engine interaction. Templates select and configure them.
local Capabilities = {}
local function identifier(id)
    return type(id) == "string" and id:match("^[a-z][a-z0-9_.%-]*:[a-z][a-z0-9_]*$")
end

function Capabilities.new(copy)
    local providers, bindings = {}, {}
    local self = {}
    function self.register_placement(provider)
        assert(type(provider) == "table" and identifier(provider.id) and type(provider.begin) == "function"
            and type(provider.validate) == "function", "Placement needs a namespaced ID, validate and begin callbacks")
        assert(not providers[provider.id], "Placement provider already registered")
        providers[provider.id] = copy(provider)
    end

    function self.validate_placement(spec, definition)
        if spec == nil then return end
        assert(type(spec) == "table" and identifier(spec.id), "Invalid placement declaration")
        assert(spec.options == nil or type(spec.options) == "table", "Invalid placement options")
        local provider = assert(providers[spec.id], "Unknown placement provider: " .. spec.id)
        assert(provider.validate(copy(spec.options or {}), copy(definition)) == true,
            "Placement provider refused building: " .. tostring(definition.id))
    end

    function self.bind(definition, transaction)
        if not definition.placement or definition.enabled == false then return end
        local id = definition.numeric_id
        transaction.defer(function() bindings[id] = nil end)
        bindings[id] = definition
    end

    function self.begin_placement(id, context)
        local definition = assert(bindings[id], "Building has no active placement provider")
        local spec = definition.placement
        return providers[spec.id].begin(id, context, copy(spec.options or {}))
    end
    return self
end
return Capabilities

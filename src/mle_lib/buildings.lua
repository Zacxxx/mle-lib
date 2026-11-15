-- Declarative building registration. Native writes belong to the pinned adapter.
local Rows = require("mle_lib.rows")
local Buildings = {}
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    assert(not seen[value], "Building definitions must be acyclic data")
    seen[value] = true
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item, seen) end
    seen[value] = nil
    return result
end
local function identity(value)
    return type(value) == "string" and value:match("^[a-z][a-z0-9_.%-]*:[a-z][a-z0-9_]*$")
end
local function positive(value)
    return math.type(value) == "integer" and value > 0 and value <= 2147483647
end
local function localized(value)
    assert(type(value) == "table" and type(value.en_US) == "string" and #value.en_US > 0,
        "Building text requires an English fallback")
    for language, text in pairs(value) do
        assert(type(language) == "string" and type(text) == "string" and #text > 0, "Invalid localized text")
    end
end
local function validate(definition)
    assert(type(definition) == "table" and definition.schema == 1, "Unsupported building definition schema")
    assert(identity(definition.id) and positive(definition.numeric_id), "Invalid building identity")
    assert(type(definition.owner) == "string" and definition.id:match("^([^:]+)") == definition.owner,
        "Building must belong to its declared package")
    assert(positive(definition.template_id) and definition.template_id ~= definition.numeric_id,
        "Building requires a distinct native template")
    assert(type(definition.assets) == "table", "Building assets are required")
    for _, key in ipairs({"assembly", "construction", "preview"}) do
        assert(type(definition.assets[key]) == "string", "Missing building asset " .. key)
    end
    assert(positive(definition.construction_part_id), "Missing construction part identity")
    assert(type(definition.presentation) == "table", "Building presentation is required")
    localized(definition.presentation.name)
    localized(definition.presentation.description)
    for _, key in ipairs({"card", "panel", "icon"}) do
        assert(type(definition.presentation[key]) == "string" and #definition.presentation[key] > 0,
            "Missing building presentation " .. key)
    end
    if definition.upgrade_to then assert(identity(definition.upgrade_to), "Invalid building upgrade reference") end
    if definition.upgraded_from then assert(identity(definition.upgraded_from), "Invalid building parent reference") end
    assert(definition.fields == nil or type(definition.fields) == "table", "Invalid native building fields")
end

function Buildings.new(api)
    assert(type(api) == "table" and type(api.before_world_load) == "function", "Building phase guard is required")
    local adapter = assert(api.adapter, "Pinned native building adapter is required")
    for _, method in ipairs({"preflight", "register", "verify"}) do
        assert(type(adapter[method]) == "function", "Missing native building adapter " .. method)
    end
    local self, definitions, numeric, parts = {}, {}, {}, {}
    local state, receipt = "collecting", nil

    function self.register_building(definition)
        assert(state == "collecting", "Building registrations are frozen")
        validate(definition)
        assert(not definitions[definition.id], "Building identity is occupied")
        assert(not numeric[definition.numeric_id], "Building numeric ID is occupied")
        assert(not parts[definition.construction_part_id], "Construction part ID is occupied")
        local snapshot = copy(definition)
        definitions[snapshot.id] = snapshot
        numeric[snapshot.numeric_id], parts[snapshot.construction_part_id] = snapshot.id, snapshot.id
        return snapshot.id
    end

    function self.apply()
        assert(state == "collecting", "Building registration already attempted")
        assert(api.before_world_load() == true, "Register buildings before loading a world")
        local ordered = {}
        for _, definition in pairs(definitions) do ordered[#ordered + 1] = definition end
        table.sort(ordered, function(a, b) return a.id < b.id end)
        for _, definition in ipairs(ordered) do
            if definition.upgrade_to then
                local target = assert(definitions[definition.upgrade_to], "Missing building upgrade target")
                assert(target.upgraded_from == definition.id, "Upgrade target must reference its parent")
            end
            if definition.upgraded_from then
                local parent = assert(definitions[definition.upgraded_from], "Missing building upgrade parent")
                assert(parent.upgrade_to == definition.id, "Upgrade parent must reference its target")
            end
            local seen, current = {}, definition
            while current do
                assert(not seen[current.id], "Building upgrade cycle")
                seen[current.id] = true
                current = current.upgrade_to and definitions[current.upgrade_to] or nil
            end
        end
        -- Preflight every definition before the first native write. Pass copies
        -- so adapter mutation cannot corrupt the registration ledger.
        for _, definition in ipairs(ordered) do
            assert(adapter.preflight(copy(definition)) == true, "Native building preflight refused " .. definition.id)
        end
        state = "applying"
        local rollback_failed = false
        local rollback_status = {}
        local ok, result = pcall(Rows.run, function(transaction)
            local guarded = {table = transaction.table}
            function guarded.defer(undo)
                assert(type(undo) == "function", "Building rollback must be callable")
                transaction.defer(function()
                    local restored, reason = pcall(undo)
                    if not restored then rollback_failed = true; error(reason, 0) end
                end)
            end
            local reports = {}
            for _, definition in ipairs(ordered) do
                reports[definition.id] = adapter.register(copy(definition), guarded)
            end
            if adapter.finalize then adapter.finalize(copy(ordered), reports, guarded) end
            for _, definition in ipairs(ordered) do
                assert(adapter.verify(copy(definition), reports[definition.id]) == true,
                    "Native building readback failed " .. definition.id)
            end
            return reports
        end, rollback_status)
        if not ok then
            state = "failed"
            if rollback_failed or rollback_status.rollback_failed then state = "reload_required" end
            error(result, 0)
        end
        state, receipt = "registered", result
        return copy(receipt)
    end

    function self.inspect()
        local ids = {}
        for id in pairs(definitions) do ids[#ids + 1] = id end
        table.sort(ids)
        return {state = state, ids = ids, gameplay_verified = false}
    end
    return self
end
return Buildings

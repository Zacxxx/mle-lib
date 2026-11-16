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
local function known_fields(value, fields, message)
    for key in pairs(value) do assert(fields[key], message .. tostring(key)) end
end
local function goods(values)
    assert(type(values) == "table", "Goods must be an array")
    local count = 0
    for index in pairs(values) do
        assert(math.type(index) == "integer" and index > 0 and index <= #values, "Goods must be a dense array")
        count = count + 1
    end
    assert(count == #values, "Goods must be a dense array")
    for _, good in ipairs(values) do
        assert(type(good) == "table", "Goods require Type and amt")
        known_fields(good, {Type = true, amt = true}, "Unknown goods field: ")
        assert(positive(good.Type) and positive(good.amt), "Invalid good or amount")
    end
end
local function validate(definition)
    assert(type(definition) == "table" and definition.schema == 1, "Unsupported building definition schema")
    known_fields(definition, {schema = true, owner = true, id = true, numeric_id = true, template_id = true,
        construction_part_id = true, native_label = true, template_label = true, construction_label = true,
        row_prepared = true, enabled = true, assets = true, presentation = true, fields = true, template = true,
        families = true, construction_goods = true, upgrade_to = true, upgraded_from = true, upgrade = true},
        "Unknown building definition field: ")
    assert(identity(definition.id) and positive(definition.numeric_id), "Invalid building identity")
    assert(type(definition.owner) == "string" and definition.id:match("^([^:]+)") == definition.owner,
        "Building must belong to its declared package")
    assert(definition.row_prepared == nil or type(definition.row_prepared) == "boolean", "Invalid prepared-row setting")
    for _, key in ipairs({"native_label", "template_label", "construction_label"}) do
        assert(definition[key] == nil or (type(definition[key]) == "string" and #definition[key] > 0), "Invalid native label")
    end
    assert(positive(definition.template_id) and definition.template_id ~= definition.numeric_id,
        "Building requires a distinct native template")
    assert(type(definition.assets) == "table", "Building assets are required")
    known_fields(definition.assets, {assembly = true, construction = true, preview = true}, "Unknown building asset field: ")
    for _, key in ipairs({"assembly", "construction", "preview"}) do
        assert(type(definition.assets[key]) == "string", "Missing building asset " .. key)
    end
    assert(positive(definition.construction_part_id), "Missing construction part identity")
    assert(type(definition.presentation) == "table", "Building presentation is required")
    known_fields(definition.presentation, {name = true, description = true, card = true, panel = true, icon = true,
        worker_role = true, upgrade_name = true, upgrade_description = true}, "Unknown building presentation field: ")
    for _, key in ipairs({"worker_role", "upgrade_name", "upgrade_description"}) do
        if definition.presentation[key] then localized(definition.presentation[key]) end
    end
    localized(definition.presentation.name)
    localized(definition.presentation.description)
    for _, key in ipairs({"card", "panel", "icon"}) do
        assert(type(definition.presentation[key]) == "string" and #definition.presentation[key] > 0,
            "Missing building presentation " .. key)
    end
    if definition.families ~= nil then
        assert(math.type(definition.families) == "integer" and definition.families >= 0 and definition.families <= 16,
            "Building families must be an integer between zero and sixteen")
    end
    if definition.construction_goods then goods(definition.construction_goods) end
    if definition.upgrade then
        known_fields(definition.upgrade, {id = true, template_id = true, name = true, cost = true}, "Unknown building upgrade field: ")
        if definition.upgrade.cost then goods(definition.upgrade.cost) end
    end
    if definition.upgrade_to then assert(identity(definition.upgrade_to), "Invalid building upgrade reference") end
    if definition.upgraded_from then assert(identity(definition.upgraded_from), "Invalid building parent reference") end
    assert(definition.enabled == nil or type(definition.enabled) == "boolean", "Invalid building enable setting")
    assert(definition.fields == nil or type(definition.fields) == "table", "Invalid native building fields")
end

function Buildings.new(api)
    if type(api) == "table" and not api.adapter and api.directory then
        return require("mle_lib.building_runtime").new(api)
    end
    assert(type(api) == "table" and type(api.before_world_load) == "function", "Building phase guard is required")
    local adapter = assert(api.adapter, "Pinned native building adapter is required")
    for _, method in ipairs({"preflight", "register", "verify"}) do
        assert(type(adapter[method]) == "function", "Missing native building adapter " .. method)
    end
    local self, definitions, numeric, parts = {}, {}, {}, {}
    local templates = require("mle_lib.building_templates").new(copy)
    local state, receipt = "collecting", nil

    for _, method in ipairs({"register_building_template", "register_building_behavior", "register_building_panel"}) do
        self[method] = function(value)
            assert(state == "collecting", "Building registrations are frozen")
            templates[method](value)
        end
    end
    self.attach_instance = templates.attach_instance
    self.mount_panel = templates.mount_panel
    self.instance_for = templates.instance_for
    self.panel_mounts = templates.panel_mounts

    function self.register_building(definition)
        assert(state == "collecting", "Building registrations are frozen")
        definition = templates.resolve(copy(definition))
        if adapter.prepare then adapter.prepare(definition) end
        if api.identities then
            definition.numeric_id = api.identities.reserve("buildings", definition.id, definition.numeric_id)
            definition.construction_part_id = api.identities.reserve("parts", definition.id, definition.construction_part_id)
            if definition.upgrade_to then
                definition.upgrade = definition.upgrade or {}
                definition.upgrade.id = api.identities.reserve("upgrades", definition.id, definition.upgrade.id)
            end
        end
        assert(identity(definition.id), "Invalid building identity")
        definition.native_label = definition.native_label or ("MLE_" .. definition.id:gsub("[^%w_]", "_"))
        definition.construction_label = definition.construction_label or definition.native_label .. "_Construction"
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
                assert(definition.enabled == false or target.enabled ~= false, "Active upgrade requires an enabled target")
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
        templates.freeze()
        state = "applying"
        local rollback_failed = false
        local rollback_status = {}
        local function run(callback)
            if api.transaction then return callback(api.transaction) end
            return Rows.run(callback, rollback_status)
        end
        local ok, result = pcall(run, function(transaction)
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
                templates.bind(definition, guarded)
            end
            if #ordered > 0 and adapter.finalize then adapter.finalize(copy(ordered), reports, guarded) end
            for _, definition in ipairs(ordered) do
                assert(adapter.verify(copy(definition), reports[definition.id]) == true,
                    "Native building readback failed " .. definition.id)
            end
            return reports
        end)
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
        local entries = {}
        for id, definition in pairs(definitions) do
            entries[id] = {numeric_id = definition.numeric_id, construction_part_id = definition.construction_part_id,
                upgrade_id = definition.upgrade and definition.upgrade.id, enabled = definition.enabled ~= false,
                composition = templates.describe(definition.numeric_id)}
        end
        local reported = state
        if api.transaction and api.transaction.status then
            local parent = api.transaction.status.state
            if parent == "rolled_back" or parent == "reload_required" then reported = parent end
        end
        return {state = reported, ids = ids, entries = entries, gameplay_verified = false}
    end
    return self
end
return Buildings

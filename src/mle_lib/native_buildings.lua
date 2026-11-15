-- Build-specific host services are injected once by the UE4SS integration.
local Native = {}
local function text(value) return type(value) == "string" and value or value:ToString() end
function Native.new(api)
    for _, capability in ipairs({"assert_profile", "presentation", "upgrade", "world"}) do
        assert(type(api[capability]) == "function", "Missing native building capability " .. capability)
    end
    local self = {}
    function self.preflight(definition)
        api.assert_profile()
        local row = api.buildings:FindRow(tostring(definition.numeric_id))
        if definition.row_prepared then
            assert(row and text(row.DisplayName) == definition.native_label, "Prepared row ownership mismatch")
        else
            assert(not row, "Native building ID collision")
        end
        local template = assert(api.buildings:FindRow(tostring(definition.template_id)), "Native template missing")
        assert(text(template.DisplayName) == definition.template_label, "Native template identity mismatch")
        for field in pairs(definition.fields or {}) do
            assert(api.fields and api.fields[field], "Native building field is outside profile: " .. field)
        end
        return true
    end
    function self.register(definition, transaction)
        local table = transaction.table(api.buildings)
        local id = tostring(definition.numeric_id)
        if not definition.row_prepared then
            table:AddRow(id, table:FindRow(tostring(definition.template_id)))
        end
        local row = assert(table:FindRow(id))
        if not definition.row_prepared then row.DisplayName = api.make_name(definition.native_label) end
        for field, value in pairs(definition.fields or {}) do
            local old = row[field]
            transaction.defer(function() row[field] = old end)
            row[field] = value
            assert(row[field] == value, "Native field write failed: " .. field)
        end
        api.presentation(definition, row, transaction)
        return {numeric_id = definition.numeric_id, label = definition.native_label}
    end
    function self.finalize(definitions, reports, transaction)
        local world = api.world(definitions, transaction)
        for _, definition in ipairs(definitions) do
            reports[definition.id].world = world
            if definition.upgrade_to then api.upgrade(definition, definitions, transaction) end
        end
    end
    function self.verify(definition, report)
        local row = api.buildings:FindRow(tostring(definition.numeric_id))
        assert(row and text(row.DisplayName) == definition.native_label, "Native building row readback failed")
        for field, value in pairs(definition.fields or {}) do
            assert(row[field] == value, "Native building field readback failed: " .. field)
        end
        return report.world and report.world.mode == "standalone"
    end
    return self
end
return Native

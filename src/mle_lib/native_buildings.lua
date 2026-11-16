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
        for field, value in pairs(definition.fields or {}) do
            local expected = api.fields and api.fields[field]
            assert(expected, "Native building field is outside profile: " .. field)
            assert(expected == true or type(value) == expected or (expected == "integer" and math.type(value) == "integer"),
                "Invalid native building field type: " .. field)
        end
        if api.preflight then api.preflight(definition) end
        return true
    end
    function self.register(definition, transaction)
        local table = transaction.table(api.buildings)
        local id = tostring(definition.numeric_id)
        if not definition.row_prepared then
            table:AddRow(id, table:FindRow(tostring(definition.template_id)))
        end
        local row = assert(table:FindRow(id))
        if not definition.row_prepared then
            row.DisplayName = api.make_name(definition.native_label)
            if row.upgrades then row.upgrades:Empty() end
            if row.assemblyBlueprintVariations then row.assemblyBlueprintVariations:Empty() end
            row.upgradedFrom = -1
        end
        for field, value in pairs(definition.fields or {}) do
            local old = row[field]
            transaction.defer(function() row[field] = old end)
            row[field] = value
            assert(row[field] == value, "Native field write failed: " .. field)
        end
        if definition.families ~= nil then
            assert(row.workerTypes, "Building family capacity field missing")
            local previous = row.workerTypes.Y
            transaction.defer(function() row.workerTypes.Y = previous end)
            row.workerTypes.Y = definition.families
            assert(row.workerTypes.Y == definition.families, "Family capacity write failed")
        end
        if definition.construction_goods then
            local previous = {}
            for index = 1, #row.constructionGoods do
                local good = row.constructionGoods[index]
                previous[index] = {Type = good.Type, amt = good.amt}
            end
            local function set(goods)
                row.constructionGoods:Empty()
                for index, good in ipairs(goods) do row.constructionGoods[index] = good end
            end
            transaction.defer(function() set(previous) end)
            set(definition.construction_goods)
            assert(#row.constructionGoods == #definition.construction_goods, "Construction cost write failed")
            for index, good in ipairs(definition.construction_goods) do
                assert(row.constructionGoods[index].Type == good.Type and row.constructionGoods[index].amt == good.amt,
                    "Construction cost readback failed")
            end
        end
        if definition.enabled == false then
            local previous = {visible = row.bVisibleInUi, work = row.isWork, job = row.job, ai = row.AIcanBuild,
                families = row.workerTypes and row.workerTypes.Y}
            transaction.defer(function()
                row.bVisibleInUi, row.isWork, row.job, row.AIcanBuild = previous.visible, previous.work, previous.job, previous.ai
                if row.workerTypes then row.workerTypes.Y = previous.families end
            end)
            row.bVisibleInUi, row.isWork, row.job, row.AIcanBuild = false, false, 0, false
            if row.workerTypes then row.workerTypes.Y = 0 end
        end
        api.presentation(definition, row, transaction)
        return {numeric_id = definition.numeric_id, label = definition.native_label}
    end
    function self.finalize(definitions, reports, transaction)
        local world = api.world(definitions, transaction)
        for _, definition in ipairs(definitions) do
            reports[definition.id].world = world
            if definition.enabled ~= false and definition.upgrade_to then reports[definition.id].upgrade = api.upgrade(definition, definitions, transaction) end
        end
        if api.after_register then api.after_register(definitions, transaction) end
    end
    function self.verify(definition, report)
        local row = api.buildings:FindRow(tostring(definition.numeric_id))
        assert(row and text(row.DisplayName) == definition.native_label, "Native building row readback failed")
        for field, value in pairs(definition.fields or {}) do
            assert(row[field] == value, "Native building field readback failed: " .. field)
        end
        if definition.enabled == false then
            assert(row.bVisibleInUi == false and row.isWork == false and row.job == 0 and row.AIcanBuild == false,
                "Disabled building capability readback failed")
            assert(not row.workerTypes or row.workerTypes.Y == 0, "Disabled building still has family slots")
        elseif definition.families ~= nil then
            assert(row.workerTypes.Y == definition.families, "Building family capacity readback failed")
        end
        return report.world and report.world.mode == "standalone"
    end
    return self
end
return Native

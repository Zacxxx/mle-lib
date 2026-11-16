local Text = {}
local languages = {"en_US", "zh_CN", "zh_TW", "ja_JA", "ko_KR", "de_DE", "es_ES", "fr_FR", "pt_BR",
    "pl_PL", "ru_RU", "it_IT", "tr_TR", "cs_CZ", "hu_HU", "uk_UA", "da_DK", "nl_NL", "sv_SE"}
local root = "/Game/Translation/HoodedHorse/"
local function valid(value) return value and value:IsValid() end
local function text(value) return type(value) == "string" and value or value:ToString() end
function Text.install(definition, api, transaction)
    local id, template = tostring(definition.numeric_id), tostring(definition.template_id)
    local entries = {
        {path = root .. "DT_Translation_BuildingNames.DT_Translation_BuildingNames", required = true,
            key = "buildingID_" .. id, template = "buildingID_" .. template, value = definition.presentation.name},
        {path = root .. "DT_Translation_BuildingDescriptions.DT_Translation_BuildingDescriptions", required = true,
            key = "buildingID_" .. id .. "_descr", template = "buildingID_" .. template .. "_descr", value = definition.presentation.description},
        {path = root .. "CombinedDataTables/CDT_HoverTooltip.CDT_HoverTooltip",
            key = "buildingID_" .. id, template = "buildingID_" .. template, value = definition.presentation.name},
        {path = root .. "CombinedDataTables/CDT_HoverTooltip.CDT_HoverTooltip",
            key = "buildingID_" .. id .. "_descr", template = "buildingID_" .. template .. "_descr", value = definition.presentation.description},
    }
    if definition.presentation.worker_role then
        entries[#entries + 1] = {path = root .. "DT_Translation_BuildingNames.DT_Translation_BuildingNames", required = true,
            key = "MLE_Worker_" .. id, template = "buildingID_" .. template, value = definition.presentation.worker_role}
    end
    for _, key in ipairs({"upgrade_name", "upgrade_description"}) do
        if definition.presentation[key] then
            entries[#entries + 1] = {path = root .. "DT_Translation_BuildingNames.DT_Translation_BuildingNames", required = true,
                key = "MLE_" .. key .. "_" .. id, template = "buildingID_" .. template, value = definition.presentation[key]}
        end
    end
    for _, entry in ipairs(entries) do
        local data = api.find_object(entry.path)
        assert(not entry.required or valid(data), "Required building translation table missing")
        if valid(data) then
            assert(data.RowStruct:GetFullName() == "ScriptStruct /Script/ManorLords.LocalizedText", "Translation schema mismatch")
            local table = transaction.table(data)
            local row = table:FindRow(entry.key)
            if not row then
                local source = table:FindRow(entry.template) or table:FindRow("buildingID_36_descr")
                assert(source, "Native translation template missing")
                table:AddRow(entry.key, source)
                row = assert(table:FindRow(entry.key))
                for _, language in ipairs(languages) do row[language] = entry.value[language] or entry.value.en_US end
            end
            for _, language in ipairs(languages) do
                assert(text(row[language]) == (entry.value[language] or entry.value.en_US), "Translation collision/readback mismatch")
            end
        end
    end
end
return Text

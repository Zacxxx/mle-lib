local Preview = {}
function Preview.install(data, definitions, api, transaction)
    local entries = {}
    for _, definition in ipairs(definitions) do
        local row = assert(data:FindRow(tostring(definition.numeric_id)))
        local mesh = api.assets.load(definition.assets.preview)
        assert(mesh and mesh:IsValid() and mesh:GetFullName() == "StaticMesh " .. definition.assets.preview, "Building preview mesh mismatch")
        local path = api.kismet:MakeSoftObjectPath(definition.assets.preview)
        entries[#entries + 1] = {row = row:GetStructAddress(), label = row.DisplayName:GetComparisonIndex(),
            package = path.AssetPath.PackageName:GetComparisonIndex(), asset = path.AssetPath.AssetName:GetComparisonIndex(), source = path,
            path = type(path.GetStructAddress) == "function" and path:GetStructAddress() or nil}
    end
    api.bridge.paths(0, entries, transaction)
    return {method = "native_top_level_soft_path", buildings = #entries, world_validation_pending = true}
end
return Preview

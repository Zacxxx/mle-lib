-- Native world registration for cooked building assemblies on the pinned profile.
local World = {}
local function text(value) return type(value) == "string" and value or value:ToString() end
local function valid(value) return value and value:IsValid() end
local function path(row)
    assert(text(row.BlueprintPath.SubPathString) == "" and #row.assemblyBlueprintVariations == 0,
        "Assembly variations and subobjects require a dedicated profile")
    local names = row.BlueprintPath.AssetPath
    return text(names.PackageName) .. "." .. text(names.AssetName)
end
local function names(value, make_name)
    local package, asset = value:match("^(/Game/[%w_/]+)%.([%w_]+)$")
    assert(package and asset, "Invalid assembly class path")
    return {PackageName = make_name(package), AssetName = make_name(asset)}
end
local function set_path(row, value)
    row.BlueprintPath.AssetPath.PackageName = value.PackageName
    row.BlueprintPath.AssetPath.AssetName = value.AssetName
end

function World.install(data, entries, api, transaction)
    assert(api.before_world_load(), "Register building world assets before world load")
    assert(data.RowStruct:GetFullName() == "ScriptStruct /Script/ManorLords.Stat", "Unexpected building schema")
    local engine = api.find_object("/Script/Engine.StaticMeshActor")
    local base = api.find_object("/Script/ManorLords.Construction")
    local parts = api.find_object("/Game/NotStronghold/Data/DT_ConstructionBPs.DT_ConstructionBPs")
    assert(valid(engine) and valid(base) and valid(parts), "Native building classes or registry unavailable")
    assert(parts:GetFullName() == "DataTable /Game/NotStronghold/Data/DT_ConstructionBPs.DT_ConstructionBPs"
        and parts.RowStruct:GetFullName() == "ScriptStruct /Script/ManorLords.ConstructionBP", "Unexpected construction registry")
    local pending, ids, row_ids = {}, {}, {}
    for _, entry in ipairs(entries) do
        assert(math.type(entry.numeric_id) == "integer" and entry.numeric_id > 0
            and entry.numeric_id ~= entry.template_id and not row_ids[entry.numeric_id], "Invalid building row identity")
        row_ids[entry.numeric_id] = true
        assert(math.type(entry.construction_part_id) == "integer" and entry.construction_part_id > 0
            and not ids[entry.construction_part_id], "Invalid construction identity")
        ids[entry.construction_part_id] = true
        local row = assert(data:FindRow(tostring(entry.numeric_id)), "Owned building row missing")
        local template = assert(data:FindRow(tostring(entry.template_id)), "Building template missing")
        assert(text(row.DisplayName) == (entry.native_label or entry.label) and text(template.DisplayName) == entry.template_label,
            "Building row ownership differs")
        local assembly = api.assets.load_class(entry.assets.assembly)
        local construction = api.assets.load_class(entry.assets.construction)
        assert(valid(assembly) and assembly:IsChildOf(engine) and valid(construction) and construction:IsChildOf(base),
            "Owned building class has incorrect parent")
        local defaults = assembly:GetCDO()
        assert(valid(defaults) and defaults:IsA(engine), "Owned assembly defaults unavailable")
        local shell = api.find_object(entry.assets.assembly .. ":MainBld_" .. entry.construction_part_id .. "_GEN_VARIABLE")
        assert(valid(shell), "Owned assembly shell missing")
        local mesh = shell.StaticMesh
        if mesh and type(mesh.IsValid) ~= "function" then mesh = mesh:get() end
        assert(valid(mesh) and mesh:GetFullName() == "StaticMesh " .. (entry.assets.main_mesh or entry.assets.preview), "Owned assembly mesh differs")
        local current, original = path(row), path(template)
        assert(current == original or current == entry.assets.assembly, "Building assembly changed externally")
        local part_key = tostring(entry.construction_part_id)
        local part_label = api.make_name(entry.construction_label)
        local existing = parts:FindRow(part_key)
        if existing then
            assert(text(existing.buildingPartName) == entry.construction_label
                and existing.ConstructionBP:GetFullName() == construction:GetFullName(), "Construction part collision")
        end
        local source = api.make_path(entry.assets.construction)
        assert(text(source.SubPathString) == "", "Construction path must be top-level")
        assert(text(source.AssetPath.PackageName) .. "." .. text(source.AssetPath.AssetName) == entry.assets.construction,
            "Construction path readback differs")
        pending[#pending + 1] = {entry = entry, row = row, template = template, original = original,
            backup = names(current, api.make_name), target = names(entry.assets.assembly, api.make_name),
            existing = existing, part_key = part_key,
            part_fields = {ConstructionBP = construction, buildingPartName = part_label},
            label = part_label:GetComparisonIndex(), package = source.AssetPath.PackageName:GetComparisonIndex(),
            asset = source.AssetPath.AssetName:GetComparisonIndex(), source = source,
            path_address = type(source.GetStructAddress) == "function" and source:GetStructAddress() or nil}
    end
    local function apply(tx)
        local table = tx.table(parts)
        local bindings, added, changed = {}, 0, 0
        for _, step in ipairs(pending) do
            if not step.existing then table:AddRow(step.part_key, step.part_fields); added = added + 1 end
            local part = assert(table:FindRow(step.part_key))
            assert(text(part.buildingPartName) == step.entry.construction_label
                and part.ConstructionBP:GetFullName() == step.part_fields.ConstructionBP:GetFullName(), "Part readback failed")
            bindings[#bindings + 1] = {row = part:GetStructAddress(), label = step.label,
                package = step.package, asset = step.asset, path = step.path_address, source = step.source}
            tx.defer(function() set_path(step.row, step.backup) end)
            if path(step.row) ~= step.entry.assets.assembly then
                set_path(step.row, step.target); changed = changed + 1
            end
            assert(path(step.row) == step.entry.assets.assembly and path(step.template) == step.original,
                "Assembly binding readback failed")
        end
        api.bind_construction_paths(bindings, tx)
        if api.resolve_part then
            for _, step in ipairs(pending) do
                local class = api.resolve_part(step.entry.construction_part_id)
                assert(valid(class) and class:GetFullName() == step.part_fields.ConstructionBP:GetFullName(), "Native part resolution failed")
            end
        end
        local previews = api.bind_previews(entries, tx)
        return {mode = "standalone", parts = {added = added, state = "verified_readback", world_lookup_pending = not api.resolve_part},
            assemblies = {changed = changed, state = "verified_readback"}, previews = previews, gameplay_verified = false}
    end
    if transaction then return apply(transaction) end
    return require("mle_lib.rows").run(apply)
end
return World

-- Owned pak assets are absent from the base game's AssetRegistry.bin.
-- Resolve their soft references through Unreal, rather than UE4SS LoadAsset.
local Assets = {}
local function valid(object)
    local kind = type(object)
    return (kind == "table" or kind == "userdata") and type(object.IsValid) == "function" and object:IsValid()
end
local function owned_path(path, root)
    assert(type(path) == "string", "Expected a Ruralities asset path string")
    local package, name = path:match("^(/Game/[%w_/]+)%.([%w_]+)$")
    assert(package and package:sub(1, #root) == root and name and package:match("([^/]+)$") == name and not path:find("//", 1, true),
        "Expected an owned, canonical asset path")
end

function Assets.new(api)
    local root = assert(api.asset_root, "Supply the package asset namespace")
    assert(root:match("^/Game/[%w_/]+/$") and not root:find("//", 1, true), "Invalid package asset namespace")
    local self, cache, library = {}, {}, nil
    local attempts = 0
    local function reference_for(path)
        if not valid(library) then library = api.find_object("/Script/Engine.KismetSystemLibrary") end
        assert(valid(library), "Native KismetSystemLibrary is unavailable")
        local soft_path = library:MakeSoftObjectPath(path)
        local reference = library:Conv_SoftObjPathToSoftObjRef(soft_path)
        assert(reference and reference:type() == "TSoftObjectPtrUserdata", "Native soft-object conversion failed")
        return reference
    end
    local function load(path)
        local asset = cache[path]
        if not valid(asset) then
            asset = api.find_object(path)
            if not valid(asset) then
                local reference = reference_for(path)
                attempts = attempts + 1
                if api.checkpoint then api.checkpoint("assets.load_blocking", {asset = path}) end
                asset = library:LoadAsset_Blocking(reference)
            end
            assert(valid(asset), "Native blocking load failed: " .. path)
            assert(asset:GetFullName():match("^%S+ (.+)$") == path, "Loaded asset identity differs from the requested package")
            cache[path] = asset
        end
        return asset
    end
    function self.reference(path)
        owned_path(path, root)
        return reference_for(path)
    end
    function self.load(path)
        owned_path(path, root)
        return load(path)
    end
    function self.load_reference(path)
        assert(api.references and api.references[path], "Asset is outside the approved reference list")
        return load(path)
    end
    function self.load_class(path)
        local package, name = path:match("^(/Game/[%w_/]+)%.([%w_]+)_C$")
        assert(package and package:sub(1, #root) == root and package:match("([^/]+)$") == name, "Expected an owned Blueprint class")
        local asset = cache[path]
        if not valid(asset) then
            if not valid(library) then library = api.find_object("/Script/Engine.KismetSystemLibrary") end
            assert(valid(library), "Native KismetSystemLibrary is unavailable")
            local soft_path = library:MakeSoftClassPath(path)
            local reference = library:Conv_SoftClassPathToSoftClassRef(soft_path)
            attempts = attempts + 1
            asset = library:LoadClassAsset_Blocking(reference)
            assert(valid(asset) and asset:GetFullName() == "BlueprintGeneratedClass " .. path,
                "Owned Blueprint class failed to load")
            cache[path] = asset
        end
        return asset
    end
    function self.status()
        local loaded = {}
        for path, asset in pairs(cache) do if valid(asset) then loaded[#loaded + 1] = path end end
        table.sort(loaded)
        return {method = "KismetSystemLibrary.LoadAsset_Blocking", blocking_loads = attempts, loaded = loaded}
    end
    return self
end
return Assets

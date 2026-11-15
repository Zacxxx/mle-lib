local Artwork = {}

function Artwork.new(api)
    local cache = {}
    return function(key)
        if not key then return nil end
        assert(key:match("^[a-z_]+$"), "Invalid artwork key")
        local cached = cache[key]
        if cached and cached:IsValid() then return cached end
        local renderer = api.find_object("/Script/Engine.Default__KismetRenderingLibrary")
        local world_context = api.world_context()
        if not world_context or not world_context:IsValid() then return nil end
        assert(renderer and renderer:IsValid(), "Artwork renderer unavailable")
        if api.trace then api.trace("ui.before_import_artwork", {artwork = key}) end
        local directory = type(api.directory) == "function" and api.directory() or api.directory
        local image = renderer:ImportFileAsTexture2D(world_context, directory .. "/" .. key .. ".png")
        assert(image and image:IsValid(), "Artwork could not be loaded: " .. key)
        if api.trace then api.trace("ui.after_import_artwork", {artwork = key}) end
        cache[key] = image
        return image
    end
end

return Artwork

local Host = require("mle_lib.host")

local Catalog = {}

local function component(value)
    return value:match("^[A-Za-z0-9][A-Za-z0-9_.-]*$") and not value:match("%.$")
end

local function entry_path(directory, value)
    assert(type(value) == "string" and value:match("%.lua$"), "Expected a Lua package entry")
    for segment in (value .. "/"):gmatch("(.-)/") do
        assert(component(segment), "Invalid package entry path")
    end
    return directory .. "/" .. value
end

function Catalog.load(mods, contents, runtime)
    local packages, directories, seen = {}, {}, {}
    for line in contents:gmatch("[^\r\n]+") do
        local folder = line:match("^%s*([^#%s]+)%s*$")
        if folder then
            assert(component(folder) and folder:lower() ~= "mlelib" and not seen[folder:lower()],
                "Invalid or duplicate package directory " .. folder)
            seen[folder:lower()] = true
            local directory = mods .. "/" .. folder
            local manifest = assert(loadfile(directory .. "/manifest.lua", "t", {}))()
            assert(type(manifest) == "table" and type(manifest.id) == "string", "Invalid package manifest")
            packages[#packages + 1] = manifest
            directories[manifest.id] = directory
        else
            assert(line:match("^%s*$") or line:match("^%s*#"), "Invalid package catalog line")
        end
    end
    local plan, failure = Host.plan(packages, {}, {capabilities = runtime:capabilities()})
    assert(plan, failure and failure.code .. ": " .. failure.message)
    for _, manifest in ipairs(plan) do
        local directory = directories[manifest.id]
        local chunk = assert(loadfile(entry_path(directory, manifest.entry), "t"))
        runtime:register(manifest, function(context)
            local activate = chunk()
            assert(type(activate) == "function", "Package entry must return an activation function")
            activate(context)
        end, directory)
    end
end

return Catalog

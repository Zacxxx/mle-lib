-- Embed namespaced package state in native SavedBuilding.buildingTags.
local Codec = require("mle_lib.state_codec")
local function text(value)
    if type(value) ~= "string" then
        local ok, unwrapped = pcall(function() return value:get() end)
        if ok then value = unwrapped end
    end
    return type(value) == "string" and value or value:ToString()
end
local function hex(value) return (value:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function unhex(value)
    assert(#value % 2 == 0 and not value:find("[^0-9a-f]"), "Corrupt rural state tag")
    return (value:gsub("..", function(c) return string.char(tonumber(c, 16)) end))
end
local function checksum(value)
    local sum = 2166136261
    for i = 1, #value do sum = ((sum ~ value:byte(i)) * 16777619) & 0xffffffff end
    return string.format("%08x", sum)
end
local function new(prefix)
    assert(type(prefix) == "string" and prefix:match("^MLE_[A-Z0-9_]+_$"), "Invalid native save tag prefix")
    local Save = {}
    function Save.write(object, state, make_name, live_tags)
        local payload = Codec.encode({schema = 1, state = state, day = object.daysTotal,
            level = live_tags and "" or text(object.LevelName), exact = not live_tags})
        local count = math.ceil(#payload / 200)
        assert(#object.savedBuildings > 0 and count <= 2048, "Cannot attach native package state to this save")
        local prepared, original = {}, {}
        for i = 1, #object.savedBuildings do
            local tags = object.savedBuildings[i].buildingTags
            local values, before = {}, {}
            for j = 1, #tags do
                local name = text(tags[j]); before[#before + 1] = name
                if name:sub(1, #prefix) ~= prefix then values[#values + 1] = name end
            end
            prepared[i], original[i] = values, before
        end
        local digest = checksum(payload)
        for i = 1, count do
            prepared[1][#prepared[1] + 1] = prefix .. i .. "_" .. count .. "_" .. digest
                .. "_" .. hex(payload:sub((i - 1) * 200 + 1, i * 200))
        end
        -- Preparation and encoding finish before any save-object mutation.
        local function replace(index, values)
            local tags = object.savedBuildings[index].buildingTags
            tags:Empty()
            for j, value in ipairs(values) do tags[j] = make_name(value) end
            assert(#tags == #values, "Native package save tag write failed")
            for j, value in ipairs(values) do assert(text(tags[j]) == value, "Native package save tag readback failed") end
        end
        local changed = {}
        local ok, failure = pcall(function()
            for i = 1, #object.savedBuildings do
                if table.concat(original[i], "\0") ~= table.concat(prepared[i], "\0") then
                    changed[#changed + 1] = i
                    replace(i, prepared[i])
                end
            end
        end)
        if not ok then
            local errors = {}
            for i = #changed, 1, -1 do
                local restored, reason = pcall(replace, changed[i], original[changed[i]])
                if not restored then errors[#errors + 1] = tostring(reason) end
            end
            error(tostring(failure) .. (#errors > 0 and "; rollback failed: " .. table.concat(errors, "; ") or ""))
        end
        return {chunks = count, bytes = #payload}
    end
    function Save.read(object, allow_older_day)
        local chunks, total, digest = {}, nil, nil
        for i = 1, #object.savedBuildings do
            local tags = object.savedBuildings[i].buildingTags
            for j = 1, #tags do
                local value = text(tags[j])
                if value:sub(1, #prefix) == prefix then
                    local index, count, hash, part = value:sub(#prefix + 1):match("^(%d+)_(%d+)_(%x+)_(%x+)$")
                    index, count = tonumber(index), tonumber(count)
                    assert(index and count and count > 0 and count <= 2048 and index > 0 and index <= count
                        and #part <= 400 and #hash == 8 and not chunks[index] and (not total or total == count) and (not digest or digest == hash),
                        "Mixed, duplicate or invalid native package state chunks")
                    chunks[index], total, digest = unhex(part), count, hash
                end
            end
        end
        if not total then return nil end
        for i = 1, total do assert(chunks[i], "Incomplete native package state in save") end
        local payload = table.concat(chunks)
        assert(checksum(payload) == digest, "Native package save checksum mismatch")
        local result = Codec.decode(payload)
        assert(result.schema == 1 and type(result.day) == "number" and type(result.exact) == "boolean"
            and ((result.exact and (result.day == object.daysTotal or (allow_older_day and result.day < object.daysTotal))
                    and result.level == text(object.LevelName))
                or (not result.exact and result.day <= object.daysTotal and result.level == ""))
            and type(result.state) == "table", "Native package state belongs to a different save snapshot")
        return result.state
    end
    return Save
end

local shared = new("MLE_LIB_STATE_V1_")
shared.new = new
return shared

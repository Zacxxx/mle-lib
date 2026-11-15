-- Small deterministic JSON writer for scalar diagnostic reports; no game objects.
local Json = {}
local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
    ['\r'] = '\\r', ['\t'] = '\\t'}

local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
        return escapes[character] or string.format('\\u%04x', character:byte())
    end) .. '"'
end

function Json.encode(value, visited)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "string" then return quote(value) end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        assert(value == value and math.abs(value) < math.huge, "non-finite JSON number")
        return tostring(value)
    end
    assert(kind == "table", "unsupported JSON value: " .. kind)
    visited = visited or {}
    assert(not visited[value], "cyclic JSON table")
    visited[value] = true
    local keys, array = {}, #value > 0
    for key in pairs(value) do
        keys[#keys + 1] = key
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #value then
            array = false
        end
    end
    local parts = {}
    if array and #keys == #value then
        for index = 1, #value do parts[index] = Json.encode(value[index], visited) end
    else
        for _, key in ipairs(keys) do assert(type(key) == "string", "JSON object key must be a string") end
        table.sort(keys)
        for _, key in ipairs(keys) do
            parts[#parts + 1] = quote(key) .. ":" .. Json.encode(value[key], visited)
        end
    end
    visited[value] = nil
    return (array and "[" or "{") .. table.concat(parts, ",") .. (array and "]" or "}")
end

return Json

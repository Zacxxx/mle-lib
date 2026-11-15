-- Bounded data-only encoding. No load(), executable Lua, JSON dependencies or
-- filesystem paths from a save. Maps have string keys; numeric values are finite.
local Codec = {}
local function encode(value, depth, visited)
    assert(depth <= 12, "State nesting limit exceeded")
    if type(value) == "boolean" then return value and "B1" or "B0" end
    if type(value) == "number" then
        assert(value == value and math.abs(value) < math.huge, "Invalid state number")
        local text = string.format("%.17g", value)
        return "N" .. #text .. ":" .. text
    end
    if type(value) == "string" then
        assert(#value <= 32768, "State string too large")
        return "S" .. #value .. ":" .. value
    end
    assert(type(value) == "table" and not visited[value], "Invalid or cyclic state")
    visited[value] = true
    local keys = {}
    for key in pairs(value) do assert(type(key) == "string", "State keys must be strings"); keys[#keys + 1] = key end
    assert(#keys <= 2048, "State map too large")
    table.sort(keys)
    local parts = {"T" .. #keys .. ":"}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = encode(key, depth + 1, visited)
        parts[#parts + 1] = encode(value[key], depth + 1, visited)
    end
    visited[value] = nil
    return table.concat(parts)
end
function Codec.encode(value)
    local result = encode(value, 0, {})
    assert(#result <= 262144, "Rural state exceeds save limit")
    Codec.decode(result) -- Encoder and decoder share the same complexity limits.
    return result
end
function Codec.decode(data)
    assert(type(data) == "string" and #data <= 262144, "Invalid state payload")
    local position, nodes = 1, 0
    local function parse(depth)
        nodes = nodes + 1
        assert(depth <= 12 and nodes <= 20000, "State complexity limit exceeded")
        local kind = data:sub(position, position); position = position + 1
        if kind == "B" then
            local value = data:sub(position, position); position = position + 1
            assert(value == "0" or value == "1", "Invalid state boolean")
            return value == "1"
        end
        assert(kind == "N" or kind == "S" or kind == "T", "Unknown state type")
        local start, finish, count = data:find("^(%d+):", position)
        assert(start and finish - start <= 6, "Invalid state length")
        position, count = finish + 1, tonumber(count)
        if kind == "T" then
            assert(count <= 2048, "State map too large")
            local result = {}
            for _ = 1, count do
                local key = parse(depth + 1)
                assert(type(key) == "string" and result[key] == nil, "Invalid or duplicate state key")
                result[key] = parse(depth + 1)
            end
            return result
        end
        assert(count <= (kind == "N" and 64 or 32768) and position + count - 1 <= #data, "Truncated state value")
        local value = data:sub(position, position + count - 1); position = position + count
        if kind == "S" then return value end
        assert(value:match("^[%d%+%-%.eE]+$"), "Invalid state number syntax")
        local number = tonumber(value)
        assert(number and number == number and math.abs(number) < math.huge, "Invalid state number")
        return number
    end
    local result = parse(0)
    assert(position == #data + 1, "Trailing state data")
    return result
end
return Codec

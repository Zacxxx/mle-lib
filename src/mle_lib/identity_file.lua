local File = {}
function File.read(path)
    local file = io.open(path, "rb"); if not file then return nil end
    local value = file:read("*a"); file:close(); return value
end
function File.write(path, value)
    local file = assert(io.open(path .. ".tmp", "wb")); local ok, reason = file:write(value); file:close(); assert(ok, reason)
    assert(File.read(path .. ".tmp") == value, "Identity staging readback failed")
    -- Keep the previous ledger recoverable if replacement fails.
    if File.read(path) then
        os.remove(path .. ".bak"); assert(os.rename(path, path .. ".bak"))
    end
    local moved, error = os.rename(path .. ".tmp", path)
    if not moved then os.rename(path .. ".bak", path); assert(moved, error) end
end
return File

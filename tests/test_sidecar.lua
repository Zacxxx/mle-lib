package.path = "src/?.lua;" .. package.path
local Sidecar = require("mle_lib.sidecar")

local function encode(value)
    if value.format then
        return "E" .. string.pack(">s4s4s4", value.format, value.checksum, value.payload)
    end
    return "D" .. string.pack(">s4s4s4I4i4", value.namespace, value.save_id, value.fingerprint, value.schema, value.data.count)
end

local function decode(bytes)
    if bytes:sub(1, 1) == "E" then
        local format, checksum, payload = string.unpack(">s4s4s4", bytes, 2)
        return {format = format, checksum = checksum, payload = payload}
    end
    assert(bytes:sub(1, 1) == "D", "Invalid fixture")
    local namespace, save_id, fingerprint, schema, count = string.unpack(">s4s4s4I4i4", bytes, 2)
    return {namespace = namespace, save_id = save_id, fingerprint = fingerprint, schema = schema, data = {count = count}}
end

local function checksum(bytes)
    local digest = 0
    for index = 1, #bytes do digest = ((digest * 131) ~ bytes:byte(index)) % 2147483647 end
    return tostring(digest)
end

local files = {["original.sav"] = "native save bytes"}
local fail_publish
local fs = {
    read = function(path) return files[path] end,
    write = function(path, bytes) files[path] = bytes; return true end,
    rename = function(from, to)
        if to == fail_publish then return false end
        assert(files[from])
        files[to], files[from] = files[from], nil
        return true
    end,
    remove = function(path) files[path] = nil; return true end,
}
local options = {fs = fs, encode = encode, decode = decode, checksum = checksum}
local state = Sidecar.new(options)
local first = {namespace = "ruralities", save_id = "slot", fingerprint = "first"}
local second = {namespace = "ruralities", save_id = "slot", fingerprint = "second"}

assert(not pcall(state.save, state, "../original.sav", first, 1, {count = 8}))
local ticket = state:prepare("slot", first, 1, {count = 8})
assert(not pcall(state.prepare, state, "slot", first, 1, {count = 99}))
local loaded, status = state:load("slot", first, 1)
assert(not loaded and status.state == "missing" and status.pending)
assert(not pcall(state.commit, state, ticket, second))
assert(state:commit(ticket, first))
loaded, status = state:load("slot", first, 2, {[1] = function(data) data.count = data.count + 1; return data end})
assert(loaded.count == 9 and status.original_schema == 1 and status.schema == 2)
assert(state:load("slot", first, 1).count == 8, "Migrations run in memory until committed")
loaded, status = state:load("slot", first, 2)
assert(not loaded and status.state == "migration_missing")

ticket = state:prepare("slot", second, 2, {count = 10})
fail_publish = "slot.state"
assert(not pcall(state.commit, state, ticket, second))
local restarted = Sidecar.new(options)
loaded, status = restarted:load("slot", first, 1)
assert(loaded.count == 8 and status.pending)
loaded, status = restarted:load("slot", second, 2)
assert(not loaded and status.state == "mismatch" and status.pending)
fail_publish = nil
assert(restarted:save("slot", second, 2, {count = 11}))
loaded, status = restarted:load("slot", first, 1)
assert(loaded.count == 8 and status.state == "recovered" and not status.pending)
loaded, status = restarted:load("slot", second, 1)
assert(not loaded and status.state == "newer_schema")
files["slot.state"] = files["slot.state"]:sub(1, -2) .. "x"
loaded, status = restarted:load("slot", first, 1)
assert(loaded.count == 8 and status.state == "recovered", "A valid backup recovers prior matching state")
loaded, status = restarted:load("slot", second, 2)
assert(not loaded and status.state == "invalid", "A corrupt companion whose backup belongs to another fingerprint refuses recovery")
assert(files["original.sav"] == "native save bytes")
print("PASS prepared state visibility; save fingerprint checks; atomic publish and backup recovery; in-memory migration; original save untouched")

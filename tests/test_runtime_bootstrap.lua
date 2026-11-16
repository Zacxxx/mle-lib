local root = "src/ue4ss"
local boot
local verified, discovered, started = false, false, false
local logs = {}
local original_print = print
local original_open = io.open

package.loaded.UEHelpers = {
    GetPlayer = function() end,
    GetGameInstance = function()
        return {IsValid = function() return true end, GetAppVersion = function() return "Version 0.8.117" end}
    end,
}
package.loaded["mle_lib.building_bridge"] = {open = function()
    return {verify = function()
        assert(verified, "Unsupported game or UE4SS profile")
    end}
end}
package.loaded["mle_lib.catalog"] = {load = function()
    assert(verified)
    discovered = true
end}
package.loaded["mle_lib.runtime"] = {new = function()
    assert(verified)
    return {capabilities = function() return {} end, start = function() started = true; return {} end,
        bind_save = function() end, apply_registry = function() end}
end}

StaticFindObject = function() return {IsValid = function() return true end} end
LoopInGameThreadWithDelay = function(_, callback) boot = callback end
RegisterConsoleCommandGlobalHandler = function() assert(started) end
print = function(message) logs[#logs + 1] = message end
io.open = function(path, mode)
    if path == root .. "/packages.txt" then
        assert(verified)
        return {read = function() return "" end, close = function() end}
    end
    return original_open(path, mode)
end

assert(loadfile(root .. "/Scripts/main.lua"))()
boot()
assert(not discovered and not started)
assert(logs[1]:find("Unsupported game or UE4SS profile", 1, true))
verified = true
assert(loadfile(root .. "/Scripts/main.lua"))()
boot()
assert(discovered and started)

print = original_print
io.open = original_open
print("PASS: runtime verifies the exact native profile before discovery and activation")

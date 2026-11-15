local Host, Registry = require("mle_lib.host"), require("mle_lib.registry")
local descriptors = assert(loadfile(assert(arg[1], "Pass the manifest built by mle.py")))()

local function run(disable_storage)
    local baseline, events = {storage = 100, workers = 2}, {}
    local registry = Registry.new({
        read = function(_, field) return baseline[field] end,
        write = function(_, field, value) baseline[field] = value end,
        fields = {buildings = {storage = "integer", workers = "integer"}},
        can_write = function() return true end,
    })
    local host = Host.new({services = {registry = registry, events = events},
        enabled = {["example.storage"] = not disable_storage}})
    for _, descriptor in ipairs(descriptors) do
        local entry = assert(loadfile("examples/" .. descriptor.location .. "/" .. descriptor.entry))
        descriptor.activate = assert(entry())
        host:register(descriptor)
    end
    local order = assert(host:start())
    assert(#order == (disable_storage and 2 or 3))
    registry:freeze()
    registry:apply()
    assert(host:emit("world.ready") == 2)
    assert(baseline.storage == (disable_storage and 100 or 125) and baseline.workers == 3)
    assert(table.concat(events, ",") == "example.balance,example.seasons")
    assert(host:stop())
    registry:restore()
    assert(baseline.storage == 100 and baseline.workers == 2)
end

run(false)
run(true)
print("PASS: three independent example packages share one host and patch registry")

local Host = require("mle_lib.host")

local function manifest(id, requires, activate)
    return {id = "example." .. id, version = "1.0.0", engine = "^0.1.0", requires = requires, activate = activate}
end

local first, second, third = manifest("a"), manifest("b", {["example.a"] = "^1.0.0"}), manifest("c")
local planned = assert(Host.plan({second, third, first}, {["example.c"] = false}))
assert(#planned == 2 and planned[1].id == "example.a" and planned[2].id == "example.b")
local function refused(packages, enabled, options, code)
    local result, failure = Host.plan(packages, enabled, options)
    assert(not result and failure.code == code, failure and failure.message or code)
end
refused({first, second}, {["example.a"] = false}, nil, "disabled_dependency")
refused({second}, nil, nil, "missing_dependency")
refused({first, first}, nil, nil, "duplicate_package")
refused({second, manifest("a", {["example.b"] = "*"})}, nil, nil, "dependency_cycle")
first.version = "2.0.0"
refused({second, first}, nil, nil, "dependency_version")
first.version = "1.0.0"
first.capabilities = {"content.buildings"}
refused({first}, nil, nil, "missing_capability")
assert(Host.plan({first}, nil, {capabilities = {["content.buildings"] = true}}))
first.capabilities = nil
first.engine = "~0.1.0"
assert(Host.plan({first}, nil, {version = "0.1.5"}))
refused({first}, nil, {version = "0.2.0"}, "engine_version")
assert(Host.matches("1.3.1", ">=1.2.0 <2.0.0"))
assert(not Host.matches("1.0.0", ">=1.2.0 <2.0.0"))
assert(not Host.matches("0.2.0", "^0.1.5"))
assert(not Host.matches("1.0.0", "1.0"))
assert(not Host.matches("1.0.0", ">=1.0.0<2.0.0"))
assert(not Host.matches("1.0.0", ">=1.0.0 nonsense"))

local events, cleanups, errors = {}, {}, {}
local host = Host.new({services = {version = 3}, report = function(record) errors[#errors + 1] = record end})
local unsubscribe
host:register(manifest("c", nil, function(context)
    assert(context.services.version == 3 and context.id == "example.c")
    context:on("world.ready", function() error("listener failure") end, 10)
    context:defer(function() cleanups[#cleanups + 1] = "c" end)
end))
host:register(manifest("b", {["example.a"] = "*"}, function(context)
    context:on("world.ready", function(value) events[#events + 1] = "b" .. value end, 10)
    context:defer(function() cleanups[#cleanups + 1] = "b" end)
end))
host:register(manifest("a", nil, function(context)
    unsubscribe = context:on("world.ready", function(value) events[#events + 1] = "a" .. value end)
    context:defer(function() cleanups[#cleanups + 1] = "a" end)
end))
assert(table.concat(assert(host:start()), ",") == "example.a,example.b,example.c")
assert(not pcall(host.register, host, manifest("d")))
local delivered, failures = host:emit("world.ready", "1")
assert(delivered == 2 and #failures == 1 and failures[1].id == "example.c")
assert(table.concat(events, ",") == "b1,a1" and errors[#errors].code == "listener_failed")
assert(unsubscribe())
assert(not unsubscribe())
host:emit("world.ready", "2")
assert(table.concat(events, ",") == "b1,a1,b2")
assert(host:stop())
assert(table.concat(cleanups, ",") == "c,b,a")
assert(not host:stop())
assert(not pcall(host.emit, host, "world.ready", ""))

local rolled_back = {}
local broken = Host.new()
broken:register(manifest("a", nil, function(context)
    context:defer(function() rolled_back[#rolled_back + 1] = "a" end)
end))
broken:register(manifest("b", {["example.a"] = "*"}, function(context)
    context:defer(function() rolled_back[#rolled_back + 1] = "b" end)
    error("activation failure")
end))
local active, failure = broken:start()
assert(not active and failure.code == "activation_failed")
assert(table.concat(rolled_back) == "ba")
assert(broken:state() == "failed")
print("PASS: ordered MLE Lib package activation, compatibility, callback ownership, and rollback")

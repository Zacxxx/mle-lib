local Hooks = require("mle_lib.hooks")
local count, before, after = 0
local broker = Hooks.new(function(_, first, second)
    count, before, after = count + 1, first, second
end)
local seen = {}
broker.add("/Script/Example:Work", function(value) seen[#seen + 1] = value end)
local remove = broker.add("/Script/Example:Work", function(value) seen[#seen + 1] = value + 1 end,
    function() return true end)
assert(count == 1 and after() == true)
before(7)
assert(table.concat(seen, ",") == "7,8")
remove()
before(9)
assert(table.concat(seen, ",") == "7,8,9" and after() == nil)
print("PASS one physical reflected hook, ordered callbacks and unsubscribe")

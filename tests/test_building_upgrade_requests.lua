local Requests = require("mle_lib.building_upgrade_requests")
local pawn = {IsValid = function() return true end}
local started, native_tick_calls, queue, callbacks = 0, 0, {}, {}
local done = {7, 117, 8, Empty = function(self) for index = #self, 1, -1 do self[index] = nil end end}
local building = {
    IsValid = function() return true end,
    GetType = function() return 487 end,
    getOwnerPawn = function() return pawn end,
    IsConstructed = function() return true end,
    isBeingUpgraded = false, upgradesDone = done,
    BeginUpgrade = function(_, action)
        assert(not pawn.upgradeRequestPending and action == 117)
        assert(#done == 2 and done[1] == 7 and done[2] == 8)
        started = started + 1
        return true
    end,
}
local definitions = {[487] = {upgrade_id = 117}}
local requests = Requests.new({
    find_object = function() return {IsValid = function() return true end} end,
    find_all = function() return {building} end,
    schedule = function(_, callback) queue[#queue + 1] = callback end,
    hooks = {add = function(path, before, after)
        assert(path == "/Script/ManorLords.PawnCPP:addUpgradeRequest")
        callbacks.before, callbacks.after = before, after
        return function() callbacks = {} end
    end},
})
requests.start(function() return definitions end)
pawn.UpgradeRequest = {BuildingMaster = building, upgradeID = 117}
pawn.upgradeRequestPending = true
callbacks.after({get = function() return pawn end})
if pawn.upgradeRequestPending then native_tick_calls = native_tick_calls + 1 end
assert(started == 1 and native_tick_calls == 0 and #done == 2)
assert(not requests.dispatch(pawn, definitions))
pawn.UpgradeRequest.upgradeID = 7
pawn.upgradeRequestPending = true
callbacks.after({get = function() return pawn end})
assert(pawn.upgradeRequestPending and started == 1)
done[3] = 117
building.isBeingUpgraded = true
assert(not requests.recover(building, definitions) and #done == 3)
building.isBeingUpgraded = false
queue[1]()
assert(#done == 2)
requests.stop()
assert(next(callbacks) == nil)
local count = #queue
queue[#queue]()
assert(#queue == count)
print("PASS: normal custom upgrade requests route once through the adapter and stale history recovers")

local foreign_pawn = {IsValid = function() return true end, upgradeRequestPending = true,
    UpgradeRequest = {BuildingMaster = building, upgradeID = 117}}
assert(not requests.dispatch(foreign_pawn, definitions) and foreign_pawn.upgradeRequestPending)
pawn.UpgradeRequest.upgradeID = 117
pawn.upgradeRequestPending = true
building.BeginUpgrade = function() return false end
assert(not requests.dispatch(pawn, definitions) and not pawn.upgradeRequestPending)
assert(#done == 2)

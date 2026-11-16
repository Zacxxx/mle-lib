-- Native UI queues a Pawn request and later calls the non-reflected upgrade body.
-- Route owned actions through BeginUpgrade so our registered adapter receives them.
local Requests = {}
local function valid(value) return value and value:IsValid() end

function Requests.new(api)
    local self = {}
    local running = false
    local generation = 0
    local remove
    local function log(message)
        if api.log then api.log(message) end
    end

    local function definition(building, definitions)
        if not valid(building) then return end
        local entry = definitions[building:GetType()]
        if entry and entry.upgrade_id then return entry end
    end

    function self.recover(building, definitions)
        local entry = definition(building, definitions)
        if not entry or not building:IsConstructed() or building.isBeingUpgraded then return false end
        local previous, remaining = {}, {}
        local done = building.upgradesDone
        for index = 1, #done do
            local action = done[index]
            previous[index] = action
            if action ~= entry.upgrade_id then remaining[#remaining + 1] = action end
        end
        if #remaining == #previous then return false end
        local function replace(values)
            done:Empty()
            for index, value in ipairs(values) do done[index] = value end
            assert(#done == #values, "Upgrade history write failed")
            for index, value in ipairs(values) do assert(done[index] == value, "Upgrade history readback failed") end
        end
        local ok, reason = pcall(replace, remaining)
        if not ok then
            local restored, failure = pcall(replace, previous)
            assert(restored, "Upgrade history rollback failed: " .. tostring(failure))
            error(reason, 0)
        end
        log("Restored unstarted custom upgrade " .. entry.upgrade_id .. " on building type " .. building:GetType())
        return true
    end

    function self.dispatch(pawn, definitions)
        if not valid(pawn) or not pawn.upgradeRequestPending then return false end
        local request = pawn.UpgradeRequest
        local building = request.BuildingMaster
        local entry = definition(building, definitions)
        if not entry or request.upgradeID ~= entry.upgrade_id then return false end
        if building:getOwnerPawn() ~= pawn then return false end
        -- Clear before dispatch. The native game-state tick must never consume it again.
        pawn.upgradeRequestPending = false
        self.recover(building, definitions)
        local accepted = building:BeginUpgrade(entry.upgrade_id)
        if not accepted then log("Custom upgrade " .. entry.upgrade_id .. " was rejected by native eligibility") end
        return accepted == true
    end

    function self.start(definitions)
        assert(not running, "Upgrade request routing already active")
        local path = "/Script/ManorLords.PawnCPP:addUpgradeRequest"
        assert(valid(api.find_object(path)), "Native addUpgradeRequest unavailable")
        running, generation = true, generation + 1
        local current = generation
        remove = api.hooks.add(path, function() end, function(context)
            if running and generation == current then self.dispatch(context:get(), definitions()) end
        end)
        local function recover()
            if not running or generation ~= current then return end
            local entries = definitions()
            for _, building in ipairs(api.find_all("SMBuildingMaster") or {}) do
                local ok, reason = pcall(self.recover, building, entries)
                if not ok then log(tostring(reason)) end
            end
            api.schedule(2000, recover)
        end
        api.schedule(0, recover)
    end

    function self.stop()
        running, generation = false, generation + 1
        if remove then remove(); remove = nil end
    end
    return self
end

return Requests

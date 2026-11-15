-- Keep recurring work in Lua. One permanent native game-thread callback avoids
-- the async timer -> ExecuteInGameThread registry handoff race in UE4SS.
local M = {}
local INTERVAL = 20
function M.new(api)
    local self, jobs = {}, {}
    local elapsed, previous_clock, next_id = 0, nil, 0
    local handle, dispatching, last_error
    local function traced(label, callback, ...)
        if api.trace then return api.trace(label, callback, ...) end
        return callback(...)
    end
    function self.schedule(delay, callback, label)
        assert(type(delay) == "number" and delay >= 0 and delay < math.huge, "Invalid game-thread delay")
        assert(type(callback) == "function", "Scheduled callback required")
        next_id = next_id + 1
        local info = debug and debug.getinfo and debug.getinfo(callback, "S") or {}
        local source = (info.source or "?"):gsub("\\", "/")
        local relative = source:match("/Scripts/(.+)$") or source:match("([^/]+)$") or "?"
        jobs[next_id] = {id = next_id, due = elapsed + delay, callback = callback,
            label = label or (relative .. ":" .. tostring(info.linedefined))}
        return next_id
    end
    function self.cancel(id) jobs[id] = nil end
    function self.execute(callback, label)
        if dispatching then return traced(label or "dispatcher.inline", callback) end
        return self.schedule(0, callback, label)
    end
    local function dispatch()
        local ok, now = pcall(traced, "dispatcher.clock", api.now)
        if ok and type(now) == "number" and now == now and math.abs(now) < math.huge then
            if previous_clock then elapsed = elapsed + math.max(0, now - previous_clock) end
            previous_clock = now
        else
            elapsed, previous_clock = elapsed + INTERVAL, nil
        end
        local ready = {}
        for _, job in pairs(jobs) do if job.due <= elapsed then ready[#ready + 1] = job end end
        table.sort(ready, function(a, b) return a.id < b.id end)
        for _, job in ipairs(ready) do
            if jobs[job.id] == job then
                jobs[job.id] = nil
                local success, failure = pcall(traced, "job:" .. job.label, job.callback)
                if not success then api.log("Scheduled rural action stopped: " .. tostring(failure)) end
            end
        end
    end
    function self.pump()
        if dispatching then return end
        dispatching = true
        local ok, failure = pcall(dispatch)
        dispatching = false
        if not ok and last_error ~= tostring(failure) then
            last_error = tostring(failure)
            api.log("Rural dispatcher stopped: " .. last_error)
        elseif ok then last_error = nil end
    end
    function self.start()
        if handle ~= nil then return true end
        assert(type(api.loop) == "function", "UE4SS game-thread loop unavailable; do not enable this candidate")
        handle = api.loop(INTERVAL, self.pump)
        assert(handle ~= nil, "Native game-thread loop registration failed")
        return true
    end
    return self
end
return M

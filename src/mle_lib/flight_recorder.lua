-- Bounded scalar-only breadcrumbs. This module never inspects Unreal objects.
local Json = require("mle_lib.json")
local Recorder = {}
local function scalar_fields(values)
    local result, count = {}, 0
    if values ~= nil and type(values) ~= "table" then return {unsupported_fields = type(values)} end
    for key, value in next, values or {} do
        if type(key) == "string" and count < 16 then
            local kind = type(value)
            if kind == "string" then result[key] = value:sub(1, 256)
            elseif kind == "boolean" or (kind == "number" and value == value and math.abs(value) < math.huge) then
                result[key] = value
            else result[key] = "<" .. kind .. ">" end
            count = count + 1
        end
        if count == 16 then break end
    end
    return result
end
function Recorder.new(config, metadata, api)
    local self = {enabled = config.enabled, sequence = 0, active = {}, history = {}, error = ""}
    local started = api.now()
    local session = tostring(started) .. "_" .. tostring(api.cpu_ms())
    local last_flush, next_token, write_sequence = -math.huge, 0, 0
    local function save(event, force)
        if not self.enabled then return end
        local cpu = api.cpu_ms()
        if not force and cpu - last_flush < config.sample_cpu_ms then return end
        local snapshot = {schema = 1, session = session, session_started_unix = started,
            unix_time = api.now(), cpu_ms = cpu, sequence = self.sequence,
            metadata = metadata, active = self.active, history = self.history}
        local ok, failure = pcall(function()
            -- Alternating snapshots leave a complete prior copy if a process
            -- dies during a write, including on Windows rename semantics.
            api.write("diagnostics_flight_" .. (write_sequence % 2 == 0 and "a" or "b") .. ".json", Json.encode(snapshot) .. "\n")
            write_sequence = write_sequence + 1
            if api.append then api.append("diagnostics_events.jsonl", Json.encode(event) .. "\n", config.max_journal_bytes) end
        end)
        if ok then last_flush = cpu; return true
        elseif self.error ~= tostring(failure) then
            self.error = tostring(failure)
            api.log("Rural diagnostics write failed: " .. self.error)
        end
    end
    function self.event(phase, label, fields, force)
        if not self.enabled then return end
        self.sequence = self.sequence + 1
        local event = {sequence = self.sequence, session = session, unix_time = api.now(),
            cpu_ms = api.cpu_ms(), phase = phase, callback = tostring(label):sub(1, 240), fields = scalar_fields(fields)}
        self.history[#self.history + 1] = event
        while #self.history > config.history_events do table.remove(self.history, 1) end
        return save(event, force)
    end
    function self.checkpoint(label, fields) self.event("checkpoint", label, fields, true) end
    local function invoke(label, callback, force, ...)
        if not self.enabled then return callback(...) end
        next_token = next_token + 1
        local token = next_token
        if #self.active < 32 then self.active[#self.active + 1] = {token = token, callback = label:sub(1, 240)} end
        local begun = self.event("begin", label, nil, force)
        local results = table.pack(pcall(callback, ...))
        for i = #self.active, 1, -1 do
            if self.active[i].token == token then table.remove(self.active, i); break end
        end
        local failure = type(results[2]) == "string" and results[2]:sub(1, 1024) or "<" .. type(results[2]) .. ">"
        self.event(results[1] and "end" or "error", label,
            results[1] and nil or {message = failure}, force or begun or not results[1])
        if not results[1] then error(results[2], 0) end
        return table.unpack(results, 2, results.n)
    end
    function self.run(label, callback, ...) return invoke(label, callback, false, ...) end
    function self.wrap(label, callback, force)
        if not callback then return nil end
        return function(...) return invoke(label, callback, force, ...) end
    end
    function self.status()
        return {enabled = self.enabled, sequence = self.sequence, session = session, error = self.error}
    end
    self.checkpoint("session_start", {version = metadata.version})
    return self
end
return Recorder

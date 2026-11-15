-- Store package state alongside a verified save identity.
local Sidecar = {}
local format = "mle-sidecar-1"

local function key(value)
    return type(value) == "string" and value:match("^[a-z0-9][a-z0-9_.-]*$")
end

local function check_identity(identity)
    assert(type(identity) == "table" and key(identity.namespace) and key(identity.save_id)
        and type(identity.fingerprint) == "string" and identity.fingerprint ~= "",
        "MLE_STATE_IDENTITY State requires a namespace, save ID, and save fingerprint")
end

local function same_slot(left, right)
    return left.namespace == right.namespace and left.save_id == right.save_id
end

local function same_save(left, right)
    return same_slot(left, right) and left.fingerprint == right.fingerprint
end

local function check_schema(schema)
    assert(math.type(schema) == "integer" and schema > 0, "MLE_STATE_SCHEMA Expected a positive state schema")
end

local function companion_path(path)
    assert(key(path) and path:sub(-6) ~= ".state" and not path:find("..", 1, true),
        "MLE_STATE_PATH Expected a relative companion name without separators")
    return path .. ".state"
end

function Sidecar.new(api)
    local fs, encode, decode, checksum = api.fs, api.encode, api.decode, api.checksum
    assert(type(fs) == "table" and type(fs.read) == "function" and type(fs.write) == "function"
        and type(fs.rename) == "function" and type(fs.remove) == "function"
        and type(encode) == "function" and type(decode) == "function" and type(checksum) == "function",
        "Sidecar requires filesystem, codec, and checksum adapters")

    local active, tickets = {}, {}
    local self = {}

    local function serialize(identity, schema, data)
        local payload = encode({namespace = identity.namespace, save_id = identity.save_id,
            fingerprint = identity.fingerprint, schema = schema, data = data})
        assert(type(payload) == "string", "MLE_STATE_CODEC Encode must return bytes")
        local digest = checksum(payload)
        assert(type(digest) == "string" and digest ~= "", "MLE_STATE_CHECKSUM Checksum must return a digest")
        local blob = encode({format = format, checksum = digest, payload = payload})
        assert(type(blob) == "string", "MLE_STATE_CODEC Encode must return bytes")
        return blob
    end

    local function read_record(bytes)
        if bytes == nil then return nil, "missing" end
        local ok, record = pcall(function()
            local envelope = decode(bytes)
            assert(type(envelope) == "table" and envelope.format == format
                and type(envelope.payload) == "string" and type(envelope.checksum) == "string"
                and envelope.checksum == checksum(envelope.payload))
            local data = decode(envelope.payload)
            check_identity(data)
            check_schema(data.schema)
            assert(type(data.data) == "table")
            return data
        end)
        if not ok then return nil, "invalid" end
        return record
    end

    local function verified_write(path, bytes)
        assert(fs.write(path, bytes) == true and fs.read(path) == bytes,
            "MLE_STATE_WRITE Could not verify companion file " .. path)
    end

    function self:prepare(path, identity, schema, data)
        path = companion_path(path)
        check_identity(identity)
        check_schema(schema)
        assert(type(data) == "table", "MLE_STATE_SCHEMA Package state must be a table")
        assert(not active[path], "MLE_STATE_BUSY A save is already prepared for this companion")
        local blob = serialize(identity, schema, data)
        local pending = path .. ".pending"
        verified_write(pending, blob)
        local record = assert(read_record(blob))
        local ticket = {}
        active[path] = ticket
        tickets[ticket] = {path = path, pending = pending, blob = blob, identity = record}
        return ticket
    end

    function self:commit(ticket, observed)
        local entry = assert(tickets[ticket], "MLE_STATE_TICKET Unknown companion save ticket")
        check_identity(observed)
        assert(same_save(entry.identity, observed), "MLE_STATE_MISMATCH Game save completion does not match prepared state")
        assert(fs.read(entry.pending) == entry.blob, "MLE_STATE_WRITE Prepared companion file changed before commit")
        local previous_bytes = fs.read(entry.path)
        local previous = read_record(previous_bytes)
        if previous then
            assert(same_slot(previous, observed), "MLE_STATE_OWNER A different save slot owns this companion")
            local temporary = entry.path .. ".backup.pending"
            verified_write(temporary, previous_bytes)
            assert(fs.rename(temporary, entry.path .. ".backup") == true
                and fs.read(entry.path .. ".backup") == previous_bytes,
                "MLE_STATE_BACKUP Could not publish the last good companion")
        else
            local backup = read_record(fs.read(entry.path .. ".backup"))
            assert(not backup or same_slot(backup, observed), "MLE_STATE_OWNER A different save slot owns this companion")
        end
        assert(fs.rename(entry.pending, entry.path) == true, "MLE_STATE_COMMIT Could not publish the companion")
        active[entry.path], tickets[ticket] = nil, nil
        assert(fs.read(entry.path) == entry.blob, "MLE_STATE_COMMIT Published companion failed readback")
        return true
    end

    function self:discard(ticket)
        local entry = assert(tickets[ticket], "MLE_STATE_TICKET Unknown companion save ticket")
        assert(fs.read(entry.pending) == entry.blob, "MLE_STATE_WRITE Prepared companion file changed")
        assert(fs.remove(entry.pending) == true, "MLE_STATE_WRITE Could not remove prepared companion")
        active[entry.path], tickets[ticket] = nil, nil
    end

    -- For an already observed game save. Use prepare/commit to span the save event.
    function self:save(path, identity, schema, data)
        local ticket = self:prepare(path, identity, schema, data)
        local ok, result = pcall(self.commit, self, ticket, identity)
        if not ok then
            local entry = tickets[ticket]
            if entry then active[entry.path], tickets[ticket] = nil, nil end
            error(result, 0)
        end
        return result
    end

    function self:load(path, identity, schema, migrations)
        path = companion_path(path)
        check_identity(identity)
        check_schema(schema)
        local latest, issue = read_record(fs.read(path))
        local record, recovered = latest, false
        if not latest or not same_save(latest, identity) then
            if latest then issue = "mismatch" end
            local backup = read_record(fs.read(path .. ".backup"))
            if backup and same_save(backup, identity) then record, recovered = backup, true else record = nil end
        end
        local status = {state = recovered and "recovered" or record and "loaded" or issue,
            pending = fs.read(path .. ".pending") ~= nil}
        if not record then return nil, status end
        if record.schema > schema then
            status.state = "newer_schema"
            return nil, status
        end
        local data = record.data
        for version = record.schema, schema - 1 do
            local migrate = migrations and migrations[version]
            if type(migrate) ~= "function" then
                status.state, status.at_schema = "migration_missing", version
                return nil, status
            end
            local ok, next_data = pcall(migrate, data)
            if not ok or type(next_data) ~= "table" then
                status.state, status.at_schema = "migration_failed", version
                return nil, status
            end
            data = next_data
        end
        status.original_schema, status.schema = record.schema, schema
        return data, status
    end
    return self
end

return Sidecar

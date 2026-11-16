-- Shared content ownership and pre-world patch transactions.
local Registry = {}

local function fail(code, message)
    error(code .. " " .. message, 0)
end

local function identifier(value)
    if type(value) ~= "string" then return false end
    local name = value:match("^[a-z0-9][a-z0-9_.-]*:([a-z0-9][a-z0-9_./-]*)$")
    return name and not name:find("//", 1, true) and name:sub(-1) ~= "/"
        and not name:match("/%.%.?/") and not name:match("/%.%.?$")
end

local function array(value)
    if type(value) ~= "table" or getmetatable(value) then return false end
    local count, max = 0, 0
    for key in pairs(value) do
        if math.type(key) ~= "integer" or key < 1 then return false end
        count, max = count + 1, math.max(max, key)
    end
    return count == max
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function typed(kind, value, label)
    if kind == "reference_list" and array(value) then
        local result = {}
        for index, item in ipairs(value) do
            if not identifier(item) then fail("MLE_PATCH_TYPE", label .. " expects namespaced references") end
            result[index] = item
        end
        return result
    end
    if (kind == "number" and finite(value)) or (kind == "integer" and math.type(value) == "integer")
        or (kind == "boolean" and type(value) == "boolean") or (kind == "string" and type(value) == "string") then
        return value
    end
    fail("MLE_PATCH_TYPE", label .. " expects " .. kind)
end

local function equal(left, right)
    if type(left) ~= "table" then return left == right end
    if type(right) ~= "table" or #left ~= #right then return false end
    for index, item in ipairs(left) do
        if item ~= right[index] then return false end
    end
    return true
end

local function target_key(target, field)
    return target.domain .. "[" .. target.id .. "]." .. field
end

local function prepare_patch(options, patch)
    local target = type(patch) == "table" and patch.target
    if type(target) ~= "table" or type(target.domain) ~= "string" or not target.domain:match("^[%w_]+$")
        or (type(target.id) ~= "string" and math.type(target.id) ~= "integer") then
        fail("MLE_PATCH_TARGET", "A patch requires a domain and row ID")
    end
    local row_id = tostring(target.id)
    local field = patch.field
    if not row_id:match("^[%w_.:-]+$") or type(field) ~= "string" or not field:match("^[%w_][%w_.]*$") then
        fail("MLE_PATCH_TARGET", "Invalid patch row or field")
    end
    local domain = options.fields[target.domain]
    local kind = type(domain) == "table" and domain[field]
    if type(kind) ~= "string" then
        fail("MLE_PATCH_FIELD", "Field is outside the profile allowlist: " .. target_key(target, field))
    end

    local op, value = patch.op, patch.value
    local label = target_key(target, field)
    if op == "set" or ((op == "add" or op == "multiply") and (kind == "number" or kind == "integer")) then
        value = typed(kind, value, label)
    elseif (op == "append" or op == "remove") and kind == "reference_list" and identifier(value) then
        -- List operands are keys, independent of list order or array indices.
    else
        fail("MLE_PATCH_OP", label .. " does not support the requested operation")
    end
    return {target = {domain = target.domain, id = row_id}, field = field, op = op, value = value, kind = kind, key = label}
end

local function transform(current, patch)
    local op, value = patch.op, patch.value
    if op == "set" then return value end
    if op == "add" or op == "multiply" then
        -- Integer addition/multiplication must not silently wrap around in Lua.
        local result
        if math.type(current) == "integer" and math.type(value) == "integer" then
            if op == "add" then
                if (value > 0 and current > math.maxinteger - value)
                    or (value < 0 and current < math.mininteger - value) then
                    fail("MLE_PATCH_RANGE", patch.key .. " integer overflow")
                end
                result = current + value
            else
                result = current * value
                if value ~= 0 and (current == math.mininteger and value == -1 or result // value ~= current) then
                    fail("MLE_PATCH_RANGE", patch.key .. " integer overflow")
                end
            end
        else
            result = op == "add" and current + value or current * value
        end
        return typed(patch.kind, result, patch.key)
    end

    local result, found = {}, false
    for _, item in ipairs(current) do
        if item == value then found = true end
        if op ~= "remove" or item ~= value then result[#result + 1] = item end
    end
    if op == "append" and not found then result[#result + 1] = value end
    return result
end

function Registry.new(options)
    assert(type(options) == "table" and type(options.read) == "function" and type(options.write) == "function"
        and type(options.fields) == "table", "Registry requires read, write, and a field allowlist")
    local entries, ordered, baseline, effective = {}, {}, {}, {}
    local state, busy, poisoned = "registration", false, false
    local registry = {}

    local function available()
        if busy then fail("MLE_REGISTRY_BUSY", "A patch transaction is already active") end
        if poisoned then fail("MLE_PATCH_ROLLBACK", "Reload the game to recover the registry after a failed rollback") end
    end

    local function require_reference(reference, owner, excluded)
        if entries[reference] and reference ~= excluded then return end
        if reference ~= excluded and options.exists and options.exists(reference) == true then return end
        fail("MLE_REGISTRY_REFERENCE", owner .. " requires missing reference " .. reference)
    end

    local function validate(excluded)
        local assignments, conflicts = {}, {}
        for _, entry in ipairs(ordered) do
            if entry.id ~= excluded then
                for _, reference in ipairs(entry.references) do require_reference(reference, entry.id, excluded) end
                for _, patch in ipairs(entry.patches) do
                    if patch.kind == "reference_list" then
                        if patch.op == "append" then
                            require_reference(patch.value, entry.id, excluded)
                        elseif patch.op == "set" then
                            for _, reference in ipairs(patch.value) do require_reference(reference, entry.id, excluded) end
                        end
                    end
                    if patch.op == "set" then
                        local assignment = assignments[patch.key]
                        if not assignment then
                            assignment = {value = patch.value, sources = {}}
                            assignments[patch.key] = assignment
                        elseif not equal(assignment.value, patch.value) then
                            conflicts[patch.key] = true
                        end
                        local source = entry.owner .. " (" .. entry.id .. ")"
                        assignment.sources[source] = true
                    end
                end
            end
        end
        local messages = {}
        for key in pairs(conflicts) do
            local sources = {}
            for source in pairs(assignments[key].sources) do sources[#sources + 1] = source end
            table.sort(sources)
            messages[#messages + 1] = key .. " has conflicting assignments from " .. table.concat(sources, ", ")
        end
        if #messages > 0 then
            table.sort(messages)
            fail("MLE_PATCH_CONFLICT", table.concat(messages, "\n"))
        end
    end

    function registry:register(owner, definition)
        available()
        if state ~= "registration" then fail("MLE_REGISTRY_FROZEN", "Definitions must register before freeze") end
        if type(owner) ~= "string" or not owner:match("^[a-z0-9][a-z0-9_.-]*$") or type(definition) ~= "table"
            or not identifier(definition.id) or math.type(definition.schema) ~= "integer" or definition.schema < 1 then
            fail("MLE_REGISTRY_ID", "Definitions require a package owner, namespaced ID, and positive integer schema")
        end
        if entries[definition.id] then
            fail("MLE_REGISTRY_DUPLICATE", definition.id .. " is already owned by " .. entries[definition.id].owner)
        end
        if definition.id:match("^([^:]+):") ~= owner then
            fail("MLE_REGISTRY_OWNER", definition.id .. " does not belong to " .. owner)
        end
        local references, patches = definition.references, definition.patches
        if references == nil then references = {} end
        if patches == nil then patches = {} end
        if not array(references) or not array(patches) then
            fail("MLE_REGISTRY_SCHEMA", "References and patches must be dense arrays")
        end
        local entry = {owner = owner, id = definition.id, schema = definition.schema, references = {}, patches = {}}
        for index, reference in ipairs(references) do
            if not identifier(reference) then fail("MLE_REGISTRY_REFERENCE", entry.id .. " has an invalid reference") end
            entry.references[index] = reference
        end
        for index, patch in ipairs(patches) do entry.patches[index] = prepare_patch(options, patch) end
        entries[entry.id] = entry
        ordered[#ordered + 1] = entry
    end

    function registry:unregister(owner, id)
        available()
        local entry = entries[id]
        if not entry then return false end
        if owner ~= entry.owner then fail("MLE_REGISTRY_OWNER", id .. " is owned by " .. entry.owner) end
        if state == "frozen" then validate(id) end
        for index, candidate in ipairs(ordered) do
            if candidate == entry then table.remove(ordered, index); break end
        end
        entries[id] = nil
        return true
    end

    function registry:freeze()
        available()
        validate()
        state = "frozen"
    end

    local function read(patch)
        return typed(patch.kind, options.read(patch.target, patch.field), patch.key)
    end

    local function write(patch, value)
        local result = options.write(patch.target, patch.field, typed(patch.kind, value, patch.key))
        if result == false or not equal(read(patch), value) then
            fail("MLE_PATCH_WRITE", "Write failed to verify: " .. patch.key)
        end
    end

    local function transaction(restore)
        available()
        if state ~= "frozen" then fail("MLE_REGISTRY_OPEN", "Freeze the registry before applying patches") end
        if options.can_write and options.can_write() ~= true then
            fail("MLE_PATCH_LIFECYCLE", "This game phase does not permit definition writes")
        end
        busy = true
        local changes, enrolled, attempted = {}, {}, 0
        local ok, result = pcall(function()
            if not restore then validate() end
            local fields = {}
            for key, record in pairs(baseline) do
                fields[key] = {patch = record.patch, original = record.original, value = record.original}
            end
            if not restore then
                for _, entry in ipairs(ordered) do
                    for _, patch in ipairs(entry.patches) do
                        local record = fields[patch.key]
                        if not record then
                            local original = read(patch)
                            record = {patch = patch, original = original, value = original}
                            fields[patch.key], enrolled[patch.key] = record, record
                        end
                        record.value = transform(record.value, patch)
                    end
                end
            end

            local keys = {}
            for key in pairs(fields) do keys[#keys + 1] = key end
            table.sort(keys)
            for _, key in ipairs(keys) do
                local record = fields[key]
                local current = read(record.patch)
                local previous = effective[key]
                if previous == nil then previous = record.original end
                if not equal(current, previous) then
                    fail("MLE_PATCH_DRIFT", key .. " changed outside MLE Lib")
                end
                if not equal(current, record.value) then
                    changes[#changes + 1] = {patch = record.patch, previous = current, value = record.value}
                end
            end
            for index, item in ipairs(changes) do
                attempted = index
                write(item.patch, item.value)
            end
            for key, record in pairs(enrolled) do baseline[key] = record end
            if restore then
                baseline, effective = {}, {}
            else
                for key, record in pairs(fields) do effective[key] = record.value end
            end
            return #changes
        end)
        if not ok then
            for index = attempted, 1, -1 do
                local item = changes[index]
                local restored = pcall(function()
                    if not equal(read(item.patch), item.previous) then write(item.patch, item.previous) end
                end)
                if not restored then poisoned = true end
            end
        end
        busy = false
        if not ok then
            if poisoned then fail("MLE_PATCH_ROLLBACK", "Could not restore a partial transaction after " .. tostring(result)) end
            error(result, 0)
        end
        return result
    end

    function registry:apply() return transaction(false) end
    function registry:restore() return transaction(true) end

    function registry:inspect()
        local definitions = {}
        for index, entry in ipairs(ordered) do
            definitions[index] = {id = entry.id, owner = entry.owner, schema = entry.schema, patches = #entry.patches}
        end
        return {state = state, rollback_failed = poisoned, definitions = definitions}
    end
    return registry
end

return Registry

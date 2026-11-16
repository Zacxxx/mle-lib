-- Persist namespaced identities before writing native content. Retired IDs remain reserved.
local Codec = require("mle_lib.state_codec")
local Ids = {}
function Ids.new(api)
    local domains = api.domains or {"buildings", "parts", "upgrades"}
    local function load()
        local persisted = api.read()
        local ledger = persisted and Codec.decode(persisted) or {schema = 1}
        if not persisted then
            for _, domain in ipairs(domains) do ledger[domain] = {} end
        end
        assert(ledger.schema == 1, "Unsupported building identity ledger schema")
        local used = {}
        for _, domain in ipairs(domains) do
            assert(type(ledger[domain]) == "table", "Invalid building identity ledger")
            used[domain] = {}
            for key, id in pairs(ledger[domain]) do
                assert(type(key) == "string" and key:match("^[a-z][a-z0-9_.%-]*:[a-z][a-z0-9_]*$") and math.type(id) == "integer" and id > 0 and id <= 2147483647
                    and not used[domain][id], "Corrupt building identity ledger")
                used[domain][id] = key
            end
        end
        return ledger, used
    end
    load()
    local self = {}
    function self.reserve(domain, key, preferred)
        local ledger, used = load()
        assert(used[domain] and type(key) == "string" and key:match("^[a-z][a-z0-9_.%-]*:[a-z][a-z0-9_]*$"), "Invalid identity request")
        local existing = ledger[domain][key]
        if existing then assert(not preferred or preferred == existing, "Saved identity cannot be remapped"); return existing end
        local limit = api.maximums and api.maximums[domain] or 2147483647
        local minimum = api.minimums and api.minimums[domain]
        assert(preferred or minimum, "No automatic identity range configured")
        local id = preferred or (minimum + 1)
        if not preferred then
            assert(math.type(limit) == "integer" and id <= limit and limit <= 2147483647, "Invalid automatic identity range")
        end
        assert(math.type(id) == "integer" and id > 0 and id <= 2147483647, "Invalid preferred identity")
        if preferred then
            assert(not used[domain][id], "Preferred identity reserved by another building")
            assert(not api.occupied(domain, id) or (api.owns and api.owns(domain, id, key)), "Preferred native identity occupied")
        else
            while used[domain][id] or api.occupied(domain, id) do
                id = id + 1
                assert(id <= limit, "Identity space exhausted")
            end
        end
        ledger[domain][key], used[domain][id] = id, key
        api.write(Codec.encode(ledger))
        assert(api.read() == Codec.encode(ledger), "Building identity persistence readback failed")
        return id
    end
    return self
end
return Ids

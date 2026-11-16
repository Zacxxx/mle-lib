-- Persist namespaced identities before writing native content. Retired IDs remain reserved.
local Codec = require("mle_lib.state_codec")
local Ids = {}
function Ids.new(api)
    local function load()
        local persisted = api.read()
        local ledger = persisted and Codec.decode(persisted) or {schema = 1, buildings = {}, parts = {}, upgrades = {}}
        assert(ledger.schema == 1, "Unsupported building identity ledger schema")
        local used = {}
        for _, domain in ipairs({"buildings", "parts", "upgrades"}) do
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
        local id = preferred or (api.minimums[domain] + 1)
        assert(math.type(id) == "integer" and id > 0 and id <= 2147483647, "Invalid preferred identity")
        if preferred then
            assert(not used[domain][id], "Preferred identity reserved by another building")
            assert(not api.occupied(domain, id) or (api.owns and api.owns(domain, id, key)), "Preferred native identity occupied")
        else
            while used[domain][id] or api.occupied(domain, id) do
                id = id + 1
                assert(id <= 2147483647, "Identity space exhausted")
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

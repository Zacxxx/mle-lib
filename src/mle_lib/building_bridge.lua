-- Exact-build native transport. Run synchronously on the game thread.
local Bridge = {}
function Bridge.open(directory, find_object, before_world_load)
    local file = assert(io.open(directory .. "/Native/buildings_name.txt", "r"), "MLE building bridge missing")
    local name = file:read("*l"); file:close()
    assert(name and name:match("^mle_buildings_%x+%.dll$"), "Invalid MLE building bridge name")
    local sequence, busy = 0, false
    local function command(channel, symbol, body)
        assert(before_world_load(), "Native building registration requires the main menu")
        assert(not busy, "Building bridge request is already active")
        busy = true
        local ok, result = pcall(function()
            sequence = sequence + 1
            local nonce = os.time() * 10000 + sequence
            local request_path = directory .. "/Control/" .. channel .. ".request"
            local response_path = directory .. "/Control/" .. channel .. ".response"
            local request = assert(io.open(request_path, "w"))
            local written, reason = request:write(body(nonce)); request:close(); assert(written, reason)
            os.remove(response_path)
            local run = assert(package.loadlib(directory .. "/Native/" .. name, symbol))
            run()
            local response = assert(io.open(response_path, "r"), "Native building bridge did not respond")
            local value = response:read("*a"); response:close()
            local returned, token = value:match("^OK (%d+) ?(%d*)\r?\n$")
            assert(tonumber(returned) == nonce, value)
            return tonumber(token)
        end)
        busy = false
        if not ok then error(result, 0) end
        return result
    end
    local self = {}
    function self.verify()
        assert(command("building-native", "mle_building_check_profile", function(nonce)
            return string.format("MLE_BUILDING_PROFILE_1 %.0f\n", nonce)
        end) == 1, "Native building profile verification failed")
    end
    function self.paths(kind, entries, transaction)
        assert(math.type(kind) == "integer" and kind >= 0 and kind <= 4, "Unknown native path kind")
        assert(#entries > 0 and #entries <= 4096, "Unsupported native path count")
        local token = command("building-native", "mle_building_paths", function(nonce)
            local lines = {string.format("MLE_BUILDING_PATHS_1 %.0f %d %d", nonce, kind, #entries)}
            for _, entry in ipairs(entries) do
                assert(entry.row > 0 and entry.label > 0 and ((entry.path and entry.path > 0) or (entry.package > 0 and entry.asset > 0)),
                    "Invalid native path descriptor")
                lines[#lines + 1] = string.format("%.0f %d %.0f %d %d", entry.row, entry.label, entry.path or 0, entry.package or 0, entry.asset or 0)
            end
            return table.concat(lines, "\n") .. "\n"
        end)
        assert(token and token > 0, "Native path snapshot missing")
        transaction.defer(function()
            command("building-native", "mle_building_paths", function(nonce)
                return string.format("MLE_BUILDING_UNDO_1 %.0f %.0f\n", nonce, token)
            end)
        end)
    end
    function self.upgrade(entry, transaction)
        local object = find_object("/Script/ManorLords.SMBuildingMaster:BeginUpgrade")
        assert(object and object:IsValid(), "Native BeginUpgrade unavailable")
        local created = command("building-upgrade", "mle_building_upgrade_bind", function(nonce)
            return string.format("MLE_BUILDING_UPGRADE_1 %.0f %.0f %d %d %d %.0f %d %.0f %d %.0f\n",
                nonce, object:GetAddress(), entry.source, entry.target, entry.action,
                entry.source_row, entry.source_label, entry.target_row, entry.target_label, entry.action_row)
        end)
        if created == 0 then return end
        assert(created == 1, "Native upgrade binding receipt missing")
        transaction.defer(function()
            command("building-native", "mle_building_upgrade_unbind", function(nonce)
                return string.format("MLE_UPGRADE_UNBIND_1 %.0f %d %d\n", nonce, entry.source, entry.action)
            end)
        end)
    end
    return self
end
return Bridge

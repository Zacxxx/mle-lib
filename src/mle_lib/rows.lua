-- Track rows inserted through the transaction, including writes that fail after insertion.
local Rows = {}

function Rows.run(callback)
    local undo, wrappers = {}, {}
    local transaction = {}

    function transaction.defer(rollback) undo[#undo + 1] = rollback end
    function transaction.table(data)
        if wrappers[data] then return wrappers[data] end
        local adapter = {
            IsValid = function() return data:IsValid() end,
            AddRow = function(_, id, value)
                if not data:FindRow(id) then
                    transaction.defer(function()
                        if data:FindRow(id) then data:RemoveRow(id) end
                        assert(not data:FindRow(id), "Rollback left row " .. tostring(id))
                    end)
                end
                return data:AddRow(id, value)
            end,
            FindRow = function(_, id) return data:FindRow(id) end,
            GetRowNames = function() return data:GetRowNames() end,
            RemoveRow = function(_, id) return data:RemoveRow(id) end,
            GetFullName = function() return data:GetFullName() end,
        }
        setmetatable(adapter, {__index = function(_, field) return data[field] end})
        wrappers[data] = adapter
        return adapter
    end

    local ok, result = pcall(callback, transaction)
    if ok then return result end
    local failures = {}
    for index = #undo, 1, -1 do
        local restored, reason = pcall(undo[index])
        if not restored then failures[#failures + 1] = tostring(reason) end
    end
    local message = tostring(result)
    if #failures > 0 then message = message .. " (rollback failed: " .. table.concat(failures, ", ") .. ")" end
    error(message, 0)
end

return Rows

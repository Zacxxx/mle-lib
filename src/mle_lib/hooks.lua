-- Share each reflected hook within a host and keep subscriber lifetimes separate.
local Hooks = {}

function Hooks.new(register)
    local targets, sequence = {}, 0
    local broker = {}
    local function dispatch(target, phase, ...)
        local result
        for _, subscriber in ipairs({table.unpack(target.subscribers)}) do
            local callback = subscriber[phase]
            if subscriber.active and callback then
                local value = callback(...)
                if value ~= nil then
                    assert(result == nil or result == value, "Conflicting reflected hook return values")
                    result = value
                end
            end
        end
        return result
    end

    function broker.targets()
        local paths = {}
        for path in pairs(targets) do paths[#paths + 1] = path end
        table.sort(paths)
        return paths
    end

    function broker.add(path, before, after)
        local target = targets[path]
        if not target then
            target = {subscribers = {}}
            local first = function(...) return dispatch(target, "before", ...) end
            if path:match("^/Script/") then
                register(path, first, function(...) return dispatch(target, "after", ...) end)
            else
                register(path, first)
            end
            targets[path] = target
        end
        sequence = sequence + 1
        local subscriber = {id = sequence, active = true, before = before, after = after}
        target.subscribers[#target.subscribers + 1] = subscriber
        return function()
            subscriber.active, subscriber.before, subscriber.after = false, nil, nil
        end
    end
    return broker
end
return Hooks

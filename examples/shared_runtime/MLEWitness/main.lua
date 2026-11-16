-- Observe the same save-request hook as Ruralities and persist an independent counter.
return function(context)
    local saves = 0
    context.services.register({id = context.id .. ":save_counter", schema = 1})
    context.services.hooks.add("/Script/ManorLords.PawnCPP:requestSaveFile", function()
        saves = saves + 1
    end)
    context.services.save_state(function()
        return {save_requests = saves}
    end, function(state, status)
        saves = 0
        if state then
            assert(math.type(state.save_requests) == "integer" and state.save_requests >= 0,
                "Invalid witness save counter")
            saves = state.save_requests
        end
        print("[MLEWitness] " .. status .. " save_requests=" .. saves .. "\n")
    end)
end

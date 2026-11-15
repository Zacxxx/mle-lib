return function(context)
    context:on("world.ready", function()
        context.services.events[#context.services.events + 1] = context.id
    end)
end

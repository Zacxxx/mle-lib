return function(context)
    local registry = context.services.registry
    registry:register(context.id, {id = context.id .. ":workers", schema = 1, patches = {{
        target = {domain = "buildings", id = "warehouse"}, field = "workers", op = "set", value = 3,
    }}})
    context:on("world.ready", function()
        context.services.events[#context.services.events + 1] = context.id
    end, 5)
end

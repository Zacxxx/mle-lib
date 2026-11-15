return function(context)
    local registry = context.services.registry
    registry:register(context.id, {id = context.id .. ":capacity", schema = 1, patches = {{
        target = {domain = "buildings", id = "warehouse"}, field = "storage", op = "add", value = 25,
    }}})
end

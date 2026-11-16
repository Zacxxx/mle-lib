-- The host supplies plot placement, yard rules, and widget rendering for its game build.
return function(buildings, host)
    buildings.register_building_mixin({
        id = "example.mod:workshop_storage",
        defaults = {
            families = 2,
            fields = {storageLimitGeneric = 150, needsRoad = true},
        },
    })

    buildings.register_building_placement({
        id = "example.mod:plot",
        validate = function(options, definition)
            return host.supports_plot(definition, options)
        end,
        begin = function(id, context, options)
            return host.begin_plot(id, context, options)
        end,
    })

    buildings.register_building_yard({
        id = "example.mod:improvements",
        list = function(context, _, options)
            return host.list_improvements(context.actor, options)
        end,
        place = function(context, _, id, options)
            return host.place_improvement(context.actor, id, options)
        end,
        mount = function(screen, menu)
            return host.mount_improvements(screen, menu)
        end,
    })

    buildings.register_building_template({
        id = "example.mod:workshop_with_yard",
        native_base = 72,
        mixins = {"example.mod:workshop_storage"},
        placement = {id = "example.mod:plot", options = {road_snap = true}},
        behavior = {id = "mle:native_storage"},
        interface = {
            id = "mle:native_storage_panel",
            sections = {"workers", "storage", "accepted_goods"},
        },
        yard = {
            id = "example.mod:improvements",
            title = {en_US = "Yard Improvements", fr_FR = "Aménagements de la cour"},
            options = {allowed = {"example.mod:drying_rack"}},
        },
    })
end

-- render(screen, model, select_recipe) builds widgets and returns a cleanup callback.
return function(buildings, render)
    buildings.register_building_behavior({
        id = "example.mod:recipe_choice",
        status = {recipes = true, selected = true},
        create = function(context, saved)
            local recipes = assert(context.options.recipes)
            local selected = saved and saved.selected or recipes[1]
            for _, recipe in ipairs(recipes) do
                if recipe == selected then return {recipes = recipes, selected = selected} end
            end
            error("Unknown saved recipe")
        end,
        read = function(_, state) return state end,
        save = function(_, state) return {selected = state.selected} end,
        actions = {
            select_recipe = function(_, state, selected)
                for _, recipe in ipairs(state.recipes) do
                    if recipe == selected then state.selected = recipe; return end
                end
                error("Unknown recipe")
            end,
        },
    })
    buildings.register_building_panel({
        id = "example.mod:recipe_panel",
        sections = {recipe_picker = {status = {"recipes", "selected"}, actions = {"select_recipe"}}},
        mount = function(screen, ui)
            return render(screen, ui.get_status(), function(recipe)
                ui.invoke("select_recipe", recipe)
                return ui.get_status()
            end)
        end,
    })
    buildings.register_building_template({
        id = "example.mod:recipe_workshop",
        native_base = 72,
        behavior = {id = "example.mod:recipe_choice", options = {recipes = {"boards", "beams"}}},
        interface = {id = "example.mod:recipe_panel", sections = {"recipe_picker"}},
        defaults = {families = 2},
    })
end

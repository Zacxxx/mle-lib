-- Call during the main-menu registration phase. Persist the numeric IDs yourself.
return function(items_table, before_world_load, ids)
    local content = require("mle_lib.items").new({items = items_table, before_world_load = before_world_load})
    content.register_item({
        id = "example.production:rough_board",
        numeric_id = ids.rough_board,
        template_id = 17,
        name = "Rough Board",
        storage = 0,
        category = 0,
        subcategory = 0,
        crafting_tool = 0,
        tradeable = false,
    })
    content.register_recipe({
        id = "example.production:cut_board",
        numeric_id = ids.cut_board,
        template_id = 357,
        crafting_template_id = 357,
        name = "Example_Recipe_CutBoard",
        inputs = {{item = 17, amount = 2}},
        outputs = {{item = "example.production:rough_board", amount = 1}},
    })
    return content.apply()
end

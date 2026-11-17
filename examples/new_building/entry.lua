-- Activated by the independent MLE Lib host at the main menu, on the game thread.
-- This is a storage building; changing its display name does not make it housing.
return function(context)
    local buildings = context.services.new_building_runtime({asset_root = "/Game/ExampleBuilding/"})
    buildings.register_building({
        schema = 1, owner = "example.building", id = "example.building:example_house",
        template_id = 72, construction_part_id = 19001,
        assets = {
            assembly = "/Game/ExampleBuilding/BP_ExampleHouse_Assembly.BP_ExampleHouse_Assembly_C",
            construction = "/Game/ExampleBuilding/BP_ExampleHouse_Construction.BP_ExampleHouse_Construction_C",
            main_mesh = "/Game/ExampleBuilding/Meshes/SM_ExampleHouse_Foundation.SM_ExampleHouse_Foundation",
            preview = "/Game/ExampleBuilding/Meshes/SM_ExampleHouse.SM_ExampleHouse",
        },
        presentation = {
            name = {en_US = "Example House", fr_FR = "Maison exemple"},
            description = {en_US = "Tutorial supply shed. Its keepers collect and store supplies.",
                fr_FR = "Remise de démonstration. Ses employés collectent et stockent des provisions."},
            card = "/Game/ExampleBuilding/UI/T_ExampleHouse.T_ExampleHouse",
            panel = "/Game/ExampleBuilding/UI/T_ExampleHouse.T_ExampleHouse",
            icon = "/Game/ExampleBuilding/UI/T_ExampleHouse.T_ExampleHouse",
            worker_role = {en_US = "Supply Keeper", fr_FR = "Intendant"},
        },
        construction_goods = {{Type = 16, amt = 2}},
        families = 2,
        fields = {storageLimitGeneric = 100, bVisibleInUi = true, needsRoad = true},
    })
    buildings.apply()
end

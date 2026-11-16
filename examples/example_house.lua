-- Copy this entry into a UE4SS mod with the declared cooked assets and PNGs.
-- Registration must be scheduled on the game thread while at the main menu.
local Example = {}
function Example.register(directory)
    local buildings = require("mle_lib.buildings").new({directory = directory, asset_root = "/Game/ExampleMod/"})
    buildings.register_building({schema = 1, owner = "example.mod", id = "example.mod:example_house",
        template_id = 72, construction_part_id = 19001,
        assets = {
            assembly = "/Game/ExampleMod/Buildings/BP_ExampleHouse.BP_ExampleHouse_C",
            construction = "/Game/ExampleMod/Buildings/BP_ExampleHouseConstruction.BP_ExampleHouseConstruction_C",
            preview = "/Game/ExampleMod/Buildings/SM_ExampleHouse.SM_ExampleHouse",
        },
        presentation = {name = {en_US = "Example House", fr_FR = "Maison exemple"},
            description = {en_US = "Stores supplies.", fr_FR = "Stocke des provisions."},
            card = "example_house_card", panel = "example_house_panel",
            icon = "/Game/ExampleMod/UI/T_ExampleHouse.T_ExampleHouse",
            worker_role = {en_US = "House Keeper", fr_FR = "Intendant"}},
        fields = {storageLimitGeneric = 100, bVisibleInUi = true},
    })
    buildings.apply()
    return buildings
end
return Example

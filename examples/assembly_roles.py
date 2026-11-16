"""Run in Unreal Editor Python with the SDK Tools directory on sys.path.

Replace the three mesh references with your authored assets before execution.
Use the resulting class as register_building assets.assembly and the foundation
mesh as assets.main_mesh. assets.preview remains the complete placement mesh.
"""
from mle_authoring.unreal_assembly import author_assembly


def build_example_house():
    return author_assembly({
        "asset": "/Game/ExampleMod/House/BP_House_Assembly.BP_House_Assembly_C",
        "construction_part_id": 19001,
        "components": [
            {"name": "Foundation", "role": "main", "mesh": "/Game/ExampleMod/House/SM_Foundation.SM_Foundation"},
            {"name": "BarnVisual_Roof", "role": "visual", "mesh": "/Game/ExampleMod/House/SM_Roof.SM_Roof"},
            {"name": "GardenBarrel", "role": "decoration", "mesh": "/Game/ExampleMod/House/SM_Barrel.SM_Barrel"},
        ],
    })

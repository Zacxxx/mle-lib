"""Owned asset identities shared by the tutorial authoring scripts."""
NAMESPACE = "/Game/ExampleBuilding"
PART_ID = 19001  # Tutorial reservation only: check the target install before using it.
ASSEMBLY = NAMESPACE + "/BP_ExampleHouse_Assembly.BP_ExampleHouse_Assembly_C"
CONSTRUCTION = NAMESPACE + "/BP_ExampleHouse_Construction.BP_ExampleHouse_Construction_C"
PREVIEW = NAMESPACE + "/Meshes/SM_ExampleHouse.SM_ExampleHouse"
PIECES = [
    {"name": "Foundation", "tags": ["foundation"], "role": "main"},
    {"name": "Frame", "tags": [], "role": "visual"},
    {"name": "Roof", "tags": ["final"], "role": "visual"},
]


def mesh(name):
    return NAMESPACE + "/Meshes/SM_ExampleHouse_" + name + ".SM_ExampleHouse_" + name


def assembly():
    return {"asset": ASSEMBLY, "construction_part_id": PART_ID,
            "components": [{"name": piece["name"], "role": piece["role"], "mesh": mesh(piece["name"])}
                           for piece in PIECES]}

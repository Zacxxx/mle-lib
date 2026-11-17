"""Run in UE 5.5.4 Python after build.py prepare; authors only owned example assets."""
import json
import os
from pathlib import Path
import sys

import unreal

LIBRARY = Path(os.environ["MLE_LIB_ROOT"])
EXAMPLE = LIBRARY / "examples/new_building"
OUTPUT = LIBRARY / "build/new_building"
sys.path[:0] = [str(LIBRARY / "src"), str(EXAMPLE), str(EXAMPLE / "scripts")]
from mle_authoring.unreal_assembly import author_assembly
from mle_authoring.render_profile import verify_render_environment
from building import NAMESPACE, ASSEMBLY, CONSTRUCTION, PIECES, assembly
from construction import stage_parent, construction_child

ASSETS = unreal.EditorAssetLibrary
TOOLS = unreal.AssetToolsHelpers.get_asset_tools()
EDIT = unreal.MaterialEditingLibrary


def environment():
    profile = json.loads((LIBRARY / "config/render_profiles/manor_lords_0_8_117.json").read_text())
    result = verify_render_environment(profile, unreal.SystemLibrary.get_engine_version(),
        {key: unreal.SystemLibrary.get_console_variable_int_value(key) for key in profile["cvars"]})
    result["host_platform"] = sys.platform
    result["gameplay_verified"] = False
    return result


def import_asset(source, folder, name, options=None):
    task = unreal.AssetImportTask()
    task.filename, task.destination_path, task.destination_name = str(source), folder, name
    task.automated, task.replace_existing, task.replace_existing_settings, task.save = True, True, True, True
    if options:
        task.options, task.factory = options, unreal.FbxFactory()
    TOOLS.import_asset_tasks([task])
    result = task.get_objects()
    assert len(result) == 1, f"Expected one imported asset: {source}"
    return result[0]


def material(name, texture=None):
    path = NAMESPACE + "/Materials/" + name
    value = unreal.load_asset(path) if ASSETS.does_asset_exist(path) else TOOLS.create_asset(
        name, NAMESPACE + "/Materials", unreal.Material, unreal.MaterialFactoryNew())
    EDIT.delete_all_material_expressions(value)
    value.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_DEFAULT_LIT)
    if texture:
        colour = EDIT.create_material_expression(value, unreal.MaterialExpressionTextureSampleParameter2D)
        colour.set_editor_property("parameter_name", "BaseColor")
        colour.set_editor_property("texture", texture)
        colour.set_editor_property("sampler_type", unreal.MaterialSamplerType.SAMPLERTYPE_COLOR)
        output = "RGB"
    else:
        colour = EDIT.create_material_expression(value, unreal.MaterialExpressionConstant3Vector)
        colour.set_editor_property("constant", unreal.LinearColor(.22, .23, .24, 1))
        output = ""
    assert EDIT.connect_material_property(colour, output, unreal.MaterialProperty.MP_BASE_COLOR)
    for prop, amount in ((unreal.MaterialProperty.MP_ROUGHNESS, .85), (unreal.MaterialProperty.MP_METALLIC, 0),
                         (unreal.MaterialProperty.MP_SPECULAR, .32)):
        node = EDIT.create_material_expression(value, unreal.MaterialExpressionConstant)
        node.set_editor_property("r", amount)
        assert EDIT.connect_material_property(node, "", prop)
    EDIT.recompile_material(value)
    assert ASSETS.save_loaded_asset(value, only_if_is_dirty=False)
    return value


def main():
    receipt = environment()
    if os.environ.get("MLE_VERIFY_ONLY") == "1":
        (OUTPUT / "render-profile.json").write_text(json.dumps(receipt, indent=4) + "\n")
        return
    wood = import_asset(EXAMPLE / "assets/ExampleWood.png", NAMESPACE + "/Textures", "ExampleWood")
    wood.set_editor_property("srgb", True)
    wood.set_editor_property("never_stream", True)
    wood.set_editor_property("mip_gen_settings", unreal.TextureMipGenSettings.TMGS_SIMPLE_AVERAGE)
    assert ASSETS.save_loaded_asset(wood)
    art = import_asset(EXAMPLE / "assets/ExampleHouse.png", NAMESPACE + "/UI", "T_ExampleHouse")
    art.set_editor_property("srgb", True)
    art.set_editor_property("never_stream", True)
    assert ASSETS.save_loaded_asset(art)
    materials = {"TutorialWood": material("M_ExampleWood", wood), "TutorialStone": material("M_ExampleStone")}
    subsystem = unreal.get_default_object(unreal.StaticMeshEditorSubsystem)
    for name in ["SM_ExampleHouse"] + ["SM_ExampleHouse_" + piece["name"] for piece in PIECES]:
        options = unreal.FbxImportUI()
        options.set_editor_property("import_mesh", True)
        options.set_editor_property("import_as_skeletal", False)
        options.set_editor_property("import_materials", False)
        options.set_editor_property("import_textures", False)
        options.set_editor_property("automated_import_should_detect_type", False)
        options.set_editor_property("mesh_type_to_import", unreal.FBXImportType.FBXIT_STATIC_MESH)
        settings = options.static_mesh_import_data
        settings.set_editor_property("combine_meshes", True)
        settings.set_editor_property("auto_generate_collision", False)
        settings.set_editor_property("one_convex_hull_per_ucx", True)
        settings.set_editor_property("convert_scene", True)
        settings.set_editor_property("convert_scene_unit", True)
        settings.set_editor_property("normal_import_method", unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS_AND_TANGENTS)
        value = import_asset(EXAMPLE / "assets" / (name + ".fbx"), NAMESPACE + "/Meshes", name, options)
        assert isinstance(value, unreal.StaticMesh)
        for index, slot in enumerate(value.get_editor_property("static_materials")):
            slot_name = str(slot.get_editor_property("material_slot_name"))
            assert slot_name in materials, f"Unexpected FBX material slot {slot_name}"
            value.set_material(index, materials[slot_name])
        build = subsystem.get_lod_build_settings(value, 0)
        for key, setting in {"recompute_normals": False, "recompute_tangents": False,
                             "use_high_precision_tangent_basis": True, "use_full_precision_u_vs": True}.items():
            build.set_editor_property(key, setting)
        subsystem.set_lod_build_settings(value, 0, build)
        assert ASSETS.save_loaded_asset(value, only_if_is_dirty=False)
    author_assembly(assembly())
    pieces = [{"name": "SM_ExampleHouse_" + piece["name"], "tags": piece["tags"], "location_cm": [0, 0, 0]}
              for piece in PIECES]
    child = construction_child(CONSTRUCTION.rsplit(".", 1)[0], pieces, NAMESPACE, stage_parent(),
                               unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem))
    assert child == CONSTRUCTION
    receipt.update(assembly=ASSEMBLY, construction=child, exclude_from_pak=["/Game/CPP_BP/ConstructionBlueprints/ConstructionBP"])
    (OUTPUT / "authoring.json").write_text(json.dumps(receipt, indent=4) + "\n")


if __name__ == "__main__":
    main()

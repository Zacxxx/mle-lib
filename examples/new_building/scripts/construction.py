"""Tutorial construction authoring, using the proven owned Hay Barn child pattern.

The native parent is an editor-only stand-in; never include it in a mod pak.
"""
import json
import os
from pathlib import Path

import unreal


ROOT = Path(__file__).resolve().parents[1]
STUB_FOLDER = "/Game/CPP_BP/ConstructionBlueprints"
STUB_NAME = "ConstructionBP"
STUB_MARKER = "MLETutorialEditorStub"
STUB_VALUE = "Manor Lords 0.8.117 import path only"
ASSETS = unreal.EditorAssetLibrary
SUBOBJECTS = unreal.SubobjectDataBlueprintFunctionLibrary


def blueprint_asset(folder, name, parent):
    path = f"{folder}/{name}"
    if ASSETS.does_asset_exist(path):
        blueprint = unreal.load_asset(path)
        assert isinstance(blueprint, unreal.Blueprint)
        assert unreal.MathLibrary.class_is_child_of(blueprint.generated_class(), parent), f"Unexpected parent class at {path}"
        return blueprint, False
    factory = unreal.BlueprintFactory()
    factory.set_editor_property("parent_class", parent)
    tools = unreal.AssetToolsHelpers.get_asset_tools()
    blueprint = tools.create_asset(name, folder, unreal.Blueprint, factory)
    assert isinstance(blueprint, unreal.Blueprint), f"Could not create Blueprint {path}"
    return blueprint, True


def stage_parent():
    stub, created = blueprint_asset(STUB_FOLDER, STUB_NAME, unreal.Actor.static_class())
    if created:
        ASSETS.set_metadata_tag(stub, unreal.Name(STUB_MARKER), STUB_VALUE)
        unreal.BlueprintEditorLibrary.compile_blueprint(stub)
        assert ASSETS.save_loaded_asset(stub, only_if_is_dirty=False)
    assert ASSETS.get_metadata_tag(stub, unreal.Name(STUB_MARKER)) == STUB_VALUE, (
        "Refusing to reuse an existing ConstructionBP asset without the MLE tutorial authoring marker"
    )
    parent = stub.generated_class()
    assert parent.get_path_name() == f"{STUB_FOLDER}/{STUB_NAME}.{STUB_NAME}_C"
    return parent


def piece_handles(blueprint, subsystem):
    result = []
    for handle in subsystem.k2_gather_subobject_data_for_blueprint(blueprint):
        data = SUBOBJECTS.get_data(handle)
        obj = SUBOBJECTS.get_object_for_blueprint(data, blueprint) or SUBOBJECTS.get_object(data)
        if isinstance(obj, unreal.SceneComponent):
            result.append((handle, data, obj))
    return result


def construction_child(path, pieces, asset_root, parent, subsystem):
    folder, name = path.rsplit("/", 1)
    blueprint, _ = blueprint_asset(folder, name, parent)
    handles = subsystem.k2_gather_subobject_data_for_blueprint(blueprint)
    actor = next(handle for handle in handles if SUBOBJECTS.is_root_actor(SUBOBJECTS.get_data(handle)))
    existing = piece_handles(blueprint, subsystem)
    expected = {piece["name"] for piece in pieces}
    for handle, data, component in existing:
        if isinstance(component, unreal.StaticMeshComponent) and str(SUBOBJECTS.get_variable_name(data)) not in expected:
            assert subsystem.delete_subobject(actor, handle, blueprint) == 1, "Could not retire the previous frame component"
    for piece in pieces:
        existing = piece_handles(blueprint, subsystem)
        candidates = [(handle, component) for handle, data, component in existing
                      if str(SUBOBJECTS.get_variable_name(data)) == piece["name"]]
        if candidates:
            assert len(candidates) == 1
            handle, component = candidates[0]
        else:
            handle, reason = subsystem.add_new_subobject(unreal.AddNewSubobjectParams(
                parent_handle=actor, new_class=unreal.StaticMeshComponent.static_class(), blueprint_context=blueprint))
            assert SUBOBJECTS.is_handle_valid(handle), str(reason)
            subsystem.rename_subobject_member_variable(blueprint, handle, unreal.Name(piece["name"]))
            component = SUBOBJECTS.get_object_for_blueprint(SUBOBJECTS.get_data(handle), blueprint)
        mesh = unreal.load_asset(f"{asset_root}/Meshes/{piece['name']}")
        assert isinstance(mesh, unreal.StaticMesh)
        component.set_editor_property("static_mesh", mesh)
        component.set_editor_property("relative_location", unreal.Vector(*piece["location_cm"]))
        component.set_editor_property("component_tags", [unreal.Name(tag) for tag in piece["tags"]])
        component.set_editor_property("mobility", unreal.ComponentMobility.MOVABLE)
        component.set_editor_property("cast_shadow", True)
        component.set_editor_property("can_ever_affect_navigation", False)
        component.set_collision_profile_name("NoCollision")
    unreal.BlueprintEditorLibrary.compile_blueprint(blueprint)
    assert ASSETS.save_loaded_asset(blueprint, only_if_is_dirty=False)
    components = {str(SUBOBJECTS.get_variable_name(data)): component
                  for _, data, component in piece_handles(blueprint, subsystem)
                  if isinstance(component, unreal.StaticMeshComponent)}
    assert set(components) == expected, f"Unexpected geometry in {path}"
    for piece in pieces:
        component = components[piece["name"]]
        assert component.get_editor_property("static_mesh").get_path_name() == (
            f"{asset_root}/Meshes/{piece['name']}.{piece['name']}")
        assert list(map(str, component.get_editor_property("component_tags"))) == piece["tags"]
        location = component.get_editor_property("relative_location")
        assert all(abs(value - expected) < .001 for value, expected in zip(
            (location.x, location.y, location.z), piece["location_cm"]))
        assert str(component.get_collision_profile_name()) == "NoCollision"
        assert not component.get_editor_property("override_materials")
    assert unreal.MathLibrary.class_is_child_of(blueprint.generated_class(), parent)
    return blueprint.generated_class().get_path_name()

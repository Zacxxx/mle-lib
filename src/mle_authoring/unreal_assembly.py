"""Author a validated MLE assembly inside Unreal Editor 5.5 Python."""
from .assembly import compile_assembly


def _components(unreal, blueprint, subsystem):
    library = unreal.SubobjectDataBlueprintFunctionLibrary
    result = {}
    for handle in subsystem.k2_gather_subobject_data_for_blueprint(blueprint):
        data = library.get_data(handle)
        component = library.get_object_for_blueprint(data, blueprint)
        if isinstance(component, unreal.StaticMeshComponent):
            result[str(library.get_variable_name(data))] = (handle, component)
    return result


def author_assembly(definition, mesh_loader=None):
    """Compile logical roles, migrate declared aliases, save and verify a Blueprint.

    mesh_loader(path, native) may resolve game-only mesh imports in an isolated
    authoring project. It must return a StaticMesh at the exact requested path.
    """
    plan = compile_assembly(definition)
    import unreal

    assets = unreal.EditorAssetLibrary
    subobjects = unreal.SubobjectDataBlueprintFunctionLibrary
    subsystem = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
    if not subsystem:
        raise RuntimeError("Unreal subobject authoring subsystem is unavailable")
    # Resolve all mesh inputs before touching the Blueprint.
    meshes = {}
    for name, spec in plan["components"].items():
        mesh = mesh_loader(spec["asset"], spec["native"]) if mesh_loader else unreal.load_asset(spec["asset"])
        if not isinstance(mesh, unreal.StaticMesh) or mesh.get_path_name() != spec["asset"]:
            raise ValueError(f"Assembly mesh is unavailable or differs: {spec['asset']}")
        meshes[name] = mesh
    blueprint = unreal.load_asset(plan["package"]) if assets.does_asset_exist(plan["package"]) else None
    if blueprint is None:
        folder, name = plan["package"].rsplit("/", 1)
        factory = unreal.BlueprintFactory()
        factory.set_editor_property("parent_class", unreal.StaticMeshActor.static_class())
        blueprint = unreal.AssetToolsHelpers.get_asset_tools().create_asset(name, folder, unreal.Blueprint, factory)
    if not isinstance(blueprint, unreal.Blueprint):
        raise ValueError("Target assembly is not a Blueprint")
    if not unreal.MathLibrary.class_is_child_of(blueprint.generated_class(), unreal.StaticMeshActor.static_class()):
        raise ValueError("Assembly must inherit StaticMeshActor")
    components = _components(unreal, blueprint, subsystem)
    roots = [(name, handle, component) for name, (handle, component) in components.items()
             if component.get_name() == "StaticMeshComponent0"]
    if len(roots) != 1:
        raise ValueError("Assembly requires the native StaticMeshActor root")
    root_name, root_handle, root = roots[0]
    if root.get_editor_property("static_mesh"):
        raise ValueError("Assembly root must not carry an undeclared render mesh")
    expected = plan["components"]
    renames = {}
    for name, spec in expected.items():
        present = [alias for alias in spec["aliases"] if alias in components]
        if len(present) > 1 or (name in components and present):
            raise ValueError(f"Ambiguous existing components for {spec['source_name']}")
        if present:
            renames[present[0]] = name
    permitted = set(expected) | set(renames) | set(plan["retired_components"]) | {root_name}
    if set(components) - permitted:
        raise ValueError("Assembly contains undeclared components: " + ", ".join(sorted(set(components) - permitted)))
    if root_name in renames or root_name in plan["retired_components"]:
        raise ValueError("Assembly root cannot be renamed or retired")
    for name in plan["retired_components"]:
        if name in components:
            if subsystem.delete_subobject(root_handle, components[name][0], blueprint) != 1:
                raise RuntimeError(f"Could not retire component {name}")
    for previous, current in renames.items():
        subsystem.rename_subobject_member_variable(blueprint, components[previous][0], unreal.Name(current))
    components = _components(unreal, blueprint, subsystem)
    root.set_editor_property("mobility", unreal.ComponentMobility.MOVABLE)
    for name, spec in expected.items():
        if name in components:
            handle = components[name][0]
        else:
            handle, reason = subsystem.add_new_subobject(unreal.AddNewSubobjectParams(
                parent_handle=root_handle, new_class=unreal.StaticMeshComponent.static_class(), blueprint_context=blueprint))
            if not subobjects.is_handle_valid(handle):
                raise RuntimeError(str(reason))
            subsystem.rename_subobject_member_variable(blueprint, handle, unreal.Name(name))
        component = subobjects.get_object_for_blueprint(subobjects.get_data(handle), blueprint)
        component.set_editor_property("static_mesh", meshes[name])
        component.set_editor_property("relative_location", unreal.Vector(*spec["location_cm"]))
        pitch, yaw, roll = spec["rotation_deg"]
        component.set_editor_property("relative_rotation", unreal.Rotator(pitch=pitch, yaw=yaw, roll=roll))
        component.set_editor_property("relative_scale3d", unreal.Vector(*spec["scale"]))
        component.set_editor_property("mobility", unreal.ComponentMobility.MOVABLE)
        component.set_editor_property("visible", True)
        component.set_editor_property("hidden_in_game", False)
        for setting in ("cast_shadow", "affect_distance_field_lighting", "visible_in_ray_tracing"):
            component.set_editor_property(setting, True)
        component.set_editor_property("can_ever_affect_navigation", spec["role"] == "main")
        component.set_editor_property("component_tags", [unreal.Name(tag) for tag in spec["tags"]])
        component.set_collision_profile_name(spec["collision"])
    unreal.BlueprintEditorLibrary.compile_blueprint(blueprint)
    if not assets.save_loaded_asset(blueprint, only_if_is_dirty=False):
        raise RuntimeError("Could not save assembly Blueprint")
    blueprint = unreal.load_asset(plan["package"])
    defaults = unreal.get_default_object(blueprint.generated_class())
    if (not isinstance(defaults, unreal.StaticMeshActor)
            or defaults.static_mesh_component.get_editor_property("static_mesh")
            or defaults.static_mesh_component.get_editor_property("mobility") != unreal.ComponentMobility.MOVABLE):
        raise RuntimeError("Saved assembly root differs from the native root contract")
    components = _components(unreal, blueprint, subsystem)
    if set(components) != set(expected) | {root_name}:
        raise RuntimeError("Saved assembly component set differs from the declaration")
    for name, spec in expected.items():
        component = components[name][1]
        if component.get_editor_property("static_mesh").get_path_name() != spec["asset"]:
            raise RuntimeError(f"Saved mesh differs for {name}")
        if list(map(str, component.get_editor_property("component_tags"))) != spec["tags"]:
            raise RuntimeError(f"Saved ground tags differ for {name}")
        if str(component.get_collision_profile_name()) != spec["collision"]:
            raise RuntimeError(f"Saved collision differs for {name}")
        location = component.get_editor_property("relative_location")
        rotation = component.get_editor_property("relative_rotation")
        scale = component.get_editor_property("relative_scale3d")
        for actual, desired in (((location.x, location.y, location.z), spec["location_cm"]),
                                ((rotation.pitch, rotation.yaw, rotation.roll), spec["rotation_deg"]),
                                ((scale.x, scale.y, scale.z), spec["scale"])):
            if any(abs(a-b) > .001 for a, b in zip(actual, desired)):
                raise RuntimeError(f"Saved transform differs for {name}")
        for setting in ("visible", "cast_shadow", "affect_distance_field_lighting", "visible_in_ray_tracing"):
            if not component.get_editor_property(setting):
                raise RuntimeError(f"Saved rendering setting differs for {name}: {setting}")
        if component.get_editor_property("hidden_in_game") or component.get_editor_property("override_materials"):
            raise RuntimeError(f"Saved visibility or material overrides differ for {name}")
        if component.get_editor_property("mobility") != unreal.ComponentMobility.MOVABLE:
            raise RuntimeError(f"Saved mobility differs for {name}")
    if blueprint.generated_class().get_path_name() != plan["asset"]:
        raise RuntimeError("Generated assembly class differs from the requested path")
    return {"class": plan["asset"], "components": expected, "mobility": "Movable",
            "authoring_api": "mle_authoring.author_assembly", "native_profile": "ManorLords-0.8.117"}

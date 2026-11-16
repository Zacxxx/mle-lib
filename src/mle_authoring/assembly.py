"""Translate logical mesh roles into Manor Lords 0.8.117 assembly conventions."""
import math
import re


GROUNDS = {"fixed": [], "reference": ["refHeight"],
           "follow_reference": ["addRefHeight"], "slope": ["adjustSlope"]}
COMPONENT_FIELDS = {"name", "role", "mesh", "location_cm", "rotation_deg", "scale", "ground", "native", "aliases"}


def identifier(value):
    return isinstance(value, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", value) is not None


def vector(value, label, positive=False):
    if not isinstance(value, (list, tuple)) or len(value) != 3:
        raise ValueError(f"{label} must contain three finite numbers")
    if any(type(number) not in (int, float) or not math.isfinite(number)
           or (positive and number <= 0) for number in value):
        raise ValueError(f"Invalid {label}")
    return list(value)


def asset_path(value):
    return isinstance(value, str) and re.fullmatch(r"/(?:Game|Engine)/[A-Za-z0-9_/]+\.[A-Za-z0-9_]+", value) is not None


def validate_native_components(components, construction_part_id):
    main = f"MainBld_{construction_part_id}"
    if main not in components:
        raise ValueError("Native assembly requires its main construction component")
    for name in components:
        if name != main and not name.startswith("clutter_"):
            raise ValueError(f"Native assembly will skip unclassified component {name}")


def compile_assembly(definition):
    if not isinstance(definition, dict) or set(definition) - {
            "asset", "construction_part_id", "components", "retired_components"}:
        raise ValueError("Unknown assembly definition field")
    asset = definition.get("asset")
    if not asset_path(asset) or not asset.startswith("/Game/"):
        raise ValueError("Assembly requires a /Game Blueprint class path")
    package, class_name = asset.rsplit(".", 1)
    if class_name != package.rsplit("/", 1)[-1] + "_C":
        raise ValueError("Assembly Blueprint class and package names must agree")
    part_id = definition.get("construction_part_id")
    if type(part_id) is not int or part_id <= 0:
        raise ValueError("Invalid construction part identity")
    declared = definition.get("components")
    if not isinstance(declared, list) or not 1 <= len(declared) <= 256:
        raise ValueError("Declare between one and 256 assembly components")
    components, logical_names, migration_names = {}, set(), set()
    main_count = 0
    for component in declared:
        if not isinstance(component, dict) or set(component) - COMPONENT_FIELDS:
            raise ValueError("Unknown assembly component field")
        name, role = component.get("name"), component.get("role")
        if not identifier(name) or name.casefold() in logical_names:
            raise ValueError("Component names must be unique identifiers")
        logical_names.add(name.casefold())
        if role not in ("main", "visual", "decoration"):
            raise ValueError(f"Unknown component role {role}")
        main = role == "main"
        main_count += main
        native_name = f"MainBld_{part_id}" if main else "clutter_" + name
        if native_name.casefold() in {key.casefold() for key in components}:
            raise ValueError("Native component name collision")
        if not asset_path(component.get("mesh")):
            raise ValueError(f"Invalid mesh path for {name}")
        ground = component.get("ground", "reference" if main else "follow_reference" if role == "visual" else "slope")
        if ground not in GROUNDS or (not main and ground == "reference"):
            raise ValueError("Invalid component ground policy")
        aliases = component.get("aliases", [])
        if not isinstance(aliases, list) or any(not identifier(alias) for alias in aliases):
            raise ValueError("Component aliases must be identifiers")
        for alias in aliases:
            key = alias.casefold()
            if key in migration_names or key == native_name.casefold():
                raise ValueError("Ambiguous component migration alias")
            migration_names.add(key)
        native = component.get("native", False)
        if type(native) is not bool:
            raise ValueError("Native asset flag must be boolean")
        components[native_name] = {
            "source_name": name, "role": role, "asset": component["mesh"],
            "location_cm": vector(component.get("location_cm", [0, 0, 0]), "location"),
            "rotation_deg": vector(component.get("rotation_deg", [0, 0, 0]), "rotation"),
            "scale": vector(component.get("scale", [1, 1, 1]), "scale", positive=True),
            "collision": "BlockAll" if main else "NoCollision", "tags": list(GROUNDS[ground]),
            "native": native, "aliases": list(aliases),
        }
    if main_count != 1:
        raise ValueError("Assembly requires exactly one main component")
    retired = definition.get("retired_components", [])
    if not isinstance(retired, list) or any(not identifier(name) for name in retired):
        raise ValueError("Retired component names must be identifiers")
    generated_names = {key.casefold() for key in components}
    retired_names = {key.casefold() for key in retired}
    if (generated_names & migration_names or generated_names & retired_names
            or migration_names & retired_names or len(retired_names) != len(retired)):
        raise ValueError("Migration names overlap active components")
    validate_native_components(components, part_id)
    return {"asset": asset, "package": package, "construction_part_id": part_id,
            "components": components, "retired_components": list(retired)}

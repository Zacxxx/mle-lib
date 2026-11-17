"""Generate original demonstration geometry using Blender's Python API.

blender --background --factory-startup --python model.py -- /absolute/output
No game geometry, textures, downloaded assets or external Python modules are used.
"""
from pathlib import Path
import json
import math
import struct
import sys
import zlib

import bpy
import bmesh


def png(path, width, height, pixel):
    def chunk(name, data):
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))
    rows = b"".join(b"\0" + bytes(channel for x in range(width) for channel in pixel(x, y)) for y in range(height))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def main():
    output = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1
    groups = {"Foundation": [], "Frame": [], "Roof": []}
    materials = {}
    for name, colour in (("TutorialWood", (.45, .3, .17, 1)), ("TutorialStone", (.3, .31, .32, 1))):
        material = bpy.data.materials.new(name)
        material.diffuse_color = colour
        material.use_nodes = True
        material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = colour
        material.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = .85
        materials[name] = material

    def box(group, name, at, size, angle=0):
        bpy.ops.mesh.primitive_cube_add(size=1, location=at)
        obj = bpy.context.object
        obj.name = name
        obj.dimensions = size
        obj.rotation_euler[1] = angle
        obj.data.materials.append(materials["TutorialStone" if group == "Foundation" else "TutorialWood"])
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bevel = obj.modifiers.new("Small timber edge", "BEVEL")
        bevel.width, bevel.segments = .015, 1
        bpy.ops.object.modifier_apply(modifier=bevel.name)
        groups[group].append(obj)
        return obj

    for x in (-2, 2):
        for y in (-1.5, 1.5):
            box("Foundation", "Stone foot", (x, y, -.2), (.65, .65, .8))
            box("Frame", "Post", (x, y, 1.55), (.22, .22, 3.1))
        box("Frame", "Side beam", (x, 0, 3), (.25, 3.4, .25))
    for y in (-1.5, 1.5):
        box("Frame", "Front beam", (0, y, 3), (4.3, .25, .25))
    for index in range(18):
        box("Frame", "Back plank", (-1.9 + index * .22, 1.5, 1.5), (.2, .12, 2.8))
    pitch = math.atan2(1.5, 2.4)
    slope_length = math.hypot(2.4, 1.5)
    for side in (-1, 1):
        box("Roof", "Roof panel", (side * 1.2, 0, 3.75), (slope_length, 3.9, .12), side * pitch)
    originals = [obj for group in groups.values() for obj in group]

    def export(name, objects, collisions=False):
        bpy.ops.object.select_all(action="DESELECT")
        copies = []
        for obj in objects:
            clone = obj.copy()
            clone.data = obj.data.copy()
            bpy.context.collection.objects.link(clone)
            clone.select_set(True)
            copies.append(clone)
        bpy.context.view_layer.objects.active = copies[0]
        bpy.ops.object.join()
        merged = bpy.context.object
        merged.name = merged.data.name = name
        bpy.context.scene.cursor.location = (0, 0, 0)
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(island_margin=.025)
        bpy.ops.mesh.quads_convert_to_tris()
        bpy.ops.object.mode_set(mode="OBJECT")
        geometry = bmesh.new()
        geometry.from_mesh(merged.data)
        bmesh.ops.recalc_face_normals(geometry, faces=list(geometry.faces))
        geometry.to_mesh(merged.data)
        geometry.free()
        temporary = [merged]
        if collisions:
            for index, obj in enumerate(groups["Foundation"] + [obj for obj in groups["Frame"] if obj.name.startswith("Post")]):
                clone = obj.copy()
                clone.data = obj.data.copy()
                bpy.context.collection.objects.link(clone)
                clone.name = f"UCX_{name}_{index:02}"
                clone.select_set(True)
                temporary.append(clone)
        bpy.context.view_layer.objects.active = merged
        result = bpy.ops.export_scene.fbx(filepath=str(output / (name + ".fbx")), use_selection=True,
            object_types={"MESH"}, apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS",
            axis_forward="-Y", axis_up="Z", bake_anim=False, mesh_smooth_type="FACE", use_tspace=True)
        assert result == {"FINISHED"}
        for obj in temporary:
            bpy.data.objects.remove(obj, do_unlink=True)

    export("SM_ExampleHouse", originals, True)
    for name, objects in groups.items():
        export("SM_ExampleHouse_" + name, objects, name == "Foundation")
    def wood(x, y):
        grain = int(10 * math.sin(x * .3 + math.sin(y * .02)) + 5 * math.sin(x * 1.7))
        return tuple(base + grain for base in (122, 92, 61))
    png(output / "ExampleWood.png", 256, 256, wood)
    material = materials["TutorialWood"]
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(output / "ExampleWood.png"))
    material.node_tree.links.new(texture.outputs["Color"], material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    bpy.ops.object.select_all(action="DESELECT")
    for obj in originals:
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(island_margin=.025)
        bpy.ops.object.mode_set(mode="OBJECT")
        obj.select_set(False)
    for obj in originals:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(output / "ExampleHouse.glb"), export_format="GLB", use_selection=True)
    def icon(x, y):
        # Deliberately simple original placeholder art; replace for a release.
        if 48 <= x <= 208 and abs(x - 128) <= (y - 25) * 1.4 and y < 95:
            return (100, 70, 42)
        if 65 < x < 190 and 95 <= y < 225:
            return (122, 92, 61) if x < 85 or x > 170 or y < 112 else (218, 202, 166)
        return (218, 202, 166)
    png(output / "ExampleHouse.png", 256, 256, icon)
    (output / "source.json").write_text(json.dumps({"units": "metres; FBX imports as centimetres",
        "pieces": list(groups), "source": "Original procedural tutorial geometry",
        "native_assets_included": False}, indent=4) + "\n")


if __name__ == "__main__":
    main()

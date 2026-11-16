import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from mle_authoring import compile_assembly, validate_native_components


def example():
    return {"asset": "/Game/Example/House.House_C", "construction_part_id": 19001,
            "components": [{"name": "Foundation", "role": "main", "mesh": "/Game/Example/Base.Base"},
                           {"name": "BarnVisual_Roof", "role": "visual", "mesh": "/Game/Example/Roof.Roof"},
                           {"name": "Yard", "role": "decoration", "mesh": "/Game/Example/Yard.Yard"}]}


class AssemblyAuthoringTests(unittest.TestCase):
    def test_logical_roles_compile_to_native_mesh_conventions(self):
        source = example()
        before = copy.deepcopy(source)
        compiled = compile_assembly(source)
        self.assertEqual(source, before)
        parts = compiled["components"]
        self.assertEqual(set(parts), {"MainBld_19001", "clutter_BarnVisual_Roof", "clutter_Yard"})
        self.assertEqual(parts["MainBld_19001"]["collision"], "BlockAll")
        self.assertEqual(parts["clutter_BarnVisual_Roof"]["tags"], ["addRefHeight"])
        self.assertEqual(parts["clutter_Yard"]["tags"], ["adjustSlope"])
        self.assertEqual(parts["clutter_Yard"]["collision"], "NoCollision")

    def test_unclassified_candidate43_component_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "will skip"):
            validate_native_components({"MainBld_19001": {}, "BarnVisual_Roof": {}}, 19001)

    def test_invalid_roles_names_transforms_and_migrations_fail_before_authoring(self):
        for field, value in (("role", "unknown"), ("name", "Foundation"), ("mesh", "bad"),
                             ("scale", [1, 0, 1]), ("location_cm", [0, float("nan"), 0]),
                             ("rotation_deg", [True, 0, 0]), ("native", "yes"),
                             ("aliases", ["MainBld_19001"]), ("ground", "reference")):
            source = example()
            source["components"][1][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                compile_assembly(source)
        for count in (0, 2):
            source = example()
            source["components"] = [source["components"][0]] * count
            with self.assertRaises(ValueError):
                compile_assembly(source)

    def test_component_rename_preserves_explicit_alias_and_transform(self):
        source = example()
        source["components"][1].update(aliases=["clutter_old_roof"], location_cm=[10, -20, 30],
                                       rotation_deg=[0, 90, 0], scale=[2, 1, 1])
        roof = compile_assembly(source)["components"]["clutter_BarnVisual_Roof"]
        self.assertEqual(roof["aliases"], ["clutter_old_roof"])
        self.assertEqual(roof["location_cm"], [10, -20, 30])
        self.assertEqual(roof["rotation_deg"], [0, 90, 0])

import copy
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from mle_authoring.render_profile import validate_render_profile, verify_render_environment


def profile():
    return {"schema_version": 1, "id": "manor_lords_0_8_117", "engine_version": "5.5.4",
            "cvars": {"r.AllowStaticLighting": 0, "r.SupportStationarySkylight": 0}}


class RenderProfileTests(unittest.TestCase):
    def test_static_lighting_mismatch_rejected_with_actionable_difference(self):
        with self.assertRaisesRegex(ValueError, "r.AllowStaticLighting.*expected 0.*observed 1"):
            verify_render_environment(profile(), "5.5.4-40574608", {
                "r.AllowStaticLighting": 1, "r.SupportStationarySkylight": 0})

    def test_missing_observation_is_not_treated_as_disabled(self):
        with self.assertRaisesRegex(ValueError, "r.AllowStaticLighting.*missing"):
            verify_render_environment(profile(), "5.5.4", {"r.SupportStationarySkylight": 0})

    def test_engine_mismatch_and_malformed_profiles_fail(self):
        with self.assertRaisesRegex(ValueError, "engine"):
            verify_render_environment(profile(), "5.6.0", profile()["cvars"])
        for field, value in (("cvars", {}), ("schema_version", 2), ("id", "bad id"),
                             ("cvars", {"r.AllowStaticLighting": False}),
                             ("cvars", {"r.AllowStaticLighting\nfoo": 0})):
            source = profile()
            source[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                validate_render_profile(source)

    def test_matching_environment_is_stable_and_does_not_mutate_input(self):
        source = profile()
        before = copy.deepcopy(source)
        result = verify_render_environment(source, "5.5.4-40574608+++UE5+Release-5.5", source["cvars"])
        self.assertEqual(source, before)
        self.assertTrue(result["compatible"])
        self.assertEqual(result["profile"], source["id"])
        changed = profile()
        changed["cvars"]["r.AllowStaticLighting"] = 1
        other = verify_render_environment(changed, "5.5.4", changed["cvars"])
        self.assertNotEqual(other["profile_sha256"], result["profile_sha256"])

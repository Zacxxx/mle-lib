"""Check the host game's shader contract before cooking mod materials.

This module has no Unreal dependency. Consumers supply effective console-variable
readbacks from their authoring/cooker process; editor defaults are not evidence.
"""
import copy
import hashlib
import json
import re


def validate_render_profile(profile):
    if not isinstance(profile, dict) or not {"schema_version", "id", "engine_version", "cvars"} <= profile.keys():
        raise ValueError("Render profile requires schema_version, id, engine_version and cvars")
    if set(profile) - {"schema_version", "id", "engine_version", "cvars", "provenance"}:
        raise ValueError("Unknown render profile fields")
    if type(profile["schema_version"]) is not int or profile["schema_version"] != 1:
        raise ValueError("Unsupported render profile schema")
    if not isinstance(profile["id"], str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,95}", profile["id"]):
        raise ValueError("Invalid render profile id")
    if not isinstance(profile["engine_version"], str) or not re.fullmatch(r"\d+\.\d+\.\d+", profile["engine_version"]):
        raise ValueError("Render profile engine_version requires an exact engine patch version")
    cvars = profile["cvars"]
    if not isinstance(cvars, dict) or not cvars:
        raise ValueError("Render profile cvars must be a nonempty map")
    for name, value in cvars.items():
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.]*", name) or type(value) is not int:
            raise ValueError("Render profile cvars require console-variable names and integer values")
    if "provenance" in profile and (not isinstance(profile["provenance"], dict)
            or any(not isinstance(k, str) or not isinstance(v, str) for k, v in profile["provenance"].items())):
        raise ValueError("Render profile provenance requires a string map")
    return copy.deepcopy(profile)


def verify_render_environment(profile, engine_version, observed):
    profile = validate_render_profile(profile)
    expected_engine = profile["engine_version"]
    if not isinstance(engine_version, str) or not (
            engine_version == expected_engine or engine_version.startswith(expected_engine + "-")):
        raise ValueError(f"Render profile engine mismatch: expected {expected_engine}, observed {engine_version}")
    if not isinstance(observed, dict):
        raise ValueError("Effective console-variable readbacks must be a map")
    differences = []
    for name, desired in sorted(profile["cvars"].items()):
        actual = observed.get(name)
        if type(actual) is not int or actual != desired:
            differences.append(f"{name}: expected {desired}, observed {actual if name in observed else 'missing'}")
    if differences:
        raise ValueError("Incompatible material cook environment: " + "; ".join(differences))
    fingerprint = hashlib.sha256(json.dumps(profile, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"compatible": True, "profile": profile["id"], "profile_sha256": fingerprint,
            "engine_version": engine_version, "effective_cvars": {key: observed[key] for key in sorted(profile["cvars"])}}

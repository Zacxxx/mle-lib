# Match the game's shader environment

A material cook inherits the authoring project's renderer settings. Those settings
must match the target game where they affect shader output or G-buffer layout.
Matching UE version and texture paths alone is insufficient.

The SDK includes `config/render_profiles/manor_lords_0_8_117.json`, established
from the installed game's DefaultEngine.ini and Windows platform INI at Steam
build 26185246. Its provenance records source SHA-256 hashes. It covers seventeen
desktop rendering/shader settings for our opaque static-mesh material path;
it is not a promise of compatibility with other game builds or every rendering
feature. Match these settings in the consumer's cooker project, then verify the
effective values in both its editor and Windows cooker processes.

For example, in UE 5.5 `ALLOW_STATIC_LIGHTING` changes whether the generic AO channel
stores encoded indirect irradiance or ambient occlusion. A custom base-pass shader
and the game's deferred decoder must agree. Studio lighting can conceal the mismatch.

`Tools/mle_authoring/render_profile.py` provides two pure Python functions:

```python
from mle_authoring.render_profile import validate_render_profile, verify_render_environment

profile = {
    "schema_version": 1,
    "id": "my_game_build",
    "engine_version": "5.5.4",
    "cvars": {"r.AllowStaticLighting": 0, "r.SupportStationarySkylight": 0},
}
validate_render_profile(profile)
# Supply values read from the actual cooker process, not this profile itself.
receipt = verify_render_environment(profile, cooker_version, observed_console_variables)
```

The verifier rejects missing observations, wrong engine patch versions and differing
settings. It returns an immutable-by-copy receipt with a SHA-256 profile fingerprint.
Optional `provenance` is a string map for game build, source paths and source hashes.
The profile must be established from the target game's effective configuration;
the two entries above are an example, not a complete universal renderer profile.

Consumers should preflight the effective environment immediately before cooking,
retain the receipt beside the exact cooked package hash and force a clean material
recook after a shader contract change. Merely editing an INI cannot repair shader
bytecode already in a published pak. The profile must not be installed as an override
to the player's game configuration.

Also verify texture colour spaces and channel packing, all texture bulk payloads,
runtime material usages and the mesh attributes actually used by the shader.
Keep unlit albedo, vertex-colour and constant-grey diagnostic materials to isolate
data sampling from lighting. In-world construction and reload acceptance remains
required; this verifier establishes a cooking contract, not correct GPU rendering.

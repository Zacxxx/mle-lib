# Assembly authoring

MLE Lib 0.1.14 includes a Python authoring API under Tools/mle_authoring in both
SDK and shared runtime archives. Add the archive's Tools directory to Unreal
Editor Python's sys.path and call mle_authoring.unreal_assembly.author_assembly.
The standalone example in examples/assembly_roles.py shows its use.

Each assembly declares its generated Blueprint class path, reserved
construction_part_id and components. Each component has a logical name, role
and mesh object path. Optional location_cm, rotation_deg (pitch, yaw, roll),
positive scale and ground policy describe its placement. Components use
Movable mobility, visible lit meshes and their mesh asset's materials.

The main role creates MainBld_<construction_part_id> with BlockAll collision
and navigation influence. Exactly one main component is required. Visual and
decoration roles create clutter_<logical name> with NoCollision. A logical
name such as BarnVisual_Roof is supported. The compiler generates the native
component name automatically. A building with one complete main mesh and no
additional visual meshes is also supported.

The default ground policy is reference for main, follow_reference for visual
and slope for decoration. Explicit fixed, reference, follow_reference and
slope policies map to the native refHeight, addRefHeight and adjustSlope tags.
Reference is reserved for the main component. The policy chooses which native
terrain behavior is invoked and requires sensible mesh pivots.

Use aliases to migrate an existing component member name. Retired components
must be listed explicitly in retired_components. Unknown existing components
and ambiguous aliases fail before editing the Blueprint. The pure
compile_assembly function can validate declarations outside Unreal. The editor
adapter resolves all meshes before editing, compiles and saves the assembly,
then checks its mesh references, transforms, tags, visibility and collision.
Editor API failures during mutation require correcting the error and rerunning
or restoring the source asset from version control. Edits are idempotent but
are not a transactional Unreal asset rollback.

The optional mesh_loader(path, native) callback allows an isolated authoring
project to resolve game-only imports. It must return a StaticMesh at the exact
requested path. Native assets and authoring stand-ins must be excluded from
the distributed pak. The default loader uses unreal.load_asset.

Register the compiled class through register_building assets.assembly. For a
modular assembly, assets.main_mesh identifies the main mesh separately from
the full placement asset in assets.preview. Construction Blueprint generation,
recipes and gameplay remain separate building API features. Run your cooker
and packaging checks after authoring. A saved Blueprint verification does not
establish settlement construction, upgrade or visual acceptance in the game.

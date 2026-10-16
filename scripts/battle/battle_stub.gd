extends Node3D
## BattleStub — **PLACEHOLDER** battle scene.  M2 replaces it.  (S0.3 batch 3 route target)
##
## Why it exists: `goto_battle()` → `return_to_world()` needs a second real scene, or the
## "world comes back to the same node count" acceptance would be vacuous.  The placeholder
## identity is registered here and in ROADMAP §5 S0.3 — it must never be read as the battle
## system, and nothing gameplay-shaped belongs in this file.
##
## It deliberately runs the SAME art pipeline as the overworld (`Style.toon()` +
## `MeshUtil.facet()` + inverted-hull outline + `Style.PALETTE`), because that is what
## makes it evidence that the pipeline works in a second scene rather than only in
## `scenes/main.tscn`.  Everything is a pure function of the constants below: no `Rng`, no
## clock, no `_process` — so two loads are byte-identical and this file cannot disturb the
## six-camera baseline that `scenes/main.tscn` establishes.

const ARENA := 6.0          ## half extent of the sparring ground, metres
const SUBDIV := 10          ## PlaneMesh subdivisions per axis (facet size)
const RELIEF := 0.85        ## how far the rim rises above the dipped centre
const WAVE := 0.18          ## extra ripple so the flat shading has bands to read
const PLINTH_TOP := -0.12   ## display-base top edge, just under the arena
const PLINTH_BOTTOM := -1.35

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var plinth: MeshInstance3D = $Plinth
@onready var arena: MeshInstance3D = $Arena
@onready var camera: Camera3D = $Camera


func _ready() -> void:
	add_to_group("battle_stub")
	_build_environment()
	# The display base reuses the diorama palette so the placeholder reads as the same
	# world, not as programmer art.
	plinth.mesh = MeshUtil.superellipse_prism(
			ARENA + 0.9, ARENA + 0.9, PLINTH_BOTTOM, PLINTH_TOP, 4.0, 5,
			Style.lit("rock_dark"), Style.lit("rock"), 0.92)
	plinth.material_override = Style.toon({"outline": false})
	arena.mesh = _arena_mesh()
	arena.material_override = Style.toon({"ink": 2.0, "rim": 0.12})
	# Orthographic isometric lens, same convention as the overworld rig (AGENTS.md 一.5).
	camera.position = Vector3(11.0, 10.5, 11.0)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Style.pal("high")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Style.pal("cream")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	world_env.environment = env
	# There is no sky here, so the sun must not try to read one.
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY


## Faceted sparring ground: a shallow bowl with a ripple, no cube anywhere.
func _arena_mesh() -> ArrayMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ARENA * 2.0, ARENA * 2.0)
	plane.subdivide_width = SUBDIV
	plane.subdivide_depth = SUBDIV
	var base := MeshUtil.facet(plane, Color.WHITE)
	var verts: PackedVector3Array = base.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var ymin := 1.0e9
	var ymax := -1.0e9
	for i in verts.size():
		var v := verts[i]
		v.y = _relief(v.x, v.z)
		verts[i] = v
		ymin = minf(ymin, v.y)
		ymax = maxf(ymax, v.y)
	var low := Style.lit("sand_deep")
	var high := Style.lit("sand")
	var colors := PackedColorArray()
	colors.resize(verts.size())
	var span := maxf(ymax - ymin, 0.001)
	for i in verts.size():
		colors[i] = low.lerp(high, smoothstep(0.0, 1.0, (verts[i].y - ymin) / span))
	var staged := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	staged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# `facet_rebuild` recomputes flat normals + smooth tangents (the inverted hull needs
	# the welded tangents) from the displaced vertices, keeping the new colours.
	return MeshUtil.facet_rebuild(staged, verts)


## Pure function of position: coincident vertices get the same height (so displacing the
## non-indexed, per-face vertices cannot crack the surface) and two loads are identical.
func _relief(x: float, z: float) -> float:
	var r := minf(sqrt(x * x + z * z) / ARENA, 1.0)
	return RELIEF * r * r + WAVE * sin(x * 1.6) * cos(z * 1.5)
class_name Scatter
extends Node3D
## Vegetation & props — the dynamic ecology layer.
##
## Everything is placed by sampling the terrain height field plus a couple of
## noise fields (forest density, moisture), so the plant communities follow the
## land instead of being sprinkled at random.  Every species is one MultiMesh
## with per-instance colour/tint/phase variation, drawn through the same toon +
## ink-outline pipeline as the terrain.

const STEP := 2.35
const JITTER := 0.62
const MAX_TREES := 190
const MAX_ROCKS := 150
const MAX_GRASS := 260

var stats := {"trees": 0, "rocks": 0, "grass": 0}

var _n_density: FastNoiseLite
var _n_kind: FastNoiseLite
var _root := Node3D.new()


func _ready() -> void:
	_root.name = "ScatterGroups"
	add_child(_root)


func scatter(terrain: Terrain, world_seed: int) -> void:
	for child in _root.get_children():
		child.queue_free()
	_n_density = _noise(world_seed + 191, 0.030, 3)
	_n_kind = _noise(world_seed + 613, 0.016, 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + 13

	var broadleaf: Array[Transform3D] = []
	var broadleaf_cd: Array[Vector4] = []
	var pines: Array[Transform3D] = []
	var pines_cd: Array[Vector4] = []
	var rocks: Array[Transform3D] = []
	var rocks_cd: Array[Vector4] = []
	var bushes: Array[Transform3D] = []
	var bushes_cd: Array[Vector4] = []

	var half := Terrain.SIZE * 0.5 - 2.6
	var spawn := terrain.spawn_point
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var px := x + rng.randf_range(-JITTER, JITTER)
			var pz := z + rng.randf_range(-JITTER, JITTER)
			z += STEP
			var h := terrain.height_at(px, pz)
			if h < 0.62 or h > 8.6:
				continue
			var slope := terrain.slope_at(px, pz)
			if slope > 0.66:
				continue
			# Keep a generous clearing around the spawn: the follow camera sits
			# behind the figurine at a fixed isometric angle, so trees planted
			# right next to it would stand between the lens and the character.
			if Vector2(px - spawn.x, pz - spawn.z).length() < 5.6:
				continue
			var dens := _n_density.get_noise_2d(px, pz) * 0.5 + 0.5
			var kind := _n_kind.get_noise_2d(px, pz) * 0.5 + 0.5
			var yaw := rng.randf_range(0.0, TAU)
			var phase := rng.randf()
			var tint := rng.randf_range(-0.055, 0.075)

			# --- conifers claim the highlands, broadleaf the lowlands -------
			var pine_chance := smoothstep(3.1, 5.8, h)
			var tree_ok := dens > 0.50 and h < 8.4 and slope < 0.60
			if tree_ok and broadleaf.size() + pines.size() < MAX_TREES and rng.randf() < 0.85:
				var s := rng.randf_range(0.72, 1.22)
				var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.92, 1.12), s)),
						Vector3(px, h - 0.14 * s, pz))
				var cd := Vector4(phase, rng.randf_range(0.55, 1.0), tint, 0.0)
				if kind < pine_chance:
					if pines.size() < MAX_TREES:
						pines.append(xf)
						pines_cd.append(cd)
				else:
					broadleaf.append(xf)
					broadleaf_cd.append(cd)
			# --- rounded pebbles & boulders ---------------------------------
			elif h > 0.35 and dens < 0.62 and rng.randf() < 0.16 and rocks.size() < MAX_ROCKS:
				var s := rng.randf_range(0.45, 1.35) * (1.0 + smoothstep(3.0, 7.0, h) * 0.5)
				var xf := Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), yaw, rng.randf_range(-0.3, 0.3)))
						.scaled(Vector3(s * rng.randf_range(0.9, 1.3), s * rng.randf_range(0.55, 0.85), s)),
						Vector3(px, h - 0.10 * s, pz))
				rocks.append(xf)
				rocks_cd.append(Vector4(phase, 0.0, rng.randf_range(-0.09, 0.09), 0.0))
			# --- soft grass tufts -------------------------------------------
			elif h > 0.9 and h < 6.4 and slope < 0.55 and rng.randf() < 0.42 and bushes.size() < MAX_GRASS:
				var s := rng.randf_range(0.55, 1.05)
				var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s)),
						Vector3(px, h - 0.05, pz))
				bushes.append(xf)
				bushes_cd.append(Vector4(phase, rng.randf_range(0.7, 1.2), rng.randf_range(-0.07, 0.1), 0.0))
		x += STEP

	_add_group("Broadleaf", _broadleaf_mesh(), broadleaf, broadleaf_cd, 0.055, 2.0)
	_add_group("Pines", _pine_mesh(), pines, pines_cd, 0.035, 1.9)
	_add_group("Rocks", _rock_mesh(), rocks, rocks_cd, 0.0, 1.5)
	_add_group("Grass", _grass_mesh(), bushes, bushes_cd, 0.05, 1.2)
	stats["trees"] = broadleaf.size() + pines.size()
	stats["rocks"] = rocks.size()
	stats["grass"] = bushes.size()


func _noise(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	n.fractal_gain = 0.5
	return n


func _add_group(name: String, mesh: ArrayMesh, xforms: Array, customs: Array,
		wind: float, ink: float) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		var cd: Vector4 = customs[k]
		mm.set_instance_custom_data(k, Color(cd.x, cd.y, cd.z, cd.w))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh.surface_set_material(0, Style.toon({
		"shade_min": 0.40,
		"rim": 0.22,
		"rim_color": Color(1.0, 0.98, 0.85),
		"wind": wind,
		"wind_speed": 0.9,
		"wind_bias": 0.9,
		"ink": ink,
	}))
	_root.add_child(mmi)


# ---------------------------------------------------------------------------
# species meshes — rounded low-poly shapes only, never a cube
# ---------------------------------------------------------------------------
func _broadleaf_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250929
	var trunk := MeshUtil.tapered_cylinder(0.19, 0.12, 1.75, 6,
			Style.pal("trunk").srgb_to_linear(), Vector2(0.09, -0.05))
	var c1 := MeshUtil.blob(1.06, 6, 9, Vector3(1.06, 0.86, 1.0), 0.07, rng, Style.pal("leaf").srgb_to_linear())
	var c2 := MeshUtil.blob(0.74, 5, 8, Vector3(1.0, 0.9, 1.0), 0.07, rng, Style.pal("leaf_dark").srgb_to_linear())
	var c3 := MeshUtil.blob(0.66, 5, 8, Vector3(1.0, 0.92, 1.0), 0.07, rng, Style.pal("leaf").srgb_to_linear())
	var mesh := MeshUtil.combine([
		{"mesh": trunk, "xform": Transform3D(Basis(), Vector3(0, 0.87, 0))},
		{"mesh": c1, "xform": Transform3D(Basis(), Vector3(0.0, 2.42, 0.0))},
		{"mesh": c2, "xform": Transform3D(Basis(), Vector3(0.72, 2.06, 0.34))},
		{"mesh": c3, "xform": Transform3D(Basis(), Vector3(-0.66, 2.18, -0.42))},
	])
	return MeshUtil.roughen(mesh, 0.035, rng, false)


func _pine_mesh() -> ArrayMesh:
	var trunk := MeshUtil.tapered_cylinder(0.16, 0.10, 1.20, 6,
			Style.pal("trunk").srgb_to_linear(), Vector2(0.03, 0.02))
	var t1 := MeshUtil.cone(1.08, 1.65, 7, true, Style.pal("pine").srgb_to_linear())
	var t2 := MeshUtil.cone(0.84, 1.45, 7, true, Style.pal("pine_dark").srgb_to_linear())
	var t3 := MeshUtil.cone(0.58, 1.30, 7, true, Style.pal("pine").srgb_to_linear())
	var mesh := MeshUtil.combine([
		{"mesh": trunk, "xform": Transform3D(Basis(), Vector3(0, 0.6, 0))},
		{"mesh": t1, "xform": Transform3D(Basis(), Vector3(0, 1.75, 0))},
		{"mesh": t2, "xform": Transform3D(Basis(), Vector3(0, 2.75, 0))},
		{"mesh": t3, "xform": Transform3D(Basis(), Vector3(0, 3.72, 0))},
	])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	return MeshUtil.roughen(mesh, 0.03, rng, false)


func _rock_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	var b := MeshUtil.blob(0.52, 5, 7, Vector3(1.18, 0.74, 0.98), 0.14, rng,
			Style.pal("stone").srgb_to_linear())
	var b2 := MeshUtil.blob(0.30, 4, 6, Vector3(1.0, 0.8, 1.1), 0.12, rng,
			Style.pal("rock").srgb_to_linear())
	var mesh := MeshUtil.combine([
		{"mesh": b, "xform": Transform3D(Basis(Vector3.UP, 0.7), Vector3(0, 0.34, 0))},
		{"mesh": b2, "xform": Transform3D(Basis(Vector3.UP, 2.1), Vector3(0.42, 0.16, 0.2))},
	])
	return MeshUtil.roughen(mesh, 0.05, rng, true)


func _grass_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var leaf := Style.pal("grass_dark").srgb_to_linear()
	var body := MeshUtil.blob(0.34, 4, 6, Vector3(1.15, 0.62, 1.15), 0.09, rng, leaf)
	var b1 := MeshUtil.cone(0.11, 0.66, 5, false, Style.pal("leaf").srgb_to_linear(), 0.25)
	var b2 := MeshUtil.cone(0.09, 0.52, 5, false, Style.pal("grass").srgb_to_linear(), -0.3)
	var mesh := MeshUtil.combine([
		{"mesh": body, "xform": Transform3D(Basis(), Vector3(0, 0.2, 0))},
		{"mesh": b1, "xform": Transform3D(Basis(Vector3.UP, 0.9), Vector3(0.12, 0.45, 0.08))},
		{"mesh": b2, "xform": Transform3D(Basis(Vector3.UP, 2.4), Vector3(-0.13, 0.38, -0.06))},
	])
	return MeshUtil.roughen(mesh, 0.03, rng, true)

class_name Terrain
extends Node3D
## Terrain — the diorama island.
##
## Deliberately NO VOXELS.  The island is one continuous, smoothly undulating
## low-poly mesh generated from layered fractal Simplex noise, then de-indexed
## so every triangle can carry its own flat normal and its own flat colour
## (Godot's equivalent of `toNonIndexed()` + flat shading).  On top of that the
## area-weighted *smooth* normal of every vertex is stored in the tangent slot,
## which is what the inverted-hull outline grows along.
##
## Public API used by the rest of the game:
##   Terrain.instance.height_at(x, z)   exact height of the rendered surface
##   Terrain.instance.normal_at(x, z)   surface normal  (slope aware walking)
##   Terrain.instance.spawn_point       a nice flat place to drop the player
##   Terrain.instance.generate(seed)    full rebuild

signal generated(stats: Dictionary)

static var instance: Terrain

# --- world constants -------------------------------------------------------
const SIZE := 63.0            # total footprint (metres, rounded square)
const HALF := SIZE * 0.5
const GRID := 104             # quads per side  -> 104*104*2 = 21 632 triangles
const SEA_LEVEL := 0.0
const SLAB_BOTTOM := -3.9
const WALL_TOP := -0.10
const MAX_HEIGHT := 12.6

# --- island footprint ------------------------------------------------------
# The landmass wants to own most of the tile so the tray reads as "an island
# with a moat" rather than "a pebble lost in an ocean".  COAST_IN is the
# normalised radius where the land is still whole, COAST_OUT where it has fully
# drowned; between them the beach slopes into the shallows.
const ISLAND_REACH := 0.96
const COAST_IN := 0.68
const COAST_OUT := 1.12

# --- palette bands ---------------------------------------------------------
const SAND_TOP := 1.80
const GRASS_TOP := 7.00
const HIGH_TOP := 9.70
## Height over which the turquoise highland fades into the snow cap.
const SNOW_FADE := 1.40

# --- slope gates for exposed rock -----------------------------------------
# Measured on a *blurred* slope field (see generate): single facets that merely
# clip the threshold no longer flip to stone, so cliff faces stay where cliffs
# actually are instead of sprinkling blue confetti over the meadows.
const ROCK_SAND := 0.58
const ROCK_GRASS := 0.62
const ROCK_HIGH := 0.68
const ROCK_SNOW := 0.78

var world_seed := 0
var spawn_point := Vector3(0.0, 4.0, 0.0)
var stats := {"trees": 0, "rocks": 0, "grass": 0, "triangles": 0}

var _n_base: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_biome: FastNoiseLite
var _n_coast: FastNoiseLite
var _mesh_instance: MeshInstance3D
var _props := Node3D.new()


func _ready() -> void:
	instance = self
	_props.name = "TerrainDecor"
	add_child(_props)


# ---------------------------------------------------------------------------
# noise setup
# ---------------------------------------------------------------------------
func _make_noise(s: int, freq: float, octaves: int, ftype: int, gain: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = ftype
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.03
	n.fractal_gain = gain
	return n


func _setup_noise(s: int) -> void:
	# continuous fractal chains: broad continental shape, sharp mountain ridges,
	# fine surface bumps, and a separate biome/moisture field.
	_n_base = _make_noise(s, 0.0095, 5, FastNoiseLite.FRACTAL_FBM, 0.48)
	_n_ridge = _make_noise(s + 977, 0.0080, 5, FastNoiseLite.FRACTAL_RIDGED, 0.52)
	_n_detail = _make_noise(s + 4241, 0.075, 3, FastNoiseLite.FRACTAL_FBM, 0.5)
	_n_biome = _make_noise(s + 7331, 0.021, 3, FastNoiseLite.FRACTAL_FBM, 0.5)
	# low frequency wobble that makes the coastline meander instead of tracing a
	# mathematical superellipse.
	_n_coast = _make_noise(s + 3167, 0.030, 2, FastNoiseLite.FRACTAL_FBM, 0.5)


# ---------------------------------------------------------------------------
# height field — shared by the mesh, the water, the scatterer and the player
# ---------------------------------------------------------------------------
func _dist(x: float, z: float) -> float:
	## Rounded-square (superellipse) radial parameter, 0 at the middle of the
	## tile and 1 where the island runs out.  A low frequency noise term makes
	## the coastline wander so the land reads as a landmass rather than as a
	## rounded rectangle.
	var nx := x / (HALF * ISLAND_REACH)
	var nz := z / (HALF * ISLAND_REACH)
	var d := pow(pow(absf(nx), 3.2) + pow(absf(nz), 3.2), 1.0 / 3.2)
	return d + _n_coast.get_noise_2d(x, z) * 0.15


func _mask(x: float, z: float) -> float:
	## Island falloff: 1 in the heart of the island, 0 out in the tray.
	return clampf(1.0 - smoothstep(COAST_IN, COAST_OUT, _dist(x, z)), 0.0, 1.0)


func height_at(x: float, z: float) -> float:
	var d := _dist(x, z)
	var m := clampf(1.0 - smoothstep(COAST_IN, COAST_OUT, d), 0.0, 1.0)
	var msm := smoothstep(0.02, 0.88, m)
	var base := _n_base.get_noise_2d(x, z) * 0.5 + 0.5
	var ridge := _n_ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var ridge_amt := smoothstep(0.26, 0.94, m)
	var detail := _n_detail.get_noise_2d(x * 1.7, z * 1.7)
	# a soft central summit gives the island a readable silhouette instead of
	# a gently wobbling plate
	var peak := smoothstep(0.74, 0.05, d) * 0.30
	var land := base * 0.62 + pow(ridge, 1.42) * 0.44 * ridge_amt + detail * 0.055 + peak
	land = clampf(land, 0.0, 1.20)
	var shelf := 1.0 - msm
	# gentle dunes on the sea floor: without them the shelf is a dead flat
	# plane and the water above it has no depth variation to read.
	var dunes := (_n_detail.get_noise_2d(x * 0.85, z * 0.85) * 0.5 + 0.5) * 0.28
	var e := land * msm - 0.46 * shelf - shelf * dunes
	if e <= 0.0:
		return e * 2.0
	return pow(e, 1.30) * MAX_HEIGHT


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.42
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < SEA_LEVEL


func biome_at(x: float, z: float) -> float:
	return _n_biome.get_noise_2d(x, z) * 0.5 + 0.5


# ---------------------------------------------------------------------------
# per-face colouring: pure flat palette bands, never a texture
# ---------------------------------------------------------------------------
enum { B_SEABED, B_SAND, B_GRASS, B_HIGH, B_SNOW, B_COUNT }


func _band_of(h: float) -> int:
	if h < -0.02:
		return B_SEABED
	if h < SAND_TOP:
		return B_SAND
	if h < GRASS_TOP:
		return B_GRASS
	if h < HIGH_TOP:
		return B_HIGH
	return B_SNOW


## Exposed rock.  `slope` arrives already blurred, so a lone facet that merely
## clips the gate can no longer punch an isolated stone patch into a meadow.
func _is_rocky(band: int, slope: float) -> bool:
	match band:
		B_SAND:
			return slope > ROCK_SAND
		B_GRASS:
			return slope > ROCK_GRASS
		B_HIGH:
			return slope > ROCK_HIGH
		B_SNOW:
			return slope > ROCK_SNOW
	return false


func _face_color(band: int, h: float, variant: float) -> Color:
	match band:
		B_SEABED:
			# submerged shelf: wet sand at the waterline dropping away into a
			# cool teal sea floor, so the translucent water above reads as water
			# rather than as a yellow field seen through a blue sheet.
			var t := smoothstep(0.0, 1.0, clampf((h + 1.30) / 1.28, 0.0, 1.0))
			var shore := Style.pal("sand_deep").lerp(Style.pal("sand"), t)
			return Style.pal("seabed").lerp(shore, smoothstep(0.0, 0.45, t))
		B_SAND:
			return Style.pal("sand")
		B_GRASS:
			return Style.pal("grass") if variant < 0.58 else Style.pal("grass_dark")
		B_HIGH:
			return Style.pal("high") if variant < 0.56 else Style.pal("high_dark")
		B_SNOW:
			var t2 := clampf((h - HIGH_TOP) / SNOW_FADE, 0.0, 1.0)
			if t2 < 1.0:
				return Style.pal("high").lerp(Style.pal("snow"), smoothstep(0.10, 0.95, t2))
			return Style.pal("snow") if variant < 0.72 else Style.pal("snow_shade")
	return Style.pal("snow")


static func _hash2(i: int, j: int) -> float:
	var n := (i * 374761393 + j * 668265263) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	n = n & 0x7fffffff
	return float(n % 65536) / 65535.0


## 3x3 box blur over a quad-sized field, repeated `passes` times, with edge
## clamping.  Used to settle the slope field so the rock gate only fires on
## slopes that are genuinely steep over a whole neighbourhood.
func _blur(src: PackedFloat32Array, g: int, passes: int) -> PackedFloat32Array:
	var cur := src
	for _p in passes:
		var out := PackedFloat32Array()
		out.resize(g * g)
		for j in g:
			for i in g:
				var sum := 0.0
				var cnt := 0
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var ii := clampi(i + di, 0, g - 1)
						var jj := clampi(j + dj, 0, g - 1)
						sum += cur[jj * g + ii]
						cnt += 1
				out[j * g + i] = sum / float(cnt)
		cur = out
	return cur


## 3x3 majority (mode) filter over a quad-sized integer field.  Isolated
## single-quad outliers are absorbed by their neighbours while genuine runs of
## a band survive untouched -- this is what converts the ragged one-triangle
## colour dithering along a band edge into clean, deliberate faceted runs.
## Ties keep the incumbent value so repeated passes are stable.
func _majority(src, g: int, passes: int) -> Array:
	var cur: Array = Array(src)
	for _p in passes:
		var out: Array = cur.duplicate()
		for j in g:
			for i in g:
				var tally := {}
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var ii := clampi(i + di, 0, g - 1)
						var jj := clampi(j + dj, 0, g - 1)
						var v: int = cur[jj * g + ii]
						tally[v] = int(tally.get(v, 0)) + 1
				var incumbent: int = cur[j * g + i]
				var best_v := incumbent
				var best_n := int(tally.get(incumbent, 0))
				for v2 in tally.keys():
					var n2: int = tally[v2]
					if n2 > best_n:
						best_n = n2
						best_v = v2
				out[j * g + i] = best_v
		cur = out
	return cur


# ---------------------------------------------------------------------------
# mesh construction
# ---------------------------------------------------------------------------
func generate(seed_value: int) -> void:
	world_seed = seed_value
	_setup_noise(seed_value)
	var t0 := Time.get_ticks_msec()

	var n := GRID + 1
	var step := SIZE / float(GRID)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		var z := -HALF + float(j) * step
		for i in n:
			var x := -HALF + float(i) * step
			hs[j * n + i] = height_at(x, z)

	# smooth (area weighted analytic) normals -> stored in the tangent slot
	var snorm := PackedVector3Array()
	snorm.resize(n * n)
	for j in n:
		for i in n:
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, GRID)
			var jd := maxi(j - 1, 0)
			var ju := mini(j + 1, GRID)
			var dx := (hs[j * n + ir] - hs[j * n + il]) / (float(ir - il) * step)
			var dz := (hs[ju * n + i] - hs[jd * n + i]) / (float(ju - jd) * step)
			snorm[j * n + i] = Vector3(-dx, 1.0, -dz).normalized()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var pos := PackedVector3Array()
	pos.resize(n * n)
	for j in n:
		for i in n:
			pos[j * n + i] = Vector3(-HALF + float(i) * step, hs[j * n + i], -HALF + float(j) * step)

	var tris := 0

	# --- quad fields: mean height, raw slope, biome variant -----------------
	var qh := PackedFloat32Array()
	var qslope := PackedFloat32Array()
	var qvar := PackedFloat32Array()
	qh.resize(GRID * GRID)
	qslope.resize(GRID * GRID)
	qvar.resize(GRID * GRID)
	for j in GRID:
		for i in GRID:
			var a := j * n + i
			var b := j * n + i + 1
			var c := (j + 1) * n + i + 1
			var d := (j + 1) * n + i
			var q := j * GRID + i
			qh[q] = (hs[a] + hs[b] + hs[c] + hs[d]) * 0.25
			# slope of the quad plane, from the two corner diagonals so the
			# result does not depend on which way the quad is split
			var dx := (hs[b] + hs[c] - hs[a] - hs[d]) / (2.0 * step)
			var dz := (hs[d] + hs[c] - hs[a] - hs[b]) / (2.0 * step)
			qslope[q] = 1.0 - 1.0 / sqrt(1.0 + dx * dx + dz * dz)
			var px := -HALF + (float(i) + 0.5) * step
			var pz := -HALF + (float(j) + 0.5) * step
			qvar[q] = _n_biome.get_noise_2d(px * 4.0, pz * 4.0) * 0.5 + 0.5

	# blur the slope so a single facet cannot trip the rock gate on its own
	var slope_blur := _blur(qslope, GRID, 1)

	# --- band index + rock mask, then a majority filter ---------------------
	# The filter is what turns the ragged per-triangle colour dithering along a
	# band edge into clean, deliberate faceted runs.
	var qband := PackedInt32Array()
	var rocky := PackedByteArray()
	qband.resize(GRID * GRID)
	rocky.resize(GRID * GRID)
	for q in GRID * GRID:
		var b := _band_of(qh[q])
		qband[q] = b
		rocky[q] = 1 if _is_rocky(b, slope_blur[q]) else 0
	var band_f := _majority(qband, GRID, 1)
	var rocky_f := _majority(rocky, GRID, 1)

	for j in GRID:
		for i in GRID:
			var a := j * n + i
			var b := j * n + i + 1
			var c := (j + 1) * n + i + 1
			var d := (j + 1) * n + i
			var q := j * GRID + i
			var col := Style.pal("rock") if rocky_f[q] == 1 else _face_color(
					band_f[q], qh[q], qvar[q])
			# a whisper of per-facet lightness keeps the flat colour from
			# reading as a printed texture
			col = col * (0.978 + _hash2(i + 7919, j) * 0.044)
			col = col.srgb_to_linear()
			if (i + j) % 2 == 0:
				tris += _emit_up(st, pos[a], pos[b], pos[c], snorm[a], snorm[b], snorm[c], col)
				tris += _emit_up(st, pos[a], pos[c], pos[d], snorm[a], snorm[c], snorm[d], col)
			else:
				tris += _emit_up(st, pos[a], pos[b], pos[d], snorm[a], snorm[b], snorm[d], col)
				tris += _emit_up(st, pos[b], pos[c], pos[d], snorm[b], snorm[c], snorm[d], col)

	# --- outer curtain wall: the block the island is carved from -----------
	var loop := _boundary_loop(n)
	var wall_bands := [
		[WALL_TOP, -1.15, Style.pal("soil")],
		[-1.15, -2.45, Style.pal("rock_dark")],
		[-2.45, SLAB_BOTTOM, Style.pal("plinth")],
	]
	for k in loop.size():
		var p0: Vector3 = loop[k]
		var p1: Vector3 = loop[(k + 1) % loop.size()]
		if p0.distance_squared_to(p1) < 1e-8:
			continue
		var mid := (p0 + p1) * 0.5
		var outward := Vector3(mid.x, 0.0, mid.z).normalized()
		if outward.length_squared() < 0.5:
			outward = Vector3(1, 0, 0)
		for band in wall_bands:
			var ytop: float = band[0]
			var ybot: float = band[1]
			var ctop: Color = (band[2] as Color).srgb_to_linear()
			var cbot: Color = ctop.darkened(0.18)
			if ytop <= ybot:
				continue
			var ta := Vector3(p0.x, ytop, p0.z)
			var tb := Vector3(p1.x, ytop, p1.z)
			var ba := Vector3(p0.x, ybot, p0.z)
			var bb := Vector3(p1.x, ybot, p1.z)
			tris += _emit_facing(st, ta, tb, bb, outward, ctop, ctop)
			tris += _emit_facing(st, ta, bb, ba, outward, ctop, cbot)

	var mesh := st.commit()
	mesh.surface_set_material(0, Style.toon({
		"shade_min": 0.40, "rim": 0.16, "rim_color": Color(1.0, 0.97, 0.82), "ink": 3.0,
	}))
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "IslandMesh"
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_mesh_instance)
		move_child(_mesh_instance, 0)
	_mesh_instance.mesh = mesh

	_build_plinth()
	_find_spawn()
	# report the *area* each band actually covers, measured on the same filtered
	# quad field the mesh was coloured from, so the numbers describe what is on
	# screen rather than what a vertex sample would suggest.
	var band_counts := {"water": 0, "sand": 0, "grass": 0, "high": 0, "snow": 0}
	var band_names := ["water", "sand", "grass", "high", "snow"]
	var rock_area := 0
	var hmin := 1e9
	var hmax := -1e9
	for j in n:
		for i in n:
			var hh := hs[j * n + i]
			hmin = minf(hmin, hh)
			hmax = maxf(hmax, hh)
	for q in GRID * GRID:
		band_counts[band_names[band_f[q]]] += 1
		if rocky_f[q] == 1:
			rock_area += 1
	var total := float(GRID * GRID)
	print("[terrain] seed=%d  h=[%.2f .. %.2f]  water=%.0f%% sand=%.0f%% grass=%.0f%% high=%.0f%% snow=%.0f%% rock=%.1f%%" % [
		world_seed, hmin, hmax,
		100.0 * band_counts["water"] / total, 100.0 * band_counts["sand"] / total,
		100.0 * band_counts["grass"] / total, 100.0 * band_counts["high"] / total,
		100.0 * band_counts["snow"] / total, 100.0 * float(rock_area) / total])
	print("[terrain] spawn=%s  (h=%.2f)" % [spawn_point, spawn_point.y])
	stats["height_range"] = [hmin, hmax]
	stats["bands"] = band_counts
	stats["rock_area"] = rock_area
	stats["spawn"] = spawn_point
	stats["triangles"] = tris
	stats["gen_ms"] = Time.get_ticks_msec() - t0
	generated.emit(stats)


func _boundary_loop(n: int) -> Array[Vector3]:
	var loop: Array[Vector3] = []
	var step := SIZE / float(GRID)
	for i in range(n - 1):
		loop.append(Vector3(-HALF + float(i) * step, 0.0, -HALF))
	for j in range(n - 1):
		loop.append(Vector3(HALF, 0.0, -HALF + float(j) * step))
	for i in range(n - 1, 0, -1):
		loop.append(Vector3(-HALF + float(i) * step, 0.0, HALF))
	for j in range(n - 1, 0, -1):
		loop.append(Vector3(-HALF, 0.0, -HALF + float(j) * step))
	return loop


## Emits a triangle with an upward facing winding (winding is fixed by testing
## the resulting normal instead of trusting a fixed vertex order).
func _emit_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		sa: Vector3, sb: Vector3, sc: Vector3, col: Color) -> int:
	var fn := (b - a).cross(c - a)
	# the stored normal always faces up (outward) ...
	var flat := Vector3.UP
	if fn.length_squared() > 1e-12:
		flat = fn.normalized()
		if flat.y < 0.0:
			flat = -flat
	# ... while the emitted winding is reversed so that (b-a) x (c-a) points
	# down, which is what Godot treats as a front facing triangle.
	if fn.y > 0.0:
		var tb := b
		b = c
		c = tb
		var ts := sb
		sb = sc
		sc = ts
	_put(st, a, flat, sa, col)
	_put(st, b, flat, sb, col)
	_put(st, c, flat, sc, col)
	return 1


func _emit_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3,
		ca: Color, cc: Color) -> int:
	var nn := (b - a).cross(c - a)
	if nn.dot(outward) > 0.0:
		var tb := b
		b = c
		c = tb
	# outward shading normal, inward winding
	var fn := outward.normalized()
	if fn.length_squared() < 1e-6:
		fn = Vector3.UP
	_put(st, a, fn, fn, ca)
	_put(st, b, fn, fn, ca)
	_put(st, c, fn, fn, cc)
	return 1


## `flat` is the per-face normal (crisp cel facets), `smooth` is the
## area-weighted vertex normal the inverted-hull outline expands along.
func _put(st: SurfaceTool, v: Vector3, flat: Vector3, smooth: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(flat)
	st.set_tangent(Plane(smooth, 1.0))
	st.add_vertex(v)


## The display base: two chamfered superellipse prisms, echoing the island
## silhouette.  Still not a cube — every edge is a rounded chamfer.
func _build_plinth() -> void:
	for child in _props.get_children():
		child.queue_free()
	var pieces := [
		{
			"name": "PlinthBody",
			"half": HALF + 0.95, "top": SLAB_BOTTOM, "bottom": SLAB_BOTTOM - 1.85,
			"taper": 1.035, "round": 4.0, "ctop": Style.pal("plinth"), "cbot": Style.pal("plinth").darkened(0.25),
		},
		{
			"name": "PlinthLip",
			"half": HALF + 0.42, "top": SLAB_BOTTOM + 0.14, "bottom": SLAB_BOTTOM - 0.04,
			"taper": 1.0, "round": 4.0, "ctop": Style.pal("sand"), "cbot": Style.pal("sand").darkened(0.12),
		},
	]
	for p in pieces:
		var mesh: ArrayMesh = MeshUtil.superellipse_prism(
			p["half"], p["half"], p["bottom"], p["top"], p["round"], 5,
			(p["ctop"] as Color).srgb_to_linear(), (p["cbot"] as Color).srgb_to_linear(), p["taper"])
		var mi := MeshInstance3D.new()
		mi.name = p["name"]
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh.surface_set_material(0, Style.toon({
			"shade_min": 0.46, "rim": 0.10, "ink": 2.6}))
		_props.add_child(mi)


## Looks for the flattest, dry, reasonably low spot near the middle of the
## island so the player always starts somewhere pleasant.
func _find_spawn() -> void:
	var best := Vector3(0, 0, 0)
	var best_score := -1e9
	var golden := 2.39996
	for k in 340:
		var r: float = sqrt(float(k) / 340.0) * 17.0
		var a: float = float(k) * golden
		var x: float = cos(a) * r
		var z: float = sin(a) * r
		var h := height_at(x, z)
		if h < 1.4 or h > 5.0:
			continue
		var s := slope_at(x, z)
		if s > 0.24:
			continue
		var score := -s * 6.0 - absf(h - 2.6) * 0.5 - r * 0.02
		if score > best_score:
			best_score = score
			best = Vector3(x, h, z)
	if best_score < -1e8:
		best = Vector3(0, height_at(0, 0), 0)
	spawn_point = best
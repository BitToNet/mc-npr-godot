class_name StrategicTerrain
extends Node3D
## Strategic-scale terrain mesh (S1.2b).
##
## One HeightField in, 6x6 land chunks + water chunks (only where the sea is) +\n## an outer curtain out.
## The cell size is *derived* from the map (`map_size / round(map_size / 32)`)
## so a 2400 m map lands on 75 cells of exactly 32 m: 75 * 75 * 2 = 11 250
## triangles, about a third of the island fixture's 21 632-triangle budget.
##
## Deliberate differences from `terrain.gd` (island fixture, 63 m / 104 cells):
##   * no inverted-hull outline on the land body.  At 32 m spacing the hull
##     inflates into the neighbouring cells and the coastline turns into a
##     smeared black band; the shoreline read comes from a one-cell ink rim
##     plus the water foam band instead (see `_classify` / `_face_color`).
##   * the outer contour *is* inked: the curtain wall's top strip uses ink, so
##     the play area still reads as a drawn, finished edge.
##   * bands are keyed on normalised height (0..1 above sea level), not on
##     island metres, so the same code survives a `hill_amplitude` change.
##
## No RNG is drawn here: shading variation comes from a positional hash, so the
## mesh is a pure function of the field and two builds are byte-identical.

const CELL_TARGET := 32.0      ## desired metres per cell (rounded to fit the map)
const CHUNK_SIDE := 6          ## 6x6 chunks; 75 cells split as 13/13/13/12/12/12
const TOON_SHADER := "res://shaders/common/toon.gdshader"
const WATER_SHADER := "res://shaders/terrain/water.gdshader"
const StyleScript := preload("res://scripts/core/style.gd")

# band edges, normalised (0 = sea level, 1 = `field.max_height`)
const B_BEACH := 0.075
const B_GRASS := 0.340
const B_HIGH := 0.620

# rock gates, per band.  These are *gradients* (rise over run), not `1 - cos`,
# because at 32 m spacing a 1.0-gradient flank only scores 0.29 on that scale and
# nothing would ever read as rock.
const ROCK_BEACH := 0.50
const ROCK_GRASS := 0.65
const ROCK_HIGH := 0.85
const ROCK_SNOW := 0.95

const COAST_INK := 0.42        ## how far the one-cell shoreline rim leans to ink
const SKIRT_DEPTH := 60.0      ## outer curtain drops this far below the rim
const WATER_FOAM_DEPTH := 8.0  ## metres of shallows that stay foamy
const WATER_DEEP_DEPTH := 90.0 ## metres of drop that reaches deep colour

var field: HeightField
var cells := 0
var step := 0.0
var half := 0.0
var stats := {}

var _hs := PackedFloat32Array()
var _qband := PackedInt32Array()
var _qrocky := PackedByteArray()
var _qcoast := PackedByteArray()
var _qwater := PackedByteArray()
var _holder: Node3D
var _skirt_tris := 0
var _palette := {}


## Build (or rebuild) everything from `p_field`.  Safe to call twice: the old
## chunks are freed first so the node never accumulates meshes.
func build(p_field: HeightField) -> Dictionary:
	field = p_field
	if field == null:
		stats = {"ok": false, "reason": "没有高度场"}
		return stats
	half = field.map_size * 0.5
	# 2400 / 32 = 75 exactly; a map that does not divide still rounds to the
	# nearest cell count and re-derives the step, so the grid always covers
	# [-half, +half] with no leftover strip.
	cells = maxi(2, int(round(field.map_size / CELL_TARGET)))
	step = field.map_size / float(cells)
	if _holder == null:
		_holder = Node3D.new()
		_holder.name = "Chunks"
		add_child(_holder)
	# The palette is resolved once per build.  Asking the preloaded script for its
	# `const PALETTE` *per quad* measured 0.9 ms a call - 5 s on colour alone.
	# `Style` holds the same const, so one source serves both modes.
	_palette = StyleScript.PALETTE
	_clear()
	_sample()
	_classify()
	_build_land()
	_build_water()
	_build_skirt()
	var water_tris := _count_water_tris()
	var ymin := 1e30
	var ymax := -1e30
	for h in _hs:
		ymin = minf(ymin, h)
		ymax = maxf(ymax, h)
	stats = {
		"ok": true,
		"cells": cells,
		"chunks": CHUNK_SIDE * CHUNK_SIDE,
		"land_tris": cells * cells * 2,
		"water_tris": water_tris,
		"skirt_tris": _skirt_tris,
		"tris": cells * cells * 2 + water_tris + _skirt_tris,
		"step": snappedf(step, 0.001),
		"size": field.map_size,
		"min_y": snappedf(ymin, 0.01),
		"max_y": snappedf(ymax, 0.01),
		"coast_cells": _count_flag(_qcoast),
		"rock_cells": _count_flag(_qrocky),
		"bands": _band_counts(),
	}
	return stats


func _clear() -> void:
	_skirt_tris = 0
	for child in _holder.get_children():
		_holder.remove_child(child)
		# `queue_free()` needs a SceneTree; the mesh must also be rebuildable off
		# tree (verify builds it that way), where a direct free is the correct call.
		if child.is_inside_tree():
			child.queue_free()
		else:
			child.free()


# ---------------------------------------------------------------------------
# sampling + classification
# ---------------------------------------------------------------------------
func _sample() -> void:
	var n := cells + 1
	_hs.resize(n * n)
	for j in n:
		for i in n:
			var x := -half + float(i) * step
			var z := -half + float(j) * step
			_hs[j * n + i] = field.height_at(x, z)


func _norm_of(h: float) -> float:
	var span := field.max_height - field.water_level
	if span <= 0.0:
		return 0.0
	return clampf((h - field.water_level) / span, 0.0, 1.0)


func _classify() -> void:
	var n := cells + 1
	_qband.resize(cells * cells)
	_qrocky.resize(cells * cells)
	_qcoast.resize(cells * cells)
	_qwater.resize(cells * cells)
	var slope := PackedFloat32Array()
	slope.resize(cells * cells)
	for j in cells:
		for i in cells:
			var a := j * n + i
			var b := a + 1
			var c := (j + 1) * n + i + 1
			var d := (j + 1) * n + i
			var q := j * cells + i
			var qh := (_hs[a] + _hs[b] + _hs[c] + _hs[d]) * 0.25
			var dx := (_hs[b] + _hs[c] - _hs[a] - _hs[d]) / (2.0 * step)
			var dz := (_hs[d] + _hs[c] - _hs[a] - _hs[b]) / (2.0 * step)
			slope[q] = sqrt(dx * dx + dz * dz)
			_qband[q] = _band_of(_norm_of(qh))
			_qwater[q] = 1 if minf(minf(_hs[a], _hs[b]), minf(_hs[c], _hs[d])) < field.water_level else 0
	var rock_slope := _blur(slope, 1)
	for q in cells * cells:
		_qrocky[q] = 1 if _is_rocky(_qband[q], rock_slope[q]) else 0
	# one-cell shoreline rim: dry cells touching a wet one.  This is the
	# "outline" the art direction keeps on the land body (see file header).
	for j in cells:
		for i in cells:
			var q := j * cells + i
			if _qwater[q] == 1:
				_qcoast[q] = 0
				continue
			_qcoast[q] = 1 if _touches_water(i, j) else 0
	# the dry ring that touches water *is* the beach, whatever its height: the
	# strategic coast drops off fast, so a pure height band would leave a cliff
	# with no sand at all (measured: 3 beach cells out of 209 coastal ones).
	for q in cells * cells:
		if _qcoast[q] == 1 and _qband[q] <= 2:
			_qband[q] = 1
	# a single majority pass kills the lone-cell dithering along band edges,
	# exactly like the island does with its per-quad colour field
	_qband = _majority(_qband)
	_qrocky = _majority_bytes(_qrocky)


func _touches_water(i: int, j: int) -> bool:
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var ni := i + d.x
		var nj := j + d.y
		if ni < 0 or nj < 0 or ni >= cells or nj >= cells:
			continue
		if _qwater[nj * cells + ni] == 1:
			return true
	return false


func _band_of(nh: float) -> int:
	if nh <= 0.0:
		return 0            # water
	if nh < B_BEACH:
		return 1            # beach
	if nh < B_GRASS:
		return 2            # grass
	if nh < B_HIGH:
		return 3            # highland
	return 4                # snow


func _is_rocky(band: int, slope: float) -> bool:
	match band:
		1:
			return slope > ROCK_BEACH
		2:
			return slope > ROCK_GRASS
		3:
			return slope > ROCK_HIGH
		4:
			return slope > ROCK_SNOW
	return false


# ---------------------------------------------------------------------------
# land chunks
# ---------------------------------------------------------------------------
func _build_land() -> void:
	var spans := _split(cells, CHUNK_SIDE)
	var mat := _toon_material()
	var n := cells + 1
	for cz in CHUNK_SIDE:
		for cx in CHUNK_SIDE:
			var sx: Vector2i = spans[cx]
			var sz: Vector2i = spans[cz]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in range(sz.x, sz.x + sz.y):
				for i in range(sx.x, sx.x + sx.y):
					var a := j * n + i
					var b := a + 1
					var c := (j + 1) * n + i + 1
					var d := (j + 1) * n + i
					var q := j * cells + i
					var col := _quad_color(q)
					var pa := Vector3(-half + float(i) * step, _hs[a], -half + float(j) * step)
					var pb := Vector3(-half + float(i + 1) * step, _hs[b], -half + float(j) * step)
					var pc := Vector3(-half + float(i + 1) * step, _hs[c], -half + float(j + 1) * step)
					var pd := Vector3(-half + float(i) * step, _hs[d], -half + float(j + 1) * step)
					if (i + j) % 2 == 0:
						_tri(st, pa, pb, pc, col)
						_tri(st, pa, pc, pd, col)
					else:
						_tri(st, pa, pb, pd, col)
						_tri(st, pb, pc, pd, col)
			var mi := MeshInstance3D.new()
			mi.name = "Land_%d_%d" % [cx, cz]
			mi.mesh = st.commit()
			mi.mesh.surface_set_material(0, mat)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_holder.add_child(mi)


func _quad_color(q: int) -> Color:
	var band := _qband[q]
	var col := _pal("rock") if _qrocky[q] == 1 else _band_color(band)
	if _qcoast[q] == 1 and band != 0:
		col = col.lerp(_pal("ink"), COAST_INK)
	# a whisper of per-facet lightness keeps flat colour from reading as print
	var jitter := 0.978 + _hash2(q * 7919, cells) * 0.044
	return (col * jitter).srgb_to_linear()


func _band_color(band: int) -> Color:
	match band:
		0:
			return _pal("seabed")
		1:
			return _pal("sand")
		2:
			return _pal("grass")
		3:
			return _pal("high")
		4:
			return _pal("snow")
	return _pal("snow")


# ---------------------------------------------------------------------------
# water chunks
# ---------------------------------------------------------------------------
func _build_water() -> void:
	var spans := _split(cells, CHUNK_SIDE)
	var mat := _water_material()
	var n := cells + 1
	var y := field.water_level
	for cz in CHUNK_SIDE:
		for cx in CHUNK_SIDE:
			var sx: Vector2i = spans[cx]
			var sz: Vector2i = spans[cz]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var quads := 0
			for j in range(sz.x, sz.x + sz.y):
				for i in range(sx.x, sx.x + sx.y):
					var q := j * cells + i
					if _qwater[q] == 0:
						continue
					var a := j * n + i
					var b := a + 1
					var c := (j + 1) * n + i + 1
					var d := (j + 1) * n + i
					var depth := _norm_depth(a, b, c, d)
					var foam := 1.0 - smoothstep(0.0, WATER_FOAM_DEPTH / WATER_DEEP_DEPTH, depth)
					var shallow := _pal("water")
					var deep := _pal("water_deep")
					var col := shallow.lerp(deep, smoothstep(0.0, 0.55, depth))
					col.a = foam
					var pa := Vector3(-half + float(i) * step, y, -half + float(j) * step)
					var pb := Vector3(-half + float(i + 1) * step, y, -half + float(j) * step)
					var pc := Vector3(-half + float(i + 1) * step, y, -half + float(j + 1) * step)
					var pd := Vector3(-half + float(i) * step, y, -half + float(j + 1) * step)
					var rim := 1.0 if _touches_land(i, j) else 0.0
					if (i + j) % 2 == 0:
						_water_tri(st, pa, pb, pc, col, rim)
						_water_tri(st, pa, pc, pd, col, rim)
					else:
						_water_tri(st, pa, pb, pd, col, rim)
						_water_tri(st, pb, pc, pd, col, rim)
					quads += 1
			if quads == 0:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Water_%d_%d" % [cx, cz]
			mi.mesh = st.commit()
			mi.mesh.surface_set_material(0, mat)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_holder.add_child(mi)


func _norm_depth(a: int, b: int, c: int, d: int) -> float:
	var h := (_hs[a] + _hs[b] + _hs[c] + _hs[d]) * 0.25
	var depth := maxf(0.0, field.water_level - h)
	return clampf(depth / WATER_DEEP_DEPTH, 0.0, 1.0)


func _touches_land(i: int, j: int) -> bool:
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var ni := i + d.x
		var nj := j + d.y
		if ni < 0 or nj < 0 or ni >= cells or nj >= cells:
			continue
		if _qwater[nj * cells + ni] == 0:
			return true
	return false


func _water_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color,
		rim: float) -> void:
	var phase := _hash2(int(a.x * 0.25) + 977, int(a.z * 0.25) + 521)
	var flat := Vector3.UP
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(flat)
		st.set_uv2(Vector2(rim, phase))
		st.add_vertex(v)


# ---------------------------------------------------------------------------
# outer curtain: the block the map is cut from, with an ink rim on top
# ---------------------------------------------------------------------------
func _build_skirt() -> void:
	var mat := _toon_material()
	var edges := [
		[Vector2i(0, 0), Vector2i(1, 0)],
		[Vector2i(cells, 0), Vector2i(0, 1)],
		[Vector2i(cells, cells), Vector2i(-1, 0)],
		[Vector2i(0, cells), Vector2i(0, -1)],
	]
	var n := cells + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_skirt_tris = 0
	for edge in edges:
		var start: Vector2i = edge[0]
		var dir: Vector2i = edge[1]
		for k in cells:
			var i0 := start.x + dir.x * k
			var j0 := start.y + dir.y * k
			var i1 := i0 + dir.x
			var j1 := j0 + dir.y
			var h0 := _hs[j0 * n + i0]
			var h1 := _hs[j1 * n + i1]
			var p0 := Vector3(-half + float(i0) * step, h0, -half + float(j0) * step)
			var p1 := Vector3(-half + float(i1) * step, h1, -half + float(j1) * step)
			var outward := Vector3(float(dir.y), 0.0, float(-dir.x))
			if outward.length_squared() < 0.5:
				outward = Vector3(1, 0, 0)
			# two bands: a thin ink lip, then the rock face down to the plinth
			var lip := 1.6
			_skirt_tris += _wall(st, p0, p1, outward, 0.0, -lip,
					_pal("ink"), _pal("ink"))
			_skirt_tris += _wall(st, p0, p1, outward, -lip, -SKIRT_DEPTH,
					_pal("rock_dark"), _pal("plinth"))
	var mi := MeshInstance3D.new()
	mi.name = "Curtain"
	mi.mesh = st.commit()
	mi.mesh.surface_set_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_holder.add_child(mi)


func _wall(st: SurfaceTool, p0: Vector3, p1: Vector3, outward: Vector3,
		top_off: float, bot_off: float, ctop: Color, cbot: Color) -> int:
	var ta := Vector3(p0.x, p0.y + top_off, p0.z)
	var tb := Vector3(p1.x, p1.y + top_off, p1.z)
	var ba := Vector3(p0.x, p0.y + bot_off, p0.z)
	var bb := Vector3(p1.x, p1.y + bot_off, p1.z)
	var nrm := outward if outward.length_squared() > 0.5 else Vector3.UP
	nrm = nrm.normalized()
	var lt := ctop.srgb_to_linear()
	var lb := cbot.srgb_to_linear()
	# winding so the faces look outward: emit (a,b,c) then (a,c,d) with the
	# provided corner order, flipping if the cross product points inward
	var order := [[ta, tb, bb], [ta, bb, ba]]
	var cols := [lt, lb]
	var added := 0
	for t in 2:
		var tri: Array = order[t]
		var pa: Vector3 = tri[0]
		var pb: Vector3 = tri[1]
		var pc: Vector3 = tri[2]
		var fn := (pb - pa).cross(pc - pa)
		if fn.dot(nrm) > 0.0:
			var tmp := pb
			pb = pc
			pc = tmp
		for v in [pa, pb, pc]:
			st.set_color(cols[t])
			st.set_normal(nrm)
			st.add_vertex(v)
		added += 1
	return added


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var fn := (b - a).cross(c - a)
	var flat := Vector3.UP
	if fn.length_squared() > 1e-12:
		flat = fn.normalized()
		if flat.y < 0.0:
			flat = -flat
	if fn.y > 0.0:
		var tb := b
		b = c
		c = tb
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(flat)
		st.add_vertex(v)


## Balanced split of `total` into `parts` runs: 75 into 6 -> 13,13,13,12,12,12.
func _split(total: int, parts: int) -> Array:
	var out: Array = []
	var base := total / parts
	var extra := total % parts
	var at := 0
	for k in parts:
		var take := base + (1 if k < extra else 0)
		out.append(Vector2i(at, take))
		at += take
	return out


func _count_flag(flags: PackedByteArray) -> int:
	var n := 0
	for f in flags:
		n += int(f)
	return n


func _band_counts() -> Array:
	var out := [0, 0, 0, 0, 0]
	for b in _qband:
		if b >= 0 and b < 5:
			out[b] += 1
	return out


func _count_water_tris() -> int:
	var n := 0
	for q in cells * cells:
		if _qwater[q] == 1:
			n += 2
	return n


func _blur(src: PackedFloat32Array, passes: int) -> PackedFloat32Array:
	var cur := src
	for p in passes:
		var nxt := PackedFloat32Array()
		nxt.resize(src.size())
		for j in cells:
			for i in cells:
				var acc := 0.0
				var cnt := 0
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var ni := i + di
						var nj := j + dj
						if ni < 0 or nj < 0 or ni >= cells or nj >= cells:
							continue
						acc += cur[nj * cells + ni]
						cnt += 1
				nxt[j * cells + i] = acc / float(cnt) if cnt > 0 else cur[j * cells + i]
		cur = nxt
	return cur


func _majority(src: PackedInt32Array) -> PackedInt32Array:
	var out := src.duplicate()
	for j in cells:
		for i in cells:
			var counts := {}
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var ni := i + di
					var nj := j + dj
					if ni < 0 or nj < 0 or ni >= cells or nj >= cells:
						continue
					var v := src[nj * cells + ni]
					counts[v] = int(counts.get(v, 0)) + 1
			var best := src[j * cells + i]
			var best_n := -1
			for k in counts:
				if int(counts[k]) > best_n:
					best_n = int(counts[k])
					best = k
			out[j * cells + i] = best
	return out


func _majority_bytes(src: PackedByteArray) -> PackedByteArray:
	var out := src.duplicate()
	for j in cells:
		for i in cells:
			var ones := 0
			var total := 0
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var ni := i + di
					var nj := j + dj
					if ni < 0 or nj < 0 or ni >= cells or nj >= cells:
						continue
					ones += src[nj * cells + ni]
					total += 1
			out[j * cells + i] = 1 if ones * 2 > total else 0
	return out


static func _hash2(i: int, j: int) -> float:
	var n := (i * 374761393 + j * 668265263) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	n = n & 0x7fffffff
	return float(n % 65536) / 65535.0


# ---------------------------------------------------------------------------
# material / palette: Style when it exists, a quiet fallback under --script
# ---------------------------------------------------------------------------
## `--script` mode has no autoloads, so materials must not depend on the `Style`
## singleton.  `null` here means "use the raw-shader fallback"; the palette is
## always `StyleScript.PALETTE`, so both paths stay single-sourced.
##
## The node is also built off tree on purpose (verify does that), and both
## `get_tree()` and `queue_free()` log an error there - hence the guard first.
func _style_node() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("Style")


func _pal(key: String) -> Color:
	return _palette.get(key, Color.MAGENTA)


func _toon_material() -> ShaderMaterial:
	var opts := {"shade_min": 0.44, "rim": 0.10, "rim_color": Color(1.0, 0.98, 0.90),
			"ink": 2.6, "outline": false}
	var style := _style_node()
	if style != null:
		return style.call("toon", opts)
	var m := ShaderMaterial.new()
	m.shader = load(TOON_SHADER)
	m.set_shader_parameter("shade_min", float(opts["shade_min"]))
	m.set_shader_parameter("rim_amount", float(opts["rim"]))
	m.set_shader_parameter("rim_color", opts["rim_color"])
	return m


func _water_material() -> ShaderMaterial:
	var style := _style_node()
	if style != null:
		return style.call("water_material")
	var m := ShaderMaterial.new()
	m.shader = load(WATER_SHADER)
	m.set_shader_parameter("shallow_color", _pal("water"))
	m.set_shader_parameter("deep_color", _pal("water_deep"))
	m.set_shader_parameter("foam_color", Color(1, 1, 0.98))
	return m


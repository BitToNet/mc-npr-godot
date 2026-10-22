class_name MeshUtil
extends RefCounted
## MeshUtil — procedural low-poly geometry helpers.
##
## The whole point of this file: NOTHING here is a cube or a voxel.  Every
## shape is a smooth, rounded, faceted solid (spheres, capsules, cones,
## tapered cylinders, superellipse prisms) that is then de-indexed and given
## *flat per-face normals* plus *area-weighted smooth normals in the tangent
## slot* — the exact pair of attributes the toon shader and the inverted-hull
## outline shader need.


## Godot's equivalent of three.js `geometry.toNonIndexed()` + flat shading.
## Returns a non-indexed ArrayMesh where
##   * NORMAL   = the flat, per-triangle normal (crisp faceted cel shading)
##   * TANGENT  = the smooth, area-weighted vertex normal (crack-free hull)
##   * COLOR    = `tint` (optionally preserved from the source mesh)
static func facet(src: Mesh, tint: Color = Color.WHITE, keep_src_color: bool = false) -> ArrayMesh:
	if src == null or src.get_surface_count() == 0:
		return ArrayMesh.new()
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return ArrayMesh.new()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var n := verts.size()
	var tri_indices := PackedInt32Array()
	if idx.is_empty():
		tri_indices.resize(n)
		for i in n:
			tri_indices[i] = i
	else:
		tri_indices = idx
	var faces := tri_indices.size() / 3

	# --- area weighted smooth normals, welded by quantised position ---------
	var smooth := {}
	var pos_keys := PackedStringArray()
	pos_keys.resize(n)
	var quant := 10000.0
	for i in n:
		var k := "%d_%d_%d" % [
			roundi(verts[i].x * quant), roundi(verts[i].y * quant), roundi(verts[i].z * quant)]
		pos_keys[i] = k
		if not smooth.has(k):
			smooth[k] = Vector3.ZERO
	# NOTE: Godot's own primitives wind their triangles so that
	# (b-a) x (c-a) points *into* the solid.  Shading normals therefore have to
	# be the negation of that cross product in order to face outward.
	for f in faces:
		var a := verts[tri_indices[f * 3]]
		var b := verts[tri_indices[f * 3 + 1]]
		var c := verts[tri_indices[f * 3 + 2]]
		var fn := (c - a).cross(b - a) # length == 2 * area, so this is area weighted
		for v in [a, b, c]:
			var k := "%d_%d_%d" % [roundi(v.x * quant), roundi(v.y * quant), roundi(v.z * quant)]
			smooth[k] = (smooth[k] as Vector3) + fn

	var src_colors: PackedColorArray = PackedColorArray()
	if keep_src_color and arrays[Mesh.ARRAY_COLOR] != null:
		src_colors = arrays[Mesh.ARRAY_COLOR]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var ia := tri_indices[f * 3]
		var ib := tri_indices[f * 3 + 1]
		var ic := tri_indices[f * 3 + 2]
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		var fn := (c - a).cross(b - a)
		var flat := Vector3.UP if fn.length_squared() < 1e-12 else fn.normalized()
		for pair in [[ia, a], [ib, b], [ic, c]]:
			var vi: int = pair[0]
			var v: Vector3 = pair[1]
			var k := pos_keys[vi]
			var sn: Vector3 = smooth[k]
			if sn.length_squared() < 1e-12:
				sn = flat
			else:
				sn = sn.normalized()
			var col := tint
			if keep_src_color and vi < src_colors.size():
				col = src_colors[vi]
			st.set_color(col)
			st.set_normal(flat)
			st.set_tangent(Plane(sn, 1.0))
			st.add_vertex(v)
	return st.commit()


## Straight builder for hand written triangle soup (already flat shaded).
static func from_faces(
		positions: PackedVector3Array,
		colors: PackedColorArray,
		flat_normals: PackedVector3Array,
		smooth_normals: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in positions.size():
		st.set_color(colors[i])
		st.set_normal(flat_normals[i])
		st.set_tangent(Plane(smooth_normals[i], 1.0))
		st.add_vertex(positions[i])
	return st.commit()


## Rounded low-poly sphere ("clay ball"), optionally squashed into a blob.
static func blob(radius: float, rings: int = 6, segments: int = 9, squash := Vector3.ONE,
		jitter: float = 0.0, rng := RandomNumberGenerator.new(), tint: Color = Color.WHITE) -> ArrayMesh:
	if rng.seed == 0:
		rng.randomize()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for r in rings + 1:
		var v := float(r) / float(rings)
		var phi: float = PI * v
		var row: Array = []
		for s in segments:
			var th: float = TAU * float(s) / float(segments)
			var p := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			# cut off the poles into flat-ish caps so it reads hand made
			p.x *= squash.x
			p.y *= squash.y
			p.z *= squash.z
			if jitter > 0.0 and r > 0 and r < rings:
				p += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * jitter
			row.append(p * radius)
		grid.append(row)
	for r in rings:
		for s in segments:
			var s2 := (s + 1) % segments
			var a: Vector3 = grid[r][s]
			var b: Vector3 = grid[r][s2]
			var c: Vector3 = grid[r + 1][s2]
			var d: Vector3 = grid[r + 1][s]
			if r == 0:
				_tri(st, a, c, d, tint)
			elif r == rings - 1:
				_tri(st, a, b, c, tint)
			else:
				_tri(st, a, c, d, tint)
				_tri(st, a, b, c, tint)
	return st.commit()


static func cone(radius: float, height: float, segments: int = 7, cap: bool = false,
		tint: Color = Color.WHITE, sway := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(sway * height, height * 0.5, 0.0)
	var rim: Array = []
	for s in segments:
		var th: float = TAU * float(s) / float(segments)
		rim.append(Vector3(cos(th) * radius, -height * 0.5, sin(th) * radius))
	for s in segments:
		var s2 := (s + 1) % segments
		_tri(st, rim[s], apex, rim[s2], tint)
	if cap:
		var c := Vector3(0, -height * 0.5, 0)
		for s in segments:
			var s2 := (s + 1) % segments
			_tri(st, rim[s2], c, rim[s], tint)
	return st.commit()


static func tapered_cylinder(bottom_r: float, top_r: float, height: float, segments: int = 8,
		tint: Color = Color.WHITE, bend := Vector2.ZERO, cap_bottom: bool = true,
		cap_top: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bot: Array = []
	var top: Array = []
	for s in segments:
		var th: float = TAU * float(s) / float(segments)
		bot.append(Vector3(cos(th) * bottom_r, -height * 0.5, sin(th) * bottom_r))
		top.append(Vector3(cos(th) * top_r + bend.x, height * 0.5, sin(th) * top_r + bend.y))
	for s in segments:
		var s2 := (s + 1) % segments
		_tri(st, bot[s], top[s], top[s2], tint)
		_tri(st, bot[s], top[s2], bot[s2], tint)
	if cap_bottom:
		var c := Vector3(0, -height * 0.5, 0)
		for s in segments:
			var s2 := (s + 1) % segments
			_tri(st, bot[s2], c, bot[s], tint)
	if cap_top:
		var ct := Vector3(bend.x, height * 0.5, bend.y)
		for s in segments:
			var s2 := (s + 1) % segments
			_tri(st, top[s], ct, top[s2], tint)
	return st.commit()


## A superellipse (rounded square) prism — used for the diorama plinth so the
## base echoes the island silhouette without ever becoming a cube.
static func superellipse_prism(half_x: float, half_z: float, bottom_y: float, top_y: float,
		roundness: float = 4.0, corner_steps: int = 5, tint_top: Color = Color.WHITE,
		tint_bottom: Color = Color.WHITE, taper: float = 1.0) -> ArrayMesh:
	var outline := PackedVector2Array()
	var corners := [
		Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for ci in corners.size():
		var c0: Vector2 = corners[ci]
		var c1: Vector2 = corners[(ci + 1) % corners.size()]
		for s in corner_steps:
			var t := float(s) / float(corner_steps)
			var p := c0.lerp(c1, t)
			outline.append(p)
	var n := outline.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bot: Array = []
	var top: Array = []
	for i in n:
		var p := outline[i]
		# superellipse-ish rounding: push the point outward on the diagonal
		var d := p.normalized()
		var k: float = 1.0
		if absf(p.x) > 0.001 and absf(p.y) > 0.001:
			k = pow(pow(absf(p.x), roundness) + pow(absf(p.y), roundness), 1.0 / roundness)
			k = maxf(k, 1.0)
		elif p.length() < 0.001:
			k = 1.0
		else:
			k = 1.0
		var q := p / k
		bot.append(Vector3(q.x * half_x * taper, bottom_y, q.y * half_z * taper))
		top.append(Vector3(q.x * half_x, top_y, q.y * half_z))
	for i in n:
		var j := (i + 1) % n
		_tri_grad(st, bot[i], top[i], top[j], tint_bottom, tint_top)
		_tri_grad(st, bot[i], top[j], bot[j], tint_bottom, tint_top)
	# top cap
	var ctop := Vector3(0, top_y, 0)
	for i in n:
		var j := (i + 1) % n
		_tri(st, top[i], ctop, top[j], tint_top)
	# bottom cap
	var cbot := Vector3(0, bottom_y, 0)
	for i in n:
		var j := (i + 1) % n
		_tri(st, bot[j], cbot, bot[i], tint_bottom)
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var n := (b - a).cross(c - a)
	var nn := Vector3.UP
	if n.length_squared() > 1e-12:
		nn = n.normalized()
	_tri_grad(st, a, b, c, tint, tint, nn)


## NOTE ON WINDING: Godot treats *clockwise* triangles as front facing, while
## the generators below author counter-clockwise (right hand rule) triangles so
## that `(b-a) x (c-a)` is the outward normal.  The emitted vertex order is
## therefore flipped to (a, c, b) — the shading normal stays outward, the
## winding becomes Godot-correct, and every shape is a solid, not a shell.
static func _tri_grad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, nn: Vector3 = Vector3.ZERO) -> void:
	if nn == Vector3.ZERO:
		var n := (b - a).cross(c - a)
		nn = Vector3.UP if n.length_squared() < 1e-12 else n.normalized()
	st.set_color(ca)
	st.set_normal(nn)
	st.set_tangent(Plane(nn, 1.0))
	st.add_vertex(a)
	st.set_color(cb)
	st.set_normal(nn)
	st.set_tangent(Plane(nn, 1.0))
	st.add_vertex(c)
	st.set_color(cb)
	st.set_normal(nn)
	st.set_tangent(Plane(nn, 1.0))
	st.add_vertex(b)


## Hard-transforms every attribute of an ArrayMesh (positions, flat normals and
## the smooth normals stored in the tangent slot).  Written by hand instead of
## trusting SurfaceTool.append_from so rotated parts never get stale normals.
static func transform_mesh(mesh: ArrayMesh, xform: Transform3D) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var basis := xform.basis
	var nbasis := basis.inverse().transposed()
	for i in verts.size():
		verts[i] = xform * verts[i]
		if i < normals.size():
			normals[i] = (nbasis * normals[i]).normalized()
		if i * 4 + 2 < tangents.size():
			var t := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
			t = (nbasis * t).normalized()
			tangents[i * 4] = t.x
			tangents[i * 4 + 1] = t.y
			tangents[i * 4 + 2] = t.z
	var out := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TANGENT] = tangents
	arr[Mesh.ARRAY_COLOR] = colors
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## 反向外壳必须靠**连续**的皮。本文件所有生成器把"面法线"同时写进法线与切线槽，
## 于是外壳沿各自的面法线膨开、炸成散三角片（正常线宽下几乎看不见）。本函数按面积加权
## 重算平滑法线、**只写进切线槽**：着色仍用平面法线（保持面着色），外壳得到一张连续的皮。
##
## 首次实现于 S1.3a 的 `party_marker.gd`；S1.5b 出现第二个使用者（聚落标记）时上提到
## 这里，两边共用同一份实现 —— 两份拷贝只要有一处被改，描边就会"一边有、一边没有"。
static func smooth_tangents(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var src := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = src[Mesh.ARRAY_COLOR]
	var smooth := {}
	var faces := verts.size() / 3
	for f in faces:
		var i0 := f * 3
		var face_n: Vector3 = normals[i0]
		var cross := (verts[i0 + 1] - verts[i0]).cross(verts[i0 + 2] - verts[i0])
		var area := cross.length() * 0.5
		for k in 3:
			var key := _vkey(verts[i0 + k])
			smooth[key] = (smooth.get(key, Vector3.ZERO) as Vector3) + face_n * area
	var tangents := PackedFloat32Array()
	tangents.resize(verts.size() * 4)
	for i in verts.size():
		var sn: Vector3 = smooth.get(_vkey(verts[i]), normals[i])
		sn = sn.normalized() if sn.length_squared() > 0.000001 else normals[i]
		tangents[i * 4] = sn.x
		tangents[i * 4 + 1] = sn.y
		tangents[i * 4 + 2] = sn.z
		tangents[i * 4 + 3] = 1.0
	var out := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TANGENT] = tangents
	arr[Mesh.ARRAY_COLOR] = colors
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## 位置量化键：同一位置的重复顶点必须落进同一个桶，否则外壳会沿接缝裂开。
static func _vkey(p: Vector3) -> String:
	return "%d_%d_%d" % [roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0)]


## Merges several meshes into one, each with its own local transform.
## `items` entries: { "mesh": ArrayMesh, "xform": Transform3D }
static func combine(items: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var c := PackedColorArray()
	for it in items:
		var m: ArrayMesh = it["mesh"]
		var xf: Transform3D = it.get("xform", Transform3D.IDENTITY)
		var arrays := m.surface_get_arrays(0)
		var mv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var mn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var mt: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var mc: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var nb := xf.basis.inverse().transposed()
		for i in mv.size():
			v.append(xf * mv[i])
			n.append((nb * mn[i]).normalized() if i < mn.size() else Vector3.UP)
			if i * 4 + 3 < mt.size():
				var tg := (nb * Vector3(mt[i * 4], mt[i * 4 + 1], mt[i * 4 + 2])).normalized()
				t.append_array(PackedFloat32Array([tg.x, tg.y, tg.z, mt[i * 4 + 3]]))
			else:
				t.append_array(PackedFloat32Array([0.0, 1.0, 0.0, 1.0]))
			c.append(mc[i] if i < mc.size() else Color.WHITE)
	var out := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TANGENT] = t
	arr[Mesh.ARRAY_COLOR] = c
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## Randomly nudges vertices of a finished mesh so nothing looks machine made.
static func roughen(mesh: ArrayMesh, amount: float, rng: RandomNumberGenerator,
		lock_bottom := true) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var min_y := INF
	for v in verts:
		min_y = minf(min_y, v.y)
	# jitter keyed on quantised position so shared corners move together
	var offsets := {}
	for i in verts.size():
		var k := "%d_%d_%d" % [roundi(verts[i].x * 500.0), roundi(verts[i].y * 500.0), roundi(verts[i].z * 500.0)]
		if not offsets.has(k):
			var o := Vector3(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount) * 0.6,
					rng.randf_range(-amount, amount))
			if lock_bottom and verts[i].y <= min_y + 0.001:
				o.y = 0.0
			offsets[k] = o
		verts[i] = verts[i] + (offsets[k] as Vector3)
	return facet_rebuild(mesh, verts)


static func facet_rebuild(mesh: ArrayMesh, verts: PackedVector3Array) -> ArrayMesh:
	## Recomputes flat normals + smooth tangents after a vertex edit.
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var faces := verts.size() / 3
	var smooth := {}
	var quant := 10000.0
	for v in verts:
		var k := "%d_%d_%d" % [roundi(v.x * quant), roundi(v.y * quant), roundi(v.z * quant)]
		smooth[k] = Vector3.ZERO
	for f in faces:
		var a := verts[f * 3]
		var b := verts[f * 3 + 1]
		var c := verts[f * 3 + 2]
		var fn := (c - a).cross(b - a)
		for v in [a, b, c]:
			var k := "%d_%d_%d" % [roundi(v.x * quant), roundi(v.y * quant), roundi(v.z * quant)]
			smooth[k] = (smooth[k] as Vector3) + fn
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a := verts[f * 3]
		var b := verts[f * 3 + 1]
		var c := verts[f * 3 + 2]
		var fn := (c - a).cross(b - a)
		var flat := Vector3.UP if fn.length_squared() < 1e-12 else fn.normalized()
		for vi in [f * 3, f * 3 + 1, f * 3 + 2]:
			var v := verts[vi]
			var k := "%d_%d_%d" % [roundi(v.x * quant), roundi(v.y * quant), roundi(v.z * quant)]
			var sn: Vector3 = smooth[k]
			sn = flat if sn.length_squared() < 1e-12 else sn.normalized()
			st.set_color(colors[vi] if vi < colors.size() else Color.WHITE)
			st.set_normal(flat)
			st.set_tangent(Plane(sn, 1.0))
			st.add_vertex(v)
	return st.commit()


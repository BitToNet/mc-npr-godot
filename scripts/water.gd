class_name WaterSurface
extends MeshInstance3D
## Water — a single clear, translucent, gently breathing sheet at sea level.
## Shore proximity, depth and foam are baked into the vertex colours by
## sampling the *same* height field the island mesh is built from, so the
## waterline always sits exactly where the terrain crosses sea level.

const RES := 56


func build(terrain: Terrain) -> void:
	var size := Terrain.SIZE
	var half := size * 0.5
	var step := size / float(RES)
	var n := RES + 1
	var shallow := Style.pal("water")
	var deep := Style.pal("water_deep")

	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var custom := PackedFloat32Array()

	for j in n:
		for i in n:
			var x := -half + float(i) * step
			var z := -half + float(j) * step
			var h := terrain.height_at(x, z)
			var depth := maxf(Terrain.SEA_LEVEL - h, 0.0)
			# a wide, obvious shallow shelf: the water reads turquoise over the
			# sand and only turns deep blue further out
			var shore := 1.0 - clampf(depth / 1.25, 0.0, 1.0)
			shore = shore * shore * (3.0 - 2.0 * shore)
			var foam := 1.0 - smoothstep(0.0, 0.42, depth)
			# rounded-square rim mask (matches the island silhouette)
			var nx := x / half
			var nz := z / half
			var d := pow(pow(absf(nx), 3.0) + pow(absf(nz), 3.0), 1.0 / 3.0)
			var rim := smoothstep(0.70, 1.0, d)
			var c := deep.lerp(shallow, shore)
			verts.append(Vector3(x, Terrain.SEA_LEVEL, z))
			colors.append(Color(c.r, c.g, c.b, foam).srgb_to_linear())
			custom.append_array(PackedFloat32Array([rim, x * 0.13 + z * 0.17, (x + z) * 0.021, 0.0]))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in RES:
		for i in RES:
			var a := j * n + i
			var b := j * n + i + 1
			var c2 := (j + 1) * n + i + 1
			var d2 := (j + 1) * n + i
			# both windings are emitted facing up
			_quad(st, verts, colors, custom, a, b, c2, d2)

	mesh = st.commit()
	material_override = null
	mesh.surface_set_material(0, Style.water_material())
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _quad(st: SurfaceTool, verts: PackedVector3Array, colors: PackedColorArray,
		custom: PackedFloat32Array,
		a: int, b: int, c: int, d: int) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var ia: int = tri[0]
		var ib: int = tri[1]
		var ic: int = tri[2]
		var p0 := verts[ia]
		var p1 := verts[ib]
		var p2 := verts[ic]
		if (p1 - p0).cross(p2 - p0).y > 0.0:
			var t := ib
			ib = ic
			ic = t
		var fn := Vector3.UP
		for idx in [ia, ib, ic]:
			st.set_color(colors[idx])
			st.set_normal(fn)
			st.set_tangent(Plane(Vector3.UP, 1.0))
			st.set_uv2(Vector2(custom[idx * 4], custom[idx * 4 + 1]))
			st.add_vertex(verts[idx])

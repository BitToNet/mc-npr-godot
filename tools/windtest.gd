extends Node3D
## Isolated winding / culling test rig — flat triangles, which *are*
## discriminating: a convex solid sphere looks the same culled either way.
##
##   Godot --path . res://tools/windtest.tscn -- --shot=wind
##
## Row 1: triangle wound so (B-A)x(C-A) points TOWARD the camera.
## Row 2: the same triangle wound the other way.
## Row 3: the blob's first triangle (its top cap) verbatim.
## In each pair the LEFT sphere uses cull_back (red) and the RIGHT uses
## cull_front (blue): whichever one shows tells us which winding is front.

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.75, 0.88)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 11.0
	cam.position = Vector3(0, 0, 14)
	cam.current = true
	add_child(cam)

	# --- row 1: cross product towards the camera (+Z) ----------------------
	var a := Vector3(-1.1, -0.8, 0.0)
	var b := Vector3(1.1, -0.8, 0.0)
	var c := Vector3(0.0, 1.0, 0.0)
	var toward := _tri_mesh(a, b, c)
	print("[windtest] row1 cross=", (b - a).cross(c - a))
	_put(toward, Vector3(-2.6, 3.4, 0), "back")
	_put(toward, Vector3(2.6, 3.4, 0), "front")

	# --- row 2: cross product away from the camera (-Z) --------------------
	var away := _tri_mesh(a, c, b)
	print("[windtest] row2 cross=", (c - a).cross(b - a))
	_put(away, Vector3(-2.6, 0.0, 0), "back")
	_put(away, Vector3(2.6, 0.0, 0), "front")

	# --- row 3: verbatim first triangle of MeshUtil.blob -------------------
	var blob := MeshUtil.blob(1.6, 7, 12, Vector3.ONE, 0.0, RandomNumberGenerator.new(), Color.WHITE)
	var arrays := blob.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var top := _tri_mesh(v[0], v[1], v[2])
	print("[windtest] row3 blob first tri cross=", (v[1] - v[0]).cross(v[2] - v[0]),
			" stored normal=", n[0])
	_put(top, Vector3(-2.6, -3.4, 0), "back")
	_put(top, Vector3(2.6, -3.4, 0), "front")
	print("[windtest] pairs: LEFT = cull_back, RIGHT = cull_front; rows top->bottom: cross+toward, cross-away, blob-top-cap")


func _tri_mesh(p0: Vector3, p1: Vector3, p2: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := (p1 - p0).cross(p2 - p0).normalized()
	for p in [p0, p1, p2]:
		st.set_normal(n)
		st.set_color(Color.WHITE)
		st.add_vertex(p)
	return st.commit()


func _put(mesh: Mesh, at: Vector3, mode: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	var sh := Shader.new()
	if mode == "front":
		sh.code = "shader_type spatial; render_mode unshaded, cull_front; void fragment(){ ALBEDO = vec3(0.30,0.55,1.0); }"
	else:
		sh.code = "shader_type spatial; render_mode unshaded, cull_back; void fragment(){ ALBEDO = vec3(1.0,0.30,0.30); }"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	add_child(mi)

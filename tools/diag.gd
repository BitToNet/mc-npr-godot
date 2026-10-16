extends SceneTree
## Compares the emitted winding of hand-built meshes against Godot's own
## primitives, and dumps the normal/tangent attributes so the outline problem
## can be diagnosed from data instead of guesswork.

func _report(label: String, mesh: Mesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var t: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	print("--- ", label, "  verts=", v.size(), " tangents=", t.size() / 4)
	var up_faces := 0
	var down_faces := 0
	var tangent_ok := 0
	var tangent_bad := 0
	for f in v.size() / 3:
		var a := v[f * 3]
		var b := v[f * 3 + 1]
		var c := v[f * 3 + 2]
		var cross := (b - a).cross(c - a)
		if cross.y > 0.0:
			up_faces += 1
		else:
			down_faces += 1
		# is the stored normal aligned with the *outward* direction (away from the
		# mesh centre) and is the tangent usable for hull growth?
		var mid := (a + b + c) / 3.0
		if n.size() > f * 3 and n[f * 3].dot(mid) > 0.0:
			tangent_ok += 1
		else:
			tangent_bad += 1
	print("    triangles: cross.y>0 = ", up_faces, "   cross.y<=0 = ", down_faces)
	print("    stored normal points outward: ", tangent_ok, "   inward/degenerate: ", tangent_bad)
	if v.size() >= 3:
		print("    first tri v0=", v[0], " v1=", v[1], " v2=", v[2])
		print("    first tri cross=", (v[1] - v[0]).cross(v[2] - v[0]), " normal=", n[0] if n.size() > 0 else Vector3.ZERO)
		if t.size() >= 4:
			print("    first tri tangent=", Vector3(t[0], t[1], t[2]), " w=", t[3])


func _sphere_mesh() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 8
	s.rings = 5
	return s


func _initialize() -> void:
	_report("godot SphereMesh (reference)", _sphere_mesh())
	_report("godot SphereMesh through MeshUtil.facet", MeshUtil.facet(_sphere_mesh(), Color.WHITE))
	_report("MeshUtil.blob", MeshUtil.blob(1.0, 5, 8, Vector3.ONE, 0.0, RandomNumberGenerator.new(), Color.WHITE))
	_report("MeshUtil.cone", MeshUtil.cone(1.0, 2.0, 7, true, Color.WHITE))
	_report("MeshUtil.tapered_cylinder", MeshUtil.tapered_cylinder(1.0, 0.5, 2.0, 8, Color.WHITE))
	_report("MeshUtil.superellipse_prism", MeshUtil.superellipse_prism(2.0, 2.0, -1.0, 1.0, 4.0, 5, Color.WHITE, Color.WHITE, 1.0))
	var b := MeshUtil.blob(1.0, 5, 8, Vector3.ONE, 0.05, RandomNumberGenerator.new(), Color.WHITE)
	_report("blob after roughen", MeshUtil.roughen(b, 0.05, RandomNumberGenerator.new(), false))
	var cyl := CylinderMesh.new()
	_report("godot CylinderMesh through facet", MeshUtil.facet(cyl, Color.WHITE))
	print("DIAG DONE")
	quit()

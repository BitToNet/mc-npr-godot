class_name CloudField
extends Node3D
## Floating rain-clouds: chunky rounded low-poly puffs that drift across the
## diorama and cast long soft-edged shadows on the island below.  They are the
## main source of "the light is alive" motion in an otherwise still scene.

const COUNT := 10
const SPAN := Terrain.HALF + 9.0

## Clouds that drift into the camera's line of sight bury the figurine: with an
## orthographic lens a puff keeps its full screen size at any depth, so a cloud
## 20 m away still covers the character completely.  Radial distance is the
## wrong test for that, so each puff measures how far it sits from the lens axis
## through the character and shrinks away as it crosses.  Cloud shadows on the
## island are preserved -- only the ones actually in the way are suppressed.
const CLEAR_INNER := 5.0
const CLEAR_OUTER := 11.0

var drift := 0.36
var _clouds: Array[Node3D] = []
var _speeds: Array[float] = []
var _phases: Array[float] = []
var _base_scale: Array[Vector3] = []


func build(world_seed: int) -> void:
	for c in _clouds:
		if is_instance_valid(c):
			c.queue_free()
	_clouds.clear()
	_speeds.clear()
	_phases.clear()
	_base_scale.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 31337
	var meshes: Array[ArrayMesh] = []
	for k in 3:
		meshes.append(_cloud_mesh(rng))
	var mat := Style.toon({
		"shade_min": 0.70,
		"shade_max": 1.06,
		"rim": 0.45,
		"rim_color": Color(1.0, 0.98, 0.9),
		"spec": 0.0,
		"ink": 2.0,
	})
	for k in COUNT:
		var holder := Node3D.new()
		holder.name = "Cloud%d" % k
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[k % meshes.size()]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(mi)
		var s := rng.randf_range(0.55, 1.05)
		var scl := Vector3(s, s * rng.randf_range(0.78, 1.05), s * rng.randf_range(0.9, 1.25))
		holder.scale = scl
		_base_scale.append(scl)
		holder.position = Vector3(
			rng.randf_range(-SPAN, SPAN),
			rng.randf_range(15.5, 21.0),
			rng.randf_range(-SPAN, SPAN))
		holder.rotation.y = rng.randf_range(0.0, TAU)
		add_child(holder)
		_clouds.append(holder)
		_speeds.append(rng.randf_range(0.55, 1.25))
		_phases.append(rng.randf_range(0.0, TAU))


func _process(_delta: float) -> void:
	# S0.6: drift off the render clock, not off the real frame delta.  A variable
	# frame pacing used to shift every puff (and therefore every cloud shadow on
	# the island) between two otherwise identical runs.
	var ray := _view_ray()
	var origin: Vector3 = ray[0]
	var axis: Vector3 = ray[1]
	for i in _clouds.size():
		var c := _clouds[i]
		if not is_instance_valid(c):
			continue
		c.position.x += drift * _speeds[i] * Clock.dt
		c.rotation.y += Clock.dt * 0.02 * _speeds[i]
		# gentle bobbing so the shadow edges keep sliding over the terrain
		# (was Time.get_ticks_msec() * 0.00035, i.e. wall-clock in ms; that equals
		#  Clock.t * 0.35 for `t` in seconds — same rate, freezable clock)
		c.position.y += sin(Clock.t * 0.35 + _phases[i]) * Clock.dt * 0.35
		if c.position.x > SPAN:
			c.position.x = -SPAN
		# fade the puff away as it drifts across the lens axis
		var rel := c.position - origin
		var along := rel.dot(axis)
		# only puffs between the lens and the character can hide it
		var off_axis := (rel - axis * along).length() if along > 0.0 else 1.0e9
		var k := smoothstep(CLEAR_INNER, CLEAR_OUTER, off_axis)
		c.visible = k > 0.02
		c.scale = _base_scale[i] * k


## The point the lens is centred on: the followed figurine when there is one.
func _focus_point() -> Vector3:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p is Node3D:
		return (p as Node3D).global_position
	return global_position


## (origin, direction) of the lens axis, running from the character back towards
## the camera.  Falls back to straight down if the rig is not in the tree yet.
func _view_ray() -> Array:
	var focus := _focus_point()
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig != null and rig is Node3D:
		var axis := -(rig as Node3D).global_transform.basis.z
		if axis.length_squared() > 0.0001:
			return [focus, axis.normalized()]
	return [focus, Vector3.UP]


func _cloud_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var blobs: Array = []
	var puffs := 5
	for k in puffs:
		var r := rng.randf_range(0.85, 1.65)
		var b := MeshUtil.blob(r, 6, 9, Vector3(1.05, rng.randf_range(0.5, 0.72), 1.05), 0.12, rng,
				Color.WHITE)
		var pos := Vector3(
			rng.randf_range(-1.5, 1.5),
			rng.randf_range(-0.3, 0.5),
			rng.randf_range(-1.0, 1.0))
		blobs.append({"mesh": b, "xform": Transform3D(Basis(), pos)})
	var mesh := MeshUtil.combine(blobs)
	mesh = MeshUtil.roughen(mesh, 0.12, rng, false)
	# repaint: cool shadowed underside, warm bright top
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var ymin := 1e9
	var ymax := -1e9
	for v in verts:
		ymin = minf(ymin, v.y)
		ymax = maxf(ymax, v.y)
	var low := Style.pal("cloud_shade").srgb_to_linear()
	var high := Style.pal("cloud").srgb_to_linear()
	for i in verts.size():
		var t := smoothstep(0.0, 1.0, (verts[i].y - ymin) / maxf(ymax - ymin, 0.001))
		colors[i] = low.lerp(high, 0.25 + t * 0.75)
	var tmp := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
	arr[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
	arr[Mesh.ARRAY_COLOR] = colors
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return MeshUtil.facet_rebuild(tmp, verts)

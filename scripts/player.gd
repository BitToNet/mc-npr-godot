class_name Player
extends Node3D
## The clay figurine.
##
## Movement is camera relative WASD / arrows, and the body is glued to the very
## same analytic height field the island mesh was carved from — no physics
## jitter, no falling through, perfectly matching the visible surface.  A hop,
## a walk cycle and squash & stretch keep the toy feeling alive.

const SPEED := 5.4
const ACCEL := 15.0
const TURN_RATE := 12.0
const GRAVITY := 21.0
const JUMP_V := 6.6
const HOVER := 0.03

var terrain: Terrain
var camera_rig: CameraRig

var velocity := Vector3.ZERO
var facing := 0.0
var speed_ratio := 0.0

var _air := 0.0
var _jump_v := 0.0
var _grounded := true
var _squash := 0.0
var _anim_t := 0.0
var _model: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _mat: ShaderMaterial


func _ready() -> void:
	_build_model()


func reset_to(point: Vector3) -> void:
	position = Vector3(point.x, point.y, point.z)
	velocity = Vector3.ZERO
	_air = 0.0
	_jump_v = 0.0
	_grounded = true


func _physics_process(delta: float) -> void:
	if terrain == null:
		return
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
	if input.length() > 1.0:
		input = input.normalized()
	var yaw := camera_rig.yaw if camera_rig != null else 0.0
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)

	var target_vel := dir * SPEED
	velocity = velocity.lerp(target_vel, 1.0 - exp(-ACCEL * delta))
	speed_ratio = Vector2(velocity.x, velocity.z).length() / SPEED

	var nx := clampf(position.x + velocity.x * delta, -Terrain.HALF + 1.6, Terrain.HALF - 1.6)
	var nz := clampf(position.z + velocity.z * delta, -Terrain.HALF + 1.6, Terrain.HALF - 1.6)
	var gh := terrain.height_at(nx, nz)

	if _grounded and Input.is_action_just_pressed("jump"):
		_jump_v = JUMP_V
		_grounded = false
		_squash = -0.32
	if not _grounded:
		_jump_v -= GRAVITY * delta
		_air += _jump_v * delta
		if _air <= 0.0:
			_air = 0.0
			_jump_v = 0.0
			_grounded = true
			_squash = 0.34

	var target_y := gh + HOVER + _air
	var y := lerpf(position.y, target_y, 1.0 - exp(-18.0 * delta)) if _grounded else target_y
	position = Vector3(nx, y, nz)

	if dir.length() > 0.05:
		facing = lerp_angle(facing, atan2(dir.x, dir.z), 1.0 - exp(-TURN_RATE * delta))

	_animate(delta)


func _animate(delta: float) -> void:
	if _model == null:
		return
	_anim_t += delta * (5.0 + speed_ratio * 9.0)
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-9.0 * delta))
	_model.rotation.y = facing
	var bob := sin(_anim_t * 2.0) * 0.055 * speed_ratio
	var stretch := 0.0
	if not _grounded:
		stretch = clampf(_jump_v * 0.022, -0.10, 0.16)
	var sy := clampf(1.0 - _squash * 0.55 + stretch, 0.55, 1.45)
	var sxz := 1.0 + (1.0 - sy) * 0.7
	_model.scale = Vector3(sxz, sy, sxz)
	_model.position.y = bob
	_model.rotation.x = -speed_ratio * 0.10
	var swing := sin(_anim_t) * 0.7 * speed_ratio
	for i in _legs.size():
		_legs[i].rotation.x = swing * (1.0 if i == 0 else -1.0)
	for i in _arms.size():
		_arms[i].rotation.x = -swing * 0.8 * (1.0 if i == 0 else -1.0)


# ---------------------------------------------------------------------------
# model: capsules, spheres and rounded cones only — not a single cube
# ---------------------------------------------------------------------------
func _build_model() -> void:
	_mat = Style.toon({
		"shade_min": 0.44,
		"rim": 0.30,
		"rim_color": Color(1.0, 0.97, 0.88),
		"spec": 0.22,
		"spec_sharp": 24.0,
		"ink": 2.2,
	})
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	# torso
	var torso := CapsuleMesh.new()
	torso.radius = 0.33
	torso.height = 0.56
	torso.radial_segments = 10
	torso.rings = 4
	_add_part("Torso", torso, Style.pal("cloth"), Vector3(0, 0.78, 0), Vector3.ONE)

	# scarf ring
	var scarf := TorusMesh.new()
	scarf.inner_radius = 0.22
	scarf.outer_radius = 0.34
	scarf.rings = 8
	scarf.ring_segments = 8
	_add_part("Scarf", scarf, Style.pal("cloth_alt"), Vector3(0, 1.04, 0), Vector3(1, 0.7, 1))

	# backpack puff
	var pack := SphereMesh.new()
	pack.radius = 0.26
	pack.height = 0.52
	pack.radial_segments = 9
	pack.rings = 5
	_add_part("Pack", pack, Style.pal("cloth_alt"), Vector3(0, 0.84, -0.30), Vector3(1.0, 0.9, 0.8))

	# head + hair cap + eyes
	var head := SphereMesh.new()
	head.radius = 0.30
	head.height = 0.60
	head.radial_segments = 11
	head.rings = 6
	_add_part("Head", head, Style.pal("skin"), Vector3(0, 1.32, 0), Vector3(1.0, 0.94, 1.0))
	var hair := SphereMesh.new()
	hair.radius = 0.312
	hair.height = 0.624
	hair.is_hemisphere = true
	hair.radial_segments = 11
	hair.rings = 4
	_add_part("Hair", hair, Style.pal("hair"), Vector3(0, 1.335, -0.012), Vector3(1.0, 0.86, 1.0))
	var eye := SphereMesh.new()
	eye.radius = 0.052
	eye.height = 0.104
	eye.radial_segments = 6
	eye.rings = 4
	_add_part("EyeL", eye, Style.pal("hair"), Vector3(-0.115, 1.30, 0.262), Vector3.ONE)
	_add_part("EyeR", eye, Style.pal("hair"), Vector3(0.115, 1.30, 0.262), Vector3.ONE)

	# limbs
	var arm := CapsuleMesh.new()
	arm.radius = 0.095
	arm.height = 0.30
	arm.radial_segments = 8
	arm.rings = 3
	_arms.append(_add_part("ArmL", arm, Style.pal("cream"), Vector3(-0.40, 0.86, 0.0), Vector3.ONE))
	_arms.append(_add_part("ArmR", arm, Style.pal("cream"), Vector3(0.40, 0.86, 0.0), Vector3.ONE))
	_arms[0].rotation.z = 0.22
	_arms[1].rotation.z = -0.22

	var leg := CapsuleMesh.new()
	leg.radius = 0.115
	leg.height = 0.26
	leg.radial_segments = 8
	leg.rings = 3
	# the leg holders sit on the hip line, the capsule hangs 0.26 m below it,
	# so rotating the holder swings the leg from the hip.
	_legs.append(_add_part("LegL", leg, Style.pal("hair"), Vector3(-0.155, 0.52, 0.0), Vector3.ONE, Vector3(0, -0.265, 0)))
	_legs.append(_add_part("LegR", leg, Style.pal("hair"), Vector3(0.155, 0.52, 0.0), Vector3.ONE, Vector3(0, -0.265, 0)))


func _add_part(name: String, src: Mesh, tint: Color, pivot: Vector3, scl: Vector3,
		mesh_offset := Vector3.ZERO) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = MeshUtil.facet(src, tint.srgb_to_linear())
	mi.material_override = _mat
	mi.position = mesh_offset
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var holder := Node3D.new()
	holder.name = name + "Pivot"
	holder.position = pivot
	holder.scale = scl
	holder.add_child(mi)
	_model.add_child(holder)
	return holder

class_name CameraRig
extends Node3D
## Orthographic isometric camera on a damped follow rig.
##
##   FOLLOW : locked isometric angle, glides after the figurine
##   ORBIT  : same, but the whole diorama slowly revolves (自转)
##   FREE   : Q / E orbit by hand, wheel zooms, no auto rotation
## A practical camera-attributes resource adds a subtle macro-lens blur so the
## scene keeps reading as a photograph of a tiny physical object.

enum Mode { FOLLOW, ORBIT, FREE }

const PITCH := deg_to_rad(-35.264)      # true isometric elevation
const MODE_NAMES := ["FOLLOW", "ORBIT", "FREE"]

var yaw := deg_to_rad(45.0)
var mode: int = Mode.ORBIT
var target: Node3D
var orbit_speed := 0.12
var distance := 70.0
var ortho_size := 38.0
var follow_rate := 7.0

var _camera: Camera3D
var _attrs: CameraAttributesPractical
var _focus := Vector3.ZERO
var _lead := Vector3.ZERO


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = ortho_size
	_camera.near = 1.0
	_camera.far = 420.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_attrs = CameraAttributesPractical.new()
	_attrs.dof_blur_far_enabled = true
	_attrs.dof_blur_far_distance = 78.0
	_attrs.dof_blur_far_transition = 30.0
	_attrs.dof_blur_near_enabled = true
	_attrs.dof_blur_near_distance = 40.0
	_attrs.dof_blur_near_transition = 18.0
	_attrs.dof_blur_amount = 0.06
	_camera.attributes = _attrs
	_camera.current = true
	add_child(_camera)
	_apply()
	_publish_pixel_span()


func snap_to(point: Vector3) -> void:
	_focus = point
	position = _focus
	_apply()


func cycle_mode() -> int:
	mode = (mode + 1) % 3
	return mode


func mode_name() -> String:
	return MODE_NAMES[mode]


func _process(delta: float) -> void:
	if Input.is_action_pressed("zoom_in"):
		ortho_size = clampf(ortho_size - delta * 24.0, 12.0, 56.0)
	if Input.is_action_pressed("zoom_out"):
		ortho_size = clampf(ortho_size + delta * 24.0, 12.0, 56.0)
	if Input.is_action_pressed("orbit_left"):
		yaw -= delta * 1.25
		if mode == Mode.ORBIT:
			mode = Mode.FREE
	if Input.is_action_pressed("orbit_right"):
		yaw += delta * 1.25
		if mode == Mode.ORBIT:
			mode = Mode.FREE
	if mode == Mode.ORBIT:
		yaw += orbit_speed * delta

	if target != null and is_instance_valid(target):
		var t := target.global_position
		_lead = _lead.lerp(t, 1.0 - exp(-3.0 * delta))
		var want := _lead
		if mode != Mode.FREE:
			_focus = _focus.lerp(want, 1.0 - exp(-follow_rate * delta))
		else:
			_focus = _focus.lerp(t, 1.0 - exp(-follow_rate * 0.5 * delta))
		_focus.x = clampf(_focus.x, -22.0, 22.0)
		_focus.z = clampf(_focus.z, -22.0, 22.0)
		_focus.y = clampf(_focus.y, 0.0, 9.0)
		position = _focus
	_apply()


func _apply() -> void:
	if _camera == null:
		return
	rotation = Vector3(PITCH, yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.size = ortho_size
	_publish_pixel_span()


## Tells the outline shader how much world space one pixel covers, so ink stays
## a constant pixel weight no matter how far the camera is zoomed.
func _publish_pixel_span() -> void:
	var h := 900.0
	var vp := get_viewport()
	if vp != null:
		h = maxf(vp.get_visible_rect().size.y, 1.0)
	Style.set_pixel_span(ortho_size / h)


func shake(a: float) -> void:
	## reserved for landing impacts
	ortho_size = clampf(ortho_size + a * 0.0, 12.0, 56.0)
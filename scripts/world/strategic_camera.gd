class_name StrategicCamera
extends Node3D
## Warband-style strategic camera (S1.2e; supersedes S1.2c's pan + tiered zoom).
##
## The camera is **anchored on the player party**: `set_follow_point()` receives the
## mover's ground position on every logical tick, and the focus eases onto it at
## `FOLLOW_RATE`.  That is the Mount & Blade campaign-map feel — you orbit your own
## party, you never lose it, and there is no free pan to lose it with.
##
## Zoom is therefore continuous, not tiered: one wheel notch multiplies the vertical
## span by `ZOOM_STEP` and the span is eased (`ZOOM_RATE`), so 120 m … 2600 m is one
## smooth range.  `set_tier()` survives only as a **capture/verification preset**
## (2600 / 700 / 170 m, the three spans the `B-` plates are shot at).
##
## The old clamp now does double duty.  `bounds_half()` is
## `map/2 − size_target/2 − MARGIN`, which is **0 at full zoom-out**, so the follow
## point collapses onto the map centre there — the whole-map plate stays
## byte-identical without a `if tier == GLOBAL` special case.
##
## Two deliberate simplifications (unchanged from S1.2c):
##   * the rig itself stays at the origin and the child `Camera3D` carries the
##     whole transform.  That keeps "rig-local == world" true off tree, which is
##     how the trajectory case drives it (no `get_tree()` in `--script` mode).
##   * the camera is the only thing that knows about the terrain: it raises
##     itself to `height_at(cam) + GROUND_CLEAR` so it can never end up inside a
##     hill at the close tiers.
##
## `step()` is the single integration entry point: `_process` feeds it real input,
## the case feeds it a scripted trajectory.  Same code, so what the case proves is
## what the player gets.

enum Tier { GLOBAL, REGION, LOCAL }
enum Lens { ORTHO, PERSP }   # Projection collides with Godot's builtin type

const TIER_NAMES := ["GLOBAL", "REGION", "LOCAL"]
const TIER_SIZE := [2600.0, 700.0, 170.0]

## Continuous zoom range, metres of vertical span.  `MIN_SIZE` is ~3.75 terrain
## cells (the mesh is 32 m), i.e. as close as the low-poly ground still reads.
const MIN_SIZE := 120.0
const MAX_SIZE := 2600.0
const ZOOM_STEP := 1.12        ## span multiplier per wheel notch
## Band edges for the *report*: they only label a span, they do not gate behaviour.
const BAND_GLOBAL_MIN := 2000.0
const BAND_REGION_MIN := 400.0
## At or beyond this span the whole map is in frame, so the plate must be ortho.
const FULL_ORTHO_SIZE := 2300.0

const FOV_DEG := 35.0
const ISO_YAW_DEG := 45.0
const ISO_PITCH_DEG := -35.264
const PITCH_MIN_DEG := -75.0
const PITCH_MAX_DEG := -20.0

const FOLLOW_RATE := 8.0       ## exponential damping for the focus point
const ZOOM_RATE := 6.0         ## exponential easing for the span (~0.35 s)
const MARGIN := 40.0           ## metres of map edge kept inside the frame
const GROUND_CLEAR := 3.0      ## camera never closer than this to the terrain
const ORTHO_DIST_FACTOR := 1.35
const MIN_DIST := 320.0
const ZOOM_STEP_COOLDOWN := 0.18
const ROTATE_GAIN := 0.006     ## right-drag radians per pixel
const PITCH_GAIN := 0.004      ## right-drag radians per pixel (vertical)

var field: HeightField
var tier := Tier.GLOBAL
var projection := Lens.ORTHO
var focus := Vector3.ZERO
var focus_target := Vector3.ZERO
var size: float = TIER_SIZE[0]
var size_target: float = TIER_SIZE[0]
var yaw := deg_to_rad(ISO_YAW_DEG)
var pitch := deg_to_rad(ISO_PITCH_DEG)

## True while the camera is anchored on the party.  `focus_on()` turns it off so the
## capture stage can frame a settlement; `set_follow(true)` resumes it.
var follow_enabled := true
## The party's ground position, refreshed by the map on every logical tick.
var follow_point := Vector3.ZERO

var _camera: Camera3D
var _wheel := 0.0
var _cooldown := 0.0
var _dragging := false


func setup(p_field: HeightField) -> void:
	field = p_field
	tier = Tier.GLOBAL
	projection = Lens.ORTHO
	size = MAX_SIZE
	size_target = MAX_SIZE
	yaw = deg_to_rad(ISO_YAW_DEG)
	pitch = deg_to_rad(ISO_PITCH_DEG)
	follow_enabled = true
	follow_point = Vector3.ZERO
	focus_target = Vector3.ZERO
	_clamp_focus()
	focus = focus_target
	_ensure_camera()
	_apply()


func _ready() -> void:
	_ensure_camera()
	_apply()


## Keyboard orbit only (`Q`/`E` = yaw, `R`/`F` = pitch): panning is gone, so the
## arrow keys no longer touch the camera, and WASD stays free for S1.6 / S4.5.
func _process(delta: float) -> void:
	if field == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	var turn := 0.0
	if Input.is_key_pressed(KEY_Q):
		turn -= 1.0
	if Input.is_key_pressed(KEY_E):
		turn += 1.0
	var tilt := 0.0
	if Input.is_key_pressed(KEY_R):
		tilt += 1.0
	if Input.is_key_pressed(KEY_F):
		tilt -= 1.0
	step(delta, turn * delta * 0.9, tilt * delta * 0.5)
	# The wheel accumulates raw notches; one is spent per cooldown here (not in the
	# input handler) so a fast spin becomes a steady zoom instead of a burst of
	# notches that only fire when some unrelated event wakes the handler up.
	if absf(_wheel) >= 1.0 and _cooldown <= 0.0:
		var notch := signf(_wheel)
		_wheel -= notch
		_cooldown = ZOOM_STEP_COOLDOWN
		zoom_by(notch)


func _unhandled_input(event: InputEvent) -> void:
	if field == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# Right-drag orbits; release ends it even outside the window.
			_dragging = mb.pressed
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_wheel += 1.0
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel -= 1.0
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		# Drag the world with the hand: right-drag spins the map right (yaw down),
		# drag-down lowers the camera (pitch toward the horizon).
		rotate_view(-mm.relative.x * ROTATE_GAIN, mm.relative.y * PITCH_GAIN)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			toggle_projection()
		elif event.keycode == KEY_T:
			cycle_tier(-1)


## One integration step.  `yaw_delta` / `pitch_delta` are radians.  The span eases
## toward `size_target`; the focus eases toward the follow point (clamped to the
## current legal area).  There is no pan input, by design.
func step(delta: float, yaw_delta := 0.0, pitch_delta := 0.0) -> void:
	if field == null or delta <= 0.0:
		return
	if yaw_delta != 0.0:
		yaw = wrapf(yaw + yaw_delta, -PI, PI)
	if pitch_delta != 0.0:
		pitch = clampf(pitch + pitch_delta, deg_to_rad(PITCH_MIN_DEG),
				deg_to_rad(PITCH_MAX_DEG))
	# easing the span is what makes a zoom read as a zoom, not a cut
	size = lerpf(size, size_target, 1.0 - exp(-delta * ZOOM_RATE))
	tier = _band_of(size_target)
	if follow_enabled:
		focus_target.x = follow_point.x
		focus_target.z = follow_point.z
		_clamp_focus()
	if tier == Tier.LOCAL:
		focus_target.y = _ground(focus_target.x, focus_target.z)
	else:
		focus_target.y = 0.0
	focus = focus.lerp(focus_target, 1.0 - exp(-delta * FOLLOW_RATE))
	_apply()


## Hands the party's ground position to the camera (called from the logical tick).
func set_follow_point(point: Vector3) -> void:
	follow_point = point
	if follow_enabled:
		focus_target.x = point.x
		focus_target.z = point.z
		_clamp_focus()


## Anchors (`true`) or releases (`false`) the camera.  Releasing is what lets the
## capture stage frame a settlement with `focus_on()`; re-anchoring snaps the target
## back onto the party, and the damping does the rest.
func set_follow(enabled: bool) -> void:
	follow_enabled = enabled
	if enabled:
		focus_target.x = follow_point.x
		focus_target.z = follow_point.z
		_clamp_focus()
		if tier == Tier.LOCAL:
			focus_target.y = _ground(focus_target.x, focus_target.z)
		_apply()


## Continuous zoom: `notches` > 0 zooms in (smaller span).  Past `FULL_ORTHO_SIZE`
## the projection is forced back to ortho — the whole-map plate must stay ortho.
func zoom_by(notches: float) -> void:
	if field == null or notches == 0.0:
		return
	size_target = clampf(size_target / pow(ZOOM_STEP, notches), MIN_SIZE, MAX_SIZE)
	tier = _band_of(size_target)
	if size_target >= FULL_ORTHO_SIZE:
		projection = Lens.ORTHO
	_clamp_focus()
	_apply()


## Orbit by hand (right-drag).  Same clamps as the keyboard path.
func rotate_view(dyaw: float, dpitch: float) -> void:
	if dyaw != 0.0:
		yaw = wrapf(yaw + dyaw, -PI, PI)
	if dpitch != 0.0:
		pitch = clampf(pitch + dpitch, deg_to_rad(PITCH_MIN_DEG),
				deg_to_rad(PITCH_MAX_DEG))
	_apply()


## Capture / verification preset.  Not the gameplay zoom any more: the wheel goes
## through `zoom_by()`.  GLOBAL still resets yaw/pitch to the isometric bearing and
## clears the projection toggle, which is what keeps the whole-map plate fixed.
func set_tier(t: int) -> void:
	tier = clampi(t, 0, Tier.LOCAL)
	size_target = TIER_SIZE[tier]
	if tier == Tier.GLOBAL:
		# the global shot is the map plate: fixed isometric bearing, ortho only
		projection = Lens.ORTHO
		yaw = deg_to_rad(ISO_YAW_DEG)
		pitch = deg_to_rad(ISO_PITCH_DEG)
	# Both the target *and* the current point are clamped: zooming out shrinks the
	# legal area, and a lagging focus must not be allowed to stay outside it while
	# the damping catches up.
	_clamp_focus()
	if tier == Tier.LOCAL:
		focus_target.y = _ground(focus_target.x, focus_target.z)
	else:
		focus_target.y = 0.0
	_apply()


func cycle_tier(step_count: int) -> void:
	set_tier(tier + step_count)


## Jumps straight to the tier's final framing (`size`, `focus`) instead of easing
## into it.  Tooling needs this: a screenshot taken 15 frames after `set_tier()`
## would otherwise catch the zoom half-way, and two "same tier" shots would not be
## the same picture (S1.2d).
func snap_to_target() -> void:
	size = size_target
	tier = _band_of(size_target)
	if follow_enabled:
		focus_target.x = follow_point.x
		focus_target.z = follow_point.z
		_clamp_focus()
	focus = focus_target
	if tier == Tier.LOCAL:
		focus.y = _ground(focus.x, focus.z)
		focus_target.y = focus.y
	else:
		focus.y = 0.0
		focus_target.y = 0.0
	_apply()


## Points the camera at a world position on the XZ plane, clamped to the current
## legal area and snapped.  Used by the shot tool to frame a settlement instead of
## wherever the party happens to be — so it **detaches the follow** first.
func focus_on(x: float, z: float) -> void:
	follow_enabled = false
	tier = _band_of(size_target)
	focus_target = Vector3(x, 0.0, z)
	_clamp_focus()
	focus_target.y = _ground(focus_target.x, focus_target.z) if tier == Tier.LOCAL else 0.0
	snap_to_target()


func toggle_projection() -> void:
	if size_target >= FULL_ORTHO_SIZE:
		projection = Lens.ORTHO
		_apply()
		return
	projection = Lens.PERSP if projection == Lens.ORTHO else Lens.ORTHO
	_apply()


## How far the focus point may travel from the map centre while keeping
## `MARGIN` metres of map inside the frame.  The whole-map span yields 0, so at full
## zoom-out the follow point collapses onto the centre instead of drifting into
## empty space.
func bounds_half() -> float:
	if field == null:
		return 0.0
	var h := field.map_size * 0.5 - size_target * 0.5 - MARGIN
	return maxf(h, 0.0)


## The rig itself never moves — only the child `Camera3D` does — so the camera's
## local Y *is* its world Y.  Reading `global_position` would log an error when
## the mesh is driven off tree (verify does that), which is why this stays local.
func camera_y() -> float:
	return _camera.position.y if _camera != null else 0.0


## World position → screen position.  UI markers and the click test both need it;
## keeping it here means the projection matrix is read from the one `Camera3D`
## that actually renders, instead of a second camera that could drift.
func screen_of(world: Vector3) -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	return _camera.unproject_position(world)


## Screen point → ground point (S1.3c click-to-move).
##
## The terrain is a bare `ArrayMesh` with no colliders, so a physics raycast would
## hit nothing.  Instead the view ray is stepped in 4 m slices until it goes below
## `height_at`, then bisected 10 times: the returned XZ is accurate to well under
## a metre, and the returned Y is the **ground height**, not the ray hit, so the
## caller can hand it straight to `order_to`.
func pick_ground(screen: Vector2) -> Dictionary:
	var miss := {"ok": false, "point": Vector3.ZERO, "reason": ""}
	if field == null or _camera == null:
		miss["reason"] = "相机或地形未就绪"
		return miss
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if dir.y > -0.0001:
		miss["reason"] = "视线不朝地面"
		return miss
	# Standing under the ground (camera hugging a hill): treat the cursor as the
	# point below it rather than reporting a miss the player cannot understand.
	var h0 := origin.y - field.height_at(origin.x, origin.z)
	if h0 <= 0.0:
		return {"ok": true, "point": Vector3(origin.x, field.height_at(origin.x, origin.z),
				origin.z), "reason": ""}
	# 注意：正交档的 `project_ray_origin()` 会落在**地图之外**（相机后撤 3 500 m），所以
	# 不能拿"采样点越界"当提前退出的条件 —— 那会在第一步就误判成 miss。改成先按
	# "相机高度 + 余量" 估一个足够长的上限，命中之后再判是否落在地界内。
	var step := 4.0
	var limit := minf((absf(origin.y) + 800.0) / maxf(0.05, absf(dir.y)), 30000.0)
	var t_prev := 0.0
	var t := 0.0
	while t <= limit:
		t += step
		var p := origin + dir * t
		if p.y - field.height_at(p.x, p.z) <= 0.0:
			var lo := t_prev
			var hi := t
			for i in 10:
				var mid := (lo + hi) * 0.5
				var mp := origin + dir * mid
				if mp.y - field.height_at(mp.x, mp.z) > 0.0:
					lo = mid
				else:
					hi = mid
			var hit := origin + dir * hi
			if absf(hit.x) > field.half_size or absf(hit.z) > field.half_size:
				miss["reason"] = "点击落在地界之外"
				return miss
			return {"ok": true, "point": Vector3(hit.x, field.height_at(hit.x, hit.z),
					hit.z), "reason": ""}
		t_prev = t
	miss["reason"] = "视线没有落在地界内"
	return miss


func report() -> Dictionary:
	return {
		"tier": tier,
		"tier_name": TIER_NAMES[tier],
		"projection": "PERSP" if projection == Lens.PERSP else "ORTHO",
		"size": size,
		"size_target": size_target,
		"min_size": MIN_SIZE,
		"max_size": MAX_SIZE,
		"focus": focus,
		"focus_target": focus_target,
		"follow": follow_enabled,
		"follow_point": follow_point,
		"yaw_deg": rad_to_deg(yaw),
		"pitch_deg": rad_to_deg(pitch),
		"bounds_half": bounds_half(),
		"camera_y": camera_y(),
		"ground_y": _ground(focus.x, focus.z),
		"current": _camera != null and _camera.current,
		"far": _camera.far if _camera != null else 0.0,
	}


func _ensure_camera() -> void:
	if _camera != null:
		return
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.near = 1.0
	_camera.far = 12000.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.current = true
	add_child(_camera)


## Band label for the report (and for `focus.y` behaviour).  Derived from the span,
## never the other way round — that is what makes continuous zoom and the capture
## presets share one truth.
func _band_of(span: float) -> int:
	if span >= BAND_GLOBAL_MIN:
		return Tier.GLOBAL
	if span >= BAND_REGION_MIN:
		return Tier.REGION
	return Tier.LOCAL


## Clamps the target *and* the lagging current point, so a zoom-out cannot leave the
## focus outside the shrunken legal area while the damping catches up.
func _clamp_focus() -> void:
	var bound := bounds_half()
	focus_target.x = clampf(focus_target.x, -bound, bound)
	focus_target.z = clampf(focus_target.z, -bound, bound)
	focus.x = clampf(focus.x, -bound, bound)
	focus.z = clampf(focus.z, -bound, bound)


func _ground(x: float, z: float) -> float:
	if field == null:
		return 0.0
	return field.height_at(x, z)


func _distance() -> float:
	if projection == Lens.PERSP:
		return size / (2.0 * tan(deg_to_rad(FOV_DEG) * 0.5))
	return maxf(size * ORTHO_DIST_FACTOR, MIN_DIST)


func _apply() -> void:
	if _camera == null:
		return
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE \
			if projection == Lens.PERSP else Camera3D.PROJECTION_ORTHOGONAL
	_camera.fov = FOV_DEG
	_camera.size = size
	var offset := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) \
			* _distance()
	var cam_pos := focus + offset
	# the camera lifts itself instead of clipping through a hill
	cam_pos.y = maxf(cam_pos.y, _ground(cam_pos.x, cam_pos.z) + GROUND_CLEAR)
	var forward := (focus - cam_pos).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward)
	_camera.transform = Transform3D(Basis(right, up, -forward), cam_pos)

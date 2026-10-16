extends Node
## Capture — headless-ish screenshot harness used while developing the look.
##
##   Godot --path . -- --shots
##   Godot --path . -- --shot=noon --time=0.5 --mode=follow --size=30
##
## Writes PNGs into res://.shots/ then quits, so the art direction can be
## reviewed as real rendered frames instead of guesses.

var _enabled := false
var _shots: Array = []
var _out_dir := "res://.shots"
var _quit := true
var _bench := false
var _single := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var single := _single
	var want := false
	for a in args:
		if a == "--shots":
			want = true
		elif a.begins_with("--shot="):
			want = true
			single["name"] = a.split("=", true, 1)[1]
		elif a.begins_with("--time="):
			single["time"] = a.split("=", true, 1)[1].to_float()
		elif a.begins_with("--mode="):
			single["mode"] = a.split("=", true, 1)[1]
		elif a.begins_with("--size="):
			single["size"] = a.split("=", true, 1)[1].to_float()
		elif a.begins_with("--yaw="):
			single["yaw"] = a.split("=", true, 1)[1].to_float()
		elif a.begins_with("--outline="):
			want = true
			single["outline"] = a.split("=", true, 1)[1]
		elif a.begins_with("--bands="):
			want = true
			single["bands"] = a.split("=", true, 1)[1].to_int()
		elif a == "--bench":
			want = true
			_bench = true
		elif a == "--nowater":
			want = true
			single["nowater"] = true
		elif a == "--noenv":
			want = true
			single["noenv"] = true
		elif a.begins_with("--ink="):
			want = true
			single["ink"] = a.split("=", true, 1)[1].to_float()
		elif a.begins_with("--nodof"):
			want = true
			single["nodof"] = true
		elif a.begins_with("--out="):
			want = true
			_out_dir = a.split("=", true, 1)[1]
		elif a == "--noquit":
			_quit = false
	if not want:
		set_process(false)
		return
	_enabled = true
	_shots = [single] if not single.is_empty() else [
		{"name": "01_dawn", "time": 0.275, "mode": "FOLLOW", "size": 40.0, "yaw": 45.0},
		{"name": "02_noon", "time": 0.50, "mode": "FOLLOW", "size": 36.0, "yaw": 45.0},
		{"name": "03_dusk", "time": 0.735, "mode": "FOLLOW", "size": 38.0, "yaw": 52.0},
		{"name": "04_night", "time": 0.92, "mode": "FOLLOW", "size": 36.0, "yaw": 45.0},
		{"name": "05_closeup", "time": 0.40, "mode": "FREE", "size": 16.0, "yaw": 35.0},
		{"name": "06_wide", "time": 0.33, "mode": "FREE", "size": 66.0, "yaw": 40.0},
	]
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# let the world build + a few frames of wave/wind animation settle
	for i in 40:
		await get_tree().process_frame
	if _bench:
		await _benchmark()
		if _quit:
			get_tree().quit()
		return
	for shot in _shots:
		_apply(shot)
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [_out_dir, String(shot.get("name", "shot"))]
		var err := img.save_png(path)
		print("[capture] ", path, " -> ", error_string(err))
	print("[capture] done")
	if _quit:
		get_tree().quit()


## Steady state performance probe: warms up, then reports averaged FPS for a
## few seconds so the README number is not a first frame shader compile hitch.
func _benchmark() -> void:
	for i in 120:
		await get_tree().process_frame
	var windows := [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
	var fps: Array = []
	for w in windows:
		var frames := 0
		var t0 := Time.get_ticks_usec()
		while (Time.get_ticks_usec() - t0) < int(w * 1000000.0):
			await get_tree().process_frame
			frames += 1
		var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
		fps.append(snappedf(float(frames) / dt, 0.1))
		print("[bench] %.1f fps" % (float(frames) / dt))
	var total := 0.0
	for f in fps:
		total += f
	print("[bench] average %.1f fps at 1600x900" % (total / fps.size()))
	print("[bench] ms/frame %.2f" % (1000.0 / (total / fps.size())))


func _apply(shot: Dictionary) -> void:
	var rig := get_tree().get_first_node_in_group("camera_rig")
	var dn := get_tree().get_first_node_in_group("day_night")
	var pl := get_tree().get_first_node_in_group("player")
	if dn != null:
		dn.set_auto_cycle(false)
		if shot.has("time"):
			dn.set_time(float(shot["time"]))
	if rig == null:
		return
	if shot.has("mode"):
		var m := String(shot["mode"]).to_upper()
		if m == "FOLLOW":
			rig.mode = 0
		elif m == "ORBIT":
			rig.mode = 1
		else:
			rig.mode = 2
	if shot.has("size"):
		rig.ortho_size = float(shot["size"])
	if shot.has("outline"):
		var on := String(shot["outline"]).to_lower() in ["1", "on", "true", "yes"]
		Style.set_outline(on)
	if shot.has("nowater"):
		var w := get_tree().get_first_node_in_group("water")
		if w != null:
			w.visible = false
	if shot.has("noenv"):
		# neutralise post processing to check the raw shading
		var m := get_tree().get_first_node_in_group("main")
		if m != null:
			var we: WorldEnvironment = m.get_node_or_null("WorldEnvironment")
			if we != null and we.environment != null:
				we.environment.adjustment_enabled = false
				we.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	if shot.has("ink"):
		Style.set_ink_scale(float(shot["ink"]))
	if shot.has("bands"):
		Style.build_ramp(int(shot["bands"]))
	if shot.has("nodof") and rig._attrs != null:
		rig._attrs.dof_blur_far_enabled = false
		rig._attrs.dof_blur_near_enabled = false
	if shot.has("yaw"):
		rig.yaw = deg_to_rad(float(shot["yaw"]))
	if pl != null:
		rig.snap_to(pl.global_position)
	rig._apply()

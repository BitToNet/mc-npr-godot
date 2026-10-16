extends Node
## Capture — headless-ish screenshot harness used while developing the look.
##
##   Godot --path . -- --shots
##   Godot --path . -- --shot=noon --time=0.5 --mode=follow --size=30
##   Godot --path . -- --shots --case=s0_boot     # S0.2: named batch case table
##   Godot --path . -- --shots --case=s0_boot --frames=24 --warmup=60
##   Godot --path . -- --shots --case=s0_boot --clock-hz=30   # 时钟步长
##   Godot --path . -- --shots --case=s0_boot --realtime      # 关掉可复现性
##
## Writes PNGs into res://.shots/ then quits, so the art direction can be
## reviewed as real rendered frames instead of guesses.
##
## S0.6 — reproducibility.  A capture batch now runs on the deterministic render
## clock (`scripts/render_clock.gd`) by default, so the same case run twice in two
## separate processes yields **byte-identical** PNGs and the `B-` gate can use a
## tight `img_diff` threshold.  `--realtime` restores real frame deltas for
## eyeballing motion (and makes captures non-reproducible again, by design).
## `--bench` always measures on the real clock.
##
## S0.2 additions (all additive — the legacy `--shots` / `--shot=` behaviour and
## the default 6-shot batch are byte-for-byte unchanged):
##   * `--shots --case=<name>`  pick a named batch from CASES (unknown name = exit 1)
##   * `--frames=<n>`   settle frames after applying a shot (default 10)
##   * `--warmup=<n>`   warm-up frames before the first shot (default 40)
##   * a machine-readable manifest `<out>/<case>.json` listing every PNG with
##     size + sha256, so B- class evidence can be anchored and diffed later.
##
## ⚠️ Trigger flags vs modifiers: only `--shots` / `--shot=` / `--capture` /
## `--bench` (plus the legacy look flags `--outline= --bands= --ink= --nodof
## --nowater --noenv`) turn the capture batch on. `--case=` / `--out=` /
## `--frames=` / `--warmup=` are modifiers only. They must NOT self-trigger,
## because `tools/verify.gd` uses the same `--case=` / `--out=` names for the
## acceptance runner; otherwise a verify subprocess would additionally launch a
## screenshot batch whose `quit(1)` clobbers the runner's exit code.

## Named batch table.  "default" must stay identical to the historic 6-shot run
## so existing art-regression baselines keep comparing apples to apples.
const CASES := {
	"default": [
		{"name": "01_dawn", "time": 0.275, "mode": "FOLLOW", "size": 40.0, "yaw": 45.0},
		{"name": "02_noon", "time": 0.50, "mode": "FOLLOW", "size": 36.0, "yaw": 45.0},
		{"name": "03_dusk", "time": 0.735, "mode": "FOLLOW", "size": 38.0, "yaw": 52.0},
		{"name": "04_night", "time": 0.92, "mode": "FOLLOW", "size": 36.0, "yaw": 45.0},
		{"name": "05_closeup", "time": 0.40, "mode": "FREE", "size": 16.0, "yaw": 35.0},
		{"name": "06_wide", "time": 0.33, "mode": "FREE", "size": 66.0, "yaw": 40.0},
	],
	## S0.1 art-regression gate: the canonical "before/after reorg" viewpoint.
	"s0_boot": [
		{"name": "s0_boot_follow", "time": 0.50, "mode": "FOLLOW", "size": 36.0, "yaw": 45.0},
		{"name": "s0_boot_wide", "time": 0.33, "mode": "FREE", "size": 66.0, "yaw": 40.0},
	],
	## S0.3 batch 4 — the save menu / 3x3 grid (B- evidence for ROADMAP §5 S0.3).
	##
	## Split into two batches of two shots because the two data states cannot both
	## be photographed by one process: the "empty" state needs no save files at all
	## and the "full" state needs nine of them.  `s0_3_slots` swaps `user://saves`
	## and spawns one child per batch, so neither PNG can depend on whatever the
	## developer happens to have saved.
	##
	## `ui` steps drive the **real** UI through injected input events — product code
	## gets no "demo state" hook.  They are deltas: the second shot of a batch
	## continues from the state the first shot left behind.  `ui_expect` then makes
	## the driver prove it arrived: a mismatch is a non-zero exit, never a quiet
	## picture of the wrong screen.
	##
	## Node paths are relative to the menu node itself and include its `Root`
	## wrapper (`menu_page.gd` builds `Root` so that a single Backdrop can swallow
	## clicks aimed at the debug HUD underneath).
	"s0_3_menu_empty": [
		{"name": "01_menu_home", "time": 0.33, "mode": "FREE", "size": 52.0, "yaw": 40.0,
			"ui": ["esc"], "ui_expect": {"open": true, "page": "home", "confirm": false}},
		{"name": "02_grid_empty", "time": 0.33, "mode": "FREE", "size": 52.0, "yaw": 40.0,
			"ui": ["click:Root/Home/Panel/Col/Actions/SaveAs"],
			"ui_expect": {"open": true, "page": "grid", "confirm": false}},
	],
	"s0_3_menu_full": [
		{"name": "03_grid_full", "time": 0.33, "mode": "FREE", "size": 52.0, "yaw": 40.0,
			"ui": ["esc", "click:Root/Home/Panel/Col/Actions/SaveAs"],
			"ui_expect": {"open": true, "page": "grid", "confirm": false}},
		{"name": "04_overwrite_confirm", "time": 0.33, "mode": "FREE", "size": 52.0, "yaw": 40.0,
			"ui": ["click:Root/GridPage/Panel/Col/Grid/Col/Cards/Slot3"],
			"ui_expect": {"open": true, "page": "grid", "confirm": true}},
	],
}

var _enabled := false
var _shots: Array = []
var _out_dir := "res://.shots"
var _quit := true
var _bench := false
var _single := {}
var _case_name := ""
var _manifest_label := ""
var _frames := 10
var _warmup := 40
var _realtime := false
var _clock_hz := 60.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var single := _single
	var want := false
	for a in args:
		if a == "--shots" or a == "--capture":
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
			# 仅作修饰符，不再单独触发截图批次：`--case=` / `--out=` 与
			# tools/verify.gd 的验收运行器同名同源（都读 OS.get_cmdline_user_args），
			# 若它们本身就能唤醒 Capture，跑验收用例时会连带触发一次截图批次，
			# 并由 Capture 的 get_tree().quit(1) 覆盖掉运行器的退出码。
			# ⇒ 想截图必须显式给出 --shots / --shot= / --capture / --bench。
			_out_dir = a.split("=", true, 1)[1]
		elif a.begins_with("--case="):
			_case_name = a.split("=", true, 1)[1]
		elif a.begins_with("--frames="):
			_frames = a.split("=", true, 1)[1].to_int()
		elif a.begins_with("--warmup="):
			_warmup = a.split("=", true, 1)[1].to_int()
		elif a == "--realtime":
			# S0.6 escape hatch: keep the clock on real frame deltas.  Captures then
			# stop being byte-reproducible (that is the whole point of --realtime),
			# so it is only for eyeballing motion, never for B- evidence.
			_realtime = true
		elif a.begins_with("--clock-hz="):
			_clock_hz = a.split("=", true, 1)[1].to_float()
		elif a == "--noquit":
			_quit = false
	if not want:
		set_process(false)
		return
	if _case_name != "" and not CASES.has(_case_name):
		# A silent fallback to the default batch would make a mistyped case name
		# look like a successful run — fail loudly instead.
		printerr("[capture] 未知 --case='", _case_name, "'；可用：",
				", ".join(PackedStringArray(CASES.keys())))
		get_tree().quit(1)
		return
	_enabled = true
	if _case_name != "":
		_shots = (CASES[_case_name] as Array).duplicate(true)
		_manifest_label = _case_name
	elif not single.is_empty():
		_shots = [single]
		_manifest_label = String(single.get("name", "single"))
	else:
		_shots = (CASES["default"] as Array).duplicate(true)
		_manifest_label = "default"
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# S0.6 — reproducibility contract.  Captures run on the deterministic clock by
	# default so that the same case twice produces byte-identical PNGs; the warm-up
	# then covers a fixed number of *frames*, not a wall-clock duration, so the
	# animation phase at the shutter is a pure function of the frame count.
	# `--bench` is a wall-clock perf probe, so it keeps interactive clock semantics.
	var use_det := (not _realtime) and (not _bench)
	Clock.set_deterministic(use_det, _clock_hz)
	if _bench:
		print("[capture] 时钟=真实 delta（--bench 性能探针）")
	elif use_det:
		print("[capture] 时钟=确定性 %.1fHz（可复现；--realtime 可关闭）" % _clock_hz)
	else:
		print("[capture] 时钟=真实 delta（--realtime，截图不保证可复现）")
	# let the world build + a few frames of wave/wind animation settle
	for i in _warmup:
		await get_tree().process_frame
	if _bench:
		await _benchmark()
		if _quit:
			get_tree().quit()
		return
	var manifest: Array = []
	var ui_failed := 0
	for shot in _shots:
		_apply(shot)
		if shot.has("ui"):
			ui_failed += await _apply_ui(shot["ui"])
		if shot.has("ui_expect"):
			ui_failed += _expect_ui(shot["ui_expect"])
		for i in _frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [_out_dir, String(shot.get("name", "shot"))]
		var err := img.save_png(path)
		print("[capture] ", path, " -> ", error_string(err))
		if err == OK:
			manifest.append({
				"name": String(shot.get("name", "shot")),
				"path": path,
				"width": img.get_width(),
				"height": img.get_height(),
				"sha256": FileAccess.get_sha256(path),
				"params": shot,
			})
	_write_manifest(manifest)
	print("[capture] done")
	if _quit:
		# S0.3 batch 4: a failed UI step or a failed `ui_expect` must not look like a
		# successful capture — the parent case asserts this exit code.
		get_tree().quit(1 if ui_failed > 0 else 0)


## Machine-readable sidecar for B- class evidence: which PNGs, which camera
## parameters, and a sha256 per image so a later diff can be anchored.
func _write_manifest(manifest: Array) -> void:
	var case_label := _manifest_label if _manifest_label != "" else "default"
	var path := "%s/%s.json" % [_out_dir, case_label]
	var payload := {
		"kind": "capture_manifest",
		"case": case_label,
		"godot": Engine.get_version_info()["string"],
		"started_at": Time.get_datetime_string_from_system(),
		"out_dir": _out_dir,
		"warmup_frames": _warmup,
		"settle_frames": _frames,
		# S0.6: without this the manifest cannot tell a reproducible capture from a
		# --realtime one, which matters when the file is used as B- evidence.
		"clock": {
			"deterministic": Clock.deterministic,
			"hz": Clock.hz,
			"t": Clock.t,
			"frame": Clock.frame,
			"shader_param_ok": Clock.shader_param_ok,
		},
		"shots": manifest,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[capture] 无法写清单 ", path)
		return
	f.store_string(JSON.stringify(payload, "  ", false))
	f.close()
	print("[capture] manifest ", path, " (", manifest.size(), " shots)")


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


## ---------------------------------------------------------------------------
## S0.3 batch 4 — 驱动真实 UI 拍图
## ---------------------------------------------------------------------------
## 产品码里**没有**「把菜单摆成某个状态」的后门；截图的 UI 状态由注入的真实输入
## 事件达成（ESC 键、鼠标按下+抬起），走的是玩家同一条管线。老师傅的做法（给菜单
## 加个 `set_demo_state()`）会让截图证明的是那个后门，而不是玩家看到的路。
##
## 步骤是**增量**：同一批次的第二张图承接第一张图留下的状态（一个批次只有一个
## 进程）。找不到控件、控件不可见、或 `ui_expect` 与真实状态不符，一律记失败并让
## 本次截图进程以非 0 退出 —— 否则「拍错屏」会变成一张看起来正常的 PNG。
func _apply_ui(steps: Array) -> int:
	var failed := 0
	for step in steps:
		var s := String(step)
		if s == "esc":
			await _press_key(KEY_ESCAPE)
			print("[capture] ui esc")
		elif s.begins_with("click:"):
			var target := s.substr(6)
			var ok_click := await _click_path(target)
			print("[capture] ui click ", target, " -> ", "ok" if ok_click else "FAILED")
			if not ok_click:
				failed += 1
		else:
			printerr("[capture] 未知 ui 步骤：", s)
			failed += 1
	return failed


func _click_path(path: String) -> bool:
	var ctrl := _menu_control(path)
	if ctrl == null:
		return false
	if not ctrl.is_visible_in_tree():
		printerr("[capture] ui 目标当前不可见：", path)
		return false
	var p := ctrl.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame
	return true


func _press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame


func _menu_control(path: String) -> Control:
	var menu := get_tree().get_first_node_in_group("menu")
	if menu == null:
		printerr("[capture] 场景里找不到菜单节点（group=menu）")
		return null
	var node := menu.get_node_or_null(path)
	if node == null:
		printerr("[capture] ui 步骤找不到控件：", path)
		return null
	return node as Control


## 截图前检查「真的到了声明的界面」。菜单用鸭子类型访问（`call`）：截图器不该
## 编译期依赖菜单脚本，否则菜单改名/换实现会连累所有批次。
func _expect_ui(expect: Dictionary) -> int:
	var menu := get_tree().get_first_node_in_group("menu")
	if menu == null:
		printerr("[capture] ui_expect：场景里没有菜单节点")
		return 1
	var failed := 0
	if expect.has("open") and bool(menu.call("is_open")) != bool(expect["open"]):
		printerr("[capture] ui_expect open 不符：期望 ", expect["open"],
				"，实际 ", menu.call("is_open"))
		failed += 1
	if expect.has("page") and String(menu.call("page_name")) != String(expect["page"]):
		printerr("[capture] ui_expect page 不符：期望 ", expect["page"],
				"，实际 ", menu.call("page_name"))
		failed += 1
	if expect.has("confirm") and bool(menu.call("confirm_open")) != bool(expect["confirm"]):
		printerr("[capture] ui_expect confirm 不符：期望 ", expect["confirm"],
				"，实际 ", menu.call("confirm_open"))
		failed += 1
	if failed == 0:
		print("[capture] ui_expect ok ", JSON.stringify(expect))
	return failed

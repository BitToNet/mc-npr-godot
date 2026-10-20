extends Node
## Capture — headless-ish screenshot harness used while developing the look.
##
##   Godot --path . -- --shots
##   Godot --path . -- --shot=noon --time=0.5 --mode=follow --size=30
##   Godot --path . -- --shots --case=s0_boot     # S0.2: named batch case table
##   Godot --path . -- --shots --case=s0_boot --frames=24 --warmup=60
##   Godot --path . -- --shots --case=s0_boot --clock-hz=30   # 时钟步长
##   Godot --path . -- --shots --case=s0_boot --realtime      # 关掉可复现性
##   Godot --path . -- --shots --scene=res://<场景>.tscn   # S1.0b 指定取景场景
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
##
## S1.0b — `--scene=res://…` 指定**拍哪个场景**（缺省 = `run/main_scene`）。与
## `--case=` / `--out=` 同级，是**纯修饰符**：单独出现不触发截图，也不抢退出码。
## 具体命令写在 `docs/ENGINEERING.md` §4，本文件**不写死**那条路径 —— 产品码里出现
## `scenes/dev/` 会被 `s0_5_doc_conventions` 的登记表拦下（S1.0d 起该表已收紧回 0 条），
## 这条门禁的用处正是"夹具场景别漏进正式构建"，不该为了抄一个路径就放宽它。
## S1.0d 之后这条参数也是 diorama 的**唯一**入口：开机主场景已是战略图空壳（无相机），
## 缺省批次拍不到世界，6 机位 `B-` 必须显式 `--scene=` 到 `dev/diorama.tscn`。
## 实现见 `_swap_scene()`：手动换 `SceneTree.current_scene`，不调
## `change_scene_to_*()`（`scene_change_owner` 只放行 `SceneRouter`，ROADMAP §3.2），
## 也不去改 `run/main_scene`（实测引擎取该路径早于 autoload，改了不生效）。
## `_swap_scene()` 里四条自证 + 路径先验都成立才继续，否则退出码 1 ——
## 绝不静默拍成默认场景（那会让 `B-` 变成"另一张也对得上基线"的假通过）。

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
	## S0.4 batch 2 — the debug observation layer (B- evidence for ROADMAP §5 S0.4).
	##
	## Two batches, not one, because the pair that carries the meaning is
	## "overlay on" vs "everything hidden": the second batch proves F1 removed the
	## UI from the render (its sha256 must equal the same camera position captured
	## with no UI at all, i.e. `s0_boot_wide`) instead of merely fading it.
	##
	## Camera parameters are deliberately identical to `s0_boot` so that the two
	## PNGs are comparable byte-for-byte; the deterministic clock makes that a
	## legitimate equality rather than a coincidence.  `key:` steps are the same
	## injected-input path the menu batches use — no "demo state" hook exists.
	"s0_4_overlay": [
		{"name": "01_overlay_on", "time": 0.33, "mode": "FREE", "size": 66.0, "yaw": 40.0,
			"ui": ["key:f3"], "ui_expect": {"overlay": true, "ui_hidden": false}},
	],
	"s0_4_ui_hidden": [
		{"name": "02_ui_hidden", "time": 0.33, "mode": "FREE", "size": 66.0, "yaw": 40.0,
			"ui": ["key:f3", "key:f1"], "ui_expect": {"overlay": true, "ui_hidden": true}},
	],
	## S0.5 — `docs/ART_PIPELINE.md` §2 的配图：**三对 A/B**，共六张。
	##
	## 每一对共用同一份网格与同一条机位，**只差一条被破坏的规则**。这是配图能不能
	## 当证据的分水岭：如果一对图里同时换了形状、颜色、光照和机位，读者看到的差异
	## 就归因不到任何一条规则上，图就只是"两张好看的图"。
	##   01 / 05 — 同一棵树（共享同一个 ArrayMesh 实例），只差材质：合规 toon 三点布光
	##             + 反向外壳描边 ↔ `StandardMaterial3D`（光滑 PBR、无阶梯、无描边）
	##   02 / 04 — 同一块"石头"：`blob()` 圆润低模 ↔ `BoxMesh` 立方体（AGENTS.md §一第一条禁令）
	##   03 / 06 — 同一个球：走过 `MeshUtil.facet()` 的面着色 ↔ 未走 facet 的 `SphereMesh`
	##             （索引网格 + 平滑法线，守卫抓不到，只能靠眼睛 —— 见文档 §2.2）
	##
	## 主体由 `tools/dev/art_samples.tscn` 生成（那个目录**故意**含违例写法，理由见
	## `docs/ART_PIPELINE.md` §1.3）；`at` 把正交相机逐张对准一个展台。
	## 相机 `size=5.0` / `yaw=38` / `time=0.42` / `FREE` 六张完全相同，只有 `at` 变。
	"s0_5_samples": [
		{"name": "01_ok_tree", "time": 0.42, "mode": "FREE", "size": 5.4, "yaw": 38.0,
			"at": "-45,1.75,0"},
		{"name": "02_ok_rock", "time": 0.42, "mode": "FREE", "size": 5.4, "yaw": 38.0,
			"at": "-27,0.80,0"},
		{"name": "03_ok_ball", "time": 0.42, "mode": "FREE", "size": 5.4, "yaw": 38.0,
			"at": "-9,1.10,0"},
		{"name": "04_bad_box", "time": 0.42, "mode": "FREE", "size": 5.4, "yaw": 38.0,
			"at": "9,0.88,0"},
		{"name": "05_bad_pbr_tree", "time": 0.42, "mode": "FREE", "size": 5.4, "yaw": 38.0,
			"at": "27,1.75,0"},
		{"name": "06_bad_smooth_ball", "time": 0.42, "mode": "FREE", "size": 5.4, "yaw": 38.0,
			"at": "45,1.10,0"},
	],
}

## `ui` 步骤可用的按键名（`key:<name>`）。只列"截图真的会用到"的键：
## 这不是键位表（键位在 `scripts/core/input_setup.gd`），而是注入器的白名单，
## 拼错名字必须**显式失败**，否则会拍下一张"看起来正常但状态没切"的图。
const KEY_BY_NAME := {
	"esc": KEY_ESCAPE,
	"escape": KEY_ESCAPE,
	"f1": KEY_F1,
	"f3": KEY_F3,
	"f5": KEY_F5,
	"f9": KEY_F9,
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
## S1.0b — `--scene=` 的值；空串表示"用 `run/main_scene`"。
var _scene_override := ""


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
		elif a.begins_with("--at="):
			# S0.5 取景修饰符：把正交相机对准一个绝对世界坐标（"x,y,z"）。
			# 参数化夹具（`tools/dev/art_samples.tscn` 的六个展台）需要在**同一批**
			# 里逐张换主体，而产品码里没有"把世界摆成某个状态"的后门 —— 取景是工具
			# 层的职责，不是产品码的职责。与 `--size=` / `--yaw=` 一样只作修饰符，
			# 不单独唤醒截图批次（否则跑 verify 时会连带触发一次截图）。
			single["at"] = a.split("=", true, 1)[1]
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
		elif a.begins_with("--scene="):
			# S1.0b — 取景场景。纯修饰符：不置 want（理由见文件头）。
			_scene_override = a.split("=", true, 1)[1]
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
	# S1.0b — 换场景**只在这一批真的要截图时**发生：只带 `--scene=` 的进程必须跟
	# `--case=` / `--out=` 一样是空转（见文件头 trigger vs modifier）。
	# 路径先验一遍：拼错必须在建任何东西、拍任何图之前就失败。
	if _scene_override != "" and not _scene_arg_ok():
		get_tree().quit(1)
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


## S1.0b — `--scene=` 的路径先验（只验路径，不动场景）。
func _scene_arg_ok() -> bool:
	if not _scene_override.begins_with("res://"):
		printerr("[capture] --scene= 只接受 res:// 路径，实际 '", _scene_override, "'")
		return false
	if not ResourceLoader.exists(_scene_override):
		printerr("[capture] --scene='", _scene_override, "' 指向的场景不存在")
		return false
	return true


## 当前真正加载的场景路径（未就绪时返回空串，绝不猜）。
func _loaded_scene_path() -> String:
	var cur := get_tree().current_scene
	return "" if cur == null else cur.scene_file_path


## S1.0b — 换成 `--scene=` 指定的场景，并自证换成了。
##
## 为什么不是 `change_scene_to_file()`：`scene_change_owner` 守卫只放行 `SceneRouter`
## （ROADMAP §3.2），把 capture 加进属主清单等于给规则开后门 —— 而这条规则的用处正是
## "切场景只能有一个入口"。这里做的是**取景工具换夹具**，不是游戏内转场，所以走
## `SceneTree` 的公开成员手动换，且不改 `current_route`（那是 SceneRouter 的事实）。
##
## 为什么不是改 `run/main_scene` 让引擎一开始就加载它：**实测无效**。引擎在 autoload
## 的 `_ready()` 之前就把主场景路径取走了，改设置只影响下一次开机；`--scene=<非默认场景>`
## 因此会安静地加载默认场景。这条路已废弃，别回头捡。
##
## 顺序是硬要求：`add_child()` 会同步跑新场景的 `_ready()`（世界立刻建好），旧场景
## 必须**同步** `free()` 掉 —— 不能 `queue_free()` 再 `await` 一帧：世界动画是**增量
## 积分**（`clouds.gd` 的 `c.position.x += drift * Clock.dt`），多跑一帧就等于把云往前
## 推一步，"`--scene=` 与缺省逐位相同"立刻不成立。实测踩过：只差这一帧，两张图肉眼
## 一模一样、sha256 全不同。
##
## 也因为不 await，旧场景必须在 `free()` 之前把 `current_scene` 让出去，否则树里会留一个
## 指向已释放对象的当前场景。
func _swap_scene() -> bool:
	var ps := load(_scene_override) as PackedScene
	if ps == null:
		printerr("[capture] --scene='", _scene_override, "' 不是可加载的 PackedScene")
		return false
	var old := get_tree().current_scene
	var inst := ps.instantiate()
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	if old != null:
		old.free()
	# 自证四条，缺一条就说明"拍的还是原来那个场景"：
	#   ① 当前场景就是新实例   ② 新实例路径就是要求的那个
	#   ③ 旧场景真的没了       ④ 组里最多一台相机（不是新旧各一台）
	if get_tree().current_scene != inst:
		printerr("[capture] --scene='", _scene_override, "' 没有接管 current_scene")
		return false
	if inst.scene_file_path != _scene_override:
		printerr("[capture] 新场景路径 '", inst.scene_file_path, "' != '", _scene_override, "'")
		return false
	if old != null and is_instance_valid(old):
		printerr("[capture] 旧场景没有被释放，取景会抓到两台相机")
		return false
	var rigs := get_tree().get_nodes_in_group("camera_rig")
	if rigs.size() > 1:
		printerr("[capture] 场景换了但相机组里还有 ", rigs.size(), " 台")
		return false
	return true


func _run() -> void:
	# S1.0b — 换场景必须在 `Clock.set_deterministic()` **之前**，而且**不额外消耗帧**：
	# 之后的确定性时钟会把 t/frame 归零，所以"换场景"与"缺省开机"两条路径在快门之前
	# 走过的帧数与 dt 序列完全相同 —— `--scene=` 的哈希组与缺省逐位相同靠的是这个，
	# 不是容差。
	if _scene_override != "" and not _swap_scene():
		get_tree().quit(1)
		return
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
		# S1.0b — 清单自报"拍的是哪个场景"。少了这一条，一张图和它的 `--scene=`
		# 参数之间就没有可核对的锚点，"指定场景"只能靠调用方自觉。
		"scene": _loaded_scene_path(),
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
	if shot.has("at"):
		# S0.5：对准显式世界坐标。用 `snap_to()` 而不是给 rig 设 target —— `target`
		# 会走 `_process` 的跟随插值（带 ±22 / 0..9 的聚焦钳制），逐帧把相机拉走，
		# 拍出来的就不是"对准那个展台"。`snap_to()` 是给工具层用的直接落位接口。
		var p: Variant = _parse_point(String(shot["at"]))
		if p == null:
			printerr("[capture] --at= 解析失败：", shot["at"], "（应为 \"x,y,z\"）")
			rig._apply()
			return
		rig.snap_to(p)
	elif pl != null:
		rig.snap_to(pl.global_position)
	rig._apply()


## "x,y,z" -> Vector3；非法输入返回 null（由调用方显式失败，不静默取默认值）。
func _parse_point(text: String) -> Variant:
	var parts := text.split(",", true, 2)
	if parts.size() != 3:
		return null
	for s in parts:
		if not String(s).strip_edges().is_valid_float():
			return null
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())


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
		elif s.begins_with("key:"):
			# S0.4 批次 2：通用按键注入。`esc` 保留为既有别名的同义词（历史批次不改），
			# 新批次用 `key:f1` / `key:f3` —— 与玩家按键走同一条 `Input.parse_input_event`。
			var kn := s.substr(4).to_lower()
			if not KEY_BY_NAME.has(kn):
				printerr("[capture] 未知按键名：", kn, "（可用：",
						", ".join(PackedStringArray(KEY_BY_NAME.keys())), "）")
				failed += 1
				continue
			await _press_key(KEY_BY_NAME[kn])
			print("[capture] ui key ", kn)
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


## 注入一次真实左键点击（移动 → 按下 → 抬起）。
##
## ⚠️ **必须先发一个 `InputEventMouseMotion`**：只发 press/release 会间歇性丢点击
## （`s0_3_slots` 在 HEAD 上 5 次跑有 2 次失败，失败点随机漂移）。Godot 的 Viewport
## 用 `gui.mouse_focus` 决定把按键投递给谁，而那个焦点**由鼠标移动事件更新**；
## 没有移动，按键就落在一个失效的焦点上。真实用户点击前一定先移动鼠标，
## 所以补上移动不是绕过问题，而是让注入序列符合真实输入。
## `tools/verify.gd::_click_control()` 有同一处修正与同一段说明。
func _click_path(path: String) -> bool:
	var ctrl := _menu_control(path)
	if ctrl == null:
		return false
	if not ctrl.is_visible_in_tree():
		printerr("[capture] ui 目标当前不可见：", path)
		return false
	var p := ctrl.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = p
	motion.global_position = p
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await get_tree().process_frame
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


## 截图前检查「真的到了声明的界面」。菜单与调试层都用鸭子类型访问（`call`）：截图器
## 不该编译期依赖它们的脚本，否则改名/换实现会连累所有批次。
func _expect_ui(expect: Dictionary) -> int:
	var failed := 0
	if expect.has("overlay") or expect.has("ui_hidden"):
		failed += _expect_debug(expect)
	var menu := get_tree().get_first_node_in_group("menu")
	var wants_menu := expect.has("open") or expect.has("page") or expect.has("confirm")
	if wants_menu and menu == null:
		printerr("[capture] ui_expect：场景里没有菜单节点")
		return failed + 1
	if menu != null and expect.has("open") and bool(menu.call("is_open")) != bool(expect["open"]):
		printerr("[capture] ui_expect open 不符：期望 ", expect["open"],
				"，实际 ", menu.call("is_open"))
		failed += 1
	if menu != null and expect.has("page") and String(menu.call("page_name")) != String(expect["page"]):
		printerr("[capture] ui_expect page 不符：期望 ", expect["page"],
				"，实际 ", menu.call("page_name"))
		failed += 1
	if menu != null and expect.has("confirm") and bool(menu.call("confirm_open")) != bool(expect["confirm"]):
		printerr("[capture] ui_expect confirm 不符：期望 ", expect["confirm"],
				"，实际 ", menu.call("confirm_open"))
		failed += 1
	if failed == 0:
		print("[capture] ui_expect ok ", JSON.stringify(expect))
	return failed


## S0.4 批次 2：调试层的到达自证。与菜单同样只认可观测到的状态，不认"我按了键"。
func _expect_debug(expect: Dictionary) -> int:
	var dbg := get_tree().get_root().get_node_or_null("Debug")
	if dbg == null:
		printerr("[capture] ui_expect：找不到 autoload Debug（调试层没挂上？）")
		return 1
	var failed := 0
	if expect.has("overlay") and bool(dbg.call("is_overlay_on")) != bool(expect["overlay"]):
		printerr("[capture] ui_expect overlay 不符：期望 ", expect["overlay"],
				"，实际 ", dbg.call("is_overlay_on"))
		failed += 1
	if expect.has("ui_hidden") and bool(dbg.call("is_ui_hidden")) != bool(expect["ui_hidden"]):
		printerr("[capture] ui_expect ui_hidden 不符：期望 ", expect["ui_hidden"],
				"，实际 ", dbg.call("is_ui_hidden"))
		failed += 1
	return failed

extends SceneTree

## Wall-clock perf probe for the strategic map (`C-` evidence, S1.2d).
##
## WHY A SEPARATE TOOL, NOT A `tools/verify.gd` CASE: the suite's cases must stay
## fast and deterministic; this one is the opposite (real frame pacing, three
## seconds of sampling per tier, vsync forced off).  The case calls it as a
## subprocess and asserts on its JSON, so the numbers still live in the ledger.
##
## Vsync is disabled on purpose: with it on, the engine is capped at the monitor's
## refresh rate (measured elsewhere at 18.75 ms/frame ⇒ ~53 fps), so "≥ 60 fps"
## would measure the display, not the scene.  The report records the mode it
## actually got, and the reverse control (`--empty`) hides the world so the same
## harness must report a much higher number — a probe that cannot tell the map from
## an empty sky proves nothing.
##
##   Godot --path . --script res://tools/perf_map.gd -- --label=perf_map \
##         --out=res://.verify --windows=3 --window=1.0 --warmup=60
##
## Output: `<out>/perf_map_<label>.json` plus one `[perf]` line per tier.

const MAP_SCENE := "res://scenes/world/strategic_map.tscn"
const TIERS := {"global": 0, "region": 1, "local": 2}
const FPS_FLOOR := 60.0

var _label := "perf_map"
var _out := "res://.verify"
var _warmup := 60
var _windows := 3
var _window_sec := 1.0
var _seed := 20250929
var _tiers: Array[String] = ["global", "region", "local"]
var _started := false
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--label="):
			_label = a.split("=", true, 1)[1]
		elif a.begins_with("--out="):
			_out = a.split("=", true, 1)[1]
		elif a.begins_with("--warmup="):
			_warmup = a.split("=", true, 1)[1].to_int()
		elif a.begins_with("--windows="):
			_windows = a.split("=", true, 1)[1].to_int()
		elif a.begins_with("--window="):
			_window_sec = a.split("=", true, 1)[1].to_float()
		elif a.begins_with("--seed="):
			_seed = a.split("=", true, 1)[1].to_int()
		elif a.begins_with("--tiers="):
			_tiers.clear()
			for t in a.split("=", true, 1)[1].split(",", false):
				if TIERS.has(t):
					_tiers.append(t)
	if DisplayServer.get_name() == "headless":
		printerr("[perf] headless 没有帧指标（渲染指标恒为 0）；请去掉 --headless 重跑")
		quit(2)
		return


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var previous_vsync := DisplayServer.window_get_vsync_mode()
	# 0 = VSYNC_DISABLED: 见文件头，量的是场景不是显示器。
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	var state := get_root().get_node_or_null("GameState")
	if state != null:
		state.set("world_seed", _seed)
	var ps := load(MAP_SCENE) as PackedScene
	var map := ps.instantiate() as Node3D
	get_root().add_child(map)
	# S1.4b — 时间条是 HUD，不是 3D 预算的一部分：留在这里会让"三角面 = 地形 + 棋子"
	# 变成"地形 + 棋子 + 字体光栅的面数"，而后者随平台字体变化，钉不住。采样前隐藏
	# `#hud` 组，量到的就是这张地图本身；HUD 自己的绘制成本由 `s0_4_cost` 的帧率兜底。
	for hud in get_nodes_in_group("hud"):
		if hud is CanvasLayer:
			(hud as CanvasLayer).visible = false
	var cam: Node3D = map.get("camera") as Node3D
	if cam == null:
		printerr("[perf] 战略图没有相机；无法分档采样")
		_finish(previous_vsync, {})
		return
	var rows: Array = []
	for tier_name in _tiers:
		cam.call("set_tier", int(TIERS[tier_name]))
		cam.call("snap_to_target")
		var row := await _sample(tier_name, float(cam.get("size")))
		rows.append(row)
	# 反向对照：同一套采样器量"空天空"。若它与地图结果一样低，说明测的是别的东西
	# （vsync / 限帧 / 采样器本身），而不是这张地图的成本。
	map.visible = false
	await process_frame
	var empty := await _sample("empty", 0.0)
	var report := {
		"label": _label,
		"world_seed": _seed,
		"vsync": "disabled" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED else "unknown",
		"vsync_previous": previous_vsync,
		"fps_floor": FPS_FLOOR,
		"windows": _windows,
		"window_sec": _window_sec,
		"warmup_frames": _warmup,
		"tiers": rows,
		"empty": empty,
	}
	var slowest := INF
	for r in rows:
		slowest = minf(slowest, float(r["fps_mean"]))
	var passes := true
	for r in rows:
		if float(r["fps_mean"]) < FPS_FLOOR:
			passes = false
	if float(empty["fps_mean"]) <= slowest * 1.5:
		# 采样器分辨不出地图与空天空 ⇒ 这些数字不能当证据。
		passes = false
	report["slowest_fps"] = snappedf(slowest, 0.01) if slowest < INF else 0.0
	report["pass"] = passes
	_finish(previous_vsync, report)


func _sample(tier_name: String, size: float) -> Dictionary:
	for i in _warmup:
		await process_frame
	var samples: Array[float] = []
	for w in _windows:
		var frames := 0
		var t0 := Time.get_ticks_usec()
		while (Time.get_ticks_usec() - t0) < int(_window_sec * 1000000.0):
			await process_frame
			frames += 1
		var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
		samples.append(snappedf(float(frames) / dt, 0.1))
	var mean := 0.0
	var lo := INF
	for s in samples:
		mean += s
		lo = minf(lo, s)
	mean /= float(samples.size())
	await RenderingServer.frame_post_draw
	var row := {
		"tier": tier_name,
		"size": size,
		"fps_mean": snappedf(mean, 0.01),
		"fps_min": snappedf(lo, 0.01),
		"ms_per_frame": snappedf(1000.0 / mean, 0.001),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"samples": samples,
	}
	print("[perf] %-6s size=%7.1f  %6.1f fps  %6.3f ms  prims=%d  draws=%d"
			% [tier_name, size, row["fps_mean"], row["ms_per_frame"],
			row["primitives"], row["draw_calls"]])
	return row


func _finish(p_previous_vsync: int, report: Dictionary) -> void:
	DisplayServer.window_set_vsync_mode(p_previous_vsync)
	if report.is_empty():
		_done = true
		quit(2)
		return
	var path := _out.path_join("perf_map_%s.json" % _label)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[perf] 写不了报告：", path)
		_done = true
		quit(2)
		return
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[perf] %s -> %s  pass=%s  slowest=%.1f fps"
			% [_label, path, str(report["pass"]), float(report["slowest_fps"])])
	_done = true
	quit(0 if bool(report["pass"]) else 1)
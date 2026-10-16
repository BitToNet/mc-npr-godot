extends SceneTree
## =============================================================================
##  tools/baseline.gd — 性能基线采集（C- 类验收，S0.2 交付物）
## =============================================================================
##  用法（**必须窗口模式**，不能加 --headless）：
##    Godot --path <proj> --script res://tools/baseline.gd -- [--label=main] \
##          [--warmup=120] [--windows=6] [--window=0.5] [--out=res://.verify]
##
##  产出：<out>/baseline_<label>.json，含四项核心指标：
##          fps_mean / ms_per_frame / memory_static_mb / primitives
##        以及 draw_calls / objects / 每个采样窗口的原始 FPS。
##
##  退出码：0 = 成功；2 = 用法错误（含误加 --headless）。
##
##  ⚠️ 实测结论（勿删）：headless 下渲染指标恒为 0、TIME_FPS 恒为 1，
##     所以性能基线**只能**在窗口模式采集。verify.gd 的 s0_2_baseline 用例
##     据此把本脚本作为子进程用窗口模式拉起 3 次，再比较方差。
##
##  ⚠️ 与 verify.gd 相同：本脚本以 `--script` 运行，**不得**使用 autoload 标识符。
## =============================================================================

const REPORT_DIR := "res://.verify"

var _label := "main"
var _out := REPORT_DIR
var _warmup := 120
var _windows := 6
var _window_sec := 0.5

var _started := false
var _finished := false


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

	if DisplayServer.get_name() == "headless":
		printerr("[baseline] 用法错误：headless 模式没有渲染指标（RENDER_* 恒为 0）。")
		printerr("[baseline] 请去掉 --headless 重跑：Godot --path <proj> --script res://tools/baseline.gd")
		quit(2)
		return


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var t0 := Time.get_ticks_msec()

	var ps := load("res://scenes/main.tscn") as PackedScene
	if ps == null:
		printerr("[baseline] 无法加载 res://scenes/main.tscn")
		_finished = true
		quit(2)
		return
	var main := ps.instantiate()
	get_root().add_child(main)
	await process_frame

	print("[baseline] 预热 %d 帧…" % _warmup)
	for i in _warmup:
		await process_frame

	print("[baseline] 采样 %d × %.2fs…" % [_windows, _window_sec])
	var samples: Array = []
	for w in _windows:
		var frames := 0
		var wt0 := Time.get_ticks_usec()
		while (Time.get_ticks_usec() - wt0) < int(_window_sec * 1000000.0):
			await process_frame
			frames += 1
		var dt := float(Time.get_ticks_usec() - wt0) / 1000000.0
		var fps := float(frames) / dt
		samples.append(snappedf(fps, 0.1))
		print("[baseline]   窗口 %d: %.1f fps" % [w + 1, fps])

	var fps_mean := 0.0
	for s in samples:
		fps_mean += float(s)
	fps_mean /= float(samples.size())

	# 渲染指标：必须在一帧渲染完成后读，否则拿到的是上一帧或 0
	await RenderingServer.frame_post_draw
	var mem_static := Performance.get_monitor(Performance.MEMORY_STATIC)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)

	var report := {
		"kind": "baseline",
		"label": _label,
		"ok": true,
		"godot": Engine.get_version_info()["string"],
		"exe": OS.get_executable_path(),
		"display": DisplayServer.get_name(),
		"viewport": [
			ProjectSettings.get_setting("display/window/size/viewport_width", 0),
			ProjectSettings.get_setting("display/window/size/viewport_height", 0),
		],
		"msaa_3d": ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0),
		"warmup_frames": _warmup,
		"sample_windows": samples,
		"fps_mean": snappedf(fps_mean, 0.01),
		"fps_min": samples.min(),
		"fps_max": samples.max(),
		"ms_per_frame": snappedf(1000.0 / fps_mean, 0.001),
		"memory_static_mb": snappedf(mem_static / 1048576.0, 0.01),
		"primitives": int(prims),
		"draw_calls": int(draws),
		"objects": int(objects),
		"started_at": Time.get_datetime_string_from_system(),
		"duration_ms": Time.get_ticks_msec() - t0,
	}

	var path := _out.path_join("baseline_%s.json" % _label)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[baseline] 无法写入 ", path)
		_finished = true
		quit(2)
		return
	f.store_string(JSON.stringify(report, "  ", false))
	f.close()

	print("[baseline] FPS %.2f  ms/frame %.3f  内存 %.2fMB  三角面 %d  draw %d  objects %d"
			% [report["fps_mean"], report["ms_per_frame"], report["memory_static_mb"],
			report["primitives"], report["draw_calls"], report["objects"]])
	print("[baseline] 报告 ", path)

	main.queue_free()
	await process_frame
	_finished = true
	quit(0)

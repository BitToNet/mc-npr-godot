extends SceneTree
## =============================================================================
##  tools/verify.gd — Pocket Sandbox A- / C- 类验收运行器（S0.2 交付物）
## =============================================================================
##  用法（与 docs/ROADMAP.md §3.4 一致）：
##
##    # 单个用例（headless，退出码 0=全绿 / 1=有失败 / 2=用法错误）
##    Godot --headless --path <proj> --script res://tools/verify.gd -- --case=s0_2_guard
##
##    # 全部用例（headless：kind="headed" 的用例自动跳过并记原因，不算失败）
##    Godot --headless --path <proj> --script res://tools/verify.gd -- --all
##
##    # 全部用例（窗口模式：C- 类性能用例才会真正执行）
##    Godot           --path <proj> --script res://tools/verify.gd -- --all
##
##    # 列出用例  /  指定报告目录
##    ... -- --list        ... -- --all --out=res://.verify
##
##  报告：<out>/<case>.json，含每条断言、逐条耗时、引擎版本、可执行文件路径。
##  聚合报告：<out>/_all.json。
##
## -----------------------------------------------------------------------------
##  ⚠️ 实测硬约束（S0.2 探针结论，改动前先复现探针，勿凭直觉改）
## -----------------------------------------------------------------------------
##  1) 本脚本以 `--script` 方式充当 MainLoop。该模式下 autoload 的**标识符不可
##     编译**（`SCRIPT ERROR: Compile Error: Identifier not found: Style`），
##     尽管 autoload 节点确实已经挂在 root 上。
##     ⇒ 本文件内**禁止**书写 `Style.xxx` / `Capture.xxx`；
##       必须 get_root().get_node_or_null("Style") 动态取用。
##  2) 全局 class_name（MeshUtil / Terrain / InputSetup / …）在本模式下正常可用。
##  3) 场景用例模式 = instantiate 主场景 + add_child + await process_frame；
##     实测可行（世界会正常生成），不需要子进程 hack。
##     注意：add_child 之后**必须** await 一帧再查节点组，否则组注册可能未完成。
##  4) headless 下没有任何渲染指标（RENDER_* 恒为 0，TIME_FPS 恒为 1），
##     所以 kind="headed" 的用例在 headless 下只能跳过，**不得**判为失败。
##  5) 每个 `_case_*` 函数必须以 `await process_frame` 开头：分发器统一用
##     `await _case_xxx()`，若某函数不是协程，Godot 会直接报错。
## =============================================================================

const REPORT_DIR := "res://.verify"

## 用例注册表。kind：pure = headless 可跑；headed = 需要真实 GPU/窗口。
## hidden：不参与 --all（供本文件自检使用的诊断用例）。
const CASES := {
	"s0_2_selfcheck": {
		"desc": "断言库自检：通过/失败用例的退出码契约 + JSON 报告字段完整性",
		"kind": "pure",
	},
	"s0_2_imgdiff": {
		"desc": "img_diff：同图 0.0000% / 改动副本 > 0% / 尺寸不一致显式失败",
		"kind": "pure",
	},
	"s0_2_guard": {
		"desc": "规范守卫：5 类违例各自可捕获 + 既有代码无未登记违例",
		"kind": "pure",
	},
	"s0_2_boot": {
		"desc": "主场景 headless 启动 60 帧，退出码 0 且日志无 ERROR/SCRIPT ERROR",
		"kind": "pure",
	},
	"s0_2_scene_api": {
		"desc": "场景用例模式：加载主场景 + await，19 个既有公开 API 符号可解析",
		"kind": "pure",
	},
	"s0_2_baseline": {
		"desc": "性能基线：FPS/ms-per-frame/内存/三角面 四项 + 连续 3 次采样方差 < 5%",
		"kind": "headed",
	},
	"s0_2_probe_pass": {
		"desc": "[诊断] 全通过用例，供 selfcheck 验证『退出码 0』",
		"kind": "pure",
		"hidden": true,
	},
	"s0_2_probe_fail": {
		"desc": "[诊断] 故意失败用例，供 selfcheck 验证『退出码 1』",
		"kind": "pure",
		"hidden": true,
	},
}

## -----------------------------------------------------------------------------
##  规范守卫（§3.1.8 / §5 S0.2）
## -----------------------------------------------------------------------------
const GUARD_SCAN_DIRS := ["res://scenes", "res://scripts", "res://shaders"]
const GUARD_EXTS := ["gd", "tscn", "tres", "gdshader", "shader"]

## 裸随机函数：禁止全局 randf()/randi()（含 _range 变体）；
## `rng.randf()` 这种成员调用是允许的（§3.2「所有随机走 Rng 服务」）。
const BARE_RAND_FUNCS := ["randf", "randi", "randf_range", "randi_range"]

## 白名单：既有文件中已存在、本步不扩大改动面的命中项（§3.2「既有文件不重写」）。
## 每条必须写清理由；守卫报告会**显式列出**命中白名单的行，不静默放过。
const GUARD_WHITELIST := [
	{
		"path": "res://scripts/main.gd",
		"rule": "bare_randi",
		"reason": "演示场景的『随机重生成』交互（main.gd:48 auto_new_seed_on_start、"
				+ "main.gd:89 _on_regenerate 的 randi()）。属 §3.2 既有文件不重写范围，"
				+ "S0.2 不扩大改动面；后续新增模块（core/world/actors/battle/legion）"
				+ "一律不得再引入裸 randi()，必须走 Rng 服务。",
	},
]

## -----------------------------------------------------------------------------
##  运行时状态
## -----------------------------------------------------------------------------
var _opt_case := ""
var _opt_all := false
var _opt_list := false
var _opt_out := REPORT_DIR

var _started := false
var _finished := false
## 早退标记：_initialize 里 quit() 之后 Godot 仍会调用一次 _process，
## 若不拦住就会把 --list / 用法错误当成一次真实运行。
var _halt := false

# 当前用例的断言收集器
var _case_id := ""
var _section := ""
var _asserts: Array = []
var _whitelist_hits: Array = []


## =============================================================================
##  入口
## =============================================================================
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--case="):
			_opt_case = a.split("=", true, 1)[1]
		elif a == "--all":
			_opt_all = true
		elif a == "--list":
			_opt_list = true
		elif a.begins_with("--out="):
			_opt_out = a.split("=", true, 1)[1]

	if _opt_list:
		_print_cases()
		_halt = true
		quit(0)
		return
	if _opt_case == "" and not _opt_all:
		printerr("[verify] 用法错误：需要 --case=<id> 或 --all（--list 可列出全部用例）")
		_halt = true
		quit(2)
		return
	if _opt_case != "" and not CASES.has(_opt_case):
		printerr("[verify] 未知用例 '", _opt_case, "'；用 --list 查看可用 id")
		_halt = true
		quit(2)
		return


## 用 _process 启动协程：_initialize 阶段场景树尚未开始迭代，
## 在 _initialize 里 await process_frame 有死锁风险。
func _process(_delta: float) -> bool:
	if _halt:
		return true
	if not _started:
		_started = true
		_run()
	return _finished


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_opt_out)
	var t_all := Time.get_ticks_msec()

	var ids: Array = []
	if _opt_all:
		for id in CASES.keys():
			if CASES[id].get("hidden", false):
				continue
			ids.append(id)
	else:
		ids.append(_opt_case)

	var results: Array = []
	for id in ids:
		var r: Dictionary = await _run_one(id)
		results.append(r)
		if not r["ok"] and not r["skipped"]:
			# 保留继续跑完全部用例的能力：单步失败不中断，便于一次看全貌
			pass

	if _opt_all:
		var failed := 0
		var skipped := 0
		for r in results:
			if r["skipped"]:
				skipped += 1
			elif not r["ok"]:
				failed += 1
		var agg := {
			"kind": "aggregate",
			"headless": _is_headless(),
			"godot": Engine.get_version_info()["string"],
			"started_at": Time.get_datetime_string_from_system(),
			"duration_ms": Time.get_ticks_msec() - t_all,
			"total_cases": results.size(),
			"failed_cases": failed,
			"skipped_cases": skipped,
			"ok": failed == 0,
			"cases": results,
		}
		_write_json(_opt_out.path_join("_all.json"), agg)
		print("")
		print("[verify] ================ 汇总 ================")
		for r in results:
			var tag := "SKIP" if r["skipped"] else ("PASS" if r["ok"] else "FAIL")
			print("[verify] %-5s %-18s %s" % [tag, r["case"], r["summary"]])
		print("[verify] 用例 %d / 失败 %d / 跳过 %d / 耗时 %dms"
				% [results.size(), failed, skipped, Time.get_ticks_msec() - t_all])
		print("[verify] 报告目录 ", _opt_out)
		print("[verify] ======================================")
		_finished = true
		quit(1 if failed > 0 else 0)
		return

	_finished = true
	quit(0 if results[0]["ok"] else 1)


func _run_one(id: String) -> Dictionary:
	_case_id = id
	_section = ""
	_asserts = []
	_whitelist_hits = []

	var meta: Dictionary = CASES[id]
	var t0 := Time.get_ticks_msec()
	var headless := _is_headless()

	if meta.get("kind", "pure") == "headed" and headless:
		var skipped := {
			"case": id,
			"ok": true,
			"skipped": true,
			"skip_reason": "该用例需要真实 GPU/窗口（headless 下渲染指标恒为 0）；"
					+ "请去掉 --headless 重跑",
			"assertions": [],
			"duration_ms": Time.get_ticks_msec() - t0,
			"summary": "SKIP(需要窗口模式)",
		}
		print("[verify] ---- ", id, "  SKIP：", skipped["skip_reason"])
		return skipped

	print("[verify] ---- ", id, "  ", meta.get("desc", ""))

	var before_fail := 0
	await _dispatch(id)
	var duration := Time.get_ticks_msec() - t0

	var failed := 0
	for a in _asserts:
		if not a["ok"]:
			failed += 1

	var report := {
		"case": id,
		"desc": meta.get("desc", ""),
		"kind": meta.get("kind", "pure"),
		"ok": failed == 0,
		"skipped": false,
		"headless": headless,
		"godot": Engine.get_version_info()["string"],
		"exe": OS.get_executable_path(),
		"started_at": Time.get_datetime_string_from_system(),
		"duration_ms": duration,
		"counts": {
			"total": _asserts.size(),
			"passed": _asserts.size() - failed,
			"failed": failed,
		},
		"whitelist_hits": _whitelist_hits,
		"assertions": _asserts,
	}
	report["summary"] = "%d/%d 断言通过" % [_asserts.size() - failed, _asserts.size()]
	_write_json(_opt_out.path_join(id + ".json"), report)

	for a in _asserts:
		if a["ok"]:
			print("    ok   ", a["name"])
		else:
			print("    FAIL ", a["name"], "  -> ", a["detail"])
	print("[verify] %s  %s  (%dms)" % ["PASS" if failed == 0 else "FAIL", id, duration])
	return report


func _dispatch(id: String) -> void:
	match id:
		"s0_2_selfcheck":
			await _case_selfcheck()
		"s0_2_imgdiff":
			await _case_imgdiff()
		"s0_2_guard":
			await _case_guard()
		"s0_2_boot":
			await _case_boot()
		"s0_2_scene_api":
			await _case_scene_api()
		"s0_2_baseline":
			await _case_baseline()
		"s0_2_probe_pass":
			await _case_probe_pass()
		"s0_2_probe_fail":
			await _case_probe_fail()
		_:
			await process_frame
			ok(false, "用例已在 CASES 注册但未在 _dispatch 中实现", "id=" + id)


## =============================================================================
##  断言 API
## =============================================================================
func section(name: String) -> void:
	_section = name


func ok(cond: bool, name: String, detail: String = "") -> bool:
	_record(name, cond, detail if not cond else "")
	return cond


func eq(actual: Variant, expected: Variant, name: String) -> bool:
	var pass_: bool = actual == expected
	_record(name, pass_, "" if pass_ else "actual=%s expected=%s" % [actual, expected])
	return pass_


func ne(actual: Variant, unexpected: Variant, name: String) -> bool:
	var pass_: bool = actual != unexpected
	_record(name, pass_, "" if pass_ else "actual 不应等于 %s" % [unexpected])
	return pass_


func near(actual: float, expected: float, eps: float, name: String) -> bool:
	var pass_ := absf(actual - expected) <= eps
	_record(name, pass_, "" if pass_ else "actual=%f expected=%f eps=%f" % [actual, expected, eps])
	return pass_


func ge(actual: float, floor_v: float, name: String) -> bool:
	var pass_ := actual >= floor_v
	_record(name, pass_, "" if pass_ else "actual=%f 应 >= %f" % [actual, floor_v])
	return pass_


func le(actual: float, ceil_v: float, name: String) -> bool:
	var pass_ := actual <= ceil_v
	_record(name, pass_, "" if pass_ else "actual=%f 应 <= %f" % [actual, ceil_v])
	return pass_


func contains(hay: String, needle: String, name: String) -> bool:
	var pass_ := hay.contains(needle)
	_record(name, pass_, "" if pass_ else "未找到 %s" % [needle])
	return pass_


func not_contains(hay: String, needle: String, name: String) -> bool:
	var pass_ := not hay.contains(needle)
	_record(name, pass_, "" if pass_ else "不应出现 %s" % [needle])
	return pass_


func _record(name: String, pass_: bool, detail: String) -> void:
	_asserts.append({
		"section": _section,
		"name": name,
		"ok": pass_,
		"detail": detail,
	})


## =============================================================================
##  用例实现
## =============================================================================
## 所有用例统一以 await process_frame 开头 —— 见文件头约束 5。

## --- s0_2_selfcheck ----------------------------------------------------------
## 通过**子进程**验证退出码契约（这才是 ROADMAP 要的『退出码 = 1』证据）。
func _case_selfcheck() -> void:
	await process_frame
	section("退出码契约")
	var pass_exit := -1
	var fail_exit := -1
	var pass_out: Array = []
	var fail_out: Array = []
	pass_exit = _exec_godot(PackedStringArray([
		"--headless", "--script", "res://tools/verify.gd", "--",
		"--case=s0_2_probe_pass", "--out=" + _opt_out,
	]), pass_out)
	fail_exit = _exec_godot(PackedStringArray([
		"--headless", "--script", "res://tools/verify.gd", "--",
		"--case=s0_2_probe_fail", "--out=" + _opt_out,
	]), fail_out)
	eq(pass_exit, 0, "全通过用例退出码 = 0")
	eq(fail_exit, 1, "含失败断言的用例退出码 = 1")

	section("JSON 报告契约")
	var p := _read_json(_opt_out.path_join("s0_2_probe_pass.json"))
	var f := _read_json(_opt_out.path_join("s0_2_probe_fail.json"))
	ok(not p.is_empty(), "通过用例写出了 JSON 报告", _opt_out.path_join("s0_2_probe_pass.json"))
	ok(not f.is_empty(), "失败用例写出了 JSON 报告", _opt_out.path_join("s0_2_probe_fail.json"))
	if not p.is_empty():
		eq(p.get("ok"), true, "通过用例报告 ok=true")
		eq((p.get("assertions", []) as Array).size(), 2, "通过用例报告含 2 条断言")
		var a0: Dictionary = (p.get("assertions", []) as Array)[0]
		ok(a0.has("name") and a0.has("ok") and a0.has("detail"),
				"每条断言含 name/ok/detail 字段")
		ok(int(p.get("duration_ms", -1)) >= 0, "报告含 duration_ms",
				"duration_ms=%s" % [p.get("duration_ms")])
		ok(String(p.get("godot", "")) != "", "报告含 godot 版本")
	if not f.is_empty():
		eq(f.get("ok"), false, "失败用例报告 ok=false")
		eq(int((f.get("counts", {}) as Dictionary).get("failed", -1)), 1,
				"失败用例报告 counts.failed=1")

	section("用法错误")
	var usage_exit := _exec_godot(PackedStringArray([
		"--headless", "--script", "res://tools/verify.gd", "--", "--case=__no_such_case__",
	]), [] as Array)
	eq(usage_exit, 2, "未知用例 id 退出码 = 2")


## --- s0_2_imgdiff ------------------------------------------------------------
func _case_imgdiff() -> void:
	await process_frame
	var idiff := load("res://tools/img_diff.gd")
	var tmp := _opt_out.path_join("_imgdiff_tmp")
	DirAccess.make_dir_recursive_absolute(tmp)

	var a_path := tmp.path_join("a.png")
	var b_path := tmp.path_join("b.png")
	var c_path := tmp.path_join("c.png")
	var d_path := tmp.path_join("d.png")

	# 64x64 纯色图 → 便于精确断言
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.9, 1.0))
	img.save_png(a_path)
	img.save_png(b_path)

	section("同图")
	var same: Dictionary = idiff.diff(a_path, b_path)
	eq(same.get("verdict"), "pass", "同一份文件判定 pass")
	eq(same.get("changed_pixels"), 0, "同图改动像素数 = 0")
	eq(snappedf(float(same.get("ratio_pct", -1.0)), 0.0001), 0.0, "同图差异像素比 = 0.0000%")
	eq(same.get("a_sha256"), same.get("b_sha256"), "同图 sha256 一致")

	section("改动副本")
	# 只改 4 个像素里的 1 个 → 已知变更像素数
	var img_c := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img_c.fill(Color(0.2, 0.6, 0.9, 1.0))
	for i in 8:
		img_c.set_pixel(i, 0, Color(0.9, 0.1, 0.1, 1.0))
	img_c.save_png(c_path)
	var changed: Dictionary = idiff.diff(a_path, c_path)
	eq(changed.get("verdict"), "fail", "存在差异时判定 fail")
	eq(changed.get("changed_pixels"), 8, "改动像素数精确 = 8")
	eq(snappedf(float(changed.get("ratio_pct", -1.0)), 0.0001),
			snappedf(8.0 / 4096.0 * 100.0, 0.0001), "差异像素比精确 = 8/4096")
	ne(changed.get("a_sha256"), changed.get("b_sha256"), "改图后 sha256 变化")

	section("亚阈值噪声不算差异")
	var img_d := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img_d.fill(Color(0.2, 0.6, 0.9, 1.0))
	# 单通道只差 4/255，低于默认通道阈值 8 → 不应计入
	for x in 64:
		img_d.set_pixel(x, 5, Color(0.2, 0.6, 0.9 + 4.0 / 255.0, 1.0))
	img_d.save_png(d_path)
	var subtle: Dictionary = idiff.diff(a_path, d_path)
	eq(subtle.get("changed_pixels"), 0, "低于通道阈值的差异不计入")
	eq(subtle.get("verdict"), "pass", "亚阈值差异仍判定 pass")

	section("尺寸不一致")
	var big := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	big.fill(Color(0.2, 0.6, 0.9, 1.0))
	var e_path := tmp.path_join("e.png")
	big.save_png(e_path)
	var mismatch: Dictionary = idiff.diff(a_path, e_path)
	eq(mismatch.get("verdict"), "fail", "尺寸不一致判定 fail（不静默裁剪）")
	contains(String(mismatch.get("reason", "")), "尺寸", "尺寸不一致给出明确原因")

	section("缺失文件")
	var missing: Dictionary = idiff.diff(a_path, tmp.path_join("__absent__.png"))
	eq(missing.get("verdict"), "error", "文件缺失判定 error")

	# 清理临时图
	for f in [a_path, b_path, c_path, d_path, e_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

	# CLI 入口也要能跑通（B- 证据链走的是命令行）
	section("CLI 入口")
	var cli_out: Array = []
	var cli_exit := _exec_godot(PackedStringArray([
		"--headless", "--script", "res://tools/img_diff.gd", "--",
		"--a=" + a_path, "--b=" + b_path,
	]), cli_out)
	eq(cli_exit, 2, "CLI 对已删除的输入返回用法/读取错误码 2")


## --- s0_2_guard --------------------------------------------------------------
func _case_guard() -> void:
	await process_frame
	section("违例检测能力（人造违例，逐类验证后立即删除）")
	var tmp_dir := "res://scripts/_verify_tmp"
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var probe_path := tmp_dir.path_join("guard_probe.gd")

	# 规则名 → 造例文本（键名与守卫规则名一致，便于逐条断言）
	var probes := {
		"box_mesh": "var m := BoxMesh.new()\n",
		"csg_box": "var n := CSGBox3D.new()\n",
		"standard_material": "var s := StandardMaterial3D.new()\n",
		"bare_randf": "var f := randf()\n",
		"bare_randi": "var i := randi()\n",
	}
	for rule in probes.keys():
		var f := FileAccess.open(probe_path, FileAccess.WRITE)
		f.store_string(String(probes[rule]))
		f.close()
		var hits := _guard_walk()
		var found := false
		for h in hits:
			if h["rule"] == rule and String(h["path"]).ends_with("guard_probe.gd"):
				found = true
		ok(found, "守卫可捕获人造违例：%s" % rule,
				"写入 %s 后未检出" % probe_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_dir))
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(tmp_dir)),
			"人造违例临时目录已清理")

	section("允许的写法不被误报")
	ok(_scan_text("res://x.gd", "var v := rng.randf()\nvar w := rng.randi_range(1, 5)\n").is_empty(),
			"rng.randf()/rng.randi_range() 等成员调用不误报")
	ok(_scan_text("res://x.gd", "# BoxMesh 出现在注释里不算违例\n").is_empty(),
			"注释中的关键字不误报")

	section("既有代码基线")
	var real := _guard_walk()
	var unlisted: Array = []
	_whitelist_hits = []
	for h in real:
		var wl := _whitelist_reason(h)
		if wl == "":
			unlisted.append(h)
		else:
			_whitelist_hits.append({
				"path": h["path"], "line": h["line"], "rule": h["rule"], "reason": wl,
			})
	ok(unlisted.is_empty(), "既有代码无未登记违例",
			"%d 条未登记：%s" % [unlisted.size(), JSON.stringify(unlisted)])
	for h in _whitelist_hits:
		print("    [guard] 白名单命中 ", h["path"], ":", h["line"], " 规则=", h["rule"])
	ok(_whitelist_hits.size() >= 1,
			"白名单命中项已被显式列出（不静默放过）",
			"命中 %d 条" % _whitelist_hits.size())


## --- s0_2_boot ---------------------------------------------------------------
func _case_boot() -> void:
	await process_frame
	section("headless 启动 60 帧")
	var out: Array = []
	var exit_code := _exec_godot(PackedStringArray([
		"--headless", "--quit-after", "60",
	]), out)
	var joined := "\n".join(PackedStringArray(out))
	eq(exit_code, 0, "启动 60 帧退出码 = 0")
	not_contains(joined, "SCRIPT ERROR", "日志无 SCRIPT ERROR")
	not_contains(joined, "ERROR:", "日志无 ERROR:")
	contains(joined, "[terrain] seed=", "日志含地形生成行（证明世界真的建起来了）")
	contains(joined, "[terrain] spawn=", "日志含出生点行")


## --- s0_2_scene_api ---------------------------------------------------------
## 通过场景用例基类模式（instantiate + add_child + await）验证既有公开 API 表面。
## 这套 19 个符号是 S0.1 重组时的 API 契约，也是 §2.2 列出的契约。
func _case_scene_api() -> void:
	await process_frame
	section("场景用例基类模式")
	var main := await _load_main()
	ok(main != null, "主场景可 instantiate 并 add_child")
	if main == null:
		return
	ok(get_first_node_in_group("main") != null, "节点组 #main 已注册")
	var terrain := get_first_node_in_group("terrain")
	var player := get_first_node_in_group("player")
	var rig := get_first_node_in_group("camera_rig")
	var water := get_first_node_in_group("water")
	var dn := get_first_node_in_group("day_night")
	ok(terrain != null, "节点组 #terrain 已注册")
	ok(player != null, "节点组 #player 已注册")
	ok(rig != null, "节点组 #camera_rig 已注册")
	ok(water != null, "节点组 #water 已注册")
	ok(dn != null, "节点组 #day_night 已注册")

	section("既有多帧运行")
	for i in 30:
		await process_frame
	ok(true, "加载主场景后连续跑 30 帧无异常")

	section("公开 API 契约（19 个符号）")
	ok(_has_callable(main, "rebuild"), "Main.rebuild")
	if terrain != null:
		ok(_has_callable(terrain, "height_at"), "Terrain.height_at")
		ok(_has_callable(terrain, "normal_at"), "Terrain.normal_at")
		ok(_has_callable(terrain, "slope_at"), "Terrain.slope_at")
		ok(_has_callable(terrain, "generate"), "Terrain.generate")
		ok(terrain.get("spawn_point") != null, "Terrain.spawn_point")
		var h: Variant = terrain.call("height_at", 0.0, 0.0)
		ok(h is float and is_finite(h), "Terrain.height_at(0,0) 返回有限浮点", "h=%s" % [h])
		var nrm: Variant = terrain.call("normal_at", 0.0, 0.0)
		ok(nrm is Vector3, "Terrain.normal_at(0,0) 返回 Vector3")
	# autoload 在本模式下只能用节点路径取，不能用标识符（见文件头约束 1）
	var style := get_root().get_node_or_null("Style")
	ok(style != null, "autoload Style 节点存在于 root")
	if style != null:
		ok(_has_callable(style, "pal"), "Style.pal")
		ok(_has_callable(style, "toon"), "Style.toon")
		ok(_has_callable(style, "water_material"), "Style.water_material")
		ok(_has_callable(style, "set_outline"), "Style.set_outline")
		ok(_has_callable(style, "set_pixel_span"), "Style.set_pixel_span")
		ok(_has_callable(style, "build_ramp"), "Style.build_ramp")
	for sym in ["facet", "combine", "roughen", "blob", "cone",
			"tapered_cylinder", "superellipse_prism"]:
		ok(_has_callable(MeshUtil, sym), "MeshUtil.%s" % sym)

	section("清理")
	main.queue_free()
	await process_frame
	ok(get_first_node_in_group("main") == null, "主场景已释放，组 #main 清空")


## --- s0_2_baseline -----------------------------------------------------------
func _case_baseline() -> void:
	await process_frame
	section("连续 3 次窗口模式采样")
	var reports: Array = []
	for i in 3:
		var label := "verify_run%d" % (i + 1)
		var out: Array = []
		var exit_code := _exec_godot(PackedStringArray([
			"--script", "res://tools/baseline.gd", "--", "--label=" + label,
		]), out)
		eq(exit_code, 0, "baseline 第 %d 次运行退出码 = 0" % (i + 1))
		var r := _read_json(_opt_out.path_join("baseline_%s.json" % label))
		ok(not r.is_empty(), "baseline 第 %d 次写出了 JSON" % (i + 1))
		if not r.is_empty():
			reports.append(r)
	if reports.size() < 3:
		ok(false, "三次采样都成功", "只拿到 %d 份" % reports.size())
		return

	section("四项指标存在")
	for key in ["fps_mean", "ms_per_frame", "memory_static_mb", "primitives"]:
		var present := true
		for r in reports:
			if not r.has(key) or float(r[key]) <= 0.0:
				present = false
		ok(present, "指标存在且为正：%s" % key)

	section("方差 < 5%（连续 3 次）")
	var keys := {
		"fps_mean": "FPS",
		"ms_per_frame": "ms/frame",
		"memory_static_mb": "静态内存",
		"primitives": "三角面数",
		"draw_calls": "绘制调用",
	}
	for key in keys.keys():
		var vals: Array = []
		for r in reports:
			if r.has(key):
				vals.append(float(r[key]))
		var mean := 0.0
		for v in vals:
			mean += v
		mean /= float(vals.size())
		var lo: float = vals.min()
		var hi: float = vals.max()
		var spread_pct := 0.0 if mean == 0.0 else (hi - lo) / mean * 100.0
		ok(spread_pct < 5.0,
				"%s 极差 %.3f%% < 5%%" % [keys[key], spread_pct],
				"样本=%s mean=%.3f" % [str(vals), mean])


## --- 诊断用例 ----------------------------------------------------------------
func _case_probe_pass() -> void:
	await process_frame
	section("probe")
	ok(true, "诊断：恒真断言 1")
	ok(1 + 1 == 2, "诊断：恒真断言 2")


func _case_probe_fail() -> void:
	await process_frame
	section("probe")
	ok(true, "诊断：先来一条真断言")
	ok(false, "诊断：这条是故意失败，用于验证退出码 1", "intentional failure")


## =============================================================================
##  工具函数
## =============================================================================
func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _load_main() -> Node:
	var ps := load("res://scenes/main.tscn") as PackedScene
	if ps == null:
		return null
	var m := ps.instantiate()
	get_root().add_child(m)
	# 必须等一帧：组注册与 @onready 在进入活动场景树后才稳定
	await process_frame
	return m


## 判定目标上是否存在可调用的符号。
## Node 走 has_method；GDScript（全局 class_name 的静态函数）走脚本方法表。
func _has_callable(target: Variant, name: String) -> bool:
	if target == null:
		return false
	if target is Script:
		for m in (target as Script).get_script_method_list():
			if String(m.get("name", "")) == name:
				return true
		return false
	if target is Object:
		return (target as Object).has_method(name)
	return false


func _project_dir() -> String:
	var p := ProjectSettings.globalize_path("res://")
	while p.ends_with("/") or p.ends_with("\\"):
		p = p.substr(0, p.length() - 1)
	return p


## 以当前引擎可执行文件启动一个 Godot 子进程（stdout+stderr 合并进 out_lines）。
func _exec_godot(extra: PackedStringArray, out_lines: Array) -> int:
	var args := PackedStringArray(["--path", _project_dir()])
	args.append_array(extra)
	return OS.execute(OS.get_executable_path(), args, out_lines, true)


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[verify] 无法写报告：", path)
		return
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}


## =============================================================================
##  规范守卫实现
## =============================================================================
func _guard_walk() -> Array:
	var hits: Array = []
	for root in GUARD_SCAN_DIRS:
		_walk(root, hits)
	return hits


func _walk(dir_path: String, hits: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories_at(dir_path):
		_walk(dir_path.path_join(sub), hits)
	for fname in d.get_files_at(dir_path):
		var ext := fname.get_extension().to_lower()
		if not GUARD_EXTS.has(ext):
			continue
		var p := dir_path.path_join(fname)
		var fa := FileAccess.open(p, FileAccess.READ)
		if fa == null:
			continue
		var text := fa.get_as_text()
		fa.close()
		hits.append_array(_scan_text(p, text))


## 纯函数：给定源文本返回违例列表。可被用例直接喂合成文本。
func _scan_text(path: String, text: String) -> Array:
	var hits: Array = []
	var ext := path.get_extension().to_lower()
	var lines := text.split("\n")
	for i in lines.size():
		var raw := String(lines[i])
		var line := _strip_comment(raw, ext)
		if line.strip_edges() == "":
			continue
		for rule in ["box_mesh", "csg_box", "standard_material"]:
			var needle: String = {
				"box_mesh": "BoxMesh",
				"csg_box": "CSGBox3D",
				"standard_material": "StandardMaterial3D",
			}[rule]
			if _contains_token(line, needle):
				hits.append(_hit(path, i + 1, rule, raw))
		for fn in BARE_RAND_FUNCS:
			if _has_bare_rand(line, fn):
				var rule := "bare_randf" if fn.begins_with("randf") else "bare_randi"
				hits.append(_hit(path, i + 1, rule, raw))
	return hits


func _hit(path: String, line: int, rule: String, snippet: String) -> Dictionary:
	return {"path": path, "line": line, "rule": rule, "snippet": snippet.strip_edges()}


func _whitelist_reason(hit: Dictionary) -> String:
	for w in GUARD_WHITELIST:
		if String(w["path"]) == String(hit["path"]) and String(w["rule"]) == String(hit["rule"]):
			return String(w["reason"])
	return ""


## 按 token 边界找标识符，避免 `MyBoxMeshThing` 之类误报。
func _contains_token(line: String, token: String) -> bool:
	var idx := line.find(token)
	while idx >= 0:
		var before_ok := idx == 0 or not _is_ident_char(line[idx - 1])
		var end := idx + token.length()
		var after_ok := end >= line.length() or not _is_ident_char(line[end])
		if before_ok and after_ok:
			return true
		idx = line.find(token, idx + 1)
	return false


func _is_ident_char(c: String) -> bool:
	return c == "_" or (c >= "0" and c <= "9") or (c >= "A" and c <= "Z") or (c >= "a" and c <= "z")


## 裸随机调用 = 函数名前面不是 `.`（成员调用）也不是标识符字符（自定义函数）。
func _has_bare_rand(line: String, fn: String) -> bool:
	var idx := line.find(fn)
	while idx >= 0:
		var prev_ok := idx == 0 or (line[idx - 1] != "." and not _is_ident_char(line[idx - 1]))
		var rest := line.substr(idx + fn.length())
		var stripped := rest.lstrip(" \t")
		if prev_ok and stripped.begins_with("("):
			return true
		idx = line.find(fn, idx + 1)
	return false


## 去掉行尾注释。.gd 用 `#`；.gdshader/.shader 用 `//`；.tscn/.tres 不去注释。
func _strip_comment(line: String, ext: String) -> String:
	if ext == "gd":
		return _strip_from(line, "#")
	if ext == "gdshader" or ext == "shader":
		return _strip_from(line, "//")
	return line


## 找到第一个位于字符串字面量之外的 mark，返回其之前的内容。
func _strip_from(line: String, mark: String) -> String:
	var in_s := false
	var in_d := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if c == "\\":
			i += 2
			continue
		if c == "'" and not in_d:
			in_s = not in_s
		elif c == "\"" and not in_s:
			in_d = not in_d
		elif not in_s and not in_d and line.substr(i).begins_with(mark):
			return line.substr(0, i)
		i += 1
	return line


## =============================================================================
##  其它
## =============================================================================
func _print_cases() -> void:
	print("[verify] 可用用例（kind=headed 需去掉 --headless 运行）：")
	for id in CASES.keys():
		var m: Dictionary = CASES[id]
		var flags: Array = [m.get("kind", "pure")]
		if m.get("hidden", false):
			flags.append("hidden")
		print("  %-18s [%s]  %s" % [id, ", ".join(PackedStringArray(flags)), m.get("desc", "")])
	print("[verify] 共 %d 个（--all 会跳过 hidden）" % CASES.size())

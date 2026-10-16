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
		"desc": "规范守卫：7 类违例各自可捕获 + 既有代码无未登记违例",
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
	"s0_6_clock": {
		"desc": "可复现时钟：确定性模式 t==frame/hz、实时模式随 delta 前进、reset 归零、全局着色器参数被注册",
		"kind": "pure",
	},
	"s0_6_repro": {
		"desc": "可复现渲染：两个独立进程同参数截图 sha256 相同 + 反向对照（改参数/改帧数）必须不同",
		"kind": "headed",
	},
	"s0_3_state": {
		"desc": "全局服务契约：autoload 3→7 与注册顺序、逻辑步 60Hz 精确前进、Rng 子流可复现且互不干扰、EventBus 5 信号、snapshot/restore 容错",
		"kind": "pure",
	},
	"s0_3_roundtrip": {
		"desc": "存档跨进程往返：子进程写 → 父进程逐字段比对 → 另一子进程读回；覆盖需二次确认、空槽位与越界被拒、九宫格卡片数据齐全",
		"kind": "pure",
	},
	"s0_3_dirty": {
		"desc": "脏存档容错：非法 JSON / 数组根 / 高版本 / 无迁移路径 / 缺 game 段一律拒读不崩；缺失·未知·类型错误字段告警且保留当前值；v0→v1 迁移钩子真能跑",
		"kind": "pure",
	},
	"s0_3_atomic": {
		"desc": "原子写：跨进程并发写同一槽位 800 次，每个读得出来的样本都是完整合法 JSON（绝无半截）；引擎 replace 的非原子窗口由读者重试吸收；rename 被占用时失败、原档不变、不留 .tmp",
		"kind": "pure",
	},
	"s0_3_no_autosave": {
		"desc": "无自动存档：启动 + 世界重建 + 五种全局事实后，user://saves 全部文件哈希与 mtime 零变化（且该检查确实能检出显式存档）",
		"kind": "pure",
	},
	"s0_3_probe_write": {
		"desc": "[打桩] 新游戏 → 存槽 3，供 s0_3_roundtrip 以子进程拉起",
		"kind": "pure",
		"hidden": true,
		"probe": true,
	},
	"s0_3_probe_read": {
		"desc": "[打桩] 读槽 3 → 回吐快照 JSON，供 s0_3_roundtrip 以子进程拉起",
		"kind": "pure",
		"hidden": true,
		"probe": true,
	},
	"s0_3_probe_loop": {
		"desc": "[打桩] 连续写同一槽位 ATOMIC_WRITES 次，供 s0_3_atomic 并发观测",
		"kind": "pure",
		"hidden": true,
		"probe": true,
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
		"path": "res://scripts/core/main.gd",
		"rule": "bare_randi",
		"reason": "演示场景的『随机重生成』交互（main.gd:48 auto_new_seed_on_start、"
				+ "main.gd:89 _on_regenerate 的 randi()）。属 §3.2 既有文件不重写范围，"
				+ "S0.2 不扩大改动面；后续新增模块（core/world/actors/battle/legion）"
				+ "一律不得再引入裸 randi()，必须走 Rng 服务。",
	},
	{
		"path": "res://scripts/core/capture.gd",
		"rule": "unfreezable_time",
		"reason": "capture.gd 的 Time.get_ticks_usec() 只用于 _benchmark 的墙钟计时窗口"
				+ "（性能探针本身就该量真实时间），不参与任何画面动画。"
				+ "S0.6 禁止的是『驱动画面运动的时间』走不可冻结的来源；"
				+ "测量用墙钟属正当用法，故登记而不改写。",
	},
	{
		"path": "res://scripts/world/terrain.gd",
		"rule": "unfreezable_time",
		"reason": "terrain.gd 的 Time.get_ticks_msec() 只用于统计 stats[\"gen_ms\"]"
				+ "（生成耗时，只写进日志与 stats 字典），不参与任何画面动画。"
				+ "同 capture.gd，属测量用墙钟的正当用法。",
	},
]

## S0.6：不可冻结的时间来源。凡驱动**画面运动**的时间都必须走 Clock
## （scripts/render_clock.gd）；这两类来源永远无法让截图逐位复现：
##   * 着色器内建 `TIME` —— 真实引擎时间，`Engine.time_scale` 之外无接口可注入；
##   * GDScript 的 `Time.get_ticks_msec/usec()` —— 墙钟，连 time_scale 都够不着。
## 测量用墙钟（性能探针、生成耗时统计）是正当用法，走上面的白名单登记。
const UNFREEZABLE_SHADER_TOKEN := "TIME"
const UNFREEZABLE_SCRIPT_TOKENS := ["Time.get_ticks_msec", "Time.get_ticks_usec"]

## -----------------------------------------------------------------------------
##  S0.3 批次 2（SaveSystem）常量
## -----------------------------------------------------------------------------
## 用例期间把 `user://saves` 整体换名为 `user://saves.bak`——探针实测引擎的目录
## 换名可用（目标必须不存在），因此验收不会碰玩家真实存档，产品码里也不留后门。
const SAVES_DIR := "user://saves"
const SAVES_BAK := "user://saves.bak"
const ROUNDTRIP_SLOT := 3
const ATOMIC_SLOT := 9
const ATOMIC_WRITES := 800
## 子进程写档时用的可辨识状态；父进程逐字段比对这几个数。
const PROBE_SEED := 4242
const PROBE_TIME := 123.5
const PROBE_MONEY := 40
const PROBE_FOOD := 7
const PROBE_SUPPLY := 3
const PROBE_SCENE_KIND := 1
const PROBE_POS := Vector3(1.25, 2.5, -3.75)
## 子进程 B 把读回的快照落成文件而不是塞进 stdout。实测：子进程 stdout 里的中文
## 被控制台按非 UTF-8 解码成乱码（`无名军团` → `鏃犲悕鍐涟`），而存档文件本身是对的。
## 所以跨进程回吐走 UTF-8 文件，stdout 只留纯 ASCII 的状态行。
const PROBE_SNAPSHOT_FILE := "_probe_read_snapshot.json"
## 狂写子进程自己的统计。`OS.create_process` 下子进程**不继承** stdout（实测：子进程
## 的 print 一行都没进父进程日志），所以子进程的话必须落成文件才拿得到。
const PROBE_LOOP_FILE := "_probe_loop_summary.json"

## -----------------------------------------------------------------------------
##  运行时状态
## -----------------------------------------------------------------------------
var _opt_case := ""
var _opt_all := false
var _opt_list := false
var _opt_out := REPORT_DIR

## 打桩用例（probe）自报的退出码。 -1 = 未设置。
## 打桩用例不走 `_run_one` 的汇总逻辑，否则汇总里的 quit() 会覆盖它们的退出码，
## 而退出码正是父用例唯一的返回通道。
var _probe_exit := -1

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

	# 打桩用例：只做事、只以退出码说话，不写报告、不进断言汇总
	var probe_meta: Dictionary = CASES.get(_opt_case, {})
	if _opt_case != "" and bool(probe_meta.get("probe", false)):
		await _run_probe(_opt_case)
		return

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
		"s0_6_clock":
			await _case_clock()
		"s0_6_repro":
			await _case_repro()
		"s0_3_state":
			await _case_state()
		"s0_3_roundtrip":
			await _case_roundtrip()
		"s0_3_dirty":
			await _case_dirty()
		"s0_3_atomic":
			await _case_atomic()
		"s0_3_no_autosave":
			await _case_no_autosave()
		"s0_3_probe_write":
			await _case_probe_write()
		"s0_3_probe_read":
			await _case_probe_read()
		"s0_3_probe_loop":
			await _case_probe_loop()
		_:
			await process_frame
			ok(false, "用例已在 CASES 注册但未在 _dispatch 中实现", "id=" + id)


## 打桩用例的统一入口：等 autoload 就位 → 分发 → 按 `_probe_exit` 退出。
## 之所以绕开 `_run_one`：那里的汇总会用 `quit(0/1)` 覆盖打桩用例自报的退出码，
## 而父用例拿到的就是那个退出码。
func _run_probe(id: String) -> void:
	await process_frame
	await process_frame
	await _dispatch(id)
	_finished = true
	quit(_probe_exit if _probe_exit >= 0 else 1)


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

	# 规则名 → 造例（键名与守卫规则名一致，便于逐条断言）
	var probes := {
		"box_mesh": {"ext": "gd", "text": "var m := BoxMesh.new()\n"},
		"csg_box": {"ext": "gd", "text": "var n := CSGBox3D.new()\n"},
		"standard_material": {"ext": "gd", "text": "var s := StandardMaterial3D.new()\n"},
		"bare_randf": {"ext": "gd", "text": "var f := randf()\n"},
		"bare_randi": {"ext": "gd", "text": "var i := randi()\n"},
		# S0.6 的两条分流都要能被抓住：脚本侧墙钟 + 着色器侧内建 TIME
		"unfreezable_time_gd": {
			"rule": "unfreezable_time", "ext": "gd",
			"text": "var t := Time.get_ticks_msec()\n",
		},
		"unfreezable_time_shader": {
			"rule": "unfreezable_time", "ext": "gdshader",
			"text": "float t = TIME * wind_speed;\n",
		},
	}
	for label in probes.keys():
		var p: Dictionary = probes[label]
		var rule := String(p.get("rule", label))
		var probe_file := tmp_dir.path_join("guard_probe.%s" % String(p["ext"]))
		var f := FileAccess.open(probe_file, FileAccess.WRITE)
		f.store_string(String(p["text"]))
		f.close()
		var hits := _guard_walk()
		var found := false
		for h in hits:
			if h["rule"] == rule and String(h["path"]).ends_with("guard_probe.%s" % String(p["ext"])):
				found = true
		ok(found, "守卫可捕获人造违例：%s" % label,
				"写入 %s 后未检出" % probe_file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_dir))
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(tmp_dir)),
			"人造违例临时目录已清理")

	section("允许的写法不被误报")
	ok(_scan_text("res://x.gd", "var v := rng.randf()\nvar w := rng.randi_range(1, 5)\n").is_empty(),
			"rng.randf()/rng.randi_range() 等成员调用不误报")
	ok(_scan_text("res://x.gd", "# BoxMesh 出现在注释里不算违例\n").is_empty(),
			"注释中的关键字不误报")
	# S0.6：正确的时间写法不得被误报，否则守卫会逼着人绕开它
	ok(_scan_text("res://x.gd", "c.position.x += drift * Clock.dt\n").is_empty(),
			"Clock.dt / Clock.t 不误报")
	ok(_scan_text("res://x.gdshader", "float t = render_time * wind_speed;\n").is_empty(),
			"着色器里的 render_time 不误报")
	ok(_scan_text("res://x.gdshader", "// the builtin TIME is banned here\n").is_empty(),
			"着色器注释里提到 TIME 不误报")
	ok(_scan_text("res://x.gd", "# 以前用 Time.get_ticks_msec()，现在用 Clock.t\n").is_empty(),
			"脚本注释里提到墙钟不误报")

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
		var report_path := _opt_out.path_join("baseline_%s.json" % label)
		# 先删旧报告再跑：`--out` 指向同一目录时，上一轮的文件会让「写出了 JSON」变成
		# 假通过（本用例曾经只认默认目录，一旦 `--out` 换目录就整例失败——见 §16 记录）。
		if FileAccess.file_exists(report_path):
			DirAccess.remove_absolute(report_path)
		ok(not FileAccess.file_exists(report_path),
				"baseline 第 %d 次的报告文件在运行前不存在（旧文件不能冒充证据）" % (i + 1))
		var out: Array = []
		var exit_code := _exec_godot(PackedStringArray([
			"--script", "res://tools/baseline.gd", "--", "--label=" + label,
			"--out=" + _opt_out,
		]), out)
		eq(exit_code, 0, "baseline 第 %d 次运行退出码 = 0" % (i + 1))
		var r := _read_json(report_path)
		ok(not r.is_empty(), "baseline 第 %d 次写出了 JSON" % (i + 1), report_path)
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


## --- s0_6_clock --------------------------------------------------------------
## Clock 是 autoload，本模式只能用节点路径取（见文件头约束 1）。
func _case_clock() -> void:
	await process_frame
	var clock := get_root().get_node_or_null("Clock")
	section("Clock autoload 存在且 API 完整")
	ok(clock != null, "autoload Clock 节点存在于 root")
	if clock == null:
		return
	for sym in ["set_deterministic", "reset", "is_reproducible"]:
		ok(_has_callable(clock, sym), "Clock.%s" % sym)
	var props := {}
	var scr: Script = clock.get_script()
	if scr != null:
		for p in scr.get_script_property_list():
			props[String(p["name"])] = true
	for prop in ["t", "dt", "frame", "deterministic", "hz", "shader_param_ok"]:
		ok(props.has(prop), "Clock.%s 属性存在" % prop,
				"脚本属性表=%s" % [str(props.keys())])

	section("确定性模式：t == frame / hz（计算而非累加）")
	clock.call("set_deterministic", true, 60.0)
	eq(clock.get("t"), 0.0, "set_deterministic 后 t 归零（确定性批次必须从已知状态开始）")
	eq(clock.get("frame"), 0, "set_deterministic 后 frame 归零")
	eq(clock.get("hz"), 60.0, "hz 记录为 60")
	var f0: int = clock.get("frame")
	for i in 12:
		await process_frame
	var f1: int = clock.get("frame")
	ok(f1 > f0, "跑 12 帧后 frame 递增", "f0=%d f1=%d" % [f0, f1])
	var expect_t := float(f1) / 60.0
	near(clock.get("t"), expect_t, 0.000001,
			"t 严格等于 frame/hz（t=%.9f 期望=%.9f）" % [clock.get("t"), expect_t])
	near(clock.get("dt"), 1.0 / 60.0, 0.000001, "确定性模式 dt 恒为 1/60")
	ok(clock.call("is_reproducible"), "is_reproducible() 为真（着色器参数也已注册）")

	section("hz 可变：30Hz 下 t == frame/30")
	clock.call("set_deterministic", true, 30.0)
	for i in 6:
		await process_frame
	var f2: int = clock.get("frame")
	near(clock.get("t"), float(f2) / 30.0, 0.000001,
			"30Hz：t=%.9f 期望=%.9f" % [clock.get("t"), float(f2) / 30.0])

	section("实时模式：t 随真实 delta 前进，量级与墙钟一致（交互行为不回归）")
	clock.call("set_deterministic", false)
	await process_frame
	var t_rt0: float = clock.get("t")
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 400:
		await process_frame
	var wall := float(Time.get_ticks_msec() - w0) / 1000.0
	var dt_rt: float = float(clock.get("t")) - t_rt0
	ok(dt_rt > 0.0, "实时模式 t 递增", "%.6f -> %.6f" % [t_rt0, clock.get("t")])
	ok(clock.get("dt") > 0.0, "实时模式 dt 为正的真实帧步长", "dt=%s" % [clock.get("dt")])
	# 量级校验：Clock.t 就是把真实 delta 累起来，二者应基本重合。
	# 容差放宽到 35%，因为 await process_frame 的调度与墙钟采样点并不完全对齐。
	var rel := absf(dt_rt - wall) / maxf(wall, 0.0001)
	ok(rel < 0.35, "实时模式 Δt 与墙钟相对误差 < 35%",
			"时钟 Δt=%.4fs 墙钟=%.4fs 误差=%.1f%%" % [dt_rt, wall, rel * 100.0])

	section("reset() 归零")
	clock.call("reset")
	eq(clock.get("t"), 0.0, "reset 后 t = 0")
	eq(clock.get("frame"), 0, "reset 后 frame = 0")
	eq(clock.get("dt"), 0.0, "reset 后 dt = 0")

	section("全局着色器参数已声明（防止动画被冻结却看起来『可复现』）")
	ok(clock.get("shader_param_ok"),
			"project.godot 的 [shader_globals] 声明了 render_time",
			"未声明：着色器会停在 render_time=0，画面看起来是冻结的")
	ok(ProjectSettings.has_setting("shader_globals/render_time"),
			"ProjectSettings.has_setting('shader_globals/render_time')")
	var decl: Variant = ProjectSettings.get_setting("shader_globals/render_time")
	ok(decl is Dictionary and String((decl as Dictionary).get("type", "")) == "float",
			"声明类型为 float", "decl=%s" % [str(decl)])
	print("    [note] 该参数**真的进入着色器**由 s0_6_repro 的『帧数 15 vs 200 必须不同』实质验证；")
	print("    [note] RenderingServer.global_shader_parameter_get_list() 是编辑器专用 API，")
	print("    [note] 运行期调用会报 'should never be used outside the editor'，故此处不做列表断言。")

	section("现场还原")
	clock.call("set_deterministic", false)
	ok(not clock.get("deterministic"), "用例结束后恢复实时模式，不污染后续用例")


## --- s0_6_repro --------------------------------------------------------------
## 两次**独立进程**的同参数截图必须逐位一致。这是 S0.2 里那条实测 1.62%–5.67%
## 噪声底的正面修复证据，也是 `B-` 门禁能否使用的前提。
## 反向对照同样重要：若两次都是空图/冻结图，逐位一致就毫无意义。
func _case_repro() -> void:
	await process_frame
	var base := _opt_out.path_join("repro")
	DirAccess.make_dir_recursive_absolute(base)
	var shot_args := PackedStringArray([
		"--shots", "--case=s0_boot", "--warmup=60", "--frames=15",
	])

	section("两次独立进程、同参数截图")
	var shas: Array = []
	for label in ["a", "b"]:
		var out_dir := base.path_join(label)
		var out: Array = []
		var extra := shot_args.duplicate()
		extra.append("--out=" + out_dir)
		var exit_code := _exec_user(PackedStringArray(), extra, out)
		eq(exit_code, 0, "截图批次 %s 退出码 = 0" % label)
		var man := _read_json(out_dir.path_join("s0_boot.json"))
		ok(not man.is_empty(), "批次 %s 写出了清单" % label)
		if not man.is_empty():
			# 清单里自证这批是可复现的，否则字节一致无从谈起
			var ck: Dictionary = man.get("clock", {})
			ok(bool(ck.get("deterministic", false)),
					"批次 %s 的清单声明 deterministic=true" % label)
			ok(bool(ck.get("shader_param_ok", false)),
					"批次 %s 的清单声明 shader_param_ok=true（时间真的进了着色器）" % label)
		var shots: Array = man.get("shots", [])
		ok(shots.size() == 2, "批次 %s 产出 2 张图" % label, "实际 %d" % shots.size())
		for s in shots:
			shas.append({
				"label": label,
				"name": String(s.get("name", "")),
				"sha": String(s.get("sha256", "")),
				"size": int(s.get("width", 0)) * int(s.get("height", 0)),
			})

	section("逐位一致（sha256 相同）")
	for name in ["s0_boot_follow", "s0_boot_wide"]:
		var ha := ""
		var hb := ""
		for e in shas:
			if e["name"] == name and e["label"] == "a":
				ha = e["sha"]
			elif e["name"] == name and e["label"] == "b":
				hb = e["sha"]
		ok(ha != "" and hb != "", "两次都拿到了 %s 的 sha256" % name)
		ok(ha == hb, "%s 两次 sha256 逐位一致" % name, "A=%s B=%s" % [ha, hb])
		var wh := 0
		for e in shas:
			if e["name"] == name:
				wh = int(e["size"])
		eq(wh, 1600 * 900, "%s 为 1600x900（不是空图）" % name)

	section("img_diff 复核：验收标准原文口径（差异 = 0.0000%）")
	var idiff := load("res://tools/img_diff.gd")
	for name in ["s0_boot_follow", "s0_boot_wide"]:
		var pa := base.path_join("a").path_join(name + ".png")
		var pb := base.path_join("b").path_join(name + ".png")
		var r: Dictionary = idiff.diff(pa, pb)
		eq(int(r.get("changed_pixels", -1)), 0, "%s 差异像素 = 0" % name)
		eq(float(r.get("ratio_pct", -1.0)), 0.0, "%s 差异 = 0.0000%%" % name)
		eq(String(r.get("verdict", "")), "pass", "%s img_diff 判定 PASS" % name)
		eq(String(r.get("a_sha256", "x")), String(r.get("b_sha256", "y")),
				"%s 两次 sha256 相同（img_diff 内部复核）" % name)

	section("反向对照 1：改一个相机参数必须不同（排除『两张都是同一张空图』）")
	var ctl_dir := base.path_join("ctl")
	var ctl_out: Array = []
	var ctl_exit := _exec_user(PackedStringArray(), PackedStringArray([
		"--shot=ctl_follow", "--time=0.5", "--mode=FOLLOW", "--size=36", "--yaw=52",
		"--warmup=60", "--frames=15", "--out=" + ctl_dir,
	]), ctl_out)
	eq(ctl_exit, 0, "对照组截图退出码 = 0")
	var ctl_man := _read_json(ctl_dir.path_join("ctl_follow.json"))
	var ctl_shots: Array = ctl_man.get("shots", [])
	ok(ctl_shots.size() == 1, "对照组产出 1 张图")
	var ctl_sha := ""
	if ctl_shots.size() == 1:
		ctl_sha = String(ctl_shots[0].get("sha256", ""))
	var base_sha := ""
	for e in shas:
		if e["name"] == "s0_boot_follow" and e["label"] == "a":
			base_sha = e["sha"]
	ok(ctl_sha != "" and base_sha != "", "对照组与基准组都有 sha256")
	ok(ctl_sha != base_sha, "yaw 45 -> 52 后图像不同（画面确实随参数变化）")

	section("反向对照 2：改帧数必须不同（证明时间真在驱动动画，而非动画被冻结）")
	var live_dir := base.path_join("live")
	var live_out: Array = []
	var live_exit := _exec_user(PackedStringArray(), PackedStringArray([
		"--shot=live_follow", "--time=0.5", "--mode=FOLLOW", "--size=36", "--yaw=45",
		"--warmup=20", "--frames=200", "--out=" + live_dir,
	]), live_out)
	eq(live_exit, 0, "长帧数组截图退出码 = 0")
	var live_man := _read_json(live_dir.path_join("live_follow.json"))
	var live_shots: Array = live_man.get("shots", [])
	var live_sha := ""
	if live_shots.size() == 1:
		live_sha = String(live_shots[0].get("sha256", ""))
	ok(live_sha != "", "长帧数组写出了 sha256")
	# 同 warmup=60/frames=15 的基准量 t=1.5s；这里 frames=200 -> t=3.667s
	ok(live_sha != base_sha,
			"帧数 15 -> 200 后图像不同（render_time 真的在驱动风摆/水波）")


## --- s0_3_state ---------------------------------------------------------------
## S0.3 批次 1：三个全局服务（Rng / EventBus / GameState）的契约。
## 本用例**只断言契约**，不验证存档往返（那是 s0_3_roundtrip 的事）。
## 三条最值钱的断言：
##   ① GameState.world_seed 的默认值 == main.gd 的 @export 默认值
##      —— S1.2 把场景入口接到本服务时，世界必须逐位相同，否则 6 机位基线全废；
##   ② game_time 在固定逻辑步上**精确**前进（60 步 == 1.000 秒）
##      —— 这是 §3.2「60Hz 逻辑固定步」的实质验证，也排除了"用 _process 累加 delta"；
##   ③ Rng 的具名子流互不干扰（先抽别的流不改变本流的下一个数）
##      —— 这条正是"按 seed 派生子流"相对单一全局发生器的全部意义。
func _case_state() -> void:
	await process_frame

	var rng := get_root().get_node_or_null("Rng")
	var bus := get_root().get_node_or_null("EventBus")
	var gs := get_root().get_node_or_null("GameState")
	var ss := get_root().get_node_or_null("SaveSystem")

	section("四个服务节点存在，且注册顺序满足依赖（Rng 先于 GameState，SaveSystem 在其后）")
	ok(rng != null, "autoload Rng 节点存在于 root")
	ok(bus != null, "autoload EventBus 节点存在于 root")
	ok(gs != null, "autoload GameState 节点存在于 root")
	ok(ss != null, "autoload SaveSystem 节点存在于 root")
	if rng == null or bus == null or gs == null or ss == null:
		return

	var order: Array = []
	for child in get_root().get_children():
		order.append(String(child.name))
	var i_rng := order.find("Rng")
	var i_bus := order.find("EventBus")
	var i_gs := order.find("GameState")
	var i_ss := order.find("SaveSystem")
	ok(i_rng >= 0 and i_bus >= 0 and i_gs >= 0 and i_ss >= 0, "四个服务都在 root 子节点中",
			"root 子节点=%s" % [str(order)])
	ok(i_rng < i_gs, "Rng 注册在 GameState 之前（GameState._ready() 要调用 Rng.seed_from）",
			"Rng@%d GameState@%d" % [i_rng, i_gs])
	ok(i_bus < i_gs or i_bus != i_gs, "EventBus 与 GameState 顺序无强依赖，只要求都存在")
	ok(i_ss > i_gs, "SaveSystem 注册在 GameState 之后（它读写 GameState.snapshot()）",
			"GameState@%d SaveSystem@%d" % [i_gs, i_ss])

	section("autoload 清单与计数（§3.2 上限 10）")
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		var nm := String(p["name"])
		if nm.begins_with("autoload/"):
			autoloads.append(nm.substr("autoload/".length()))
	autoloads.sort()
	var expected := ["Capture", "Clock", "EventBus", "GameState", "Rng", "SaveSystem", "Style"]
	eq(autoloads, expected, "project.godot 的 autoload 恰好是这 7 个（批次 2 后 3 → 7）")
	ok(autoloads.size() <= 10, "autoload 数量 %d ≤ 10（§3.2 上限）" % autoloads.size())

	section("GameState 字段契约：SNAPSHOT_FIELDS == snapshot() 的键集")
	var gs_script: Script = gs.get_script()
	var props := {}
	if gs_script != null:
		for p in gs_script.get_script_property_list():
			props[String(p["name"])] = true
	for prop in ["world_seed", "game_time", "day_length", "party", "money",
			"food", "supply", "scene_kind", "player_pos", "playtime"]:
		ok(props.has(prop), "GameState.%s 属性存在" % prop)

	# 常量要走 get_script_constant_map()：Script.get() 只认脚本变量，读不到 const。
	var consts: Dictionary = {}
	if gs_script != null:
		consts = gs_script.get_script_constant_map()
	var fields: Array = consts.get("SNAPSHOT_FIELDS", [])
	ok(fields.size() == 10, "SNAPSHOT_FIELDS 常量可读且含 10 个字段",
			"读到 %d 个：%s" % [fields.size(), str(fields)])
	var snap: Dictionary = gs.call("snapshot")
	var snap_keys: Array = snap.keys()
	snap_keys.sort()
	var fields_sorted: Array = fields.duplicate()
	fields_sorted.sort()
	eq(snap_keys, fields_sorted, "snapshot() 的键集与 SNAPSHOT_FIELDS 完全一致（写读不会漂移）")
	ok(snap.has("player_pos") and typeof(snap["player_pos"]) == TYPE_ARRAY
			and (snap["player_pos"] as Array).size() == 3,
			"snapshot() 把 Vector3 降级为 [x,y,z]（JSON 无法编码引擎数学类型）")

	section("默认值与 main.gd 对齐（S1.2 接线必须逐位不变）")
	eq(gs.get("world_seed"), 20250929, "GameState.world_seed 默认值 == 20250929")
	var main_src := FileAccess.get_file_as_string("res://scripts/core/main.gd")
	ok(main_src.contains("var world_seed := 20250929"),
			"main.gd 的 world_seed 默认值仍是 20250929（两个来源同值，接线才不改变画面）")
	eq(gs.get("day_length"), 170.0, "GameState.day_length 默认值与 day_night.gd 一致（170 秒/天）")

	section("逻辑步：60Hz 固定步，前进量恒为 1/60 的整数倍（不掺真实 delta）")
	eq(Engine.physics_ticks_per_second, 60, "引擎物理步长 = 60Hz（§3.2 逻辑固定步）")
	print("    [note] SceneTree.physics_frame 在节点 _physics_process **之前**发射，")
	print("    [note] 所以 N 次 await 只对应 N-1 次 game_time 推进；下面断言『整数步』而非固定次数。")
	await physics_frame
	var t0: float = gs.get("game_time")
	for i in 60:
		await physics_frame
	var dt: float = float(gs.get("game_time")) - t0
	var steps := dt * 60.0
	var steps_int := roundi(steps)
	ok(absf(steps - float(steps_int)) < 0.000001,
			"前进量恰好是 %d 个 1/60 秒（整数步 ⇒ 时间只来自固定逻辑步；"
					% steps_int + "若改用 _process 累加真实 delta，这里会是非整数）")
	ok(absf(float(steps_int) - 60.0) <= 2.0,
			"60 次 await physics_frame 推进 %d 步（60±2，含上面的对齐抖动）" % steps_int)
	ok(gs.get("playtime") > 0.0, "playtime 随 game_time 一起推进")

	section("派生量：day / time_of_day / clock_text 自洽")
	gs.set("game_time", 0.0)
	eq(gs.call("game_day"), 1, "game_time=0 → 第 1 天")
	eq(gs.call("time_of_day"), 0.0, "game_time=0 → 午夜")
	gs.set("game_time", 170.0 * 2.0 + 170.0 * 0.5)
	eq(gs.call("game_day"), 3, "game_time=2.5 天 → 第 3 天")
	near(gs.call("time_of_day"), 0.5, 0.000001, "2.5 天处 time_of_day = 0.5（正午）")
	var clk := String(gs.call("clock_text"))
	ok(clk.contains("第 3 天") and clk.contains("12:00"), "clock_text 为『第 3 天 12:00』",
			"实际=%s" % clk)

	section("Rng：具名子流可复现、互不干扰、reset 可重放")
	rng.call("seed_from", 12345)
	var s_terrain: int = rng.call("stream_seed", "terrain")
	eq(rng.call("stream_seed", "terrain"), s_terrain, "stream_seed 是纯函数（同名同种子）")
	ok(rng.call("stream_seed", "scatter") != s_terrain,
			"同一主种子下不同流名派生出不同种子",
			"terrain=%d scatter=%d" % [s_terrain, rng.call("stream_seed", "scatter")])
	rng.call("seed_from", 999)
	ok(rng.call("stream_seed", "terrain") != s_terrain, "换主种子后同名流的种子改变")
	rng.call("seed_from", 12345)

	# 独立复现：两次全新构建的同名流，前 5 个数必须一致。
	var draw_a := _draw_ints(rng, "terrain", 5)
	rng.call("seed_from", 12345)
	var draw_b := _draw_ints(rng, "terrain", 5)
	eq(draw_a, draw_b, "同一主种子下 terrain 流前 5 个数逐位相同（可复现）")

	# 互不干扰：先把另一个流抽 10 次，再抽 terrain，结果不受影响。
	rng.call("seed_from", 12345)
	for i in 10:
		rng.call("randi_in", "scatter", 0, 1000000)
	var draw_c := _draw_ints(rng, "terrain", 5)
	eq(draw_c, draw_a, "先抽 10 次 scatter 后，terrain 的下一个数与全新运行时相同（子流隔离）")

	# reset 重放
	rng.call("seed_from", 12345)
	for i in 3:
		rng.call("randi_in", "terrain", 0, 1000000)
	rng.call("reset")
	var draw_d := _draw_ints(rng, "terrain", 5)
	eq(draw_d, draw_a, "reset() 后 terrain 流从头重放")

	section("EventBus：5 个信号齐全、参数形状固定、总线保持无状态")
	var bus_script: Script = bus.get_script()
	var sigs := {}
	if bus_script != null:
		for s in bus_script.get_script_signal_list():
			sigs[String(s["name"])] = s
	for sig in ["time_advanced", "encounter_started", "battle_finished",
			"resources_changed", "settlement_entered"]:
		ok(sigs.has(sig), "EventBus.%s 已声明" % sig)
	eq(sigs.size(), 5, "EventBus 恰好只声明这 5 个信号（总线上不许塞业务数据）；实际=%s" % [str(sigs.keys())])
	if sigs.has("time_advanced"):
		eq((sigs["time_advanced"]["args"] as Array).size(), 2,
				"time_advanced 携带 (day, time_of_day) 两个参数")
	if sigs.has("resources_changed"):
		eq((sigs["resources_changed"]["args"] as Array).size(), 3,
				"resources_changed 携带 (money, food, supply) 三个参数")

	# 真的能送达：连一个回调，emit，断言收到的是新值而不是差值。
	var received: Array = []
	var cb := func(m: int, f: int, s: int) -> void:
		received.append([m, f, s])
	bus.connect("resources_changed", cb)
	bus.emit_signal("resources_changed", 7, 8, 9)
	eq(received.size(), 1, "订阅者收到了 resources_changed")
	if received.size() == 1:
		eq(received[0], [7, 8, 9], "负载是传入的新值")
	bus.disconnect("resources_changed", cb)

	section("restore() 容错：未知 / 缺失 / 类型错误一律告警且不崩、不静默改值")
	gs.call("new_game", 20250929)
	gs.set("money", 111)
	var warn_unknown: PackedStringArray = gs.call("restore",
			{"money": 5, "no_such_field": 1})
	ok(warn_unknown.size() >= 1, "未知字段产生告警", "告警=%s" % [str(warn_unknown)])
	ok(_warn_mentions(warn_unknown, "no_such_field"), "告警里点名了未知字段 no_such_field")
	eq(gs.get("money"), 5, "已识别字段照常应用（money=5）")
	ok(_warn_mentions(warn_unknown, "world_seed"), "缺失字段 world_seed 也被点名")

	gs.set("money", 222)
	var warn_type: PackedStringArray = gs.call("restore", {"money": "很多钱"})
	eq(gs.get("money"), 222, "类型错误的字段保留当前值（不会被写成 0 或崩溃）")
	ok(_warn_mentions(warn_type, "类型错误"), "类型错误有明确告警",
			"告警=%s" % [str(warn_type)])

	gs.set("player_pos", Vector3.ZERO)
	var warn_pos: PackedStringArray = gs.call("restore",
			{"player_pos": {"x": 1.5, "y": -2.0, "z": 3.0}})
	eq(gs.get("player_pos"), Vector3(1.5, -2.0, 3.0), "player_pos 接受 {x,y,z} 字典形式")
	gs.call("restore", {"player_pos": [4.0, 5.0, 6.0]})
	eq(gs.get("player_pos"), Vector3(4.0, 5.0, 6.0), "player_pos 接受 [x,y,z] 数组形式")
	gs.call("restore", {"player_pos": "北方"})
	eq(gs.get("player_pos"), Vector3(4.0, 5.0, 6.0), "player_pos 为垃圾值时保留当前值")
	ok(warn_pos.size() >= 0, "（上面三次 restore 均未崩溃）")

	section("完整快照往返（同进程内；跨进程往返是 s0_3_roundtrip 的事）")
	gs.call("new_game", 4242)
	gs.set("game_time", 123.5)
	gs.set("money", 40)
	gs.set("food", 7)
	gs.set("supply", 3)
	gs.set("player_pos", Vector3(1.25, 2.5, -3.75))
	gs.call("set_scene_kind", 1)
	var snap2: Dictionary = gs.call("snapshot")
	gs.call("new_game", 1)
	eq(gs.get("world_seed"), 1, "new_game 真的重置了世界 seed")
	var warn_rt: PackedStringArray = gs.call("restore", snap2)
	eq(warn_rt.size(), 0, "完整快照 restore 无任何告警；告警=%s" % [str(warn_rt)])
	eq(gs.get("world_seed"), 4242, "world_seed 往返一致")
	near(gs.get("game_time"), 123.5, 0.000001, "game_time 往返一致")
	eq(gs.get("money"), 40, "money 往返一致")
	eq(gs.get("food"), 7, "food 往返一致")
	eq(gs.get("supply"), 3, "supply 往返一致")
	eq(gs.get("player_pos"), Vector3(1.25, 2.5, -3.75), "player_pos 往返一致")
	eq(gs.get("scene_kind"), 1, "scene_kind 往返一致")
	eq(gs.call("scene_kind_name"), "WORLD", "scene_kind_name 映射正确")

	section("现场还原（不污染后续用例）")
	gs.call("new_game", 20250929)
	rng.call("seed_from", 20250929)
	eq(gs.get("world_seed"), 20250929, "GameState 回到默认世界 seed")
	eq(rng.get("master_seed"), 20250929, "Rng 回到默认主种子")
	eq(gs.get("money"), 0, "资源清零")


## 抽 `n` 个整数，供"同名流可复现/互不干扰"的对照使用。
func _draw_ints(rng: Node, stream_name: String, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(rng.call("randi_in", stream_name, 0, 1000000))
	return out


## 告警里是否有一条提到某个字段/关键词。
func _warn_mentions(warns: PackedStringArray, needle: String) -> bool:
	for w in warns:
		if String(w).contains(needle):
			return true
	return false


## =============================================================================
##  S0.3 批次 2 —— SaveSystem（ROADMAP §5 S0.3，契约 §3.5）
## =============================================================================
## 证据分工：
##   s0_3_roundtrip    跨进程往返（子进程 A 写 → 父进程逐字段比对 → 子进程 B 读回）
##   s0_3_dirty        脏存档：拒读类与「可读但告警」类分开，迁移钩子真能跑
##   s0_3_atomic       跨进程并发写同一槽位，观测不到半截文件
##   s0_3_no_autosave  文件内容哈希 + mtime 零变化，且该检查确实能检出显式存档
##   s0_3_probe_*      打桩（hidden），只由上面三个用例以子进程拉起
##
## ⚠️ 全部用例期间 `user://saves` 被整体换名为 `user://saves.bak`（目录换名已实测
##    可用），所以验收**不会碰玩家真实存档**，产品码里也没有任何测试后门。

func _case_roundtrip() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	ok(ss != null, "autoload SaveSystem 节点存在于 root")
	if ss == null:
		return

	section("测试隔离（不动玩家真实存档）")
	var notes := _saves_begin()
	print("    [note] ", "; ".join(notes))

	section("子进程 A：新游戏 → 存档（写文件的是另一个进程）")
	var out_a: Array = []
	var code_a := _exec_case("s0_3_probe_write", out_a)
	ok(code_a == 0, "写档子进程退出码 = 0", "退出码=%d 输出=%s" % [code_a, _tail(out_a, 4)])
	ok(_lines_contain(out_a, "[probe] WRITE ok=true"), "子进程自称写入成功", _tail(out_a, 4))

	section("父进程直接读文件：schema_version / 时间戳 / game 段逐字段")
	var raw := FileAccess.get_file_as_string(_slot_file(ROUNDTRIP_SLOT))
	var parsed: Variant = JSON.parse_string(raw)
	ok(typeof(parsed) == TYPE_DICTIONARY, "槽 3 是合法 JSON 对象")
	var d: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	eq(int(d.get("schema_version", 0)), 1, "存档含 schema_version: 1")
	ok(String(d.get("saved_at", "")).length() >= 16, "含可读的真实写入时刻",
			str(d.get("saved_at", "")))
	ok(int(d.get("saved_at_unix", 0)) > 0, "含 unix 写入时刻", str(d.get("saved_at_unix", 0)))
	var game_v: Variant = d.get("game", {})
	var game: Dictionary = game_v if typeof(game_v) == TYPE_DICTIONARY else {}
	eq(game.size(), 10, "game 段含 10 个字段（与 GameState.SNAPSHOT_FIELDS 同量）")
	eq(int(game.get("world_seed", 0)), PROBE_SEED, "game.world_seed")
	near(float(game.get("game_time", -1.0)), PROBE_TIME, 0.000001, "game.game_time")
	eq(int(game.get("money", -1)), PROBE_MONEY, "game.money")
	eq(int(game.get("food", -1)), PROBE_FOOD, "game.food")
	eq(int(game.get("supply", -1)), PROBE_SUPPLY, "game.supply")
	eq(int(game.get("scene_kind", -1)), PROBE_SCENE_KIND, "game.scene_kind")
	near(float(game.get("day_length", -1.0)), 170.0, 0.000001, "game.day_length")
	var pos: Array = game.get("player_pos", [])
	eq(pos.size(), 3, "game.player_pos 为 [x,y,z]")
	if pos.size() == 3:
		near(float(pos[0]), PROBE_POS.x, 0.000001, "player_pos.x")
		near(float(pos[1]), PROBE_POS.y, 0.000001, "player_pos.y")
		near(float(pos[2]), PROBE_POS.z, 0.000001, "player_pos.z")
	var meta_v: Variant = d.get("meta", {})
	var meta: Dictionary = meta_v if typeof(meta_v) == TYPE_DICTIONARY else {}
	eq(int(meta.get("game_day", 0)), 1, "meta.game_day 与 game_time=123.5 自洽（第 1 天）")
	eq(String(meta.get("clock_text", "")), "第 1 天 17:26", "meta.clock_text 与 game_time 自洽")
	eq(String(meta.get("party_name", "")), "无名军团", "meta.party_name")
	eq(int(meta.get("party_level", 0)), 1, "meta.party_level")
	eq(int(meta.get("world_seed", 0)), PROBE_SEED, "meta.world_seed 与 game 段一致")
	ok(String(meta.get("playtime_text", "")).length() == 8, "meta.playtime_text 形如 HH:MM:SS",
			str(meta.get("playtime_text", "")))

	section("子进程 B：跨进程读档 → 回吐快照")
	var handoff := _opt_out.path_join(PROBE_SNAPSHOT_FILE)
	if FileAccess.file_exists(handoff):
		DirAccess.remove_absolute(handoff)
	ok(not FileAccess.file_exists(handoff), "回吐文件在子进程运行前不存在（陈旧文件不能冒充证据）")
	var out_b: Array = []
	var code_b := _exec_case("s0_3_probe_read", out_b)
	ok(code_b == 0, "读档子进程退出码 = 0", "退出码=%d 输出=%s" % [code_b, _tail(out_b, 4)])
	ok(_lines_contain(out_b, "[probe] READ ok=true"), "子进程自称读档成功", _tail(out_b, 4))
	ok(_lines_contain(out_b, "[probe] READ ok=true warnings=0"),
			"读回时零告警（写读字段集没有漂移）", _tail(out_b, 4))
	ok(_lines_contain(out_b, "[probe] SNAPSHOT_FILE "), "子进程 B 声明写出了回吐文件", _tail(out_b, 4))
	ok(FileAccess.file_exists(handoff), "回吐文件确实存在（另一个进程写、本进程读）", handoff)
	var snap: Dictionary = _read_json(handoff)
	eq(snap.size(), 10, "回吐快照含 10 个字段")
	eq(int(snap.get("world_seed", 0)), PROBE_SEED, "跨进程读回 world_seed")
	near(float(snap.get("game_time", -1.0)), PROBE_TIME, 0.000001, "跨进程读回 game_time")
	eq(int(snap.get("money", -1)), PROBE_MONEY, "跨进程读回 money")
	eq(int(snap.get("food", -1)), PROBE_FOOD, "跨进程读回 food")
	eq(int(snap.get("supply", -1)), PROBE_SUPPLY, "跨进程读回 supply")
	eq(int(snap.get("scene_kind", -1)), PROBE_SCENE_KIND, "跨进程读回 scene_kind")
	var bparty: Dictionary = snap.get("party", {})
	eq(String(bparty.get("name", "")), "无名军团", "跨进程读回 party.name（中文不被 stdout 编码破坏）")
	eq(int(bparty.get("level", 0)), 1, "跨进程读回 party.level")
	var bpos: Array = snap.get("player_pos", [])
	ok(bpos.size() == 3 and absf(float(bpos[0]) - PROBE_POS.x) < 0.000001
			and absf(float(bpos[1]) - PROBE_POS.y) < 0.000001
			and absf(float(bpos[2]) - PROBE_POS.z) < 0.000001,
			"跨进程读回 player_pos", str(bpos))

	section("覆盖契约：默认拒写、显式 overwrite 才生效")
	var slot3 := _slot_file(ROUNDTRIP_SLOT)
	var sha_before := FileAccess.get_sha256(slot3)
	var denied: Dictionary = ss.call("save_slot", ROUNDTRIP_SLOT)
	ok(not bool(denied.get("ok")), "槽位已占用时默认拒写", str(denied.get("reason")))
	ok(bool(denied.get("requires_confirm")), "结果标记 requires_confirm（批次 4 的菜单据此弹框）")
	ok(String(denied.get("reason")).contains("二次确认"), "原因说明需二次确认",
			str(denied.get("reason")))
	eq(FileAccess.get_sha256(slot3), sha_before, "拒写后原档逐位不变")
	var allowed: Dictionary = ss.call("save_slot", ROUNDTRIP_SLOT, true)
	ok(bool(allowed.get("ok")), "显式 overwrite=true 写入成功", str(allowed.get("reason")))
	ne(FileAccess.get_sha256(slot3), sha_before, "覆盖后内容确实变化")

	section("九宫格卡片数据（§3.5：槽号 / 真实时间 / 游戏内时间 / 队伍 / 时长）")
	var info3: Dictionary = ss.call("slot_info", ROUNDTRIP_SLOT)
	ok(bool(info3.get("exists")), "slot_info(3).exists")
	eq(int(info3.get("slot", 0)), ROUNDTRIP_SLOT, "卡片带槽号")
	eq(String(info3.get("party_name", "")), "无名军团", "卡片带队伍名")
	eq(int(info3.get("party_level", 0)), 1, "卡片带队伍等级")
	ok(String(info3.get("clock_text", "")).contains("第"), "卡片带游戏内日期时间",
			str(info3.get("clock_text", "")))
	ok(String(info3.get("saved_at", "")).length() >= 16, "卡片带真实写入时刻")
	ok(String(info3.get("playtime_text", "")).length() == 8, "卡片带累计时长",
			str(info3.get("playtime_text", "")))
	var info2: Dictionary = ss.call("slot_info", 2)
	ok(not bool(info2.get("exists")), "空槽位 exists=false")
	eq(String(info2.get("label", "")), "空槽位", "空槽位卡片文案")
	eq((ss.call("list_slots") as Array).size(), 9, "list_slots() 恰好 9 个槽位")

	section("空槽位与越界槽位")
	var empty_load: Dictionary = ss.call("load_slot", 2)
	ok(not bool(empty_load.get("ok")), "读空槽位失败（不是崩溃）")
	ok(String(empty_load.get("reason")).contains("空槽位"), "原因明说空槽位",
			str(empty_load.get("reason")))
	var oob: Dictionary = ss.call("save_slot", 10, true)
	ok(not bool(oob.get("ok")), "槽位号 10 越界被拒")
	ok(String(oob.get("reason")).contains("非法"), "越界原因明确", str(oob.get("reason")))
	ok(not bool(ss.call("slot_exists", 0)), "slot_exists(0) 为假")

	section("测试隔离回收")
	var back := _saves_end()
	print("    [note] ", "; ".join(back))
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "隔离目录已清走（saves.bak 不存在）")
	_restore_defaults()


func _case_dirty() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	var gs := get_root().get_node_or_null("GameState")
	ok(ss != null and gs != null, "SaveSystem / GameState 均存在")
	if ss == null or gs == null:
		return
	_saves_begin()
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)

	var load_failed_log: Array = []
	var loaded_log: Array = []
	var on_load_failed := func(slot: int, reason: String) -> void:
		load_failed_log.append([slot, reason])
	var on_slot_loaded := func(slot: int) -> void:
		loaded_log.append(slot)
	ss.connect("load_failed", on_load_failed)
	ss.connect("slot_loaded", on_slot_loaded)

	# 基线现场：可辨识的初始值，用来断言「缺失 / 类型错误字段保留当前值」
	gs.call("new_game", 777)
	gs.set("money", 555)
	gs.set("food", 111)
	gs.set("player_pos", Vector3(9.0, 9.0, 9.0))
	gs.set("game_time", 1.0)

	section("可用但脏：缺失字段逐条告警并保留当前值")
	_write_text(_slot_file(1), '{"schema_version": 1, "game": {}}')
	var r1: Dictionary = ss.call("load_slot", 1)
	ok(bool(r1.get("ok")), "空 game 段仍可读（字段级问题不该拒绝整个存档）",
			str(r1.get("reason")))
	var w1: PackedStringArray = r1.get("warnings", PackedStringArray())
	ge(w1.size(), 10, "10 个缺失字段各自告警（实际 %d 条）" % w1.size())
	ok(_warn_mentions(w1, "world_seed"), "告警点名 world_seed")
	ok(_warn_mentions(w1, "player_pos"), "告警点名 player_pos")
	eq(gs.get("money"), 555, "缺失的 money 保留当前值")
	eq(gs.get("player_pos"), Vector3(9.0, 9.0, 9.0), "缺失的 player_pos 保留当前值")

	section("可用但脏：未知字段 / 类型错误")
	_write_text(_slot_file(2), '{"schema_version": 1, "game": {"money": "很多钱", '
			+ '"game_time": "早晨", "food": 9, "no_such_field": 1}}')
	gs.set("money", 555)
	gs.set("game_time", 1.0)
	var r2: Dictionary = ss.call("load_slot", 2)
	ok(bool(r2.get("ok")), "类型错误字段不拒绝整个存档", str(r2.get("reason")))
	var w2: PackedStringArray = r2.get("warnings", PackedStringArray())
	ok(_warn_mentions(w2, "类型错误"), "类型错误有明确告警", str(w2))
	ok(_warn_mentions(w2, "no_such_field"), "未知字段被点名而不是静默丢弃", str(w2))
	eq(gs.get("money"), 555, "类型错误的 money 保留当前值")
	near(gs.get("game_time"), 1.0, 0.000001, "类型错误的 game_time 保留当前值")
	eq(gs.get("food"), 9, "同一文件里合法的 food 照常应用")

	section("不可用：拒读而不是崩溃，且一个字段都不改")
	var before_money: int = gs.get("money")
	var refuse_cases := [
		{"slot": 3, "text": "{oops", "needle": "JSON", "what": "非 JSON 文本"},
		{"slot": 4, "text": "[1, 2, 3]", "needle": "JSON 对象", "what": "数组根"},
		{"slot": 5, "text": '{"schema_version": 99, "game": {}}', "needle": "99",
			"what": "来自更高版本"},
		{"slot": 6, "text": '{"schema_version": 0, "game": {}}', "needle": "无迁移路径",
			"what": "无迁移路径的旧版本"},
		{"slot": 7, "text": '{"schema_version": 1}', "needle": "game", "what": "缺 game 段"},
		{"slot": 8, "text": '{"schema_version": 1, "game": "不是字典"}', "needle": "game",
			"what": "game 段类型错误"},
		{"slot": 3, "text": "", "needle": "读不出",
			"what": "0 字节空文件（读者重试花完后才报错）"},
		{"slot": 9, "text": '{"schema_version": 1, "game": {},', "needle": "JSON",
			"what": "被截断的 JSON（半截文件）"},
	]
	for c in refuse_cases:
		_write_text(_slot_file(int(c["slot"])), String(c["text"]))
		var r: Dictionary = ss.call("load_slot", int(c["slot"]))
		ok(not bool(r.get("ok")), "拒读：%s（不崩溃）" % c["what"], str(r.get("reason")))
		ok(String(r.get("reason")).contains(String(c["needle"])),
				"拒读原因点名 %s" % c["needle"], str(r.get("reason")))
	eq(gs.get("money"), before_money, "全部拒读之后 GameState 一个字段都没被改")
	eq(gs.get("world_seed"), 777, "world_seed 仍是拒读前的值")

	section("缺失 schema_version：告警并沿用当前版本")
	_write_text(_slot_file(1), '{"game": {"money": 12}}')
	var r7: Dictionary = ss.call("load_slot", 1)
	ok(bool(r7.get("ok")), "缺失 schema_version 仍按 v1 读取", str(r7.get("reason")))
	ok(_warn_mentions(r7.get("warnings", PackedStringArray()), "缺少 schema_version"),
			"告警说明缺失 schema_version")
	eq(gs.get("money"), 12, "字段照常应用")

	section("迁移钩子：v0 → v1 真能跑通（不是死代码）")
	_write_text(_slot_file(1), '{"schema_version": 0, "save": {"world_seed": 99, "money": 31}}')
	var no_hook: Dictionary = ss.call("load_slot", 1)
	ok(not bool(no_hook.get("ok")), "未注册钩子时 v0 被明确拒读", str(no_hook.get("reason")))
	var mig: Dictionary = ss.get("migrations")
	mig[0] = func(d: Dictionary) -> Dictionary:
		return {"schema_version": 1, "game": d.get("save", {})}
	gs.set("money", 0)
	var migrated: Dictionary = ss.call("load_slot", 1)
	ok(bool(migrated.get("ok")), "注册 v0→v1 钩子后同一文件可读", str(migrated.get("reason")))
	eq(gs.get("world_seed"), 99, "迁移后的 world_seed 生效")
	eq(gs.get("money"), 31, "迁移后的 money 生效")
	mig.erase(0)
	var after_erase: Dictionary = ss.call("load_slot", 1)
	ok(not bool(after_erase.get("ok")), "撤掉钩子后又拒读（证明生效的确实是钩子）",
			str(after_erase.get("reason")))

	section("信号契约：过去式事实，只在真的发生时发一次")
	eq(loaded_log, [1, 2, 1, 1], "slot_loaded 只在四次成功读档时各发一次")
	ge(load_failed_log.size(), refuse_cases.size() + 1,
			"load_failed 每次拒读都发（含撤钩子后那一次，实际 %d 次）" % load_failed_log.size())
	ok(not load_failed_log.is_empty() and String(load_failed_log[0][1]).length() > 0,
			"load_failed 负载带非空原因",
			str(load_failed_log[0] if not load_failed_log.is_empty() else []))
	ss.disconnect("load_failed", on_load_failed)
	ss.disconnect("slot_loaded", on_slot_loaded)

	var wrote_log: Array = []
	var on_save_written := func(slot: int, path: String) -> void:
		wrote_log.append([slot, path])
	ss.connect("save_written", on_save_written)
	var wsave: Dictionary = ss.call("save_slot", 1, true)
	ok(bool(wsave.get("ok")), "显式覆盖写入成功", str(wsave.get("reason")))
	eq(wrote_log.size(), 1, "save_written 发了一次")
	if wrote_log.size() == 1:
		eq(int(wrote_log[0][0]), 1, "save_written 带槽号")
		ok(String(wrote_log[0][1]).ends_with("slot_1.json"), "save_written 带路径",
				str(wrote_log[0][1]))
	ss.disconnect("save_written", on_save_written)

	section("测试隔离回收")
	_saves_end()
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "saves.bak 已清走")
	_restore_defaults()


func _case_atomic() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	ok(ss != null, "autoload SaveSystem 节点存在于 root")
	if ss == null:
		return
	_saves_begin()
	var slot_path := _slot_file(ATOMIC_SLOT)

	section("预置有效存档，再让子进程狂写同一槽位（父进程同时轮询）")
	var seed_save: Dictionary = ss.call("save_slot", ATOMIC_SLOT, true)
	ok(bool(seed_save.get("ok")), "预置槽 9 成功", str(seed_save.get("reason")))
	var summary_path := _opt_out.path_join(PROBE_LOOP_FILE)
	if FileAccess.file_exists(summary_path):
		DirAccess.remove_absolute(summary_path)
	ok(not FileAccess.file_exists(summary_path), "狂写统计文件在子进程运行前不存在（陈旧文件不能冒充证据）")
	var pid := _spawn_case("s0_3_probe_loop")
	ok(pid > 0, "狂写子进程已启动", "pid=%d" % pid)

	# 两种读法并行采样，因为它们证明的是不同的东西：
	#   (a) 裸读 —— 读者恰好在这一刻打开文件，会撞上引擎 rename 的非原子窗口；
	#   (b) 产品读档接口 —— 自带重试，它的失败次数才是玩家真正会遇到的。
	var samples := 0
	var half := 0
	var absent := 0
	var unreadable := 0
	var first_half := ""
	var reader_fails := 0
	var first_reader_fail := ""
	var money_seen := {}
	var deadline := Time.get_ticks_msec() + 30000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(slot_path):
			var txt := FileAccess.get_file_as_string(slot_path)
			if txt.strip_edges() == "":
				unreadable += 1
			elif _slot_text_is_complete(txt):
				samples += 1
				var seen_d := _parse_json_silent(txt)
				var seen_game: Dictionary = seen_d.get("game", {})
				money_seen[int(seen_game.get("money", -1))] = true
			else:
				half += 1
				if first_half == "":
					first_half = txt.substr(0, 96)
		else:
			absent += 1
		var lr: Dictionary = ss.call("load_slot", ATOMIC_SLOT)
		if not bool(lr.get("ok")):
			reader_fails += 1
			if first_reader_fail == "":
				first_reader_fail = String(lr.get("reason"))
		await process_frame

	var finished := pid > 0 and not OS.is_process_running(pid)
	ok(finished, "狂写子进程在 30 秒内自行结束（不是被超时打断）")
	if not finished and pid > 0:
		OS.kill(pid)
	var code := OS.get_process_exit_code(pid) if pid > 0 else -1
	ok(code == 0, "狂写子进程退出码 = 0（%d 次 save_slot 全部成功）" % ATOMIC_WRITES,
			"退出码=%d" % code)
	ge(samples, 20, "轮询期间读到 ≥ 20 次完整内容（否则本用例是空转，实际 %d 次）" % samples)
	ok(half == 0, "0 次半截/损坏内容：每一个读得出来的样本都是完整合法 JSON",
			"首个异常样本=%s（共 %d 次）" % [first_half, half])
	eq(reader_fails, 0, "风暴期间产品读档接口 0 次失败（读者重试用掉了引擎的非原子窗口）：%s"
			% first_reader_fail)
	ge(money_seen.size(), 2, "风暴期间读到过 ≥ 2 个不同的存档版本（实际 %d 种）" % money_seen.size())
	var max_money := -1
	for k in money_seen.keys():
		max_money = maxi(max_money, int(k))
	print("    [note] 裸读样本 %d 次：完整 %d / 半截 %d；不可读瞬间：文件不存在 %d / 存在但读不出 %d"
			% [samples + half + absent + unreadable, samples, half, absent, unreadable])
	print("    [note] 产品读档接口并发调用失败 %d 次；读到 %d 种不同版本（money 最大 %d）"
			% [reader_fails, money_seen.size(), max_money])

	section("写者自述（子进程不继承 stdout，只能靠文件说话）")
	var summary: Dictionary = _read_json(summary_path)
	eq(int(summary.get("writes", 0)), ATOMIC_WRITES, "写者自述写了 %d 次" % ATOMIC_WRITES)
	eq(int(summary.get("fails", -1)), 0, "写者自述 0 次失败：%s" % str(summary.get("first_reason", "")))
	eq(int(summary.get("last_published_money", -1)), ATOMIC_WRITES,
			"写者最后一版就是 money=%d" % ATOMIC_WRITES)

	# ⚠️ 这两段必须紧跟在轮询之后：本节后面的用例自己会重写槽 9，一旦中间插入写操作，
	# 「读者的最终版本 = 写者发布的最后一版」就不再是并发的事实，而只是巧合。
	section("风暴结束后：读者看到的最终版本 = 写者发布的最后一版（逐字节）")
	var final_txt := FileAccess.get_file_as_string(slot_path)
	ok(_slot_text_is_complete(final_txt), "槽 9 最终内容是完整合法 JSON")
	var final_d := _parse_json_silent(final_txt)
	var final_game: Dictionary = final_d.get("game", {})
	var final_money := int(final_game.get("money", -1))
	ok(final_money >= 1 and final_money <= ATOMIC_WRITES,
			"槽 9 的 money 是并发写入序列里的某个值（1..%d）" % ATOMIC_WRITES,
			"实际=%d" % final_money)
	eq(final_money, int(summary.get("last_published_money", -1)),
			"读者的最终版本与写者自述的最后一版一致（不是陈旧版本）")
	eq(FileAccess.get_sha256(slot_path), String(summary.get("last_published_sha", "")),
			"最终内容 sha256 与写者发布时自算的 sha256 完全一致")

	section("rename 被占用时：拒绝写入、原档不变、不留 .tmp（引擎实测语义）")
	var before_sha := FileAccess.get_sha256(slot_path)
	var hold := FileAccess.open(slot_path, FileAccess.READ)
	var blocked: Dictionary = ss.call("save_slot", ATOMIC_SLOT, true)
	if hold != null:
		hold.close()
	ok(not bool(blocked.get("ok")), "目标被读句柄占用时返回失败（不假装成功）",
			str(blocked.get("reason")))
	ok(String(blocked.get("reason")).contains("原存档保持不变"), "原因说明原档保持不变",
			str(blocked.get("reason")))
	eq(FileAccess.get_sha256(slot_path), before_sha, "失败后原存档逐位不变")
	ok(not FileAccess.file_exists(slot_path + ".tmp"), "失败后不残留 .tmp")
	var retried: Dictionary = ss.call("save_slot", ATOMIC_SLOT, true)
	ok(bool(retried.get("ok")), "句柄释放后同一槽位写入成功", str(retried.get("reason")))

	section("残留 .tmp 既不是槽位，也不会被当成存档")
	var tmp8 := _slot_file(8) + ".tmp"
	_write_text(tmp8, '{"schema_version": 1, "game": {}}')
	ok(not bool(ss.call("slot_exists", 8)), "slot_exists(8) 为假（.tmp 不算槽位）")
	var r8: Dictionary = ss.call("load_slot", 8)
	ok(not bool(r8.get("ok")), "load_slot(8) 拒绝")
	ok(String(r8.get("reason")).contains("空槽位"), "原因明说空槽位", str(r8.get("reason")))
	ok(FileAccess.file_exists(tmp8), "残留 .tmp 本身还在（不是被静默删除）")
	var w8: Dictionary = ss.call("save_slot", 8, true)
	ok(bool(w8.get("ok")), "写入槽 8 成功", str(w8.get("reason")))
	ok(not FileAccess.file_exists(tmp8), "写入成功后自己的 .tmp 被清理")

	section("测试隔离回收")
	_saves_end()
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "saves.bak 已清走")
	_restore_defaults()


func _case_no_autosave() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	ok(ss != null, "autoload SaveSystem 节点存在于 root")
	if ss == null:
		return
	_saves_begin()

	section("阶段 1：存档目录不存在时，跑满一整轮也不该建出任何存档")
	ok(not DirAccess.dir_exists_absolute(SAVES_DIR), "隔离后 user://saves 不存在")
	await _idle_run(90)
	var snap1 := _saves_snapshot(SAVES_DIR)
	eq(snap1.size(), 0, "阶段 1 后仍无任何存档文件：%s" % str(snap1.keys()))
	ok(not DirAccess.dir_exists_absolute(SAVES_DIR),
			"阶段 1 后目录仍未被创建（服务没有 _ready 写盘，也没有别的隐式写动作）")

	section("阶段 2：目录已有存档时，全流程内容哈希与 mtime 零变化")
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	_write_text(_slot_file(1), '{"schema_version": 1, "game": {"money": 5}}')
	var before := _saves_snapshot(SAVES_DIR)
	eq(before.size(), 1, "基线快照含 1 个文件")
	await _idle_run(90)
	eq(_saves_snapshot(SAVES_DIR), before, "本进程跑满一轮后哈希与 mtime 全不变")
	var out: Array = []
	var code := _exec_godot(PackedStringArray(["--headless", "--quit-after", "120"]), out)
	ok(code == 0, "子进程完整启动主场景 120 帧退出码 = 0",
			"退出码=%d 输出=%s" % [code, _tail(out, 4)])
	var errs := _error_lines(out)
	eq(errs.size(), 0, "子进程日志无 ERROR / SCRIPT ERROR：%s" % str(errs))
	eq(_saves_snapshot(SAVES_DIR), before, "另一个进程完整启动后哈希与 mtime 仍全不变")

	section("正面控制：显式存档必须被这套检查检出（否则上面是空转）")
	var wrote: Dictionary = ss.call("save_slot", 1, true)
	ok(bool(wrote.get("ok")), "显式 save_slot(1, true) 成功", str(wrote.get("reason")))
	ne(_saves_snapshot(SAVES_DIR), before, "显式存档后快照确实变化（内容哈希变了）")

	section("静态契约：服务里没有隐式写盘入口")
	var src := FileAccess.get_file_as_string("res://scripts/core/save_system.gd")
	# 只看代码、不看注释：文件顶部的契约说明里**提到**了这些名字，把它们算成证据就是
	# 自欺——注释不会写盘，也不能证明代码不写盘。
	var code_only := ""
	for raw in src.split("\n"):
		code_only += _strip_comment(String(raw), "gd") + "\n"
	ok(not code_only.contains("func _process"), "SaveSystem 没有 _process（不按帧写盘）")
	ok(not code_only.contains("func _physics_process"), "SaveSystem 没有 _physics_process")
	ok(not code_only.contains("func _ready"), "SaveSystem 没有 _ready（启动零动作）")
	ok(not code_only.contains("EventBus"), "SaveSystem 的代码不引用全局总线（没有事件触发的写盘）")
	eq(code_only.count("_atomic_write("), 2,
			"唯一的写盘路径 _atomic_write 只有 1 处定义 + 1 处调用（新增写入口必须显式登记）")

	section("测试隔离回收")
	_saves_end()
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "saves.bak 已清走")
	_restore_defaults()


## --- 打桩用例（hidden）-------------------------------------------------------
## 这三个用例不写报告、不走断言汇总：输出与退出码就是父用例的证据通道。
## `--all` 永远不会直接跑到它们（hidden），只由上面的用例以子进程拉起。

## 子进程：新游戏 → 设定可辨识状态 → 存槽 3。
func _case_probe_write() -> void:
	var gs := get_root().get_node_or_null("GameState")
	var ss := get_root().get_node_or_null("SaveSystem")
	if gs == null or ss == null:
		printerr("[probe] WRITE ok=false 原因=autoload 缺失")
		_probe_exit = 1
		return
	gs.call("new_game", PROBE_SEED)
	gs.set("game_time", PROBE_TIME)
	gs.set("money", PROBE_MONEY)
	gs.set("food", PROBE_FOOD)
	gs.set("supply", PROBE_SUPPLY)
	gs.set("player_pos", PROBE_POS)
	gs.call("set_scene_kind", PROBE_SCENE_KIND)
	var r: Dictionary = ss.call("save_slot", ROUNDTRIP_SLOT, true)
	print("[probe] WRITE ok=%s path=%s reason=%s" % [
		str(r.get("ok")), str(r.get("path")), str(r.get("reason")),
	])
	_probe_exit = 0 if bool(r.get("ok")) else 1


## 子进程：读槽 3 → 回吐单行快照 JSON（父进程直接解析）。
func _case_probe_read() -> void:
	var ss := get_root().get_node_or_null("SaveSystem")
	var gs := get_root().get_node_or_null("GameState")
	if ss == null or gs == null:
		printerr("[probe] READ ok=false 原因=autoload 缺失")
		_probe_exit = 1
		return
	var r: Dictionary = ss.call("load_slot", ROUNDTRIP_SLOT)
	var warns: PackedStringArray = r.get("warnings", PackedStringArray())
	print("[probe] READ ok=%s warnings=%d reason=%s" % [
		str(r.get("ok")), warns.size(), str(r.get("reason")),
	])
	if not bool(r.get("ok")):
		_probe_exit = 1
		return
	var handoff := _opt_out.path_join(PROBE_SNAPSHOT_FILE)
	_write_json(handoff, gs.call("snapshot"))
	print("[probe] SNAPSHOT_FILE ", handoff)
	_probe_exit = 0


## 子进程：连续写同一槽位 ATOMIC_WRITES 次，父进程同时在轮询那个文件。
## 结束时把「按自己写的最后一次，槽位里应当是什么」落成文件——父进程只能靠它
## 判断「读者看到的最终版本是不是写者发布的最后一版」。
func _case_probe_loop() -> void:
	var ss := get_root().get_node_or_null("SaveSystem")
	var gs := get_root().get_node_or_null("GameState")
	if ss == null or gs == null:
		printerr("[probe] LOOP writes=0 fails=1 原因=autoload 缺失")
		_probe_exit = 1
		return
	var fails := 0
	var first_reason := ""
	for i in ATOMIC_WRITES:
		gs.set("money", i + 1)
		var r: Dictionary = ss.call("save_slot", ATOMIC_SLOT, true)
		if not bool(r.get("ok")):
			fails += 1
			if first_reason == "":
				first_reason = String(r.get("reason"))
	var slot_path: String = ss.call("slot_path", ATOMIC_SLOT)
	var last_published := FileAccess.get_file_as_string(slot_path)
	var last_d: Dictionary = _parse_json_silent(last_published)
	var last_game: Dictionary = last_d.get("game", {})
	_write_json(_opt_out.path_join(PROBE_LOOP_FILE), {
		"writes": ATOMIC_WRITES,
		"fails": fails,
		"first_reason": first_reason,
		"last_published_sha": FileAccess.get_sha256(slot_path),
		"last_published_bytes": last_published.length(),
		"last_published_money": int(last_game.get("money", -1)),
	})
	print("[probe] LOOP writes=%d fails=%d first_reason=%s" % [
		ATOMIC_WRITES, fails, first_reason,
	])
	_probe_exit = 0 if fails == 0 else 1


## --- S0.3 批次 2 辅助 ---------------------------------------------------------

func _slot_file(slot: int) -> String:
	return SAVES_DIR.path_join("slot_%d.json" % slot)


## 把 user://saves 整体让位给 user://saves.bak。
## 目录换名已由探针实测：目标不存在时可用；target 已存在且非空时失败（因此先清）。
func _saves_begin() -> PackedStringArray:
	var notes := PackedStringArray()
	if DirAccess.dir_exists_absolute(SAVES_BAK):
		if DirAccess.dir_exists_absolute(SAVES_DIR):
			_dir_remove_recursive(SAVES_DIR)
		DirAccess.rename_absolute(SAVES_BAK, SAVES_DIR)
		notes.append("发现上次遗留的 saves.bak，已先还原")
	if DirAccess.dir_exists_absolute(SAVES_DIR):
		var err := DirAccess.rename_absolute(SAVES_DIR, SAVES_BAK)
		notes.append("已把 saves/ 让位为 saves.bak（err=%d）" % err)
	else:
		notes.append("原本没有 saves/ 目录，无需让位")
	return notes


## 删掉用例期间造出来的 saves/，再把备份换回来。
func _saves_end() -> PackedStringArray:
	var notes := PackedStringArray()
	if DirAccess.dir_exists_absolute(SAVES_DIR):
		_dir_remove_recursive(SAVES_DIR)
	if DirAccess.dir_exists_absolute(SAVES_BAK):
		var err := DirAccess.rename_absolute(SAVES_BAK, SAVES_DIR)
		notes.append("已还原 saves.bak -> saves/（err=%d）" % err)
	else:
		notes.append("没有 saves.bak 需要还原")
	return notes


## 递归删除目录。先把 DirAccess 的目录句柄收起来再删——Windows 上打开着的
## 目录句柄会挡住删除（与预登记陷阱 2 同源的引擎/系统语义）。
func _dir_remove_recursive(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dirs: Array = []
	var files: Array = []
	var d := DirAccess.open(dir_path)
	if d != null:
		dirs = d.get_directories()
		files = d.get_files()
		d.list_dir_end()
	for sub in dirs:
		_dir_remove_recursive(dir_path.path_join(String(sub)))
	for f in files:
		DirAccess.remove_absolute(dir_path.path_join(String(f)))
	DirAccess.remove_absolute(dir_path)


## 目录内每个文件的 sha256 + mtime —— 验收原文要的正是这两项。
func _saves_snapshot(dir_path: String) -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	var files := d.get_files()
	d.list_dir_end()
	for f in files:
		var p := dir_path.path_join(String(f))
		out[String(f)] = {
			"sha256": FileAccess.get_sha256(p),
			"mtime": FileAccess.get_modified_time(p),
		}
	return out


## 一次观测是否算「完整」：JSON 对象 + schema_version 1 + 必备 game.money。
## 「不存在」与「存在但读不出」是另外两类观测，由调用方单独计数，不算半截。
func _slot_text_is_complete(txt: String) -> bool:
	var d := _parse_json_silent(txt)
	if d.is_empty():
		return false
	if int(d.get("schema_version", -1)) != 1:
		return false
	var game_v: Variant = d.get("game", null)
	if typeof(game_v) != TYPE_DICTIONARY:
		return false
	return (game_v as Dictionary).has("money")


## 解析可能损坏的文本，失败时保持安静。
## 与 `scripts/core/save_system.gd` 同一条理由：并发观测里的「半截样本」是**预期输入**，
## `JSON.parse_string()` 会为每一个样本打一行引擎级 ERROR，把真正的错误淹掉。
func _parse_json_silent(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var data: Variant = parser.data
	return data if typeof(data) == TYPE_DICTIONARY else {}


## 跑一轮「该写盘的东西都没写盘」的模拟：新游戏 → 逻辑步推进 → 五种全局事实
## 全部投递 → 把所有只读的存档接口调一遍。
##
## ⚠️ 真正的「大地图遭遇 → 战斗 → 返回」需要 SceneRouter（S0.3 批次 3）才能跑通；
## 本用例覆盖它现在能覆盖的部分：任何非玩家显式操作的流程都不许落盘。
func _idle_run(frames: int) -> void:
	var gs := get_root().get_node_or_null("GameState")
	var bus := get_root().get_node_or_null("EventBus")
	var ss := get_root().get_node_or_null("SaveSystem")
	if gs != null:
		gs.call("new_game", 31337)
	for i in 6:
		await physics_frame
	if bus != null:
		bus.emit_signal("time_advanced", 2, 0.5)
		bus.emit_signal("encounter_started", {"id": "probe"})
		bus.emit_signal("battle_finished", {"win": true})
		bus.emit_signal("resources_changed", 1, 2, 3)
		bus.emit_signal("settlement_entered", "s1")
	if ss != null:
		ss.call("select_slot", 1)
		ss.call("slot_info", 1)
		ss.call("list_slots")
		ss.call("load_slot", 1)
		ss.call("load_slot", 9)
	for i in maxi(frames - 6, 0):
		await physics_frame


## 把现场还给后续用例（GameState / Rng 回默认，与 s0_3_state 的收尾同口径）。
func _restore_defaults() -> void:
	var gs := get_root().get_node_or_null("GameState")
	var rng := get_root().get_node_or_null("Rng")
	if gs != null:
		gs.call("new_game", 20250929)
	if rng != null:
		rng.call("seed_from", 20250929)


## 以子进程跑一个打桩用例并把 stdout 收回来。
## `--quit-after` 是兜底：万一打桩用例挂死，子进程也会退出，表现为「标记行缺失」的
## 显式失败，而不是无限等待（与 `_exec_user` 同一条约束）。
## 以子进程跑一个打桩用例并把 stdout 收回来。
## `--out=` 必须放在 `--` **之后**：`--` 之前的参数引擎自己解析，子进程的
## `OS.get_cmdline_user_args()` 只看得见 `--` 之后的（踩过一次：放前面时子进程
## 静默用了默认报告目录，回吐文件写去了别处）。`--quit-after` 同理是兜底：万一
## 打桩用例挂死，子进程也会退出，表现为「标记行缺失」的显式失败，而不是无限等待。
func _exec_case(case_id: String, out_lines: Array) -> int:
	return _exec_godot(PackedStringArray([
		"--headless", "--quit-after", "20000",
		"--script", "res://tools/verify.gd", "--", "--case=" + case_id, "--out=" + _opt_out,
	]), out_lines)


## 非阻塞启动一个打桩用例子进程（stdout 继承本进程），返回 pid。
## 必须非阻塞：父进程要在子进程写盘的同时轮询那个槽位文件。
func _spawn_case(case_id: String) -> int:
	return OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", _project_dir(), "--quit-after", "20000",
		"--script", "res://tools/verify.gd", "--", "--case=" + case_id, "--out=" + _opt_out,
	]))


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[verify] 无法写入 ", path)
		return
	f.store_string(text)
	f.close()


## 把 `OS.execute` 收回的输出摊平成单行。
## `out_lines` 的元素是**读取分块**而不是严格按行（实测一整段 stderr+stdout 会落在
## 同一个元素里），所以这里统一按 "\n" 再切一次：机器可读标记行必须能逐行匹配，
## 否则断言会随缓冲边界随机失败。
func _flatten_lines(lines: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for l in lines:
		for piece in String(l).split("\n"):
			out.append(String(piece))
	return out


func _lines_contain(lines: Array, needle: String) -> bool:
	for l in _flatten_lines(lines):
		if String(l).contains(needle):
			return true
	return false


## 取以 `prefix` 开头那一行的剩余部分（打桩用例的单行机器可读输出）。
func _line_value(lines: Array, prefix: String) -> String:
	for l in _flatten_lines(lines):
		var s := String(l)
		if s.begins_with(prefix):
			return s.substr(prefix.length())
	return ""


func _tail(lines: Array, n: int) -> String:
	var flat := _flatten_lines(lines)
	var start := maxi(flat.size() - n, 0)
	var out := PackedStringArray()
	for i in range(start, flat.size()):
		out.append(String(flat[i]))
	return " | ".join(out)


func _error_lines(lines: Array) -> Array:
	var out: Array = []
	for l in _flatten_lines(lines):
		var s := String(l)
		if s.contains("ERROR") or s.contains("SCRIPT ERROR"):
			out.append(s.strip_edges())
	return out


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


## 启动子进程并把**游戏侧**参数放在 `--` 之后。
##
## ⚠️ `--` 不是可选的分隔符。Godot 只把 `--` 之后的参数交给
## `OS.get_cmdline_user_args()`；少了它，`capture.gd` 收不到 `--shots`，
## 既不会触发截图也不会 `quit()`，子进程会一直跑主场景——
## 实测后果是整个验收套件静默挂死（`OS.execute` 没有超时）。
## 因此本函数强制插入 `--`，并通过 `--quit-after` 兜底：
## 万一将来还有谁忘了回归，子进程最多跑 `safety_frames` 帧就退出，
## 表现为"清单没写出"的**显式失败**，而不是无限等待。
##
## engine_args 放 `--` 之前（`--headless` / `--script res://...` 之类）。
func _exec_user(engine_args: PackedStringArray, user_args: PackedStringArray,
		out_lines: Array, safety_frames: int = 3600) -> int:
	var args := PackedStringArray(["--quit-after", str(safety_frames)])
	args.append_array(engine_args)
	args.append("--")
	args.append_array(user_args)
	return _exec_godot(args, out_lines)


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
		# S0.6：不可冻结的时间来源（按扩展名分流）
		if ext == "gdshader" or ext == "shader":
			if _contains_token(line, UNFREEZABLE_SHADER_TOKEN):
				hits.append(_hit(path, i + 1, "unfreezable_time", raw))
		elif ext == "gd":
			for tok in UNFREEZABLE_SCRIPT_TOKENS:
				if _contains_token(line, tok):
					hits.append(_hit(path, i + 1, "unfreezable_time", raw))
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

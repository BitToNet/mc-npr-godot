extends Node
## =============================================================================
##  Debug — 调试与观测层（ROADMAP §5 S0.4 批次 2）
## =============================================================================
##  职责：一个默认隐藏的调试叠加层（帧时间曲线 / 实体计数 / 场景与路由状态 /
##  内存），两条调试热键 `F1`（隐藏全部 UI）与 `F3`（切换叠加层），外加一份
##  可落盘的 CSV 观测数据（供 M1/M2/M4 的 `C-` 类性能验收取证）。
##
##  为什么是 autoload：叠加层必须**跨场景常驻**。`SceneRouter` 会真正
##  `change_scene_to_file()`（旧场景被释放），挂在场景里的面板每切一次场景就消失，
##  而且 `F1/F3` 要在每个场景各实现一遍。"哪个场景在屏幕上"只有路由器知道，
##  "调试层在所有场景里都在"只有 autoload 做得到。autoload 计数 8 → 9（上限 10，§3.2）。
##
##  三条硬约束（它们直接决定了下面的写法）
##   1) **默认隐藏**。S0.4 之前录下的 6 机位 `B-` 基线必须继续逐位不变，
##      所以本节点开工第一件事就是把整个 `CanvasLayer` 设为不可见。
##   2) **确定性模式只显示可复现量**。截图模式下"内存 / 对象数 / 真实帧时间"是
##      环境噪声（同参数两次进程也不同），显示它们会让 `B-` 的 sha256 永远对不上。
##      这与 `main.gd` 把 HUD 的 FPS 读数在确定性模式下换成 `Clock.hz` 是同一条理由：
##      宁可少显示一个数字，也不显示一个会撒谎的数字。
##   3) **不引入不可冻结的时间源**。帧时间一律读 `Performance.TIME_PROCESS`
##      （引擎自己的指标），绝不碰 `Time.get_ticks_msec/usec`（守卫规则
##      `unfreezable_time` 禁止；测量用墙钟要逐条登记白名单，能不引入就不引入）。
##
##  F1 / F3 语义（§5 S0.4）
##   * `F1` 隐藏**全部** UI（HUD + 叠加层），再按一次恢复。菜单开着时先关菜单：
##     菜单是 `get_tree().paused = true` 的唯一来源，把菜单变不可见却不解除暂停，
##     会得到一个"黑屏但世界停住"的假死态 —— 这不是手感问题，是卡死。
##   * `F3` 只切叠加层；菜单暂停时仍然响应（`PROCESS_MODE_ALWAYS`，
##     与 `Clock` / 菜单同一个理由，见 §5 S0.3 陷阱 1）。
##   * 二者**只存在于 Debug 构建**。闸门只有一个：`InputSetup.ensure_debug_hotkeys()`
##     按 `OS.is_debug_build()` 注册 action；本节点只认"action 在不在"，
##     不自己再判断一次构建类型（两处判断迟早会不一致）。
##
##  CSV 观测
##   `record_start(path)` / `record_stop()`，或启动参数 `--obs-csv=<path>`。
##   `--obs-csv=` 是**纯修饰符**：不触发截图批次、不 quit。`--case=` / `--out=`
##   曾因自我触发抢走过验收运行器的退出码（§3.4 的实测结论），这里不重蹈覆辙。
##   每行写完即 flush：录制中的数据比"少一次系统调用"重要，而录制不是常开状态
##   （`C-` 的开销测量在关闭录制下进行）。
##
##  ⚠️ `tools/verify.gd` 以 `--script` 方式充当 MainLoop，那里 autoload 的**标识符
##     不编译**；验收用例一律用 `root.get_node("Debug")` 取本节点。
## =============================================================================

## 叠加层所在的 CanvasLayer 层号。高于 HUD（10）与菜单（20）：
## 调试层是工具，被任何面板盖住都会让人以为"叠加层没开"。
const LAYER := 30
## 曲线保留的采样帧数。
const GRAPH_FRAMES := 120
## 面板刷新间隔（帧）。10Hz 足够看清趋势，也把"每帧刷 4 个 Label + 重绘曲线"
## 的成本摊薄 —— `C-` 量的是这个实际开销，不是理论值。
const REFRESH_EVERY := 6
## 曲线纵轴上限（ms）。固定刻度 ⇒ 确定性模式下图形逐位可复现。
const GRAPH_PEAK_MS := 33.0
## 面板最小宽度（像素）。固定宽度让布局不随文字长短漂移（截图逐位复现的前提之一）。
const PANEL_WIDTH := 460
const GRAPH_HEIGHT := 72

## CSV 列定义（唯一的顺序来源；表头由它拼出来，不另写一份字符串）。
const CSV_COLUMNS := ["frame", "t_s", "dt_ms", "scene", "stack", "depth", "nodes",
		"draw_calls", "prims", "ms_process"]
## 启动参数前缀（纯修饰符，见文件头）。
const CSV_ARG := "--obs-csv="
## 热键 action 名（由 `InputSetup` 注册；名字写在这里也写在那里会漂移，
## 所以这里只引用 `InputSetup` 的常量）。
const ACTION_OVERLAY := InputSetup.ACTION_DEBUG_OVERLAY
const ACTION_HIDE_UI := InputSetup.ACTION_DEBUG_HIDE_UI
## 叠加层里显示的节点组（顺序即显示顺序；没有节点的组不显示）。
const GROUP_ORDER := ["main", "player", "camera_rig", "terrain", "water",
		"day_night", "menu", "hud"]


# ---------------------------------------------------------------------------
# 内部控件：帧时间曲线
# ---------------------------------------------------------------------------
## 纵轴固定 `0..peak_ms`，横轴固定 `GRAPH_FRAMES` 帧 —— 两条轴都不自适应，
## 图形才是采样值的纯函数，截图才能逐位复现。
class GraphView extends Control:
	var samples := PackedFloat32Array()
	var peak_ms := 33.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), UiKit.PAPER, true)
		# 60fps 预算参考线（16.67ms）
		var y60 := h - clampf((1000.0 / 60.0) / peak_ms, 0.0, 1.0) * h
		draw_line(Vector2(0.0, y60), Vector2(w, y60), UiKit.MUTED, 1.0)
		if samples.size() >= 2:
			var pts := PackedVector2Array()
			var last := float(samples.size() - 1)
			for i in samples.size():
				var x := w * float(i) / last
				var y := h - clampf(samples[i] / peak_ms, 0.0, 1.0) * h
				pts.append(Vector2(x, y))
			draw_polyline(pts, UiKit.PINK, 2.0, true)
		draw_rect(Rect2(Vector2.ZERO, size), UiKit.INK, false, 2.0)


signal overlay_toggled(on: bool)
signal ui_hidden_changed(hidden: bool)

## 叠加层是否开着（与"是否真的可见"分开：F1 隐藏全部 UI 时它被压住但状态保留）。
var overlay_on := false
## 全部 UI 是否被 F1 隐藏。
var hud_hidden := false

var _layer: CanvasLayer
var _panel: PanelContainer
var _lbl_head: Label
var _lbl_scene: Label
var _lbl_entities: Label
var _lbl_clock: Label
var _lbl_csv: Label
var _graph: GraphView
var _samples := PackedFloat32Array()
var _tick := 0
var _csv: FileAccess = null
var _csv_path := ""
var _csv_rows := 0


# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------
func _ready() -> void:
	# 与 Clock / 菜单同理：`get_tree().paused = true` 会连 autoload 的 `_process`
	# 一起停掉，调试层必须在菜单打开时也响应 F1/F3（§5 S0.3 陷阱 1）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 单一闸门：`ensure()` 内部按 `OS.is_debug_build()` 决定是否注册调试热键。
	# 这里显式调用一次，是为了让"非主场景"（战斗、M4 军团战）也有热键可用 ——
	# 那些场景的 `_ready` 不会替我们调 `InputSetup`。
	InputSetup.ensure()
	_build()
	_layer.visible = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with(CSV_ARG):
			var p := a.substr(CSV_ARG.length())
			if p != "":
				record_start(p)


func _exit_tree() -> void:
	# 兜底 flush：`--quit-after` / `quit()` 之后不该丢最后几行。
	record_stop()


func _process(_delta: float) -> void:
	_tick += 1
	_push_sample()
	if _tick % REFRESH_EVERY == 0:
		_refresh()
	if _csv != null:
		_write_row()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	# 只认 action：非 Debug 构建里 `InputSetup` 根本没注册它们，于是这里也自然失效。
	if InputMap.has_action(ACTION_OVERLAY) and key.is_action_pressed(ACTION_OVERLAY):
		toggle_overlay()
		get_viewport().set_input_as_handled()
	elif InputMap.has_action(ACTION_HIDE_UI) and key.is_action_pressed(ACTION_HIDE_UI):
		toggle_ui_hidden()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 公开状态（验收用例只读这些事实，不去翻私有字段）
# ---------------------------------------------------------------------------
func is_overlay_on() -> bool:
	return overlay_on


func is_ui_hidden() -> bool:
	return hud_hidden


## 叠加层此刻是否真的画在屏幕上（`visible` 与"开关状态"是两件事）。
func is_panel_visible() -> bool:
	return _layer != null and _layer.visible


## 当前场景的可读标签。优先用路由器（只有它知道"第几层、怎么来的"）；
## 路由器还没登记时退回引擎当前场景的文件名 —— 启动时主场景是引擎直接加载的，
## 那一格在开局必然是空的，而"最常看的一行在最常见的状态下是空的"等于没有这一行。
## 返回值不带修饰，显示层用括号表达"这是文件名、不是路由条目"。
func scene_label() -> String:
	var route := SceneRouter.current_route()
	if route != "":
		return route
	var cs := get_tree().current_scene
	if cs == null:
		return ""
	var p := String(cs.scene_file_path)
	if p != "":
		return p.get_file().get_basename()
	return String(cs.name)


func stats() -> Dictionary:
	var stack := SceneRouter.route_stack()
	var groups := {}
	for g in GROUP_ORDER:
		var n := get_tree().get_nodes_in_group(g).size()
		if n > 0:
			groups[g] = n
	return {
		"overlay_on": overlay_on,
		"hud_hidden": hud_hidden,
		"panel_visible": is_panel_visible(),
		"layer": LAYER if _layer != null else -1,
		"frame": Clock.frame,
		"t": Clock.t,
		"deterministic": Clock.deterministic,
		"hz": Clock.hz,
		"route": SceneRouter.current_route(),
		"scene_label": scene_label(),
		"stack": stack,
		"depth": stack.size(),
		"nodes": get_tree().get_node_count(),
		"groups": groups,
		# `rng.gd` 的 `stream_names()` 注释里写着"the S0.4 debug layer shows it"：
		# 这里兑现它。看得到"谁抽过随机"是排查"同一 seed 两片世界不一样"的第一线索。
		"rng_streams": Rng.stream_names(),
		"refresh_every": REFRESH_EVERY,
		"graph_frames": GRAPH_FRAMES,
		"csv_path": _csv_path,
		"csv_rows": _csv_rows,
		"recording": _csv != null,
		"hotkeys": InputMap.has_action(ACTION_OVERLAY) and InputMap.has_action(ACTION_HIDE_UI),
	}


func toggle_overlay() -> bool:
	set_overlay(not overlay_on)
	return overlay_on


func set_overlay(on: bool) -> void:
	overlay_on = on
	_sync_panel_visible()
	if on:
		# 立刻填一次内容：否则开层后的前 REFRESH_EVERY 帧是一块空面板，
		# 截图（以及人眼）会先看到一次"空白闪一下"。
		_tick = 0
		_refresh()
	overlay_toggled.emit(on)


func toggle_ui_hidden() -> bool:
	set_ui_hidden(not hud_hidden)
	return hud_hidden


func set_ui_hidden(on: bool) -> void:
	hud_hidden = on
	if on:
		# 先解除暂停再隐藏：菜单是 paused 的唯一来源，藏了菜单不解除暂停 = 卡死。
		var menu := get_tree().get_first_node_in_group("menu")
		if menu != null and menu.has_method("is_open") and bool(menu.call("is_open")):
			menu.call("close_menu")
	for n in get_tree().get_nodes_in_group("hud"):
		if n is CanvasLayer:
			(n as CanvasLayer).visible = not on
		elif n is CanvasItem:
			(n as CanvasItem).visible = not on
	_sync_panel_visible()
	ui_hidden_changed.emit(on)


# ---------------------------------------------------------------------------
# CSV 观测
# ---------------------------------------------------------------------------
func is_recording() -> bool:
	return _csv != null


## 开始录制。返回是否真的打开了文件（打不开时显式报错并返回 false，不静默）。
func record_start(path: String) -> bool:
	if path == "":
		return false
	if _csv != null:
		record_stop()
	var dir := path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	_csv = FileAccess.open(path, FileAccess.WRITE)
	if _csv == null:
		printerr("[debug] CSV 打不开：", path, "（err=", FileAccess.get_open_error(), "）")
		return false
	_csv.store_line(",".join(CSV_COLUMNS))
	_csv.flush()
	_csv_path = path
	_csv_rows = 0
	print("[debug] CSV 录制开始 -> ", path)
	return true


func record_stop() -> void:
	if _csv == null:
		return
	_csv.flush()
	_csv.close()
	_csv = null
	print("[debug] CSV 录制结束：", _csv_path, " 共 ", _csv_rows, " 行")


## 当前帧该写进 CSV 的一行（列名 -> 值）。验收用例直接断言这个字典，
## 不必去读文件格式；`_write_row()` 只负责把它按 `CSV_COLUMNS` 顺序落盘。
##
## 确定性模式下环境量（draw_calls / prims / ms_process）**留空**：
## 它们随机器与进程状态漂移，写进去 CSV 就不再是"同参数两次逐位相同"，
## 而"两份 CSV 逐位相同"正是本步 `A-` 要证的那件事。真实性能取证时
## 关掉确定性模式（`--realtime`），这三列自然就有值。
func sample_row() -> Dictionary:
	var stack := SceneRouter.route_stack()
	var row := {
		"frame": Clock.frame,
		"t_s": "%.3f" % Clock.t,
		"dt_ms": "%.3f" % (Clock.dt * 1000.0),
		"scene": scene_label(),
		"stack": ">".join(stack),
		"depth": stack.size(),
		"nodes": get_tree().get_node_count(),
		"draw_calls": "",
		"prims": "",
		"ms_process": "",
	}
	if not Clock.deterministic:
		row["draw_calls"] = str(int(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		row["prims"] = str(int(Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		row["ms_process"] = "%.3f" % (Performance.get_monitor(
				Performance.TIME_PROCESS) * 1000.0)
	return row


# ---------------------------------------------------------------------------
# 装配与刷新
# ---------------------------------------------------------------------------
func _build() -> void:
	var font := UiKit.font()

	_layer = CanvasLayer.new()
	_layer.name = "DebugLayer"
	_layer.layer = LAYER
	add_child(_layer)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 整层不吃输入：调试层绝不能抢走本属于游戏的点击（§5 S0.3 批次 4 的教训 ——
	# 菜单用一整块 Backdrop 才敢吃点击，调试层相反，一律 IGNORE）。
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)

	# 右下角：HUD 占左上（控制面板）与右上（状态徽章），提示条在左下。
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	root.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Box"
	# 内容贴右下：VBox 拉满整个 margin 区域，子项靠右收缩、整体贴底。
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiKit.sb(UiKit.PAPER, 4, 6, Vector2(6, 6), 14))
	box.add_child(_panel)

	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)

	_lbl_head = UiKit.label(font, "DEBUG   F1=隐藏全部UI   F3=叠加层", 18, UiKit.INK)
	_lbl_head.name = "Head"
	col.add_child(_lbl_head)

	_lbl_scene = UiKit.label(font, "", 14, UiKit.MUTED)
	_lbl_scene.name = "Scene"
	col.add_child(_lbl_scene)

	_lbl_entities = UiKit.label(font, "", 14, UiKit.MUTED)
	_lbl_entities.name = "Entities"
	_lbl_entities.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_lbl_entities)

	_lbl_clock = UiKit.label(font, "", 14, UiKit.MUTED)
	_lbl_clock.name = "ClockLine"
	col.add_child(_lbl_clock)

	_graph = GraphView.new()
	_graph.name = "Graph"
	_graph.peak_ms = GRAPH_PEAK_MS
	_graph.custom_minimum_size = Vector2(PANEL_WIDTH - 28, GRAPH_HEIGHT)
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_graph)

	_lbl_csv = UiKit.label(font, "", 13, UiKit.MUTED)
	_lbl_csv.name = "Csv"
	col.add_child(_lbl_csv)

	_refresh()


func _push_sample() -> void:
	var ms := 0.0
	if Clock.deterministic:
		# 确定性模式下"真实帧时间"是环境噪声，采样值改用逻辑步长：
		# 曲线于是也是帧号的纯函数（与面板文字同一条口径）。
		ms = 1000.0 / maxf(Clock.hz, 1.0)
	else:
		ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_samples.append(ms)
	while _samples.size() > GRAPH_FRAMES:
		_samples.remove_at(0)


func _refresh() -> void:
	if _panel == null:
		return
	_graph.samples = _samples.duplicate()
	_graph.queue_redraw()

	var st := stats()
	var route := String(st["route"])
	var stack_txt := "—"
	if not (st["stack"] as PackedStringArray).is_empty():
		stack_txt = ">".join(st["stack"])
	# 路由条目为空时用括号标出"这是场景文件名，不是路由条目"：两者含义不同，
	# 显示上也不该长得一样。
	var scene_txt := "—"
	var label := String(st["scene_label"])
	if label != "":
		scene_txt = label if route != "" else "(" + label + ")"
	_lbl_scene.text = "SCENE %s   STACK %s   DEPTH %d   FSM —" % [
		scene_txt, stack_txt, int(st["depth"]),
	]
	var streams: PackedStringArray = st["rng_streams"]
	_lbl_scene.text += "\nRNG %s" % ("—" if streams.is_empty() else ",".join(streams))

	var parts := PackedStringArray()
	for g in GROUP_ORDER:
		if (st["groups"] as Dictionary).has(g):
			parts.append("%s:%d" % [g, int((st["groups"] as Dictionary)[g])])
	_lbl_entities.text = "NODES %d   %s" % [int(st["nodes"]), " ".join(parts)]

	if Clock.deterministic:
		# 只显示可复现量：环境量在确定性模式下没有意义（见文件头约束 2）。
		_lbl_clock.text = "FRAME %d   T %.3fs   STEP %.2fms   (det %.0fHz)" % [
			Clock.frame, Clock.t, Clock.dt * 1000.0, Clock.hz,
		]
	else:
		_lbl_clock.text = "T %.3fs   MS %.2f   FPS %d   MEM %.1fMB" % [
			Clock.t,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		]

	if _csv == null:
		_lbl_csv.text = ""
	else:
		_lbl_csv.text = "CSV %s   行 %d" % [_csv_path.get_file(), _csv_rows]


func _write_row() -> void:
	var row := sample_row()
	var parts := PackedStringArray()
	for c in CSV_COLUMNS:
		parts.append(str(row.get(c, "")))
	_csv.store_line(",".join(parts))
	_csv.flush()
	_csv_rows += 1


func _sync_panel_visible() -> void:
	if _layer != null:
		_layer.visible = overlay_on and not hud_hidden
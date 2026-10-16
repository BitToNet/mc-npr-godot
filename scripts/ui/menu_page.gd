extends CanvasLayer
## MenuPage — 存档菜单（ROADMAP §5 S0.3 批次 4，交互契约 §3.5）。
##
## 两个页面 + 一层弹窗，全部由本文件组装（`scenes/main.tscn` 里只挂一个节点，
## 与 `scripts/ui/ui_panel.gd` 同一种做法）：
##
##   home   —— 标题 + 世界状态 + 「保存 / 另存为 / 读取 / 设置 / 返回游戏」
##   grid   —— 3×3 宫格（`scripts/ui/save_grid.gd`）+ 返回
##   确认弹窗 —— 覆盖已有存档前的**整页**二次确认（点击外面/ESC 都算取消）
##
## ESC 的四级语义（每一级都可观测，故都可以被用例断言）：
##   菜单关着 → 打开；弹窗开着 → 取消弹窗；在宫格页 → 回主页；在主页 → 关闭菜单。
##
## ⚠️ 打开菜单会 `get_tree().paused = true`（常规手感：菜单里世界不该继续跑）。
## 暂停**会连带停掉 autoload 与场景节点的 `_process`**（预登记陷阱 1，实测见
## `s0_3_slots`）：所以本节点的 `process_mode` 必须是 `PROCESS_MODE_ALWAYS`，
## 否则暂停之后菜单自己都收不到点击。`Clock` 同理（它必须继续走，见
## `render_clock.gd`）；`GameState` 保持默认 —— 暂停时游戏时间不该推进。
##
## 「保存」为什么在没有当前槽位时要跳宫格：`SaveSystem.save_current()` 的契约
## 就是「没有当前槽位 ⇒ 等同另存为，请先选槽」，菜单照抄这个契约而不是自己
## 发明一句提示，两边就不会说不一样的话。

signal opened
signal closed

const GRID_SCRIPT := preload("res://scripts/ui/save_grid.gd")

const INK := Color("13101b")
const PAPER := Color("fff9e8")
const YELLOW := Color("ffe45c")
const CYAN := Color("6fe3e1")
const PINK := Color("ff8fb1")
const GREEN := Color("7ed957")
const LILAC := Color("c3b1ff")
const MUTED := Color("6b6480")
const BACKDROP := Color(0.07, 0.06, 0.10, 0.62)

var _font: SystemFont
var _open := false
var _page := "home"
var _grid_intent := "save"
var _pending_slot := 0
var _home: CenterContainer
var _grid_page: CenterContainer
var _confirm: Control
var _grid: PanelContainer
var _lbl_status: Label
var _lbl_slot: Label
var _lbl_hint: Label
var _lbl_grid_hint: Label
var _lbl_confirm_title: Label
var _lbl_confirm_detail: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	add_to_group("menu")
	_build_font()
	_build()
	visible = false
	refresh()


# ---------------------------------------------------------------------------
# 公开状态（用例与 S0.4 调试层读取；全是只读事实）
# ---------------------------------------------------------------------------
func is_open() -> bool:
	return _open


## "home" 或 "grid"。
func page_name() -> String:
	return _page


func confirm_open() -> bool:
	return _confirm != null and _confirm.visible


func hint_text() -> String:
	return "" if _lbl_hint == null else _lbl_hint.text


func grid() -> PanelContainer:
	return _grid


func open_menu() -> void:
	if _open:
		return
	_open = true
	visible = true
	show_home()
	get_tree().paused = true
	opened.emit()


func close_menu() -> void:
	if not _open:
		return
	_open = false
	_cancel_confirm()
	visible = false
	get_tree().paused = false
	closed.emit()


func toggle_menu() -> void:
	if _open:
		close_menu()
	else:
		open_menu()


func show_home() -> void:
	_page = "home"
	_home.visible = true
	_grid_page.visible = false


## 切到宫格页。`note` 是"为什么跳过来"（例如服务返回的拒绝理由）—— 它和"点一格
## 干什么"是两件事，所以两句话都要在：只保留后一句的话，玩家会看到宫格弹出来却
## 不知道为什么（验收用例就是盯着这一条）。
func show_grid(intent: String, note: String = "", tone := "info") -> void:
	_grid_intent = intent
	_page = "grid"
	_home.visible = false
	_grid_page.visible = true
	var base := "点一格读取它（空槽位会说明为什么读不了）"
	if intent != "load":
		base = "点一格写入它；已有存档的格子会先问一次"
	_hint(base if note.is_empty() else "%s\n%s" % [base, note], tone)


## 重新从服务读状态（世界状态行 + 宫格 + 当前槽位）。
func refresh() -> void:
	if _lbl_status == null:
		return
	# `GameState.clock_text()` 已经是「第 N 天 HH:MM」的完整形态，这里不再自己拼日期，
	# 否则会出现「第 1 天 第 1 天 00:00」（踩过一次）。
	_lbl_status.text = "%s · 金钱 %d · 粮草 %d · 补给 %d · 队伍 %s Lv%d" % [
		GameState.clock_text(), GameState.money, GameState.food,
		GameState.supply, String(GameState.party.get("name", "")),
		int(GameState.party.get("level", 0))]
	var slot := int(SaveSystem.current_slot)
	if slot == 0:
		_lbl_slot.text = "当前槽位：未选择（保存会先让你选一格）"
	else:
		_lbl_slot.text = "当前槽位：%d · %s" % [slot, String(SaveSystem.slot_info(slot).get("label", ""))]
	_grid.refresh()


# ---------------------------------------------------------------------------
# 输入：ESC 四级
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	# 既认 `ui_cancel`（可改键/手柄），也认 ESC 键码本身（§3.5 写死的手感，
	# 且让注入事件驱动的用例与截图不依赖 InputMap 的具体绑定形态）。
	if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE \
			or key.is_action_pressed("ui_cancel"):
		_on_escape()
		get_viewport().set_input_as_handled()


func _on_escape() -> void:
	if not _open:
		open_menu()
		return
	if confirm_open():
		_cancel_confirm()
		_hint("已取消覆盖：旧存档没有被改动", "info")
		return
	if _page == "grid":
		show_home()
		return
	close_menu()


# ---------------------------------------------------------------------------
# 流程
# ---------------------------------------------------------------------------
func _on_save() -> void:
	# 服务的裁决就是唯一的裁决，菜单不重算一遍规则：`save_current()` 在没有当前
	# 槽位时返回 `requires_confirm=true, slot=0`（注释原文「保存等同另存为」），
	# 槽位已占用时返回 `requires_confirm=true, slot=N`。菜单只把这两种「需要确认」
	# 翻译成两种界面（跳宫格 / 覆盖弹窗），于是两边永远不会说不一样的话。
	_handle_save_result(SaveSystem.save_current(false))


func _on_save_as() -> void:
	show_grid("save")


func _on_load() -> void:
	var slot := int(SaveSystem.current_slot)
	if slot == 0:
		show_grid("load", "当前没有选中槽位：请先在宫格里选一格", "warn")
		return
	_load_from(slot)


func _on_settings() -> void:
	_hint("设置页还没做（ROADMAP 留到 S0.4 调试观测层与后续步骤）", "info")


func _on_resume() -> void:
	close_menu()


func _on_slot_pressed(slot: int) -> void:
	if _page != "grid":
		return
	if _grid_intent == "load":
		_load_from(slot)
	else:
		_handle_save_result(SaveSystem.save_slot(slot, false))


func _handle_save_result(res: Dictionary) -> void:
	var slot := int(res.get("slot", 0))
	if bool(res.get("ok", false)):
		_hint("已保存到槽位 %d（%d 字节）" % [slot, int(res.get("bytes", 0))], "ok")
		show_home()
		refresh()
		return
	if bool(res.get("requires_confirm", false)):
		if slot == 0:
			show_grid("save", String(res.get("reason", "")), "warn")
			return
		_ask_overwrite(slot)
		return
	_hint("保存失败：%s" % String(res.get("reason", "")), "bad")


func _load_from(slot: int) -> void:
	var res: Dictionary = SaveSystem.load_slot(slot)
	if bool(res.get("ok", false)):
		var warns: PackedStringArray = res.get("warnings", PackedStringArray())
		var tail := "" if warns.is_empty() else "，%d 条字段告警" % warns.size()
		_hint("已读取槽位 %d%s（世界重建留到 S1.9：本次只应用 GameState 已登记字段）" % [
			slot, tail], "ok")
		show_home()
		refresh()
		return
	_hint("读取失败：%s" % String(res.get("reason", "")), "bad")


func _ask_overwrite(slot: int) -> void:
	_pending_slot = slot
	var info: Dictionary = SaveSystem.slot_info(slot)
	_lbl_confirm_title.text = "覆盖槽位 %d 的存档？" % slot
	_lbl_confirm_detail.text = "%s\n存于 %s" % [
		String(info.get("label", "")), String(info.get("saved_at", ""))]
	_confirm.visible = true
	_hint("覆盖会丢掉槽位 %d 的旧存档，需要确认" % slot, "warn")


func _confirm_overwrite() -> void:
	var slot := _pending_slot
	if slot == 0:
		return
	_confirm.visible = false
	_pending_slot = 0
	var res: Dictionary = SaveSystem.save_slot(slot, true)
	if bool(res.get("ok", false)):
		_hint("已覆盖槽位 %d（%d 字节）" % [slot, int(res.get("bytes", 0))], "ok")
		show_home()
		refresh()
		return
	_hint("覆盖失败：%s" % String(res.get("reason", "")), "bad")


func _cancel_confirm() -> void:
	_confirm.visible = false
	_pending_slot = 0


func _hint(text: String, tone := "info") -> void:
	if _lbl_hint == null:
		return
	var col := MUTED
	match tone:
		"ok":
			col = Color("2f7d32")
		"warn":
			col = Color("a8410f")
		"bad":
			col = Color("a4133c")
		_:
			col = MUTED
	_lbl_hint.text = text
	_lbl_hint.add_theme_color_override("font_color", col)
	if _lbl_grid_hint != null:
		_lbl_grid_hint.text = text
		_lbl_grid_hint.add_theme_color_override("font_color", col)


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------
func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP  # 挡住主 HUD 的按钮
	root.add_child(backdrop)

	_build_home(root)
	_build_grid_page(root)
	_build_confirm(root)


func _build_home(root: Control) -> void:
	_home = CenterContainer.new()
	_home.name = "Home"
	_home.set_anchors_preset(Control.PRESET_FULL_RECT)
	_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_home)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", _sb(PAPER, 5, 12, Vector2(9, 9), 22))
	panel.custom_minimum_size = Vector2(560, 0)
	_home.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var title := _label("口袋沙盘", 30)
	title.name = "Title"
	col.add_child(title)
	var sub := _label("存档菜单 · ESC 关闭", 13, MUTED)
	sub.name = "Sub"
	col.add_child(sub)

	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 5)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	_lbl_status = _label("", 14)
	_lbl_status.name = "Status"
	col.add_child(_lbl_status)
	_lbl_slot = _label("", 14)
	_lbl_slot.name = "Slot"
	col.add_child(_lbl_slot)

	var actions := VBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 10)
	col.add_child(actions)

	var save := _button("保存", GREEN)
	save.name = "Save"
	save.pressed.connect(_on_save)
	actions.add_child(save)

	var save_as := _button("另存为（选槽位）", YELLOW)
	save_as.name = "SaveAs"
	save_as.pressed.connect(_on_save_as)
	actions.add_child(save_as)

	var load := _button("读取", CYAN)
	load.name = "Load"
	load.pressed.connect(_on_load)
	actions.add_child(load)

	var settings := _button("设置", LILAC)
	settings.name = "Settings"
	settings.pressed.connect(_on_settings)
	actions.add_child(settings)

	var resume := _button("返回游戏", PINK)
	resume.name = "Resume"
	resume.pressed.connect(_on_resume)
	actions.add_child(resume)

	_lbl_hint = _label("ESC 关闭菜单 · 「保存」写入当前槽位，「另存为」挑一格", 13, MUTED)
	_lbl_hint.name = "Hint"
	_lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_hint.custom_minimum_size = Vector2(516, 0)
	col.add_child(_lbl_hint)


func _build_grid_page(root: Control) -> void:
	_grid_page = CenterContainer.new()
	_grid_page.name = "GridPage"
	_grid_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_page.visible = false
	root.add_child(_grid_page)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", _sb(PAPER, 5, 12, Vector2(9, 9), 22))
	_grid_page.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var title := _label("选择槽位", 26)
	title.name = "Title"
	col.add_child(title)

	_grid = GRID_SCRIPT.new() as PanelContainer
	_grid.name = "Grid"
	col.add_child(_grid)
	_grid.slot_pressed.connect(_on_slot_pressed)

	_lbl_grid_hint = _label("", 13, MUTED)
	_lbl_grid_hint.name = "Hint"
	_lbl_grid_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_grid_hint.custom_minimum_size = Vector2(916, 0)
	col.add_child(_lbl_grid_hint)

	var back := _button("返回", PAPER)
	back.name = "Back"
	back.pressed.connect(func() -> void: show_home())
	col.add_child(back)


func _build_confirm(root: Control) -> void:
	_confirm = Control.new()
	_confirm.name = "Confirm"
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.visible = false
	root.add_child(_confirm)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.07, 0.06, 0.10, 0.74)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", _sb(PAPER, 6, 14, Vector2(10, 10), 24))
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	_lbl_confirm_title = _label("覆盖存档？", 26)
	_lbl_confirm_title.name = "Title"
	col.add_child(_lbl_confirm_title)
	_lbl_confirm_detail = _label("", 14, MUTED)
	_lbl_confirm_detail.name = "Detail"
	_lbl_confirm_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_confirm_detail.custom_minimum_size = Vector2(532, 0)
	col.add_child(_lbl_confirm_detail)

	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 5)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)

	var no := _button("取消（保留旧存档）", CYAN)
	no.name = "No"
	no.pressed.connect(func() -> void:
		_cancel_confirm()
		_hint("已取消覆盖：旧存档没有被改动", "info"))
	row.add_child(no)

	var yes := _button("确认覆盖", PINK)
	yes.name = "Yes"
	yes.pressed.connect(_confirm_overwrite)
	row.add_child(yes)


func _build_font() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray([
		"PingFang SC", "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC",
		"Source Han Sans SC", "Microsoft YaHei", "Arial Unicode MS", "Sans-Serif"])
	_font.font_weight = 700
	_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY


func _sb(bg: Color, border: int, shadow: int, offset: Vector2, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = INK
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(0)
	sb.shadow_color = INK
	sb.shadow_size = shadow
	sb.shadow_offset = offset
	sb.anti_aliasing = false
	sb.set_content_margin_all(pad)
	return sb


func _label(text: String, size: int, col: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 焦点环会让同一状态出现两种像素；截图门禁要求逐位一致，故不要焦点环
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_stylebox_override("normal", _sb(accent, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("hover", _sb(accent.lightened(0.14), 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("pressed", _sb(accent.darkened(0.14), 4, 0, Vector2(1, 1), 10))
	b.add_theme_stylebox_override("focus", _sb(accent, 4, 6, Vector2(5, 5), 10))
	return b
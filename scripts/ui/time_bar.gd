extends CanvasLayer
## 时间条（S1.4b）：屏幕顶部常驻的一行 —— `暂停 / 1x / 2x / 4x` 四个按钮 + 当前日期时间。
##
## 【ROADMAP §6 S1.4b】这一批把"时间能停、能快"变成玩家可见的东西。UI 语言沿用
## `ui_kit.gd` 的新粗野主义：厚墨边、硬投影、零圆角、纯色块，"当前档位"就是按钮底色
## 换成黄色，不额外画勾选标记（多一种形状就多一套像素要解释）。
##
## 为什么是 CanvasLayer 而不是 Control：它必须**不随场景重开而重建**（战略图 `boot()`
## 可以跑两次），并且要压在 3D 之上。`process_mode = PROCESS_MODE_ALWAYS` + 进 `#hud`
## 组是 S0.3 批次 4 / S0.4 批次 2 定下的两条老规矩：暂停时按钮仍然能点（否则一按暂停
## 就再也点不到"继续"），F1「隐藏全部 UI」按组找属主。
##
## 只读 `GameState`，不持有时间。日期从 `date_text()` 取，档位从 `speed` 取 —— 本文件
## 里没有第二份日历，也没有第二个 `game_time`（S1.4a 的唯一时钟判据）。
##
## ⚠️ autoload 一律**按路径**查找（`/root/GameState`）：`tools/verify.gd` 跑在
## `--script` MainLoop 里，那里 autoload 标识符不参与编译（ENGINEERING §5 陷阱 34），
## 而这个节点正是被它实例化来证明接线的。

## 档位按钮的宽度。够放 "4x"，又比日期面板窄，视觉上"按钮组 + 读数"分成两块。
const TIER_BUTTON_WIDTH := 76
## 暂停按钮略宽：它的文案会在 "暂停" / "继续" 之间切换，宽度固定住就不会跳版。
const PAUSE_BUTTON_WIDTH := 96
## 没有 `GameState`（裸 `--script` 夹具）时的读数占位，避免一个空字符串面板。
const NO_CLOCK_TEXT := "时间不可用"

## 档位清单的兜底。正常运行时由 `GameState.SPEED_TIERS` 覆盖（见 `_ready`）—— 这个文件
## 必须能在 `--script` 模式下编译，而那里 autoload 标识符不可见（陷阱 34），所以不能
## 直接写 `GameState.SPEED_TIERS`。运行时从属主的脚本常量表里读，仍然只有一个来源。
const FALLBACK_TIERS := [1, 2, 4]

const TIER_ACCENT := UiKit.YELLOW
const IDLE_ACCENT := UiKit.PAPER
const PAUSED_ACCENT := UiKit.PINK
const RUNNING_ACCENT := UiKit.CYAN

var _font: SystemFont
## 档位清单（`GameState.SPEED_TIERS` 的运行时副本，见 `FALLBACK_TIERS`）。
var tiers: Array = FALLBACK_TIERS
var _btn_pause: Button
var _tier_buttons := {}
var _lbl_date: Label
## 上一帧已经画出去的档位 / 暂停态。只在**变化时**重刷样式，避免每帧重建 5 个
## `StyleBoxFlat`（那会让"每帧分配"变成一个看不见的泄漏源）。
var _shown_tier := 0
var _shown_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	add_to_group("hud")
	_font = UiKit.font()
	tiers = _resolve_tiers()
	_build()


## 顶部居中的一整条。`MarginContainer` 走 `PRESET_TOP_WIDE` + 20 px 边距，
## 里层 `HBoxContainer` 居中 —— 这样窗口宽度变化时按钮组始终居中，不需要锚点算偏移。
func _build() -> void:
	var root := Control.new()
	root.name = "TimeRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	root.add_child(margin)

	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	center.add_child(_build_controls())
	center.add_child(_build_readout())
	refresh()


## 左侧：暂停 + 三个档位按钮。
func _build_controls() -> Control:
	var panel := PanelContainer.new()
	panel.name = "Controls"
	panel.add_theme_stylebox_override("panel", UiKit.sb(UiKit.PAPER, 5, 10, Vector2(8, 8), 12))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	_btn_pause = UiKit.button_hud(_font, "暂停", RUNNING_ACCENT)
	_btn_pause.name = "Pause"
	_btn_pause.custom_minimum_size = Vector2(PAUSE_BUTTON_WIDTH, 46)
	_btn_pause.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn_pause.pressed.connect(_on_pause_pressed)
	row.add_child(_btn_pause)

	for tier in tiers:
		var b := UiKit.button_hud(_font, "%dx" % int(tier), IDLE_ACCENT)
		b.name = "Tier%d" % int(tier)
		b.custom_minimum_size = Vector2(TIER_BUTTON_WIDTH, 46)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_on_tier_pressed.bind(int(tier)))
		row.add_child(b)
		_tier_buttons[int(tier)] = b
	return panel


## 右侧：`第 Y 年 M 月 D 日 HH:MM  ×N` 读数。
func _build_readout() -> Control:
	var panel := PanelContainer.new()
	panel.name = "Readout"
	panel.add_theme_stylebox_override("panel", UiKit.sb(UiKit.PAPER, 5, 10, Vector2(8, 8), 12))
	_lbl_date = UiKit.label(_font, NO_CLOCK_TEXT, 22)
	_lbl_date.name = "Date"
	_lbl_date.custom_minimum_size = Vector2(320, 0)
	_lbl_date.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_lbl_date)
	return panel


## 暂停 = `get_tree().paused`（见 `GameState.toggle_pause` 的注释：冻结的是整棵树，
## 不是本节点）。按钮自己在 `PROCESS_MODE_ALWAYS`，所以按得回来。
func _on_pause_pressed() -> void:
	var gs := _game_state()
	if gs != null:
		gs.call("toggle_pause")
	refresh()


func _on_tier_pressed(tier: int) -> void:
	var gs := _game_state()
	if gs != null and bool(gs.call("set_speed", tier)):
		refresh()


func _process(_delta: float) -> void:
	refresh()


## 把"当前事实"画到控件上。幂等：状态没变时一个 StyleBox 都不重建。
func refresh() -> void:
	var gs := _game_state()
	if gs == null:
		if _shown_tier != -1:
			_shown_tier = -1
			_lbl_date.text = NO_CLOCK_TEXT
		return

	var paused := bool(gs.call("is_paused"))
	if paused != _shown_paused:
		_shown_paused = paused
		_btn_pause.text = "继续" if paused else "暂停"
		UiKit.repaint_hud(_btn_pause, PAUSED_ACCENT if paused else RUNNING_ACCENT)

	var tier := int(gs.get("speed"))
	if tier != _shown_tier:
		_shown_tier = tier
		for t in _tier_buttons.keys():
			UiKit.repaint_hud(_tier_buttons[t], TIER_ACCENT if int(t) == tier else IDLE_ACCENT)

	_lbl_date.text = "%s  ×%d" % [String(gs.call("date_text")), tier]


## 供用例断言的一帧快照 —— 用例读这个，而不是自己去摸按钮树。
func report() -> Dictionary:
	var texts: Array = []
	for t in _tier_buttons.keys():
		texts.append(String((_tier_buttons[t] as Button).text))
	return {
		"paused": _shown_paused,
		"pause_text": String(_btn_pause.text) if _btn_pause != null else "",
		"speed": _shown_tier,
		"tier_texts": texts,
		"date_text": String(_lbl_date.text) if _lbl_date != null else "",
		"is_hud": is_in_group("hud"),
		"always_on": process_mode == Node.PROCESS_MODE_ALWAYS,
	}


## `GameState.SPEED_TIERS`，但不通过标识符拿：`--script` 模式下 autoload 名字不参与编译。
## 读不到（裸夹具）就退到 `FALLBACK_TIERS` —— 与属主同序同值，UI 不会因此少一个按钮。
func _resolve_tiers() -> Array:
	var gs := _game_state()
	if gs == null:
		return FALLBACK_TIERS
	var script := gs.get_script() as Script
	if script == null:
		return FALLBACK_TIERS
	var consts: Dictionary = script.get_script_constant_map()
	var list: Variant = consts.get("SPEED_TIERS", FALLBACK_TIERS)
	if list is Array and not (list as Array).is_empty():
		return list
	return FALLBACK_TIERS


func _game_state() -> Node:
	return get_node_or_null("/root/GameState")
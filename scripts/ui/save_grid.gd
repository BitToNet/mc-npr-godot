extends PanelContainer
## SaveGrid — 3×3 存档宫格（ROADMAP §5 S0.3 批次 4，契约 §3.5）。
##
## 它只做一件事：把 `SaveSystem.list_slots()` 的结果画成九张卡片。
## **自己不算、不猜、不缓存**任何槽位数据 —— 卡片上的每个字都来自服务，
## 于是「宫格显示的和实际存的是不是同一件事」不需要靠约定维持：
## 用例可以逐格断言 `卡片正文 == slot_info(slot).label`。
##
## 刻意不做的事：
##   * 不写盘、不读盘：写入/读取是菜单页的流程，宫格只负责回答「点了哪一格」；
##   * 不弹确认框：覆盖确认是**整页**弹窗（见 `menu_page.gd`）——它要盖住
##     整个菜单，挂在宫格内部就盖不住。
##
## 卡片用 `Button` 而不是 `Panel` + 手写命中检测：hover / 按下态 / 键盘焦点
## 全部由引擎提供，S0.4 的键盘导航可以直接复用 `card(slot).grab_focus()`。
##
## 视觉语言与 `scripts/ui/ui_panel.gd` 同源（厚墨边、硬投影、纯色块、零圆角）。
## 两处样式助手暂时各留一份：抽公共 `UiStyle` 属于 S0.5 工程规范的活，
## 本批不顺手重构（一次提交只承载一件事）。

signal slot_pressed(slot: int)

const COLUMNS := 3
const SLOT_COUNT := 9
const CARD_SIZE := Vector2(296, 104)
const EMPTY_LABEL := "空槽位"
const BROKEN_LABEL := "损坏的存档"

const INK := Color("13101b")
const PAPER := Color("fff9e8")
const YELLOW := Color("ffe45c")
const PINK := Color("ff8fb1")
const GREY := Color("cdc7bb")
const MUTED := Color("6b6480")

var _font: SystemFont
var _cards: Array = []
var _titles: Array = []
var _bodies: Array = []
var _selected := 0


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray([
		"PingFang SC", "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC",
		"Source Han Sans SC", "Microsoft YaHei", "Arial Unicode MS", "Sans-Serif"])
	_font.font_weight = 700
	_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	add_theme_stylebox_override("panel", _sb(PAPER, 5, 10, Vector2(8, 8), 16))

	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var title := _label("存档槽位 1 - 9", 20)
	col.add_child(title)
	col.add_child(_label("点击一格：另存为写入它，读取读取它", 12, MUTED))

	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 4)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var cards := GridContainer.new()
	cards.name = "Cards"
	cards.columns = COLUMNS
	cards.add_theme_constant_override("h_separation", 14)
	cards.add_theme_constant_override("v_separation", 12)
	col.add_child(cards)

	for slot in range(1, SLOT_COUNT + 1):
		cards.add_child(_build_card(slot))


# ---------------------------------------------------------------------------
# 公开查询（用例与 S0.4 键盘导航都用这两个）
# ---------------------------------------------------------------------------
## 第 `slot` 格的按钮；槽位号非法返回 null。
func card(slot: int) -> Button:
	if slot < 1 or slot > SLOT_COUNT:
		return null
	return _cards[slot - 1] as Button


## 宫格当前记忆的「当前槽位」（与 `SaveSystem.current_slot` 同源，0 = 未选择）。
func selected_slot() -> int:
	return _selected


## 重新从 `SaveSystem` 读九格。纯读：不写盘、不改 `GameState`。
## 服务尚未就绪（`_ready` 还没跑）时为无操作，便于调用方在任意时机调它。
func refresh() -> void:
	if _cards.is_empty():
		return
	_selected = int(SaveSystem.current_slot)
	var infos: Array = SaveSystem.list_slots()
	for slot in range(1, SLOT_COUNT + 1):
		var info: Dictionary = infos[slot - 1]
		var label := String(info.get("label", EMPTY_LABEL))
		var kind := "empty"
		if bool(info.get("exists", false)):
			kind = "filled"
		elif label == BROKEN_LABEL:
			kind = "broken"
		var is_sel := slot == _selected
		(_titles[slot - 1] as Label).text = "槽位 %d%s" % [slot, "   ← 当前" if is_sel else ""]
		(_bodies[slot - 1] as Label).text = label
		_apply_card_style(_cards[slot - 1] as Button, kind, is_sel)


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------
func _build_card(slot: int) -> Button:
	var btn := Button.new()
	btn.name = "Slot%d" % slot
	btn.custom_minimum_size = CARD_SIZE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 焦点环会随焦点状态改变像素：截图门禁要求同一状态逐位一致，故不要焦点环。
	# 键盘导航（S0.4）改用显式的「← 当前」标记，不依赖引擎焦点环。
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", INK)
	btn.add_theme_color_override("font_hover_color", INK)
	btn.add_theme_color_override("font_pressed_color", INK)
	btn.pressed.connect(func() -> void: slot_pressed.emit(slot))

	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 10
	box.offset_right = -12
	box.offset_bottom = -10
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	var title := _label("槽位 %d" % slot, 16)
	title.name = "Title"
	box.add_child(title)
	# 正文不换行、按需裁切：换行位置依赖字体度量，会让截图在不同机器上形状不同
	var body := _label(EMPTY_LABEL, 12, MUTED)
	body.name = "Body"
	body.clip_text = true
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(body)

	_cards.append(btn)
	_titles.append(title)
	_bodies.append(body)
	_apply_card_style(btn, "empty", false)
	return btn


func _apply_card_style(btn: Button, kind: String, selected: bool) -> void:
	var bg := GREY
	match kind:
		"filled":
			bg = YELLOW
		"broken":
			bg = PINK
		_:
			bg = GREY
	# 当前槽位：墨边加粗（第二信号；第一信号是标题里的「← 当前」）
	var border := 8 if selected else 4
	btn.add_theme_stylebox_override("normal", _sb(bg, border, 6, Vector2(5, 5), 10))
	btn.add_theme_stylebox_override("hover", _sb(bg.lightened(0.12), border, 6, Vector2(5, 5), 10))
	btn.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.14), border, 0, Vector2(1, 1), 10))
	btn.add_theme_stylebox_override("focus", _sb(bg, border, 6, Vector2(5, 5), 10))


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
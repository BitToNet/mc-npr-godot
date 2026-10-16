class_name UiPanel
extends CanvasLayer
## Neo-brutalist control panel.
##
## Thick ink borders, hard offset shadows, flat saturated blocks of colour,
## chunky square grabbers — the UI is drawn with the same language as the
## diorama: hard edges, no gradients, no soft blur.  Every control maps to a
## real system in the scene (seed / outline / cel bands / camera / clock).

signal regenerate_pressed
signal outline_pressed
signal bands_pressed
signal camera_pressed
signal autocycle_pressed
signal time_scrubbed(t: float)

const INK := Color("13101b")
const PAPER := Color("fff9e8")
const YELLOW := Color("ffe45c")
const CYAN := Color("6fe3e1")
const PINK := Color("ff8fb1")
const GREEN := Color("7ed957")
const LILAC := Color("c3b1ff")

var _font: SystemFont
var _btn_seed: Button
var _btn_outline: Button
var _btn_bands: Button
var _btn_camera: Button
var _btn_cycle: Button
var _slider: BrutalSlider
var _lbl_time: Label
var _lbl_readout: Label
var _syncing := false


func _ready() -> void:
	# S0.3 batch 4: the save menu pauses the tree, so a HUD that inherited the pause
	# mode would stop receiving clicks the moment ESC opens the menu (and would also
	# stop being drawn) — the debug panel is supposed to stay usable.  Same rule as
	# `Clock` and `menu_page.gd`.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_font()
	var root := Control.new()
	root.name = "UIRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	# ---- row 1: control panel (left) + status badge (right) ----------------
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 14)
	column.add_child(top_row)
	top_row.add_child(_build_panel())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)
	top_row.add_child(_build_status())

	# ---- row 2: pushes the hint strip to the bottom ------------------------
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(grow)

	var bottom_row := HBoxContainer.new()
	bottom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom_row)
	bottom_row.add_child(_build_hint())


# ---------------------------------------------------------------------------
# widgets
# ---------------------------------------------------------------------------
func _build_font() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray([
		"PingFang SC", "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC",
		"Source Han Sans SC", "Microsoft YaHei", "Arial Unicode MS", "Sans-Serif"])
	_font.font_weight = 700
	_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY


func _sb(bg: Color, border: int = 4, shadow: int = 0, offset := Vector2.ZERO,
		pad := 14) -> StyleBoxFlat:
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
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_stylebox_override("normal", _sb(accent, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("hover", _sb(INK, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("pressed", _sb(accent.darkened(0.12), 4, 0, Vector2(1, 1), 10))
	b.add_theme_stylebox_override("focus", _sb(accent, 4, 6, Vector2(5, 5), 10))
	b.add_theme_stylebox_override("disabled", _sb(accent.darkened(0.3), 4, 0, Vector2.ZERO, 10))
	return b


func _build_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(PAPER, 5, 10, Vector2(8, 8), 18))
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var title := _label("POCKET SANDBOX", 25)
	col.add_child(title)
	col.add_child(_label("口袋沙盘 · NPR 微缩手办", 13, Color("6b6480")))

	var rule := ColorRect.new()
	rule.color = INK
	rule.custom_minimum_size = Vector2(0, 5)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	_btn_seed = _button("NEW SEED  重新生成", YELLOW)
	_btn_seed.pressed.connect(func() -> void: regenerate_pressed.emit())
	col.add_child(_btn_seed)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	col.add_child(row1)
	_btn_outline = _button("OUTLINE ON", CYAN)
	_btn_outline.pressed.connect(func() -> void: outline_pressed.emit())
	row1.add_child(_btn_outline)
	_btn_bands = _button("BANDS 3", LILAC)
	_btn_bands.pressed.connect(func() -> void: bands_pressed.emit())
	row1.add_child(_btn_bands)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	col.add_child(row2)
	_btn_camera = _button("CAM ORBIT", PINK)
	_btn_camera.pressed.connect(func() -> void: camera_pressed.emit())
	row2.add_child(_btn_camera)
	_btn_cycle = _button("AUTO DAY", GREEN)
	_btn_cycle.pressed.connect(func() -> void: autocycle_pressed.emit())
	row2.add_child(_btn_cycle)

	var time_row := VBoxContainer.new()
	time_row.add_theme_constant_override("separation", 6)
	col.add_child(time_row)
	_lbl_time = _label("TIME  07:40", 15)
	time_row.add_child(_lbl_time)
	_slider = BrutalSlider.new()
	_slider.name = "TimeSlider"
	_slider.label_font = _font
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.set_value_no_signal(0.32)
	_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			time_scrubbed.emit(v))
	time_row.add_child(_slider)

	return panel


func _build_status() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(INK, 4, 8, Vector2(6, 6), 14))
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_lbl_readout = _label("SEED 00000", 15, PAPER)
	panel.add_child(_lbl_readout)
	return panel


func _build_hint() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(PAPER, 4, 8, Vector2(6, 6), 12))
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	col.add_child(_label("WASD / 方向键 漫游   ·   SPACE 跳跃   ·   Q E 旋转", 14))
	col.add_child(_label("滚轮 缩放   ·   R 新种子   ·   O 描边   ·   C 视角   ·   T 昼夜自转", 14))
	return panel


# ---------------------------------------------------------------------------
func sync(state: Dictionary) -> void:
	_syncing = true
	var outline: bool = state.get("outline", true)
	_btn_outline.text = "OUTLINE " + ("ON" if outline else "OFF")
	_btn_outline.modulate = Color.WHITE if outline else Color(0.72, 0.72, 0.78)
	_btn_bands.text = "BANDS %d" % int(state.get("bands", 3))
	_btn_camera.text = "CAM %s" % String(state.get("camera", "ORBIT"))
	var auto: bool = state.get("autocycle", true)
	_btn_cycle.text = "AUTO DAY " + ("ON" if auto else "OFF")
	_btn_cycle.modulate = Color.WHITE if auto else Color(0.72, 0.72, 0.78)
	var t: float = clampf(float(state.get("time", 0.3)), 0.0, 1.0)
	_slider.set_value_no_signal(t)
	_lbl_time.text = "TIME  %s" % String(state.get("clock", "07:40"))
	_lbl_readout.text = "SEED %d   TREES %d   ROCKS %d   %d FPS" % [
		int(state.get("seed", 0)), int(state.get("trees", 0)),
		int(state.get("rocks", 0)), int(state.get("fps", 0))]
	_syncing = false
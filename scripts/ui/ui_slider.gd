class_name BrutalSlider
extends Control
## Neo-brutalist time scrubber.
##
## Godot's stock HSlider theme items refused to paint the track and the fill on
## top of the cream panel, so the control collapsed into a lone grabber square.
## This draws the whole widget by hand instead: an ink-framed track, a hard
## offset shadow, a flat colour fill, a chunky square grabber and hour ticks.
## Everything is snapped to whole pixels so the edges stay razor sharp, exactly
## like the rest of the panel.

signal value_changed(v: float)

## S0.4 批次 1：颜色收归 `res://scripts/ui/ui_kit.gd`（唯一来源）。本控件是手绘的
## （不走 StyleBox），故只需要这一个常量；轨迹/抓手的两个色值仍留在下方
## `track_fill` / `track_bg` 的默认值里（它们是可被调用方覆盖的实例属性）。
const INK := UiKit.INK
const TRACK_H := 18
const BORDER := 3
const SHADOW := 4
const GRAB_W := 24
const GRAB_H := 32
## 24h clock handle positions, drawn as small ink ticks behind the track.
const TICKS := [0.0, 0.25, 0.5, 0.75]
const TICK_LABELS := ["00", "06", "12", "18"]

var min_value := 0.0
var max_value := 1.0
var track_fill := Color("ffe45c")
var track_bg := Color("fff9e8")
var dragging := false
## Supplied by the panel so the hour ticks use the same heavy face as the rest
## of the neo-brutalist chrome.
var label_font: Font = null

var _value := 0.3


func _ready() -> void:
	custom_minimum_size = Vector2(0, GRAB_H + SHADOW + 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func get_value() -> float:
	return _value


func set_value(v: float) -> void:
	var nv := clampf(v, min_value, max_value)
	if absf(nv - _value) < 0.0001:
		return
	_value = nv
	queue_redraw()


## Used by the per-frame sync so pushing the clock state back into the widget
## never re-triggers a scrub event.
func set_value_no_signal(v: float) -> void:
	set_value(v)


func ratio() -> float:
	var span := max_value - min_value
	if span <= 0.0:
		return 0.0
	return clampf((_value - min_value) / span, 0.0, 1.0)


# ---------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			_scrub_to(event.position.x)
			accept_event()
		else:
			if dragging:
				dragging = false
				accept_event()
	elif event is InputEventMouseMotion and dragging:
		_scrub_to(event.position.x)
		accept_event()


func _scrub_to(px: float) -> void:
	var usable := maxf(size.x - GRAB_W, 1.0)
	var r := clampf((px - GRAB_W * 0.5) / usable, 0.0, 1.0)
	_value = min_value + r * (max_value - min_value)
	queue_redraw()
	value_changed.emit(_value)


func _grabber_x() -> float:
	return roundf(ratio() * maxf(size.x - GRAB_W, 0.0))


# ---------------------------------------------------------------------------
func _draw() -> void:
	var w := size.x
	var cy := size.y * 0.5
	var track_y := roundf(cy - TRACK_H * 0.5)
	var grab_x := _grabber_x()
	var fill_w := roundf(grab_x + GRAB_W * 0.5)

	# ---- hard offset shadow behind the whole widget ------------------------
	_rect(Rect2(SHADOW, track_y + SHADOW, w, TRACK_H), INK)

	# ---- track: ink frame, cream bed, flat colour fill ---------------------
	_rect(Rect2(0, track_y, w, TRACK_H), INK)
	_rect(Rect2(BORDER, track_y + BORDER, w - BORDER * 2, TRACK_H - BORDER * 2), track_bg)
	if fill_w > BORDER:
		_rect(Rect2(BORDER, track_y + BORDER, maxf(fill_w - BORDER, 0.0), TRACK_H - BORDER * 2), track_fill)

	# ---- hour ticks: short ink bars poking out below the track -------------
	# mapped through the same usable span as the grabber so a tick sits exactly
	# under the knob when the clock reaches that hour.
	var usable := maxf(w - GRAB_W, 0.0)
	for i in TICKS.size():
		var tx := roundf(float(TICKS[i]) * usable + GRAB_W * 0.5)
		_rect(Rect2(clampf(tx - 1.5, 0.0, w - 3.0), track_y + TRACK_H, 3, 6), INK)
	var f := _font_for()
	if f != null:
		for i in TICKS.size():
			var tx := float(TICKS[i]) * usable + GRAB_W * 0.5
			var s: String = TICK_LABELS[i]
			var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(f, Vector2(clampf(tx - tw * 0.5, 0.0, maxf(w - tw, 0.0)), track_y + TRACK_H + 20),
					s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.75))

	# ---- chunky grabber with its own hard shadow ---------------------------
	var gy := roundf(cy - GRAB_H * 0.5)
	_rect(Rect2(grab_x + 3, gy + 3, GRAB_W, GRAB_H), INK)
	_rect(Rect2(grab_x, gy, GRAB_W, GRAB_H), INK)
	_rect(Rect2(grab_x + BORDER, gy + BORDER, GRAB_W - BORDER * 2, GRAB_H - BORDER * 2),
			Color("fff9e8") if not dragging else track_fill)
	# two grip lines so it reads as a physical slider knob
	_rect(Rect2(grab_x + 8, gy + 11, GRAB_W - 16, 3), INK)
	_rect(Rect2(grab_x + 8, gy + 18, GRAB_W - 16, 3), INK)


## Fills a rect with snapped integer edges and no anti-aliasing.
func _rect(r: Rect2, c: Color) -> void:
	var rr := Rect2(roundf(r.position.x), roundf(r.position.y), roundf(r.size.x), roundf(r.size.y))
	if rr.size.x <= 0.0 or rr.size.y <= 0.0:
		return
	draw_rect(rr, c, true)


func _font_for() -> Font:
	if label_font != null:
		return label_font
	return ThemeDB.fallback_font
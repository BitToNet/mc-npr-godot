extends CanvasLayer

## 聚落交互提示条（S1.5b）：屏幕底部居中的一行。
##
## 两种状态，**都必须是看得见的**（ROADMAP S1.5 的 `D-` 判据）：
##
##   * 进入范围：`进入 村庄 3` + `[Enter]` —— 纸底墨字，和 HUD 其它面板同一种视觉语言。
##   * 按下 Enter：`未开放` + 一句说明 —— **灰底**（`UiKit.GREY`），停留 120 帧。
##
## 为什么"未开放"也要给反馈：这一刻聚落面板还没接（S1.5c 才交付）。如果按键毫无反应，
## 玩家会以为是 bug；如果弹一个空面板，又会被当成"功能坏了"。灰底 + 明确标签是第三种、
## 也是唯一诚实的选择：**看得见、看得懂、点不进去**。
##
## 文案全部走 key（`UI_SETTLEMENT_*`，见 `data/i18n/strings.csv`）：本文件里一个面向玩家的
## 中文字面量都没有 —— 守卫规则 `hardcoded_text` 会扫 `res://scripts/ui/` 下的新文件。
##
## 与 `time_bar.gd` 同一套老规矩：`PROCESS_MODE_ALWAYS`（暂停时也能读提示）、进 `#hud` 组
## （F1「隐藏全部 UI」按组找属主）、只读外部状态、自己不留时间。
## 停留时长用**帧计数**而不是 `Time`：截图门禁要求逐位可复现（S0.6 的冻结规则）。

## 「未开放」停留多久（帧）。60 fps 下 2 秒，够读完一句短说明。
const LOCKED_FRAMES := 120

const NORMAL_BG := UiKit.PAPER
const LOCKED_BG := UiKit.GREY
const MAIN_SIZE := 20
const SUB_SIZE := 15

## 最近一次 `refresh()` 给的焦点（`SettlementLayer.focus_at()` 的原样副本）。
var focus: Dictionary = {}
## 此刻是否正在显示「未开放」。
var locked := false

var _font: SystemFont
var _panel: PanelContainer
var _lbl_main: Label
var _lbl_sub: Label
var _locked_left := 0
var _shown_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	add_to_group("hud")
	_font = UiKit.font()
	_build()
	visible = false


## 每 tick 由 `strategic_map.gd` 喂一次焦点。范围内才显示；离开范围立刻收起。
func refresh(p_focus: Dictionary) -> void:
	focus = p_focus.duplicate()
	var in_range := not focus.is_empty() and bool(focus.get("in_range", false))
	if not in_range:
		locked = false
		_locked_left = 0
		_shown_id = ""
		visible = false
		# 文案也要清：隐藏的节点留着上一座聚落的名字，下一次"取景/断言"会读到鬼影。
		_lbl_main.text = ""
		_lbl_sub.text = ""
		return
	var id := String(focus.get("id", ""))
	if id != _shown_id:
		# 换了一座聚落：旧的「未开放」不再相关。
		_shown_id = id
		locked = false
		_locked_left = 0
	visible = true
	if locked and _locked_left > 0:
		_paint_locked()
	else:
		locked = false
		_paint_enter()


## 按下交互键。返回**事实**（不是布尔），调用方据此记账与断言：
##   `{ok, reason, id, label, shown}` —— `reason` 是 `locked` / `no_range`。
func press() -> Dictionary:
	if focus.is_empty() or not bool(focus.get("in_range", false)):
		return {"ok": false, "reason": "no_range", "id": "", "label": "", "shown": visible}
	locked = true
	_locked_left = LOCKED_FRAMES
	visible = true
	_paint_locked()
	return {
		"ok": true,
		"reason": "locked",
		"id": String(focus.get("id", "")),
		"label": String(focus.get("label", "")),
		"shown": visible,
	}


func _process(_delta: float) -> void:
	if _locked_left <= 0:
		return
	_locked_left -= 1
	if _locked_left <= 0 and visible:
		locked = false
		_paint_enter()


## 提示条的自述：用例据此断言"未开放"是看得见的，而不是按键没反应。
func report() -> Dictionary:
	return {
		"visible": visible,
		"locked": locked,
		"locked_left": _locked_left,
		"main": _lbl_main.text if _lbl_main != null else "",
		"sub": _lbl_sub.text if _lbl_sub != null else "",
		"focus_id": String(focus.get("id", "")),
		"in_range": bool(focus.get("in_range", false)),
		"group": "hud" if is_in_group("hud") else "",
	}


func _build() -> void:
	var root := Control.new()
	root.name = "SettlementPromptRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "bottom", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	root.add_child(margin)

	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "SettlementPromptPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiKit.sb(NORMAL_BG, 5, 10, Vector2(8, 8), 12))
	center.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	_lbl_main = UiKit.label(_font, "", MAIN_SIZE, UiKit.INK)
	row.add_child(_lbl_main)
	_lbl_sub = UiKit.label(_font, "", SUB_SIZE, UiKit.MUTED)
	row.add_child(_lbl_sub)


func _paint_enter() -> void:
	var label := String(focus.get("label", ""))
	_lbl_main.text = "%s %s" % [L10n.text("UI_SETTLEMENT_ENTER"), label]
	_lbl_sub.text = L10n.text("UI_SETTLEMENT_KEY_HINT")
	_lbl_sub.add_theme_color_override("font_color", UiKit.MUTED)
	_panel.add_theme_stylebox_override("panel", UiKit.sb(NORMAL_BG, 5, 10, Vector2(8, 8), 12))


func _paint_locked() -> void:
	_lbl_main.text = L10n.text("UI_SETTLEMENT_LOCKED")
	_lbl_sub.text = L10n.text("UI_SETTLEMENT_LOCKED_DETAIL")
	# 灰底 + 灰字：第二眼就能看出"这不是可继续的状态"。
	_lbl_sub.add_theme_color_override("font_color", UiKit.INK)
	_panel.add_theme_stylebox_override("panel", UiKit.sb(LOCKED_BG, 5, 10, Vector2(8, 8), 12))
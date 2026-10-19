class_name InputSetup
extends RefCounted
## Runtime input map.  Registering actions in code (instead of project.godot)
## keeps the project file readable and guarantees the bindings exist even if
## the InputMap section is stripped.

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"orbit_left": [KEY_Q],
	"orbit_right": [KEY_E],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"regen": [KEY_R],
	"toggle_outline": [KEY_O],
	"cycle_camera": [KEY_C],
	"toggle_cycle": [KEY_T],
}

## 调试热键（ROADMAP §5 S0.4）。**只存在于 Debug 构建**，见 `ensure_debug_hotkeys()`。
## 名字写成常量而不是散落的字面量：`scripts/core/debug_layer.gd` 与验收用例都引用它们，
## 三处各写一遍字符串迟早会漂移成"按了没反应"。
const ACTION_DEBUG_HIDE_UI := "debug_ui_hide"
const ACTION_DEBUG_OVERLAY := "debug_overlay"
const DEBUG_BINDINGS := {
	ACTION_DEBUG_HIDE_UI: [KEY_F1],
	ACTION_DEBUG_OVERLAY: [KEY_F3],
}

static var _done := false


static func ensure() -> void:
	if _done:
		return
	_done = true
	for action in BINDINGS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
	# mouse wheel zoom
	if not InputMap.has_action("zoom_in"):
		InputMap.add_action("zoom_in")
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	InputMap.action_add_event("zoom_in", wheel_up)
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	InputMap.action_add_event("zoom_out", wheel_down)
	# S0.4 批次 2：调试热键的**唯一**闸门就在这里。发布构建里这一行注册不出任何
	# action ⇒ `debug_layer.gd` 的 F1/F3 分支（以及将来 F5/F9）全部自然失效。
	ensure_debug_hotkeys(OS.is_debug_build())


## 调试热键注册闸门（ROADMAP §5 S0.4 的"发布构建必须默认关闭"验收项）。
##
## 调用点只有 `ensure()` 一处，参数是 `OS.is_debug_build()`。处理侧（`debug_layer.gd`）
## 只认"action 在不在"，不再自己判断一次构建类型 —— 两处判断迟早会不一致，
## 而"哪一处说了算"必须只有一个答案。
##
## `enabled=false` 时**删除**已存在的 action，而不是仅仅"不注册"：验收用例要在同一个
## 进程里先开、再关，并断言"关了之后按 F3 真的没反应"。若只做"不注册"，进程里残留的
## action 会让那条断言永远为真 —— 一个假通过的发布门禁比没有门禁更糟。
static func ensure_debug_hotkeys(enabled: bool) -> void:
	for action in DEBUG_BINDINGS.keys():
		if not enabled:
			if InputMap.has_action(action):
				InputMap.erase_action(action)
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in DEBUG_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)

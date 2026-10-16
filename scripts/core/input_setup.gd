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

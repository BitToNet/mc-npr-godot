extends Node
## SceneRouter — the single owner of "which scene is the game showing".
##
## S0.3 batch 3.  `change_scene_to_file()` is a global side effect: any script that calls
## it can yank the world out from under every other system.  The spec guard now refuses
## that call outside this file (rule `scene_change_owner`), so routing lives in exactly
## one place when the screen changes unexpectedly.
##
## THE STACK MUST MATCH REALITY.  `_stack` is not a wish list: every public call first
## re-reads `SceneTree.current_scene`, and if the live scene is not what the stack's top
## claims, the stack is dropped instead of being kept alive on a stale belief.  A scene
## the engine loaded by itself (`run/main_scene`) or a test loaded by hand is likewise
## adopted as the route root — that is what lets the two entry paths agree without either
## of them having to know about this service.
##
## WHAT THIS BATCH DELIBERATELY DOES NOT DO
##   * no gameplay facts: `encounter_started` / `battle_finished` belong to the systems
##     that actually know an encounter happened or a battle resolved (M1 S1.6 / M2).  A
##     second emitter here would become a double emission the moment those exist.
##   * no transition effect — `_switch_to()` is a hard cut.  The fade layer is UI and
##     arrives with the menu in batch 4 (it would also have to be cleared in the `B-`
##     six-camera gate, which is a batch-4 question, not this one).
##   * the world seed is still whatever `scenes/dev/diorama.tscn` exports; agreeing it with
##     `GameState.world_seed` is S1.2's job (see the note in the `s0_3_router` case).
##
## Depth is capped at 2 on purpose: world → battle is the only *stack* this game has until
## M1 adds the settlement screen.  Deeper stacks now would be unused speculation.
##
## THREE ROUTES, ONE LADDER (S1.0c).  `strategic` is registered because `scenes/world/
## strategic_map.tscn` now exists and S1.0d will repoint `world` at it — but this step
## deliberately stops at registration:
##   * no `goto_strategic()` and no change to `goto_world()` / `goto_battle()` semantics;
##   * nothing in the shipped game can reach `strategic` yet, so the stack is still only
##     world → battle.  `s1_0_routes` asserts both halves of that sentence (entry present,
##     public navigation surface unchanged), so a half-wired API is caught rather than
##     silently accepted.
## FOLLOW-UP for S1.0d: `goto_world()` currently only refuses when already on `world` or on
## `battle`.  Once `world` IS `strategic`, boot lands on `strategic` and `goto_world()` would
## reload that same file — that semantic must be decided in S1.0d, not papered over here.

const WORLD := "world"
const BATTLE := "battle"
## Not reachable yet (see the header).  S1.0d repoints `world` here; S1.2 fills the scene.
const STRATEGIC := "strategic"

## Route name → scene file.  Key order is `route_names()` order.
##
## S1.0a: the diorama moved from `res://scenes/main.tscn` to `res://scenes/dev/diorama.tscn`
## (content byte-identical; only the path changed).  `run/main_scene` points at the same
## file, and `s0_3_router` asserts the two agree — the path is a fact in three places, so
## a test now fails if only two of them are updated.
const SCENES := {
	WORLD: "res://scenes/dev/diorama.tscn",
	BATTLE: "res://scenes/battle/battle_stub.tscn",
	# S1.0c: registered but not navigable.  The scene is an empty `Node3D` on purpose —
	# S1.2 builds the real strategic layer, and an art placeholder here would be thrown away.
	STRATEGIC: "res://scenes/world/strategic_map.tscn",
}

## Hard cap on stack depth (see the header).
const MAX_DEPTH := 2

## Emitted **after** the engine accepted a switch.  `from` is "" when nothing had been
## routed yet (no scene was on screen), never a guess.
signal route_changed(from: String, to: String)

## Why the last call was refused.  Cleared on success.
var last_error := ""

var _stack: Array[Dictionary] = []
## Set while an engine scene change is in flight.  `current_scene` only catches up at the
## end of the frame, so until it does, the live scene is the *old* one and must not be
## used to disown the stack we just committed.
var _expected_path := ""


func is_known_route(route: String) -> bool:
	return SCENES.has(route)


func scene_path_for(route: String) -> String:
	return String(SCENES.get(route, ""))


func route_names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in SCENES.keys():
		out.append(String(k))
	return out


## Top of the stack — "" when nothing has been routed yet.
func current_route() -> String:
	_sync()
	return _top_name()


## Payload handed to the route on top ({} when there is none).
func current_payload() -> Dictionary:
	_sync()
	if _stack.is_empty():
		return {}
	return _stack[_stack.size() - 1]["payload"]


## Bottom-to-top route names, for the S0.4 debug overlay.
func route_stack() -> PackedStringArray:
	_sync()
	var out := PackedStringArray()
	for e in _stack:
		out.append(String(e["name"]))
	return out


func route_depth() -> int:
	_sync()
	return _stack.size()


func is_transitioning() -> bool:
	_sync()
	return _expected_path != ""


## Root route.  Allowed only while nothing is routed yet (boot): going back from a battle
## has to run through `return_to_world(result)`, otherwise the battle result would be
## dropped without anyone noticing.
func goto_world(payload: Dictionary = {}) -> bool:
	_sync()
	var from := _top_name()
	if from == WORLD:
		return _fail("已经在世界场景（world），无需重复进入")
	if from == BATTLE:
		return _fail("当前在 battle：返回世界请走 return_to_world(result)，以免丢掉战斗结果")
	return _switch_to(WORLD, [{"name": WORLD, "payload": payload}], from)


## One step deeper.  Only world → battle, and only while there is room.
func goto_battle(ctx: Dictionary = {}) -> bool:
	_sync()
	var from := _top_name()
	if from == "":
		return _fail("没有可用的起始路由：当前场景既不是 world 也不是 battle（先用 goto_world()）")
	# Depth is checked before the source route: at depth 2 the ladder has no third rung, and
	# "栈已满" is the honest reason (the source-route reason would hide the real limit).
	if _stack.size() >= MAX_DEPTH:
		return _fail("路由栈已满（上限 %d）：请用 return_to_world() 退出战斗" % MAX_DEPTH)
	if from != WORLD:
		return _fail("只能从 world 进入 battle（当前在 %s）" % from)
	var next := _stack.duplicate()
	next.append({"name": BATTLE, "payload": ctx})
	return _switch_to(BATTLE, next, from)


## One step back.  The world entry underneath takes the battle result, so the world can
## read what happened without a second global store.
func return_to_world(result: Dictionary = {}) -> bool:
	_sync()
	var from := _top_name()
	if from != BATTLE:
		return _fail("当前不在战斗场景（%s），无法返回世界" % ("未知" if from == "" else from))
	return _switch_to(WORLD, [{"name": WORLD, "payload": {"battle_result": result}}], from)


## --- internals ---------------------------------------------------------------

func _fail(reason: String) -> bool:
	last_error = reason
	return false


## Engine-level switch.  `next` is committed only if `change_scene_to_file()` accepted the
## request, so a refusal leaves the stack exactly as it was.
func _switch_to(target: String, next: Array, from: String) -> bool:
	if _expected_path != "":
		return _fail("上一次场景切换尚未落地（正切往 %s），拒绝并发切换" % _expected_path)
	var path := scene_path_for(target)
	if path == "":
		return _fail("未登记的路由：%s" % target)
	if not ResourceLoader.exists(path):
		return _fail("场景文件不存在：%s" % path)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		return _fail("切换到 %s 失败（%s）：当前场景保持不变" % [path, error_string(err)])
	_expected_path = path
	_stack.clear()
	_stack.assign(next)
	last_error = ""
	route_changed.emit(from, target)
	return true


## Reconcile the stack with the live scene before answering anything.
func _sync() -> void:
	var path := _current_scene_path()
	if _expected_path != "":
		if path != _expected_path:
			return  # switch still in flight: the live scene is the old one, don't judge
		_expected_path = ""
	var route := _route_for_path(path)
	if _stack.is_empty():
		if route != "":
			_stack.append({"name": route, "payload": {}})
		return
	# An external scene change (engine boot, a test, a future call site) makes the stack
	# a stale belief; drop it and adopt whatever is really on screen.
	if path != scene_path_for(_top_name()):
		_stack.clear()
		if route != "":
			_stack.append({"name": route, "payload": {}})


func _top_name() -> String:
	if _stack.is_empty():
		return ""
	return String(_stack[_stack.size() - 1]["name"])


func _current_scene_path() -> String:
	var tree := get_tree()
	if tree == null:
		return ""
	var cs := tree.current_scene
	if cs == null or not is_instance_valid(cs):
		return ""
	return cs.scene_file_path


func _route_for_path(path: String) -> String:
	if path == "":
		return ""
	for k in SCENES.keys():
		if String(SCENES[k]) == path:
			return String(k)
	return ""
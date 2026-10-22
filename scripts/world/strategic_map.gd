extends Node3D

## Root script of `scenes/world/strategic_map.tscn` (S1.2).
##
## SCOPE.  This scene owns exactly **one** `WorldSession`, one `StrategicTerrain`
## built from it (S1.2b), one `StrategicCamera` plus the fixed noon stage it needs
## to be visible at all (`WorldEnvironment` + `Sun` + `DayNight`, auto-cycle off),
## and — since S1.3c — the player party (`PartyMover` + its `PartyMarker`).  The
## day/night *system* is still S1.7's; here the node is only a way to reuse the
## diorama's exact sky and sun without inventing a second look.
##
## Booting the scene keeps one invariant true from the first batch: there is never
## more than one world instance per scene, and it is always built through
## `WorldSession.boot()`, which reseeds the generator (so re-entering the scene
## cannot inherit a half-drawn `world_gen` stream; see
## `docs/ENGINEERING.md` §9.8.5 / §9.9).
##
## INPUT SCOPE (S1.3c).  This node owns **click-to-move only**: left click → screen
## pick → `order_to()`.  Keyboard walking is deliberately *not* implemented in this
## batch — the interactive keys are already taken by the camera (arrows pan, Q/E
## yaw, R/F pitch, P projection, T tier), and a second scheme has to be designed
## together with unit selection, which is a later batch.  See ROADMAP §6 S1.3c.
##
## TIME DRIVES THE PARTY (S1.4b).  The party integrates on `GameState.simulation_tick`,
## not on `_process(delta)`: a tick is a fixed 1/60 s slice of **game** time, and a
## speed tier only changes how many ticks a frame runs.  Driving the mover from a raw
## delta instead would make "4x for one day" disagree with "1x for one day" in the
## last millimetres — which is exactly what `s1_4_speed` forbids.  The tick hands the
## step length along, so this file never spells `1.0 / 60.0` itself.
##
## AUTOLOADS BY PATH, NOT BY NAME.  `tools/verify.gd` runs as a `--script` MainLoop
## where autoload identifiers do not compile, and it instantiates this scene to
## prove the wiring.  Looking the nodes up as `/root/Rng` / `/root/GameState` keeps
## this script loadable in both modes.  `StrategicTerrain` does the same for
## `Style`, with a documented fallback (see that file).

## Fallback seed, identical to `GameState.DEFAULT_WORLD_SEED` and
## `Rng.DEFAULT_MASTER_SEED`.  Only used when `GameState` is absent (bare
## `--script` runs); the game always reads the live value.
const FALLBACK_SEED := 20250929

## The top-of-screen time bar (S1.4b).  No `class_name` on purpose: `verify.gd` counts
## the documented global classes, and this one is wired by path exactly like
## `ui_panel.gd`'s sibling `save_grid.gd`.
const TIME_BAR_SCRIPT := preload("res://scripts/ui/time_bar.gd")

## Fixed noon, so every screenshot of this scene is reproducible (S1.2c).
const STAGE_TIME := 0.5

## The world owned by this scene.  `null` until `_ready()` runs, and stays `null`
## with `boot_error` set if the build failed — so "not booted yet" and "booted but
## empty" are distinguishable.
var session: WorldSession
## The terrain mesh built from `session`.  `null` when the world failed to build.
var terrain: StrategicTerrain
## The three-tier camera.  `null` when the world failed to build.
var camera: StrategicCamera
## The player party (S1.3c).  `null` when the world failed to build.
var party: PartyMover
## The time bar (S1.4b): pause / 1x / 2x / 4x + the current date.  `null` only when
## the scene was never added to the tree.
var time_bar: CanvasLayer
## The stage nodes, kept as fields so the case can assert what is on screen.
var sun: DirectionalLight3D
var environment_owner: WorldEnvironment
var day_night: DayNight
## Non-empty only when `session` is `null` because something went wrong.
var boot_error := ""
## Why the party could not be built (empty in the normal case).  Kept separate from
## `boot_error`: a lost travel graph must not blank the whole strategic map.
var party_error := ""
## Last rejected click ("clicked the sky" / "clicked into water" as a reason).
var last_pick_error := ""


func _ready() -> void:
	boot()
	_rebuild_hud()
	# Godot disconnects a signal automatically when the receiving object is freed, so
	# leaving the scene needs no `_exit_tree()` bookkeeping here.
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.connect("simulation_tick", _on_simulation_tick)


## Builds (or rebuilds) the world for the current `GameState.world_seed`, then
## rebuilds the terrain, the stage, the camera and the party from it.  Safe to call
## twice: the previous session is dropped, and the new one is built from a reseeded
## generator, so a rebuild is not "the same world, continued".
func boot() -> void:
	session = null
	boot_error = ""
	var rng := get_node_or_null("/root/Rng")
	if rng == null:
		boot_error = "找不到 Rng autoload，无法生成世界"
		push_warning(boot_error)
		return
	var seed_value := FALLBACK_SEED
	var state := get_node_or_null("/root/GameState")
	if state != null:
		seed_value = int(state.get("world_seed"))
	session = WorldSession.boot(rng, seed_value)
	if not session.ok:
		boot_error = "; ".join(session.errors)
		push_warning("战略地图的世界生成失败：%s" % boot_error)
		return
	_rebuild_terrain()
	_rebuild_stage()
	_rebuild_camera()
	_rebuild_party()


## Applies the generated world to the visible mesh.  Kept separate from `boot()`
## so a future "the world changed but the seed did not" path only has to call
## this half.
func _rebuild_terrain() -> void:
	if terrain == null:
		terrain = StrategicTerrain.new()
		terrain.name = "StrategicTerrain"
		add_child(terrain)
	terrain.build(session.field)


## Fixed-noon sky and sun: the same `ProceduralSkyMaterial` / sun arc as the
## diorama, with the cycle pinned so two runs are pixel-identical.
func _rebuild_stage() -> void:
	if environment_owner == null:
		environment_owner = WorldEnvironment.new()
		environment_owner.name = "WorldEnvironment"
		add_child(environment_owner)
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
	if day_night == null:
		day_night = DayNight.new()
		day_night.name = "DayNight"
		add_child(day_night)
	day_night.setup(sun, environment_owner)
	# S1.4d — the stage **follows the one game clock** (S1.4 计划：战略层光照随游戏时间
	# 变化).  `STAGE_TIME` is kept as the *initial* frame only, so the very first rendered
	# frame is lit even before `GameState` has ticked; from the first `_process` on the
	# phase is read from `GameState.time_of_day()`.  Captures pin the clock to noon
	# (`--game-time=43200`, the same instant `STAGE_TIME` used to hard-code) ⇒ every
	# existing plate stays bit-identical.
	day_night.set_time(STAGE_TIME)
	day_night.set_auto_cycle(true)


## The camera reads the height field directly so it can refuse to enter a hill.
func _rebuild_camera() -> void:
	if camera == null:
		camera = StrategicCamera.new()
		camera.name = "StrategicCamera"
		add_child(camera)
	camera.setup(session.field)


## The player party (S1.3c).  It owns its own `TravelGraph` — ~47 ms to build, and
## per-scene state rather than an autoload, because `boot()` can reseed the world
## and the graph must be rebuilt with it.
func _rebuild_party() -> void:
	party_error = ""
	if party == null:
		party = PartyMover.new()
		party.name = "PartyLayer"
		add_child(party)
	if not party.setup(session.field, session.data):
		party_error = "行军图建不起来"
		push_warning(party_error)
		return
	var spawn := _spawn_party()
	party.spawn_at(float(spawn["x"]), float(spawn["z"]), int(spawn["faction"]))


## Where the player party starts.  `WorldData` already decided that in S1.1c
## (`parties[0]`), so the scene does not invent a second answer; the map centre is
## only a fallback for a world without parties.
func _spawn_party() -> Dictionary:
	var list: Array = []
	if session != null and session.data != null:
		list = session.data.parties
	if list.is_empty():
		return {"x": 0.0, "z": 0.0, "faction": 0}
	var p: Dictionary = list[0]
	return {"x": float(p.get("x", 0.0)), "z": float(p.get("z", 0.0)),
			"faction": int(p.get("faction", 0))}


## The party integrates on the fixed logical step (S1.4b); it is the only node that
## moves it.  `seconds` comes from `GameState` so the step length has one definition.
func _on_simulation_tick(_step: int, seconds: float) -> void:
	if party != null:
		party.step(seconds)


## The time bar (S1.4b).  Built once per scene instance — `boot()` may run twice (a
## world rebuild must not stack two HUDs, or F1 would have to hide both).
func _rebuild_hud() -> void:
	if time_bar != null:
		return
	time_bar = TIME_BAR_SCRIPT.new() as CanvasLayer
	time_bar.name = "TimeBar"
	add_child(time_bar)


## Click-to-move.  A rejected pick never cancels the current march: clicking the
## sky or a lake should be a no-op with a reason, not a "stop" the player did not
## ask for.
func _unhandled_input(event: InputEvent) -> void:
	if party == null or camera == null:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var pick := camera.pick_ground(mb.position)
	if not bool(pick.get("ok", false)):
		last_pick_error = "点击没有落在地面上：%s" % String(pick.get("reason", ""))
		return
	last_pick_error = ""
	var point: Vector3 = pick["point"]
	party.order_to(point.x, point.z)


## The generated world's macro indicators (empty before `_ready()` / after a
## failed boot).
func metrics() -> Dictionary:
	if session == null:
		return {}
	return session.metrics()


## The terrain mesh statistics (empty before `_ready()` / after a failed boot).
func terrain_stats() -> Dictionary:
	if terrain == null:
		return {}
	return terrain.stats


## What the camera currently shows (empty before `_ready()` / after a failed boot).
func camera_report() -> Dictionary:
	if camera == null:
		return {}
	return camera.report()


## What the party is doing (empty before `_ready()` / after a failed boot).  The
## case asserts on this instead of reaching into the mover's internals.
func party_report() -> Dictionary:
	if party == null:
		return {}
	var out := party.report()
	out["graph_ok"] = party.graph != null and party.graph.built
	out["error"] = party_error
	out["pick_error"] = last_pick_error
	return out
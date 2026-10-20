extends Node3D

## Root script of `scenes/world/strategic_map.tscn` (S1.2).
##
## S1.2a SCOPE.  This scene owns exactly **one** `WorldSession` and renders
## nothing: the strategic terrain mesh arrives in S1.2b, the camera rig in S1.2c.
## Booting the scene in the first batch keeps one invariant true from the start —
## there is never more than one world instance per scene, and it is always built
## through `WorldSession.boot()`, which reseeds the generator (so re-entering the
## scene cannot inherit a half-drawn `world_gen` stream; see
## `docs/ENGINEERING.md` §9.8.5).
##
## AUTOLOADS BY PATH, NOT BY NAME.  `tools/verify.gd` runs as a `--script` MainLoop
## where autoload identifiers do not compile, and it instantiates this scene to
## prove the wiring.  Looking the nodes up as `/root/Rng` / `/root/GameState` keeps
## this script loadable in both modes.

## Fallback seed, identical to `GameState.DEFAULT_WORLD_SEED` and
## `Rng.DEFAULT_MASTER_SEED`.  Only used when `GameState` is absent (bare
## `--script` runs); the game always reads the live value.
const FALLBACK_SEED := 20250929

## The world owned by this scene.  `null` until `_ready()` runs, and stays `null`
## with `boot_error` set if the build failed — so "not booted yet" and "booted but
## empty" are distinguishable.
var session: WorldSession
## Non-empty only when `session` is `null` because something went wrong.
var boot_error := ""


func _ready() -> void:
	boot()


## Builds (or rebuilds) the world for the current `GameState.world_seed`.
## Safe to call twice: the previous session is dropped, and the new one is built
## from a reseeded generator, so a rebuild is not "the same world, continued".
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


## The world's macro indicators (empty before `_ready()` / after a failed boot).
func metrics() -> Dictionary:
	if session == null:
		return {}
	return session.metrics()

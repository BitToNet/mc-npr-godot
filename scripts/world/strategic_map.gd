extends Node3D

## Root script of `scenes/world/strategic_map.tscn` (S1.2).
##
## SCOPE.  This scene owns exactly **one** `WorldSession` and, since S1.2b, one
## `StrategicTerrain` built from that session.  The camera rig still belongs to
## S1.2c — the scene has no camera of its own yet.
##
## Booting the scene keeps one invariant true from the first batch: there is never
## more than one world instance per scene, and it is always built through
## `WorldSession.boot()`, which reseeds the generator (so re-entering the scene
## cannot inherit a half-drawn `world_gen` stream; see
## `docs/ENGINEERING.md` §9.8.5 / §9.9).
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

## The world owned by this scene.  `null` until `_ready()` runs, and stays `null`
## with `boot_error` set if the build failed — so "not booted yet" and "booted but
## empty" are distinguishable.
var session: WorldSession
## The terrain mesh built from `session`.  `null` when the world failed to build.
var terrain: StrategicTerrain
## Non-empty only when `session` is `null` because something went wrong.
var boot_error := ""


func _ready() -> void:
	boot()


## Builds (or rebuilds) the world for the current `GameState.world_seed`, then
## rebuilds the terrain from it.  Safe to call twice: the previous session is
## dropped, and the new one is built from a reseeded generator, so a rebuild is
## not "the same world, continued".
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


## Applies the generated world to the visible mesh.  Kept separate from `boot()`
## so a future "the world changed but the seed did not" path only has to call
## this half.
func _rebuild_terrain() -> void:
	if terrain == null:
		terrain = StrategicTerrain.new()
		terrain.name = "StrategicTerrain"
		add_child(terrain)
	terrain.build(session.field)


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

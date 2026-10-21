extends Node3D

## Dev-only capture stage for S1.2d — the three tier plates of `B-`, plus the three
## top-down global plates S1.1 owed.
##
## WHY A DEV SCENE INSTEAD OF `--seed=` / `--tier=` IN `capture.gd`: those two are
## *gameplay-shaped* knobs (which world, which zoom).  Product code must not carry
## them just so a tool can take a picture, and `scripts/dev/` is allowed to
## reference product code but never the other way round — so the knobs live here,
## at the same layer as the scene override itself.
##
## This file reads exactly two arguments; everything else (`--shots`, `--warmup=`,
## `--frames=`, `--out=`) still belongs to `capture.gd`:
##   Godot --path . -- --shots --scene=res://scenes/dev/strategic_shots.tscn \
##         --seed=20250929 --tier=global --warmup=60 --frames=15 \
##         --out=res://.shots/s12d/global_20250929
##
## Framing rule: GLOBAL is the whole plate (map centre, locked by the camera), while
## REGION / LOCAL are framed on the settlement nearest the map centre — the centre
## itself is often open water, and a "local" plate of blank sea would prove nothing
## about the terrain or the outline style.

const MAP_SCENE := "res://scenes/world/strategic_map.tscn"

const TIERS := {"global": 0, "region": 1, "local": 2}

## Fallback matches `GameState.DEFAULT_WORLD_SEED`; only used when neither the CLI
## nor `GameState` supplies one.
const FALLBACK_SEED := 20250929

## The map instance this stage owns.  Replaced (not reused) by `build()`.
var map: Node3D
var seed_value := FALLBACK_SEED
var tier_name := "global"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = a.split("=", true, 1)[1].to_int()
		elif a.begins_with("--tier="):
			tier_name = a.split("=", true, 1)[1]
	if not TIERS.has(tier_name):
		push_warning("[shots] 未知 --tier='%s'，回退 global" % tier_name)
		tier_name = "global"
	build(seed_value, tier_name)


## (Re)builds the world for `p_seed` and applies `p_tier`, snapped (no easing), so
## two runs of the same command are the same picture.  Public so a case can prove
## both knobs actually move the world instead of trusting this file's own log line.
func build(p_seed: int, p_tier: String) -> void:
	if map != null:
		remove_child(map)
		map.free()
		map = null
	seed_value = p_seed
	tier_name = p_tier if TIERS.has(p_tier) else "global"
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.set("world_seed", seed_value)
	var ps := load(MAP_SCENE) as PackedScene
	map = ps.instantiate() as Node3D
	map.name = "StrategicMap"
	add_child(map)
	var cam: Node3D = map.get("camera") as Node3D
	if cam == null:
		push_error("[shots] 战略图没有相机，取景失败")
		return
	cam.call("set_tier", int(TIERS[tier_name]))
	if tier_name == "global":
		cam.call("snap_to_target")
	else:
		var spot := _pick_settlement()
		cam.call("focus_on", spot.x, spot.z)
	print("[shots] seed=%d tier=%s focus=%s size=%.1f" % [
			seed_value, tier_name, str(focus_point()), _size()])


## Deterministic framing subject: the **lowland** settlement nearest the map centre.
##
## First attempt framed the settlement nearest the centre of *any* kind.  On seed
## 20250929 the map centre happens to be a high plateau (the nearest village sits at
## 92 m, and most of the interior is the turquoise high band), so the local plate
## came out as white/turquoise planes with no readable shape.  Framing a low
## settlement instead shows what the art direction actually is — apple-green
## lowland, lemon shoal, clear water — while still being a real place from the
## world, not a hand-picked camera pose.
##
## Order: altitude bucket (≤ 40 m first) → height → distance.  Returns the origin
## when there is nothing to frame, which degrades to "map centre" instead of
## failing.
func _pick_settlement() -> Vector3:
	if map == null:
		return Vector3.ZERO
	var session: Variant = map.get("session")
	if session == null:
		return Vector3.ZERO
	var data: Variant = session.get("data")
	if data == null:
		return Vector3.ZERO
	var field: Variant = session.get("field")
	var settlements: Array = data.get("settlements")
	var best := Vector3.ZERO
	var best_high := true
	var best_h := INF
	var best_d := INF
	for s in settlements:
		var p := Vector3(float(s["x"]), 0.0, float(s["z"]))
		var h := float(field.call("height_at", p.x, p.z)) if field != null else 0.0
		var high := h > 40.0
		var d := Vector2(p.x, p.z).length()
		var better := false
		if best_d == INF:
			better = true
		elif high != best_high:
			better = not high
		elif not is_equal_approx(h, best_h):
			better = h < best_h
		else:
			better = d < best_d
		if better:
			best = p
			best_high = high
			best_h = h
			best_d = d
	return best

## The camera's current focus, for the log line and for cases.  Zero when the
## world failed to build (there is nothing to frame).
func focus_point() -> Vector3:
	var cam: Variant = map.get("camera") if map != null else null
	if cam == null:
		return Vector3.ZERO
	var f: Vector3 = cam.get("focus")
	return f


## The camera's current vertical span, metres.
func _size() -> float:
	var cam: Variant = map.get("camera") if map != null else null
	if cam == null:
		return 0.0
	return float(cam.get("size"))

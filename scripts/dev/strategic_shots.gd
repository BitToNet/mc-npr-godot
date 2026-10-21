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
## This file reads four arguments; everything else (`--shots`, `--warmup=`,
## `--frames=`, `--out=`) still belongs to `capture.gd`:
##   Godot --path . -- --shots --scene=res://scenes/dev/strategic_shots.tscn \
##         --seed=20250929 --tier=global --warmup=60 --frames=15 \
##         --out=res://.shots/s12d/global_20250929
##
## `--party=1` drops the S1.3a party marker on the framed settlement (faction taken
## from that settlement, so the plate shows a real in-world colour, not a fixture);
## `--span=<m>` overrides the tier span for a tighter close-up: LOCAL is 170 m, where a 22 m
## marker is only ~116 px tall and its ink is ~2 px, too small to judge the art.
##   Godot --path . -- --shot=party_close --scene=res://scenes/dev/strategic_shots.tscn \
##         --seed=20250929 --tier=local --party=1 --span=55 --warmup=60 --frames=12 \
##         --out=res://.shots/s13a/party_close
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
## --party=1 plants the close-up subject; kept off by default so the five S1.2d
## plates stay bit-identical.
var with_party := false
## The marker this stage owns (only when with_party).
var party_marker: PartyMarker = null
## --span=<m> overrides the tier's vertical span (0 = keep the tier's own size).
## Added for the S1.3a close-up: LOCAL is 170 m, where a 22 m marker is only ~116 px tall.
var span_override := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = a.split("=", true, 1)[1].to_int()
		elif a.begins_with("--tier="):
			tier_name = a.split("=", true, 1)[1]
		elif a.begins_with("--party="):
			with_party = a.split("=", true, 1)[1].to_int() != 0
		elif a.begins_with("--span="):
			span_override = a.split("=", true, 1)[1].to_float()
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
	party_marker = null
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
	var spot := _pick_settlement()
	if tier_name == "global":
		cam.call("snap_to_target")
	else:
		cam.call("focus_on", spot.x, spot.z)
	if span_override > 0.0:
		cam.set("size_target", span_override)
		cam.call("snap_to_target")
	_publish_ink()
	if with_party:
		_place_party(spot)
	print("[shots] seed=%d tier=%s focus=%s size=%.1f party=%s" % [
			seed_value, tier_name, str(focus_point()), _size(), str(_party_point())])


## Plants the S1.3a marker at the framed settlement, facing the map centre (so the
## banner reads across the camera instead of edge-on).  Returns silently when the
## world has no session — the plate is then simply the S1.2d plate again.
func _place_party(spot: Vector3) -> void:
	var session: Variant = map.get("session") if map != null else null
	if session == null:
		push_warning("[shots] --party 需要世界 session，本张图不带棋子")
		return
	var field: Variant = session.get("field")
	var data: Variant = session.get("data")
	var fac := 0
	if data != null:
		for s in Array(data.get("settlements")):
			if absf(float(s["x"]) - spot.x) < 0.01 and absf(float(s["z"]) - spot.z) < 0.01:
				fac = int(s["faction"])
				break
	var marker := PartyMarker.new()
	marker.name = "PartyMarker"
	marker.set_faction(fac)
	marker.setup(field as HeightField)
	marker.place_at(spot.x, spot.z)
	marker.face_towards(-spot)
	map.add_child(marker)
	party_marker = marker
	if OS.get_cmdline_user_args().has("--probe-neg"):
		var b := marker.get_node_or_null("Body") as MeshInstance3D
		var om := (b.material_override as ShaderMaterial).next_pass as ShaderMaterial
		om.set_shader_parameter("width", -6.0)
	print("[shots] party at %s h=%.2f faction=%d" % [
			str(marker.position), marker.ground_at(spot.x, spot.z), fac])



## 反向外壳的线宽以"屏幕像素"为单位，靠 Style.pixel_span（1 px 等于多少世界单位）
## 换算。战略相机不发布这个值（S1.2 的海岸墨线是几何色带，用不到外壳），所以取景台
## 按当前跨度与视口高度自己发一次 —— 否则同一枚棋子在 2600 m 档的线宽只有 0.03 px、
## 在 55 m 档 1.4 px，特写永远看不到描边。
func _publish_ink() -> void:
	var style := get_node_or_null("/root/Style")
	if style == null:
		return
	var view_h := float(get_viewport().get_visible_rect().size.y)
	if view_h <= 0.0:
		return
	style.call("set_pixel_span", _size() / view_h)


## Where the marker stands (zero when the plate has no party).
func _party_point() -> Vector3:
	if party_marker == null:
		return Vector3.ZERO
	return party_marker.position


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

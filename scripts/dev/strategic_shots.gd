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
## This file reads five arguments; everything else (`--shots`, `--warmup=`,
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
## `--route=1` (S1.3b) traces the longest road with the real TravelGraph and paints the
## returned polyline as an ink trail, then frames the camera on that road's midpoint.
## It proves "the path follows the road and crosses no water" visually — the numbers are
## asserted in `tools/verify.gd::s1_3_path`.
##   Godot --path . -- --shot=route_region --scene=res://scenes/dev/strategic_shots.tscn \
##         --seed=20250929 --tier=region --route=1 --warmup=60 --frames=12 \
##         --out=res://.shots/s13b/route_region
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
## --route=1 (S1.3b) traces the longest road with TravelGraph and paints the polyline.
## --march alone also traces it (it needs a road to walk) but paints nothing — that is
## how the S1.3d clean close-up keeps the ink dots out of the hero shot.
var with_route := false
## The polyline --route=1 / --march produced (empty otherwise).
var route_points := PackedVector2Array()
## What the trace measured, for the log line.
var route_info := {}
## The graph that produced `route_points` (kept so the plate can also paint its road cells).
var route_graph: TravelGraph = null
## `--march=<秒>` (S1.3c) lets the real party walk the longest road for that many seconds
## before the shutter, so "移动积分" also has a plate, not just test numbers.  It traces the
## road itself (`--route=1` not needed); with `--route=1` the polyline is painted too, without
## it the frame stays clean —— that is how the S1.3d close-up is shot.
var march_seconds := 0.0
## S1.4b — keep the time bar on the plate (`--hud=1`) or hide it (default).
var show_hud := false

const StyleDef := preload("res://scripts/core/style.gd")


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
		elif a.begins_with("--route="):
			with_route = a.split("=", true, 1)[1].to_int() != 0
		elif a.begins_with("--march="):
			march_seconds = a.split("=", true, 1)[1].to_float()
		elif a.begins_with("--hud="):
			show_hud = a.split("=", true, 1)[1].to_int() != 0
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
	route_points = PackedVector2Array()
	route_info = {}
	route_graph = null
	seed_value = p_seed
	tier_name = p_tier if TIERS.has(p_tier) else "global"
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.set("world_seed", seed_value)
	var ps := load(MAP_SCENE) as PackedScene
	map = ps.instantiate() as Node3D
	map.name = "StrategicMap"
	add_child(map)
	# S1.4b — the album plates are 3D evidence (S1.3d): the time bar is a HUD, and
	# hiding it is what keeps those four sha256 values byte-identical after the bar
	# landed.  A batch that *wants* the bar (S1.4d's hour plates) passes `--hud=1`.
	var bar: Node = map.get("time_bar")
	if bar is CanvasLayer and not show_hud:
		(bar as CanvasLayer).visible = false
	var cam: Node3D = map.get("camera") as Node3D
	if cam == null:
		push_error("[shots] 战略图没有相机，取景失败")
		return
	cam.call("set_tier", int(TIERS[tier_name]))
	var site := _pick_settlement()
	var spot := site
	if with_route or march_seconds > 0.0:
		var route := _trace_route()
		if route.has("mid"):
			var mid: Vector2 = route["mid"]
			spot = Vector3(mid.x, 0.0, mid.y)
	if tier_name == "global":
		cam.call("snap_to_target")
	else:
		cam.call("focus_on", spot.x, spot.z)
	if span_override > 0.0:
		cam.set("size_target", span_override)
		cam.call("snap_to_target")
	_publish_ink()
	if with_party:
		_place_party(site)
	if with_route:
		_draw_route()
	if march_seconds > 0.0:
		_march(march_seconds)
	print("[shots] seed=%d tier=%s focus=%s size=%.1f party=%s route=%s" % [
			seed_value, tier_name, str(focus_point()), _size(), str(_party_point()),
			str(route_info.get("summary", "off"))])


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



## Traces the **longest** road with the real `TravelGraph` (S1.3b), so the plate shows
## the shipped pathfinder's output rather than a hand-drawn line.  Ties break on the
## road order (roads are already sorted by `a` then `b`), so one seed always frames the
## same road.  Returns `{}` (and warns) when there is no session / no road / no path.
func _trace_route() -> Dictionary:
	var session: Variant = map.get("session") if map != null else null
	if session == null:
		push_warning("[shots] --route 需要世界 session，本张图不带路径")
		return {}
	var field: Variant = session.get("field")
	var data: Variant = session.get("data")
	if field == null or data == null:
		push_warning("[shots] --route 需要 field 与 data")
		return {}
	var graph := TravelGraph.new()
	route_graph = graph
	if not graph.build(field as HeightField, data as WorldData, TravelGraph.Params.load_from()):
		push_warning("[shots] 行军图构建失败：%s" % ", ".join(graph.warnings))
		return {}
	var roads: Array = data.get("roads")
	if roads.is_empty():
		push_warning("[shots] 这个世界没有道路")
		return {}
	var by_id := {}
	for s in Array(data.get("settlements")):
		by_id[String(s["id"])] = s
	var best: Dictionary = roads[0]
	for r in roads:
		if float(r["length"]) > float(best["length"]):
			best = r
	var a: Dictionary = by_id.get(String(best["a"]), {})
	var b: Dictionary = by_id.get(String(best["b"]), {})
	if a.is_empty() or b.is_empty():
		return {}
	var from := Vector2(float(a["x"]), float(a["z"]))
	var to := Vector2(float(b["x"]), float(b["z"]))
	var path := graph.find_path(from, to)
	if not bool(path["ok"]):
		push_warning("[shots] 寻路失败：%s" % String(path["reason"]))
		return {}
	route_points = path["points"]
	route_info = {
		"points": route_points.size(),
		"cost": float(path["cost"]),
		"road_m": float(path["road_m"]),
		"offroad_m": float(path["offroad_m"]),
		"expanded": int(path["expanded"]),
		"mid": (from + to) * 0.5,
		"summary": "%s→%s %d 点 / 路 %.0f m / 野 %.0f m / 成本 %.0f" % [
				String(best["a"]), String(best["b"]), route_points.size(),
				float(path["road_m"]), float(path["offroad_m"]), float(path["cost"])],
	}
	return route_info


## Paints the traced polyline as an ink trail (one dot per 12 m) so a REGION plate reads
## as "the road, followed" instead of a few isolated dots.  Dots carry **no ink hull**:
## they are 3 m props, and the inverted hull on a combined mesh shatters into slivers
## (`docs/ENGINEERING.md` §5 trap 35).
## `--march=<秒>`：让场景里**真**的队伍沿 `--route=1` 那条路走 `秒` 秒（固定 1/60 步长），
## 然后把镜头对到它身上并**冻结**它 —— 场景根的 `_process` 会继续推着它走，不冻结的话
## 同一条命令两次拍出来的位置就不一样，图不能当证据。
func _march(seconds: float) -> void:
	var mover: PartyMover = null
	if map != null:
		mover = map.get("party") as PartyMover
	if mover == null:
		push_warning("[shots] --march 需要场景里已经建好队伍")
		return
	if route_points.size() < 2:
		push_warning("[shots] --march 需要 --route=1 给出的折线")
		return
	var from: Vector2 = route_points[0]
	var to: Vector2 = route_points[route_points.size() - 1]
	mover.spawn_at(from.x, from.y, 0)
	var order := mover.order_to(to.x, to.y)
	if not bool(order.get("ok", false)):
		push_warning("[shots] --march 下令失败：%s" % String(order.get("reason", "")))
		return
	var dt := 1.0 / 60.0
	var frames := int(round(seconds / dt))
	for i in frames:
		mover.step(dt)
	var report := mover.report()
	mover.stop()
	var cam: Node3D = map.get("camera") as Node3D
	if cam != null and tier_name != "global":
		cam.call("focus_on", float(report["x"]), float(report["z"]))
		if span_override > 0.0:
			cam.set("size_target", span_override)
		cam.call("snap_to_target")
	print("[shots] march %.1f s / %d 帧 → %s 位置=(%.1f, %.1f) 剩余 %.1f m（已冻结）" % [
			seconds, frames, String(report["state"]), float(report["x"]), float(report["z"]),
			float(report["remaining"])])


func _draw_route() -> void:
	if route_points.size() < 2 or map == null:
		return
	var session: Variant = map.get("session")
	var field: Variant = session.get("field") if session != null else null
	var data: Variant = session.get("data") if session != null else null
	# 先铺**图里的道路格**（暗沙色、宽而低），再把路径压在上面（墨色、窄而高）。
	# 只画路径的话，图上没有任何"路"可对照，"它确实沿路走"就退化成一句自述；
	# 画"设计上的直线"又会对不上 —— 路径点在格心，直线点在线上，两者天然差半格。
	var road_pts := _road_cell_points()
	if not road_pts.is_empty():
		_add_trail(road_pts, "RoadCells", 3.4, 1.2, StyleDef.PALETTE["sand_deep"], 0.0)
	_add_trail(_trail_points(route_points, 12.0), "RouteTrail", 4.2, 3.0,
			StyleDef.PALETTE["ink"], 12.0)


## 图里所有"道路格"的格心。路径点也是格心，所以两层能严丝合缝地叠在一起。
func _road_cell_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if route_graph == null or not route_graph.built:
		return out
	for iz in route_graph.n:
		for ix in route_graph.n:
			if route_graph.road[route_graph.index_of(ix, iz)] != 0:
				out.append(route_graph.cell_center(ix, iz))
	return out


## 一条点带 = 一个 `MultiMeshInstance3D`（1 个 draw call）。点是无描边的扁球：
## 3–4 m 的小道具挂反向外壳会炸成碎屑（`docs/ENGINEERING.md` §5 陷阱 35）。
func _add_trail(pts: PackedVector2Array, node_name: String, radius: float,
		lift: float, tint: Color, _spacing: float) -> void:
	if pts.is_empty():
		return
	var session: Variant = map.get("session")
	var field: Variant = session.get("field") if session != null else null
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = MeshUtil.blob(radius, 3, 6)
	mm.instance_count = pts.size()
	for i in pts.size():
		var p := pts[i]
		var h := float(field.call("height_at", p.x, p.y)) if field != null else 0.0
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, h + lift, p.y)))
	node.multimesh = mm
	var style := get_node_or_null("/root/Style")
	if style != null:
		node.material_override = style.call("toon", {
			"tint": tint, "outline": false,
			"rim": 0.0, "spec": 0.0, "shade_min": 0.92,
		})
	map.add_child(node)
	print("[shots] %s %d dots（%.0f m 一点）" % [node_name, pts.size(), _spacing])


## 折线按固定弧长重采样（含首末点）。12 m 在 REGION 档约 27 px 间距，读起来是虚线。
func _trail_points(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(pts[0])
	var since := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i] - pts[i - 1]
		var len := seg.length()
		if len <= 0.0001:
			continue
		var dir := seg / len
		var left := step - since
		while left <= len:
			out.append(pts[i - 1] + dir * left)
			left += step
		since = len - (left - step)
	out.append(pts[pts.size() - 1])
	return out
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

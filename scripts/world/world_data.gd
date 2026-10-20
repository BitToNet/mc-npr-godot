class_name WorldData
extends RefCounted
## WorldData — settlements, roads, factions and AI parties on top of the
## strategic height field (S1.1c).
##
## Regions (S1.1b) say *how the land is divided*; this file says *who lives on
## it*: where the villages / towns / fortresses stand, which roads connect them,
## which faction owns what, and where the 24 AI parties start.  Everything here
## is derived from the same three inputs (`world_seed`, the validated parameter
## table, the `HeightField`) plus exactly one explicit `RandomNumberGenerator`,
## so two builds with the same seed produce the same world — which is what the
## `A-` serialisation case in S1.1d will start from.
##
## WHAT IS NOT IN HERE.  Serialising the world to bytes (`Canon` + `WorldData`
## snapshot) and the three macro indicators are S1.1d.  Roads are a **graph**
## (`{a, b, length}`), not a mesh: laying them on the terrain belongs to S1.2,
## where the strategic renderer exists.  Rejecting water / steep ground is the
## placer's job; drawing the ribbon is not.
##
## DETERMINISM RULE.  No `randf()`, no `randi()`, no time, no autoload reads —
## the only source of jitter is the `RandomNumberGenerator` handed to `_init()`
## (game side: `Rng.stream("world_gen")`; `--script` side: the same substream
## reached through the tree root).  Iteration order is always array order, so a
## replay of the same seed reproduces every coordinate bit for bit.
##
## ANCHORS WIN.  `data/world/anchors.json` pins hand-authored landmarks.  Their
## coordinates are adopted verbatim (that is why the `A-` case can assert 100%
## agreement), and generated settlements must keep the minimum spacing from them
## like from any other settlement.  An anchor that is malformed, on water, on too
## steep a slope, or over its kind's quota is **skipped with a warning** — never
## silently moved, because moving it would defeat the point of pinning it.

const PATH := "res://data/world/anchors.json"
const SCHEMA := 1

const KIND_VILLAGE := "village"
const KIND_TOWN := "town"
const KIND_FORTRESS := "fortress"
## Order matters: villages are placed first, so the 12 cheap points fill the map
## before the 4 towns and 4 fortresses claim the good remaining spots.
const KINDS := [KIND_VILLAGE, KIND_TOWN, KIND_FORTRESS]
const KIND_LABELS := {
	KIND_VILLAGE: "村庄",
	KIND_TOWN: "城镇",
	KIND_FORTRESS: "要塞",
}
## Parameter-table keys per kind (`villages` / `towns` / `fortresses` — plural in
## the table, singular in the code).
const KIND_PARAM := {
	KIND_VILLAGE: "villages",
	KIND_TOWN: "towns",
	KIND_FORTRESS: "fortresses",
}

# --- shape constants (deliberately not gameplay numbers) --------------------
## Nearest-neighbour skeleton width: every settlement links to its 2 closest
## neighbours, then isolated components are stitched together.  Road *count* is
## therefore data-shaped, while "the graph must be connected" is the invariant.
const ROAD_K := 2
## Attempts per generated settlement.  Bounded on purpose: an unsatisfiable
## spacing must degrade with a warning, never spin forever.
const MAX_PLACE_TRIES := 200
## Attempts to jitter an AI party off its home settlement onto walkable ground.
const MAX_PARTY_TRIES := 30
## Keep settlements this far from the map border, in metres.
const MAP_MARGIN := 80.0
## Party spawn ring around its home settlement, in metres.
const PARTY_RING_MIN := 40.0
const PARTY_RING_MAX := 200.0
## Faction colour slots; the renderer (S1.2) maps these onto `Style.PALETTE`.
const FACTION_NAMES := ["青岚盟", "赤砂部", "白霜庭"]

var world_seed: int
var params: Dictionary
var field: HeightField
var regions: WorldRegions
var stream: RandomNumberGenerator
var anchors: Array

var settlements: Array[Dictionary] = []
var roads: Array[Dictionary] = []
var factions: Array[Dictionary] = []
var parties: Array[Dictionary] = []
var warnings := PackedStringArray()


func _init(p_seed_value: int, p_params: Dictionary, p_field: HeightField,
		p_regions: WorldRegions, p_stream: RandomNumberGenerator,
		p_anchors: Array = []) -> void:
	world_seed = p_seed_value
	params = p_params
	field = p_field
	regions = p_regions
	stream = p_stream
	anchors = p_anchors


# --- read-only views --------------------------------------------------------

func spacing() -> float:
	return float(params.get("settlement_min_spacing", 120.0))


func slope_limit() -> float:
	return float(params.get("settlement_slope_limit", 0.35))


func half_size() -> float:
	return float(params.get("map_size", 2400)) * 0.5


func count_by_kind() -> Dictionary:
	var counts := {KIND_VILLAGE: 0, KIND_TOWN: 0, KIND_FORTRESS: 0}
	for s in settlements:
		var kind := String(s["kind"])
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


func road_length_total() -> float:
	var total := 0.0
	for r in roads:
		total += float(r["length"])
	return total


func settlement_by_id(p_id: String) -> Dictionary:
	for s in settlements:
		if String(s["id"]) == p_id:
			return s
	return {}


func settlements_of_kind(p_kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in settlements:
		if String(s["kind"]) == p_kind:
			out.append(s)
	return out


## Stable textual fingerprint of the generated world, used by the determinism
## assertions.  Not a serialisation format — S1.1d owns that (`Canon`).
func fingerprint() -> String:
	var parts := PackedStringArray()
	parts.append("seed=%d" % world_seed)
	for s in settlements:
		parts.append("s:%s|%s|%.3f|%.3f|%d|%s" % [String(s["id"]), String(s["kind"]),
				float(s["x"]), float(s["z"]), int(s["faction"]), String(s["name"])])
	for r in roads:
		parts.append("r:%s|%s|%.3f" % [String(r["a"]), String(r["b"]), float(r["length"])])
	for p in parties:
		parts.append("p:%s|%d|%.3f|%.3f" % [String(p["id"]), int(p["faction"]),
				float(p["x"]), float(p["z"])])
	return "\n".join(parts)


# --- generation -------------------------------------------------------------

## Build every layer.  Returns
## `{ok, settlements, roads, factions, parties, warnings, counts, road_length_total,
## spacing, slope_limit, reason}`; `ok` is false only when nothing could be placed.
func build() -> Dictionary:
	settlements.clear()
	roads.clear()
	factions.clear()
	parties.clear()
	warnings.clear()

	_place_anchors()
	_place_generated()
	if settlements.is_empty():
		return _summary(false, "一个聚落都放不下（地图或间距参数不可行）")

	_assign_factions()
	_build_roads()
	_spawn_parties()
	return _summary(true, "")


func _place_anchors() -> void:
	var quotas := _kind_quotas()
	var seen := {}
	for entry in anchors:
		if typeof(entry) != TYPE_DICTIONARY:
			warnings.append("锚点条目不是对象（实际 `%s`）：跳过" % type_string(typeof(entry)))
			continue
		var anchor: Dictionary = entry
		var id := String(anchor.get("id", ""))
		var kind := String(anchor.get("kind", ""))
		var name := String(anchor.get("name", id))
		if id.is_empty():
			warnings.append("锚点缺少 `id`：跳过（无法作为稳定标识）")
			continue
		if seen.has(id):
			warnings.append("锚点 `%s` 重复：跳过后者" % id)
			continue
		if not KINDS.has(kind):
			warnings.append("锚点 `%s` 的 kind = `%s` 不在 %s 内：跳过" % [id, kind, str(KINDS)])
			continue
		if not (anchor.has("x") and anchor.has("z")):
			warnings.append("锚点 `%s` 缺少坐标：跳过" % id)
			continue
		var x := float(anchor.get("x", 0.0))
		var z := float(anchor.get("z", 0.0))
		if int(quotas.get(kind, 0)) <= 0:
			warnings.append("锚点 `%s` 超出 `%s` 的配额：跳过（总数以参数表为准）" % [id, kind])
			continue
		var why := _spot_problem(x, z)
		if not why.is_empty():
			warnings.append("锚点 `%s` 位置不合法（%s）：跳过" % [id, why])
			continue
		if not _far_enough(x, z):
			warnings.append("锚点 `%s` 与已放置聚落间距不足 %.0f m：跳过" % [id, spacing()])
			continue
		quotas[kind] = int(quotas[kind]) - 1
		seen[id] = true
		settlements.append({
			"id": id,
			"kind": kind,
			"name": name,
			"x": x,
			"z": z,
			"region": regions.region_at(x, z),
			"faction": -1,
			"anchor": true,
		})


func _place_generated() -> void:
	var quotas := _kind_quotas()
	for s in settlements:
		var kind := String(s["kind"])
		quotas[kind] = int(quotas.get(kind, 0)) - 1
	for kind in KINDS:
		var want := int(quotas.get(kind, 0))
		for i in range(want):
			var label := String(KIND_LABELS[kind])
			if _try_place(kind, "%s %d" % [label, i + 1]):
				continue
			warnings.append("`%s` 第 %d 个在 %d 次内找不到落点（间距 %.0f m / 坡度上限 %.2f）：按实际数量降级"
					% [kind, i + 1, MAX_PLACE_TRIES, spacing(), slope_limit()])


func _try_place(kind: String, name: String) -> bool:
	var limit := half_size() - MAP_MARGIN
	for _attempt in range(MAX_PLACE_TRIES):
		var x := stream.randf_range(-limit, limit)
		var z := stream.randf_range(-limit, limit)
		if not _spot_problem(x, z).is_empty():
			continue
		if not _far_enough(x, z):
			continue
		settlements.append({
			"id": "%s_%d" % [kind, _next_serial(kind)],
			"kind": kind,
			"name": name,
			"x": x,
			"z": z,
			"region": regions.region_at(x, z),
			"faction": -1,
			"anchor": false,
		})
		return true
	return false


func _kind_quotas() -> Dictionary:
	var quotas := {}
	for kind in KINDS:
		quotas[kind] = int(params.get(String(KIND_PARAM[kind]), 0))
	return quotas


func _next_serial(kind: String) -> int:
	var n := 0
	for s in settlements:
		if String(s["kind"]) == kind and not bool(s["anchor"]):
			n += 1
	return n


## Empty string when `(x, z)` is a legal settlement spot, otherwise the reason.
func _spot_problem(x: float, z: float) -> String:
	var limit := half_size() - MAP_MARGIN
	if absf(x) > limit or absf(z) > limit:
		return "超出地图可用区（|x|,|z| ≤ %.0f m）" % limit
	if field.is_water(x, z):
		return "落在水面（高度 %.2f m ≤ 海平面）" % field.height_at(x, z)
	var slope := field.slope_at(x, z)
	if slope > slope_limit():
		return "坡度 %.3f > 上限 %.2f" % [slope, slope_limit()]
	return ""


func _far_enough(x: float, z: float) -> bool:
	var min_sq := spacing() * spacing()
	var here := Vector2(x, z)
	for s in settlements:
		if here.distance_squared_to(Vector2(float(s["x"]), float(s["z"]))) < min_sq:
			return false
	return true


# --- factions ---------------------------------------------------------------

func _assign_factions() -> void:
	var want := maxi(1, int(params.get("factions", 3)))
	var seats: Array[Dictionary] = settlements_of_kind(KIND_TOWN)
	if seats.size() < want:
		# Not enough towns: fall back to whatever is available so the world still
		# has `want` factions instead of silently shipping fewer.
		seats.clear()
		for s in settlements:
			seats.append(s)
	if seats.is_empty():
		return
	if seats.size() < want:
		warnings.append("城镇只有 %d 座，少于势力数 %d：首都取现有聚落" % [seats.size(), want])
		want = seats.size()

	# Farthest-point sampling from the map centre: deterministic, spread-out
	# capitals, no randomness (a seed change already moves the towns themselves).
	var picked: Array[Dictionary] = []
	var picked_ids := {}
	var first: Dictionary = seats[0]
	var best_d := -1.0
	for s in seats:
		var d := Vector2(float(s["x"]), float(s["z"])).length_squared()
		if d > best_d:
			best_d = d
			first = s
	picked.append(first)
	picked_ids[String(first["id"])] = true
	while picked.size() < want:
		var best: Dictionary = {}
		var best_gap := -1.0
		for s in seats:
			if picked_ids.has(String(s["id"])):
				continue
			var gap := _distance_to_nearest(s, picked)
			if gap > best_gap:
				best_gap = gap
				best = s
		if best.is_empty():
			break
		picked.append(best)
		picked_ids[String(best["id"])] = true

	for i in range(picked.size()):
		factions.append({
			"id": "faction_%d" % i,
			"name": String(FACTION_NAMES[i % FACTION_NAMES.size()]),
			"color_index": i,
			"capital": String(picked[i]["id"]),
		})
	for s in settlements:
		var nearest := 0
		var nearest_d := -1.0
		for i in range(picked.size()):
			var d := Vector2(float(s["x"]) - float(picked[i]["x"]),
					float(s["z"]) - float(picked[i]["z"])).length_squared()
			if nearest_d < 0.0 or d < nearest_d:
				nearest_d = d
				nearest = i
		s["faction"] = nearest


func _distance_to_nearest(p_point: Dictionary, p_others: Array[Dictionary]) -> float:
	var best := INF
	for o in p_others:
		var d := Vector2(float(p_point["x"]) - float(o["x"]),
				float(p_point["z"]) - float(o["z"])).length()
		best = minf(best, d)
	return best


# --- roads ------------------------------------------------------------------

## Nearest-neighbour skeleton + stitch until one component (ROADMAP §6 S1.1:
## 最近邻骨架 + 对孤立分量补边直到连通).  Edges carry ids and lengths only —
## the ribbon on the terrain is S1.2's problem.
func _build_roads() -> void:
	var n := settlements.size()
	if n < 2:
		return
	var pairs := {}
	for i in range(n):
		for j in _nearest_indices(i, ROAD_K):
			var lo := mini(i, j)
			var hi := maxi(i, j)
			pairs[Vector2i(lo, hi)] = true

	var parent: Array = []
	for i in range(n):
		parent.append(i)
	for key in pairs.keys():
		var k: Vector2i = key
		_union(parent, k.x, k.y)

	while true:
		var root := _root(parent, 0)
		var all_same := true
		for i in range(n):
			if _root(parent, i) != root:
				all_same = false
				break
		if all_same:
			break
		# Stitch the two closest yet-unconnected settlements, then re-check.
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for i in range(n):
			for j in range(i + 1, n):
				if _root(parent, i) == _root(parent, j):
					continue
				var d := _distance_between(i, j)
				if d < best_d:
					best_d = d
					best_a = i
					best_b = j
		if best_a < 0:
			break
		pairs[Vector2i(best_a, best_b)] = true
		_union(parent, best_a, best_b)

	var keys: Array = pairs.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	for key in keys:
		var k: Vector2i = key
		roads.append({
			"a": String(settlements[k.x]["id"]),
			"b": String(settlements[k.y]["id"]),
			"length": _distance_between(k.x, k.y),
		})


func _nearest_indices(p_index: int, p_count: int) -> Array[int]:
	var order: Array[int] = []
	for j in range(settlements.size()):
		if j != p_index:
			order.append(j)
	var here := Vector2(float(settlements[p_index]["x"]), float(settlements[p_index]["z"]))
	order.sort_custom(func(a: int, b: int) -> bool:
		var da := here.distance_squared_to(Vector2(float(settlements[a]["x"]), float(settlements[a]["z"])))
		var db := here.distance_squared_to(Vector2(float(settlements[b]["x"]), float(settlements[b]["z"])))
		if not is_equal_approx(da, db):
			return da < db
		return a < b)
	var out: Array[int] = []
	for i in range(mini(p_count, order.size())):
		out.append(order[i])
	return out


func _distance_between(p_a: int, p_b: int) -> float:
	return Vector2(float(settlements[p_a]["x"]), float(settlements[p_a]["z"])) \
			.distance_to(Vector2(float(settlements[p_b]["x"]), float(settlements[p_b]["z"])))


func _root(parent: Array, p_index: int) -> int:
	var i := p_index
	while int(parent[i]) != i:
		parent[i] = parent[int(parent[i])]
		i = int(parent[i])
	return i


func _union(parent: Array, p_a: int, p_b: int) -> void:
	var ra := _root(parent, p_a)
	var rb := _root(parent, p_b)
	if ra != rb:
		parent[rb] = ra


# --- AI parties -------------------------------------------------------------

func _spawn_parties() -> void:
	var want := int(params.get("ai_parties", 0))
	if factions.is_empty() or want <= 0:
		return
	var fallbacks := 0
	for i in range(want):
		var fid := i % factions.size()
		var homes: Array[Dictionary] = _settlements_of_faction(fid)
		if homes.is_empty():
			continue
		var home: Dictionary = homes[stream.randi_range(0, homes.size() - 1)]
		var spot := _party_spot(home)
		if spot.is_empty():
			spot = {"x": float(home["x"]), "z": float(home["z"])}
			fallbacks += 1
		parties.append({
			"id": "party_%02d" % i,
			"faction": fid,
			"home": String(home["id"]),
			"x": float(spot["x"]),
			"z": float(spot["z"]),
		})
	if fallbacks > 0:
		warnings.append("%d 支队伍在 %d 次内找不到可站立点：退回其所属聚落坐标"
				% [fallbacks, MAX_PARTY_TRIES])


func _party_spot(p_home: Dictionary) -> Dictionary:
	for _attempt in range(MAX_PARTY_TRIES):
		var angle := stream.randf_range(0.0, TAU)
		var radius := stream.randf_range(PARTY_RING_MIN, PARTY_RING_MAX)
		var x := float(p_home["x"]) + cos(angle) * radius
		var z := float(p_home["z"]) + sin(angle) * radius
		if not _spot_problem(x, z).is_empty():
			continue
		return {"x": x, "z": z}
	return {}


func _settlements_of_faction(p_faction: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in settlements:
		if int(s["faction"]) == p_faction:
			out.append(s)
	return out


# --- summary ----------------------------------------------------------------

func _summary(p_ok: bool, p_reason: String) -> Dictionary:
	return {
		"ok": p_ok,
		"reason": p_reason,
		"settlements": settlements,
		"roads": roads,
		"factions": factions,
		"parties": parties,
		"warnings": warnings,
		"counts": count_by_kind(),
		"road_length_total": road_length_total(),
		"spacing": spacing(),
		"slope_limit": slope_limit(),
	}


# --- anchor table -----------------------------------------------------------

## Read + validate `data/world/anchors.json`.
## `{ok, anchors, warnings, reason, path}`.  `ok` is false only when the table as
## a whole is unusable (missing / bad JSON / wrong schema); a bad *entry* is
## skipped with a warning so one typo cannot take the whole world down.
static func load_anchors(path: String = PATH) -> Dictionary:
	var out := {"ok": false, "anchors": [], "warnings": PackedStringArray(),
			"reason": "", "path": path}
	if not FileAccess.file_exists(path):
		out["reason"] = "锚点表不存在：%s" % path
		return out
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		out["reason"] = "锚点表为空或不可读：%s" % path
		return out
	var parsed := Canon.from_text(text)
	if not bool(parsed["ok"]):
		out["reason"] = "锚点表不是合法 JSON：%s" % String(parsed["reason"])
		return out
	var table: Variant = parsed["value"]
	if typeof(table) != TYPE_DICTIONARY:
		out["reason"] = "锚点表根必须是对象（实际 `%s`）" % type_string(typeof(table))
		return out
	var dict: Dictionary = table
	var warnings := PackedStringArray()
	if not dict.has("schema"):
		warnings.append("锚点表缺少 `schema`：按当前版本 %d 读取" % SCHEMA)
	elif not Canon.is_integral(dict["schema"]):
		warnings.append("锚点表的 `schema` 不是整数：按当前版本 %d 读取" % SCHEMA)
	elif int(dict["schema"]) > SCHEMA:
		out["reason"] = "锚点表 schema = %d 高于本构建支持的 %d" % [int(dict["schema"]), SCHEMA]
		out["warnings"] = warnings
		return out
	if not dict.has("anchors"):
		out["reason"] = "锚点表缺少 `anchors` 数组"
		out["warnings"] = warnings
		return out
	if typeof(dict["anchors"]) != TYPE_ARRAY:
		out["reason"] = "锚点表的 `anchors` 必须是数组（实际 `%s`）" % type_string(typeof(dict["anchors"]))
		out["warnings"] = warnings
		return out
	var entries: Array = dict["anchors"]
	var anchors: Array = []
	var seen := {}
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			warnings.append("锚点条目不是对象（实际 `%s`）：跳过" % type_string(typeof(entry)))
			continue
		var anchor: Dictionary = entry
		var id := String(anchor.get("id", ""))
		var kind := String(anchor.get("kind", ""))
		if id.is_empty():
			warnings.append("锚点缺少 `id`：跳过")
			continue
		if seen.has(id):
			warnings.append("锚点 `%s` 重复：跳过后者" % id)
			continue
		if not KINDS.has(kind):
			warnings.append("锚点 `%s` 的 kind = `%s` 不在 %s 内：跳过" % [id, kind, str(KINDS)])
			continue
		if not (anchor.has("x") and anchor.has("z")):
			warnings.append("锚点 `%s` 缺少坐标：跳过" % id)
			continue
		var x := float(anchor["x"])
		var z := float(anchor["z"])
		if not (is_finite(x) and is_finite(z)):
			warnings.append("锚点 `%s` 坐标不是有限数：跳过" % id)
			continue
		seen[id] = true
		anchors.append({
			"id": id,
			"kind": kind,
			"name": String(anchor.get("name", id)),
			"x": x,
			"z": z,
		})
	out["ok"] = true
	out["anchors"] = anchors
	out["warnings"] = warnings
	return out

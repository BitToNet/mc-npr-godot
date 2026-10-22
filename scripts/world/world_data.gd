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
## SERIALISATION.  `to_dict()` / `to_text()` (S1.1d) emit the whole snapshot
## through `Canon`, which is what makes "same seed, same bytes" checkable.  Roads
## stay a **graph** (`{a, b, length}`), not a mesh: laying them on the terrain
## belongs to S1.2, where the strategic renderer exists.  Rejecting water /
## steep ground is the placer's job; drawing the ribbon is not.
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
## 显示名一律走 key（S1.5a）：明文只允许出现在 `data/i18n/strings.csv`。
## 这三条是"生成聚落"的标签，`name_number` 拼在后面（"村庄 3"）。
const KIND_KEYS := {
	KIND_VILLAGE: "SETTLEMENT_KIND_VILLAGE",
	KIND_TOWN: "SETTLEMENT_KIND_TOWN",
	KIND_FORTRESS: "SETTLEMENT_KIND_FORTRESS",
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
const FACTION_KEYS := ["FACTION_QINGLAN", "FACTION_CHISHA", "FACTION_BAISHUANG"]

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
		parts.append("s:%s|%s|%.3f|%.3f|%d|%s|%d" % [String(s["id"]), String(s["kind"]),
				float(s["x"]), float(s["z"]), int(s["faction"]), String(s["name_key"]),
				int(s["name_number"])])
	for r in roads:
		parts.append("r:%s|%s|%.3f" % [String(r["a"]), String(r["b"]), float(r["length"])])
	for p in parties:
		parts.append("p:%s|%d|%.3f|%.3f" % [String(p["id"]), int(p["faction"]),
				float(p["x"]), float(p["z"])])
	return "\n".join(parts)


## 显示名（S1.5a）：数据层只存 key，把 key 变成字是 UI 的事，但这里是唯一知道
## "聚落名 = key + 编号"这条契约的地方，所以在数据层给出一个显式入口。
func settlement_label(s: Dictionary) -> String:
	return L10n.text(String(s["name_key"]), int(s.get("name_number", 0)))


func faction_label(f: Dictionary) -> String:
	return L10n.text(String(f["name_key"]))


# --- serialisation + macro indicators (S1.1d) -------------------------------

## The indicators the `A-` variety case compares.  They must *move* when the seed
## moves, otherwise "another seed gives another world" is a claim with nothing
## behind it.
##
## NOT `settlement_count`.  With the default table the quotas are fixed
## (12 + 4 + 4), so that count is 20 for every seed that does not degrade — an
## indicator that never moves proves nothing.  `settlements_by_region` is the
## distribution that actually answers to the seed, and it is what the variety
## case compares instead (see `docs/ENGINEERING.md` §9.8).
const METRIC_VARIETY := ["coastline_length", "region_areas", "road_length",
		"settlements_by_region"]

## Macro indicators of the generated world.
##
## `coastline_length` is measured on the **region grid** (32 m cells: the sum of
## every interior edge between a land cell and a water cell) rather than by
## sampling `height_at`.  Why: it is then a property of the same partition the
## rest of the game reads, it costs one pass over an array we already have, and
## it cannot drift when a sampler changes.  Edges on the map border are **not**
## counted — they are not coast.
##
## `region_areas` and `settlements_by_region` are in region-id order, so they are
## directly comparable between two builds (same id = same slot in the vector).
## A missing / empty region layer degrades to zeroes instead of failing: the
## indicator is diagnostic, never load-bearing.
func metrics() -> Dictionary:
	var land_ratio := 0.0
	var coastline := 0.0
	var region_count := 0
	var areas: Array = []
	var by_region: Array = []
	if regions != null and regions.grid_w > 0 and regions.grid_h > 0:
		var w := regions.grid_w
		var h := regions.grid_h
		var total := w * h
		var land := 0
		var coast_edges := 0
		for j in range(h):
			for i in range(w):
				var idx := j * w + i
				var here := int(regions.owner[idx])
				if here >= 0:
					land += 1
				if i + 1 < w:
					var right := int(regions.owner[idx + 1])
					if (here >= 0) != (right >= 0):
						coast_edges += 1
				if j + 1 < h:
					var down := int(regions.owner[idx + w])
					if (here >= 0) != (down >= 0):
						coast_edges += 1
		land_ratio = float(land) / float(total)
		coastline = float(coast_edges) * regions.cell
		region_count = regions.regions.size()
		for r in regions.regions:
			areas.append(float(r["area"]))
			by_region.append(0)
	for s in settlements:
		var rid := int(s.get("region", -1))
		if rid >= 0 and rid < by_region.size():
			by_region[rid] = int(by_region[rid]) + 1
	return {
		"land_ratio": land_ratio,
		"coastline_length": coastline,
		"region_count": region_count,
		"region_areas": areas,
		"settlements_by_region": by_region,
		"settlement_count": settlements.size(),
		"road_count": roads.size(),
		"road_length": road_length_total(),
		"party_count": parties.size(),
	}


## Canon-shaped snapshot of the world: everything the world **is**, and nothing
## the runtime added (no warnings, no paths, no timings), so two builds of the
## same seed serialise to the same bytes.
##
## Every array is sorted by a stable textual key before it is emitted.  Generation
## order already happens to be stable, but serialisation must not *rely* on that:
## a future change to placement order would then silently reorder the file and
## break "same seed, same bytes" for a reason that has nothing to do with the
## world being different.
func to_dict() -> Dictionary:
	var out := {
		"schema": SCHEMA,
		"world_seed": world_seed,
		"params": params.duplicate(true),
		"metrics": metrics(),
		"settlements": [],
		"roads": [],
		"factions": [],
		"parties": [],
	}
	for s in _sorted_by(settlements, "id"):
		out["settlements"].append({
			"id": String(s["id"]),
			"kind": String(s["kind"]),
			"name_key": String(s["name_key"]),
			"name_number": int(s["name_number"]),
			"x": float(s["x"]),
			"z": float(s["z"]),
			"region": int(s["region"]),
			"faction": int(s["faction"]),
			"anchor": bool(s["anchor"]),
		})
	for r in _sorted_by(roads, "a"):
		out["roads"].append({
			"a": String(r["a"]),
			"b": String(r["b"]),
			"length": float(r["length"]),
		})
	for f in _sorted_by(factions, "id"):
		out["factions"].append({
			"id": String(f["id"]),
			"name_key": String(f["name_key"]),
			"color_index": int(f["color_index"]),
			"capital": String(f["capital"]),
		})
	for p in _sorted_by(parties, "id"):
		out["parties"].append({
			"id": String(p["id"]),
			"faction": int(p["faction"]),
			"home": String(p["home"]),
			"x": float(p["x"]),
			"z": float(p["z"]),
		})
	return out


## The serialised world → `{ok, text, reason}` (the same contract as every
## `Canon` entry point, so a caller that ignores the error has to ignore an
## explicit flag).  `Canon` owns the format (schema + code-point key order +
## integers as integers + `%.6f` otherwise + LF); this class only decides *what*
## goes in and in what order.
func to_text() -> Dictionary:
	return Canon.to_text(to_dict())


## Copy of `p_items` sorted by the textual field `p_key`.  A copy, because the
## returned array must never be an alias of live generation state.
func _sorted_by(p_items: Array, p_key: String) -> Array:
	var out: Array = []
	for item in p_items:
		out.append(item)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get(p_key, "")) < String(b.get(p_key, "")))
	return out


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
		var name_key := String(anchor.get("name_key", ""))
		if name_key.is_empty():
			# 数据表只存 key（S1.5a）。缺 key 时按 id 生成一个，告警一次，别静默显示空名。
			name_key = "SETTLEMENT_" + id.to_upper()
			warnings.append("锚点 `%s` 缺少 `name_key`：按 id 回退为 `%s`" % [id, name_key])
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
			"name_key": name_key,
			"name_number": 0,
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
			if _try_place(kind, String(KIND_KEYS[kind]), i + 1):
				continue
			warnings.append("`%s` 第 %d 个在 %d 次内找不到落点（间距 %.0f m / 坡度上限 %.2f）：按实际数量降级"
					% [kind, i + 1, MAX_PLACE_TRIES, spacing(), slope_limit()])


func _try_place(kind: String, name_key: String, name_number: int) -> bool:
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
			"name_key": name_key,
			"name_number": name_number,
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
			"name_key": String(FACTION_KEYS[i % FACTION_KEYS.size()]),
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
			"name_key": String(anchor.get("name_key", "")),
			"x": x,
			"z": z,
		})
	out["ok"] = true
	out["anchors"] = anchors
	out["warnings"] = warnings
	return out

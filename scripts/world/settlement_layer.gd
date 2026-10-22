class_name SettlementLayer
extends Node3D

## 全部聚落的集合（S1.5b）：建 20 枚 `SettlementMarker`，并回答"队伍现在离哪个聚落
## 有多远、是否进入了可交互范围"。
##
## WHY A LAYER: 与 `PartyLayer` 同一条理由 —— 场景根只多一个子节点，聚落自己长多少枚
## 棋子是这一层的事。范围和几何分开：`SettlementMarker` 不知道"玩家在哪"，
## 这一层不知道"屋子长什么样"。
##
## 交互半径 `INTERACT_RADIUS = 90 m` 的来历：行军速度 24 m/s（`travel_params.json`），
## 90 m ≈ 3.75 秒的余量 —— 玩家看见提示条之后还来得及停；同时 90 m 远小于聚落最小间距
## 120 m（`gen_params.json`），所以**两个聚落不可能同时落在范围内**，焦点永远是唯一的。
## 这个不等式是这条设计的地基，用例里有一条断言直接钉它。
##
## 本层不读输入、不推进时间：输入在 `strategic_map.gd`，范围在 `focus_at()` 里算。

const INTERACT_RADIUS := 90.0

## 贴地用的高度场与聚落数据（都由 `setup()` 注入；本层不自己造世界）。
var field: HeightField = null
var data: WorldData = null
## 按 `data.settlements` 的顺序排列，一枚聚落一枚棋子。
var markers: Array[SettlementMarker] = []
## 最近一次 `focus_at()` 的结果：
## `{id, kind, faction, label, distance, in_range, x, z}`；空字典表示还没有聚落。
var focus: Dictionary = {}


## 建好全部棋子。`p_material` 可注入现成材质（用例里传 `null`，让棋子自己找 `Style`）。
## 可重复调用：先清空再重建，不叠加节点（重复 `boot()` 是合法路径）。
func setup(p_field: HeightField, p_data: WorldData,
		p_material: ShaderMaterial = null) -> bool:
	field = p_field
	data = p_data
	clear()
	if data == null:
		return false
	for s in data.settlements:
		var marker := SettlementMarker.new()
		marker.name = "S_" + String(s["id"])
		marker.setup(field, String(s["kind"]), int(s["faction"]), String(s["id"]), p_material)
		# 先 `add_child` 再摆位置：`position` 是局部坐标，父节点在原点，所以顺序不影响
		# 结果 —— 但进树后再摆能保证"节点已在世界里"这一条对所有调用方都成立。
		add_child(marker)
		marker.place_at(float(s["x"]), float(s["z"]))
		markers.append(marker)
	focus = {}
	return markers.size() == data.settlements.size()


## 清空全部棋子。在树里用 `queue_free()`，离树用 `free()`（陷阱 30）。
func clear() -> void:
	for m in markers:
		if not is_instance_valid(m):
			continue
		if m.is_inside_tree():
			m.queue_free()
		else:
			m.free()
	markers.clear()
	focus = {}


## 更新焦点：最近的聚落 + 是否进入交互范围。返回同一份字典（调用方不必再查）。
## `(x, z)` 是队伍在地面上的位置；本方法**不写** `GameState`，也不看时间。
func focus_at(x: float, z: float) -> Dictionary:
	focus = {}
	if data == null or markers.is_empty():
		return focus
	var best: Dictionary = {}
	var best_sq := INF
	for s in data.settlements:
		var dx := x - float(s["x"])
		var dz := z - float(s["z"])
		var d2 := dx * dx + dz * dz
		if d2 < best_sq:
			best_sq = d2
			best = s
	if best.is_empty():
		return focus
	var dist := sqrt(best_sq)
	focus = {
		"id": String(best["id"]),
		"kind": String(best["kind"]),
		"faction": int(best["faction"]),
		"label": data.settlement_label(best),
		"distance": dist,
		"in_range": dist <= INTERACT_RADIUS,
		"x": float(best["x"]),
		"z": float(best["z"]),
	}
	return focus


## 焦点里那枚聚落的棋子（没有焦点时返回 `null`）。
func focused_marker() -> SettlementMarker:
	if focus.is_empty():
		return null
	return marker_for(String(focus["id"]))


func marker_for(id: String) -> SettlementMarker:
	for m in markers:
		if is_instance_valid(m) and m.settlement_id == id:
			return m
	return null


## 某一型聚落的棋子（用例按种类断言外形层级）。
func markers_of_kind(kind: String) -> Array[SettlementMarker]:
	var out: Array[SettlementMarker] = []
	for m in markers:
		if is_instance_valid(m) and m.kind == kind:
			out.append(m)
	return out


## 确定性签名：同一世界两次构建必须逐字相同（几何 + 归属 + 落点 + 三角数）。
func signature() -> String:
	var cells: Array[String] = []
	for m in markers:
		if not is_instance_valid(m):
			continue
		var mt := m.metrics()
		cells.append("%s|%s|%d|%.3f|%.3f|%.3f|%d" % [
			String(mt["id"]), String(mt["kind"]), int(mt["faction"]),
			(m.position as Vector3).x, (m.position as Vector3).y, (m.position as Vector3).z,
			int(mt["tris"])])
	return ";".join(cells)


## 这一层的自述：枚数、按种类的分布、势力、三角预算、焦点。
## `tris` 是单遍三角数合计；渲染器面数 = 2 × tris（描边第二遍）。
func report() -> Dictionary:
	var by_kind := {"village": 0, "town": 0, "fortress": 0}
	var by_faction := {}
	var tris := 0
	var verts := 0
	var missing: Array[String] = []
	var ungrounded: Array[String] = []
	for m in markers:
		if not is_instance_valid(m):
			continue
		var mt := m.metrics()
		by_kind[String(mt["kind"])] = int(by_kind.get(String(mt["kind"]), 0)) + 1
		var f := int(mt["faction"])
		by_faction[f] = int(by_faction.get(f, 0)) + 1
		tris += int(mt["tris"])
		verts += int(mt["verts"])
		if absf(float(mt["min_y"])) > 1e-4:
			ungrounded.append(String(mt["id"]))
	if data != null and markers.size() != data.settlements.size():
		missing.append("%d/%d" % [markers.size(), data.settlements.size()])
	return {
		"count": markers.size(),
		"by_kind": by_kind,
		"by_faction": by_faction,
		"tris": tris,
		"verts": verts,
		"interact_radius": INTERACT_RADIUS,
		"focus": focus.duplicate(),
		"ungrounded": ungrounded,
		"missing": missing,
	}
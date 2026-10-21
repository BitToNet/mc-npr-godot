class_name TravelGraph
extends RefCounted
## 战略图行军图（S1.3b）：把高度场 + 路网压成一张 75×75 的可走格图，并在上面跑
## **确定性** A\*。
##
## 为什么是"网格 + 道路格"而不是"聚落连通图"：S1.3c 要让玩家点地面就能走，目标点是任意
## 坐标而不是 20 个聚落；聚落图只能回答"这两个村子怎么走"，回答不了"走到那个山坡上"。
## 道路在这个模型里是**成本折扣**（格子被道路直线覆盖 ⇒ 每米更便宜），所以"沿路更快"
## 是从同一张图里自然长出来的，不需要第二套寻路。
##
## 三条硬约束（`docs/ROADMAP.md` §6 S1.3 `A-` 两项都压在这里）：
##   1. **决定论**：二叉堆按 `(f, 节点序号)` 双键排序、邻居按固定顺序展开、成本只做
##      确定性浮点运算 —— 同起终点两次运行必须逐位一致，不允许用哈希表迭代序。
##   2. **合法性**：一格"可走"要求**中心 + 四个角**都高于水面；对角移动还要求两个
##      正交邻居都可走（否则会从两块陆地之间的水角"斜穿"过去）。
##   3. **数值进表**：格距 / 道路提速 / 坡度成本 / 水域余量 / 展开预算，以及 S1.3c 的
##      行军速度 / 转向角速度 / 到达半径 / 爬坡俯仰上限，全在
##      `data/world/travel_params.json`，代码里只有安全区间与兜底值。
##
## 本类是纯数据 + 纯函数：不碰 `Time.*`、不抽随机数、不碰 `get_tree()`，所以能离树构建，
## 也能被 `--script` 用例直接驱动。

const PATH := "res://data/world/travel_params.json"
const SCHEMA := 1

## 表缺失 / 损坏时的兜底值。改这里必须同步改 `data/world/travel_params.json` 与
## `docs/ROADMAP.md` §6 S1.3，否则用例的规范化断言会先红。
const DEFAULTS := {
	"grid_m": 32.0,
	"road_speed_bonus": 0.35,
	"slope_cost": 1.6,
	"water_margin": 1.5,
	"max_expanded": 20000,
	# 移动积分（S1.3c）：米/秒、转向角速度（°/s）、到达半径（m）、爬坡俯仰上限（°）。
	"march_speed": 24.0,
	"turn_rate_deg": 300.0,
	"arrive_radius": 6.0,
	"max_pitch_deg": 12.0,
}

## 安全区间（超出即钳制并记告警，不致命）。
const RANGES := {
	"grid_m": [8.0, 120.0],
	"road_speed_bonus": [0.0, 1.0],
	"slope_cost": [0.0, 8.0],
	"water_margin": [0.0, 20.0],
	"max_expanded": [100.0, 500000.0],
	"march_speed": [1.0, 200.0],
	"turn_rate_deg": [10.0, 1440.0],
	"arrive_radius": [0.5, 60.0],
	"max_pitch_deg": [0.0, 45.0],
}

## 邻居展开顺序必须固定：先四个正交（+x / −x / +z / −z），再四个对角。顺序一变，
## 同代价路径的选择就变，`A-` 的"两次一致"会变成"两次都合法但不一样"。
const NEIGHBOURS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


## 参数表（`data/world/travel_params.json`）。与 `GenParams` 同一套契约：区间外钳制、
## 类型错退回该字段兜底值、未知/缺失键记告警、`schema` 高于本版整体拒绝。
class Params:
	var grid_m := 32.0
	var road_speed_bonus := 0.35
	var slope_cost := 1.6
	var water_margin := 1.5
	var max_expanded := 20000
	var march_speed := 24.0
	var turn_rate_deg := 300.0
	var arrive_radius := 6.0
	var max_pitch_deg := 12.0
	var warnings := PackedStringArray()
	var ok := true

	## 道路格的每米成本系数：路上快 `1 + bonus` 倍 ⇒ 成本 × `1 / (1 + bonus)`。
	func cost_on_road() -> float:
		return 1.0 / (1.0 + road_speed_bonus)

	## 道路格的速度系数（b3 的移动积分直接用这个数，不再二次换算）。
	func speed_on_road() -> float:
		return 1.0 + road_speed_bonus

	## 转向角速度（弧度/秒）与爬坡俯仰上限（弧度）—— 移动积分只认弧度。
	func turn_rate_rad() -> float:
		return deg_to_rad(turn_rate_deg)

	func max_pitch_rad() -> float:
		return deg_to_rad(max_pitch_deg)

	static func load_from(path: String = PATH) -> Params:
		var p := Params.new()
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			p.ok = false
			p.warnings.append("读不到 %s（%s），全部用兜底值" % [path, error_string(FileAccess.get_open_error())])
			return p
		var text := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(text)
		if parsed == null:
			p.ok = false
			p.warnings.append("%s 不是合法 JSON，全部用兜底值" % path)
			return p
		return from_dict(parsed, p)

	static func from_dict(raw: Variant, into: Params = null) -> Params:
		var p: Params = into if into != null else Params.new()
		if not raw is Dictionary:
			p.ok = false
			p.warnings.append("参数表顶层必须是对象，全部用兜底值")
			return p
		var table: Dictionary = raw
		var schema := int(table.get("schema", 0))
		if schema > SCHEMA:
			p.ok = false
			p.warnings.append("schema %d 高于本版 %d，整表拒绝" % [schema, SCHEMA])
			return p
		for key in table.keys():
			if String(key) == "schema":
				continue
			if not DEFAULTS.has(String(key)):
				p.warnings.append("未知字段 `%s` 已忽略" % String(key))
		for key in DEFAULTS.keys():
			if not table.has(key):
				p.warnings.append("缺字段 `%s`，用兜底值 %s" % [key, str(DEFAULTS[key])])
				continue
			var value: Variant = table[key]
			if not (value is int or value is float):
				p.warnings.append("字段 `%s` 不是数字，用兜底值 %s" % [key, str(DEFAULTS[key])])
				continue
			var v := float(value)
			var rng: Array = RANGES[key]
			if v < float(rng[0]) or v > float(rng[1]):
				v = clampf(v, float(rng[0]), float(rng[1]))
				p.warnings.append("字段 `%s` 超出安全区间，钳到 %s" % [key, str(v)])
			match String(key):
				"grid_m":
					p.grid_m = v
				"road_speed_bonus":
					p.road_speed_bonus = v
				"slope_cost":
					p.slope_cost = v
				"water_margin":
					p.water_margin = v
				"max_expanded":
					p.max_expanded = int(v)
				"march_speed":
					p.march_speed = v
				"turn_rate_deg":
					p.turn_rate_deg = v
				"arrive_radius":
					p.arrive_radius = v
				"max_pitch_deg":
					p.max_pitch_deg = v
		return p


var field: HeightField = null
var data: WorldData = null
var params: Params = null
var warnings := PackedStringArray()

## 每边格数 / 格距（米）/ 地图半宽（米）。
var n := 0
var cell_m := 32.0
var half := 1200.0
var built := false

## 逐格事实：可走 / 在道路上 / 每米成本系数 / 格心高度。
var walkable := PackedByteArray()
var road := PackedByteArray()
var cost_mul := PackedFloat32Array()
var heights := PackedFloat32Array()

## 构建统计（用例直接读，不另开接口）。
var walkable_count := 0
var water_count := 0
var road_cell_count := 0
var road_water_crossings := 0

# A* 的工作区。放在实例上而不是每帧新建：一次寻路要填满 5625 格，反复 new 会把
# `s1_3_path` 的 8 次寻路拖成秒级。
var _g := PackedFloat32Array()
var _came := PackedInt32Array()
var _closed := PackedByteArray()
var _heap_ids := PackedInt32Array()
var _heap_f := PackedFloat32Array()
var _heap_size := 0

# 最近一次寻路的统计。
var last_expanded := 0
var last_cost := 0.0
var last_road_m := 0.0
var last_offroad_m := 0.0


## 建图。返回 `true` 表示可用；失败原因写在 `warnings` 里（不致命，但用例会判红）。
func build(p_field: HeightField, p_data: WorldData = null, p_params: Params = null) -> bool:
	built = false
	warnings.clear()
	field = p_field
	data = p_data
	params = p_params if p_params != null else Params.load_from()
	for w in params.warnings:
		warnings.append(w)
	if field == null:
		warnings.append("没有高度场，建不了行军图")
		return false
	n = maxi(1, roundi(field.map_size / maxf(1.0, params.grid_m)))
	cell_m = field.map_size / float(n)
	half = field.half_size
	var total := n * n
	walkable.resize(total)
	road.resize(total)
	cost_mul.resize(total)
	heights.resize(total)
	_g.resize(total)
	_came.resize(total)
	_closed.resize(total)
	_heap_ids.resize(total * 2 + 8)
	_heap_f.resize(total * 2 + 8)
	walkable_count = 0
	water_count = 0
	road_cell_count = 0
	road_water_crossings = 0
	var floor_h := field.water_level + params.water_margin
	var reach := cell_m * 0.5
	for iz in n:
		for ix in n:
			var c := cell_center(ix, iz)
			var ok_cell := true
			if field.height_at(c.x, c.y) <= floor_h:
				ok_cell = false
			else:
				# 四角也要干：只在格心采样会让"半格水"的浅滩被当成陆地，
				# 于是路径贴着海岸线切过去，b3 的棋子就踩着水走。
				for d: Vector2 in [Vector2(-reach, -reach), Vector2(reach, -reach),
						Vector2(-reach, reach), Vector2(reach, reach)]:
					if field.height_at(c.x + d.x, c.y + d.y) <= floor_h:
						ok_cell = false
						break
			var i := iz * n + ix
			walkable[i] = 1 if ok_cell else 0
			heights[i] = field.height_at(c.x, c.y)
			if ok_cell:
				walkable_count += 1
				var slope := maxf(0.0, field.slope_at(c.x, c.y))
				cost_mul[i] = 1.0 + params.slope_cost * slope
			else:
				water_count += 1
				cost_mul[i] = -1.0
	if data != null:
		_rasterise_roads()
	built = walkable_count > 0
	if not built:
		warnings.append("全图没有一个可走格")
	return built


## 把每条道路直线（聚落 A 中心 → 聚落 B 中心）栅格化成道路格。道路只是成本折扣：
## 穿水的格子不会因此变成可走，只记一条 `road_water_crossings` 供台账记账。
func _rasterise_roads() -> void:
	var by_id := {}
	for s in data.settlements:
		by_id[String(s["id"])] = s
	for r in data.roads:
		var a: Dictionary = by_id.get(String(r.get("a", "")), {})
		var b: Dictionary = by_id.get(String(r.get("b", "")), {})
		if a.is_empty() or b.is_empty():
			continue
		var p0 := Vector2(float(a["x"]), float(a["z"]))
		var p1 := Vector2(float(b["x"]), float(b["z"]))
		var c0 := cell_of(p0.x, p0.y)
		var c1 := cell_of(p1.x, p1.y)
		for cell in _line_cells(c0, c1):
			var i := cell.y * n + cell.x
			if walkable[i] == 0:
				road_water_crossings += 1
				continue
			if road[i] == 0:
				road[i] = 1
				road_cell_count += 1
			cost_mul[i] = params.cost_on_road()


## 整数 DDA：从 c0 到 c1 逐格走，返回经过的格坐标（含两端）。对称、无浮点累积误差，
## 因而"同一对聚落两次栅格化结果相同"是可证的。
func _line_cells(c0: Vector2i, c1: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := absi(c1.x - c0.x)
	var dz := absi(c1.y - c0.y)
	var sx := 1 if c1.x >= c0.x else -1
	var sz := 1 if c1.y >= c0.y else -1
	var x := c0.x
	var z := c0.y
	var err := dx - dz
	while true:
		out.append(Vector2i(x, z))
		if x == c1.x and z == c1.y:
			break
		var e2 := err * 2
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
	return out


func cell_of(x: float, z: float) -> Vector2i:
	var ix := floori((x + half) / cell_m)
	var iz := floori((z + half) / cell_m)
	return Vector2i(clampi(ix, 0, n - 1), clampi(iz, 0, n - 1))


func cell_center(ix: int, iz: int) -> Vector2:
	return Vector2(-half + (float(ix) + 0.5) * cell_m, -half + (float(iz) + 0.5) * cell_m)


func index_of(ix: int, iz: int) -> int:
	return iz * n + ix


func inside(ix: int, iz: int) -> bool:
	return ix >= 0 and iz >= 0 and ix < n and iz < n


func is_walkable_at(x: float, z: float) -> bool:
	var c := cell_of(x, z)
	return walkable[index_of(c.x, c.y)] != 0


func on_road_at(x: float, z: float) -> bool:
	var c := cell_of(x, z)
	return road[index_of(c.x, c.y)] != 0


## 该点的每米成本系数（越大越慢）；不可走返回 `-1.0`。
func cost_per_m_at(x: float, z: float) -> float:
	var c := cell_of(x, z)
	return cost_mul[index_of(c.x, c.y)]


## 该点的速度系数（1.0 = 平地基准速度，路上 = `1 + bonus`，坡上 < 1）。b3 的移动积分
## 用这个值，寻路成本与移动速度因此共用同一张表，不会出现"路算得便宜、走起来不快"。
func speed_factor_at(x: float, z: float) -> float:
	var mul := cost_per_m_at(x, z)
	if mul <= 0.0:
		return 0.0
	return 1.0 / mul


## 确定性 A\*。返回 `{ok, reason, points, cells, cost, expanded, road_m, offroad_m}`；
## `points` 是格心折线，首尾分别替换成传入的精确坐标。
func find_path(from: Vector2, to: Vector2) -> Dictionary:
	var out := {
		"ok": false,
		"reason": "",
		"points": PackedVector2Array(),
		"cells": PackedInt32Array(),
		"cost": 0.0,
		"expanded": 0,
		"road_m": 0.0,
		"offroad_m": 0.0,
	}
	last_expanded = 0
	last_cost = 0.0
	last_road_m = 0.0
	last_offroad_m = 0.0
	if not built:
		out["reason"] = "图未构建"
		return out
	if absf(from.x) > half or absf(from.y) > half or absf(to.x) > half or absf(to.y) > half:
		out["reason"] = "起终点越界"
		return out
	var cs := cell_of(from.x, from.y)
	var ct := cell_of(to.x, to.y)
	if walkable[index_of(cs.x, cs.y)] == 0:
		out["reason"] = "起点不可走（水或边界）"
		return out
	if walkable[index_of(ct.x, ct.y)] == 0:
		out["reason"] = "终点不可走（水或边界）"
		return out
	var start := index_of(cs.x, cs.y)
	var goal := index_of(ct.x, ct.y)
	if start == goal:
		out["ok"] = true
		out["points"] = PackedVector2Array([from, to])
		out["cells"] = PackedInt32Array([start])
		out["cost"] = from.distance_to(to)
		return out

	_g.fill(INF)
	_came.fill(-1)
	_closed.fill(0)
	_heap_size = 0
	_g[start] = 0.0
	_push(start, _heuristic(start, goal))
	var found := false
	var expanded := 0
	while _heap_size > 0:
		var cur := _pop()
		if _closed[cur] != 0:
			continue
		_closed[cur] = 1
		expanded += 1
		if cur == goal:
			found = true
			break
		if expanded > params.max_expanded:
			out["reason"] = "展开预算用尽（%d 格）" % params.max_expanded
			break
		var cx := cur % n
		var cz := cur / n
		for d: Vector2i in NEIGHBOURS:
			var nx: int = cx + d.x
			var nz: int = cz + d.y
			if not inside(nx, nz):
				continue
			var ni := index_of(nx, nz)
			if walkable[ni] == 0 or _closed[ni] != 0:
				continue
			if d.x != 0 and d.y != 0:
				# 对角不许"切角"：两块陆地只在一个角相接时，中间其实是水。
				if walkable[index_of(cx + d.x, cz)] == 0:
					continue
				if walkable[index_of(cx, cz + d.y)] == 0:
					continue
			var step := cell_m * (1.4142135623730951 if d.x != 0 and d.y != 0 else 1.0)
			var step_cost := step * 0.5 * (cost_mul[cur] + cost_mul[ni])
			var tentative := _g[cur] + step_cost
			if tentative >= _g[ni]:
				continue
			_g[ni] = tentative
			_came[ni] = cur
			_push(ni, tentative + _heuristic(ni, goal))
	last_expanded = expanded
	if not found:
		if String(out["reason"]) == "":
			out["reason"] = "无可达路径"
		out["expanded"] = expanded
		return out

	var chain: Array[int] = []
	var walk := goal
	while walk >= 0:
		chain.append(walk)
		if walk == start:
			break
		walk = _came[walk]
	chain.reverse()
	var points := PackedVector2Array()
	var cells := PackedInt32Array()
	var road_m := 0.0
	var offroad_m := 0.0
	var cost_sum := 0.0
	for k in chain.size():
		var i := chain[k]
		cells.append(i)
		if k == 0:
			points.append(from)
		elif k == chain.size() - 1:
			points.append(to)
		else:
			points.append(cell_center(i % n, i / n))
		if k > 0:
			var seg := points[k].distance_to(points[k - 1])
			# 成本必须**对着报出去的折线**重算一遍，不能直接返回 `_g[goal]`：A\* 的
			# g 只覆盖格心到格心，首末两段（精确点到格心）不在里面。若返回 `_g[goal]`，
			# 调用方拿到的"成本"与拿到的"折线"就不是同一趟行程 —— 实测差 15 个成本单位
			# （673 m 的路，折线 672.9 m，`_g` 只算到 483.9，按折线算是 498.5）。
			cost_sum += seg * 0.5 * (cost_mul[chain[k - 1]] + cost_mul[chain[k]])
			if road[chain[k - 1]] != 0:
				road_m += seg
			else:
				offroad_m += seg
	last_cost = cost_sum
	last_road_m = road_m
	last_offroad_m = offroad_m
	out["ok"] = true
	out["points"] = points
	out["cells"] = cells
	out["cost"] = cost_sum
	out["expanded"] = expanded
	out["road_m"] = road_m
	out["offroad_m"] = offroad_m
	return out


## 八向 octile 距离 × 全局最小成本系数。用最小系数（而不是 1.0）才保持可采纳：
## 道路格的成本系数小于 1，按 1.0 估会高估剩余代价，A* 就不再最优。
func _heuristic(a: int, b: int) -> float:
	var ax := a % n
	var az := a / n
	var bx := b % n
	var bz := b / n
	var dx := absi(ax - bx)
	var dz := absi(az - bz)
	var lo := mini(dx, dz)
	var hi := maxi(dx, dz)
	var octile := float(lo) * 1.4142135623730951 + float(hi - lo)
	return octile * cell_m * params.cost_on_road()


# --- 二叉堆：按 (f, 节点序号) 双键排序 ---------------------------------------
# 只按 f 排序时，同 f 的两个节点谁先出堆取决于插入顺序，而插入顺序又取决于邻居展开
# 与浮点累加 —— 那样"两次一致"只能靠运气。加上序号作第二键，堆序就是全序。

func _push(id: int, f: float) -> void:
	if _heap_size >= _heap_ids.size():
		_heap_ids.resize(_heap_ids.size() * 2 + 8)
		_heap_f.resize(_heap_f.size() * 2 + 8)
	_heap_ids[_heap_size] = id
	_heap_f[_heap_size] = f
	var i := _heap_size
	_heap_size += 1
	while i > 0:
		var parent := (i - 1) / 2
		if not _less(i, parent):
			break
		_swap(i, parent)
		i = parent


func _pop() -> int:
	var top := _heap_ids[0]
	_heap_size -= 1
	if _heap_size > 0:
		_heap_ids[0] = _heap_ids[_heap_size]
		_heap_f[0] = _heap_f[_heap_size]
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var best := i
			if l < _heap_size and _less(l, best):
				best = l
			if r < _heap_size and _less(r, best):
				best = r
			if best == i:
				break
			_swap(i, best)
			i = best
	return top


func _less(a: int, b: int) -> bool:
	if _heap_f[a] != _heap_f[b]:
		return _heap_f[a] < _heap_f[b]
	return _heap_ids[a] < _heap_ids[b]


func _swap(a: int, b: int) -> void:
	var id := _heap_ids[a]
	_heap_ids[a] = _heap_ids[b]
	_heap_ids[b] = id
	var f := _heap_f[a]
	_heap_f[a] = _heap_f[b]
	_heap_f[b] = f


## 路径的确定性指纹：坐标按 `%.4f` 拼接。用例用它比"两次逐位一致"，台账里也贴这个值。
static func path_key(points: PackedVector2Array) -> String:
	var parts := PackedStringArray()
	parts.append("%d" % points.size())
	for p in points:
		parts.append("%.4f,%.4f" % [p.x, p.y])
	return "|".join(parts)

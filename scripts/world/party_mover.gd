class_name PartyMover
extends Node3D
## 队伍移动（S1.3c）：把 S1.3b 算出来的折线变成每帧的位移、朝向与爬坡俯仰。
##
## **只有一个积分入口** `step(delta)`，和 `StrategicCamera.step()` 同构：本类不读 `Input`、
## 不读 `Time.*`、不抽随机数，所以 60 s 的行军可以在用例里用固定 1/60 步长逐帧重放，
## 结果与真机一致。输入（鼠标点击、将来的键盘）留在场景根里，本类只接受"命令"。
##
## 三层分工，一层只做一件事：
##   `TravelGraph`  —— 图与路径（纯数据，离树可用）；
##   `PartyMover`   —— 沿路径的积分（本类，Node3D，可离树构建）；
##   `PartyMarker`  —— 造型与贴地（离树可用，只被摆位）。
##
## 速度不是一个常数，而是 `march_speed × speed_factor_at(x, z)`：路上 1.35、地面 1.0、
## 坡上更小。寻路用的成本表与这里用的速度表是**同一张**（§9.13.2），所以"算得便宜"
## 与"走得快"不可能各说各话。

## 正前方是 +Z（与 `PartyMarker.face_towards` 的 `atan2(x, z)` 约定一致）。
const PITCH_SPAN := 11.0     ## 俯仰采样的前后半跨度（米）≈ 标称 22 m 的一半
const ARRIVE_EPS := 0.001

enum State { IDLE, MARCHING, ARRIVED, BLOCKED }

var field: HeightField = null
var data: WorldData = null
var params: TravelGraph.Params = null
var graph: TravelGraph = null
var marker: PartyMarker = null

## 生效中的数值（`setup()` 从参数表取，缺表则用兜底值，用例可以事后改）。
var speed_mps := 24.0
var turn_rate := deg_to_rad(300.0)
var arrive_radius := 6.0
var max_pitch := deg_to_rad(12.0)

var state := State.IDLE
## 当前朝向（弧度，`atan2(x, z)` 约定）与爬坡俯仰（弧度，正 = 上坡）。
var facing := 0.0
var pitch := 0.0

## 上一帧的位移与预算（用例用它们证明"位移 = 速度 × dt"）。
var last_moved := 0.0
var last_budget := 0.0
var last_speed := 0.0
## 剩余路径长度（米）；`ARRIVED` 后为 0。
var remaining := 0.0

var _points := PackedVector2Array()
var _seg := 0
var _offset := 0.0
var _length := 0.0
var _last_reason := ""


## 建图并挂上棋子。`p_params` 为空时读 `data/world/travel_params.json`。
## 失败时 `graph` 仍可能是半成品，调用方看返回值，不要看 `graph == null`。
func setup(p_field: HeightField, p_data: WorldData, p_params: TravelGraph.Params = null) -> bool:
	field = p_field
	data = p_data
	params = p_params if p_params != null else TravelGraph.Params.load_from()
	speed_mps = params.march_speed
	turn_rate = params.turn_rate_rad()
	arrive_radius = params.arrive_radius
	max_pitch = params.max_pitch_rad()
	graph = TravelGraph.new()
	var ok := graph.build(field, data, params)
	if not ok:
		_last_reason = "行军图建不起来"
		return false
	if marker == null:
		marker = PartyMarker.new()
		marker.name = "PartyMarker"
		add_child(marker)
	marker.setup(field)
	return true


## 落位并清空命令。`faction` 换色会重建网格（顶点色烘在网格里），所以只在换阵营时给。
func spawn_at(x: float, z: float, faction := 0) -> void:
	if marker == null:
		return
	marker.set_faction(faction)
	marker.place_at(x, z)
	_clear_path()
	state = State.IDLE
	facing = marker.facing
	pitch = 0.0
	marker.rotation = Vector3(0.0, facing, 0.0)


## 命令：走到 (x, z)。返回 `{ok, reason, length}`；失败时**不动**当前命令，
## 调用方可以据此决定要不要提示玩家（点水里不该打断正在进行的行军）。
func order_to(x: float, z: float) -> Dictionary:
	if marker == null or graph == null or not graph.built:
		return {"ok": false, "reason": "队伍还没有落地", "length": 0.0}
	var from := Vector2(marker.position.x, marker.position.z)
	var found := graph.find_path(from, Vector2(x, z))
	if not bool(found.get("ok", false)):
		_last_reason = String(found.get("reason", ""))
		return {"ok": false, "reason": _last_reason, "length": 0.0}
	var was_marching := state == State.MARCHING
	_points = found["points"]
	_seg = 0
	_offset = 0.0
	_length = 0.0
	for i in range(1, _points.size()):
		_length += _points[i - 1].distance_to(_points[i])
	remaining = _length
	state = State.MARCHING
	_last_reason = ""
	# 从**静止**出发时立即把朝向对准第一段：否则第一帧会先"原地转身"，手感上像点下去
	# 没反应。行进中改令则不在这里扭头 —— 那会绕过 `turn_rate`，让反向行军"啪"地转身
	# （最常见的一帧转 180°），交给 `step()` 按角速度限速转过去。
	if _points.size() >= 2 and not was_marching:
		var d := _points[1] - _points[0]
		if d.length_squared() > 0.000001:
			facing = atan2(d.x, d.y)
			marker.rotation.y = facing
	return {"ok": true, "reason": "", "length": _length}


## 取消当前命令（保留 `_last_reason` 供 HUD 显示）。
func stop(reason := "") -> void:
	_clear_path()
	state = State.IDLE
	_last_reason = reason


## 唯一积分入口。`delta` 必须是调用方给的固定步长（真机是帧间隔，用例是 1/60）。
func step(delta: float) -> void:
	last_moved = 0.0
	last_budget = 0.0
	last_speed = 0.0
	if state != State.MARCHING or delta <= 0.0 or _points.size() < 2:
		return
	var pos := Vector2(marker.position.x, marker.position.z)
	var factor := graph.speed_factor_at(pos.x, pos.y)
	if factor <= 0.0:
		# 只有"图变了 / 位置漂了"才会走到这里：宁可停下报原因，也不穿水。
		stop("前方不可走")
		state = State.BLOCKED
		return
	var budget := speed_mps * factor * delta
	last_budget = budget
	# 位移按**沿折线消耗的弧长**记账，而不是两点直线距离：拐角处的弦长天然短于弧长，
	# 用它当位移会让"位移 = 速度 × dt"在拐弯帧假红。位置本身仍严格落在折线上。
	var rem_before := _remaining_from(pos)
	_advance(budget)
	var p := _point_at_cursor()
	remaining = _remaining_from(p)
	last_moved = maxf(rem_before - remaining, 0.0)
	last_speed = last_moved / delta
	# 到达：剩余 ≤ 半径就停**在当前折线点上**，不吸附到终点 —— 吸附意味着最后一帧
	# 最多瞬移 `arrive_radius`（6 m），肉眼就是一个跳。
	if remaining <= arrive_radius:
		state = State.ARRIVED
	_face_along(p, delta)
	_pitch_at(p)
	marker.place_at(p.x, p.y)
	marker.rotation = Vector3(-pitch, facing, 0.0)


## 状态快照（场景根与用例都只用这一个出口）。
func report() -> Dictionary:
	var pos := Vector2.ZERO
	if marker != null:
		pos = Vector2(marker.position.x, marker.position.z)
	return {
		"state": _state_name(state),
		"x": pos.x,
		"z": pos.y,
		"y": 0.0 if marker == null else marker.position.y,
		"facing": facing,
		"pitch": pitch,
		"remaining": remaining,
		"length": _length,
		"points": _points.size(),
		"faction": 0 if marker == null else marker.faction,
		"reason": _last_reason,
		"last_moved": last_moved,
		"last_speed": last_speed,
	}


func state_name() -> String:
	return _state_name(state)


# --- 内部 --------------------------------------------------------------------


func _clear_path() -> void:
	_points = PackedVector2Array()
	_seg = 0
	_offset = 0.0
	_length = 0.0
	remaining = 0.0


## 沿折线消耗 `budget` 米（允许一帧跨过多个格子）。
func _advance(budget: float) -> void:
	while budget > 0.0 and _seg < _points.size() - 1:
		var seg := _points[_seg].distance_to(_points[_seg + 1])
		var left := seg - _offset
		if budget < left:
			_offset += budget
			return
		budget -= left
		_seg += 1
		_offset = 0.0


## 当前游标处的精确坐标（`_seg` 越界时返回终点）。
func _point_at_cursor() -> Vector2:
	var last := _points.size() - 1
	if _seg >= last:
		return _points[last]
	var seg := _points[_seg].distance_to(_points[_seg + 1])
	if seg <= ARRIVE_EPS:
		return _points[_seg + 1]
	return _points[_seg].lerp(_points[_seg + 1], _offset / seg)


func _remaining_from(p: Vector2) -> float:
	var total := 0.0
	var cur := p
	for i in range(_seg + 1, _points.size()):
		total += cur.distance_to(_points[i])
		cur = _points[i]
	return total


## 朝向下一段的方向，并且**限速**转过去：本帧最多转 `turn_rate × delta` 弧度。
## 不限速的话，折线的直角拐弯会让棋子"啪"地瞬间扭头，肉眼就是抖动。
func _face_along(p: Vector2, delta: float) -> void:
	var last := _points.size() - 1
	if _seg >= last:
		return
	var target := _points[_seg + 1] - p
	if target.length_squared() < 0.000001:
		return
	var want := atan2(target.x, target.y)
	var d := wrapf(want - facing, -PI, PI)
	var max_step := turn_rate * delta
	facing = wrapf(facing + clampf(d, -max_step, max_step), -PI, PI)


## 爬坡俯仰：前后各采一个点，俯仰 = 高差 / 水平距离；正 = 上坡。
func _pitch_at(p: Vector2) -> void:
	if field == null:
		return
	var fx := sin(facing)
	var fz := cos(facing)
	var ahead := field.height_at(p.x + fx * PITCH_SPAN, p.y + fz * PITCH_SPAN)
	var behind := field.height_at(p.x - fx * PITCH_SPAN, p.y - fz * PITCH_SPAN)
	pitch = clampf(atan2(ahead - behind, 2.0 * PITCH_SPAN), -max_pitch, max_pitch)


func _state_name(s: int) -> String:
	match s:
		State.MARCHING:
			return "MARCHING"
		State.ARRIVED:
			return "ARRIVED"
		State.BLOCKED:
			return "BLOCKED"
		_:
			return "IDLE"
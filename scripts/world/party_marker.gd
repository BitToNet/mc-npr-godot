class_name PartyMarker
extends Node3D

## 玩家队伍的**微缩棋子**（S1.3a 批 1）。
##
## 造型取自美术规范的"微缩手办"：圆底座 + 斗篷 + 头 + 旗杆旗面，全部是圆/柱/球，
## 没有一个方块。所有零件在构建时用顶点色烘好颜色，再用 `MeshUtil.combine()` 合成
## **单一 mesh**（一次 draw call）。
##
## 材质：优先用调用方注入的 `ShaderMaterial`（`setup(field, material)`）；不注入时按名字
## 去 `/root` 找 `Style` 单例调 `toon()` —— 它默认会挂反向外壳描边，所以线稿轮廓是
## "默认就完整"的，不靠调用方记得补。**这里刻意不写 `Style.toon()` 这个标识符**：autoload
## 的全局名在 `--script` 模式的编译期不可见（`tools/verify.gd` 的 headless 用例就是这么跑
## 的，写了会直接报 `Identifier not found: Style`），所以只 preload 它的 `const PALETTE` 取色。
##
## 本类**只管画和贴地**：不读输入、不推进时间、不写 `GameState`。移动积分与寻路是批 2 / 批 3
## 的事；这样批 1 的用例可以在 headless 里直接量"脚底与 `height_at` 的偏差"。
##
## 尺寸：`NOMINAL_HEIGHT = 22 m`（约 0.7 个 32 m 地形格）。这不是真实身高，是**棋子**的尺寸
## —— GLOBAL 档 2600 m 跨度下约 7.6 px（一个点）、REGION 约 28 px、LOCAL 约 116 px。
## 用户 2026-10-21 定：固定 22 m，不随档位缩放（`set_marker_scale()` 留着，批 3 再决定）。

const NOMINAL_HEIGHT := 22.0
const BASE_RADIUS := 3.4
const BANNER_WIDTH := 5.0
const BANNER_HEIGHT := 8.2
const BANNER_BOTTOM := 20.4
const BANNER_THICKNESS := 0.18
const POLE_HEIGHT := 19.3
const POLE_BOTTOM := 1.9

## 只取常量，不碰 autoload 实例（理由见文件头）。
const StyleDef := preload("res://scripts/core/style.gd")

## 势力主色（`Style.PALETTE` 键）。按 faction 取模，确定性、无随机。
const FACTION_KEYS := ["cloth", "water_deep", "cloth_alt", "plinth"]

## 贴地用的高度场；为 `null` 时地面按 0 处理（用例里总会给）。
var field: HeightField = null
var faction := 0
## 当前朝向（弧度，已归一化到 (−π, π]）。
var facing := 0.0

var _mesh_instance: MeshInstance3D
var _mesh: ArrayMesh
var _material: ShaderMaterial = null
var _injected_material: ShaderMaterial = null
var _built := false


## 绑定高度场并建好网格。`p_material` 可注入现成材质；为 `null` 时按名字找 `Style` 单例。
## 重复调用是幂等的（离树也能跑：只用 `position`，不碰 `global_*`）。
func setup(p_field: HeightField, p_material: ShaderMaterial = null) -> void:
	field = p_field
	_injected_material = p_material
	_build()


## 换势力色：会重建网格（颜色是烘在顶点色里的，不能只改材质）。
func set_faction(p_faction: int) -> void:
	var v := int(p_faction)
	if v == faction and _built:
		return
	faction = v
	_built = false
	if _mesh_instance != null:
		# 陷阱 30：离树节点上 `queue_free()` 会打印 ERROR，所以按是否在树里分开处理。
		if _mesh_instance.is_inside_tree():
			_mesh_instance.queue_free()
		else:
			_mesh_instance.free()
		_mesh_instance = null
	_build()


## 把棋子放到世界 (x, z)：脚底 = 底座底面，正好落在 `height_at(x, z)`。
func place_at(x: float, z: float) -> Vector3:
	position = Vector3(x, ground_at(x, z), z)
	return position


## 地面高度；没有高度场时按 0（用例总要给，这条只是为了离树安全）。
func ground_at(x: float, z: float) -> float:
	if field == null:
		return 0.0
	return field.height_at(x, z)


## 朝向某个水平方向（`dir` 的 y 分量被忽略）。零向量不动，返回值是归一化后的弧度。
func face_towards(dir: Vector3) -> float:
	var flat := Vector2(dir.x, dir.z)
	if flat.length_squared() < 0.000001:
		return facing
	# `atan2(x, z)` 与 Godot 的 -Z 前方约定一致：dir = (0, 0, -1) 时朝正前。
	facing = wrapf(atan2(flat.x, flat.y), -PI, PI)
	rotation.y = facing
	return facing


## 把目标点方向转成 `face_towards` 的参数（可读性用）。
func face_to_point(point: Vector3) -> float:
	return face_towards(point - position)


## 缩放倍率（1.0 = 22 m 标称高度）。批 3 决定要不要随镜头档位缩放。
func set_marker_scale(k: float) -> void:
	var v := maxf(k, 0.01)
	scale = Vector3(v, v, v)


## 网格与描边的实测指标（用例与日志用）。
func metrics() -> Dictionary:
	var out := {
		"height": 0.0,
		"min_y": 0.0,
		"tris": 0,
		"verts": 0,
		"surfaces": 0,
		"outline": false,
		"faction": faction,
		"size": Vector3.ZERO,
		"aabb_pos": Vector3.ZERO,
		"smooth_verts": 0,
	}
	if _mesh == null:
		return out
	var aabb := _mesh.get_aabb()
	out["height"] = aabb.size.y
	out["min_y"] = aabb.position.y
	out["surfaces"] = _mesh.get_surface_count()
	out["size"] = aabb.size
	out["aabb_pos"] = aabb.position
	out["smooth_verts"] = _count_smooth_verts()
	# 合成后的 mesh 是**非索引**三角形汤，所以三角数 = 顶点数 / 3（索引长度恒为 0）。
	out["verts"] = _mesh.surface_get_array_len(0)
	out["tris"] = int(out["verts"]) / 3
	var mi := _mesh_instance
	if mi != null and mi.material_override is ShaderMaterial:
		var m := mi.material_override as ShaderMaterial
		var o := m.next_pass as ShaderMaterial
		out["outline"] = o != null and o.shader != null \
				and String(o.shader.resource_path).ends_with("outline.gdshader") \
				and float(o.get_shader_parameter("enabled")) > 0.5
	return out


func _build() -> void:
	if _built:
		return
	_built = true
	_material = _make_material()
	var plinth := _tint("plinth")
	var lip := _tint("plinth_lip")
	var coat := _tint(String(FACTION_KEYS[faction % FACTION_KEYS.size()]))
	var cream := _tint("cream")
	var skin := _tint("skin")
	var pole := _tint("hair")
	var cream_disc := _tint("snow_shade")
	var cream_band := _tint("cream")
	var coat_dark := (coat * 0.82)

	var parts: Array = []
	# 底座：两段收口圆柱，底面正好在 y = 0（贴地就靠它）。
	parts.append(_part(MeshUtil.tapered_cylinder(BASE_RADIUS * 1.06, BASE_RADIUS, 0.55, 14, plinth),
			Vector3(0.0, 0.275, 0.0)))
	parts.append(_part(MeshUtil.tapered_cylinder(BASE_RADIUS, BASE_RADIUS * 0.88, 1.05, 14, lip),
			Vector3(0.0, 1.075, 0.0)))
	# 底座顶面一圈奶油色：让"棋子站在台座上"读得出来（不然只有一个黑边圆盘）。
	parts.append(_part(MeshUtil.tapered_cylinder(BASE_RADIUS * 0.90, BASE_RADIUS * 0.84, 0.42, 14, cream_disc),
			Vector3(0.0, 1.80, 0.0)))
	# 斗篷分两段：下摆宽、肩部收窄，读起来才是"披斗篷的人"而不是一枚锥体。
	parts.append(_part(MeshUtil.tapered_cylinder(2.35, 1.62, 6.4, 12, coat, Vector2.ZERO, false, false),
			Vector3(0.0, 4.85, 0.0)))
	parts.append(_part(MeshUtil.tapered_cylinder(1.62, 1.10, 3.4, 12, coat_dark, Vector2.ZERO, false, true),
			Vector3(0.0, 9.75, 0.0)))
	# 两条手臂：从肩部斜下去的小圆柱，有了它剪影才像"人"而不是一枚锥体。
	var arm_rng := RandomNumberGenerator.new()
	arm_rng.seed = 20251022
	var arm := MeshUtil.tapered_cylinder(0.32, 0.24, 3.4, 7, coat_dark, Vector2.ZERO, true, true)
	parts.append(_part_rot(arm, Vector3(-1.30, 10.4, 0.10), Basis(Vector3(0, 0, 1), deg_to_rad(20.0))))
	parts.append(_part_rot(arm, Vector3(1.30, 10.4, 0.10), Basis(Vector3(0, 0, 1), deg_to_rad(-20.0))))
	# 领口一圈奶油色，把斗篷和头分开。
	parts.append(_part(MeshUtil.tapered_cylinder(1.24, 1.10, 0.55, 12, cream_band),
			Vector3(0.0, 11.72, 0.0)))
	# 头 + 兜帽尖（低多边形球 + 收口圆柱，没有方块）。
	var head_rng := RandomNumberGenerator.new()
	head_rng.seed = 20251021
	parts.append(_part(MeshUtil.blob(1.06, 5, 9, Vector3(1.0, 1.04, 1.0), 0.0, head_rng, skin),
			Vector3(0.0, 12.95, 0.0)))
	parts.append(_part(MeshUtil.tapered_cylinder(1.26, 0.16, 1.45, 9, cream),
			Vector3(0.0, 14.45, 0.0)))
	# 旗杆：立在底座上，穿过斗篷背后。
	parts.append(_part(MeshUtil.tapered_cylinder(0.20, 0.16, POLE_HEIGHT, 6, pole),
			Vector3(0.0, POLE_BOTTOM + POLE_HEIGHT * 0.5, -1.15)))
	# 杆顶球。
	parts.append(_part(MeshUtil.blob(0.44, 4, 8, Vector3.ONE, 0.0, head_rng, cream),
			Vector3(0.0, POLE_BOTTOM + POLE_HEIGHT + 0.10, -1.15)))
	# 旗面：一面微拱的薄布，双面各一层（描边材质不开 cull_disabled，所以不能靠单面）。
	var flag_tint := _tint(String(FACTION_KEYS[faction % FACTION_KEYS.size()]))
	parts.append(_part(_banner_mesh(flag_tint), Vector3(0.12, BANNER_BOTTOM, -1.15)))

	_mesh = MeshUtil.combine(parts)
	# 描边必须靠**连续**的外壳。MeshUtil 的生成器把"面法线"同时写进法线和切线槽，于是
	# 反向外壳沿各自的面法线炸开成散三角片，正常线宽下几乎看不见（本批实测：把线宽拉到
	# 120 才看到几道洋红碎屑）。_with_smooth_tangents() 按面积加权重算平滑法线、只写进
	# 切线槽 —— 着色仍用平面法线（保持面着色），外壳才是一张连续的皮。
	_mesh = _with_smooth_tangents(_mesh)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Body"
	_mesh_instance.mesh = _mesh
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_instance)
	if rotation.y != 0.0:
		rotation.y = facing


## 切线槽里不等于面法线的顶点数。反向外壳必须靠平滑法线才连得成一张皮，用例据此断言
## 这一步真的做了（否则描边会炸成散三角片，正常线宽下完全看不见）。
func _count_smooth_verts() -> int:
	if _mesh == null:
		return 0
	var arr := _mesh.surface_get_arrays(0)
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
	var count := 0
	for i in n.size():
		if i * 4 + 2 >= tg.size():
			break
		var t := Vector3(tg[i * 4], tg[i * 4 + 1], tg[i * 4 + 2])
		if t.distance_to(n[i]) > 0.01:
			count += 1
	return count


## 取调色板颜色（常量查表，不碰 autoload 实例）。
static func _tint(key: String) -> Color:
	var c: Color = StyleDef.PALETTE.get(key, Color.WHITE)
	return c.srgb_to_linear()


## 材质：优先注入；否则按名字找 `Style` 单例。找不到返回 `null`（用例会因此判失败）。
func _make_material() -> ShaderMaterial:
	if _injected_material != null:
		return _injected_material
	var style := _style_node()
	if style == null:
		return null
	return style.call("toon", {
		"shade_min": 0.44,
		"rim": 0.28,
		"rim_color": Color(1.0, 0.97, 0.88),
		"spec": 0.18,
		"spec_sharp": 28.0,
		"ink": 3.0,
	}) as ShaderMaterial


## autoload 实例只能运行时按名字取（`--script` 编译期没有 `Style` 标识符）。
static func _style_node() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Style")
	return null


## 计算局部平滑法线（面积加权）并写进切线槽。方向直接取网格自带的面法线，保证与着色
## 一致；顶点位置按 1e-4 量化后共享，合起来的零件之间才不会被当成两层皮。
static func _with_smooth_tangents(mesh: ArrayMesh) -> ArrayMesh:
	var src := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = src[Mesh.ARRAY_COLOR]
	var smooth := {}
	var faces := verts.size() / 3
	for f in faces:
		var i0 := f * 3
		var face_n: Vector3 = normals[i0]
		var cross := (verts[i0 + 1] - verts[i0]).cross(verts[i0 + 2] - verts[i0])
		var area := cross.length() * 0.5
		for k in 3:
			var key := _vkey(verts[i0 + k])
			smooth[key] = (smooth.get(key, Vector3.ZERO) as Vector3) + face_n * area
	var tangents := PackedFloat32Array()
	tangents.resize(verts.size() * 4)
	for i in verts.size():
		var sn: Vector3 = smooth.get(_vkey(verts[i]), normals[i])
		sn = sn.normalized() if sn.length_squared() > 0.000001 else normals[i]
		tangents[i * 4] = sn.x
		tangents[i * 4 + 1] = sn.y
		tangents[i * 4 + 2] = sn.z
		tangents[i * 4 + 3] = 1.0
	var out := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TANGENT] = tangents
	arr[Mesh.ARRAY_COLOR] = colors
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## 位置量化键：同一位置的重复顶点必须落进同一个桶，否则外壳会沿接缝裂开。
static func _vkey(p: Vector3) -> String:
	return "%d_%d_%d" % [roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0)]


static func _part(mesh: ArrayMesh, at: Vector3) -> Dictionary:
	return {"mesh": mesh, "xform": Transform3D(Basis.IDENTITY, at)}


## 带旋转的零件（手臂要斜着放）。
static func _part_rot(mesh: ArrayMesh, at: Vector3, rot: Basis) -> Dictionary:
	return {"mesh": mesh, "xform": Transform3D(rot, at)}


## 旗面：**有厚度的薄板**，不是单层平面。
##
## WHY A SLAB: the ink pass is an inverted hull grown along the normal, so a
## single flat layer can only move forwards/backwards — its silhouette never
## grows and the flag ends up with no outline at all.  Giving the cloth four
## side walls (whose normals point outward, in the plane of the flag) is what
## makes the hull draw a rim around it.  Front/back layers keep it readable from
## both sides without needing `cull_disabled` (which a ShaderMaterial cannot set).
##
## Winding: this project's generators emit vertices clockwise as seen from
## outside (see `MeshUtil._tri`), and the ink pass grows along the tangent slot,
## which by project convention holds the *smooth* normal — here the same value as
## the flat normal, since every quad is planar.
static func _banner_mesh(tint: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 3
	var rows := 2
	var half := BANNER_THICKNESS * 0.5
	var front_grid: Array = []
	var back_grid: Array = []
	for c in cols + 1:
		var u := float(c) / float(cols)
		var bulge := sin(PI * u) * 0.55
		var fcol: Array = []
		var bcol: Array = []
		for r in rows + 1:
			var v := float(r) / float(rows)
			var x := u * BANNER_WIDTH
			var y := -v * BANNER_HEIGHT
			fcol.append(Vector3(x, y, bulge + half))
			bcol.append(Vector3(x, y, bulge - half))
		front_grid.append(fcol)
		back_grid.append(bcol)
	var front := tint.srgb_to_linear()
	var back := (tint * 0.84).srgb_to_linear()
	var edge := (tint * 0.62).srgb_to_linear()
	for c in cols:
		for r in rows:
			# 正面朝 +Z、背面朝 −Z：同一块格子的顶点按同样顺序读、法线相反。
			_quad(st, front_grid[c][r], front_grid[c][r + 1],
					front_grid[c + 1][r + 1], front_grid[c + 1][r], front, Vector3.BACK)
			_quad(st, back_grid[c][r], back_grid[c + 1][r],
					back_grid[c + 1][r + 1], back_grid[c][r + 1], back, Vector3.FORWARD)
	# 四条边墙：法线朝外（在旗面平面内），这样反向外壳才有轮廓可长。
	for c in cols:
		_edge_strip(st, front_grid[c][0], front_grid[c + 1][0], back_grid[c][0],
				back_grid[c + 1][0], edge, Vector3.UP)
		_edge_strip(st, front_grid[c][rows], front_grid[c + 1][rows],
				back_grid[c][rows], back_grid[c + 1][rows], edge, Vector3.DOWN)
	for r in rows:
		_edge_strip(st, front_grid[0][r], front_grid[0][r + 1], back_grid[0][r],
				back_grid[0][r + 1], edge, Vector3.LEFT)
		_edge_strip(st, front_grid[cols][r], front_grid[cols][r + 1],
				back_grid[cols][r], back_grid[cols][r + 1], edge, Vector3.RIGHT)
	return st.commit()


## 一条边墙（前后两对顶点围成一个四边形），法线按给定方向。
static func _edge_strip(st: SurfaceTool, f0: Vector3, f1: Vector3, b0: Vector3, b1: Vector3,
		tint: Color, out_normal: Vector3) -> void:
	_quad(st, f0, f1, b1, b0, tint, out_normal)


## 两个三角形组成一个四边形；法线由调用方给（平面着色，不插值）。
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		tint: Color, n: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		_tri(st, tri[0], tri[1], tri[2], tint, n)


## 单个三角形：法线与切槽都写"平滑法线"（本项目约定切槽存平滑法线，外壳靠它膨胀）。
## 顶点顺序翻转成"从外面看顺时针"，与 `MeshUtil` 的生成器保持一致。
static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, tint: Color,
		n: Vector3) -> void:
	var nn := n.normalized()
	if nn.length_squared() < 0.5:
		nn = Vector3.UP
	var plane := Plane(nn, 1.0)
	for p in [p0, p2, p1]:
		st.set_color(tint)
		st.set_normal(nn)
		st.set_tangent(plane)
		st.add_vertex(p)
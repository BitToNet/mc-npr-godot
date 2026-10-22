class_name SettlementMarker
extends Node3D

## 聚落的**微缩棋子**（S1.5b）。
##
## 三种聚落各有自己的轮廓，不靠颜色区分（GLOBAL 档只有几十像素，
## 红绿蓝三个点看不出"这是村庄还是要塞"）：
##
##   * 村庄 `village`  —— 圆台基座 + 3 座尖顶小屋（围一圈）+ 井 + 旗
##   * 城镇 `town`     —— 更大的台基 + 环形矮墙 + 4 座小屋 + 中央双层主楼 + 旗
##   * 要塞 `fortress` —— 台基 + 高圆塔 + 一圈垛口（8 个圆头垛）+ 锥顶 + 最高的旗
##
## 全部零件都是圆柱 / 圆锥 / 球这类**圆润多面体**，没有一个方块（美术规范硬约束：
## NO Voxels, NO Cubes）。零件用顶点色烘好颜色，再由 `MeshUtil.combine()` 合成
## **单一 mesh** —— 每枚棋子 1 次 draw call（加描边第二遍 = 2 次）。
##
## 势力归属色的**载体是屋顶、旗面与台基顶圈**，不是整枚棋子：整枚染色会让 20 枚棋子变成 20 个
## 色块，台基 / 墙 / 屋顶的层次反而消失。色槽统一在 `Style.FACTION_TINT_KEYS`
## （与玩家棋子同一张表，见 `party_marker.gd`），两处各写一份键序迟早会漂。
##
## 贴地：`place_at()` 把**台基底面**放到 `HeightField.height_at(x, z)`，所以网格的
## `min_y` 必须恒为 0（用例据此判"贴地"）。
##
## 本类只管画与贴地：不读输入、不推进时间、不写 `GameState`。范围判定在 `SettlementLayer`。

## 三型的轮廓参数（米）。高度是**棋子**尺寸，不是真实比例：
## GLOBAL 2600 m 跨度下村庄约 5 px、要塞约 12 px；LOCAL 170 m 下能看清屋顶与垛口。
## 层级关系必须可读：村庄 < 城镇 < 要塞。
const SPECS := {
	"village": {"height": 14.0, "base": 7.2},
	"town": {"height": 26.0, "base": 10.4},
	"fortress": {"height": 33.0, "base": 9.6},
}
const KINDS := ["village", "town", "fortress"]

## 台基顶面高度：`_parts_base()` 三段圆柱叠出来的实际结果（0.9 + 0.8 + 0.45）。
## 各型的"地面"零件都从这里往上坐 —— 改台基只改这一处，不会出现"房子陷进台基"。
const BASE_TOP := 0.9 + 0.8 + 0.45

## 只取常量与静态函数，不碰 autoload 实例（`--script` 模式下 `Style` 标识符不可见）。
const StyleDef := preload("res://scripts/core/style.gd")

## 贴地用的高度场；为 `null` 时地面按 0 处理（用例里总会给）。
var field: HeightField = null
var kind := "village"
var faction := 0
var settlement_id := ""

var _mesh_instance: MeshInstance3D
var _mesh: ArrayMesh
var _material: ShaderMaterial = null
var _injected_material: ShaderMaterial = null
var _built := false
## 用到的生成器名字（`tapered_cylinder` / `cone` / `blob` / `fin`）。用例靠它断言
## "这枚棋子确实没有引入方块类几何" —— 与 `box_mesh` 守卫互补：守卫扫源码，
## 这条断言扫**实际造出来的东西**。
var _generators: Array[String] = []


## 绑定高度场、种类、势力并建网格。`p_material` 可注入现成材质；为 `null` 时按名字
## 找 `Style` 单例。重复调用是幂等的。
func setup(p_field: HeightField, p_kind: String, p_faction: int, p_id: String,
		p_material: ShaderMaterial = null) -> void:
	field = p_field
	kind = p_kind if SPECS.has(p_kind) else "village"
	faction = int(p_faction)
	settlement_id = p_id
	_injected_material = p_material
	_built = false
	_build()


## 换势力色：会重建网格（颜色烘在顶点色里，不能只改材质）。
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


## 把基座底面贴到地形高度（局部坐标；父节点在原点）。离树也能跑（只用 `position`）。
func place_at(x: float, z: float) -> void:
	var bed := 0.0
	if field != null:
		bed = field.height_at(x, z)
	position = Vector3(x, bed, z)


func height() -> float:
	return float((SPECS[kind] as Dictionary)["height"])


func base_radius() -> float:
	return float((SPECS[kind] as Dictionary)["base"])


## 顶点色里的势力色（测试与报告用；与实际染色走同一个函数）。
func faction_tint() -> Color:
	return StyleDef.faction_tint(faction)


func faction_key() -> String:
	return StyleDef.faction_tint_key(faction)


## 一枚棋子的自述。`tris` 是**单遍**三角数（渲染器面数 = 2 × tris，因为描边第二遍）。
func metrics() -> Dictionary:
	var out := {
		"id": settlement_id,
		"kind": kind,
		"faction": faction,
		"faction_key": faction_key(),
		"height": height(),
		"base_radius": base_radius(),
		"position": position,
		"built": _built,
		"generators": _generators.duplicate(),
		"verts": 0,
		"tris": 0,
		"surfaces": 0,
		"min_y": 0.0,
		"size": Vector3.ZERO,
		"outline": false,
	}
	if _mesh == null or _mesh.get_surface_count() == 0:
		return out
	var aabb := _mesh.get_aabb()
	out["surfaces"] = _mesh.get_surface_count()
	out["size"] = aabb.size
	out["min_y"] = aabb.position.y
	# 合成后的 mesh 是非索引三角形汤：三角数 = 顶点数 / 3。
	out["verts"] = _mesh.surface_get_array_len(0)
	out["tris"] = int(out["verts"]) / 3
	out["smooth_verts"] = _count_smooth_verts()
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
	_generators.clear()
	_material = _make_material()
	var rng := _seeded_rng(settlement_id)
	var parts: Array = []
	match kind:
		"town":
			_parts_town(parts, rng)
		"fortress":
			_parts_fortress(parts, rng)
		_:
			_parts_village(parts, rng)
	_mesh = MeshUtil.combine(parts)
	# 描边必须靠连续的外壳：见 `MeshUtil.smooth_tangents()` 的说明。
	_mesh = MeshUtil.smooth_tangents(_mesh)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Body"
	_mesh_instance.mesh = _mesh
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_instance)


# --- 三型外形 ---------------------------------------------------------------

## 村庄：3 座小屋 + 水井 + 旗。占地最小、高度最矮（读作"一个聚落"）。
func _parts_village(parts: Array, rng: RandomNumberGenerator) -> void:
	var r := base_radius()
	var cream := _tint("cream")
	var stone := _tint("stone")
	var roof := _tint(faction_key())
	var roof_dark := roof * 0.84

	_parts_base(parts, r, _tint("plinth"), _tint("plinth_lip"), _tint(faction_key()), 14)
	# 三座小屋：120° 围一圈，半径略缩，避免屋顶互相咬合。
	for i in 3:
		var th := TAU * float(i) / 3.0 + deg_to_rad(90.0)
		var hx := cos(th) * r * 0.44
		var hz := sin(th) * r * 0.44
		var spin := rng.randf_range(-0.25, 0.25)
		var wall := _gen(MeshUtil.tapered_cylinder(1.95, 1.78, 4.0, 7, cream), "tapered_cylinder")
		parts.append(_part_rot(wall, Vector3(hx, BASE_TOP + 2.0, hz), Basis(Vector3.UP, th + spin)))
		var cap := _gen(MeshUtil.cone(2.6, 3.0, 6, true, roof), "cone")
		parts.append(_part_rot(cap, Vector3(hx, BASE_TOP + 5.5, hz), Basis(Vector3.UP, th + spin)))
		# 屋檐下一圈深色：GLOBAL 档只剩一个点，靠这条明暗差把屋顶从墙里拉出来。
		var eave := _gen(MeshUtil.cone(2.75, 0.55, 6, false, roof_dark), "cone")
		parts.append(_part_rot(eave, Vector3(hx, BASE_TOP + 4.18, hz),
				Basis(Vector3.UP, th + spin)))
	# 井：扁球 + 石色，中间那点亮色让"有人住"读得出来。
	var well := _gen(MeshUtil.blob(1.15, 2, 5, Vector3(1.0, 0.75, 1.0), 0.0, rng, stone), "blob")
	parts.append(_part(well, Vector3(0.0, BASE_TOP + 0.35, 0.0)))
	_parts_flag(parts, Vector3(0.0, BASE_TOP, -r * 0.66), 8.6, roof, 0.9)


## 城镇：环形矮墙 + 4 座小屋 + 双层主楼 + 高旗。明显比村庄"厚"。
func _parts_town(parts: Array, rng: RandomNumberGenerator) -> void:
	var r := base_radius()
	var cream := _tint("cream")
	var stone := _tint("stone")
	var roof := _tint(faction_key())
	var roof_dark := roof * 0.84

	_parts_base(parts, r, _tint("plinth"), _tint("plinth_lip"), _tint(faction_key()), 16)
	# 环形矮墙：不封顶（`cap_top=false`），否则主楼与小屋会坐在一块圆板上像"蛋糕"。
	var wall := _gen(MeshUtil.tapered_cylinder(r * 0.72, r * 0.68, 2.6, 10, stone,
			Vector2.ZERO, true, false), "tapered_cylinder")
	parts.append(_part(wall, Vector3(0.0, BASE_TOP + 1.3, 0.0)))
	var wall_top := BASE_TOP + 2.6
	# 4 座小屋：45° 起跳，避开正门方向。
	for i in 4:
		var th := TAU * float(i) / 4.0 + deg_to_rad(45.0)
		var hx := cos(th) * r * 0.55
		var hz := sin(th) * r * 0.55
		var spin := rng.randf_range(-0.2, 0.2)
		var house := _gen(MeshUtil.tapered_cylinder(1.7, 1.58, 3.4, 7, cream), "tapered_cylinder")
		parts.append(_part_rot(house, Vector3(hx, wall_top + 1.7, hz),
				Basis(Vector3.UP, th + spin)))
		var cap := _gen(MeshUtil.cone(2.3, 2.5, 6, true, roof), "cone")
		parts.append(_part_rot(cap, Vector3(hx, wall_top + 4.65, hz),
				Basis(Vector3.UP, th + spin)))
		var eave := _gen(MeshUtil.cone(2.42, 0.45, 6, false, roof_dark), "cone")
		parts.append(_part_rot(eave, Vector3(hx, wall_top + 3.54, hz),
				Basis(Vector3.UP, th + spin)))
	# 主楼：下段粗、上段收，顶部锥顶（势力色）。
	var lower := _gen(MeshUtil.tapered_cylinder(3.3, 2.95, 6.4, 8, cream), "tapered_cylinder")
	parts.append(_part(lower, Vector3(0.0, wall_top + 3.2, 0.0)))
	var mid_y := wall_top + 6.4
	var upper := _gen(MeshUtil.tapered_cylinder(2.95, 2.5, 2.8, 8, cream), "tapered_cylinder")
	parts.append(_part(upper, Vector3(0.0, mid_y + 1.4, 0.0)))
	var spire_y := mid_y + 2.8
	var spire := _gen(MeshUtil.cone(3.7, 4.4, 8, true, roof), "cone")
	parts.append(_part(spire, Vector3(0.0, spire_y + 2.2, 0.0)))
	_parts_flag(parts, Vector3(0.0, spire_y, 0.0), 7.0, roof, 1.0)


## 要塞：高圆塔 + 8 个圆头垛 + 锥顶 + 最高的一面旗。剪影最"瘦高"。
func _parts_fortress(parts: Array, rng: RandomNumberGenerator) -> void:
	var cream := _tint("cream")
	var stone := _tint("stone")
	var roof := _tint(faction_key())
	var roof_dark := roof * 0.84

	_parts_base(parts, base_radius(), _tint("plinth"), _tint("plinth_lip"), _tint(faction_key()), 14)
	# 主塔：下粗上收，塔身用石色，与奶油色墙裙形成上下两段。
	var drum := _gen(MeshUtil.tapered_cylinder(5.5, 4.9, 15.0, 10, stone), "tapered_cylinder")
	parts.append(_part(drum, Vector3(0.0, BASE_TOP + 7.5, 0.0)))
	# 墙裙：塔脚一圈奶油色，把塔"钉"在台基上（不然塔像浮着）。
	var skirt := _gen(MeshUtil.tapered_cylinder(5.9, 5.6, 2.4, 10, cream), "tapered_cylinder")
	parts.append(_part(skirt, Vector3(0.0, BASE_TOP + 1.2, 0.0)))
	var drum_top := BASE_TOP + 15.0
	# 8 个圆头垛：绕塔顶一圈。方垛会变成"方块"，所以用收口小圆柱。
	for i in 8:
		var th := TAU * float(i) / 8.0
		var merlon := _gen(MeshUtil.tapered_cylinder(0.62, 0.5, 1.6, 5, cream,
				Vector2.ZERO, false, false), "tapered_cylinder")
		parts.append(_part_rot(merlon, Vector3(cos(th) * 4.6, drum_top + 0.8, sin(th) * 4.6),
				Basis(Vector3.UP, th + rng.randf_range(-0.1, 0.1))))
	# 锥顶：比塔身细一圈，垛口才露得出来。
	var cap := _gen(MeshUtil.cone(3.5, 3.4, 10, true, roof), "cone")
	parts.append(_part(cap, Vector3(0.0, drum_top + 1.7, 0.0)))
	var eave := _gen(MeshUtil.cone(3.7, 0.5, 10, false, roof_dark), "cone")
	parts.append(_part(eave, Vector3(0.0, drum_top + 0.35, 0.0)))
	_parts_flag(parts, Vector3(0.0, drum_top + 3.4, 0.0), 7.5, roof, 1.1)


# --- 公共零件 ---------------------------------------------------------------

## 台基：两段收口圆柱 + 一圈顶面。底面正好在 y = 0（贴地就靠它）。
##
## 顶面那一圈（`pad`）是**势力色**，不是雪色。理由纯粹是"看不看得见"：REGION 档（700 m）
## 一枚棋子只有几十像素高，屋顶与旗面加起来不到 5% 的画面，势力色根本读不出来；而顶面
## 是从上往下看时**唯一一大块**面积（战略档相机永远是俯视），染它等于给每枚棋子画了
## 一圈阵营环 —— 造型层次（台基 / 墙 / 屋顶）一点没少，辨识度却从"看不见"变成"一眼"。
## 这也是 wargame 棋子底盘的通用做法，不是临时凑色。
func _parts_base(parts: Array, r: float, plinth: Color, lip: Color, pad: Color, seg: int) -> void:
	var lower := _gen(MeshUtil.tapered_cylinder(r, r * 0.94, 0.9, seg, plinth), "tapered_cylinder")
	parts.append(_part(lower, Vector3(0.0, 0.45, 0.0)))
	var upper := _gen(MeshUtil.tapered_cylinder(r * 0.94, r * 0.86, 0.8, seg, lip), "tapered_cylinder")
	parts.append(_part(upper, Vector3(0.0, 1.30, 0.0)))
	var disc := _gen(MeshUtil.tapered_cylinder(r * 0.84, r * 0.80, 0.45, seg,
			pad, Vector2.ZERO, false, true), "tapered_cylinder")
	parts.append(_part(disc, Vector3(0.0, 1.925, 0.0)))


## 旗：杆 + 杆顶球 + 一片"鳍"。
##
## WHY A FIN, NOT A CLOTH SLAB: 玩家棋子的旗面是厚 0.18 m 的薄布（三列两行网格 + 四边
## 墙，二十多个三角），那是本项目的招牌零件但也是最贵的之一。聚落有 20 枚，旗只需要在
## GLOBAL 档读出"这里有个势力色的小旗"，所以用**压扁的 4 面锥**当旗：轮廓是尖的、有厚度、
## 描边长得出，三角数是布旗的 1/5。两种旗的取舍登记在 ENGINEERING §9.21。
func _parts_flag(parts: Array, foot: Vector3, pole_h: float, tint: Color, scale: float) -> void:
	var pole := _gen(MeshUtil.tapered_cylinder(0.20 * scale, 0.15 * scale, pole_h, 4,
			_tint("hair"), Vector2.ZERO, false, false), "tapered_cylinder")
	parts.append(_part(pole, foot + Vector3(0.0, pole_h * 0.5, 0.0)))
	var finial := _gen(MeshUtil.blob(0.40 * scale, 2, 5, Vector3.ONE, 0.0,
			_seeded_rng(settlement_id + ":finial"), _tint("cream")), "blob")
	parts.append(_part(finial, foot + Vector3(0.0, pole_h + 0.12 * scale, 0.0)))
	# 旗面：锥尖朝 +X、沿 Z 压扁成薄片（4 面锥 = 4 个三角，不封底）。
	var fin := MeshUtil.cone(1.55 * scale, 4.4 * scale, 4, false, tint)
	var squashed := Basis(Vector3(0, 0, 1), deg_to_rad(-90.0)) \
			* Basis.from_scale(Vector3(1.0, 1.0, 0.11))
	parts.append(_part_xf(_gen(fin, "fin"), Transform3D(squashed,
			foot + Vector3(0.10, pole_h * 0.74, 0.0))))


## 切线槽里不等于面法线的顶点数。反向外壳必须靠平滑法线才连得成一张皮，用例据此断言
## 这一步真的做了（否则描边会炸成散三角片，正常线宽下完全看不见）。
func _count_smooth_verts() -> int:
	if _mesh == null or _mesh.get_surface_count() == 0:
		return 0
	var arr := _mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
	var total := 0
	for i in normals.size():
		if i * 4 + 2 >= tangents.size():
			break
		var st := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
		if st.distance_to(normals[i]) > 0.001:
			total += 1
	return total


## 记录生成器名字（用例断言"没有方块类几何"）。
func _gen(mesh: ArrayMesh, generator: String) -> ArrayMesh:
	if not _generators.has(generator):
		_generators.append(generator)
	return mesh


static func _part(mesh: ArrayMesh, at: Vector3) -> Dictionary:
	return {"mesh": mesh, "xform": Transform3D(Basis.IDENTITY, at)}


static func _part_rot(mesh: ArrayMesh, at: Vector3, rot: Basis) -> Dictionary:
	return {"mesh": mesh, "xform": Transform3D(rot, at)}


static func _part_xf(mesh: ArrayMesh, xf: Transform3D) -> Dictionary:
	return {"mesh": mesh, "xform": xf}


## 取调色板颜色（常量查表，不碰 autoload 实例）。
static func _tint(key: String) -> Color:
	var c: Color = StyleDef.PALETTE.get(key, Color.WHITE)
	return c.srgb_to_linear()


## 每枚棋子自己的抖动流：种子上叠 `settlement_id` 的 FNV-1a。
##
## WHY NOT `String.hash()`: 哈希实现随引擎版本可能变，而"同一 seed 两次构建逐字节一致"
## 是这条流水线的硬要求；FNV-1a 是我们自己写的，跨版本稳定。
static func _seeded_rng(p_id: String) -> RandomNumberGenerator:
	var h := 2166136261
	for i in p_id.length():
		h = ((h ^ p_id.unicode_at(i)) * 16777619) & 0xFFFFFFFF
	var rng := RandomNumberGenerator.new()
	rng.seed = int(h)
	return rng


## 材质：优先注入；否则按名字找 `Style` 单例。与玩家棋子同一套参数（同一种"手办感"）。
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
		"ink": 2.2,
	}) as ShaderMaterial


## autoload 实例只能运行时按名字取（`--script` 编译期没有 `Style` 标识符）。
static func _style_node() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Style")
	return null
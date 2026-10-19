extends Node3D
## S0.5 教材夹具 —— `docs/ART_PIPELINE.md` §2 那六张配图的**唯一来源**。
##
## 六个展台一字排开，`Capture` 用 `--at=<x,y,z>` 逐个对准（见 `capture.gd` 的
## `s0_5_samples` 批次）。相机、光照、时刻、曝光六张完全相同 —— 换了任何一项，
## 两张图的差异就归因不到"被破坏的那条规则"上，图也就当不了证据。
##
## ⚠️ 本文件**故意**包含被守卫禁止的写法
## ---------------------------------------------------------------------------
## `04_bad_box` 用 `BoxMesh`、`05_bad_pbr_tree` 用 `StandardMaterial3D` —— 这正是
## 两张违例反例要展示的东西，写不出来就拍不出来。它们已在 `tools/verify.gd` 的
## `GUARD_WHITELIST` 里逐条登记（含理由），守卫报告每次运行都会把这两行**显式
## 打印出来**，不会静默放过。
##
## 因此本目录（`res://scripts/dev`、`res://scenes/dev`）的硬约束是：
## **产品码一律不得引用**。`s0_5_doc_conventions` 用例对此做了双向断言：
##   ① 反向：除本夹具外，`res://scenes` / `res://scripts` 里没有任何文件引用 `dev/`；
##   ② 正向：本文件确实命中了 `box_mesh` / `standard_material` 两条规则 ——
##      否则"白名单里有两条"就变成了凭空多出来的豁免，而不是可解释的反例。
##
## 为什么不做成"运行时切一下材质"
## ---------------------------------------------------------------------------
## 违例反例必须是**真的**用了被禁的写法。若改成"合规网格 + 给材质打个光滑的补丁"，
## 读者看到的光滑效果就来自那个补丁，而不是 `StandardMaterial3D`，反例便不再对应
## 守卫拦得住的东西。

const SPACING := 18.0

## 展台表：顺序即 `s0_5_samples` 的镜头顺序，x 由 `_slot_x()` 从索引算出。
## `y` 是"让物件底面正好落在台面上"的抬升量（网格都是以自身原点为中心生成的）：
## 树干已经建在 y≈0 处，所以 0；球与方块是一半埋在地下，所以要抬半个高度。
const EXHIBITS := [
	{"name": "01_ok_tree", "y": 0.00},
	{"name": "02_ok_rock", "y": 0.78},
	{"name": "03_ok_ball", "y": 1.10},
	{"name": "04_bad_box", "y": 0.85},
	{"name": "05_bad_pbr_tree", "y": 0.00},
	{"name": "06_bad_smooth_ball", "y": 1.10},
]

var _rng: RandomNumberGenerator


func _ready() -> void:
	# 命名子流：展台网格的抖动只依赖 `("dev_art_samples", master_seed)`，
	# 与 terrain / scatter 抽了多少个数无关（§3.2「按 seed 派生子流」）。
	_rng = Rng.stream("dev_art_samples")
	_build_stage()
	_build_exhibits()


## 世界：天空 + 太阳。全部走产品码同一条路径（`DayNight` 是真类），这样配图的
## 曝光/色调与游戏内一致，不会出现"文档里好看、游戏里不是这样"。
##
## 刻意**不**铺一张大桌面：`sand` 是柠檬黄的高饱和色，铺满整个画面会把物体和
## 描边一起吃掉，两张图也就没法比较。每个展台单独一块圆角台座，背景留天空。
func _build_stage() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)

	var dn := DayNight.new()
	dn.name = "DayNight"
	add_child(dn)
	dn.add_to_group("day_night")
	dn.setup(sun, we)
	dn.set_time(0.42)
	dn.set_auto_cycle(false)

	var rig := CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.add_to_group("camera_rig")
	rig.mode = CameraRig.Mode.FREE


func _build_exhibits() -> void:
	# 同一份树网格给 01 与 05 共用：两图的差别只能来自材质。
	var tree := _tree_mesh()
	var rock := _rock_mesh()
	var ball := _ball_mesh()

	_exhibit("01_ok_tree", 0, tree, _good_material())
	_exhibit("02_ok_rock", 1, rock, _good_material())
	_exhibit("03_ok_ball", 2, ball, _good_material())
	_exhibit("04_bad_box", 3, _box_mesh(), Style.toon({"tint": Style.pal("stone")}))
	_exhibit("05_bad_pbr_tree", 4, tree, _bad_pbr_material())
	_exhibit("06_bad_smooth_ball", 5, _smooth_ball_mesh(),
			Style.toon({"tint": Style.pal("stone")}))


## ---------------------------------------------------------------------------
##  合规样板（01 / 02 / 03）
## ---------------------------------------------------------------------------
## 合规材质：与 `scripts/world/scatter.gd` 同一套参数 —— 3 阶硬光 + 反向外壳描边。
func _good_material() -> ShaderMaterial:
	return Style.toon({
		"shade_min": 0.40, "rim": 0.22, "rim_color": Color(1.0, 0.98, 0.85), "ink": 2.0,
	})


## 树：树干 + 三团叶冠。与 `scatter.gd::_broadleaf_mesh()` 同一套构造，
## 只是这里逐字写开，好让文档能一段一段指着讲。**注意 `facet()` 与 `roughen()`
## 的顺序**：先合并、再 roughen（`roughen` 内部会 `facet_rebuild`，重算法线）。
func _tree_mesh() -> ArrayMesh:
	var trunk := MeshUtil.tapered_cylinder(0.19, 0.12, 1.75, 6,
			Style.lit("trunk"), Vector2(0.09, -0.05))
	var leaf := Style.lit("leaf")
	var leaf_dark := Style.lit("leaf_dark")
	var c0 := MeshUtil.blob(1.06, 6, 9, Vector3(1.06, 0.86, 1.0), 0.07, _rng, leaf)
	var c1 := MeshUtil.blob(0.74, 5, 8, Vector3(1.0, 0.9, 1.0), 0.06, _rng, leaf_dark)
	var c2 := MeshUtil.blob(0.66, 5, 8, Vector3(1.0, 0.92, 1.0), 0.06, _rng, leaf)
	var mesh := MeshUtil.combine([
		{"mesh": trunk, "xform": Transform3D(Basis(), Vector3(0.0, 0.87, 0.0))},
		{"mesh": c0, "xform": Transform3D(Basis(), Vector3(0.0, 2.42, 0.0))},
		{"mesh": c1, "xform": Transform3D(Basis(), Vector3(0.72, 2.06, 0.34))},
		{"mesh": c2, "xform": Transform3D(Basis(), Vector3(-0.66, 2.18, -0.42))},
	])
	return MeshUtil.roughen(mesh, 0.035, _rng, false)


## 石头：两团 `blob()` 叠在一起，`roughen(lock_bottom=true)` 让底面仍是平的。
func _rock_mesh() -> ArrayMesh:
	var stone := Style.lit("stone")
	var stone_dark := Style.lit("rock_dark")
	var a := MeshUtil.blob(1.0, 6, 9, Vector3(1.15, 0.78, 1.0), 0.10, _rng, stone)
	var b := MeshUtil.blob(0.62, 5, 8, Vector3(1.0, 0.7, 1.0), 0.09, _rng, stone_dark)
	var mesh := MeshUtil.combine([
		{"mesh": a, "xform": Transform3D(Basis(), Vector3(0.0, 0.0, 0.0))},
		{"mesh": b, "xform": Transform3D(Basis(), Vector3(0.72, 0.12, 0.30))},
	])
	return MeshUtil.roughen(mesh, 0.05, _rng, true)


## 球：`blob()` 已经是面着色网格（`_tri()` 逐三角写死法线），是"最省事的合规件"。
func _ball_mesh() -> ArrayMesh:
	return MeshUtil.blob(1.1, 7, 12, Vector3.ONE, 0.06, _rng, Style.lit("stone"))


## ---------------------------------------------------------------------------
##  违例反例（04 / 05 / 06）
## ---------------------------------------------------------------------------
## ⚠️ 反例 1：立方体。AGENTS.md §一 的第一条禁令，守卫规则 `box_mesh` 拦它。
## 材质仍用 toon，好让读者明白"问题只在形状"，不是所有毛病一起犯。
func _box_mesh() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(1.7, 1.7, 1.7)
	return box


## ⚠️ 反例 2：`StandardMaterial3D`。守卫规则 `standard_material` 拦它。
## 保留顶点色，好让颜色与 01 一致 —— 两图唯一的差别就是着色管线：
## 没有 3 阶阶梯、没有反向外壳描边、带真实高光。
func _bad_pbr_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.roughness = 0.32
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.rim_enabled = false
	return m


## ⚠️ 反例 3：`SphereMesh` —— 索引网格 + 平滑法线，**没有**过 `MeshUtil.facet()`。
## 守卫抓不到这一类（它不是某一类节点，而是"少调了一次函数"），只能靠眼睛与
## 文档 §2.2 的检查清单。所以它必须以对照组的身份出现，而不是被守卫兜住。
func _smooth_ball_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 1.1
	s.height = 2.2
	s.radial_segments = 32
	s.rings = 16
	return s


## ---------------------------------------------------------------------------
##  摆放
## ---------------------------------------------------------------------------
func _exhibit(which: String, slot: int, mesh: Mesh, mat: Material) -> void:
	var y := float(EXHIBITS[slot]["y"])
	var x := _slot_x(slot)
	assert(String(EXHIBITS[slot]["name"]) == which,
			"展台表与摆放调用的顺序不一致：%s vs %s" % [EXHIBITS[slot]["name"], which])
	# 每个展台一块小圆角台座：既接住投影，又不让高饱和底色铺满画面。
	var top := Style.lit("sand")
	var bottom := Style.lit("plinth").darkened(0.30)
	_prop(which + "_plinth",
			MeshUtil.superellipse_prism(1.75, 1.75, -0.50, 0.0, 4.0, 5, top, bottom, 1.06),
			Style.toon({"shade_min": 0.46, "rim": 0.10, "ink": 2.2}),
			Vector3(x, 0.0, 0.0))
	_prop(which, mesh, mat, Vector3(x, y, 0.0))


## `Capture --at=` 的 y 分量由各展台主体的高度决定，坐标从 `_slot_x()` 取；
## 两处都从这里算，避免"改了间距但只改了一边"。
func _slot_x(slot: int) -> float:
	return (float(slot) - float(EXHIBITS.size() - 1) * 0.5) * SPACING

func _prop(node_name: String, mesh: Mesh, mat: Material, at := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi

extends SceneTree
## =============================================================================
##  tools/verify.gd — Pocket Sandbox A- / C- 类验收运行器（S0.2 交付物）
## =============================================================================
##  用法（与 docs/ROADMAP.md §3.4 一致）：
##
##    # 单个用例（headless，退出码 0=全绿 / 1=有失败 / 2=用法错误）
##    Godot --headless --path <proj> --script res://tools/verify.gd -- --case=s0_2_guard
##
##    # 全部用例（headless：kind="headed" 的用例自动跳过并记原因，不算失败）
##    Godot --headless --path <proj> --script res://tools/verify.gd -- --all
##
##    # 全部用例（窗口模式：C- 类性能用例才会真正执行）
##    Godot           --path <proj> --script res://tools/verify.gd -- --all
##
##    # 列出用例  /  指定报告目录
##    ... -- --list        ... -- --all --out=res://.verify
##
##  报告：<out>/<case>.json，含每条断言、逐条耗时、引擎版本、可执行文件路径。
##  聚合报告：<out>/_all.json。
##
## -----------------------------------------------------------------------------
##  ⚠️ 实测硬约束（S0.2 探针结论，改动前先复现探针，勿凭直觉改）
## -----------------------------------------------------------------------------
##  1) 本脚本以 `--script` 方式充当 MainLoop。该模式下 autoload 的**标识符不可
##     编译**（`SCRIPT ERROR: Compile Error: Identifier not found: Style`），
##     尽管 autoload 节点确实已经挂在 root 上。
##     ⇒ 本文件内**禁止**书写 `Style.xxx` / `Capture.xxx`；
##       必须 get_root().get_node_or_null("Style") 动态取用。
##  2) 全局 class_name（MeshUtil / Terrain / InputSetup / …）在本模式下正常可用。
##  3) 场景用例模式 = instantiate 夹具场景（diorama）+ add_child + await process_frame；
##     实测可行（世界会正常生成），不需要子进程 hack。
##     注意：add_child 之后**必须** await 一帧再查节点组，否则组注册可能未完成。
##  4) headless 下没有任何渲染指标（RENDER_* 恒为 0，TIME_FPS 恒为 1），
##     所以 kind="headed" 的用例在 headless 下只能跳过，**不得**判为失败。
##  5) 每个 `_case_*` 函数必须以 `await process_frame` 开头：分发器统一用
##     `await _case_xxx()`，若某函数不是协程，Godot 会直接报错。
## =============================================================================

const REPORT_DIR := "res://.verify"

## 产品主场景路径（S1.0d 起）＝ 路由 `world` 的目标：战略图（S1.2b 起有地形，仍无相机）。
##
## 为什么在这里留一个字面量而不是从 `SceneRouter` 读：本文件要能**独立**发现
## "路由表改了、测试没改"和"测试改了、路由表没改"两种漂移。若两边共读一个源，
## 任何一边被改都会一起跟着走，断言就永远绿。
## 真正不依赖字面量的交叉校验是 `_case_router` 里的 `run/main_scene` 断言。
const WORLD_SCENE := "res://scenes/world/strategic_map.tscn"

## 演示岛。S1.0d 起它**不再是路由**，只是回归夹具：6 机位 `B-` 与内容用例直接加载它，
## 取景则只能走 `capture.gd --scene=`。同样留字面量，才能独立发现"夹具被顺手换掉/删掉"。
const DIORAMA_SCENE := "res://scenes/dev/diorama.tscn"

## 自旋固定微秒数，返回实际耗时（毫秒）。用于给"量法分辨率"做标尺。
func _spin_us(usec: int) -> float:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < usec:
		pass
	return float(Time.get_ticks_usec() - t0) / 1000.0


## 直接量叠加层**自己**每帧的 CPU 成本（毫秒/帧）。
##
## 为什么不用"开层/关层的帧时间差"：实测（2026-10-19）这条路在本工程里没有分辨率 ——
## vsync 开着时差值是**负**的（关层 18.75 / 开层 17.84 ms，量到的是 vsync 等待+抖动）；
## 关掉 vsync 改用逐帧墙钟后，注入一个确定的 2ms/帧 自旋负载，只回收 41%（量到 0.82ms）。
## 也就是说帧时间差对 0.5ms 量级既测不准也测不出，拿它写断言等于没写。
##
## 改为把叠加层的每帧工作**单独计时**：`_push_sample()` 每帧一次，`_refresh()` 每
## `REFRESH_EVERY` 帧一次，与 `_process()` 的真实节奏一致。这是可归因的成本，
## 不掺 vsync、不掺其它节点的抖动。
func _time_overlay_frame(dbg: Node, frames: int) -> float:
	for i in 3:   # 预热：首次 Label 排版/字体缓存不计入
		dbg.call("_push_sample")
		dbg.call("_refresh")
	var t0 := Time.get_ticks_usec()
	for i in frames:
		dbg.call("_push_sample")
		if i % 6 == 0:
			dbg.call("_refresh")
	var dt := float(Time.get_ticks_usec() - t0)
	return dt / float(maxi(frames, 1)) / 1000.0

## 用例注册表。kind：pure = headless 可跑；headed = 需要真实 GPU/窗口。
## hidden：不参与 --all（供本文件自检使用的诊断用例）。
const CASES := {
	"s0_2_selfcheck": {
		"desc": "断言库自检：通过/失败用例的退出码契约 + JSON 报告字段完整性",
		"kind": "pure",
	},
	"s0_2_imgdiff": {
		"desc": "img_diff：同图 0.0000% / 改动副本 > 0% / 尺寸不一致显式失败",
		"kind": "pure",
	},
	"s0_2_guard": {
		"desc": "规范守卫：8 类违例各自可捕获 + 既有代码无未登记违例",
		"kind": "pure",
	},
	"s0_2_boot": {
		"desc": "开机场景（战略图：地形 + 无相机）headless 启动 60 帧，退出码 0 且日志无 ERROR/SCRIPT ERROR",
		"kind": "pure",
	},
	"s0_2_scene_api": {
		"desc": "场景用例模式：加载 diorama 夹具 + await，19 个既有公开 API 符号可解析",
		"kind": "pure",
	},
	"s0_2_baseline": {
		"desc": "性能基线：FPS/ms-per-frame/内存/三角面 四项 + 连续 3 次采样方差 < 5%",
		"kind": "headed",
	},
	"s0_2_probe_pass": {
		"desc": "[诊断] 全通过用例，供 selfcheck 验证『退出码 0』",
		"kind": "pure",
		"hidden": true,
	},
	"s0_2_probe_fail": {
		"desc": "[诊断] 故意失败用例，供 selfcheck 验证『退出码 1』",
		"kind": "pure",
		"hidden": true,
	},
	"s0_6_clock": {
		"desc": "可复现时钟：确定性模式 t==frame/hz、实时模式随 delta 前进、reset 归零、全局着色器参数被注册",
		"kind": "pure",
	},
	"s0_6_repro": {
		"desc": "可复现渲染：两个独立进程同参数截图 sha256 相同 + 反向对照（改参数/改帧数）必须不同",
		"kind": "headed",
	},
	"s1_0_scene_arg": {
		"desc": "capture.gd 的 --scene=res://…：同参两次独立进程逐位一致；缺省（战略图：地形、无相机）"
				+ "与 --scene=diorama 的哈希组必须不同；反向对照（battle_stub 与两者都不同）"
				+ "哈希必变；清单自报 scene；坏路径退出码 1；只带 --scene= 不触发批次也不抢退出码；"
				+ "守卫属主清单没有放宽",
		"kind": "headed",
	},
	"s1_0_routes": {
		"desc": "S1.0d 路由收口：两条路由（world→战略图 / battle）且路径真实存在、path↔route "
				+ "双向映射唯一（diorama 不再回指任何路由）、strategic_map.tscn 可实例化（S1.2a 起挂入口脚本）"
				+ "（Node3D / 零子节点 / 入口脚本 / 无相机）、run/main_scene 同步、MAX_DEPTH 仍为 2、"
				+ "没有 goto_strategic()，且『已在 world 再 goto_world()』被拒后路由栈/屏幕/实例数零变化",
		"kind": "pure",
	},
	"s1_0_migration": {
		"desc": "S1.0d 迁移闭环：路由 world → 文件 → 场景根类（Node3D/StrategicMap/入口脚本/零子节点）"
				+ "三者一致；run/main_scene 已改指且 diorama 退居可加载的回归夹具；"
				+ "引擎直接加载的战略图被 _sync() 认领为 world，此时 goto_world() 被拒且不重载同一文件",
		"kind": "pure",
	},
	"s0_4_overlay": {
		"desc": "调试观测层契约：叠加层默认隐藏、F3/F1 只改观测不改世界（结构指纹+Rng 状态逐项不变）、"
				+ "F1 后画面与『无 UI』基线逐位相同、发布构建热键闸门真的删 action、CSV 两进程逐位一致且 --obs-csv= 不触发截图",
		"kind": "pure",
	},
	"s0_4_cost": {
		"desc": "调试层开销：120 实体场景下直接给叠加层每帧工作计时（_push_sample 每帧 + _refresh 每 6 帧）"
				+ " < 0.5ms，并用 0.5ms/2ms 自旋标尺证明这套计时可分辨该量级；"
				+ "反向对照『开层后 draw_calls 必须上升』；外加 B- 两张截图两轮逐位一致且互不相同",
		"kind": "headed",
	},
	"s0_4_quick": {
		"desc": "快存/快读（F5/F9）：仍写 9 个真槽位、不新增隐藏槽位与旁路文件；"
				+ "空槽位直写不弹菜单、已占用必须先按两次（§3.5 的覆盖确认不被绕过）、"
				+ "无当前槽位时拒绝并说明；发布构建闸门删 action 后按键完全无反应；"
				+ "菜单调试页只读事实与 Debug 同源",
		"kind": "pure",
	},
	"s0_3_state": {
		"desc": "全局服务契约：autoload 3→9 与注册顺序、逻辑步 60Hz 精确前进、Rng 子流可复现且互不干扰、EventBus 5 信号、snapshot/restore 容错",
		"kind": "pure",
	},
	"s0_3_roundtrip": {
		"desc": "存档跨进程往返：子进程写 → 父进程逐字段比对 → 另一子进程读回；覆盖需二次确认、空槽位与越界被拒、九宫格卡片数据齐全",
		"kind": "pure",
	},
	"s0_3_dirty": {
		"desc": "脏存档容错：非法 JSON / 数组根 / 高版本 / 无迁移路径 / 缺 game 段一律拒读不崩；缺失·未知·类型错误字段告警且保留当前值；v0→v1 迁移钩子真能跑",
		"kind": "pure",
	},
	"s0_3_atomic": {
		"desc": "原子写：跨进程并发写同一槽位 800 次，每个读得出来的样本都是完整合法 JSON（绝无半截）；引擎 replace 的非原子窗口由读者重试吸收；rename 被占用时失败、原档不变、不留 .tmp",
		"kind": "pure",
	},
	"s0_3_no_autosave": {
		"desc": "无自动存档：启动 + 世界重建 + 五种全局事实后，user://saves 全部文件哈希与 mtime 零变化（且该检查确实能检出显式存档）",
		"kind": "pure",
	},
	"s0_3_router": {
		"desc": "场景路由：world→battle→world 后世界节点数 ±0 且结构指纹逐条一致；栈深上限与越界显式拒绝；场景被外部换掉后路由栈不再撒谎",
		"kind": "pure",
	},
	"s0_3_slots": {
		"desc": "存档菜单与九宫格：ESC 暂停契约（世界停、菜单与 Clock 不停）、九卡正文逐个==服务 label、无当前槽位走『保存等同另存为』、空槽位直写、B- 四张截图两轮逐位一致且两两不同",
		"kind": "headed",
	},
	"s0_3_overwrite": {
		"desc": "覆盖二次确认：整页弹窗先问后写、弹窗期间与取消后旧档 sha256+mtime 逐项不变、确认后才覆盖、ESC 层级（弹窗→宫格→主页→关闭）",
		"kind": "headed",
	},
	"s0_3_probe_write": {
		"desc": "[打桩] 新游戏 → 存槽 3，供 s0_3_roundtrip 以子进程拉起",
		"kind": "pure",
		"hidden": true,
		"probe": true,
	},
	"s0_3_probe_read": {
		"desc": "[打桩] 读槽 3 → 回吐快照 JSON，供 s0_3_roundtrip 以子进程拉起",
		"kind": "pure",
		"hidden": true,
		"probe": true,
	},
	"s0_3_probe_loop": {
		"desc": "[打桩] 连续写同一槽位 ATOMIC_WRITES 次，供 s0_3_atomic 并发观测",
		"kind": "pure",
		"hidden": true,
		"probe": true,
	},
	"s0_5_doc_conventions": {
		"desc": "文档契约：两份文档的每条约定都能在代码里定位（反向用编造的锚点证明不假绿）；"
				+ "教材夹具的双向约束（产品码不引用 scripts/dev + 夹具命中数恰等于白名单登记数）；"
				+ "6 张教材截图存在且 sha256 与 s0_5_samples 批次清单一致",
		"kind": "pure",
	},
	"s1_1_canon": {
		"desc": "Canon 规范化序列化：键按码点升序（乱序插入也必须排好）/ 整数值写整数、非整数 %.6f / "
				+ "2 空格缩进 + LF + 恰好一个结尾换行、无 BOM / 字符串转义可回读 / "
				+ "顶层 schema 必填 / 不支持的值（Color/Vector3/非字符串键/NAN/自引用）fail-fast 且报出键路径 / "
				+ "两次序列化逐位一致 + 读回再写幂等；反向对照：手写未排序 JSON ≠ Canon 输出",
		"kind": "pure",
	},
	"s1_1_params": {
		"desc": "gen_params.json 参数表：表文件本身是 Canon 规范形式、默认值 = ROADMAP 初值且在安全区间内 / "
				+ "越界 clamp + 告警 / 类型错误回退默认 / regions_min>max 修正 / 聚落总数上下钳制 / "
				+ "未知键与缺键告警 / 高版本 schema 整表拒读 / 坏文件回退默认不崩、不写 user://",
		"kind": "pure",
	},
	"s1_1_height": {
		"desc": "战略尺度高度场：同 seed 两实例 5 625 点逐位相同、换 seed 95% 以上点变 / "
				+ "中心陆地四角是海、海岸线穿越、值域与归一化合法 / slope_at 可手算复核 / "
				+ "biome 分层且都在合法集合内 / 改 hill_amplitude 后 400/400 点必变且 max_height 同步",
		"kind": "pure",
	},
	"s1_1_regions": {
		"desc": "region 划分：数量落在 regions_min..max、id 稠密无空洞 / 每个陆地格恰属一个 region、"
				+ "水格 owner=-1、面积和 = 陆地格数×32² / 中心回到自己的 region / "
				+ "重放同一 Rng 状态逐格相同、换 seed 必变 / 一次 build 的耗时",
		"kind": "pure",
	},
	"s1_1_world": {
		"desc": "世界数据：聚落配额（12 村 + 4 镇 + 4 要塞）全放出且零告警 / 每个聚落与队伍都在陆地、"
				+ "坡度合法、聚落两两间距达标 / 道路图单连通（删一条边即断）且总长可累加 / "
				+ "3 个锚点坐标逐位等于表、排在最前 / 同 seed 两次构建指纹逐位相同、换 seed 必变 / "
				+ "间距不可行时降级为告警而不是死循环 / 锚点落水或 kind 非法时跳过并告警 / 一次 build 的耗时",
		"kind": "pure",
	},
	"s1_1_gen": {
		"desc": "序列化：同 seed 两次构建文本逐字节相同 / Canon 规范形式（无 CR、末尾单换行、读回再写幂等）/"
				+ "顶层键码点升序 / 20 聚落 + 24 道路 + 3 势力 + 24 队伍按稳定键排序 / 锚点坐标逐位落进文本 / "
				+ "指标与内存一致 / 换 seed 文本不同 / 整条生成链 < 800 ms（C-）",
		"kind": "pure",
	},
	"s1_1_variety": {
		"desc": "换 seed 后宏观指标真的变化：三个 seed 两两文本不同；海岸线长度 / region 面积分布 / "
				+ "道路总长 / 聚落按 region 分布 四项里至少 3 项随 seed 动；并显式记录"
				+ "「聚落数恒为 20，不能当变化指标」",
		"kind": "pure",
	},
	"s1_2_boot": {
		"desc": "世界入口：`WorldSession.boot()` 先按 seed 重置 Rng 再建世界 ⇒ 同 seed 两次 boot 文本"
				+ "逐字节相同；先往 world_gen 子流里多抽 200 个数再 boot，结果不变（这是 S1.1d 前置缺陷的"
				+ "反向对照）；换 seed 文本必变；boot 出的世界与 `_world_fixture()` 逐字节一致；"
				+ "`strategic_map.tscn` 实例化后 session 非空、零告警、20 聚落；失败路径不抛异常",
		"kind": "pure",
	},
	"s1_2_mesh": {
		"desc": "战略地形网格：32 m 网格 / 75×75 格 ⇒ 11 250 三角（C- 上限 34 611 的 1/3）；"
				+ "6×6 分块（36 块陆 + 36 块水 + 外缘裙边）；水面只覆盖水下格、顶点色带泡沫衰减；"
				+ "顶点全部有限且落在 ±1200 m 地图内；两次 build 逐字节一致；换 seed 几何必变；"
				+ "场景接线后地形 + 舞台 + 相机全部就位且仍是 11 250 三角",
		"kind": "pure",
	},
	"s1_2_camera": {
		"desc": "战略镜头三档：2600 / 700 / 170 m 垂直跨度，GLOBAL 锁正交等距且焦点锁中心；"
				+ "600 帧脚本轨迹（右移 → 第 200 帧进区域档 → 第 400 帧转 yaw）逐帧断言无 NaN、"
				+ "焦点不越界、帧间位移 ≤ 视野×0.35×dt×1.35、相机不低于地形 3 m；同脚本两次轨迹"
				+ "哈希一致、反向平移不同；场景接线后相机 current、舞台固定正午",
		"kind": "pure",
	},
	"s1_3_party": {
		"desc": "队伍棋子本体（S1.3a）：12 个圆柱/球/旗面零件合成单一 mesh（1 个 draw call、"
				+ "非索引三角形汤），标称 22 m、脚底落在 y=0；反向外壳描边挂在 next_pass 且 enabled=1，"
				+ "切线槽写入平滑法线（否则外壳炸成散三角片、描边不可见）；100 个定种子采样点的落点"
				+ "高度恒等于 height_at（正负偏差都有），配合 min_y=0 才算贴地；四方向朝向含 ±π 回绕、"
				+ "facing 恒在 (−π, π]；4 个阵营换色不重建几何；两次构建逐字节一致",
		"kind": "pure",
	},
	"s1_2_perf": {
		"desc": "战略图分档帧率（C-）：vsync 关闭下三档（2600 / 700 / 170 m）平均帧率均 ≥ 60 fps，"
				+ "全球档三角面 = 16 920 且不超 34 611 上限、绘制调用 ≤ 120；反向对照『隐藏地图后"
				+ "帧率 > 最慢档 × 1.5』证明采样器能分辨地图与空天空；外加 B- 取景工具接线"
				+ "（--seed= / --tier= 的 build() 真的换了世界与档位）",
		"kind": "headed",
	},
}

## -----------------------------------------------------------------------------
##  规范守卫（§3.1.8 / §5 S0.2）
## -----------------------------------------------------------------------------
const GUARD_SCAN_DIRS := ["res://scenes", "res://scripts", "res://shaders"]
const GUARD_EXTS := ["gd", "tscn", "tres", "gdshader", "shader"]

## 裸随机函数：禁止全局 randf()/randi()（含 _range 变体）；
## `rng.randf()` 这种成员调用是允许的（§3.2「所有随机走 Rng 服务」）。
const BARE_RAND_FUNCS := ["randf", "randi", "randf_range", "randi_range"]

## 白名单：既有文件中已存在、本步不扩大改动面的命中项（§3.2「既有文件不重写」）。
## 每条必须写清理由；守卫报告会**显式列出**命中白名单的行，不静默放过。
const GUARD_WHITELIST := [
	{
		"path": "res://scripts/core/main.gd",
		"rule": "bare_randi",
		"reason": "演示场景的『随机重生成』交互（main.gd:48 auto_new_seed_on_start、"
				+ "main.gd:89 _on_regenerate 的 randi()）。属 §3.2 既有文件不重写范围，"
				+ "S0.2 不扩大改动面；后续新增模块（core/world/actors/battle/legion）"
				+ "一律不得再引入裸 randi()，必须走 Rng 服务。",
	},
	{
		"path": "res://scripts/core/capture.gd",
		"rule": "unfreezable_time",
		"reason": "capture.gd 的 Time.get_ticks_usec() 只用于 _benchmark 的墙钟计时窗口"
				+ "（性能探针本身就该量真实时间），不参与任何画面动画。"
				+ "S0.6 禁止的是『驱动画面运动的时间』走不可冻结的来源；"
				+ "测量用墙钟属正当用法，故登记而不改写。",
	},
	{
		"path": "res://scripts/world/terrain.gd",
		"rule": "unfreezable_time",
		"reason": "terrain.gd 的 Time.get_ticks_msec() 只用于统计 stats[\"gen_ms\"]"
				+ "（生成耗时，只写进日志与 stats 字典），不参与任何画面动画。"
				+ "同 capture.gd，属测量用墙钟的正当用法。",
	},
	{
		"path": "res://scripts/dev/art_samples.gd",
		"rule": "box_mesh",
		"reason": "S0.5 教材夹具的**违例反例** `04_bad_box`：`docs/ART_PIPELINE.md` §2 要用"
				+ "一张真的立方体截图讲清 AGENTS.md §一「严格禁止立方体」。反例必须真的"
				+ "使用被禁写法，否则读者看到的是补丁的效果而不是禁令的效果。"
				+ "该目录的硬约束（由 `s0_5_doc_conventions` 断言）：产品码一律不得引用"
				+ " `scripts/dev/`，且本文件命中数必须恰为下列登记项。",
	},
	{
		"path": "res://scripts/dev/art_samples.gd",
		"rule": "standard_material",
		"reason": "同一份夹具的违例反例 `05_bad_pbr_tree`：与 `01_ok_tree` 共用同一份网格、"
				+ "同一机位、同一时刻，唯一差别是材质换成 `StandardMaterial3D`"
				+ "（光滑渐变、真实高光、无逆壳描边），用来对照讲清 §一.2「全局 toon 阶梯」。"
				+ "登记理由同 `box_mesh` 那条。",
	},
]

## S0.6：不可冻结的时间来源。凡驱动**画面运动**的时间都必须走 Clock
## （scripts/render_clock.gd）；这两类来源永远无法让截图逐位复现：
##   * 着色器内建 `TIME` —— 真实引擎时间，`Engine.time_scale` 之外无接口可注入；
##   * GDScript 的 `Time.get_ticks_msec/usec()` —— 墙钟，连 time_scale 都够不着。
## 测量用墙钟（性能探针、生成耗时统计）是正当用法，走上面的白名单登记。
const UNFREEZABLE_SHADER_TOKEN := "TIME"
const UNFREEZABLE_SCRIPT_TOKENS := ["Time.get_ticks_msec", "Time.get_ticks_usec"]

## S0.3 批次 3：场景切换的所有权。`change_scene_to_file()` 会把当前场景从所有系统
## 脚下抽走，是全局副作用；§3.2 约定「只有 `SceneRouter` 能切场景」，否则
## 「屏幕为什么变了」将无法定位。这条规则是本仓库第一条**按文件路径**放行的规则：
## 命中者只要不是下面登记的属主文件就是违例。
const SCENE_CHANGE_TOKENS := [
	"change_scene_to_file", "change_scene_to_packed",
	"reload_current_scene", "unload_current_scene",
]
const SCENE_CHANGE_OWNERS := ["res://scripts/core/scene_router.gd"]

## -----------------------------------------------------------------------------
##  S0.3 批次 2（SaveSystem）常量
## -----------------------------------------------------------------------------
## 用例期间把 `user://saves` 整体换名为 `user://saves.bak`——探针实测引擎的目录
## 换名可用（目标必须不存在），因此验收不会碰玩家真实存档，产品码里也不留后门。
const SAVES_DIR := "user://saves"
const SAVES_BAK := "user://saves.bak"
const ROUNDTRIP_SLOT := 3
const ATOMIC_SLOT := 9
const ATOMIC_WRITES := 800
## 子进程写档时用的可辨识状态；父进程逐字段比对这几个数。
const PROBE_SEED := 4242
const PROBE_TIME := 123.5
const PROBE_MONEY := 40
const PROBE_FOOD := 7
const PROBE_SUPPLY := 3
const PROBE_SCENE_KIND := 1
const PROBE_POS := Vector3(1.25, 2.5, -3.75)
## 子进程 B 把读回的快照落成文件而不是塞进 stdout。实测：子进程 stdout 里的中文
## 被控制台按非 UTF-8 解码成乱码（`无名军团` → `鏃犲悕鍐涟`），而存档文件本身是对的。
## 所以跨进程回吐走 UTF-8 文件，stdout 只留纯 ASCII 的状态行。
const PROBE_SNAPSHOT_FILE := "_probe_read_snapshot.json"
## 狂写子进程自己的统计。`OS.create_process` 下子进程**不继承** stdout（实测：子进程
## 的 print 一行都没进父进程日志），所以子进程的话必须落成文件才拿得到。
const PROBE_LOOP_FILE := "_probe_loop_summary.json"

## -----------------------------------------------------------------------------
##  S0.3 批次 4（存档菜单 / 九宫格）常量
## -----------------------------------------------------------------------------
## 菜单节点名与界面路径。路径是**相对菜单节点**的，包含它自己的 `Root` 包装层
## （`menu_page.gd` 用一个 `Root` 控件承载整屏 Backdrop，好让点击落在菜单外面时
## 被它吃掉，不会穿透到调试 HUD 上）。
const MENU_NODE := "MenuLayer"
const MENU_PATHS := {
	"home": "Root/Home/Panel/Col",
	"save": "Root/Home/Panel/Col/Actions/Save",
	"save_as": "Root/Home/Panel/Col/Actions/SaveAs",
	"load": "Root/Home/Panel/Col/Actions/Load",
	"settings": "Root/Home/Panel/Col/Actions/Settings",
	"resume": "Root/Home/Panel/Col/Actions/Resume",
	"status": "Root/Home/Panel/Col/Slot",
	"grid": "Root/GridPage/Panel/Col/Grid",
	"grid_hint": "Root/GridPage/Panel/Col/Hint",
	"back": "Root/GridPage/Panel/Col/Back",
	"confirm_title": "Root/Confirm/Center/Panel/Col/Title",
	"confirm_detail": "Root/Confirm/Center/Panel/Col/Detail",
	"confirm_yes": "Root/Confirm/Center/Panel/Col/Row/Yes",
	"confirm_no": "Root/Confirm/Center/Panel/Col/Row/No",
}

## -----------------------------------------------------------------------------
##  运行时状态
## -----------------------------------------------------------------------------
var _opt_case := ""
var _opt_all := false
var _opt_list := false
var _opt_out := REPORT_DIR

## 打桩用例（probe）自报的退出码。 -1 = 未设置。
## 打桩用例不走 `_run_one` 的汇总逻辑，否则汇总里的 quit() 会覆盖它们的退出码，
## 而退出码正是父用例唯一的返回通道。
var _probe_exit := -1

var _started := false
var _finished := false
## 早退标记：_initialize 里 quit() 之后 Godot 仍会调用一次 _process，
## 若不拦住就会把 --list / 用法错误当成一次真实运行。
var _halt := false

# 当前用例的断言收集器
var _case_id := ""
var _section := ""
var _asserts: Array = []
var _whitelist_hits: Array = []


## =============================================================================
##  入口
## =============================================================================
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--case="):
			_opt_case = a.split("=", true, 1)[1]
		elif a == "--all":
			_opt_all = true
		elif a == "--list":
			_opt_list = true
		elif a.begins_with("--out="):
			_opt_out = a.split("=", true, 1)[1]

	if _opt_list:
		_print_cases()
		_halt = true
		quit(0)
		return
	if _opt_case == "" and not _opt_all:
		printerr("[verify] 用法错误：需要 --case=<id> 或 --all（--list 可列出全部用例）")
		_halt = true
		quit(2)
		return
	if _opt_case != "" and not CASES.has(_opt_case):
		printerr("[verify] 未知用例 '", _opt_case, "'；用 --list 查看可用 id")
		_halt = true
		quit(2)
		return


## 用 _process 启动协程：_initialize 阶段场景树尚未开始迭代，
## 在 _initialize 里 await process_frame 有死锁风险。
func _process(_delta: float) -> bool:
	if _halt:
		return true
	if not _started:
		_started = true
		_run()
	return _finished


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_opt_out)
	var t_all := Time.get_ticks_msec()

	# 打桩用例：只做事、只以退出码说话，不写报告、不进断言汇总
	var probe_meta: Dictionary = CASES.get(_opt_case, {})
	if _opt_case != "" and bool(probe_meta.get("probe", false)):
		await _run_probe(_opt_case)
		return

	var ids: Array = []
	if _opt_all:
		for id in CASES.keys():
			if CASES[id].get("hidden", false):
				continue
			ids.append(id)
	else:
		ids.append(_opt_case)

	var results: Array = []
	for id in ids:
		var r: Dictionary = await _run_one(id)
		results.append(r)
		if not r["ok"] and not r["skipped"]:
			# 保留继续跑完全部用例的能力：单步失败不中断，便于一次看全貌
			pass

	if _opt_all:
		var failed := 0
		var skipped := 0
		for r in results:
			if r["skipped"]:
				skipped += 1
			elif not r["ok"]:
				failed += 1
		var agg := {
			"kind": "aggregate",
			"headless": _is_headless(),
			"godot": Engine.get_version_info()["string"],
			"started_at": Time.get_datetime_string_from_system(),
			"duration_ms": Time.get_ticks_msec() - t_all,
			"total_cases": results.size(),
			"failed_cases": failed,
			"skipped_cases": skipped,
			"ok": failed == 0,
			"cases": results,
		}
		_write_json(_opt_out.path_join("_all.json"), agg)
		print("")
		print("[verify] ================ 汇总 ================")
		for r in results:
			var tag := "SKIP" if r["skipped"] else ("PASS" if r["ok"] else "FAIL")
			print("[verify] %-5s %-18s %s" % [tag, r["case"], r["summary"]])
		print("[verify] 用例 %d / 失败 %d / 跳过 %d / 耗时 %dms"
				% [results.size(), failed, skipped, Time.get_ticks_msec() - t_all])
		print("[verify] 报告目录 ", _opt_out)
		print("[verify] ======================================")
		_finished = true
		quit(1 if failed > 0 else 0)
		return

	_finished = true
	quit(0 if results[0]["ok"] else 1)


func _run_one(id: String) -> Dictionary:
	_case_id = id
	_section = ""
	_asserts = []
	_whitelist_hits = []

	var meta: Dictionary = CASES[id]
	var t0 := Time.get_ticks_msec()
	var headless := _is_headless()

	if meta.get("kind", "pure") == "headed" and headless:
		var skipped := {
			"case": id,
			"ok": true,
			"skipped": true,
			"skip_reason": "该用例需要真实 GPU/窗口（headless 下渲染指标恒为 0）；"
					+ "请去掉 --headless 重跑",
			"assertions": [],
			"duration_ms": Time.get_ticks_msec() - t0,
			"summary": "SKIP(需要窗口模式)",
		}
		print("[verify] ---- ", id, "  SKIP：", skipped["skip_reason"])
		return skipped

	print("[verify] ---- ", id, "  ", meta.get("desc", ""))

	var before_fail := 0
	await _dispatch(id)
	var duration := Time.get_ticks_msec() - t0

	var failed := 0
	for a in _asserts:
		if not a["ok"]:
			failed += 1

	var report := {
		"case": id,
		"desc": meta.get("desc", ""),
		"kind": meta.get("kind", "pure"),
		"ok": failed == 0,
		"skipped": false,
		"headless": headless,
		"godot": Engine.get_version_info()["string"],
		"exe": OS.get_executable_path(),
		"started_at": Time.get_datetime_string_from_system(),
		"duration_ms": duration,
		"counts": {
			"total": _asserts.size(),
			"passed": _asserts.size() - failed,
			"failed": failed,
		},
		"whitelist_hits": _whitelist_hits,
		"assertions": _asserts,
	}
	report["summary"] = "%d/%d 断言通过" % [_asserts.size() - failed, _asserts.size()]
	_write_json(_opt_out.path_join(id + ".json"), report)

	for a in _asserts:
		if a["ok"]:
			print("    ok   ", a["name"])
		else:
			print("    FAIL ", a["name"], "  -> ", a["detail"])
	print("[verify] %s  %s  (%dms)" % ["PASS" if failed == 0 else "FAIL", id, duration])
	return report


func _dispatch(id: String) -> void:
	match id:
		"s0_2_selfcheck":
			await _case_selfcheck()
		"s0_2_imgdiff":
			await _case_imgdiff()
		"s0_2_guard":
			await _case_guard()
		"s0_2_boot":
			await _case_boot()
		"s0_2_scene_api":
			await _case_scene_api()
		"s0_2_baseline":
			await _case_baseline()
		"s0_2_probe_pass":
			await _case_probe_pass()
		"s0_2_probe_fail":
			await _case_probe_fail()
		"s0_6_clock":
			await _case_clock()
		"s0_6_repro":
			await _case_repro()
		"s1_0_scene_arg":
			await _case_scene_arg()
		"s1_0_routes":
			await _case_routes()
		"s1_0_migration":
			await _case_migration()
		"s0_4_overlay":
			await _case_overlay()
		"s0_4_cost":
			await _case_debug_cost()
		"s0_4_quick":
			await _case_quick()
		"s0_3_state":
			await _case_state()
		"s0_3_roundtrip":
			await _case_roundtrip()
		"s0_3_dirty":
			await _case_dirty()
		"s0_3_atomic":
			await _case_atomic()
		"s0_3_no_autosave":
			await _case_no_autosave()
		"s0_3_router":
			await _case_router()
		"s0_3_slots":
			await _case_slots()
		"s0_3_overwrite":
			await _case_overwrite()
		"s0_3_probe_write":
			await _case_probe_write()
		"s0_3_probe_read":
			await _case_probe_read()
		"s0_3_probe_loop":
			await _case_probe_loop()
		"s0_5_doc_conventions":
			await _case_doc_conventions()
		"s1_1_canon":
			await _case_canon()
		"s1_1_params":
			await _case_gen_params()
		"s1_1_height":
			await _case_height_field()
		"s1_1_regions":
			await _case_regions()
		"s1_1_world":
			await _case_world()
		"s1_1_gen":
			await _case_world_gen()
		"s1_1_variety":
			await _case_world_variety()
		"s1_2_boot":
			await _case_world_session()
		"s1_2_mesh":
			await _case_strategic_mesh()
		"s1_2_camera":
			await _case_strategic_camera()
		"s1_2_perf":
			await _case_strategic_perf()
		"s1_3_party":
			await _case_party_marker()
		_:
			await process_frame
			ok(false, "用例已在 CASES 注册但未在 _dispatch 中实现", "id=" + id)


## 打桩用例的统一入口：等 autoload 就位 → 分发 → 按 `_probe_exit` 退出。
## 之所以绕开 `_run_one`：那里的汇总会用 `quit(0/1)` 覆盖打桩用例自报的退出码，
## 而父用例拿到的就是那个退出码。
func _run_probe(id: String) -> void:
	await process_frame
	await process_frame
	await _dispatch(id)
	_finished = true
	quit(_probe_exit if _probe_exit >= 0 else 1)


## =============================================================================
##  断言 API
## =============================================================================
func section(name: String) -> void:
	_section = name


func ok(cond: bool, name: String, detail: String = "") -> bool:
	_record(name, cond, detail if not cond else "")
	return cond


func eq(actual: Variant, expected: Variant, name: String) -> bool:
	var pass_: bool = actual == expected
	_record(name, pass_, "" if pass_ else "actual=%s expected=%s" % [actual, expected])
	return pass_


func ne(actual: Variant, unexpected: Variant, name: String) -> bool:
	var pass_: bool = actual != unexpected
	_record(name, pass_, "" if pass_ else "actual 不应等于 %s" % [unexpected])
	return pass_


func near(actual: float, expected: float, eps: float, name: String) -> bool:
	var pass_ := absf(actual - expected) <= eps
	_record(name, pass_, "" if pass_ else "actual=%f expected=%f eps=%f" % [actual, expected, eps])
	return pass_


func ge(actual: float, floor_v: float, name: String) -> bool:
	var pass_ := actual >= floor_v
	_record(name, pass_, "" if pass_ else "actual=%f 应 >= %f" % [actual, floor_v])
	return pass_


func le(actual: float, ceil_v: float, name: String) -> bool:
	var pass_ := actual <= ceil_v
	_record(name, pass_, "" if pass_ else "actual=%f 应 <= %f" % [actual, ceil_v])
	return pass_


func contains(hay: String, needle: String, name: String) -> bool:
	var pass_ := hay.contains(needle)
	_record(name, pass_, "" if pass_ else "未找到 %s" % [needle])
	return pass_


func not_contains(hay: String, needle: String, name: String) -> bool:
	var pass_ := not hay.contains(needle)
	_record(name, pass_, "" if pass_ else "不应出现 %s" % [needle])
	return pass_


func _record(name: String, pass_: bool, detail: String) -> void:
	_asserts.append({
		"section": _section,
		"name": name,
		"ok": pass_,
		"detail": detail,
	})


## =============================================================================
##  用例实现
## =============================================================================
## 所有用例统一以 await process_frame 开头 —— 见文件头约束 5。

## --- s0_2_selfcheck ----------------------------------------------------------
## 通过**子进程**验证退出码契约（这才是 ROADMAP 要的『退出码 = 1』证据）。
func _case_selfcheck() -> void:
	await process_frame
	section("退出码契约")
	var pass_exit := -1
	var fail_exit := -1
	var pass_out: Array = []
	var fail_out: Array = []
	pass_exit = _exec_godot(PackedStringArray([
		"--headless", "--script", "res://tools/verify.gd", "--",
		"--case=s0_2_probe_pass", "--out=" + _opt_out,
	]), pass_out)
	fail_exit = _exec_godot(PackedStringArray([
		"--headless", "--script", "res://tools/verify.gd", "--",
		"--case=s0_2_probe_fail", "--out=" + _opt_out,
	]), fail_out)
	eq(pass_exit, 0, "全通过用例退出码 = 0")
	eq(fail_exit, 1, "含失败断言的用例退出码 = 1")

	section("JSON 报告契约")
	var p := _read_json(_opt_out.path_join("s0_2_probe_pass.json"))
	var f := _read_json(_opt_out.path_join("s0_2_probe_fail.json"))
	ok(not p.is_empty(), "通过用例写出了 JSON 报告", _opt_out.path_join("s0_2_probe_pass.json"))
	ok(not f.is_empty(), "失败用例写出了 JSON 报告", _opt_out.path_join("s0_2_probe_fail.json"))
	if not p.is_empty():
		eq(p.get("ok"), true, "通过用例报告 ok=true")
		eq((p.get("assertions", []) as Array).size(), 2, "通过用例报告含 2 条断言")
		var a0: Dictionary = (p.get("assertions", []) as Array)[0]
		ok(a0.has("name") and a0.has("ok") and a0.has("detail"),
				"每条断言含 name/ok/detail 字段")
		ok(int(p.get("duration_ms", -1)) >= 0, "报告含 duration_ms",
				"duration_ms=%s" % [p.get("duration_ms")])
		ok(String(p.get("godot", "")) != "", "报告含 godot 版本")
	if not f.is_empty():
		eq(f.get("ok"), false, "失败用例报告 ok=false")
		eq(int((f.get("counts", {}) as Dictionary).get("failed", -1)), 1,
				"失败用例报告 counts.failed=1")

	section("用法错误")
	var usage_exit := _exec_godot(PackedStringArray([
		"--headless", "--script", "res://tools/verify.gd", "--", "--case=__no_such_case__",
	]), [] as Array)
	eq(usage_exit, 2, "未知用例 id 退出码 = 2")


## --- s0_2_imgdiff ------------------------------------------------------------
func _case_imgdiff() -> void:
	await process_frame
	var idiff := load("res://tools/img_diff.gd")
	var tmp := _opt_out.path_join("_imgdiff_tmp")
	DirAccess.make_dir_recursive_absolute(tmp)

	var a_path := tmp.path_join("a.png")
	var b_path := tmp.path_join("b.png")
	var c_path := tmp.path_join("c.png")
	var d_path := tmp.path_join("d.png")

	# 64x64 纯色图 → 便于精确断言
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.9, 1.0))
	img.save_png(a_path)
	img.save_png(b_path)

	section("同图")
	var same: Dictionary = idiff.diff(a_path, b_path)
	eq(same.get("verdict"), "pass", "同一份文件判定 pass")
	eq(same.get("changed_pixels"), 0, "同图改动像素数 = 0")
	eq(snappedf(float(same.get("ratio_pct", -1.0)), 0.0001), 0.0, "同图差异像素比 = 0.0000%")
	eq(same.get("a_sha256"), same.get("b_sha256"), "同图 sha256 一致")

	section("改动副本")
	# 只改 4 个像素里的 1 个 → 已知变更像素数
	var img_c := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img_c.fill(Color(0.2, 0.6, 0.9, 1.0))
	for i in 8:
		img_c.set_pixel(i, 0, Color(0.9, 0.1, 0.1, 1.0))
	img_c.save_png(c_path)
	var changed: Dictionary = idiff.diff(a_path, c_path)
	eq(changed.get("verdict"), "fail", "存在差异时判定 fail")
	eq(changed.get("changed_pixels"), 8, "改动像素数精确 = 8")
	eq(snappedf(float(changed.get("ratio_pct", -1.0)), 0.0001),
			snappedf(8.0 / 4096.0 * 100.0, 0.0001), "差异像素比精确 = 8/4096")
	ne(changed.get("a_sha256"), changed.get("b_sha256"), "改图后 sha256 变化")

	section("亚阈值噪声不算差异")
	var img_d := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img_d.fill(Color(0.2, 0.6, 0.9, 1.0))
	# 单通道只差 4/255，低于默认通道阈值 8 → 不应计入
	for x in 64:
		img_d.set_pixel(x, 5, Color(0.2, 0.6, 0.9 + 4.0 / 255.0, 1.0))
	img_d.save_png(d_path)
	var subtle: Dictionary = idiff.diff(a_path, d_path)
	eq(subtle.get("changed_pixels"), 0, "低于通道阈值的差异不计入")
	eq(subtle.get("verdict"), "pass", "亚阈值差异仍判定 pass")

	section("尺寸不一致")
	var big := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	big.fill(Color(0.2, 0.6, 0.9, 1.0))
	var e_path := tmp.path_join("e.png")
	big.save_png(e_path)
	var mismatch: Dictionary = idiff.diff(a_path, e_path)
	eq(mismatch.get("verdict"), "fail", "尺寸不一致判定 fail（不静默裁剪）")
	contains(String(mismatch.get("reason", "")), "尺寸", "尺寸不一致给出明确原因")

	section("缺失文件")
	var missing: Dictionary = idiff.diff(a_path, tmp.path_join("__absent__.png"))
	eq(missing.get("verdict"), "error", "文件缺失判定 error")

	# 清理临时图
	for f in [a_path, b_path, c_path, d_path, e_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))

	# CLI 入口也要能跑通（B- 证据链走的是命令行）
	section("CLI 入口")
	var cli_out: Array = []
	var cli_exit := _exec_godot(PackedStringArray([
		"--headless", "--script", "res://tools/img_diff.gd", "--",
		"--a=" + a_path, "--b=" + b_path,
	]), cli_out)
	eq(cli_exit, 2, "CLI 对已删除的输入返回用法/读取错误码 2")


## --- s0_2_guard --------------------------------------------------------------
func _case_guard() -> void:
	await process_frame
	section("违例检测能力（人造违例，逐类验证后立即删除）")
	var tmp_dir := "res://scripts/_verify_tmp"
	DirAccess.make_dir_recursive_absolute(tmp_dir)

	# 规则名 → 造例（键名与守卫规则名一致，便于逐条断言）
	var probes := {
		"box_mesh": {"ext": "gd", "text": "var m := BoxMesh.new()\n"},
		"csg_box": {"ext": "gd", "text": "var n := CSGBox3D.new()\n"},
		"standard_material": {"ext": "gd", "text": "var s := StandardMaterial3D.new()\n"},
		"bare_randf": {"ext": "gd", "text": "var f := randf()\n"},
		"bare_randi": {"ext": "gd", "text": "var i := randi()\n"},
		# S0.6 的两条分流都要能被抓住：脚本侧墙钟 + 着色器侧内建 TIME
		"unfreezable_time_gd": {
			"rule": "unfreezable_time", "ext": "gd",
			"text": "var t := Time.get_ticks_msec()\n",
		},
		"unfreezable_time_shader": {
			"rule": "unfreezable_time", "ext": "gdshader",
			"text": "float t = TIME * wind_speed;\n",
		},
		# S0.3 批次 3：人造违例落在 res://scripts/_verify_tmp/，不是登记属主 ⇒ 必被抓住
		"scene_change_owner": {
			"ext": "gd",
			"text": "get_tree().change_scene_to_file(\"res://scenes/dev/diorama.tscn\")\n",
		},
	}
	for label in probes.keys():
		var p: Dictionary = probes[label]
		var rule := String(p.get("rule", label))
		var probe_file := tmp_dir.path_join("guard_probe.%s" % String(p["ext"]))
		var f := FileAccess.open(probe_file, FileAccess.WRITE)
		f.store_string(String(p["text"]))
		f.close()
		var hits := _guard_walk()
		var found := false
		for h in hits:
			if h["rule"] == rule and String(h["path"]).ends_with("guard_probe.%s" % String(p["ext"])):
				found = true
		ok(found, "守卫可捕获人造违例：%s" % label,
				"写入 %s 后未检出" % probe_file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_dir))
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(tmp_dir)),
			"人造违例临时目录已清理")

	section("允许的写法不被误报")
	ok(_scan_text("res://x.gd", "var v := rng.randf()\nvar w := rng.randi_range(1, 5)\n").is_empty(),
			"rng.randf()/rng.randi_range() 等成员调用不误报")
	ok(_scan_text("res://x.gd", "# BoxMesh 出现在注释里不算违例\n").is_empty(),
			"注释中的关键字不误报")
	# S0.6：正确的时间写法不得被误报，否则守卫会逼着人绕开它
	ok(_scan_text("res://x.gd", "c.position.x += drift * Clock.dt\n").is_empty(),
			"Clock.dt / Clock.t 不误报")
	ok(_scan_text("res://x.gdshader", "float t = render_time * wind_speed;\n").is_empty(),
			"着色器里的 render_time 不误报")
	ok(_scan_text("res://x.gdshader", "// the builtin TIME is banned here\n").is_empty(),
			"着色器注释里提到 TIME 不误报")
	ok(_scan_text("res://x.gd", "# 以前用 Time.get_ticks_msec()，现在用 Clock.t\n").is_empty(),
			"脚本注释里提到墙钟不误报")
	# S0.3 批次 3：属主文件里的切场景调用是**允许**的，规则按路径放行而非按 token 全禁
	ok(_scan_text("res://scripts/core/scene_router.gd",
			"get_tree().change_scene_to_file(\"res://scenes/dev/diorama.tscn\")\n").is_empty(),
			"SceneRouter 自身切场景不误报")
	ok(_scan_text("res://scripts/world/terrain.gd",
			"get_tree().change_scene_to_file(\"res://scenes/dev/diorama.tscn\")\n").size() == 1,
			"非属主文件切场景恰好报 1 条（不多不少）")

	section("既有代码基线")
	var real := _guard_walk()
	var unlisted: Array = []
	_whitelist_hits = []
	for h in real:
		var wl := _whitelist_reason(h)
		if wl == "":
			unlisted.append(h)
		else:
			_whitelist_hits.append({
				"path": h["path"], "line": h["line"], "rule": h["rule"], "reason": wl,
			})
	ok(unlisted.is_empty(), "既有代码无未登记违例",
			"%d 条未登记：%s" % [unlisted.size(), JSON.stringify(unlisted)])
	for h in _whitelist_hits:
		print("    [guard] 白名单命中 ", h["path"], ":", h["line"], " 规则=", h["rule"])
	ok(_whitelist_hits.size() >= 1,
			"白名单命中项已被显式列出（不静默放过）",
			"命中 %d 条" % _whitelist_hits.size())


## --- s0_2_boot ---------------------------------------------------------------
func _case_boot() -> void:
	await process_frame
	section("headless 启动 60 帧")
	var out: Array = []
	var exit_code := _exec_godot(PackedStringArray([
		"--headless", "--quit-after", "60",
	]), out)
	var joined := "\n".join(PackedStringArray(out))
	eq(exit_code, 0, "启动 60 帧退出码 = 0")
	not_contains(joined, "SCRIPT ERROR", "日志无 SCRIPT ERROR")
	not_contains(joined, "ERROR:", "日志无 ERROR:")
	# S1.0d：开机场景已从 diorama 换成战略图（当时空壳；S1.2a 起挂入口脚本，仍无地形 / 相机）。所以这里
	# 改**反向断言**：日志里不能再出现地形生成行。S1.0c 之前这条正向断言证明"世界真的建
	# 起来了"，现在它证明的是相反的事实 —— 开机确实换了场景，而不是"还偷偷加载着 diorama"。
	# 正向证据在 `s1_0_migration`：run/main_scene == 路由 world == 该文件真实存在。
	not_contains(joined, "[terrain]", "启动场景不是 diorama（没有地形生成行）")


## --- s0_2_scene_api ---------------------------------------------------------
## 通过场景用例基类模式（instantiate + add_child + await）验证既有公开 API 表面。
## 这套 19 个符号是 S0.1 重组时的 API 契约，也是 §2.2 列出的契约。
func _case_scene_api() -> void:
	await process_frame
	section("场景用例基类模式")
	var main := await _load_diorama()
	ok(main != null, "diorama 夹具可 instantiate 并 add_child")
	if main == null:
		return
	ok(get_first_node_in_group("main") != null, "节点组 #main 已注册")
	var terrain := get_first_node_in_group("terrain")
	var player := get_first_node_in_group("player")
	var rig := get_first_node_in_group("camera_rig")
	var water := get_first_node_in_group("water")
	var dn := get_first_node_in_group("day_night")
	ok(terrain != null, "节点组 #terrain 已注册")
	ok(player != null, "节点组 #player 已注册")
	ok(rig != null, "节点组 #camera_rig 已注册")
	ok(water != null, "节点组 #water 已注册")
	ok(dn != null, "节点组 #day_night 已注册")

	section("既有多帧运行")
	for i in 30:
		await process_frame
	ok(true, "加载夹具后连续跑 30 帧无异常")

	section("公开 API 契约（19 个符号）")
	ok(_has_callable(main, "rebuild"), "Main.rebuild")
	if terrain != null:
		ok(_has_callable(terrain, "height_at"), "Terrain.height_at")
		ok(_has_callable(terrain, "normal_at"), "Terrain.normal_at")
		ok(_has_callable(terrain, "slope_at"), "Terrain.slope_at")
		ok(_has_callable(terrain, "generate"), "Terrain.generate")
		ok(terrain.get("spawn_point") != null, "Terrain.spawn_point")
		var h: Variant = terrain.call("height_at", 0.0, 0.0)
		ok(h is float and is_finite(h), "Terrain.height_at(0,0) 返回有限浮点", "h=%s" % [h])
		var nrm: Variant = terrain.call("normal_at", 0.0, 0.0)
		ok(nrm is Vector3, "Terrain.normal_at(0,0) 返回 Vector3")
	# autoload 在本模式下只能用节点路径取，不能用标识符（见文件头约束 1）
	var style := get_root().get_node_or_null("Style")
	ok(style != null, "autoload Style 节点存在于 root")
	if style != null:
		ok(_has_callable(style, "pal"), "Style.pal")
		ok(_has_callable(style, "toon"), "Style.toon")
		ok(_has_callable(style, "water_material"), "Style.water_material")
		ok(_has_callable(style, "set_outline"), "Style.set_outline")
		ok(_has_callable(style, "set_pixel_span"), "Style.set_pixel_span")
		ok(_has_callable(style, "build_ramp"), "Style.build_ramp")
	for sym in ["facet", "combine", "roughen", "blob", "cone",
			"tapered_cylinder", "superellipse_prism"]:
		ok(_has_callable(MeshUtil, sym), "MeshUtil.%s" % sym)

	section("清理")
	main.queue_free()
	await process_frame
	ok(get_first_node_in_group("main") == null, "夹具已释放，组 #main 清空")


## --- s0_2_baseline -----------------------------------------------------------
func _case_baseline() -> void:
	await process_frame
	section("--out 透传：换目录跑，报告必须落在新目录（回归锚点）")
	# `93c25e6` 修好了"`_case_baseline` 不把 `--out=` 传给 baseline.gd"这个缺陷，
	# 但当时只靠"默认目录刚好也能过"没被抓住。这条断言把修好的行为钉死：
	# 只有当 `--out=` 真的透传到子进程，报告才会出现在**非默认**目录里。
	var nondefault := _opt_out.path_join("outprobe")
	DirAccess.make_dir_recursive_absolute(nondefault)
	var stray := nondefault.path_join("baseline_verify_outprobe.json")
	if FileAccess.file_exists(stray):
		DirAccess.remove_absolute(stray)
	var p_out: Array = []
	var p_code := _exec_godot(PackedStringArray([
		"--script", "res://tools/baseline.gd", "--", "--label=verify_outprobe",
		"--out=" + nondefault,
	]), p_out)
	eq(p_code, 0, "显式 --out 的子进程退出码 = 0")
	ok(FileAccess.file_exists(stray),
			"报告落在显式指定的目录（说明 --out= 真的被透传，而不是被子进程忽略）", stray)
	ok(not FileAccess.file_exists(REPORT_DIR.path_join("baseline_verify_outprobe.json")),
			"默认报告目录里没有这份文件（不是'两个目录都写'的假通过）")

	section("连续 3 次窗口模式采样")
	var reports: Array = []
	for i in 3:
		var label := "verify_run%d" % (i + 1)
		var report_path := _opt_out.path_join("baseline_%s.json" % label)
		# 先删旧报告再跑：`--out` 指向同一目录时，上一轮的文件会让「写出了 JSON」变成
		# 假通过（本用例曾经只认默认目录，一旦 `--out` 换目录就整例失败——见 §16 记录）。
		if FileAccess.file_exists(report_path):
			DirAccess.remove_absolute(report_path)
		ok(not FileAccess.file_exists(report_path),
				"baseline 第 %d 次的报告文件在运行前不存在（旧文件不能冒充证据）" % (i + 1))
		var out: Array = []
		var exit_code := _exec_godot(PackedStringArray([
			"--script", "res://tools/baseline.gd", "--", "--label=" + label,
			"--out=" + _opt_out,
		]), out)
		eq(exit_code, 0, "baseline 第 %d 次运行退出码 = 0" % (i + 1))
		var r := _read_json(report_path)
		ok(not r.is_empty(), "baseline 第 %d 次写出了 JSON" % (i + 1), report_path)
		if not r.is_empty():
			reports.append(r)
	if reports.size() < 3:
		ok(false, "三次采样都成功", "只拿到 %d 份" % reports.size())
		return

	section("四项指标存在")
	for key in ["fps_mean", "ms_per_frame", "memory_static_mb", "primitives"]:
		var present := true
		for r in reports:
			if not r.has(key) or float(r[key]) <= 0.0:
				present = false
		ok(present, "指标存在且为正：%s" % key)

	section("方差 < 5%（连续 3 次）")
	var keys := {
		"fps_mean": "FPS",
		"ms_per_frame": "ms/frame",
		"memory_static_mb": "静态内存",
		"primitives": "三角面数",
		"draw_calls": "绘制调用",
	}
	for key in keys.keys():
		var vals: Array = []
		for r in reports:
			if r.has(key):
				vals.append(float(r[key]))
		var mean := 0.0
		for v in vals:
			mean += v
		mean /= float(vals.size())
		var lo: float = vals.min()
		var hi: float = vals.max()
		var spread_pct := 0.0 if mean == 0.0 else (hi - lo) / mean * 100.0
		ok(spread_pct < 5.0,
				"%s 极差 %.3f%% < 5%%" % [keys[key], spread_pct],
				"样本=%s mean=%.3f" % [str(vals), mean])


## --- s0_6_clock --------------------------------------------------------------
## Clock 是 autoload，本模式只能用节点路径取（见文件头约束 1）。
func _case_clock() -> void:
	await process_frame
	var clock := get_root().get_node_or_null("Clock")
	section("Clock autoload 存在且 API 完整")
	ok(clock != null, "autoload Clock 节点存在于 root")
	if clock == null:
		return
	for sym in ["set_deterministic", "reset", "is_reproducible"]:
		ok(_has_callable(clock, sym), "Clock.%s" % sym)
	var props := {}
	var scr: Script = clock.get_script()
	if scr != null:
		for p in scr.get_script_property_list():
			props[String(p["name"])] = true
	for prop in ["t", "dt", "frame", "deterministic", "hz", "shader_param_ok"]:
		ok(props.has(prop), "Clock.%s 属性存在" % prop,
				"脚本属性表=%s" % [str(props.keys())])

	section("确定性模式：t == frame / hz（计算而非累加）")
	clock.call("set_deterministic", true, 60.0)
	eq(clock.get("t"), 0.0, "set_deterministic 后 t 归零（确定性批次必须从已知状态开始）")
	eq(clock.get("frame"), 0, "set_deterministic 后 frame 归零")
	eq(clock.get("hz"), 60.0, "hz 记录为 60")
	var f0: int = clock.get("frame")
	for i in 12:
		await process_frame
	var f1: int = clock.get("frame")
	ok(f1 > f0, "跑 12 帧后 frame 递增", "f0=%d f1=%d" % [f0, f1])
	var expect_t := float(f1) / 60.0
	near(clock.get("t"), expect_t, 0.000001,
			"t 严格等于 frame/hz（t=%.9f 期望=%.9f）" % [clock.get("t"), expect_t])
	near(clock.get("dt"), 1.0 / 60.0, 0.000001, "确定性模式 dt 恒为 1/60")
	ok(clock.call("is_reproducible"), "is_reproducible() 为真（着色器参数也已注册）")

	section("hz 可变：30Hz 下 t == frame/30")
	clock.call("set_deterministic", true, 30.0)
	for i in 6:
		await process_frame
	var f2: int = clock.get("frame")
	near(clock.get("t"), float(f2) / 30.0, 0.000001,
			"30Hz：t=%.9f 期望=%.9f" % [clock.get("t"), float(f2) / 30.0])

	section("实时模式：t 随真实 delta 前进，量级与墙钟一致（交互行为不回归）")
	clock.call("set_deterministic", false)
	await process_frame
	var t_rt0: float = clock.get("t")
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 400:
		await process_frame
	var wall := float(Time.get_ticks_msec() - w0) / 1000.0
	var dt_rt: float = float(clock.get("t")) - t_rt0
	ok(dt_rt > 0.0, "实时模式 t 递增", "%.6f -> %.6f" % [t_rt0, clock.get("t")])
	ok(clock.get("dt") > 0.0, "实时模式 dt 为正的真实帧步长", "dt=%s" % [clock.get("dt")])
	# 量级校验：Clock.t 就是把真实 delta 累起来，二者应基本重合。
	# 容差放宽到 35%，因为 await process_frame 的调度与墙钟采样点并不完全对齐。
	var rel := absf(dt_rt - wall) / maxf(wall, 0.0001)
	ok(rel < 0.35, "实时模式 Δt 与墙钟相对误差 < 35%",
			"时钟 Δt=%.4fs 墙钟=%.4fs 误差=%.1f%%" % [dt_rt, wall, rel * 100.0])

	section("reset() 归零")
	clock.call("reset")
	eq(clock.get("t"), 0.0, "reset 后 t = 0")
	eq(clock.get("frame"), 0, "reset 后 frame = 0")
	eq(clock.get("dt"), 0.0, "reset 后 dt = 0")

	section("全局着色器参数已声明（防止动画被冻结却看起来『可复现』）")
	ok(clock.get("shader_param_ok"),
			"project.godot 的 [shader_globals] 声明了 render_time",
			"未声明：着色器会停在 render_time=0，画面看起来是冻结的")
	ok(ProjectSettings.has_setting("shader_globals/render_time"),
			"ProjectSettings.has_setting('shader_globals/render_time')")
	var decl: Variant = ProjectSettings.get_setting("shader_globals/render_time")
	ok(decl is Dictionary and String((decl as Dictionary).get("type", "")) == "float",
			"声明类型为 float", "decl=%s" % [str(decl)])
	print("    [note] 该参数**真的进入着色器**由 s0_6_repro 的『帧数 15 vs 200 必须不同』实质验证；")
	print("    [note] RenderingServer.global_shader_parameter_get_list() 是编辑器专用 API，")
	print("    [note] 运行期调用会报 'should never be used outside the editor'，故此处不做列表断言。")

	section("现场还原")
	clock.call("set_deterministic", false)
	ok(not clock.get("deterministic"), "用例结束后恢复实时模式，不污染后续用例")


## --- s0_6_repro --------------------------------------------------------------
## 两次**独立进程**的同参数截图必须逐位一致。这是 S0.2 里那条实测 1.62%–5.67%
## 噪声底的正面修复证据，也是 `B-` 门禁能否使用的前提。
## 反向对照同样重要：若两次都是空图/冻结图，逐位一致就毫无意义。
func _case_repro() -> void:
	await process_frame
	var base := _opt_out.path_join("repro")
	DirAccess.make_dir_recursive_absolute(base)
	# S1.0d：缺省开机场景已是空壳，截图批次必须显式指定 diorama 夹具，否则拍到的
	# 是一张没有相机的纯背景图 —— 两张同为纯色，"逐位一致"就退化成真空通过。
	var shot_args := PackedStringArray([
		"--scene=" + DIORAMA_SCENE,
		"--shots", "--case=s0_boot", "--warmup=60", "--frames=15",
	])

	section("两次独立进程、同参数截图")
	var shas: Array = []
	for label in ["a", "b"]:
		var out_dir := base.path_join(label)
		var out: Array = []
		var extra := shot_args.duplicate()
		extra.append("--out=" + out_dir)
		var exit_code := _exec_user(PackedStringArray(), extra, out)
		eq(exit_code, 0, "截图批次 %s 退出码 = 0" % label)
		var man := _read_json(out_dir.path_join("s0_boot.json"))
		ok(not man.is_empty(), "批次 %s 写出了清单" % label)
		if not man.is_empty():
			# 清单里自证这批是可复现的，否则字节一致无从谈起
			var ck: Dictionary = man.get("clock", {})
			ok(bool(ck.get("deterministic", false)),
					"批次 %s 的清单声明 deterministic=true" % label)
			ok(bool(ck.get("shader_param_ok", false)),
					"批次 %s 的清单声明 shader_param_ok=true（时间真的进了着色器）" % label)
		var shots: Array = man.get("shots", [])
		ok(shots.size() == 2, "批次 %s 产出 2 张图" % label, "实际 %d" % shots.size())
		for s in shots:
			shas.append({
				"label": label,
				"name": String(s.get("name", "")),
				"sha": String(s.get("sha256", "")),
				"size": int(s.get("width", 0)) * int(s.get("height", 0)),
			})

	section("逐位一致（sha256 相同）")
	for name in ["s0_boot_follow", "s0_boot_wide"]:
		var ha := ""
		var hb := ""
		for e in shas:
			if e["name"] == name and e["label"] == "a":
				ha = e["sha"]
			elif e["name"] == name and e["label"] == "b":
				hb = e["sha"]
		ok(ha != "" and hb != "", "两次都拿到了 %s 的 sha256" % name)
		ok(ha == hb, "%s 两次 sha256 逐位一致" % name, "A=%s B=%s" % [ha, hb])
		var wh := 0
		for e in shas:
			if e["name"] == name:
				wh = int(e["size"])
		eq(wh, 1600 * 900, "%s 为 1600x900（不是空图）" % name)

	section("img_diff 复核：验收标准原文口径（差异 = 0.0000%）")
	var idiff := load("res://tools/img_diff.gd")
	for name in ["s0_boot_follow", "s0_boot_wide"]:
		var pa := base.path_join("a").path_join(name + ".png")
		var pb := base.path_join("b").path_join(name + ".png")
		var r: Dictionary = idiff.diff(pa, pb)
		eq(int(r.get("changed_pixels", -1)), 0, "%s 差异像素 = 0" % name)
		eq(float(r.get("ratio_pct", -1.0)), 0.0, "%s 差异 = 0.0000%%" % name)
		eq(String(r.get("verdict", "")), "pass", "%s img_diff 判定 PASS" % name)
		eq(String(r.get("a_sha256", "x")), String(r.get("b_sha256", "y")),
				"%s 两次 sha256 相同（img_diff 内部复核）" % name)

	section("反向对照 1：改一个相机参数必须不同（排除『两张都是同一张空图』）")
	var ctl_dir := base.path_join("ctl")
	var ctl_out: Array = []
	var ctl_exit := _exec_user(PackedStringArray(), PackedStringArray([
		"--shot=ctl_follow", "--time=0.5", "--mode=FOLLOW", "--size=36", "--yaw=52",
		"--warmup=60", "--frames=15", "--out=" + ctl_dir,
	]), ctl_out)
	eq(ctl_exit, 0, "对照组截图退出码 = 0")
	var ctl_man := _read_json(ctl_dir.path_join("ctl_follow.json"))
	var ctl_shots: Array = ctl_man.get("shots", [])
	ok(ctl_shots.size() == 1, "对照组产出 1 张图")
	var ctl_sha := ""
	if ctl_shots.size() == 1:
		ctl_sha = String(ctl_shots[0].get("sha256", ""))
	var base_sha := ""
	for e in shas:
		if e["name"] == "s0_boot_follow" and e["label"] == "a":
			base_sha = e["sha"]
	ok(ctl_sha != "" and base_sha != "", "对照组与基准组都有 sha256")
	ok(ctl_sha != base_sha, "yaw 45 -> 52 后图像不同（画面确实随参数变化）")

	section("反向对照 2：改帧数必须不同（证明时间真在驱动动画，而非动画被冻结）")
	var live_dir := base.path_join("live")
	var live_out: Array = []
	var live_exit := _exec_user(PackedStringArray(), PackedStringArray([
		"--shot=live_follow", "--time=0.5", "--mode=FOLLOW", "--size=36", "--yaw=45",
		"--warmup=20", "--frames=200", "--out=" + live_dir,
	]), live_out)
	eq(live_exit, 0, "长帧数组截图退出码 = 0")
	var live_man := _read_json(live_dir.path_join("live_follow.json"))
	var live_shots: Array = live_man.get("shots", [])
	var live_sha := ""
	if live_shots.size() == 1:
		live_sha = String(live_shots[0].get("sha256", ""))
	ok(live_sha != "", "长帧数组写出了 sha256")
	# 同 warmup=60/frames=15 的基准量 t=1.5s；这里 frames=200 -> t=3.667s
	ok(live_sha != base_sha,
			"帧数 15 -> 200 后图像不同（render_time 真的在驱动风摆/水波）")


## --- s1_0_scene_arg ------------------------------------------------------------
## S1.0b 的 `--scene=res://…`（ROADMAP §5 S1.0b），S1.0d 之后**前提变了**：
## 缺省场景不再是 diorama，而是战略图（地形 + 无相机）。于是本用例的语义从"换场景不改像素"
## 变成"缺省确实是空壳，而 `--scene=` 能把夹具换回来"：
##   ① 同参数两次独立进程截图 sha256 相同 —— `--scene=` 是确定性通道；
##   ② 缺省（空壳）与 `--scene=diorama` 的哈希**必须不同** —— 这是 S1.0d 的
##      "开机真的换了场景"的像素级证据（旧版本的 ② 是"两者相同"，本步正好反过来）；
##   ③ 反向对照：`battle_stub` 与缺省、与 diorama 都不同 —— 三个场景三种像素，
##      否则"`--scene=` 没生效"仍可能靠"两个场景碰巧一样"混过去；
##   ④ 清单自报场景：manifest 的 `scene` 字段 == 实际加载的路径，图与参数可对账；
##   ⑤ 失败要显式：路径不存在 / 非 `res://` 一律退出码 1；只带 `--scene=` 不加
##      `--shots` 时必须是空转（退出码 0、不写清单），否则它会抢掉验收运行器的退出码。
## 注意：空壳场景没有相机，缺省批次拍到的是一张纯背景图 —— 它只用于证明"缺省换了
## 场景"与"两次进程一致"，**不**是新的视觉基线（视觉证据仍是 `B-` diorama 6 机位）。
func _case_scene_arg() -> void:
	await process_frame
	var base := _opt_out.path_join("scene_arg")
	DirAccess.make_dir_recursive_absolute(base)
	var dio := DIORAMA_SCENE
	var battle := "res://scenes/battle/battle_stub.tscn"
	var shot_args := PackedStringArray([
		"--shots", "--case=s0_boot", "--warmup=60", "--frames=15",
	])
	var runs := {
		"default": PackedStringArray(),
		"scene_a": PackedStringArray(["--scene=" + dio]),
		"scene_b": PackedStringArray(["--scene=" + dio]),
		"battle": PackedStringArray(["--scene=" + battle]),
	}
	var shas := {}
	var scenes := {}

	section("四个独立进程：缺省 / --scene=diorama ×2 / --scene=battle")
	for label in runs.keys():
		var out_dir := base.path_join(String(label))
		var extra: PackedStringArray = shot_args.duplicate()
		extra.append_array(runs[label])
		extra.append("--out=" + out_dir)
		var out: Array = []
		var exit_code := _exec_user(PackedStringArray(), extra, out)
		eq(exit_code, 0, "批次 %s 退出码 = 0" % label)
		var man := _read_json(out_dir.path_join("s0_boot.json"))
		ok(not man.is_empty(), "批次 %s 写出了清单" % label)
		scenes[label] = String(man.get("scene", ""))
		var per: Dictionary = {}
		for s in man.get("shots", []):
			per[String(s.get("name", ""))] = String(s.get("sha256", ""))
		shas[label] = per
		eq(per.size(), 2, "批次 %s 产出 2 张图" % label)

	section("清单自报场景：缺省 = 战略图（S1.0d 后的真开机场景）")
	eq(String(scenes.get("default", "")), WORLD_SCENE,
			"缺省批次的 scene == run/main_scene == 战略图")
	eq(String(scenes.get("scene_a", "")), dio, "--scene=diorama 批次的 scene == 指定路径")
	eq(String(scenes.get("battle", "")), battle, "--scene=battle 批次的 scene == 指定路径")

	section("① 同参数两次独立进程：diorama 夹具批次逐位一致")
	for name in ["s0_boot_follow", "s0_boot_wide"]:
		var h_a := String(shas.get("scene_a", {}).get(name, ""))
		var h_b := String(shas.get("scene_b", {}).get(name, ""))
		ok(h_a != "" and h_b != "", "%s：diorama 两批都拿到了 sha256" % name)
		eq(h_b, h_a, "%s：--scene=diorama 两次独立进程逐位一致（确定性通道）" % name)

	section("② --scene= 真的把夹具换回来了：diorama ≠ 缺省（空壳）")
	for name in ["s0_boot_follow", "s0_boot_wide"]:
		var h_def := String(shas.get("default", {}).get(name, ""))
		var h_dio := String(shas.get("scene_a", {}).get(name, ""))
		ok(h_def != "" and h_dio != "", "%s：缺省与 diorama 都拿到了 sha256" % name)
		ok(h_def != h_dio,
				"%s：缺省（战略图：地形、无相机）≠ --scene=diorama（有内容的世界）" % name)

	section("③ 反向对照：battle 与缺省、与 diorama 都不相同")
	for name in ["s0_boot_follow", "s0_boot_wide"]:
		var h_def := String(shas.get("default", {}).get(name, ""))
		var h_dio := String(shas.get("scene_a", {}).get(name, ""))
		var h_bt := String(shas.get("battle", {}).get(name, ""))
		ok(h_bt != "", "battle 批次拿到了 %s 的 sha256" % name)
		ok(h_bt != h_def, "battle 与缺省（空壳）的 %s 不同" % name)
		ok(h_bt != h_dio, "battle 与 diorama 的 %s 不同（三个场景三种像素）" % name)

	section("⑤ 失败要显式：坏路径不许静默拍成默认场景")
	for bad in ["res://nope/none.tscn", "scenes/dev/diorama.tscn"]:
		var out: Array = []
		var code := _exec_user(PackedStringArray(), PackedStringArray([
			"--shots", "--case=s0_boot", "--scene=" + String(bad),
			"--out=" + base.path_join("bad"),
		]), out)
		eq(code, 1, "--scene='%s' 退出码 = 1" % bad)
	ok(not _dir_has_json(base.path_join("bad")), "坏路径没有写出任何清单（没有拍到一半的图）")

	section("⑤ 纯修饰符：只带 --scene= 时不触发批次、不抢退出码")
	var solo_dir := base.path_join("solo")
	DirAccess.make_dir_recursive_absolute(solo_dir)
	var solo_out: Array = []
	var solo_code := _exec_user(PackedStringArray(), PackedStringArray([
		"--scene=" + battle, "--out=" + solo_dir,
	]), solo_out, 240)
	eq(solo_code, 0, "只带 --scene= 的进程退出码 = 0（没有被截图批次抢走）")
	ok(not _dir_has_json(solo_dir), "--scene= 单独出现没有触发截图批次")

	section("守卫没有被放宽：切场景仍然只有 SceneRouter 一个属主")
	eq(SCENE_CHANGE_OWNERS.size(), 1, "SCENE_CHANGE_OWNERS 仍只有 1 个属主")
	ok(not SCENE_CHANGE_OWNERS.has("res://scripts/core/capture.gd"),
			"capture.gd 没有靠扩属主清单拿到切场景权限")


## --- s1_0_routes --------------------------------------------------------------
## S1.0d：路由表收口 —— `world` 指向战略图（S1.2b 起有地形），S1.0c 的临时名 `strategic` 退役。
##
## 为什么删临时名：一个文件留两个名字会让 `_route_for_path()`（`_sync()` 开机认领路由
## 用的就是它）二义。S1.0c 登记 `strategic` 只是为了让本步只有"改指向"一件事可做；
## 现在它到期了，表回到 world / battle 两条。
##
## 每条判据都配一个反向形状：
##   ① **双向映射唯一**：名字 → 路径 与 路径 → 名字 同时成立，且 diorama 路径**不**
##      回指任何路由（回归夹具不是世界）；
##   ② **场景真的能被读**：load + instantiate，逐项检查根节点类型/名字/子节点数/脚本。
##      空壳仍是本步的验收物：S1.2 才填内容；
##   ③ **接线面没被扩大**：仍然没有 `goto_strategic()`；
##   ④ **拒绝不改状态**：已在 world 时 `goto_world()` 被拒，且**不重载同一个文件** ——
##      这正是 S1.0c 留到本步的那个语义问题，现在有了机器判定；
##   ⑤ **栈深没变**：`MAX_DEPTH` 仍为 2 —— 迁移的是指向，不是阶梯。
func _case_routes() -> void:
	await process_frame
	var router := get_root().get_node_or_null("SceneRouter")
	if not ok(router != null, "autoload SceneRouter 节点存在于 root"):
		return
	var consts: Dictionary = router.get_script().get_script_constant_map()

	section("表条目：两条路由，world 已指向战略图，diorama 不再是路由")
	var names: Array = []
	for n in router.call("route_names"):
		names.append(String(n))
	names.sort()
	eq(names, ["battle", "world"], "登记的路由恰好两条（S1.0c 的临时名 strategic 已退役）")
	var scenes: Dictionary = consts.get("SCENES", {})
	eq(scenes.size(), 2, "SCENES 表恰好两条（与 route_names() 同源）")
	ok(not consts.has("STRATEGIC"), "常量 STRATEGIC 已删除：一个文件只留一个名字")
	var seen := {}
	for r in names:
		var p := String(router.call("scene_path_for", r))
		ok(p != "" and ResourceLoader.exists(p), "%s → 文件真实存在" % r, p)
		seen[p] = true
	eq(seen.size(), 2, "两条路由指向两个不同文件（没有复制粘贴成同一路径）")
	eq(String(router.call("scene_path_for", "world")), WORLD_SCENE,
			"world → scenes/world/strategic_map.tscn（S1.0d 的迁移结果）")
	eq(String(ProjectSettings.get_setting("application/run/main_scene", "")), WORLD_SCENE,
			"run/main_scene 同步改到战略图（开机即落在 world）")

	section("反向映射唯一：文件 → 路由，且夹具不会被误认成世界")
	eq(String(router.call("_route_for_path", WORLD_SCENE)), "world",
			"strategic_map.tscn 的路径回指 world（_sync() 开机认领靠这条）")
	eq(String(router.call("_route_for_path", DIORAMA_SCENE)), "",
			"diorama 不再是路由：取景夹具不会被误认成世界")
	eq(String(router.call("_route_for_path", "res://scenes/dev/art_samples.tscn")), "",
			"未登记场景不映射成任意路由")

	section("场景解剖：世界根 = StrategicMap（S1.2a 起挂世界入口脚本）")
	var ps := load(WORLD_SCENE) as PackedScene
	if ok(ps != null, "strategic_map.tscn 可加载为 PackedScene", WORLD_SCENE):
		var inst: Node = ps.instantiate()
		if ok(inst != null, "可实例化"):
			eq(inst.get_class(), "Node3D", "根节点是 Node3D")
			eq(String(inst.name), "StrategicMap", "根名 = StrategicMap（路由→文件→根 第三段）")
			eq(inst.get_child_count(), 0, "零子节点：地形 / 相机仍属 S1.2b / S1.2c")
			# S1.2a 之前这里断言"根节点无脚本"，为的是不造一个什么都不做的占位入口。
			# 现在脚本真的做事了（建世界），所以判据从"有没有脚本"改成"脚本是不是入口"。
			var script: Script = inst.get_script()
			ok(script != null, "根节点挂脚本（S1.2a 起）", WORLD_SCENE)
			if script != null:
				var src := String(script.source_code)
				contains(src, "func _ready()", "脚本在 _ready() 里启动（不是空文件）")
				contains(src, "WorldSession.boot", "走 WorldSession.boot() 这个唯一入口")
				ok(not src.contains("TODO") and not src.contains("占位"),
					"脚本不是占位：不含 TODO / 占位字样")
			ok(inst.find_children("*", "Camera3D", true, false).is_empty(),
				"仍无相机：镜头属 S1.2c")
			eq(String(inst.scene_file_path), WORLD_SCENE, "场景自报路径 == 路由表路径")
			inst.free()

	section("接线面：没有 goto_strategic()，既有 API 与栈深不变")
	ok(not _has_callable(router, "goto_strategic"),
			"没有 goto_strategic()：战略图就是 world，不需要第二个入口")
	for sym in ["goto_world", "goto_battle", "return_to_world"]:
		ok(_has_callable(router, sym), "既有导航 API 仍在：%s" % sym)
	eq(int(consts.get("MAX_DEPTH", -1)), 2, "MAX_DEPTH 仍是 2：迁移的是指向，不是阶梯")

	section("拒绝不改状态：已在 world 时 goto_world() 被拒，且不重载同一个文件")
	if String(router.call("current_route")) != "world":
		ok(bool(router.call("goto_world")), "前置：先站到 world 上", String(router.get("last_error")))
		ok(await _await_route("world"), "前置：world 已落地")
	eq(String(router.call("current_route")), "world", "起点是 world")
	var stack0 := _router_stack(router)
	var depth0 := int(router.call("route_depth"))
	var scene0 := ""
	if current_scene != null:
		scene0 = current_scene.scene_file_path
	var inst0 := _count_scene_instances(WORLD_SCENE)
	var names0: Array = []
	for n in router.call("route_names"):
		names0.append(String(n))
	ok(not bool(router.call("goto_world")), "已在 world 时 goto_world() 返回 false")
	ok(String(router.get("last_error")).contains("world"), "拒绝理由指名 world",
			String(router.get("last_error")))
	eq(_router_stack(router), stack0, "拒绝后路由栈逐项不变")
	eq(int(router.call("route_depth")), depth0, "拒绝后栈深不变")
	eq(String(router.call("current_route")), "world", "拒绝后当前路由仍是 world")
	var scene1 := ""
	if current_scene != null:
		scene1 = current_scene.scene_file_path
	eq(scene1, scene0, "拒绝后屏幕没换（current_scene 路径逐字相同）")
	eq(_count_scene_instances(WORLD_SCENE), inst0,
			"★ 拒绝后世界实例数不变（%d）：没有把同一个文件重载一遍" % inst0)
	eq(bool(router.call("is_transitioning")), false, "拒绝没有留下『切换在飞行中』标记")
	var names1: Array = []
	for n in router.call("route_names"):
		names1.append(String(n))
	eq(names1, names0, "拒绝后表条目一条没少、没多")

	# 本用例为了验"已在 world 被拒"真的切到了 world；不清理会让下一个用例的世界夹具
	# 落在**第二个**世界里（两个 #main / 两台相机），与 s0_3_router 同口径收尾。
	var live: Node = current_scene
	if live != null:
		live.queue_free()
		await process_frame
		await process_frame
	_restore_defaults()
	eq(String(router.call("current_route")), "", "收尾：场景释放后路由归空，现场交还后续用例")


## --- s1_0_migration -----------------------------------------------------------
## S1.0d 的验收物：**路由 → 文件 → 场景根类**三段一致（ROADMAP §5 S1.0d）。
##
## 与 `s1_0_routes` 的分工：那边管"表长什么样、拒绝逻辑对不对"（机制），这边管
## "开机到底落在哪、那个文件是不是同一个人"（身份）。三条断言不是重复：
##   ① 三环绑定：`scene_path_for("world")` → 文件可加载 → 根类 `Node3D` / 根名
##      `StrategicMap` / 入口脚本（S1.2a 起）/ 零子节点 / 无相机；
##   ② 开机契约：`run/main_scene` == world 路径 —— 引擎自己就会落在 world 上，
##      不需要任何 `goto_*` 调用（这条是 S1.0a 建立的三处事实源断言的延续）；
##   ③ 认领与不重载：把战略图设成 `current_scene`（模拟引擎开机），`_sync()` 必须把它
##      认领成 `world`；此时 `goto_world()` 被拒且屏幕上仍只有一个实例 —— S1.0c 的
##      follow-up（"开机即 strategic 时会不会重载同一文件"）在此闭环。
func _case_migration() -> void:
	await process_frame
	var router := get_root().get_node_or_null("SceneRouter")
	if not ok(router != null, "autoload SceneRouter 节点存在于 root"):
		return

	# 清场：本用例要模拟"开机第一现场"，先把上一个用例可能留下的场景拿掉。
	if current_scene != null:
		var old: Node = current_scene
		old.queue_free()
		await process_frame
		await process_frame
	_restore_defaults()
	eq(current_scene, null, "前置：现场已清空，能从零模拟开机")

	section("① 三环绑定：路由 world → 文件 → 场景根类")
	var path := String(router.call("scene_path_for", "world"))
	eq(path, WORLD_SCENE, "路由 world 的路径 == 用例独立持有的字面量")
	ok(ResourceLoader.exists(path), "该路径在文件系统里真实存在", path)
	var ps := load(path) as PackedScene
	if ok(ps != null, "该路径可加载为 PackedScene"):
		var inst: Node = ps.instantiate()
		if ok(inst != null, "可实例化"):
			eq(inst.get_class(), "Node3D", "根类是 Node3D（与路由表的『世界』定位一致）")
			eq(String(inst.name), "StrategicMap", "根名是 StrategicMap")
			eq(inst.get_child_count(), 0, "零子节点：内容留给 S1.2")
			eq(inst.get_child_count(), 0, "零子节点：内容留给 S1.2b / S1.2c")
			var script2: Script = inst.get_script()
			ok(script2 != null, "根节点挂世界入口脚本（S1.2a 起）")
			if script2 != null:
				contains(String(script2.source_code), "WorldSession.boot",
					"脚本真的接上 WorldSession.boot()，不是伪入口")
			inst.free()

	section("② 开机契约：run/main_scene == world 路径，diorama 退居夹具")
	var declared := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	eq(declared, path, "run/main_scene 与 world 逐字相同")
	ok(declared != DIORAMA_SCENE, "diorama 不再是主场景（否则开机仍是演示岛）")
	ok(FileAccess.file_exists(DIORAMA_SCENE), "diorama 文件仍在（回归夹具没被删）")
	ok(load(DIORAMA_SCENE) != null, "diorama 仍可加载（夹具没被搬坏）")
	ok(not bool(router.call("is_known_route", "strategic")),
			"临时路由名 strategic 已不在表里（一个文件只留一个名字）")

	section("③ 开机认领：引擎直接加载的场景被 _sync() 认领为 world，且不重载")
	var inst2: Node = (load(path) as PackedScene).instantiate()
	get_root().add_child(inst2)
	current_scene = inst2
	eq(String(router.call("current_route")), "world",
			"引擎直接加载的场景被认领成 world（不需要先 goto_world()）")
	eq(int(router.call("route_depth")), 1, "栈里恰好一条（不是零条，也不是两条）")
	ok(not bool(router.call("goto_world")), "开机即 world：goto_world() 被拒")
	ok(String(router.get("last_error")).contains("world"), "拒绝理由指名 world",
			String(router.get("last_error")))
	eq(_count_scene_instances(WORLD_SCENE), 1,
			"★ 被拒后世界实例数仍为 1：没有把同一个文件重载一遍")

	# 收尾：释放本用例造的场景，把现场交还后续用例（与 s1_0_routes 同口径）。
	var live: Node = current_scene
	if live != null:
		live.queue_free()
		await process_frame
		await process_frame
	_restore_defaults()
	eq(String(router.call("current_route")), "", "收尾：场景释放后路由归空")


## --- s0_4_overlay -------------------------------------------------------------
## S0.4 批次 2：调试与观测层（ROADMAP §5 S0.4）。
##
## 五组最值钱的断言：
##   ① **默认隐藏**：一条 `visible=false` 决定 S0.4 之前录的 6 机位基线还成不成立。
##      验收用例在**同一个进程**里先证明"关着"，再去证明"开着"的样子。
##   ② **开关只改观测，不改世界**（§5 S0.4 的 `A-` 原文）：结构指纹、seed 派生量、
##      Rng 子流内部状态、GameState 世界字段逐项不变。这条不是形式主义 ——
##      调试层最容易犯的错就是"顺手读一下随机数"或"顺手重建世界"。
##   ③ **F1 是"拿掉"而不是"调透明"**：截图口径见 `s0_4_cost`（像素证据）。
##      这里先定状态语义：F1 压住叠加层时**不改变**它的开关状态，且不删节点。
##   ④ **菜单开着时 F1 先关菜单**：菜单是 `paused` 的唯一来源，藏掉菜单不解除暂停
##      会留下"看不见但世界停住"的假死态。这条只能靠"暂停真的解除了"来证。
##   ⑤ **发布构建门禁**：`ensure_debug_hotkeys(false)` 必须**删除** action，
##      并且此后按键真的没反应；同时全项目只允许 `input_setup.gd` 一处判断构建类型。
func _case_overlay() -> void:
	await process_frame
	var dbg := get_root().get_node_or_null("Debug")
	var clock := get_root().get_node_or_null("Clock")
	var gs := get_root().get_node_or_null("GameState")
	var rng := get_root().get_node_or_null("Rng")
	if not ok(dbg != null, "autoload Debug 节点存在于 root（本步新增，autoload 8 → 9）"):
		return
	if not ok(clock != null and gs != null and rng != null, "Clock / GameState / Rng 就位",
			"clock=%s gs=%s rng=%s" % [clock, gs, rng]):
		return

	# 前置条件自带，不依赖"进程恰好是新的"（`--all` 里前面的用例会留下全局状态）。
	_restore_defaults()
	dbg.call("set_overlay", false)
	dbg.call("set_ui_hidden", false)

	section("装配：默认隐藏、层号最高、整层不吃输入")
	eq(bool(dbg.get("overlay_on")), false, "叠加层默认关闭")
	eq(bool(dbg.get("hud_hidden")), false, "默认不隐藏 HUD")
	eq(bool(dbg.call("is_panel_visible")), false,
			"默认整层不可见（S0.4 之前录的 6 机位基线继续逐位有效的前提）")
	var main := await _load_diorama()
	if not ok(main != null, "diorama 夹具可加载"):
		return
	var hud := main.get_node_or_null("UI") as CanvasLayer
	var menu := main.get_node_or_null(MENU_NODE) as CanvasLayer
	var dlay := dbg.get_node_or_null("DebugLayer") as CanvasLayer
	if not ok(dlay != null, "Debug 自带 CanvasLayer（跨场景常驻，不挂在世界场景上）"):
		main.queue_free()
		return
	var consts: Dictionary = dbg.get_script().get_script_constant_map()
	eq(dlay.layer, int(consts.get("LAYER", -1)),
			"层号 == 脚本常量 LAYER（验收用例不另抄一份数字）")
	ok(hud != null and menu != null and dlay.layer > menu.layer and menu.layer > hud.layer,
			"层序 HUD < 菜单 < 调试层（遮挡靠 layer，不靠节点顺序）",
			"hud=%s menu=%s debug=%s" % [hud.layer if hud else -1,
					menu.layer if menu else -1, dlay.layer])
	var droot := dlay.get_node_or_null("Root") as Control
	ok(droot != null and droot.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"调试层整层 MOUSE_FILTER_IGNORE（绝不抢游戏本来该收到的点击）")
	ok(get_nodes_in_group("hud").size() >= 1, "HUD 已注册到组 #hud（F1 按组找属主，不硬编码路径）")

	section("开关只改观测，不改世界（§5 S0.4 的 A- 原文）")
	rng.call("stream", "s0_4_probe")   # 保证至少有一条子流可观测
	var fp0 := _world_fingerprint()
	var sig0 := _world_seed_signature()
	var facts0 := _world_facts(gs)
	var rng0 := _rng_states(rng)
	var on := bool(dbg.call("toggle_overlay"))
	eq(on, true, "toggle_overlay() -> 开")
	ok(bool(dbg.call("is_panel_visible")), "开层后整层真的可见")
	for i in 20:
		await process_frame
	ok(_debug_label(dbg, "Scene").contains("SCENE"), "面板显示了场景/路由行")
	ok(_debug_label(dbg, "Entities").contains("NODES"), "面板显示了节点计数行")
	ok(_debug_label(dbg, "ClockLine").length() > 0, "面板显示了时钟行")
	eq(bool(dbg.call("toggle_overlay")), false, "再切一次 -> 关")
	ok(not bool(dbg.call("is_panel_visible")), "关层后整层不可见")
	for i in 20:
		await process_frame
	eq(_world_fingerprint(), fp0, "开关两轮后世界结构指纹逐条一致")
	eq(_world_seed_signature(), sig0, "seed 派生量（spawn/高度/植被计数）不变")
	eq(_world_facts(gs), facts0, "GameState 世界字段不变")
	eq(_rng_states(rng), rng0, "Rng 子流内部状态不变（调试层没有偷抽随机数）")

	section("F1：隐藏全部 UI，且不改变叠加层开关状态、不删节点")
	dbg.call("set_overlay", true)
	ok(bool(dbg.call("is_panel_visible")), "前置：叠加层开着")
	eq(bool(dbg.call("toggle_ui_hidden")), true, "toggle_ui_hidden() -> 隐藏")
	ok(not bool(dbg.call("is_panel_visible")), "F1 同时压住调试层自己")
	ok(hud != null and not hud.visible, "HUD 层被隐藏")
	ok(bool(dbg.call("is_overlay_on")), "F1 不改变叠加层开关状态（只是压住）")
	eq(_world_fingerprint(), fp0, "F1 不删节点（隐藏 != 卸载）")
	ok(hud != null and hud.can_process(), "隐藏后 HUD 仍在处理（visible 不等于 process_mode）")
	eq(bool(dbg.call("toggle_ui_hidden")), false, "再按一次 -> 恢复")
	ok(hud != null and hud.visible, "HUD 恢复可见")

	section("菜单开着时按 F1：先关菜单解除暂停，不留『看不见但世界停住』")
	await _press_escape()
	ok(menu != null and bool(menu.call("is_open")), "前置：ESC 打开了菜单")
	ok(paused, "前置：树处于暂停")
	dbg.call("set_ui_hidden", true)
	ok(menu != null and not bool(menu.call("is_open")), "F1 后菜单已关闭")
	ok(not paused, "暂停已解除（否则就是假死态）")
	ok(main.can_process(), "夹具恢复处理")
	ok(hud != null and not hud.visible, "HUD 仍然隐藏（F1 的语义没有被菜单改写）")
	dbg.call("set_ui_hidden", false)

	section("发布构建门禁：闸门关掉后 action 被删除，按键真的没反应")
	ok(OS.is_debug_build(), "本进程是 Debug 构建（编辑器二进制），所以下面『开着』这一半有效")
	ok(InputMap.has_action(InputSetup.ACTION_DEBUG_OVERLAY)
			and InputMap.has_action(InputSetup.ACTION_DEBUG_HIDE_UI),
			"Debug 构建下两个调试 action 已注册")
	InputSetup.ensure_debug_hotkeys(false)
	ok(not InputMap.has_action(InputSetup.ACTION_DEBUG_OVERLAY)
			and not InputMap.has_action(InputSetup.ACTION_DEBUG_HIDE_UI),
			"ensure_debug_hotkeys(false) 后 action 被**删除**（不是留着不注册）")
	var before_on := bool(dbg.call("is_overlay_on"))
	var before_hidden := bool(dbg.call("is_ui_hidden"))
	await _press_key(KEY_F3)
	eq(bool(dbg.call("is_overlay_on")), before_on, "闸门关掉后按 F3 完全没反应")
	await _press_key(KEY_F1)
	eq(bool(dbg.call("is_ui_hidden")), before_hidden, "闸门关掉后按 F1 完全没反应")
	InputSetup.ensure_debug_hotkeys(true)
	ok(InputMap.has_action(InputSetup.ACTION_DEBUG_OVERLAY), "恢复闸门（后续用例不受影响）")

	section("单一闸门：全项目只有 input_setup.gd 一处判断构建类型")
	var gate_hits := _code_token_hits("res://scripts", "OS.is_debug_build")
	ok(gate_hits.size() == 1, "OS.is_debug_build 在 res://scripts 的代码行里只出现 1 次（注释不算）",
			"命中：%s" % [str(gate_hits)])
	if gate_hits.size() > 0:
		eq(String(gate_hits[0]["path"]), "res://scripts/core/input_setup.gd",
				"闸门就在 input_setup.gd")
		ok(String(gate_hits[0]["code"]).contains("ensure_debug_hotkeys"),
				"那一行确实是把构建类型喂给 ensure_debug_hotkeys()")

	section("确定性口径：环境量在确定性模式下不落盘（B- 逐位复现的前提）")
	clock.call("set_deterministic", true, 60.0)
	await process_frame
	var row: Dictionary = dbg.call("sample_row")
	eq(String(row.get("draw_calls", "x")), "", "确定性模式 draw_calls 留空")
	eq(String(row.get("prims", "x")), "", "确定性模式 prims 留空")
	eq(String(row.get("ms_process", "x")), "", "确定性模式 ms_process 留空")
	eq(int(row.get("nodes", -1)), int(dbg.call("stats")["nodes"]),
			"行里的节点数与 stats() 一致（同一份事实）")
	# ⚠️ 本用例直接加载 diorama 夹具，路由器的栈是空的（`--script` 模式不替我们加载主场景，
	# 夹具也只是 add_child 的子节点）——所以这里断言的是"字段与路由器同源"，而不是写死 world。
	# 面板/CSV 不许自己发明一份场景事实。
	var sr := get_root().get_node_or_null("SceneRouter")
	eq(String(row.get("scene", "x")), String(dbg.call("scene_label")),
			"CSV 的 scene 列与面板同源（标签只算一次）")
	eq(String(dbg.call("stats")["route"]), String(sr.call("current_route")),
			"stats().route 保留路由器的原值（不改写事实）")
	eq(String(row.get("stack", "x")), ">".join(sr.call("route_stack")),
			"CSV 的 stack 列 == 路由器的栈（自底向上、'>' 连接）")
	eq(int(row.get("depth", -1)), int(sr.call("route_depth")), "depth 列 == route_depth()")
	clock.call("set_deterministic", false, 60.0)
	await process_frame
	var row2: Dictionary = dbg.call("sample_row")
	ok(String(row2.get("ms_process", "")) != "", "实时模式 ms_process 有真实值（C- 取证靠它）")
	eq(int(row2.get("frame", -1)), 0, "实时模式 frame 不再前进（Clock 的既有契约）")

	section("CSV：确定性模式下两个独立进程逐位一致")
	var base := _opt_out.path_join("obs")
	DirAccess.make_dir_recursive_absolute(base)
	var csv_shas: Array = []
	for label in ["a", "b"]:
		var dir := base.path_join("det_" + String(label))
		var csv := dir.path_join("obs.csv")
		if FileAccess.file_exists(csv):
			DirAccess.remove_absolute(csv)
		var out: Array = []
		# S1.0d：显式拍 diorama 夹具 —— 缺省开机场景已是空壳，draw_calls 恒为 0，
		# 那样"CSV 里有真实渲染指标"这条证据就没了。
		var code := _exec_user(PackedStringArray(), PackedStringArray([
			"--scene=" + DIORAMA_SCENE,
			"--shots", "--case=s0_boot", "--warmup=60", "--frames=15",
			"--obs-csv=" + csv, "--out=" + dir,
		]), out)
		eq(code, 0, "带 --obs-csv= 的截图批次 %s 退出码 = 0" % label)
		ok(FileAccess.file_exists(csv), "批次 %s 写下了 CSV" % label)
		csv_shas.append(FileAccess.get_sha256(csv) if FileAccess.file_exists(csv) else "")
	ok(String(csv_shas[0]) != "" and String(csv_shas[0]) == String(csv_shas[1]),
			"两份 CSV sha256 逐位一致（确定性模式下 CSV 是可复现证据）",
			"A=%s B=%s" % [csv_shas[0], csv_shas[1]])
	var det_lines := _read_lines(base.path_join("det_a").path_join("obs.csv"))
	ok(det_lines.size() > 10, "CSV 有表头 + 每帧一行", "行数=%d" % det_lines.size())
	# S1.0d：确定性模式下调试层**不采样**渲染列（draw_calls/prims 留空），所以这里改验
	# `scene` 列 —— 它证明 `--scene=diorama` 在真实批次里生效了，拍的不是缺省空壳。
	if det_lines.size() > 1:
		var det_row := String(det_lines[1]).split(",")
		if det_row.size() >= 10:
			eq(String(det_row[3]), "diorama", "CSV 的 scene 列 == diorama（--scene= 在批次里生效）")
	if det_lines.size() > 0:
		eq(String(det_lines[0]), "frame,t_s,dt_ms,scene,stack,depth,nodes,draw_calls,prims,ms_process",
				"表头 == 脚本里的列定义（两边不许各写一份）")

	section("--obs-csv= 是纯修饰符：单独出现不触发截图、不抢退出码")
	var solo_dir := base.path_join("solo")
	DirAccess.make_dir_recursive_absolute(solo_dir)
	var solo_csv := solo_dir.path_join("solo.csv")
	if FileAccess.file_exists(solo_csv):
		DirAccess.remove_absolute(solo_csv)
	var solo_out: Array = []
	# ⚠️ 必须**窗口模式**：headless 用的是 dummy 渲染器，`TIME_PROCESS` 没有意义 ——
	# 那样"列里有值"会退化成"列里是 0.000"，断言看起来通过、证据其实全假（实测踩过一次）。
	# ⚠️ 这里**不再**断言 `draw_calls > 0`：S1.2b 起开机主场景是战略图（有地形、仍无相机），
	# 一个空场景的 draw_calls 本来就是 0 —— 把它当失败是假红，把它当证据是假绿。
	# "窗口模式真在渲染"的证据改由上面 diorama 批次的 `det_draw_rows` 承担。
	# 另注：`--scene=` 只在截图批次里生效（换场景发生在 `Capture._run()`），
	# 所以这条"纯修饰符"探针跑的自然就是缺省的空壳场景。
	var solo_code := _exec_user(PackedStringArray(), PackedStringArray([
		"--obs-csv=" + solo_csv, "--quit-after=90",
	]), solo_out, 400)
	eq(solo_code, 0, "只带 --obs-csv= 的进程退出码 = 0（没有被截图批次抢走）")
	ok(FileAccess.file_exists(solo_csv), "CSV 落盘")
	var solo_lines := _read_lines(solo_csv)
	ok(solo_lines.size() >= 60, "至少 60 帧数据", "行数=%d" % solo_lines.size())
	var env_rows := 0
	for i in range(1, solo_lines.size()):
		var cols := String(solo_lines[i]).split(",")
		if cols.size() < 10:
			continue
		if float(String(cols[9])) > 0.0:
			env_rows += 1
	ok(env_rows >= 30, "实时模式 ms_process 列有**非零**实测值（C- 取证靠它）",
			"ms_process>0 的行数=%d" % env_rows)
	# S1.0d 的运行时证据：这个进程没有调用任何 `goto_*`，路由器却已把开机场景认领成 world ——
	# CSV 的 scene / stack / depth 三列如实写出 world / world / 1（`_sync()` 在生产进程里也成立）。
	if solo_lines.size() > 1:
		var solo_row := String(solo_lines[1]).split(",")
		if solo_row.size() >= 10:
			eq(String(solo_row[3]), "world", "CSV 的 scene 列 == world（开机即被认领，无需 goto_world）")
			eq(String(solo_row[4]), "world", "CSV 的 stack 列 == world")
			eq(int(String(solo_row[5])), 1, "CSV 的 depth 列 == 1（栈里恰好一条）")
	ok(not _dir_has_json(solo_dir), "--obs-csv= 没有触发截图批次（该目录无任何清单）")

	section("清理：状态复位，别把全局残留留给后面的用例")
	dbg.call("set_overlay", false)
	dbg.call("set_ui_hidden", false)
	_restore_defaults()
	InputSetup.ensure_debug_hotkeys(true)
	main.queue_free()
	await process_frame
	ok(get_first_node_in_group("main") == null, "夹具已释放，组 #main 清空")


## --- s0_4_cost ----------------------------------------------------------------
## S0.4 批次 2：调试层的开销（`C-`）与 B- 像素证据。
##
## ① 开销：120 个真实 `MeshInstance3D`（`MeshUtil.blob()` + `Style.toon()`，含反向外壳
##    描边）做夹具在场，**直接给叠加层自己的每帧工作计时**（`_push_sample()` 每帧 +
##    `_refresh()` 每 6 帧），5 轮 × 400 帧取中位数，要求 < 0.5ms。
##    为什么不量"开层/关层的帧时间差"：实测它在本工程没有分辨率 —— vsync 开着时差值
##    是负的（关层 18.75 / 开层 17.84ms，量到的是 vsync 等待）；关掉 vsync 改逐帧墙钟后，
##    注入确定的 2ms/帧 自旋负载只回收 41%（2.000 → 0.817）。这种断言叠加层再贵也会绿。
##    另外附一条**标尺**：用同一口径注入 0.5ms / 2ms 自旋，回收率≈100%，证明 0.5ms
##    这个阈值确实可分辨 —— 否则"< 0.5ms"是一句不可证伪的话。
## ② 反向对照：开层后 `draw_calls` 必须真的上升 —— 否则"开销 < 0.5ms"可能只是
##    "面板压根没画"。
## ③ B-：两张截图（叠加层开 / 全隐藏）× 两轮独立进程逐位一致、两图不同；再用像素
##    统计证明 F1 是**把 UI 从渲染里拿掉**：F1 后的图里 UI 面板的精确底色像素为 0，
##    而有 HUD 的同机位基准图里它成千上万。这是"拿掉"与"调透明/盖一层"的分水岭。
func _case_debug_cost() -> void:
	await process_frame
	var dbg := get_root().get_node_or_null("Debug")
	var clock := get_root().get_node_or_null("Clock")
	if not ok(dbg != null and clock != null, "Debug / Clock autoload 就位"):
		return
	_restore_defaults()
	dbg.call("set_overlay", false)
	dbg.call("set_ui_hidden", false)

	section("夹具：120 个真实实体（MeshUtil.blob + Style.toon，含反向外壳描边）")
	var main := await _load_diorama()
	if not ok(main != null, "diorama 夹具可加载"):
		return
	var terrain := get_first_node_in_group("terrain")
	var style := get_root().get_node_or_null("Style")
	if not ok(terrain != null and style != null, "terrain / Style 就位"):
		main.queue_free()
		return
	var holder := Node3D.new()
	holder.name = "DebugCostEntities"
	main.add_child(holder)
	var mesh := MeshUtil.blob(0.45, 5, 7)
	ok(mesh != null and mesh.get_surface_count() > 0, "夹具网格由 MeshUtil.blob() 生成（非 BoxMesh）")
	var mat: ShaderMaterial = style.call("toon", {"tint": style.call("pal", "grass")})
	ok(mat != null and mat.shader != null, "夹具材质由 Style.toon() 生成（带 3 阶梯度）")
	var made := 0
	for i in 120:
		var mi := MeshInstance3D.new()
		var gx := float(i % 12) - 5.5
		var gz := float(int(i / 12)) - 5.0
		var y := float(terrain.call("height_at", gx, gz))
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(gx * 1.8, y + 0.7, gz * 1.8)
		holder.add_child(mi)
		made += 1
	eq(made, 120, "120 个 MeshInstance3D 已挂到夹具世界")
	for i in 20:
		await process_frame   # 让网格上传/着色器编译/阴影贴图先稳定下来

	section("量法：直接给叠加层的每帧工作计时（帧时间差在本工程没有分辨率）")
	# 这一节是本用例最贵的一课，留作证据：
	#  ① vsync 开着时"开层/关层帧时间差"是**负**的（关层 18.75 / 开层 17.84 ms）——
	#    它量的是 vsync 等待与抖动，不是叠加层成本。
	#  ② 关掉 vsync 改成逐帧墙钟后，注入一个确定的 2ms/帧 自旋负载，**只回收 41%**
	#    （注入 2.000 量到 0.817）。即帧时间差对 0.5ms 量级既测不准也测不出。
	#  ⇒ 断言"开层 < 0.5ms"若建立在帧时间差上，叠加层再贵也会绿（沉默的绿灯）。
	#  改为把叠加层自己的每帧工作单独计时：`_push_sample()` 每帧、`_refresh()` 每
	#  REFRESH_EVERY 帧，与 `_process()` 的真实节奏一致，成本可归因、不掺其它节点。
	# vsync 仍要关：它不改变被测代码，但会让 CPU 空转等待，干扰同机其它测量。
	var vsync_before := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 10:
		await process_frame

	section("开销：叠加层每帧 CPU 成本 < 0.5ms（120 实体场景在场）")
	dbg.call("set_overlay", true)
	var ov_med: Array = []
	var ov_max := 0.0
	for r in 5:
		var ms: float = _time_overlay_frame(dbg, 400)
		ov_med.append(ms)
		ov_max = maxf(ov_max, ms)
	dbg.call("set_overlay", false)
	var ov_sorted := ov_med.duplicate()
	ov_sorted.sort()
	var ov_use: float = float(ov_sorted[ov_sorted.size() / 2])
	print("    · 叠加层每帧成本 5 轮：%s（中位数 %.4f ms，最大 %.4f ms）"
			% [str(ov_med), ov_use, ov_max])
	ge(ov_use, 0.0, "叠加层成本可测（%.4f ms/帧）" % ov_use)
	ok(ov_use < 0.5, "叠加层每帧成本 %.4f ms < 0.5ms（§3.3 / §5 S0.4）" % ov_use,
			"5 轮 %s" % str(ov_med))

	section("灵敏度对照：这套计时能分辨 0.5ms 吗？")
	# 一个计时器若连 0.5ms 的自旋都量不出来，用它判 0.5ms 就毫无意义。
	# 这里用同一个 `Time.get_ticks_usec()` 口径注入已知量，验证回收率 ≈ 100%。
	var probe_500: float = _spin_us(500)
	var probe_2000: float = _spin_us(2000)
	print("    · 标尺：注入 0.500 ms → 量到 %.4f ms；注入 2.000 ms → 量到 %.4f ms"
			% [probe_500, probe_2000])
	ok(probe_500 > 0.35, "0.5ms 量级可分辨（量到 %.4f ms）" % probe_500)
	ok(probe_2000 > 1.6, "2ms 量级可分辨（量到 %.4f ms）" % probe_2000)
	# 分辨率标定之后，"< 0.5ms" 才是一个**可证伪**的断言：真超标就会被量出来。
	ok(ov_use < probe_500, "叠加层成本小于 0.5ms 标尺本身（%.4f < %.4f）" % [ov_use, probe_500])

	section("反向对照：开层后 draw_calls 必须上升")
	var draw_off: Array = []
	var draw_on: Array = []
	for b in 4:
		var want_on := b % 2 == 1
		dbg.call("set_overlay", want_on)
		var m: Dictionary = await _sample_ms(60)
		if want_on:
			draw_on.append(float(m["draw_calls"]))
		else:
			draw_off.append(float(m["draw_calls"]))
	dbg.call("set_overlay", false)
	var mean_of := func(arr: Array) -> float:
		var s := 0.0
		for v in arr:
			s += float(v)
		return s / float(maxi(arr.size(), 1))
	var dc_off: float = mean_of.call(draw_off)
	var dc_on: float = mean_of.call(draw_on)
	ok(dc_on > dc_off, "反向对照：开层后 draw_calls 上升（面板真的在画）",
			"off=%.1f on=%.1f" % [dc_off, dc_on])
	# 恢复 vsync：后面的 B- 截图用例跑在同一台机器上，渲染节奏不该被本用例改掉。
	DisplayServer.window_set_vsync_mode(vsync_before)
	for i in 10:
		await process_frame
	eq(DisplayServer.window_get_vsync_mode(), vsync_before, "vsync 模式已复原（不留全局副作用）")

	section("B-：两张截图 × 两轮独立进程，逐位一致且互不相同")
	var base := _opt_out.path_join("debug")
	DirAccess.make_dir_recursive_absolute(base)
	var shas := {}
	for label in ["a", "b"]:
		for case_id in ["s0_4_overlay", "s0_4_ui_hidden"]:
			var dir := base.path_join("%s_%s" % [String(case_id), String(label)])
			var out: Array = []
			var code := _exec_user(PackedStringArray(), PackedStringArray([
				"--scene=" + DIORAMA_SCENE,
				"--shots", "--case=" + String(case_id), "--warmup=60", "--frames=15",
				"--out=" + dir,
			]), out)
			eq(code, 0, "%s/%s 退出码 = 0" % [case_id, label])
			var man := _read_json(dir.path_join(String(case_id) + ".json"))
			var shots: Array = man.get("shots", [])
			if ok(shots.size() == 1, "%s/%s 产出 1 张图" % [case_id, label],
					"实际 %d" % shots.size()):
				shas["%s/%s" % [String(case_id), String(label)]] = String(
						shots[0].get("sha256", ""))
	for case_id in ["s0_4_overlay", "s0_4_ui_hidden"]:
		var ha := String(shas.get(String(case_id) + "/a", ""))
		var hb := String(shas.get(String(case_id) + "/b", ""))
		ok(ha != "" and ha == hb, "%s 两轮 sha256 逐位一致" % case_id, "A=%s B=%s" % [ha, hb])
	ok(String(shas.get("s0_4_overlay/a", "")) != String(shas.get("s0_4_ui_hidden/a", "")),
			"『叠加层开』与『全隐藏』必须不同（否则 F3 或 F1 根本没生效）")

	section("B-：F1 是把 UI 从渲染里拿掉，而不是调透明度（像素证据）")
	# 同机位、同 warmup/frames、同确定性时钟，唯一的差别就是 UI 在不在：
	#   · `s0_boot_wide`  —— HUD 可见、调试层关闭（S0.4 之前的既有基线口径）
	#   · `02_ui_hidden`  —— F3 开层后 F1 全隐藏
	var ref_dir := base.path_join("boot_ref")
	var ref_out: Array = []
	var ref_code := _exec_user(PackedStringArray(), PackedStringArray([
		"--scene=" + DIORAMA_SCENE,
		"--shots", "--case=s0_boot", "--warmup=60", "--frames=15",
		"--out=" + ref_dir,
	]), ref_out)
	eq(ref_code, 0, "基准批次（s0_boot，HUD 可见）退出码 = 0")
	var ref_man := _read_json(ref_dir.path_join("s0_boot.json"))
	var ref_shots: Array = ref_man.get("shots", [])
	var ref_png := ref_dir.path_join("s0_boot_wide.png")
	var ref_sha := ""
	for s in ref_shots:
		if String(s.get("name", "")) == "s0_boot_wide":
			ref_sha = String(s.get("sha256", ""))
	ok(ref_sha != "", "拿到同机位基准图的 sha256")
	var hidden_png := base.path_join("s0_4_ui_hidden_a").path_join("02_ui_hidden.png")
	var on_png := base.path_join("s0_4_overlay_a").path_join("01_overlay_on.png")
	ok(FileAccess.file_exists(ref_png) and FileAccess.file_exists(hidden_png)
			and FileAccess.file_exists(on_png), "三张 PNG 都在盘上")
	ok(ref_sha != String(shas.get("s0_4_ui_hidden/a", "")),
			"有 HUD 与 F1 全隐藏两张图**必须不同**（HUD 真的占了像素）")
	# UI 面板底色（UiKit.PAPER #fff9e8）：3D 世界不用这个精确值（云是 #fffdf6、
	# 奶油是 #fff3d6），所以"精确匹配计数"能干净地把 UI 从画面里区分出来。
	var paper := Color("fff9e8")
	var n_ref := _count_exact_color_px(ref_png, paper)
	var n_hidden := _count_exact_color_px(hidden_png, paper)
	var n_on := _count_exact_color_px(on_png, paper)
	ok(n_ref > 0, "基准图里 UI 面板底色可见（%d 像素样本）" % n_ref)
	ok(n_hidden == 0, "F1 后的图里 UI 面板底色 **0 像素**（UI 被拿掉，不是被调透明）",
			"实测 %d" % n_hidden)
	ok(n_on > n_ref, "开层后 UI 底色像素变多（调试面板自己也画出来了）",
			"基准=%d 开层=%d" % [n_ref, n_on])

	section("清理")
	holder.queue_free()
	await process_frame
	main.queue_free()
	await process_frame
	_restore_defaults()
	ok(get_first_node_in_group("main") == null, "夹具已释放，组 #main 清空")


## --- s0_4_quick ---------------------------------------------------------------
## S0.4 批次 3：`F5` 快存 / `F9` 快读 + 菜单调试页（ROADMAP §5 S0.4）。
##
## 本用例存在的理由是**一条硬约束和一条对齐结论的冲突**：
##   * §3.5 写死"`F5`/`F9` 不允许绕过覆盖二次确认"，也写死"不得新增隐藏槽位或旁路存档"；
##   * 批次 3 的对齐结论是"直写、不弹菜单"。
## 两者能同时成立的唯一写法是：**确认落在按键上**（撞上已占用槽位时先不写，
## 窗口内再按一次 `F5` 才覆盖）。下面五组就是围绕它取证：
##   ① 全部写入都落在 `user://saves` 的 9 个真槽位文件上，目录里不许多出任何文件；
##   ② 空槽位一次 `F5` 就落盘，且**不打开菜单**（`is_open()` 全程为假）；
##   ③ 已占用槽位：第一次 `F5` 后文件 sha256 必须**不变**，第二次才变 —— 这是
##      "没有静默覆盖"的可观测证据，比读 `requires_confirm` 更硬；
##   ④ 没有当前槽位时拒绝，并且不发明一个槽位（旧存档一个都不许被动到）；
##   ⑤ 发布构建闸门：`ensure_debug_hotkeys(false)` 之后按键完全无反应。
## 另外顺带断言菜单调试页的只读事实与 `Debug.stats()` **同源**（不许自己算一份）。
func _case_quick() -> void:
	await process_frame
	var dbg := get_root().get_node_or_null("Debug")
	var saves := get_root().get_node_or_null("SaveSystem")
	var gs := get_root().get_node_or_null("GameState")
	if not ok(dbg != null and saves != null and gs != null,
			"Debug / SaveSystem / GameState 就位",
			"debug=%s saves=%s gs=%s" % [dbg, saves, gs]):
		return

	# `--all` 里前面的用例会留下全局状态，这里一律自带前置条件并事后还原。
	_restore_defaults()
	dbg.call("set_overlay", false)
	dbg.call("set_ui_hidden", false)
	_saves_begin()

	# 清空九格，保证下面的"空槽位直写"与既有存档无关（副本已备份）。
	for i in range(1, 10):
		var p: String = saves.call("slot_path", i)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	var main := await _load_diorama()
	if not ok(main != null, "diorama 夹具可加载"):
		_saves_end()
		return
	var menu := main.get_node_or_null(MENU_NODE)
	if not ok(menu != null, "菜单节点就位"):
		main.queue_free()
		_saves_end()
		return

	section("热键注册：F5/F9 与 F1/F3 同一个闸门")
	eq(bool(dbg.call("stats")["quick_hotkeys"]), true,
			"Debug 构建里 F5/F9 的 action 已注册（stats().quick_hotkeys）")
	for a in [InputSetup.ACTION_DEBUG_QUICK_SAVE, InputSetup.ACTION_DEBUG_QUICK_LOAD]:
		ok(InputMap.has_action(a), "action 存在：" + a)
		var keys := PackedInt32Array()
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey:
				keys.append((ev as InputEventKey).physical_keycode)
		ok(keys.has(KEY_F5 if a.ends_with("save") else KEY_F9),
				"绑定到正确的物理键（%s）" % ("F5" if a.ends_with("save") else "F9"))

	section("① 无当前槽位：拒绝，且不发明槽位")
	saves.set("current_slot", 0)
	var before := _saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR))
	var r0: Dictionary = dbg.call("quick_save")
	eq(bool(r0.get("ok", true)), false, "没有当前槽位时快存被拒绝")
	ok(String(r0.get("reason", "")).contains("槽位"), "拒绝理由说清是槽位问题",
			"理由=%s" % String(r0.get("reason", "")))
	ok(String(dbg.call("notice")).contains("槽位"), "提示行同时给出人话解释")
	eq(_saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR)), before, "一个存档文件都没被写（目录哈希不变）")
	var r1: Dictionary = dbg.call("quick_load")
	eq(bool(r1.get("ok", true)), false, "没有当前槽位时快读也被拒绝")

	section("② 空槽位：一次 F5 直写，全程不打开菜单")
	saves.set("current_slot", 2)
	eq(bool(menu.call("is_open")), false, "前置：菜单是关着的")
	var ok2: Dictionary = dbg.call("quick_save")
	eq(bool(ok2.get("ok", false)), true, "空槽位上一次快存就成功")
	eq(int(ok2.get("slot", 0)), 2, "写的就是当前槽位 2")
	eq(bool(ok2.get("requires_confirm", true)), false, "空槽位不需要确认")
	eq(bool(menu.call("is_open")), false, "**没有**打开菜单（批次 3 的对齐结论）")
	ok(FileAccess.file_exists(saves.call("slot_path", 2)), "槽位 2 的文件真的在盘上")
	var sha2a := FileAccess.get_sha256(saves.call("slot_path", 2))
	ok(sha2a != "", "能读到槽位 2 的 sha256")

	section("③ 已占用槽位：第一次不写，第二次才覆盖（§3.5 的确认没有被绕过）")
	# 先把世界改一下，让"覆盖"有可观测的内容差异（否则两次字节可能恰好相同）。
	gs.set("money", int(gs.get("money")) + 777)
	await process_frame
	eq(dbg.call("is_confirm_pending"), false, "前置：当前没有待确认项")
	var again: Dictionary = dbg.call("quick_save")
	eq(bool(again.get("ok", true)), false, "撞上已占用槽位时第一次快存**不成功**")
	eq(bool(again.get("requires_confirm", false)), true, "返回 requires_confirm=true（服务是唯一裁决）")
	eq(dbg.call("is_confirm_pending"), true, "进入『再按一次 F5 覆盖』的待确认状态")
	eq(int(dbg.call("confirm_pending_slot")), 2, "待确认的就是槽位 2")
	eq(FileAccess.get_sha256(saves.call("slot_path", 2)), sha2a,
			"**第一次按 F5 后旧存档逐位未变**（这是『没有静默覆盖』的硬证据）")
	ok(String(dbg.call("notice")).contains("再按一次"), "提示行告诉人要再按一次",
			"提示=%s" % String(dbg.call("notice")))
	var confirmed: Dictionary = dbg.call("quick_save")
	eq(bool(confirmed.get("ok", false)), true, "窗口内第二次快存成功")
	eq(bool(menu.call("is_open")), false, "覆盖同样没有打开菜单")
	var sha2b := FileAccess.get_sha256(saves.call("slot_path", 2))
	ok(sha2b != sha2a, "覆盖后字节确实变了（世界改动的确有落盘）",
			"前=%s 后=%s" % [sha2a, sha2b])
	eq(dbg.call("is_confirm_pending"), false, "确认用掉后不再挂着待确认状态")

	section("③b 确认窗口按帧过期：超时后又要重新按两次")
	saves.set("current_slot", 2)
	dbg.call("quick_save")  # 重新进入待确认
	eq(dbg.call("is_confirm_pending"), true, "又进入待确认")
	var clock := get_root().get_node_or_null("Clock")
	var consts: Dictionary = dbg.get_script().get_script_constant_map()
	var window := int(consts.get("CONFIRM_WINDOW_FRAMES", 0))
	ok(window > 0, "CONFIRM_WINDOW_FRAMES 是个正数", "实测 %d" % window)
	# 直接把截止帧推到现在之前（不改产品代码里的任何常量：只挪一次"现在"）。
	dbg.set("_confirm_until", int(clock.get("frame")) - 1)
	eq(dbg.call("is_confirm_pending"), false, "超过窗口后待确认自动失效")
	var sha2c := FileAccess.get_sha256(saves.call("slot_path", 2))
	dbg.call("quick_save")
	eq(FileAccess.get_sha256(saves.call("slot_path", 2)), sha2c,
			"过期后单按一次 F5 **不会**覆盖（回到『先拒绝』这一步）")

	section("④ 快读：读回当前槽位，字段与应用都来自服务")
	gs.set("money", 123456)
	await process_frame
	var loaded: Dictionary = dbg.call("quick_load")
	eq(bool(loaded.get("ok", false)), true, "快读成功")
	ok(int(gs.get("money")) != 123456, "GameState 的字段被存档内容覆盖了（真的应用了）",
			"现值=%d" % int(gs.get("money")))
	eq(bool(menu.call("is_open")), false, "快读也不打开菜单")

	section("⑤ 存档目录里只有 9 个真槽位：没有隐藏槽位、没有旁路文件")
	var stray: Array = []
	var d := DirAccess.open(ProjectSettings.globalize_path(SAVES_DIR))
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if not d.current_is_dir():
				var allowed := f.begins_with("slot_") and f.ends_with(".json")
				if allowed:
					var stem := f.get_basename().substr(5)
					allowed = stem.is_valid_int() and int(stem) >= 1 and int(stem) <= 9
				if not allowed:
					stray.append(f)
			f = d.get_next()
		d.list_dir_end()
	ok(stray.is_empty(), "存档目录里只有 9 个真槽位文件（旁路存档会在这里露出来）",
			"多余：%s" % [str(stray)])
	var quick_hits := _code_token_hits("res://scripts", "quicksave")
	ok(quick_hits.is_empty(), "产品代码里没有『快存专用文件』这种东西（quicksave 零命中）",
			"命中：%s" % [str(quick_hits)])

	section("⑥ 发布构建闸门：删掉 action 之后按键完全无反应")
	InputSetup.ensure_debug_hotkeys(false)
	for a in [InputSetup.ACTION_DEBUG_QUICK_SAVE, InputSetup.ACTION_DEBUG_QUICK_LOAD]:
		ok(not InputMap.has_action(a), "闸门关闭后 action 被真的删除：" + a)
	eq(bool(dbg.call("stats")["quick_hotkeys"]), false, "stats().quick_hotkeys 同步为假")
	gs.set("money", 42)
	saves.set("current_slot", 5)
	var before_gate := _saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR))
	var pressed: Dictionary = dbg.call("quick_save")
	eq(bool(pressed.get("ok", true)), false, "闸门关闭后直接调用也没有动作")
	eq(_saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR)), before_gate, "闸门关闭后按 F5 不产生任何存档写入")
	InputSetup.ensure_debug_hotkeys(true)
	ok(InputMap.has_action(InputSetup.ACTION_DEBUG_QUICK_SAVE), "恢复闸门（后续用例不受影响）")

	section("⑦ 菜单调试页：只读事实与 Debug.stats() 同源")
	menu.call("open_menu")
	menu.call("show_debug")
	eq(String(menu.call("page_name")), "debug", "『设置』进去落在调试页")
	eq(bool(menu.call("is_debug_page")), true, "is_debug_page() 同步为真")
	var facts: Dictionary = menu.call("debug_facts")
	var st: Dictionary = dbg.call("stats")
	eq(bool(facts.get("hotkeys", false)), bool(st.get("hotkeys", false)),
			"调试页的『热键』格子 == stats().hotkeys（同源，不自己算）")
	eq(bool(facts.get("quick_hotkeys", false)), bool(st.get("quick_hotkeys", false)),
			"调试页的『快存/快读』格子 == stats().quick_hotkeys")
	eq(bool(facts.get("overlay_on", false)), bool(st.get("overlay_on", false)),
			"调试页的『叠加层』格子 == stats().overlay_on")
	eq(String(facts.get("scene", "x")), String(st.get("scene_label", "y")),
			"调试页的场景标签 == Debug.scene_label()")
	eq(int(facts.get("slot", -1)), int(saves.get("current_slot")),
			"调试页的槽位 == SaveSystem.current_slot")
	var body := menu.get_node_or_null("Root/DebugPage/Panel/Col/Body") as Label
	ok(body != null and body.text.contains("F5"), "调试页正文里写明了 F5/F9",
			"正文=%s" % ("" if body == null else body.text.replace("\n", " / ")))
	# 【打开叠加层】按钮必须真的驱动 Debug，而不是只改自己那一行文字。
	# ⚠️ 本用例是 `pure`（`--headless`）：headless 下 `DisplayServer` 是 dummy、
	# 窗口尺寸为 0×0，注入的鼠标事件没有可命中的视口 ⇒ **不能**用 `_click_control`
	# 验按钮（实测点击"落下去"了却没人接）。鼠标命中路径由 headed 的
	# `s0_3_slots` 覆盖（同一个 `UiKit.button_page` 工厂、同一套页面结构），
	# 这里只验本步新增的东西：按钮在、按钮连着处理器、处理器真的驱动 Debug。
	dbg.call("set_overlay", false)
	var open_btn := menu.get_node_or_null("Root/DebugPage/Panel/Col/OpenOverlay") as Button
	ok(open_btn != null, "调试页有『打开叠加层』按钮（路径 Root/DebugPage/Panel/Col/OpenOverlay）")
	if open_btn != null:
		ok(open_btn.visible, "按钮随调试页一起可见")
		ok(open_btn.pressed.get_connections().size() >= 1, "按钮至少连了一个处理器")
		open_btn.pressed.emit()
		await process_frame
		ok(String(menu.call("hint_text")).contains("叠加层"),
				"处理器真的跑了（提示行被改写）",
				"提示=%s" % String(menu.call("hint_text")))
	eq(bool(dbg.call("is_overlay_on")), true, "调试页的『打开叠加层』按钮真的打开了叠加层")
	# ESC 从调试页回主页（与宫格同一层级语义）。
	await _press_escape()
	eq(String(menu.call("page_name")), "home", "ESC 从调试页回主页（不直接关菜单）")
	eq(bool(menu.call("is_open")), true, "此时菜单还开着")
	menu.call("close_menu")
	await process_frame

	section("清理")
	dbg.call("set_overlay", false)
	dbg.call("set_ui_hidden", false)
	for i in range(1, 10):
		var p: String = saves.call("slot_path", i)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	saves.set("current_slot", 0)
	main.queue_free()
	await process_frame
	_restore_defaults()
	_saves_end()
	ok(get_first_node_in_group("main") == null, "夹具已释放，组 #main 清空")


## --- s0_3_state ---------------------------------------------------------------
## S0.3 批次 1：三个全局服务（Rng / EventBus / GameState）的契约。
## 本用例**只断言契约**，不验证存档往返（那是 s0_3_roundtrip 的事）。
## 三条最值钱的断言：
##   ① GameState.world_seed 的默认值 == main.gd 的 @export 默认值
##      —— S1.2 把场景入口接到本服务时，世界必须逐位相同，否则 6 机位基线全废；
##   ② game_time 在固定逻辑步上**精确**前进（60 步 == 1.000 秒）
##      —— 这是 §3.2「60Hz 逻辑固定步」的实质验证，也排除了"用 _process 累加 delta"；
##   ③ Rng 的具名子流互不干扰（先抽别的流不改变本流的下一个数）
##      —— 这条正是"按 seed 派生子流"相对单一全局发生器的全部意义。
func _case_state() -> void:
	await process_frame

	var rng := get_root().get_node_or_null("Rng")
	var bus := get_root().get_node_or_null("EventBus")
	var gs := get_root().get_node_or_null("GameState")
	var ss := get_root().get_node_or_null("SaveSystem")
	var sr := get_root().get_node_or_null("SceneRouter")

	section("五个服务节点存在，且注册顺序满足依赖（Rng 先于 GameState，SaveSystem 在其后）")
	ok(rng != null, "autoload Rng 节点存在于 root")
	ok(bus != null, "autoload EventBus 节点存在于 root")
	ok(gs != null, "autoload GameState 节点存在于 root")
	ok(ss != null, "autoload SaveSystem 节点存在于 root")
	ok(sr != null, "autoload SceneRouter 节点存在于 root")
	if rng == null or bus == null or gs == null or ss == null or sr == null:
		return

	var order: Array = []
	for child in get_root().get_children():
		order.append(String(child.name))
	var i_rng := order.find("Rng")
	var i_bus := order.find("EventBus")
	var i_gs := order.find("GameState")
	var i_ss := order.find("SaveSystem")
	var i_sr := order.find("SceneRouter")
	ok(i_rng >= 0 and i_bus >= 0 and i_gs >= 0 and i_ss >= 0 and i_sr >= 0,
			"五个服务都在 root 子节点中", "root 子节点=%s" % [str(order)])
	ok(i_rng < i_gs, "Rng 注册在 GameState 之前（GameState._ready() 要调用 Rng.seed_from）",
			"Rng@%d GameState@%d" % [i_rng, i_gs])
	ok(i_bus < i_gs or i_bus != i_gs, "EventBus 与 GameState 顺序无强依赖，只要求都存在")
	ok(i_ss > i_gs, "SaveSystem 注册在 GameState 之后（它读写 GameState.snapshot()）",
			"GameState@%d SaveSystem@%d" % [i_gs, i_ss])
	ok(i_sr != i_ss and i_sr != i_gs,
			"SceneRouter 无 `_ready`/`_process`，与其它服务无顺序依赖，只要求存在",
			"SceneRouter@%d" % i_sr)

	section("autoload 清单与计数（§3.2 上限 10）")
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		var nm := String(p["name"])
		if nm.begins_with("autoload/"):
			autoloads.append(nm.substr("autoload/".length()))
	autoloads.sort()
	var expected := ["Capture", "Clock", "Debug", "EventBus", "GameState", "Rng",
			"SaveSystem", "SceneRouter", "Style"]
	eq(autoloads, expected, "project.godot 的 autoload 恰好是这 9 个（S0.4 批次 2 后 8 → 9）")
	ok(autoloads.size() <= 10, "autoload 数量 %d ≤ 10（§3.2 上限）" % autoloads.size())

	section("GameState 字段契约：SNAPSHOT_FIELDS == snapshot() 的键集")
	var gs_script: Script = gs.get_script()
	var props := {}
	if gs_script != null:
		for p in gs_script.get_script_property_list():
			props[String(p["name"])] = true
	for prop in ["world_seed", "game_time", "day_length", "party", "money",
			"food", "supply", "scene_kind", "player_pos", "playtime"]:
		ok(props.has(prop), "GameState.%s 属性存在" % prop)

	# 常量要走 get_script_constant_map()：Script.get() 只认脚本变量，读不到 const。
	var consts: Dictionary = {}
	if gs_script != null:
		consts = gs_script.get_script_constant_map()
	var fields: Array = consts.get("SNAPSHOT_FIELDS", [])
	ok(fields.size() == 10, "SNAPSHOT_FIELDS 常量可读且含 10 个字段",
			"读到 %d 个：%s" % [fields.size(), str(fields)])
	var snap: Dictionary = gs.call("snapshot")
	var snap_keys: Array = snap.keys()
	snap_keys.sort()
	var fields_sorted: Array = fields.duplicate()
	fields_sorted.sort()
	eq(snap_keys, fields_sorted, "snapshot() 的键集与 SNAPSHOT_FIELDS 完全一致（写读不会漂移）")
	ok(snap.has("player_pos") and typeof(snap["player_pos"]) == TYPE_ARRAY
			and (snap["player_pos"] as Array).size() == 3,
			"snapshot() 把 Vector3 降级为 [x,y,z]（JSON 无法编码引擎数学类型）")

	section("默认值与 main.gd 对齐（S1.2 接线必须逐位不变）")
	eq(gs.get("world_seed"), 20250929, "GameState.world_seed 默认值 == 20250929")
	var main_src := FileAccess.get_file_as_string("res://scripts/core/main.gd")
	ok(main_src.contains("var world_seed := 20250929"),
			"main.gd 的 world_seed 默认值仍是 20250929（两个来源同值，接线才不改变画面）")
	eq(gs.get("day_length"), 170.0, "GameState.day_length 默认值与 day_night.gd 一致（170 秒/天）")

	section("逻辑步：60Hz 固定步，前进量恒为 1/60 的整数倍（不掺真实 delta）")
	eq(Engine.physics_ticks_per_second, 60, "引擎物理步长 = 60Hz（§3.2 逻辑固定步）")
	print("    [note] SceneTree.physics_frame 在节点 _physics_process **之前**发射，")
	print("    [note] 所以 N 次 await 只对应 N-1 次 game_time 推进；下面断言『整数步』而非固定次数。")
	await physics_frame
	var t0: float = gs.get("game_time")
	for i in 60:
		await physics_frame
	var dt: float = float(gs.get("game_time")) - t0
	var steps := dt * 60.0
	var steps_int := roundi(steps)
	ok(absf(steps - float(steps_int)) < 0.000001,
			"前进量恰好是 %d 个 1/60 秒（整数步 ⇒ 时间只来自固定逻辑步；"
					% steps_int + "若改用 _process 累加真实 delta，这里会是非整数）")
	ok(absf(float(steps_int) - 60.0) <= 2.0,
			"60 次 await physics_frame 推进 %d 步（60±2，含上面的对齐抖动）" % steps_int)
	ok(gs.get("playtime") > 0.0, "playtime 随 game_time 一起推进")

	section("派生量：day / time_of_day / clock_text 自洽")
	gs.set("game_time", 0.0)
	eq(gs.call("game_day"), 1, "game_time=0 → 第 1 天")
	eq(gs.call("time_of_day"), 0.0, "game_time=0 → 午夜")
	gs.set("game_time", 170.0 * 2.0 + 170.0 * 0.5)
	eq(gs.call("game_day"), 3, "game_time=2.5 天 → 第 3 天")
	near(gs.call("time_of_day"), 0.5, 0.000001, "2.5 天处 time_of_day = 0.5（正午）")
	var clk := String(gs.call("clock_text"))
	ok(clk.contains("第 3 天") and clk.contains("12:00"), "clock_text 为『第 3 天 12:00』",
			"实际=%s" % clk)

	section("Rng：具名子流可复现、互不干扰、reset 可重放")
	rng.call("seed_from", 12345)
	var s_terrain: int = rng.call("stream_seed", "terrain")
	eq(rng.call("stream_seed", "terrain"), s_terrain, "stream_seed 是纯函数（同名同种子）")
	ok(rng.call("stream_seed", "scatter") != s_terrain,
			"同一主种子下不同流名派生出不同种子",
			"terrain=%d scatter=%d" % [s_terrain, rng.call("stream_seed", "scatter")])
	rng.call("seed_from", 999)
	ok(rng.call("stream_seed", "terrain") != s_terrain, "换主种子后同名流的种子改变")
	rng.call("seed_from", 12345)

	# 独立复现：两次全新构建的同名流，前 5 个数必须一致。
	var draw_a := _draw_ints(rng, "terrain", 5)
	rng.call("seed_from", 12345)
	var draw_b := _draw_ints(rng, "terrain", 5)
	eq(draw_a, draw_b, "同一主种子下 terrain 流前 5 个数逐位相同（可复现）")

	# 互不干扰：先把另一个流抽 10 次，再抽 terrain，结果不受影响。
	rng.call("seed_from", 12345)
	for i in 10:
		rng.call("randi_in", "scatter", 0, 1000000)
	var draw_c := _draw_ints(rng, "terrain", 5)
	eq(draw_c, draw_a, "先抽 10 次 scatter 后，terrain 的下一个数与全新运行时相同（子流隔离）")

	# reset 重放
	rng.call("seed_from", 12345)
	for i in 3:
		rng.call("randi_in", "terrain", 0, 1000000)
	rng.call("reset")
	var draw_d := _draw_ints(rng, "terrain", 5)
	eq(draw_d, draw_a, "reset() 后 terrain 流从头重放")

	section("EventBus：5 个信号齐全、参数形状固定、总线保持无状态")
	var bus_script: Script = bus.get_script()
	var sigs := {}
	if bus_script != null:
		for s in bus_script.get_script_signal_list():
			sigs[String(s["name"])] = s
	for sig in ["time_advanced", "encounter_started", "battle_finished",
			"resources_changed", "settlement_entered"]:
		ok(sigs.has(sig), "EventBus.%s 已声明" % sig)
	eq(sigs.size(), 5, "EventBus 恰好只声明这 5 个信号（总线上不许塞业务数据）；实际=%s" % [str(sigs.keys())])
	if sigs.has("time_advanced"):
		eq((sigs["time_advanced"]["args"] as Array).size(), 2,
				"time_advanced 携带 (day, time_of_day) 两个参数")
	if sigs.has("resources_changed"):
		eq((sigs["resources_changed"]["args"] as Array).size(), 3,
				"resources_changed 携带 (money, food, supply) 三个参数")

	# 真的能送达：连一个回调，emit，断言收到的是新值而不是差值。
	var received: Array = []
	var cb := func(m: int, f: int, s: int) -> void:
		received.append([m, f, s])
	bus.connect("resources_changed", cb)
	bus.emit_signal("resources_changed", 7, 8, 9)
	eq(received.size(), 1, "订阅者收到了 resources_changed")
	if received.size() == 1:
		eq(received[0], [7, 8, 9], "负载是传入的新值")
	bus.disconnect("resources_changed", cb)

	section("restore() 容错：未知 / 缺失 / 类型错误一律告警且不崩、不静默改值")
	gs.call("new_game", 20250929)
	gs.set("money", 111)
	var warn_unknown: PackedStringArray = gs.call("restore",
			{"money": 5, "no_such_field": 1})
	ok(warn_unknown.size() >= 1, "未知字段产生告警", "告警=%s" % [str(warn_unknown)])
	ok(_warn_mentions(warn_unknown, "no_such_field"), "告警里点名了未知字段 no_such_field")
	eq(gs.get("money"), 5, "已识别字段照常应用（money=5）")
	ok(_warn_mentions(warn_unknown, "world_seed"), "缺失字段 world_seed 也被点名")

	gs.set("money", 222)
	var warn_type: PackedStringArray = gs.call("restore", {"money": "很多钱"})
	eq(gs.get("money"), 222, "类型错误的字段保留当前值（不会被写成 0 或崩溃）")
	ok(_warn_mentions(warn_type, "类型错误"), "类型错误有明确告警",
			"告警=%s" % [str(warn_type)])

	gs.set("player_pos", Vector3.ZERO)
	var warn_pos: PackedStringArray = gs.call("restore",
			{"player_pos": {"x": 1.5, "y": -2.0, "z": 3.0}})
	eq(gs.get("player_pos"), Vector3(1.5, -2.0, 3.0), "player_pos 接受 {x,y,z} 字典形式")
	gs.call("restore", {"player_pos": [4.0, 5.0, 6.0]})
	eq(gs.get("player_pos"), Vector3(4.0, 5.0, 6.0), "player_pos 接受 [x,y,z] 数组形式")
	gs.call("restore", {"player_pos": "北方"})
	eq(gs.get("player_pos"), Vector3(4.0, 5.0, 6.0), "player_pos 为垃圾值时保留当前值")
	ok(warn_pos.size() >= 0, "（上面三次 restore 均未崩溃）")

	section("完整快照往返（同进程内；跨进程往返是 s0_3_roundtrip 的事）")
	gs.call("new_game", 4242)
	gs.set("game_time", 123.5)
	gs.set("money", 40)
	gs.set("food", 7)
	gs.set("supply", 3)
	gs.set("player_pos", Vector3(1.25, 2.5, -3.75))
	gs.call("set_scene_kind", 1)
	var snap2: Dictionary = gs.call("snapshot")
	gs.call("new_game", 1)
	eq(gs.get("world_seed"), 1, "new_game 真的重置了世界 seed")
	var warn_rt: PackedStringArray = gs.call("restore", snap2)
	eq(warn_rt.size(), 0, "完整快照 restore 无任何告警；告警=%s" % [str(warn_rt)])
	eq(gs.get("world_seed"), 4242, "world_seed 往返一致")
	near(gs.get("game_time"), 123.5, 0.000001, "game_time 往返一致")
	eq(gs.get("money"), 40, "money 往返一致")
	eq(gs.get("food"), 7, "food 往返一致")
	eq(gs.get("supply"), 3, "supply 往返一致")
	eq(gs.get("player_pos"), Vector3(1.25, 2.5, -3.75), "player_pos 往返一致")
	eq(gs.get("scene_kind"), 1, "scene_kind 往返一致")
	eq(gs.call("scene_kind_name"), "WORLD", "scene_kind_name 映射正确")

	section("现场还原（不污染后续用例）")
	gs.call("new_game", 20250929)
	rng.call("seed_from", 20250929)
	eq(gs.get("world_seed"), 20250929, "GameState 回到默认世界 seed")
	eq(rng.get("master_seed"), 20250929, "Rng 回到默认主种子")
	eq(gs.get("money"), 0, "资源清零")


## 抽 `n` 个整数，供"同名流可复现/互不干扰"的对照使用。
func _draw_ints(rng: Node, stream_name: String, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(rng.call("randi_in", stream_name, 0, 1000000))
	return out


## 告警里是否有一条提到某个字段/关键词。
func _warn_mentions(warns: PackedStringArray, needle: String) -> bool:
	for w in warns:
		if String(w).contains(needle):
			return true
	return false


## =============================================================================
##  S0.3 批次 2 —— SaveSystem（ROADMAP §5 S0.3，契约 §3.5）
## =============================================================================
## 证据分工：
##   s0_3_roundtrip    跨进程往返（子进程 A 写 → 父进程逐字段比对 → 子进程 B 读回）
##   s0_3_dirty        脏存档：拒读类与「可读但告警」类分开，迁移钩子真能跑
##   s0_3_atomic       跨进程并发写同一槽位，观测不到半截文件
##   s0_3_no_autosave  文件内容哈希 + mtime 零变化，且该检查确实能检出显式存档
##   s0_3_probe_*      打桩（hidden），只由上面三个用例以子进程拉起
##
## ⚠️ 全部用例期间 `user://saves` 被整体换名为 `user://saves.bak`（目录换名已实测
##    可用），所以验收**不会碰玩家真实存档**，产品码里也没有任何测试后门。

func _case_roundtrip() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	ok(ss != null, "autoload SaveSystem 节点存在于 root")
	if ss == null:
		return

	section("测试隔离（不动玩家真实存档）")
	var notes := _saves_begin()
	print("    [note] ", "; ".join(notes))

	section("子进程 A：新游戏 → 存档（写文件的是另一个进程）")
	var out_a: Array = []
	var code_a := _exec_case("s0_3_probe_write", out_a)
	ok(code_a == 0, "写档子进程退出码 = 0", "退出码=%d 输出=%s" % [code_a, _tail(out_a, 4)])
	ok(_lines_contain(out_a, "[probe] WRITE ok=true"), "子进程自称写入成功", _tail(out_a, 4))

	section("父进程直接读文件：schema_version / 时间戳 / game 段逐字段")
	var raw := FileAccess.get_file_as_string(_slot_file(ROUNDTRIP_SLOT))
	var parsed: Variant = JSON.parse_string(raw)
	ok(typeof(parsed) == TYPE_DICTIONARY, "槽 3 是合法 JSON 对象")
	var d: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	eq(int(d.get("schema_version", 0)), 1, "存档含 schema_version: 1")
	ok(String(d.get("saved_at", "")).length() >= 16, "含可读的真实写入时刻",
			str(d.get("saved_at", "")))
	ok(int(d.get("saved_at_unix", 0)) > 0, "含 unix 写入时刻", str(d.get("saved_at_unix", 0)))
	var game_v: Variant = d.get("game", {})
	var game: Dictionary = game_v if typeof(game_v) == TYPE_DICTIONARY else {}
	eq(game.size(), 10, "game 段含 10 个字段（与 GameState.SNAPSHOT_FIELDS 同量）")
	eq(int(game.get("world_seed", 0)), PROBE_SEED, "game.world_seed")
	near(float(game.get("game_time", -1.0)), PROBE_TIME, 0.000001, "game.game_time")
	eq(int(game.get("money", -1)), PROBE_MONEY, "game.money")
	eq(int(game.get("food", -1)), PROBE_FOOD, "game.food")
	eq(int(game.get("supply", -1)), PROBE_SUPPLY, "game.supply")
	eq(int(game.get("scene_kind", -1)), PROBE_SCENE_KIND, "game.scene_kind")
	near(float(game.get("day_length", -1.0)), 170.0, 0.000001, "game.day_length")
	var pos: Array = game.get("player_pos", [])
	eq(pos.size(), 3, "game.player_pos 为 [x,y,z]")
	if pos.size() == 3:
		near(float(pos[0]), PROBE_POS.x, 0.000001, "player_pos.x")
		near(float(pos[1]), PROBE_POS.y, 0.000001, "player_pos.y")
		near(float(pos[2]), PROBE_POS.z, 0.000001, "player_pos.z")
	var meta_v: Variant = d.get("meta", {})
	var meta: Dictionary = meta_v if typeof(meta_v) == TYPE_DICTIONARY else {}
	eq(int(meta.get("game_day", 0)), 1, "meta.game_day 与 game_time=123.5 自洽（第 1 天）")
	eq(String(meta.get("clock_text", "")), "第 1 天 17:26", "meta.clock_text 与 game_time 自洽")
	eq(String(meta.get("party_name", "")), "无名军团", "meta.party_name")
	eq(int(meta.get("party_level", 0)), 1, "meta.party_level")
	eq(int(meta.get("world_seed", 0)), PROBE_SEED, "meta.world_seed 与 game 段一致")
	ok(String(meta.get("playtime_text", "")).length() == 8, "meta.playtime_text 形如 HH:MM:SS",
			str(meta.get("playtime_text", "")))

	section("子进程 B：跨进程读档 → 回吐快照")
	var handoff := _opt_out.path_join(PROBE_SNAPSHOT_FILE)
	if FileAccess.file_exists(handoff):
		DirAccess.remove_absolute(handoff)
	ok(not FileAccess.file_exists(handoff), "回吐文件在子进程运行前不存在（陈旧文件不能冒充证据）")
	var out_b: Array = []
	var code_b := _exec_case("s0_3_probe_read", out_b)
	ok(code_b == 0, "读档子进程退出码 = 0", "退出码=%d 输出=%s" % [code_b, _tail(out_b, 4)])
	ok(_lines_contain(out_b, "[probe] READ ok=true"), "子进程自称读档成功", _tail(out_b, 4))
	ok(_lines_contain(out_b, "[probe] READ ok=true warnings=0"),
			"读回时零告警（写读字段集没有漂移）", _tail(out_b, 4))
	ok(_lines_contain(out_b, "[probe] SNAPSHOT_FILE "), "子进程 B 声明写出了回吐文件", _tail(out_b, 4))
	ok(FileAccess.file_exists(handoff), "回吐文件确实存在（另一个进程写、本进程读）", handoff)
	var snap: Dictionary = _read_json(handoff)
	eq(snap.size(), 10, "回吐快照含 10 个字段")
	eq(int(snap.get("world_seed", 0)), PROBE_SEED, "跨进程读回 world_seed")
	near(float(snap.get("game_time", -1.0)), PROBE_TIME, 0.000001, "跨进程读回 game_time")
	eq(int(snap.get("money", -1)), PROBE_MONEY, "跨进程读回 money")
	eq(int(snap.get("food", -1)), PROBE_FOOD, "跨进程读回 food")
	eq(int(snap.get("supply", -1)), PROBE_SUPPLY, "跨进程读回 supply")
	eq(int(snap.get("scene_kind", -1)), PROBE_SCENE_KIND, "跨进程读回 scene_kind")
	var bparty: Dictionary = snap.get("party", {})
	eq(String(bparty.get("name", "")), "无名军团", "跨进程读回 party.name（中文不被 stdout 编码破坏）")
	eq(int(bparty.get("level", 0)), 1, "跨进程读回 party.level")
	var bpos: Array = snap.get("player_pos", [])
	ok(bpos.size() == 3 and absf(float(bpos[0]) - PROBE_POS.x) < 0.000001
			and absf(float(bpos[1]) - PROBE_POS.y) < 0.000001
			and absf(float(bpos[2]) - PROBE_POS.z) < 0.000001,
			"跨进程读回 player_pos", str(bpos))

	section("覆盖契约：默认拒写、显式 overwrite 才生效")
	var slot3 := _slot_file(ROUNDTRIP_SLOT)
	var sha_before := FileAccess.get_sha256(slot3)
	var denied: Dictionary = ss.call("save_slot", ROUNDTRIP_SLOT)
	ok(not bool(denied.get("ok")), "槽位已占用时默认拒写", str(denied.get("reason")))
	ok(bool(denied.get("requires_confirm")), "结果标记 requires_confirm（批次 4 的菜单据此弹框）")
	ok(String(denied.get("reason")).contains("二次确认"), "原因说明需二次确认",
			str(denied.get("reason")))
	eq(FileAccess.get_sha256(slot3), sha_before, "拒写后原档逐位不变")
	var allowed: Dictionary = ss.call("save_slot", ROUNDTRIP_SLOT, true)
	ok(bool(allowed.get("ok")), "显式 overwrite=true 写入成功", str(allowed.get("reason")))
	ne(FileAccess.get_sha256(slot3), sha_before, "覆盖后内容确实变化")

	section("九宫格卡片数据（§3.5：槽号 / 真实时间 / 游戏内时间 / 队伍 / 时长）")
	var info3: Dictionary = ss.call("slot_info", ROUNDTRIP_SLOT)
	ok(bool(info3.get("exists")), "slot_info(3).exists")
	eq(int(info3.get("slot", 0)), ROUNDTRIP_SLOT, "卡片带槽号")
	eq(String(info3.get("party_name", "")), "无名军团", "卡片带队伍名")
	eq(int(info3.get("party_level", 0)), 1, "卡片带队伍等级")
	ok(String(info3.get("clock_text", "")).contains("第"), "卡片带游戏内日期时间",
			str(info3.get("clock_text", "")))
	ok(String(info3.get("saved_at", "")).length() >= 16, "卡片带真实写入时刻")
	ok(String(info3.get("playtime_text", "")).length() == 8, "卡片带累计时长",
			str(info3.get("playtime_text", "")))
	var info2: Dictionary = ss.call("slot_info", 2)
	ok(not bool(info2.get("exists")), "空槽位 exists=false")
	eq(String(info2.get("label", "")), "空槽位", "空槽位卡片文案")
	eq((ss.call("list_slots") as Array).size(), 9, "list_slots() 恰好 9 个槽位")

	section("空槽位与越界槽位")
	var empty_load: Dictionary = ss.call("load_slot", 2)
	ok(not bool(empty_load.get("ok")), "读空槽位失败（不是崩溃）")
	ok(String(empty_load.get("reason")).contains("空槽位"), "原因明说空槽位",
			str(empty_load.get("reason")))
	var oob: Dictionary = ss.call("save_slot", 10, true)
	ok(not bool(oob.get("ok")), "槽位号 10 越界被拒")
	ok(String(oob.get("reason")).contains("非法"), "越界原因明确", str(oob.get("reason")))
	ok(not bool(ss.call("slot_exists", 0)), "slot_exists(0) 为假")

	section("测试隔离回收")
	var back := _saves_end()
	print("    [note] ", "; ".join(back))
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "隔离目录已清走（saves.bak 不存在）")
	_restore_defaults()


func _case_dirty() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	var gs := get_root().get_node_or_null("GameState")
	ok(ss != null and gs != null, "SaveSystem / GameState 均存在")
	if ss == null or gs == null:
		return
	_saves_begin()
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)

	var load_failed_log: Array = []
	var loaded_log: Array = []
	var on_load_failed := func(slot: int, reason: String) -> void:
		load_failed_log.append([slot, reason])
	var on_slot_loaded := func(slot: int) -> void:
		loaded_log.append(slot)
	ss.connect("load_failed", on_load_failed)
	ss.connect("slot_loaded", on_slot_loaded)

	# 基线现场：可辨识的初始值，用来断言「缺失 / 类型错误字段保留当前值」
	gs.call("new_game", 777)
	gs.set("money", 555)
	gs.set("food", 111)
	gs.set("player_pos", Vector3(9.0, 9.0, 9.0))
	gs.set("game_time", 1.0)

	section("可用但脏：缺失字段逐条告警并保留当前值")
	_write_text(_slot_file(1), '{"schema_version": 1, "game": {}}')
	var r1: Dictionary = ss.call("load_slot", 1)
	ok(bool(r1.get("ok")), "空 game 段仍可读（字段级问题不该拒绝整个存档）",
			str(r1.get("reason")))
	var w1: PackedStringArray = r1.get("warnings", PackedStringArray())
	ge(w1.size(), 10, "10 个缺失字段各自告警（实际 %d 条）" % w1.size())
	ok(_warn_mentions(w1, "world_seed"), "告警点名 world_seed")
	ok(_warn_mentions(w1, "player_pos"), "告警点名 player_pos")
	eq(gs.get("money"), 555, "缺失的 money 保留当前值")
	eq(gs.get("player_pos"), Vector3(9.0, 9.0, 9.0), "缺失的 player_pos 保留当前值")

	section("可用但脏：未知字段 / 类型错误")
	_write_text(_slot_file(2), '{"schema_version": 1, "game": {"money": "很多钱", '
			+ '"game_time": "早晨", "food": 9, "no_such_field": 1}}')
	gs.set("money", 555)
	gs.set("game_time", 1.0)
	var r2: Dictionary = ss.call("load_slot", 2)
	ok(bool(r2.get("ok")), "类型错误字段不拒绝整个存档", str(r2.get("reason")))
	var w2: PackedStringArray = r2.get("warnings", PackedStringArray())
	ok(_warn_mentions(w2, "类型错误"), "类型错误有明确告警", str(w2))
	ok(_warn_mentions(w2, "no_such_field"), "未知字段被点名而不是静默丢弃", str(w2))
	eq(gs.get("money"), 555, "类型错误的 money 保留当前值")
	near(gs.get("game_time"), 1.0, 0.000001, "类型错误的 game_time 保留当前值")
	eq(gs.get("food"), 9, "同一文件里合法的 food 照常应用")

	section("不可用：拒读而不是崩溃，且一个字段都不改")
	var before_money: int = gs.get("money")
	var refuse_cases := [
		{"slot": 3, "text": "{oops", "needle": "JSON", "what": "非 JSON 文本"},
		{"slot": 4, "text": "[1, 2, 3]", "needle": "JSON 对象", "what": "数组根"},
		{"slot": 5, "text": '{"schema_version": 99, "game": {}}', "needle": "99",
			"what": "来自更高版本"},
		{"slot": 6, "text": '{"schema_version": 0, "game": {}}', "needle": "无迁移路径",
			"what": "无迁移路径的旧版本"},
		{"slot": 7, "text": '{"schema_version": 1}', "needle": "game", "what": "缺 game 段"},
		{"slot": 8, "text": '{"schema_version": 1, "game": "不是字典"}', "needle": "game",
			"what": "game 段类型错误"},
		{"slot": 3, "text": "", "needle": "读不出",
			"what": "0 字节空文件（读者重试花完后才报错）"},
		{"slot": 9, "text": '{"schema_version": 1, "game": {},', "needle": "JSON",
			"what": "被截断的 JSON（半截文件）"},
	]
	for c in refuse_cases:
		_write_text(_slot_file(int(c["slot"])), String(c["text"]))
		var r: Dictionary = ss.call("load_slot", int(c["slot"]))
		ok(not bool(r.get("ok")), "拒读：%s（不崩溃）" % c["what"], str(r.get("reason")))
		ok(String(r.get("reason")).contains(String(c["needle"])),
				"拒读原因点名 %s" % c["needle"], str(r.get("reason")))
	eq(gs.get("money"), before_money, "全部拒读之后 GameState 一个字段都没被改")
	eq(gs.get("world_seed"), 777, "world_seed 仍是拒读前的值")

	section("缺失 schema_version：告警并沿用当前版本")
	_write_text(_slot_file(1), '{"game": {"money": 12}}')
	var r7: Dictionary = ss.call("load_slot", 1)
	ok(bool(r7.get("ok")), "缺失 schema_version 仍按 v1 读取", str(r7.get("reason")))
	ok(_warn_mentions(r7.get("warnings", PackedStringArray()), "缺少 schema_version"),
			"告警说明缺失 schema_version")
	eq(gs.get("money"), 12, "字段照常应用")

	section("迁移钩子：v0 → v1 真能跑通（不是死代码）")
	_write_text(_slot_file(1), '{"schema_version": 0, "save": {"world_seed": 99, "money": 31}}')
	var no_hook: Dictionary = ss.call("load_slot", 1)
	ok(not bool(no_hook.get("ok")), "未注册钩子时 v0 被明确拒读", str(no_hook.get("reason")))
	var mig: Dictionary = ss.get("migrations")
	mig[0] = func(d: Dictionary) -> Dictionary:
		return {"schema_version": 1, "game": d.get("save", {})}
	gs.set("money", 0)
	var migrated: Dictionary = ss.call("load_slot", 1)
	ok(bool(migrated.get("ok")), "注册 v0→v1 钩子后同一文件可读", str(migrated.get("reason")))
	eq(gs.get("world_seed"), 99, "迁移后的 world_seed 生效")
	eq(gs.get("money"), 31, "迁移后的 money 生效")
	mig.erase(0)
	var after_erase: Dictionary = ss.call("load_slot", 1)
	ok(not bool(after_erase.get("ok")), "撤掉钩子后又拒读（证明生效的确实是钩子）",
			str(after_erase.get("reason")))

	section("信号契约：过去式事实，只在真的发生时发一次")
	eq(loaded_log, [1, 2, 1, 1], "slot_loaded 只在四次成功读档时各发一次")
	ge(load_failed_log.size(), refuse_cases.size() + 1,
			"load_failed 每次拒读都发（含撤钩子后那一次，实际 %d 次）" % load_failed_log.size())
	ok(not load_failed_log.is_empty() and String(load_failed_log[0][1]).length() > 0,
			"load_failed 负载带非空原因",
			str(load_failed_log[0] if not load_failed_log.is_empty() else []))
	ss.disconnect("load_failed", on_load_failed)
	ss.disconnect("slot_loaded", on_slot_loaded)

	var wrote_log: Array = []
	var on_save_written := func(slot: int, path: String) -> void:
		wrote_log.append([slot, path])
	ss.connect("save_written", on_save_written)
	var wsave: Dictionary = ss.call("save_slot", 1, true)
	ok(bool(wsave.get("ok")), "显式覆盖写入成功", str(wsave.get("reason")))
	eq(wrote_log.size(), 1, "save_written 发了一次")
	if wrote_log.size() == 1:
		eq(int(wrote_log[0][0]), 1, "save_written 带槽号")
		ok(String(wrote_log[0][1]).ends_with("slot_1.json"), "save_written 带路径",
				str(wrote_log[0][1]))
	ss.disconnect("save_written", on_save_written)

	section("测试隔离回收")
	_saves_end()
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "saves.bak 已清走")
	_restore_defaults()


func _case_atomic() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	ok(ss != null, "autoload SaveSystem 节点存在于 root")
	if ss == null:
		return
	_saves_begin()
	var slot_path := _slot_file(ATOMIC_SLOT)

	section("预置有效存档，再让子进程狂写同一槽位（父进程同时轮询）")
	var seed_save: Dictionary = ss.call("save_slot", ATOMIC_SLOT, true)
	ok(bool(seed_save.get("ok")), "预置槽 9 成功", str(seed_save.get("reason")))
	var summary_path := _opt_out.path_join(PROBE_LOOP_FILE)
	if FileAccess.file_exists(summary_path):
		DirAccess.remove_absolute(summary_path)
	ok(not FileAccess.file_exists(summary_path), "狂写统计文件在子进程运行前不存在（陈旧文件不能冒充证据）")
	var pid := _spawn_case("s0_3_probe_loop")
	ok(pid > 0, "狂写子进程已启动", "pid=%d" % pid)

	# 两种读法并行采样，因为它们证明的是不同的东西：
	#   (a) 裸读 —— 读者恰好在这一刻打开文件，会撞上引擎 rename 的非原子窗口；
	#   (b) 产品读档接口 —— 自带重试，它的失败次数才是玩家真正会遇到的。
	var samples := 0
	var half := 0
	var absent := 0
	var unreadable := 0
	var first_half := ""
	var reader_fails := 0
	var first_reader_fail := ""
	var money_seen := {}
	var deadline := Time.get_ticks_msec() + 30000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(slot_path):
			var txt := FileAccess.get_file_as_string(slot_path)
			if txt.strip_edges() == "":
				unreadable += 1
			elif _slot_text_is_complete(txt):
				samples += 1
				var seen_d := _parse_json_silent(txt)
				var seen_game: Dictionary = seen_d.get("game", {})
				money_seen[int(seen_game.get("money", -1))] = true
			else:
				half += 1
				if first_half == "":
					first_half = txt.substr(0, 96)
		else:
			absent += 1
		var lr: Dictionary = ss.call("load_slot", ATOMIC_SLOT)
		if not bool(lr.get("ok")):
			reader_fails += 1
			if first_reader_fail == "":
				first_reader_fail = String(lr.get("reason"))
		await process_frame

	var finished := pid > 0 and not OS.is_process_running(pid)
	ok(finished, "狂写子进程在 30 秒内自行结束（不是被超时打断）")
	if not finished and pid > 0:
		OS.kill(pid)
	var code := OS.get_process_exit_code(pid) if pid > 0 else -1
	ok(code == 0, "狂写子进程退出码 = 0（%d 次 save_slot 全部成功）" % ATOMIC_WRITES,
			"退出码=%d" % code)
	ge(samples, 20, "轮询期间读到 ≥ 20 次完整内容（否则本用例是空转，实际 %d 次）" % samples)
	ok(half == 0, "0 次半截/损坏内容：每一个读得出来的样本都是完整合法 JSON",
			"首个异常样本=%s（共 %d 次）" % [first_half, half])
	eq(reader_fails, 0, "风暴期间产品读档接口 0 次失败（读者重试用掉了引擎的非原子窗口）：%s"
			% first_reader_fail)
	ge(money_seen.size(), 2, "风暴期间读到过 ≥ 2 个不同的存档版本（实际 %d 种）" % money_seen.size())
	var max_money := -1
	for k in money_seen.keys():
		max_money = maxi(max_money, int(k))
	print("    [note] 裸读样本 %d 次：完整 %d / 半截 %d；不可读瞬间：文件不存在 %d / 存在但读不出 %d"
			% [samples + half + absent + unreadable, samples, half, absent, unreadable])
	print("    [note] 产品读档接口并发调用失败 %d 次；读到 %d 种不同版本（money 最大 %d）"
			% [reader_fails, money_seen.size(), max_money])

	section("写者自述（子进程不继承 stdout，只能靠文件说话）")
	var summary: Dictionary = _read_json(summary_path)
	eq(int(summary.get("writes", 0)), ATOMIC_WRITES, "写者自述写了 %d 次" % ATOMIC_WRITES)
	eq(int(summary.get("fails", -1)), 0, "写者自述 0 次失败：%s" % str(summary.get("first_reason", "")))
	eq(int(summary.get("last_published_money", -1)), ATOMIC_WRITES,
			"写者最后一版就是 money=%d" % ATOMIC_WRITES)

	# ⚠️ 这两段必须紧跟在轮询之后：本节后面的用例自己会重写槽 9，一旦中间插入写操作，
	# 「读者的最终版本 = 写者发布的最后一版」就不再是并发的事实，而只是巧合。
	section("风暴结束后：读者看到的最终版本 = 写者发布的最后一版（逐字节）")
	var final_txt := FileAccess.get_file_as_string(slot_path)
	ok(_slot_text_is_complete(final_txt), "槽 9 最终内容是完整合法 JSON")
	var final_d := _parse_json_silent(final_txt)
	var final_game: Dictionary = final_d.get("game", {})
	var final_money := int(final_game.get("money", -1))
	ok(final_money >= 1 and final_money <= ATOMIC_WRITES,
			"槽 9 的 money 是并发写入序列里的某个值（1..%d）" % ATOMIC_WRITES,
			"实际=%d" % final_money)
	eq(final_money, int(summary.get("last_published_money", -1)),
			"读者的最终版本与写者自述的最后一版一致（不是陈旧版本）")
	eq(FileAccess.get_sha256(slot_path), String(summary.get("last_published_sha", "")),
			"最终内容 sha256 与写者发布时自算的 sha256 完全一致")

	section("rename 被占用时：拒绝写入、原档不变、不留 .tmp（引擎实测语义）")
	var before_sha := FileAccess.get_sha256(slot_path)
	var hold := FileAccess.open(slot_path, FileAccess.READ)
	var blocked: Dictionary = ss.call("save_slot", ATOMIC_SLOT, true)
	if hold != null:
		hold.close()
	ok(not bool(blocked.get("ok")), "目标被读句柄占用时返回失败（不假装成功）",
			str(blocked.get("reason")))
	ok(String(blocked.get("reason")).contains("原存档保持不变"), "原因说明原档保持不变",
			str(blocked.get("reason")))
	eq(FileAccess.get_sha256(slot_path), before_sha, "失败后原存档逐位不变")
	ok(not FileAccess.file_exists(slot_path + ".tmp"), "失败后不残留 .tmp")
	var retried: Dictionary = ss.call("save_slot", ATOMIC_SLOT, true)
	ok(bool(retried.get("ok")), "句柄释放后同一槽位写入成功", str(retried.get("reason")))

	section("残留 .tmp 既不是槽位，也不会被当成存档")
	var tmp8 := _slot_file(8) + ".tmp"
	_write_text(tmp8, '{"schema_version": 1, "game": {}}')
	ok(not bool(ss.call("slot_exists", 8)), "slot_exists(8) 为假（.tmp 不算槽位）")
	var r8: Dictionary = ss.call("load_slot", 8)
	ok(not bool(r8.get("ok")), "load_slot(8) 拒绝")
	ok(String(r8.get("reason")).contains("空槽位"), "原因明说空槽位", str(r8.get("reason")))
	ok(FileAccess.file_exists(tmp8), "残留 .tmp 本身还在（不是被静默删除）")
	var w8: Dictionary = ss.call("save_slot", 8, true)
	ok(bool(w8.get("ok")), "写入槽 8 成功", str(w8.get("reason")))
	ok(not FileAccess.file_exists(tmp8), "写入成功后自己的 .tmp 被清理")

	section("测试隔离回收")
	_saves_end()
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "saves.bak 已清走")
	_restore_defaults()


func _case_no_autosave() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	ok(ss != null, "autoload SaveSystem 节点存在于 root")
	if ss == null:
		return
	_saves_begin()

	section("阶段 1：存档目录不存在时，跑满一整轮也不该建出任何存档")
	ok(not DirAccess.dir_exists_absolute(SAVES_DIR), "隔离后 user://saves 不存在")
	await _idle_run(90)
	var snap1 := _saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR))
	eq(snap1.size(), 0, "阶段 1 后仍无任何存档文件：%s" % str(snap1.keys()))
	ok(not DirAccess.dir_exists_absolute(SAVES_DIR),
			"阶段 1 后目录仍未被创建（服务没有 _ready 写盘，也没有别的隐式写动作）")

	section("阶段 2：目录已有存档时，全流程内容哈希与 mtime 零变化")
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	_write_text(_slot_file(1), '{"schema_version": 1, "game": {"money": 5}}')
	var before := _saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR))
	eq(before.size(), 1, "基线快照含 1 个文件")
	await _idle_run(90)
	eq(_saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR)), before, "本进程跑满一轮后哈希与 mtime 全不变")
	var out: Array = []
	var code := _exec_godot(PackedStringArray(["--headless", "--quit-after", "120"]), out)
	ok(code == 0, "子进程完整启动游戏 120 帧退出码 = 0",
			"退出码=%d 输出=%s" % [code, _tail(out, 4)])
	var errs := _error_lines(out)
	eq(errs.size(), 0, "子进程日志无 ERROR / SCRIPT ERROR：%s" % str(errs))
	eq(_saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR)), before, "另一个进程完整启动后哈希与 mtime 仍全不变")

	section("正面控制：显式存档必须被这套检查检出（否则上面是空转）")
	var wrote: Dictionary = ss.call("save_slot", 1, true)
	ok(bool(wrote.get("ok")), "显式 save_slot(1, true) 成功", str(wrote.get("reason")))
	ne(_saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR)), before, "显式存档后快照确实变化（内容哈希变了）")

	section("静态契约：服务里没有隐式写盘入口")
	var src := FileAccess.get_file_as_string("res://scripts/core/save_system.gd")
	# 只看代码、不看注释：文件顶部的契约说明里**提到**了这些名字，把它们算成证据就是
	# 自欺——注释不会写盘，也不能证明代码不写盘。
	var code_only := ""
	for raw in src.split("\n"):
		code_only += _strip_comment(String(raw), "gd") + "\n"
	ok(not code_only.contains("func _process"), "SaveSystem 没有 _process（不按帧写盘）")
	ok(not code_only.contains("func _physics_process"), "SaveSystem 没有 _physics_process")
	ok(not code_only.contains("func _ready"), "SaveSystem 没有 _ready（启动零动作）")
	ok(not code_only.contains("EventBus"), "SaveSystem 的代码不引用全局总线（没有事件触发的写盘）")
	eq(code_only.count("_atomic_write("), 2,
			"唯一的写盘路径 _atomic_write 只有 1 处定义 + 1 处调用（新增写入口必须显式登记）")

	section("测试隔离回收")
	_saves_end()
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "saves.bak 已清走")
	_restore_defaults()


## --- s0_3_router --------------------------------------------------------------
## 场景路由验收：world → battle → world 后世界回到同一个形状。
##
## 证据强度分三层，从弱到强：
##   1. `SceneTree.get_node_count()` 逐次相等 —— ROADMAP §5 S0.3 的字面验收；
##   2. 世界子树的**结构指纹**（去自动命名后的 类+子节点数 逐条序列）逐条一致 ——
##      比总数强：总数相同但节点换了位置/换了类也抓得住；
##   3. `Terrain.spawn_point` 与 `Scatter.stats` 这类**由 seed 派生**的值一致 ——
##      证明回来的是同一片地形，不是恰好同规模的另一片。
## 预设陷阱 3「change_scene_to_file 后旧场景不是当帧释放」在此正面回答：所有断言都在
## **等到目标场景真的成为 current_scene 之后再数两帧**，绝不靠固定延时。
func _case_router() -> void:
	await process_frame
	var router := get_root().get_node_or_null("SceneRouter")
	ok(router != null, "autoload SceneRouter 节点存在于 root")
	if router == null:
		return

	section("路由表与 API 契约")
	var names: Array = []
	for n in router.call("route_names"):
		names.append(String(n))
	names.sort()
	eq(names, ["battle", "world"], "登记的路由恰好是 world / battle 两条（S1.0d 收口）")
	eq(String(router.call("scene_path_for", "world")), WORLD_SCENE,
			"world → strategic_map.tscn（战略图接管世界）")
	eq(String(router.call("scene_path_for", "battle")), "res://scenes/battle/battle_stub.tscn",
			"battle → battle_stub.tscn")
	ok(not bool(router.call("is_known_route", "strategic")),
			"S1.0c 的临时名 strategic 已退役（一个文件只留一个名字）")
	eq(String(router.call("scene_path_for", "nowhere")), "", "未登记路由返回空路径")

	# S1.0a：路径是**三处**事实（路由表 / project.godot / 主场景文件本身），
	# 只改两处会让第三处静默漂移。这条断言把「改完用 git diff 逐行确认」升级成机器判定。
	section("三处事实源一致：路由表 == project.godot 的 run/main_scene == 真实存在的文件")
	var declared := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	eq(declared, WORLD_SCENE, "project.godot 的 run/main_scene 指向同一个文件")
	eq(declared, String(router.call("scene_path_for", "world")),
			"run/main_scene 与路由表的 world 条目逐字相同")
	ok(ResourceLoader.exists(declared), "该路径在文件系统里真的存在", declared)
	for sym in ["goto_world", "goto_battle", "return_to_world", "current_route",
			"route_stack", "route_depth", "route_names", "is_transitioning"]:
		ok(_has_callable(router, sym), "SceneRouter.%s" % sym)

	section("起点归一化：无论上一个用例留下什么，都先站到 world 上")
	if String(router.call("current_route")) != "world":
		ok(bool(router.call("goto_world")), "goto_world() 建立根路由", String(router.get("last_error")))
	var ok_start := await _await_route("world")
	ok(ok_start, "世界场景已就位（等待 current_scene 落地，不靠固定延时）")
	eq(String(router.call("current_route")), "world", "current_route() == world")
	eq(int(router.call("route_depth")), 1, "栈深 = 1")
	eq(_router_stack(router), ["world"], "route_stack() 自底向上 = [world]")

	section("信号接上：只播自己的路由事实，不冒充游戏事实")
	var seen: Array = []
	router.connect("route_changed", func(from: String, to: String) -> void:
		seen.append("%s->%s" % [from, to]))
	var bus := get_root().get_node_or_null("EventBus")
	var facts: Array = []
	if bus != null:
		for sig in ["encounter_started", "battle_finished"]:
			bus.connect(sig, func(_a: Dictionary) -> void:
				facts.append(sig))

	section("世界基线：S1.2c 起 world 是「地形 + 固定正午舞台 + 相机」")
	var base_nodes := get_node_count()
	var base_fp := _world_fingerprint(current_scene)
	ok(base_nodes > 5, "世界节点数 = %d（地形 + autoload，不是空指针）" % base_nodes)
	# 判据从 S1.0d 的「空壳」迁到「形如地形」：仍是能力断言，不是删断言 —— 根只有
	# 一个子节点、块里每个 MeshInstance3D 都真的有 mesh、而且**还没有相机**。
	# 判据第二次随交付物迁移（S1.2c）：世界现在有地形 + 固定正午舞台 + 相机，所以
	# 「指纹恰为『根 → 地形』、且没有相机」不再成立。换成的仍是能力断言：地形在、
	# 相机会渲染、舞台三件齐备 —— 而且明确要求「唯一 current 相机」，不比原来弱。
	ok(String(base_fp).begins_with("StrategicMap:Node3D:5|StrategicTerrain:Node3D:1|Chunks:Node3D:"),
			"结构指纹形如『根 → 地形 → 块容器』且根有 5 个子节点：%s" % String(base_fp).substr(0, 72))
	contains(base_fp, "StrategicCamera:Node3D:1|Camera3D:Camera3D",
			"结构指纹里有相机（S1.2c 的交付物）")
	var terr: Node = current_scene.get_node_or_null("StrategicTerrain")
	ok(terr != null, "世界有 StrategicTerrain")
	var cam_rig: Node = current_scene.get_node_or_null("StrategicCamera")
	ok(cam_rig != null, "世界有 StrategicCamera")
	var vp: Viewport = current_scene.get_viewport()
	var cams: Camera3D = null
	if vp != null:
		cams = vp.get_camera_3d()
	ok(cams != null, "视口里有 current 相机（画面不再全黑）")
	eq(current_scene.get_child_count(), 5,
			"根 5 个子节点：地形 + WorldEnvironment + Sun + DayNight + 相机")
	ok(current_scene.get_node_or_null("Sun") != null, "世界有 Sun（固定正午）")
	ok(current_scene.get_node_or_null("WorldEnvironment") != null, "世界有 WorldEnvironment")
	var chunk_n := 0
	var mesh_n := 0
	if terr != null:
		var chunks: Node = terr.get_node_or_null("Chunks")
		if chunks != null:
			for c in chunks.get_children():
				chunk_n += 1
				var mi := c as MeshInstance3D
				if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
					mesh_n += 1
	eq(mesh_n, chunk_n, "块节点 %d 个，全部带网格" % chunk_n)
	ge(float(mesh_n), 36.0, "至少 36 块陆地形（实测 %d 块）" % mesh_n)
	eq(get_nodes_in_group("main").size(), 0, "战略图不挂 #main 组（那是岛屿夹具的编排组）")
	eq(get_nodes_in_group("terrain").size(), 0, "战略图不套岛屿夹具的 #terrain 组（63 m 夹具）")
	eq(_world_seed_signature(), "", "战略图没有夹具的 seed 派生值（它是场 + 网格，不是夹具）")

	section("进入战斗：world → battle（含切换落地前的同帧语义）")
	ok(bool(router.call("goto_battle", {"reason": "s0_3_router"})), "goto_battle() 被接受",
			String(router.get("last_error")))
	# 陷阱 3：change_scene_to_file 只是登记请求，旧场景当帧还在树上。此刻再切一次必须被
	# 拦下，否则第二次请求会覆盖第一次，"路由栈"与最终屏幕将不一致。
	eq(String(router.call("current_route")), "battle",
			"落地前 current_route() 已如实反映『已提交的意图』（不因旧场景还在就撒谎）")
	ok(not bool(router.call("return_to_world", {"result": "early"})),
			"同一次切换落地前再调用 return_to_world() 被拒（并发切换保护）")
	contains(String(router.get("last_error")), "尚未落地", "拒绝理由点名『上一次切换尚未落地』")
	ok(await _await_route("battle"), "battle_stub 已成为 current_scene")
	eq(String(router.call("current_route")), "battle", "current_route() == battle")
	eq(int(router.call("route_depth")), 2, "栈深 = 2（上限）")
	eq(_router_stack(router), ["world", "battle"], "route_stack() = [world, battle]")
	var stub := get_first_node_in_group("battle_stub")
	ok(stub != null, "战斗占位场景已注册节点组 #battle_stub")
	ok(get_first_node_in_group("main") == null, "旧世界场景已不在树上（不是叠加渲染）")
	eq(get_nodes_in_group("terrain").size(), 0, "旧地形节点组已清空（change_scene 真的换掉了场景）")
	if stub != null:
		var arena: MeshInstance3D = stub.get_node_or_null("Arena")
		ok(arena != null, "占位场景含 Arena 网格节点")
		var cam: Camera3D = stub.get_node_or_null("Camera")
		ok(cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL,
				"占位场景用正交镜头（AGENTS.md 一.5）")
		if arena != null and arena.mesh != null:
			var faces: int = arena.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
			ok(faces > 100, "竞技场是面着色网格（%d 个三角面）" % faces)
			var mat := arena.material_override as ShaderMaterial
			ok(mat != null and mat.next_pass != null,
					"竞技场走 Style.toon() 且挂了逆壳描边 pass（next_pass 非空）")

	section("栈深与越界：拒绝必须显式，且不动当前场景")
	ok(not bool(router.call("goto_battle")), "战斗中再次 goto_battle() 被拒")
	contains(String(router.get("last_error")), "上限", "拒绝理由点名栈深上限")
	ok(not bool(router.call("goto_world")),
			"goto_world() 在战斗中不被当成『返回』（返回要走 return_to_world()）")
	contains(String(router.get("last_error")), "return_to_world", "拒绝理由指向 return_to_world()")
	eq(String(router.call("current_route")), "battle", "被拒后仍在 battle（拒绝不改状态）")

	section("返回世界：battle → world，世界回到同一个形状")
	ok(await _await_route_settled(), "等上一次切换彻底落地")
	ok(bool(router.call("return_to_world", {"result": "win", "turns": 3})), "return_to_world() 被接受",
			String(router.get("last_error")))
	ok(await _await_route("world"), "战略图重新成为 current_scene")
	eq(String(router.call("current_route")), "world", "current_route() 回到 world")
	eq(int(router.call("route_depth")), 1, "栈深回到 1（battle 条目已弹出）")
	var payload: Dictionary = router.call("current_payload")
	var result: Dictionary = payload.get("battle_result", {})
	eq(String(result.get("result", "")), "win", "世界条目收下了战斗结算结果（上下文传递不是空谈）")
	eq(int(result.get("turns", 0)), 3, "结算结果逐字段原样带回")
	eq(_count_scene_instances(WORLD_SCENE), 1, "世界里只有一个 StrategicMap 实例（没有泄漏的旧场景）")
	eq(get_nodes_in_group("main").size(), 0, "空壳世界仍没有 #main 组（与基线一致）")
	var after_nodes := get_node_count()
	eq(after_nodes, base_nodes, "★ 节点数 ±0：%d → %d" % [base_nodes, after_nodes])
	eq(_world_fingerprint(current_scene), base_fp,
			"★ 结构指纹逐条一致（%d 条）" % base_fp.split("|").size())

	section("非战斗状态下 return_to_world 被拒")
	ok(not bool(router.call("return_to_world")), "在世界里调 return_to_world() 被拒")
	contains(String(router.get("last_error")), "不在战斗场景", "拒绝理由说明当前不在战斗")

	section("信号账本：route_changed 逐次如实，游戏事实信号一次都没被冒发")
	eq(seen, ["world->battle", "battle->world"], "route_changed 恰好两次且顺序正确")
	eq(facts, [], "SceneRouter 没有冒发 encounter_started / battle_finished（留给 M1/M2）")

	section("并发保护：同一帧内连续两次切换，第二次必须被拒")
	var first := bool(router.call("goto_battle", {"reason": "race"}))
	var second := bool(router.call("goto_battle", {"reason": "race"}))
	ok(first and not second, "第一次接受、第二次拒绝（引擎只保留最后一次请求，故必须挡住）")
	var third := bool(router.call("return_to_world", {}))
	ok(not third, "切换在飞行中时 return_to_world() 也被拦下")
	ok(await _await_route("battle"), "战斗场景如实落地")
	ok(await _await_route_settled(), "等待切换彻底沉淀")
	ok(bool(router.call("return_to_world", {})), "沉淀后 return_to_world() 恢复正常")
	ok(await _await_route("world"), "回到世界")
	eq(seen, ["world->battle", "battle->world", "world->battle", "battle->world"],
			"两次往返共 4 次播报，被拒的调用一次都没播报")

	section("静态契约：路由表本体只有一个切场景入口，且本文件是唯一属主")
	var src := FileAccess.get_file_as_string("res://scripts/core/scene_router.gd")
	var code_only := ""
	for raw in src.split("\n"):
		code_only += _strip_comment(String(raw), "gd") + "\n"
	eq(code_only.count("change_scene_to_file("), 1, "切场景调用只有 1 处（唯一入口 _switch_to）")
	ok(not code_only.contains("func _process"), "SceneRouter 没有 _process（批次 4 的暂停不会卡住路由）")
	ok(not code_only.contains("func _ready"), "SceneRouter 没有 _ready（启动零动作）")
	ok(not code_only.contains("EventBus"), "SceneRouter 的代码不引用全局总线（不冒发游戏事实）")

	section("栈不撒谎：场景被外部释放后，current_route() 归空而不是沿用旧信念")
	var live: Node = current_scene
	ok(live != null, "世界场景仍在树上")
	live.queue_free()
	await process_frame
	await process_frame
	eq(String(router.call("current_route")), "", "场景消失后 current_route() 归空")
	eq(int(router.call("route_depth")), 0, "栈已清空")
	_restore_defaults()


## 等目标路由真的成为 current_scene（有界循环，不靠固定延时），再多等两帧让 `_ready`
## 里的世界生成彻底落定。陷阱 3 说 `change_scene_to_file` 后旧场景不是当帧释放——所以
## 取证时刻只能由"目标场景已就位"来定义。
func _await_route(route: String, max_frames := 120) -> bool:
	var router := get_root().get_node_or_null("SceneRouter")
	if router == null:
		return false
	var want := String(router.call("scene_path_for", route))
	for i in max_frames:
		await process_frame
		var cs: Node = current_scene
		if cs != null and cs.scene_file_path == want:
			await process_frame
			await process_frame
			# 路由器只在 public 调用里做对账；这里读一次让它清掉"在飞行中"标记，后续
			# 断言看到的状态才是沉淀后的状态。
			router.call("is_transitioning")
			return true
	return false


## 等 SceneRouter 的"切换在飞行中"标记清掉（它只在 current_scene 追上来时才清除）。
func _await_route_settled(max_frames := 120) -> bool:
	var router := get_root().get_node_or_null("SceneRouter")
	if router == null:
		return false
	for i in max_frames:
		await process_frame
		if not bool(router.call("is_transitioning")):
			return true
	return false


func _router_stack(router: Node) -> Array:
	var out: Array = []
	for e in router.call("route_stack"):
		out.append(String(e))
	return out


## 统计根下有多少个节点的 `scene_file_path` 等于给定路径。
##
## 用途：证明"`goto_world()` 被拒时没有把同一个文件重载一遍" —— 只断言路由栈不变
## 抓不到重复加载（栈会被 `_sync()` 归一到同一个名字，但屏幕上可能多了一个世界）。
func _count_scene_instances(path: String) -> int:
	var root := get_root()
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur != root and cur.scene_file_path == path:
			count += 1
		for c in cur.get_children():
			stack.append(c)
	return count


## 世界结构指纹：去自动命名（`@MeshInstance3D@28` 里带全局计数器，两次加载必然不同）后
## 逐条记录「名字或类 : 类 : 子节点数」。比节点总数强：总数相同但结构换了也抓得住。
##
## `root` 缺省时取 `#main` 组（diorama 夹具的入口）；S1.0d 之后战略图没有 `#main`
## 组，路由用例改为显式传 `current_scene` —— 这样两个世界都能被同一套指纹度量，
## 而不是"空壳时指纹恒为空、相等断言自动真空通过"。
func _world_fingerprint(root: Node = null) -> String:
	var ctx := {"parts": PackedStringArray()}
	var top: Node = root if root != null else get_first_node_in_group("main")
	_walk_fingerprint(top, ctx)
	return "|".join(ctx["parts"])


func _walk_fingerprint(n: Node, ctx: Dictionary) -> void:
	if n == null:
		return
	var label := String(n.name)
	if label.begins_with("@"):
		label = n.get_class()
	ctx["parts"].append("%s:%s:%d" % [label, n.get_class(), n.get_child_count()])
	for c in n.get_children():
		_walk_fingerprint(c, ctx)


## seed 派生值：只有同一个 seed 才会得到同一片地形，光看节点数区分不了。
func _world_seed_signature() -> String:
	var out := PackedStringArray()
	var terrain := get_first_node_in_group("terrain")
	var main := get_first_node_in_group("main")
	if terrain != null:
		out.append("spawn=%s" % [terrain.get("spawn_point")])
		out.append("h00=%.6f h55=%.6f" % [
			float(terrain.call("height_at", 0.0, 0.0)),
			float(terrain.call("height_at", 5.0, -5.0)),
		])
	if main != null:
		var scatter := main.get_node_or_null("Scatter")
		if scatter != null:
			var st: Dictionary = scatter.get("stats")
			out.append("trees=%s rocks=%s" % [st.get("trees"), st.get("rocks")])
	return " ".join(out)


## --- s0_3_slots ---------------------------------------------------------------
## S0.3 批次 4：存档菜单与九宫格（ROADMAP §5 S0.3，交互契约 §3.5）。
##
## 四组最值钱的断言：
##   ① **暂停契约**（预登记陷阱 1 的实测版）：ESC 打开菜单 ⇒ `paused == true`，
##      而菜单自己 `can_process()` 仍为真、`Clock` 仍在精确前进。暂停会停掉
##      autoload 的 `_process` 是引擎语义，不是猜测；修复是给菜单与 Clock 显式
##      `PROCESS_MODE_ALWAYS`，所以这里必须能观测到两者的差别。
##   ② **宫格不撒谎**：九张卡片的正文逐个 == `SaveSystem.slot_info(slot).label`。
##      宫格自己不算、不缓存槽位数据，"显示的和存的是同一件事"才是可证的。
##   ③ **服务是唯一裁决**：没有当前槽位时点「保存」跳宫格（`save_current()` 的
##      契约原文就是「保存等同另存为」），菜单不自己发明一句提示。
##   ④ **B- 四张截图**：两个数据状态（一个档都没有 / 九格全满）× 两轮独立进程，
##      逐位一致；四张两两不同；每张都非空图。截图状态由**注入的真实输入**达成，
##      产品码里没有"演示状态"后门；子进程的 `ui_expect` 自证到达了声明的界面，
##      对不上就以非 0 退出（否则"拍错屏"会变成一张看着正常的 PNG）。
func _case_slots() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	var clock := get_root().get_node_or_null("Clock")
	if ss == null or clock == null:
		ok(false, "SaveSystem / Clock autoload 就位", "ss=%s clock=%s" % [ss, clock])
		return

	section("环境：user://saves 整体让位（用例只动隔离目录）")
	# `--all` 里上一个用例可能正停在某个槽位上；本用例要从"全新存档"起步，
	# 所以自带前置条件而不是依赖进程恰好是新的。
	_restore_defaults()
	eq(int(ss.get("current_slot")), 0, "前置条件：这一步从『没有选中槽位』起步")
	for n in _saves_begin():
		print("    · ", n)
	ok(not DirAccess.dir_exists_absolute(SAVES_DIR), "起步是『一个存档都没有』的干净状态")

	section("装配：菜单隐藏挂载、层高于调试 HUD、注册到 group=menu")
	var main := await _load_diorama()
	if main == null:
		ok(false, "diorama 夹具可加载")
		_saves_end()
		return
	var menu := main.get_node_or_null(MENU_NODE)
	if not ok(menu != null, "diorama 夹具挂着 MenuLayer"):
		main.queue_free()
		_saves_end()
		return
	ok(get_nodes_in_group("menu").size() == 1, "group=menu 恰好一个节点")
	ok(not bool(menu.call("is_open")), "启动时菜单是关的")
	ok(not (menu as CanvasLayer).visible, "启动时菜单不可见（否则 B- 六机位基线会被盖住）")
	var hud := main.get_node_or_null("UI") as CanvasLayer
	ok(hud != null and (menu as CanvasLayer).layer > hud.layer,
			"菜单层号高于调试 HUD 层号（遮挡关系靠 layer，不靠节点顺序）")
	ok(_menu_node(menu, "grid") != null, "宫格组件在树上")
	ok(_menu_node(menu, "save_as") is Button, "主页五个入口都是可点按钮")

	section("暂停契约：世界停、菜单与 Clock 不停（陷阱 1）")
	ok(InputMap.has_action("ui_cancel"), "存在内建 ui_cancel（ESC 走它，不改 keymap）")
	var esc_bound := false
	for ev in InputMap.action_get_events("ui_cancel"):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE:
				esc_bound = true
	ok(esc_bound, "ui_cancel 绑定到 Escape")
	await _press_escape()
	ok(bool(menu.call("is_open")), "ESC 打开菜单")
	eq(String(menu.call("page_name")), "home", "打开后落在主页")
	ok(paused, "菜单打开时 get_tree().paused == true")
	ok(not main.can_process(), "暂停时夹具世界 can_process() == false（世界真的停了）")
	ok(menu.can_process(), "暂停时菜单 can_process() == true（否则它连点击都收不到）")
	ok(clock.can_process(), "暂停时 Clock can_process() == true")
	# Clock 照走：先切到确定性模式，好让"照走"是可数的而不是"看起来在动"。
	# 确定性模式下 `t == frame/hz`，所以暂停期间两者的前进量都能逐帧对上。
	clock.call("set_deterministic", true, 60.0)
	var f0 := int(clock.get("frame"))
	var t0 := float(clock.get("t"))
	var pf0 := Engine.get_process_frames()
	for i in 30:
		await process_frame
	eq(int(clock.get("frame")) - f0, 30, "暂停中 Clock.frame 精确前进 30 帧")
	near(float(clock.get("t")) - t0, 0.5, 0.0001, "暂停中 Clock.t 精确前进 0.5s（30/60）")
	eq(Engine.get_process_frames() - pf0, 30, "暂停中主循环仍在出帧（30 帧）")
	clock.call("set_deterministic", false)

	section("无当前槽位：『保存』按契约跳宫格、『读取』失败不改任何状态")
	contains(String(menu.call("hint_text")), "ESC", "初始提示语告诉玩家 ESC 的语义")
	var save_btn := _menu_node(menu, "save") as Button
	await _click_control(save_btn)
	eq(String(menu.call("page_name")), "grid", "无当前槽位时『保存』跳宫格")
	ok(not bool(menu.call("confirm_open")), "此时不该弹覆盖确认（没有旧档可覆盖）")
	contains(String(menu.call("hint_text")), "保存等同", "提示语引用 save_current() 的契约原文")
	await _click_control(_menu_node(menu, "back") as Button)
	eq(String(menu.call("page_name")), "home", "宫格『返回』回主页")

	await _click_control(_menu_node(menu, "load") as Button)
	eq(String(menu.call("page_name")), "grid", "无当前槽位时『读取』也跳宫格")
	contains(String(menu.call("hint_text")), "读取", "读取态提示语说明点击语义")
	await _click_control(_menu_node(menu, _menu_card_path(5)) as Button)
	contains(String(menu.call("hint_text")), "空槽位", "点空槽位给出『空槽位』理由")
	eq(int(ss.get("current_slot")), 0, "失败的读取不改当前槽位")
	eq(_saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR)).size(), 0, "失败的读取不写任何文件")
	await _click_control(_menu_node(menu, "back") as Button)

	section("空槽位写入：点第 5 格直接写盘，卡片立刻刷新")
	await _click_control(_menu_node(menu, "save_as") as Button)
	eq(String(menu.call("page_name")), "grid", "『另存为』进宫格")
	var body5 := _menu_node(menu, _menu_card_body_path(5)) as Label
	eq("" if body5 == null else body5.text, "空槽位", "第 5 格点之前是空槽位")
	await _click_control(_menu_node(menu, _menu_card_path(5)) as Button)
	ok(FileAccess.file_exists(_slot_file(5)), "slot_5.json 已写出")
	ok(not bool(menu.call("confirm_open")), "写空槽位不该弹覆盖确认")
	eq(int(ss.get("current_slot")), 5, "写成功后 current_slot == 5")
	eq(String(menu.call("page_name")), "home", "写成功后回主页")
	contains(String(menu.call("hint_text")), "已保存到槽位 5", "提示语点明槽位号")
	ok(_slot_text_is_complete(FileAccess.get_file_as_string(_slot_file(5))),
			"写出的存档是完整合法 JSON（schema 1 + game.money）")
	eq(_saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR)).size(), 1, "只写出一个文件（没有 .tmp 残留）")
	var info5: Dictionary = ss.call("slot_info", 5)
	eq("" if body5 == null else body5.text, String(info5.get("label", "")),
			"第 5 格正文刷新成服务给的 label（宫格不缓存）")
	ok(not String(info5.get("label", "")).is_empty(), "服务确实给了非空 label")
	contains(String((_menu_node(menu, "status") as Label).text), "当前槽位：5",
			"主页状态行显示当前槽位 5")

	section("ESC 层级：宫格 → 主页 → 关闭（并解除暂停）")
	await _click_control(_menu_node(menu, "save_as") as Button)
	eq(String(menu.call("page_name")), "grid", "再次进入宫格")
	await _press_escape()
	eq(String(menu.call("page_name")), "home", "ESC 从宫格回主页（不直接关菜单）")
	ok(bool(menu.call("is_open")), "此时菜单仍开着")
	await _press_escape()
	ok(not bool(menu.call("is_open")), "第二次 ESC 关闭菜单")
	ok(not paused, "关闭后解除暂停")
	ok(not (menu as CanvasLayer).visible, "关闭后不可见")
	ok(main.can_process(), "关闭后夹具世界恢复处理")

	section("B- 截图：两个数据状态 × 两轮独立进程")
	await _shoot_menu_rounds()

	main.queue_free()
	await process_frame
	for n in _saves_end():
		print("    · ", n)
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "saves.bak 已还原、无残留")
	_restore_defaults()


## --- s0_3_overwrite -----------------------------------------------------------
## S0.3 批次 4 的另一半：**先问后写**。
##
## 最值钱的一条是「取消 = 旧档逐位不变」：它同时否掉了两种常见错法 ——
## 先写后问（写坏了再问，问也没用），以及确认框只是个动画（点了取消文件早换了）。
## 比较口径用目录快照（每个文件的 sha256 + mtime），整目录逐项相等才算数。
##
## 另外订阅 `save_written` 数写入次数：**同一秒内状态没变时，两次存档的字节可以
## 逐位相同**（`saved_at` 只到秒），所以"文件内容变了"不是一条能站住的断言；
## 能站住的是"到底发布了几次写入"—— 取消必须 0 次，确认必须 +1。
func _case_overwrite() -> void:
	await process_frame
	var ss := get_root().get_node_or_null("SaveSystem")
	if ss == null:
		ok(false, "SaveSystem autoload 就位")
		return
	var writes := [0]
	var on_write := func(_slot: int, _path: String) -> void: writes[0] += 1
	ss.connect("save_written", on_write)

	section("环境：让位 saves/，先写一个真存档当靶子")
	_restore_defaults()
	for n in _saves_begin():
		print("    · ", n)
	var main := await _load_diorama()
	var menu := main.get_node_or_null(MENU_NODE)
	if not ok(menu != null, "MenuLayer 在树上"):
		main.queue_free()
		_saves_end()
		return
	await _press_escape()
	await _click_control(_menu_node(menu, "save_as") as Button)
	await _click_control(_menu_node(menu, _menu_card_path(3)) as Button)
	ok(FileAccess.file_exists(_slot_file(3)), "槽位 3 先写入一次（空槽位无需确认）")
	var before := _saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR))
	var sha_before := String((before.get("slot_3.json", {}) as Dictionary).get("sha256", ""))
	ok(sha_before != "", "拿到了覆盖前的 sha256 锚点", "sha=%s" % sha_before)
	eq(writes[0], 1, "空槽位那一次确实发布了写入")

	section("点击已占用槽位：整页弹窗先问，问的时候旧档一个字节都没动")
	await _click_control(_menu_node(menu, "save_as") as Button)
	await _click_control(_menu_node(menu, _menu_card_path(3)) as Button)
	ok(bool(menu.call("confirm_open")), "弹出了覆盖确认")
	eq(String(menu.call("page_name")), "grid", "弹窗叠在宫格页上（独立整页弹窗，不是行内提示）")
	var dialog := _saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR))
	eq(dialog, before, "弹窗期间 saves/ 逐项不变（先问后写）")
	contains(String((_menu_node(menu, "confirm_title") as Label).text), "槽位 3",
			"弹窗标题点明槽位号")
	contains(String((_menu_node(menu, "confirm_detail") as Label).text),
			String(ss.call("slot_info", 3).get("label", "")), "弹窗正文引用该档的 label")
	contains(String((_menu_node(menu, "confirm_detail") as Label).text),
			String(ss.call("slot_info", 3).get("saved_at", "")), "弹窗正文给出存档时间")

	section("ESC 层级：先取消弹窗，不关菜单")
	await _press_escape()
	ok(not bool(menu.call("confirm_open")), "ESC 先取消弹窗")
	ok(bool(menu.call("is_open")), "菜单仍然开着")
	eq(String(menu.call("page_name")), "grid", "取消后仍在宫格页（可以改选别格）")
	eq(_saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR)), before, "取消后 saves/ 逐项不变（sha256 与 mtime 都算）")
	eq(writes[0], 1, "取消期间一次写入都没发布（先问后写）")
	contains(String(menu.call("hint_text")), "已取消", "提示语说明是取消")

	section("确认覆盖：只有点了确认才落盘")
	await _click_control(_menu_node(menu, _menu_card_path(3)) as Button)
	ok(bool(menu.call("confirm_open")), "再次弹出确认")
	await _click_control(_menu_node(menu, "confirm_yes") as Button)
	ok(not bool(menu.call("confirm_open")), "确认后弹窗关闭")
	eq(String(menu.call("page_name")), "home", "覆盖成功后回主页")
	contains(String(menu.call("hint_text")), "已覆盖槽位 3", "提示语点明是『覆盖』")
	var after := _saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR))
	eq(writes[0], 2, "确认后确实又发布了一次写入（取消 0 次、确认 +1）")
	ok(String((after.get("slot_3.json", {}) as Dictionary).get("sha256", "")) != "",
			"确认后槽位 3 仍是一份存档（同秒内字节可能逐位相同，故不拿哈希当判据）")
	eq(after.size(), 1, "覆盖只动这一个文件（没有多出 .tmp）")
	ok(_slot_text_is_complete(FileAccess.get_file_as_string(_slot_file(3))),
			"覆盖后的存档仍是完整合法 JSON")

	section("主页『保存』：写当前槽位同样先问（服务是唯一裁决，不静默覆盖）")
	await _click_control(_menu_node(menu, "save") as Button)
	ok(bool(menu.call("confirm_open")), "『保存』写已占用的当前槽位时先问")
	eq(String(menu.call("page_name")), "home", "『保存』不跳宫格（当前槽位已选中）")
	var asked := _saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR))
	await _click_control(_menu_node(menu, "confirm_no") as Button)
	ok(not bool(menu.call("confirm_open")), "『取消（保留旧存档）』关闭弹窗")
	eq(_saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR)), asked, "取消后旧档逐项不变")
	eq(writes[0], 2, "『保存』弹窗里取消：写入次数没有增加")
	await _click_control(_menu_node(menu, "save") as Button)
	await _click_control(_menu_node(menu, "confirm_yes") as Button)
	eq(writes[0], 3, "『保存』确认后才多出第 3 次写入")
	var rewritten := _saves_snapshot(ProjectSettings.globalize_path(SAVES_DIR))
	eq(rewritten.size(), 1, "确认后仍然只有一个文件")
	ok(String((rewritten.get("slot_3.json", {}) as Dictionary).get("sha256", "")) != "",
			"当前槽位被重写成一个完整存档")
	contains(String(menu.call("hint_text")), "已覆盖槽位 3", "提示语仍是覆盖槽位 3")

	main.queue_free()
	ss.disconnect("save_written", on_write)
	await process_frame
	for n in _saves_end():
		print("    · ", n)
	ok(not DirAccess.dir_exists_absolute(SAVES_BAK), "saves.bak 已还原、无残留")
	_restore_defaults()


## 四张 B- 截图：空状态两轮 + 满状态两轮（各跑一个独立窗口进程）。
## 每轮先 `ui_expect` 自证到达声明的界面（子进程退出码 0 就是这条证据），
## 再由父进程做「两轮同图逐位一致」「四张两两不同」「每张非空图」三件事。
func _shoot_menu_rounds() -> void:
	var base := _opt_out.path_join("menu_shots")
	DirAccess.make_dir_recursive_absolute(base)
	var shots: Dictionary = {}
	var names: Array = []
	for label in ["a", "b"]:
		# 状态一：一个存档都没有
		_clear_saves_files()
		var empty_dir := base.path_join("empty_" + label)
		var empty_code := _shoot_menu_case("s0_3_menu_empty", empty_dir, 2)
		eq(empty_code, 0, "空状态批次 %s：退出码 0（含两次 ui_expect 自证）" % label)
		# 状态二：九格全满（fixture 的时间全部写死，否则像素会跟着墙上时钟变）
		_write_fixture_slots()
		var full_dir := base.path_join("full_" + label)
		var full_code := _shoot_menu_case("s0_3_menu_full", full_dir, 2)
		eq(full_code, 0, "满状态批次 %s：退出码 0（含两次 ui_expect 自证）" % label)
		for spec in [["01_menu_home", empty_dir], ["02_grid_empty", empty_dir],
				["03_grid_full", full_dir], ["04_overwrite_confirm", full_dir]]:
			var name := String(spec[0])
			var path := String(spec[1]).path_join(name + ".png")
			shots["%s/%s" % [name, label]] = {"path": path, "sha": FileAccess.get_sha256(path)}
			if label == "a":
				names.append(name)

	var idiff := load("res://tools/img_diff.gd")
	for name in names:
		var a: Dictionary = shots["%s/a" % name]
		var b: Dictionary = shots["%s/b" % name]
		var st := _png_stats(String(a["path"]))
		ok(bool(st["ok"]), "%s 能解码" % name, String(st["reason"]))
		eq(int(st["width"]), 1600, "%s 宽 1600" % name)
		eq(int(st["height"]), 900, "%s 高 900" % name)
		ge(float(st["mean"]), 0.02, "%s 不是空图（平均亮度 %.4f）" % [name, float(st["mean"])])
		eq(String(a["sha"]), String(b["sha"]), "%s 两轮 sha256 逐位一致" % name)
		var r: Dictionary = idiff.diff(String(a["path"]), String(b["path"]), 0)
		eq(int(r.get("changed_pixels", -1)), 0, "%s 两轮差异像素 0（严格 channel=0）" % name)
		print("    · B- %s sha256=%s" % [name, String(a["sha"])])
	for i in names.size():
		for j in range(i + 1, names.size()):
			var ra: Dictionary = shots["%s/a" % names[i]]
			var rb: Dictionary = shots["%s/a" % names[j]]
			var d: Dictionary = idiff.diff(String(ra["path"]), String(rb["path"]))
			ok(float(d.get("ratio_pct", 0.0)) > 0.0, "%s 与 %s 不是同一张图（%.2f%% 不同）"
					% [names[i], names[j], float(d.get("ratio_pct", 0.0))])


## 跑一个菜单截图批次：窗口模式（截图必须有真 GPU），并核对清单与自证行。
func _shoot_menu_case(case_name: String, out_dir: String, expect_shots: int) -> int:
	var out: Array = []
	var code := _exec_user(PackedStringArray(), PackedStringArray([
		"--scene=" + DIORAMA_SCENE,
		"--shots", "--case=" + case_name, "--warmup=60", "--frames=15",
		"--out=" + out_dir,
	]), out)
	var flat := _flatten_lines(out)
	var expect_ok := 0
	for line in flat:
		if String(line).contains("ui_expect ok"):
			expect_ok += 1
	eq(expect_ok, expect_shots, "%s：%d 次 ui_expect 全部 ok" % [case_name, expect_shots])
	if expect_ok != expect_shots:
		# 失败时把子进程输出打出来 —— 否则只知道"少了一次自证"，不知道少在哪一步。
		print("    · 子进程退出码 ", code, "，输出 ", flat.size(), " 行，末尾 20 行：")
		for i in range(maxi(0, flat.size() - 20), flat.size()):
			print("      | ", String(flat[i]))
	var man := _read_json(out_dir.path_join(case_name + ".json"))
	if not ok(not man.is_empty(), "%s 写出了清单" % case_name):
		return code
	var shots: Array = man.get("shots", [])
	eq(shots.size(), expect_shots, "%s 清单里有 %d 张图" % [case_name, expect_shots])
	var ck: Dictionary = man.get("clock", {})
	ok(bool(ck.get("deterministic", false)), "%s 清单声明确定性时钟" % case_name)
	return code


## --- 打桩用例（hidden）-------------------------------------------------------
## 这三个用例不写报告、不走断言汇总：输出与退出码就是父用例的证据通道。
## `--all` 永远不会直接跑到它们（hidden），只由上面的用例以子进程拉起。

## 子进程：新游戏 → 设定可辨识状态 → 存槽 3。
func _case_probe_write() -> void:
	var gs := get_root().get_node_or_null("GameState")
	var ss := get_root().get_node_or_null("SaveSystem")
	if gs == null or ss == null:
		printerr("[probe] WRITE ok=false 原因=autoload 缺失")
		_probe_exit = 1
		return
	gs.call("new_game", PROBE_SEED)
	gs.set("game_time", PROBE_TIME)
	gs.set("money", PROBE_MONEY)
	gs.set("food", PROBE_FOOD)
	gs.set("supply", PROBE_SUPPLY)
	gs.set("player_pos", PROBE_POS)
	gs.call("set_scene_kind", PROBE_SCENE_KIND)
	var r: Dictionary = ss.call("save_slot", ROUNDTRIP_SLOT, true)
	print("[probe] WRITE ok=%s path=%s reason=%s" % [
		str(r.get("ok")), str(r.get("path")), str(r.get("reason")),
	])
	_probe_exit = 0 if bool(r.get("ok")) else 1


## 子进程：读槽 3 → 回吐单行快照 JSON（父进程直接解析）。
func _case_probe_read() -> void:
	var ss := get_root().get_node_or_null("SaveSystem")
	var gs := get_root().get_node_or_null("GameState")
	if ss == null or gs == null:
		printerr("[probe] READ ok=false 原因=autoload 缺失")
		_probe_exit = 1
		return
	var r: Dictionary = ss.call("load_slot", ROUNDTRIP_SLOT)
	var warns: PackedStringArray = r.get("warnings", PackedStringArray())
	print("[probe] READ ok=%s warnings=%d reason=%s" % [
		str(r.get("ok")), warns.size(), str(r.get("reason")),
	])
	if not bool(r.get("ok")):
		_probe_exit = 1
		return
	var handoff := _opt_out.path_join(PROBE_SNAPSHOT_FILE)
	_write_json(handoff, gs.call("snapshot"))
	print("[probe] SNAPSHOT_FILE ", handoff)
	_probe_exit = 0


## 子进程：连续写同一槽位 ATOMIC_WRITES 次，父进程同时在轮询那个文件。
## 结束时把「按自己写的最后一次，槽位里应当是什么」落成文件——父进程只能靠它
## 判断「读者看到的最终版本是不是写者发布的最后一版」。
func _case_probe_loop() -> void:
	var ss := get_root().get_node_or_null("SaveSystem")
	var gs := get_root().get_node_or_null("GameState")
	if ss == null or gs == null:
		printerr("[probe] LOOP writes=0 fails=1 原因=autoload 缺失")
		_probe_exit = 1
		return
	var fails := 0
	var first_reason := ""
	for i in ATOMIC_WRITES:
		gs.set("money", i + 1)
		var r: Dictionary = ss.call("save_slot", ATOMIC_SLOT, true)
		if not bool(r.get("ok")):
			fails += 1
			if first_reason == "":
				first_reason = String(r.get("reason"))
	var slot_path: String = ss.call("slot_path", ATOMIC_SLOT)
	var last_published := FileAccess.get_file_as_string(slot_path)
	var last_d: Dictionary = _parse_json_silent(last_published)
	var last_game: Dictionary = last_d.get("game", {})
	_write_json(_opt_out.path_join(PROBE_LOOP_FILE), {
		"writes": ATOMIC_WRITES,
		"fails": fails,
		"first_reason": first_reason,
		"last_published_sha": FileAccess.get_sha256(slot_path),
		"last_published_bytes": last_published.length(),
		"last_published_money": int(last_game.get("money", -1)),
	})
	print("[probe] LOOP writes=%d fails=%d first_reason=%s" % [
		ATOMIC_WRITES, fails, first_reason,
	])
	_probe_exit = 0 if fails == 0 else 1


## --- S0.3 批次 4 辅助（菜单 / 九宫格）-----------------------------------------

func _menu_node(menu: Node, key_or_path: String) -> Node:
	return menu.get_node_or_null(String(MENU_PATHS.get(key_or_path, key_or_path)))


func _menu_card_path(slot: int) -> String:
	return "Root/GridPage/Panel/Col/Grid/Col/Cards/Slot%d" % slot


func _menu_card_body_path(slot: int) -> String:
	return _menu_card_path(slot) + "/Box/Body"


## 注入一次真实按键（按下 + 抬起）。
##
## 走 `Input.parse_input_event`，和玩家的键盘走同一条管线：产品码里没有为测试
## 留的后门，所以"菜单能被 ESC 打开"这件事必须真的由菜单的输入处理完成。也正
## 因为如此，暂停期间还能点得动按钮才是**证据**（PROCESS_MODE_ALWAYS 生效），
## 而不是"测试直接调了函数"。
func _press_key(keycode: Key) -> void:
	for i in 2:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = (i == 0)
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await process_frame


func _press_escape() -> void:
	await _press_key(KEY_ESCAPE)


## 注入一次真实左键点击（移动 → 按下 → 抬起，落在控件中心）。
##
## ⚠️ **必须先发一个 `InputEventMouseMotion`**。只发 press/release 会间歇性丢点击
## （实测 `s0_3_slots` 在 HEAD 上 5 次跑有 2 次失败，失败点随机漂移）：Godot 的
## Viewport 在处理鼠标按键时用 `gui.mouse_focus` 决定投递给谁，而那个焦点是**由
## 鼠标移动事件更新**的；没有移动，按键就落在一个失效/为空的焦点上。真实用户点击
## 之前一定先移动鼠标，所以补上移动不是"绕过问题"，而是让注入序列符合真实输入。
##
## 控件矩形退化时直接不点：那说明布局还没跑出尺寸，点 (0,0) 只会得到"点过了"的假信号。
func _click_control(ctrl: Control) -> bool:
	if ctrl == null:
		return false
	var rect := ctrl.get_global_rect()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return false
	var pos := rect.get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await process_frame
	for i in 2:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = (i == 0)
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await process_frame
	return true


## 清空隔离目录里的文件，但保留目录本身（同一用例要在"空"与"满"之间来回切）。
func _clear_saves_files() -> void:
	var d := DirAccess.open(SAVES_DIR)
	if d == null:
		return
	var files := d.get_files()
	d.list_dir_end()
	for f in files:
		DirAccess.remove_absolute(SAVES_DIR.path_join(String(f)))


## 九个固定存档样本。`saved_at` / `game_time` / `playtime` 全部**写死**：如果让
## `SaveSystem` 自己写，卡片上的时间会取墙上时钟，同一份代码两次运行会拍出不同的
## PNG，B- 门禁就永远是红的。也就是说这里的"假"是为了让截图这个"真"成立。
func _write_fixture_slots() -> void:
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	for slot in range(1, 10):
		_write_text(_slot_file(slot), _fixture_slot_text(slot))


func _fixture_slot_text(slot: int) -> String:
	var hour := (6 + slot) % 24
	var minute := slot * 5
	var playtime := float(slot * 137)
	var game_time := float(slot - 1) * 170.0 + (float(hour) * 60.0 + float(minute)) / 1440.0 * 170.0
	return JSON.stringify({
		"schema_version": 1,
		"saved_at": "2025-10-16 %02d:%02d:00" % [hour, minute],
		"saved_at_unix": 1760571600 + slot * 60,
		"meta": {
			"slot": slot,
			"game_day": slot,
			"clock_text": "第 %d 天 %02d:%02d" % [slot, hour, minute],
			"party_name": "无名军团",
			"party_level": slot,
			"playtime": playtime,
			"playtime_text": "%02d:%02d:%02d" % [
				int(playtime) / 3600, (int(playtime) / 60) % 60, int(playtime) % 60,
			],
			"world_seed": PROBE_SEED,
		},
		"game": {
			"world_seed": PROBE_SEED,
			"game_time": game_time,
			"day_length": 170.0,
			"party": {"name": "无名军团", "level": slot},
			"money": slot * 11,
			"food": slot * 3,
			"supply": slot,
			"scene_kind": 0,
			"player_pos": {"x": 0.0, "y": 0.0, "z": 0.0},
			"playtime": playtime,
		},
	}, "  ", false)


## 一张 PNG 的尺寸与平均亮度。
##
## 用途只有一条——**否掉空图**：截图黑屏或纯色时，路径、清单、sha256 一切照旧
## "正常"，只有看一眼像素才能发现。`res://.shots/*.png` 不在引擎导入库里，必须
## 用 `FileAccess` 读原始字节再解码（与 `tools/img_diff.gd` 同一套做法）。
func _png_stats(path: String) -> Dictionary:
	var out := {"ok": false, "width": 0, "height": 0, "mean": 0.0, "reason": ""}
	if not FileAccess.file_exists(path):
		out["reason"] = "文件不存在"
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out["reason"] = "打不开（%s）" % error_string(FileAccess.get_open_error())
		return out
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		out["reason"] = "PNG 解码失败"
		return out
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 7):
		for x in range(0, img.get_width(), 7):
			total += img.get_pixel(x, y).get_luminance()
			n += 1
	out["ok"] = true
	out["width"] = img.get_width()
	out["height"] = img.get_height()
	out["mean"] = total / maxf(float(n), 1.0)
	return out


## --- S0.3 批次 2 辅助 ---------------------------------------------------------

func _slot_file(slot: int) -> String:
	return SAVES_DIR.path_join("slot_%d.json" % slot)


## 把 user://saves 整体让位给 user://saves.bak。
## 目录换名已由探针实测：目标不存在时可用；target 已存在且非空时失败（因此先清）。
func _saves_begin() -> PackedStringArray:
	var notes := PackedStringArray()
	if DirAccess.dir_exists_absolute(SAVES_BAK):
		if DirAccess.dir_exists_absolute(SAVES_DIR):
			_dir_remove_recursive(SAVES_DIR)
		DirAccess.rename_absolute(SAVES_BAK, SAVES_DIR)
		notes.append("发现上次遗留的 saves.bak，已先还原")
	if DirAccess.dir_exists_absolute(SAVES_DIR):
		var err := DirAccess.rename_absolute(SAVES_DIR, SAVES_BAK)
		notes.append("已把 saves/ 让位为 saves.bak（err=%d）" % err)
	else:
		notes.append("原本没有 saves/ 目录，无需让位")
	return notes


## 删掉用例期间造出来的 saves/，再把备份换回来。
func _saves_end() -> PackedStringArray:
	var notes := PackedStringArray()
	if DirAccess.dir_exists_absolute(SAVES_DIR):
		_dir_remove_recursive(SAVES_DIR)
	if DirAccess.dir_exists_absolute(SAVES_BAK):
		var err := DirAccess.rename_absolute(SAVES_BAK, SAVES_DIR)
		notes.append("已还原 saves.bak -> saves/（err=%d）" % err)
	else:
		notes.append("没有 saves.bak 需要还原")
	return notes


## 递归删除目录。先把 DirAccess 的目录句柄收起来再删——Windows 上打开着的
## 目录句柄会挡住删除（与预登记陷阱 2 同源的引擎/系统语义）。
func _dir_remove_recursive(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dirs: Array = []
	var files: Array = []
	var d := DirAccess.open(dir_path)
	if d != null:
		dirs = d.get_directories()
		files = d.get_files()
		d.list_dir_end()
	for sub in dirs:
		_dir_remove_recursive(dir_path.path_join(String(sub)))
	for f in files:
		DirAccess.remove_absolute(dir_path.path_join(String(f)))
	DirAccess.remove_absolute(dir_path)


## 目录内每个文件的 sha256 + mtime —— 验收原文要的正是这两项。
func _saves_snapshot(dir_path: String) -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	var files := d.get_files()
	d.list_dir_end()
	for f in files:
		var p := dir_path.path_join(String(f))
		out[String(f)] = {
			"sha256": FileAccess.get_sha256(p),
			"mtime": FileAccess.get_modified_time(p),
		}
	return out


## 一次观测是否算「完整」：JSON 对象 + schema_version 1 + 必备 game.money。
## 「不存在」与「存在但读不出」是另外两类观测，由调用方单独计数，不算半截。
func _slot_text_is_complete(txt: String) -> bool:
	var d := _parse_json_silent(txt)
	if d.is_empty():
		return false
	if int(d.get("schema_version", -1)) != 1:
		return false
	var game_v: Variant = d.get("game", null)
	if typeof(game_v) != TYPE_DICTIONARY:
		return false
	return (game_v as Dictionary).has("money")


## 解析可能损坏的文本，失败时保持安静。
## 与 `scripts/core/save_system.gd` 同一条理由：并发观测里的「半截样本」是**预期输入**，
## `JSON.parse_string()` 会为每一个样本打一行引擎级 ERROR，把真正的错误淹掉。
func _parse_json_silent(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var data: Variant = parser.data
	return data if typeof(data) == TYPE_DICTIONARY else {}


## 跑一轮「该写盘的东西都没写盘」的模拟：新游戏 → 逻辑步推进 → 五种全局事实
## 全部投递 → 把所有只读的存档接口调一遍。
##
## ⚠️ 真正的「大地图遭遇 → 战斗 → 返回」需要 SceneRouter（S0.3 批次 3）才能跑通；
## 本用例覆盖它现在能覆盖的部分：任何非玩家显式操作的流程都不许落盘。
func _idle_run(frames: int) -> void:
	var gs := get_root().get_node_or_null("GameState")
	var bus := get_root().get_node_or_null("EventBus")
	var ss := get_root().get_node_or_null("SaveSystem")
	if gs != null:
		gs.call("new_game", 31337)
	for i in 6:
		await physics_frame
	if bus != null:
		bus.emit_signal("time_advanced", 2, 0.5)
		bus.emit_signal("encounter_started", {"id": "probe"})
		bus.emit_signal("battle_finished", {"win": true})
		bus.emit_signal("resources_changed", 1, 2, 3)
		bus.emit_signal("settlement_entered", "s1")
	if ss != null:
		ss.call("select_slot", 1)
		ss.call("slot_info", 1)
		ss.call("list_slots")
		ss.call("load_slot", 1)
		ss.call("load_slot", 9)
	for i in maxi(frames - 6, 0):
		await physics_frame


## 把现场还给后续用例（GameState / Rng 回默认，与 s0_3_state 的收尾同口径）。
## 把用例改过的全局事实复原到出厂态。用例之间共享**同一个进程**（`--all` 在一个
## 进程里顺序跑完所有用例），所以"上一个用例停在哪个槽位"属于必须显式复原的状态：
## 不还原的话，下一个用例会以为自己是从全新存档开始的（踩过一次：`s0_3_roundtrip`
## 走后 `SaveSystem.current_slot` 停在 3，`s0_3_slots` 的"无当前槽位"分支整段失效）。
func _restore_defaults() -> void:
	var gs := get_root().get_node_or_null("GameState")
	var rng := get_root().get_node_or_null("Rng")
	var ss := get_root().get_node_or_null("SaveSystem")
	if gs != null:
		gs.call("new_game", 20250929)
	if rng != null:
		rng.call("seed_from", 20250929)
	if ss != null:
		# `select_slot()` 只接受 1..9（没有公开的"清空"入口，这正是它的语义），
		# 所以"回到没有选中槽位"只能写回默认值。
		ss.set("current_slot", 0)
		ss.set("last_error", "")
	# S0.4 批次 2：调试层也是"用例会改、下一个用例必须假设它是默认值"的全局事实
	# （`s0_4_overlay` 会故意把调试热键的闸门关掉来验证发布门禁）。
	var dbg := get_root().get_node_or_null("Debug")
	if dbg != null:
		dbg.call("set_overlay", false)
		dbg.call("set_ui_hidden", false)
	InputSetup.ensure_debug_hotkeys(OS.is_debug_build())


## 以子进程跑一个打桩用例并把 stdout 收回来。
## `--quit-after` 是兜底：万一打桩用例挂死，子进程也会退出，表现为「标记行缺失」的
## 显式失败，而不是无限等待（与 `_exec_user` 同一条约束）。
## 以子进程跑一个打桩用例并把 stdout 收回来。
## `--out=` 必须放在 `--` **之后**：`--` 之前的参数引擎自己解析，子进程的
## `OS.get_cmdline_user_args()` 只看得见 `--` 之后的（踩过一次：放前面时子进程
## 静默用了默认报告目录，回吐文件写去了别处）。`--quit-after` 同理是兜底：万一
## 打桩用例挂死，子进程也会退出，表现为「标记行缺失」的显式失败，而不是无限等待。
func _exec_case(case_id: String, out_lines: Array) -> int:
	return _exec_godot(PackedStringArray([
		"--headless", "--quit-after", "20000",
		"--script", "res://tools/verify.gd", "--", "--case=" + case_id, "--out=" + _opt_out,
	]), out_lines)


## 非阻塞启动一个打桩用例子进程（stdout 继承本进程），返回 pid。
## 必须非阻塞：父进程要在子进程写盘的同时轮询那个槽位文件。
func _spawn_case(case_id: String) -> int:
	return OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", _project_dir(), "--quit-after", "20000",
		"--script", "res://tools/verify.gd", "--", "--case=" + case_id, "--out=" + _opt_out,
	]))


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[verify] 无法写入 ", path)
		return
	f.store_string(text)
	f.close()


## 把 `OS.execute` 收回的输出摊平成单行。
## `out_lines` 的元素是**读取分块**而不是严格按行（实测一整段 stderr+stdout 会落在
## 同一个元素里），所以这里统一按 "\n" 再切一次：机器可读标记行必须能逐行匹配，
## 否则断言会随缓冲边界随机失败。
func _flatten_lines(lines: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for l in lines:
		for piece in String(l).split("\n"):
			out.append(String(piece))
	return out


func _lines_contain(lines: Array, needle: String) -> bool:
	for l in _flatten_lines(lines):
		if String(l).contains(needle):
			return true
	return false


## 取以 `prefix` 开头那一行的剩余部分（打桩用例的单行机器可读输出）。
func _line_value(lines: Array, prefix: String) -> String:
	for l in _flatten_lines(lines):
		var s := String(l)
		if s.begins_with(prefix):
			return s.substr(prefix.length())
	return ""


func _tail(lines: Array, n: int) -> String:
	var flat := _flatten_lines(lines)
	var start := maxi(flat.size() - n, 0)
	var out := PackedStringArray()
	for i in range(start, flat.size()):
		out.append(String(flat[i]))
	return " | ".join(out)


func _error_lines(lines: Array) -> Array:
	var out: Array = []
	for l in _flatten_lines(lines):
		var s := String(l)
		if s.contains("ERROR") or s.contains("SCRIPT ERROR"):
			out.append(s.strip_edges())
	return out


## --- 诊断用例 ----------------------------------------------------------------
func _case_probe_pass() -> void:
	await process_frame
	section("probe")
	ok(true, "诊断：恒真断言 1")
	ok(1 + 1 == 2, "诊断：恒真断言 2")


func _case_probe_fail() -> void:
	await process_frame
	section("probe")
	ok(true, "诊断：先来一条真断言")
	ok(false, "诊断：这条是故意失败，用于验证退出码 1", "intentional failure")


## =============================================================================
##  S0.5 文档契约（A- / B-）
## =============================================================================
## 这个用例要证明的是"文档里写的每条约定都能在代码里定位"，而不是"文档里出现了某几个字"。
## 所以每条断言都是 **(文档必须有的锚点, 代码里必须找得到的符号)** 成对出现：
## 文档删了锚点 → 红；代码改了名 → 红。
##
## 反面同样重要：一个只会 `contains()` 的用例，把锚点换成任何一段文字都照样绿。
## 因此 §4 用**编造的锚点**做反向对照 —— 证明这套断言真的会因为"文档里没有"而失败。
func _case_doc_conventions() -> void:
	await process_frame

	var eng := _read_text_file("res://docs/ENGINEERING.md")
	var art := _read_text_file("res://docs/ART_PIPELINE.md")
	var road := _read_text_file("res://docs/ROADMAP.md")

	section("两份文档存在且非空")
	ok(eng.length() > 3000, "docs/ENGINEERING.md 可读且非空（%d 字符）" % eng.length())
	ok(art.length() > 3000, "docs/ART_PIPELINE.md 可读且非空（%d 字符）" % art.length())
	ok(road.length() > 10000, "docs/ROADMAP.md 可读且非空（%d 字符）" % road.length())

	section("§7 命名：文档里的 20 个 class_name 逐个在代码里存在")
	# (文档里必须出现的类名, 代码文件, 文件里必须有的声明)
	var classes := {
		"Player": "res://scripts/actors/player.gd",
		"CameraRig": "res://scripts/core/camera_rig.gd",
		"InputSetup": "res://scripts/core/input_setup.gd",
		"MeshUtil": "res://scripts/core/mesh_util.gd",
		"Canon": "res://scripts/core/canon.gd",
		"UiKit": "res://scripts/ui/ui_kit.gd",
		"UiPanel": "res://scripts/ui/ui_panel.gd",
		"BrutalSlider": "res://scripts/ui/ui_slider.gd",
		"CloudField": "res://scripts/world/clouds.gd",
		"DayNight": "res://scripts/world/day_night.gd",
		"Scatter": "res://scripts/world/scatter.gd",
		"Terrain": "res://scripts/world/terrain.gd",
		"WaterSurface": "res://scripts/world/water.gd",
		"HeightField": "res://scripts/world/height_field.gd",
		"WorldRegions": "res://scripts/world/regions.gd",
		"WorldData": "res://scripts/world/world_data.gd",
		"GenParams": "res://scripts/world/gen_params.gd",
		"WorldSession": "res://scripts/world/world_session.gd",
		"StrategicTerrain": "res://scripts/world/strategic_terrain.gd",
		"StrategicCamera": "res://scripts/world/strategic_camera.gd",
	}
	for cls in classes.keys():
		var path := String(classes[cls])
		var src := _read_text_file(path)
		contains(eng, "`%s`" % cls, "ENGINEERING.md §7 登记了 class_name `%s`" % cls)
		contains(src, "class_name %s" % cls,
				"%s 里确实声明了 `class_name %s`" % [path.get_file(), cls])

	section("§8 信号：文档登记的四类口径在代码里各有实例")
	var sig_src := _read_text_file("res://scripts/ui/ui_panel.gd")
	contains(sig_src, "signal regenerate_pressed", "`*_pressed` 实例：ui_panel.gd 的 regenerate_pressed")
	contains(eng, "`*_pressed`", "ENGINEERING.md §8 写的是 `*_pressed`（不是过期的 `on_xxx`）")
	not_contains(eng, "`on_xxx`（按钮）",
			"ENGINEERING.md §8 不再声称按钮信号叫 `on_xxx`（S0.5 已按实际代码更正）")
	var bus_src := _read_text_file("res://scripts/core/event_bus.gd")
	contains(bus_src, "signal time_advanced", "过去式事实信号实例：event_bus.gd 的 time_advanced")
	var style_src := _read_text_file("res://scripts/core/style.gd")
	contains(style_src, "signal style_changed", "`*_changed` 实例：style.gd 的 style_changed")

	section("§9 Canon：文档声明『已落地』、代码里三个入口都在，且旧的『未实现』标记已清空")
	contains(eng, "`Canon` 已落地", "ENGINEERING.md §9 标注 Canon 已落地（S1.1a）")
	ok(FileAccess.file_exists("res://scripts/core/canon.gd"),
			"scripts/core/canon.gd 确实存在（文档没有虚报）")
	var canon_src := _read_text_file("res://scripts/core/canon.gd")
	contains(canon_src, "class_name Canon", "canon.gd 声明了 `class_name Canon`")
	for fn in ["to_text", "from_text", "write_file"]:
		contains(canon_src, "static func %s(" % fn, "canon.gd 提供入口 `%s()`（文档承诺的三个之一）" % fn)
	not_contains(eng, "`Canon` 未实现", "ENGINEERING.md §9 不再残留『未实现』标记")
	# 附录 A 里 canon.gd 的那一行：必须已标落地、且不再写『未实现』（只认这一行，
	# 不扫全篇 —— §16 的变更日志里可能引用旧标记作为历史记录）。
	var canon_row := ""
	for line in road.split("\n"):
		if line.contains("canon.gd") and line.contains("（新增"):
			canon_row = line
	contains(canon_row, "✅ 已落地", "ROADMAP 附录 A 的 canon.gd 行标为『已落地』")
	not_contains(canon_row, "未实现", "该行不再写『未实现』")
	contains(eng, "S1.1", "ENGINEERING.md §9 写明落地步骤是 S1.1")

	section("§10 autoload：文档写 9，project.godot 就是 9，且顺序约束与实现一致")
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		var nm := String(p["name"])
		if nm.begins_with("autoload/"):
			autoloads.append(nm.substr("autoload/".length()))
	eq(autoloads.size(), 9, "autoload 实际数量 = 9")
	contains(eng, "**当前 9 / 上限 10**", "ENGINEERING.md §10 写的是 9 / 10")
	contains(road, "**当前 9 / 10**", "ROADMAP §3.2 也写的是 9 / 10（原文『合计 8 / 当前 6』已更正）")
	not_contains(road, "合计 8；余量 2", "ROADMAP §3.2 不再残留过期的『合计 8；余量 2』")
	for i in autoloads.size():
		contains(eng, "`%s`" % String(autoloads[i]),
				"ENGINEERING.md §10 列出了实际存在的 autoload `%s`" % String(autoloads[i]))

	section("§11 禁止清单：文档列的 7 条规则名与守卫实现一致")
	# 规则名 → 一段**只含该类违例**的合成源码（与 _case_guard 同一手法）
	var rule_probes := {
		"box_mesh": "var m := BoxMesh.new()\n",
		"csg_box": "var n := CSGBox3D.new()\n",
		"standard_material": "var s := StandardMaterial3D.new()\n",
		"bare_randf": "var f := randf()\n",
		"bare_randi": "var i := randi()\n",
		"unfreezable_time": "var t := Time.get_ticks_msec()\n",
		"scene_change_owner": "get_tree().change_scene_to_file(\"res://scenes/dev/diorama.tscn\")\n",
	}
	for rule in rule_probes.keys():
		contains(eng, "`%s`" % rule, "ENGINEERING.md §11 登记了守卫规则 `%s`" % rule)
		var probe: String = String(rule_probes[rule])
		var hits := _scan_text("res://scripts/_verify_tmp/doc_probe.gd", String(probe))
		var found := false
		for h in hits:
			if h["rule"] == rule:
				found = true
		ok(found, "守卫确实能报出 `%s`（文档没有登记一条不存在的规则）" % rule)

	section("§11.3『守卫管不到』的清单：必须点名未 facet 的 primitive")
	contains(eng, "未 `facet()` 的引擎 primitive", "ENGINEERING.md §11.3 点名了未 facet 的 primitive")
	contains(art, "守卫抓不到", "ART_PIPELINE.md §2.2 ⑥ 明说这一类守卫抓不到")

	section("ART_PIPELINE：6 步模板与 3 个反例都在")
	for step in ["步骤 1", "步骤 2", "步骤 3", "步骤 4", "步骤 5", "步骤 6"]:
		contains(art, step, "ART_PIPELINE.md §3 有「%s」" % step)
	contains(art, "04_bad_box", "反例 ①：04_bad_box")
	contains(art, "05_bad_pbr_tree", "反例 ②：05_bad_pbr_tree")
	contains(art, "06_bad_smooth_ball", "反例 ③：06_bad_smooth_ball")
	contains(art, "01_ok_tree", "样板 ①：01_ok_tree")
	contains(art, "02_ok_rock", "样板 ②：02_ok_rock")
	contains(art, "03_ok_ball", "样板 ③：03_ok_ball")
	contains(art, "AGENTS.md", "ART_PIPELINE.md 交叉引用 AGENTS.md（冲突以它为准）")

	section("教材夹具：双向约束 —— 产品码不引用 scripts/dev/，dev/ 的命中恰等于白名单登记")
	# ① 反向 A：`res://scripts/dev/` 零容忍。
	#    这里放的是**故意违例的教材脚本**，产品码引用它就是把反例带进正式构建。
	var script_leaks: Array = []
	_collect_dev_refs("res://scripts", script_leaks, "res://scripts/dev/")
	_collect_dev_refs("res://scenes", script_leaks, "res://scripts/dev/")
	_collect_dev_refs("res://shaders", script_leaks, "res://scripts/dev/")
	eq(script_leaks.size(), 0, "产品码没有一处引用 scripts/dev/（教材脚本不得进正式构建）")
	if script_leaks.size() > 0:
		print("    · 泄漏点：", script_leaks)

	# ① 反向 B：`res://scenes/dev/` 走**登记清单**，不搞零容忍。
	#    S1.0a 把演示岛搬成 `res://scenes/dev/diorama.tscn` 后，`scene_router.gd` 曾必须
	#    引用它 —— 那时"零容忍"就不再是正确的约束，于是改成"逐条登记、多一个少一个都红"。
	#    S1.0d 战略图接管 `world` 后那条登记到期，清单**已收紧回 0 条**：夹具场景只允许
	#    被 `tools/`（回归用例与取景脚本）和 `--scene=` 引用，正式构建里一个都不许出现。
	var scene_refs: Array = []
	for dir_path in ["res://scenes", "res://scripts", "res://shaders"]:
		_collect_dev_refs(dir_path, scene_refs, "res://scenes/dev/")
	scene_refs.sort()
	var scene_refs_want: Array = []
	eq(scene_refs, scene_refs_want,
			"引用 scenes/dev/ 的产品码为 0 处（S1.0d 起战略图接管 world，diorama 只是夹具，"
			+ "只能由 tools/ 与 --scene= 引用）")
	for p in scene_refs_want:
		ok(FileAccess.file_exists(p), "登记为可引用 scenes/dev/ 的文件真的存在", p)
	# 反向对照：登记清单不是"随便写个路径就能过" —— 未登记的引用必须被抓住。
	# 用临时文件造一个假泄漏点，确认收集器真的会把它找出来（而不是恒返回空）。
	var tmp_leak := "res://scripts/_verify_tmp/leak_probe.gd"
	DirAccess.make_dir_recursive_absolute("res://scripts/_verify_tmp")
	var lf := FileAccess.open(tmp_leak, FileAccess.WRITE)
	if lf != null:
		lf.store_string("const P := \"res://scenes/dev/diorama.tscn\"\n")
		lf.close()
		var probe_leaks: Array = []
		_collect_dev_refs("res://scripts", probe_leaks, "res://scenes/dev/")
		ok(probe_leaks.has(tmp_leak),
				"未登记引用 scenes/dev/ 的文件会被收集器抓出（清单不是恒真）")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_leak))

	# ② 正向：夹具真的命中被禁写法，且命中数恰等于白名单里登记给它的条数
	var fixture_src := _read_text_file("res://scripts/dev/art_samples.gd")
	var fixture_hits := _scan_text("res://scripts/dev/art_samples.gd", fixture_src)
	var rules_hit: Array = []
	for h in fixture_hits:
		rules_hit.append(String(h["rule"]))
	rules_hit.sort()
	eq(rules_hit, ["box_mesh", "standard_material", "standard_material"],
			"夹具命中的规则恰好是登记的那 3 条（1 条 box_mesh + 2 条 standard_material）")
	var wl_reasons := 0
	for entry in GUARD_WHITELIST:
		if String(entry.get("path", "")) == "res://scripts/dev/art_samples.gd":
			wl_reasons += 1
	eq(wl_reasons, 2, "白名单里为夹具登记的条目数 = 2（box_mesh / standard_material 各一条）")
	ok(_read_text_file("res://scenes/dev/art_samples.tscn").contains("art_samples.gd"),
			"夹具场景挂的就是夹具脚本（不是别处的产品脚本）")
	contains(fixture_src, "产品码一律不得引用", "夹具脚本文件头写明了那条硬约束")

	section("B- 6 张教材截图：存在、非空、sha256 与批次清单一致")
	var manifest := _read_text_file("res://.shots/s05/s0_5_samples.json")
	if manifest == "":
		ok(true, "（无 .shots/s05 清单：本机未跑过该批次，跳过逐位比对）")
		ok(true, "（同上，跳过）")
		ok(true, "（同上，跳过）")
	else:
		var md: Dictionary = _parse_json_silent(manifest)
		var shots: Array = md.get("shots", [])
		eq(shots.size(), 6, "批次清单里是 6 张")
		var mismatch: Array = []
		var missing: Array = []
		for s in shots:
			var nm := String(s.get("name", ""))
			var want := String(s.get("sha256", ""))
			var p := "res://docs/art/s0_5/%s.png" % nm
			if not FileAccess.file_exists(p):
				missing.append(nm)
				continue
			if FileAccess.get_sha256(p) != want:
				mismatch.append(nm)
		ok(missing.is_empty(), "docs/art/s0_5/ 里 6 张 PNG 齐全", "缺：%s" % [missing])
		ok(mismatch.is_empty(),
				"6 张 PNG 的 sha256 与 s0_5_samples 批次清单逐位一致"
						+ "（文档内嵌的就是工具产出的那 6 张）",
				"不一致：%s" % [mismatch])

	section("反向对照：编造的锚点在文档里找不到（证明上面的断言不是假绿）")
	# 这三条**必须失败**的查找，用来证明 contains() 真的在做事。
	not_contains(eng, "`Canon` 支持 `Vector3` 直写", "编造锚点 ①：文档里没有『Canon 支持 Vector3 直写』")
	not_contains(eng, "`on_xxx`（按钮）", "编造锚点 ②：文档里没有过期的 on_xxx 规则")
	not_contains(art, "07_ok_nothing", "编造锚点 ③：文档里没有不存在的第 7 张图")
	ok(eng.length() > 0 and not eng.contains("__s0_5_fabricated_anchor__"),
			"编造锚点 ④：任意伪造字符串在文档里都不存在（contains 不是恒真）")


## 递归收集「产品码引用教材目录」的泄漏点。
## 判据是**字面路径出现**，不做 AST —— 漏网的写法（如拼字符串）不在此用例能力范围内，
## 但常见的 preload/load/tscn ext_resource 都会被它逮住。
## `needle` 是要查的字面路径，调用方按目录分别查（`scripts/dev/` 与 `scenes/dev/`
## 的约束强度不同，见 `s0_5_doc_conventions`）。
## 教材目录自身（`res://scripts/dev/`、`res://scenes/dev/`）内部的互相引用不算泄漏：
## 夹具脚本的文档串会提到自己的路径，夹具场景必须引用夹具脚本 —— 那是它该做的事。
func _collect_dev_refs(dir_path: String, out: Array, needle: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var p := dir_path.path_join(fname)
		if dir.current_is_dir():
			_collect_dev_refs(p, out, needle)
		else:
			var ext := p.get_extension().to_lower()
			if ext in GUARD_EXTS and not _is_dev_area(p):
				var text := _read_text_file(p)
				if text.contains(needle):
					out.append(p)
		fname = dir.get_next()
	dir.list_dir_end()


## 该路径是否属于教材目录（含其内部的一切）。
func _is_dev_area(path: String) -> bool:
	return path.begins_with("res://scripts/dev/") or path.begins_with("res://scenes/dev/")


## 读文本文件；失败返回空串（断言会以"文档为空"报红，而不是抛异常）。
func _read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ""
	var text := fa.get_as_text()
	fa.close()
	return text


## =============================================================================
##  工具函数
## =============================================================================
func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

## 加载**回归夹具**（diorama）。S1.0d 之后产品主场景是战略图（S1.2b 起有地形）；内容用例（场景 API、
## 叠加层、快存、九宫格、覆盖确认）要的是一片有内容的世界，所以显式加载夹具，而不是
## 依赖 `run/main_scene`。夹具以**子节点**身份进树（不抢 `current_scene`），与 S1.0a
## 起的口径一致。
func _load_diorama() -> Node:
	var ps := load(DIORAMA_SCENE) as PackedScene
	if ps == null:
		return null
	var m := ps.instantiate()
	get_root().add_child(m)
	# 必须等一帧：组注册与 @onready 在进入活动场景树后才稳定
	await process_frame
	return m


## 判定目标上是否存在可调用的符号。
## Node 走 has_method；GDScript（全局 class_name 的静态函数）走脚本方法表。
func _has_callable(target: Variant, name: String) -> bool:
	if target == null:
		return false
	if target is Script:
		for m in (target as Script).get_script_method_list():
			if String(m.get("name", "")) == name:
				return true
		return false
	if target is Object:
		return (target as Object).has_method(name)
	return false


func _project_dir() -> String:
	var p := ProjectSettings.globalize_path("res://")
	while p.ends_with("/") or p.ends_with("\\"):
		p = p.substr(0, p.length() - 1)
	return p


## 以当前引擎可执行文件启动一个 Godot 子进程（stdout+stderr 合并进 out_lines）。
func _exec_godot(extra: PackedStringArray, out_lines: Array) -> int:
	var args := PackedStringArray(["--path", _project_dir()])
	args.append_array(extra)
	return OS.execute(OS.get_executable_path(), args, out_lines, true)


## 启动子进程并把**游戏侧**参数放在 `--` 之后。
##
## ⚠️ `--` 不是可选的分隔符。Godot 只把 `--` 之后的参数交给
## `OS.get_cmdline_user_args()`；少了它，`capture.gd` 收不到 `--shots`，
## 既不会触发截图也不会 `quit()`，子进程会一直跑着游戏——
## 实测后果是整个验收套件静默挂死（`OS.execute` 没有超时）。
## 因此本函数强制插入 `--`，并通过 `--quit-after` 兜底：
## 万一将来还有谁忘了回归，子进程最多跑 `safety_frames` 帧就退出，
## 表现为"清单没写出"的**显式失败**，而不是无限等待。
##
## engine_args 放 `--` 之前（`--headless` / `--script res://...` 之类）。
func _exec_user(engine_args: PackedStringArray, user_args: PackedStringArray,
		out_lines: Array, safety_frames: int = 3600) -> int:
	var args := PackedStringArray(["--quit-after", str(safety_frames)])
	args.append_array(engine_args)
	args.append("--")
	args.append_array(user_args)
	return _exec_godot(args, out_lines)


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[verify] 无法写报告：", path)
		return
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}


## 读文件为行数组（不存在的文件返回空数组）。CSV 断言用。
func _read_lines(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var txt := f.get_as_text()
	f.close()
	return txt.split("\n")


func _dir_has_json(dir_path: String) -> bool:
	var d := DirAccess.open(dir_path)
	if d == null:
		return false
	for f in d.get_files_at(dir_path):
		if String(f).to_lower().ends_with(".json"):
			return true
	return false


## 只取"世界事实"字段。`game_time` / `playtime` **不能**进这个集合：它们本来就在走，
## 拿它们当不变量样本会得到一条必然失败的断言（而那是用例的错，不是实现的错）。
func _world_facts(gs: Node) -> Dictionary:
	var snap: Dictionary = gs.call("snapshot")
	var out := {}
	for k in ["world_seed", "day_length", "party", "money", "food", "supply",
			"scene_kind", "player_pos"]:
		out[k] = snap.get(k)
	return out


## 每条已创建子流的内部状态。开关调试层若"顺手抽了个随机数"，这里必然变化。
## 只遍历 `stream_names()` 再取 `stream()`，不会因为取值而**新建**子流。
func _rng_states(rng: Node) -> String:
	var names: Array = []
	for n in (rng.call("stream_names") as PackedStringArray):
		names.append(String(n))
	names.sort()
	var parts := PackedStringArray()
	for n in names:
		var gen: RandomNumberGenerator = rng.call("stream", String(n))
		parts.append("%s=%d" % [String(n), gen.state])
	return " ".join(parts)


## 读调试面板上某个具名 Label 的正文（节点名在 `debug_layer.gd` 里固定）。
func _debug_label(dbg: Node, label_name: String) -> String:
	var l := dbg.get_node_or_null("DebugLayer/Root/Margin/Box/Panel/Col/" + label_name) as Label
	return "" if l == null else l.text


## 在目录树里找"代码行"（注释已剥离）中出现某 token 的位置。
## `_strip_comment()` 是守卫用的同一个纯函数：注释里提到某个 API 不算"使用它"。
func _code_token_hits(dir_path: String, token: String) -> Array:
	var hits: Array = []
	_code_token_walk(dir_path, token, hits)
	return hits


func _code_token_walk(dir_path: String, token: String, hits: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories_at(dir_path):
		_code_token_walk(dir_path.path_join(sub), token, hits)
	for fname in d.get_files_at(dir_path):
		if fname.get_extension().to_lower() != "gd":
			continue
		var p := dir_path.path_join(fname)
		var fa := FileAccess.open(p, FileAccess.READ)
		if fa == null:
			continue
		var lines := fa.get_as_text().split("\n")
		fa.close()
		for i in lines.size():
			var code := _strip_comment(String(lines[i]), "gd")
			if code.contains(token):
				hits.append({"path": p, "line": i + 1, "code": code.strip_edges()})


## 采样 `frames` 帧的**墙钟**耗时（毫秒）+ 平均 draw_calls / primitives。
## 中位数是主判据：偶发一次 OS 调度或 GC 会把均值抬高，而那不是被测对象的成本。
##
## 为什么**不**用 `Performance.TIME_PROCESS`（本文件第二次被它坑）：
## 实测（2026-10-19）它在 vsync 开启时量到的是"vsync 等待 + 抖动"（关层 18.75 /
## 开层 17.84 ms ⇒ 差值为**负**），关掉 vsync 后又量化成 78.58 / 6.204 两个离散值 ——
## 挂一个确定的 2ms/帧 负载上去，它给出 6.204，比空载还低。即这个监视器在本工程里
## 对 0.5ms 量级**没有分辨率**，拿它写 `C-` 断言，叠加层再贵也会绿。
## 改为直接量墙钟：`Time.get_ticks_usec()` 包住每一帧再除以帧数。`tools/**` 不在守卫
## `unfreezable_time` 的扫描范围内（它只管 `res://scenes|scripts|shaders`），这里的墙钟是
## **测量**、不是被渲染的时间源，不影响截图可复现性。vsync 必须先关掉，否则量到的
## 仍是 16.7ms 的封顶而不是真实成本。
func _sample_ms(frames: int) -> Dictionary:
	var vals: Array = []
	var draw_sum := 0.0
	var prim_sum := 0.0
	# 预热 2 帧：第一帧还带着上一段的状态切换开销，计进去会污染单帧样本。
	for i in 2:
		await process_frame
	for i in frames:
		var t0 := Time.get_ticks_usec()
		await process_frame
		vals.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		draw_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim_sum += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var sorted_vals := vals.duplicate()
	sorted_vals.sort()
	var n := sorted_vals.size()
	var denom := float(maxi(n, 1))
	var mean := 0.0
	for v in vals:
		mean += float(v)
	return {
		"median": float(sorted_vals[n / 2]) if n > 0 else 0.0,
		"mean": mean / denom,
		"max": float(sorted_vals[n - 1]) if n > 0 else 0.0,
		"draw_calls": draw_sum / denom,
		"prims": prim_sum / denom,
	}


## 统计 PNG 里"精确等于某颜色"的像素数。先降采样到 400×225（最近邻 = 只挑真实像素，
## 不插值），每个色块仍留有成百上千个样本；全图 1.44M 像素 × 3 张在 GDScript 里要好几秒，
## 而这里要回答的问题只是"这个颜色还在不在画面上"。文件不存在返回 -1（区别于 0）。
func _count_exact_color_px(png_path: String, col: Color) -> int:
	if not FileAccess.file_exists(png_path):
		return -1
	var img := Image.load_from_file(png_path)
	if img == null:
		return -1
	img.resize(400, 225, Image.INTERPOLATE_NEAREST)
	img.convert(Image.FORMAT_RGBA8)
	var want := col.to_rgba32()
	var n := 0
	for y in 225:
		for x in 400:
			if img.get_pixel(x, y).to_rgba32() == want:
				n += 1
	return n


## =============================================================================
##  规范守卫实现
## =============================================================================
func _guard_walk() -> Array:
	var hits: Array = []
	for root in GUARD_SCAN_DIRS:
		_walk(root, hits)
	return hits


func _walk(dir_path: String, hits: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories_at(dir_path):
		_walk(dir_path.path_join(sub), hits)
	for fname in d.get_files_at(dir_path):
		var ext := fname.get_extension().to_lower()
		if not GUARD_EXTS.has(ext):
			continue
		var p := dir_path.path_join(fname)
		var fa := FileAccess.open(p, FileAccess.READ)
		if fa == null:
			continue
		var text := fa.get_as_text()
		fa.close()
		hits.append_array(_scan_text(p, text))


## 纯函数：给定源文本返回违例列表。可被用例直接喂合成文本。
func _scan_text(path: String, text: String) -> Array:
	var hits: Array = []
	var ext := path.get_extension().to_lower()
	var lines := text.split("\n")
	for i in lines.size():
		var raw := String(lines[i])
		var line := _strip_comment(raw, ext)
		if line.strip_edges() == "":
			continue
		for rule in ["box_mesh", "csg_box", "standard_material"]:
			var needle: String = {
				"box_mesh": "BoxMesh",
				"csg_box": "CSGBox3D",
				"standard_material": "StandardMaterial3D",
			}[rule]
			if _contains_token(line, needle):
				hits.append(_hit(path, i + 1, rule, raw))
		for fn in BARE_RAND_FUNCS:
			if _has_bare_rand(line, fn):
				var rule := "bare_randf" if fn.begins_with("randf") else "bare_randi"
				hits.append(_hit(path, i + 1, rule, raw))
		# S0.6：不可冻结的时间来源（按扩展名分流）
		if ext == "gdshader" or ext == "shader":
			if _contains_token(line, UNFREEZABLE_SHADER_TOKEN):
				hits.append(_hit(path, i + 1, "unfreezable_time", raw))
		elif ext == "gd":
			for tok in UNFREEZABLE_SCRIPT_TOKENS:
				if _contains_token(line, tok):
					hits.append(_hit(path, i + 1, "unfreezable_time", raw))
		# S0.3 批次 3：只有 SceneRouter 可以切场景（按属主文件放行）
		if ext == "gd" and not SCENE_CHANGE_OWNERS.has(path):
			for tok in SCENE_CHANGE_TOKENS:
				if _contains_token(line, tok):
					hits.append(_hit(path, i + 1, "scene_change_owner", raw))
	return hits


func _hit(path: String, line: int, rule: String, snippet: String) -> Dictionary:
	return {"path": path, "line": line, "rule": rule, "snippet": snippet.strip_edges()}


func _whitelist_reason(hit: Dictionary) -> String:
	for w in GUARD_WHITELIST:
		if String(w["path"]) == String(hit["path"]) and String(w["rule"]) == String(hit["rule"]):
			return String(w["reason"])
	return ""


## 按 token 边界找标识符，避免 `MyBoxMeshThing` 之类误报。
func _contains_token(line: String, token: String) -> bool:
	var idx := line.find(token)
	while idx >= 0:
		var before_ok := idx == 0 or not _is_ident_char(line[idx - 1])
		var end := idx + token.length()
		var after_ok := end >= line.length() or not _is_ident_char(line[end])
		if before_ok and after_ok:
			return true
		idx = line.find(token, idx + 1)
	return false


func _is_ident_char(c: String) -> bool:
	return c == "_" or (c >= "0" and c <= "9") or (c >= "A" and c <= "Z") or (c >= "a" and c <= "z")


## 裸随机调用 = 函数名前面不是 `.`（成员调用）也不是标识符字符（自定义函数）。
func _has_bare_rand(line: String, fn: String) -> bool:
	var idx := line.find(fn)
	while idx >= 0:
		var prev_ok := idx == 0 or (line[idx - 1] != "." and not _is_ident_char(line[idx - 1]))
		var rest := line.substr(idx + fn.length())
		var stripped := rest.lstrip(" \t")
		if prev_ok and stripped.begins_with("("):
			return true
		idx = line.find(fn, idx + 1)
	return false


## 去掉行尾注释。.gd 用 `#`；.gdshader/.shader 用 `//`；.tscn/.tres 不去注释。
func _strip_comment(line: String, ext: String) -> String:
	if ext == "gd":
		return _strip_from(line, "#")
	if ext == "gdshader" or ext == "shader":
		return _strip_from(line, "//")
	return line


## 找到第一个位于字符串字面量之外的 mark，返回其之前的内容。
func _strip_from(line: String, mark: String) -> String:
	var in_s := false
	var in_d := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if c == "\\":
			i += 2
			continue
		if c == "'" and not in_d:
			in_s = not in_s
		elif c == "\"" and not in_s:
			in_d = not in_d
		elif not in_s and not in_d and line.substr(i).begins_with(mark):
			return line.substr(0, i)
		i += 1
	return line


## =============================================================================
##  S1.1a 数据层：Canon 规范化序列化 + gen_params.json 参数表
## =============================================================================
## 这两条用例守的是**字节级**契约，所以断言尽量做成"逐字节等于手写的期望文本"，
## 而不是"包含某个子串"——后者对缩进、顺序、末尾换行的变化是瞎的。

## 把 {schema:1, "v": value} 序列化后取整段文本，供数字格式断言复用。
func _canon_num(value: Variant) -> String:
	var r := Canon.to_text({"schema": 1, "v": value})
	return String(r["text"])


func _case_canon() -> void:
	await process_frame

	# --- 1. 键序与结构 --------------------------------------------------------
	section("键序：按 Unicode 码点升序，递归生效（插入顺序无关）")
	var sample := {"zeta": 1, "alpha": {"b": true, "a": null}, "mid": [3, 1, 2], "schema": 1}
	var built := Canon.to_text(sample)
	ok(bool(built["ok"]), "序列化成功", String(built.get("reason", "")))
	var text := String(built["text"])
	var want := "\n".join(PackedStringArray([
		"{",
		"  \"alpha\": {",
		"    \"a\": null,",
		"    \"b\": true",
		"  },",
		"  \"mid\": [",
		"    3,",
		"    1,",
		"    2",
		"  ],",
		"  \"schema\": 1,",
		"  \"zeta\": 1",
		"}",
		"",
	]))
	ok(text == want, "整棵树逐字节等于手写期望（键序 / 2 空格缩进 / 分隔符）",
			"实际：\n%s" % text)

	# 同一个字典换个插入顺序，输出必须一模一样——这才是"排序真的在做事"。
	var shuffled := {"schema": 1}
	shuffled["mid"] = [3, 1, 2]
	shuffled["zeta"] = 1
	shuffled["alpha"] = {"a": null, "b": true}
	eq(String(Canon.to_text(shuffled)["text"]), text, "乱序插入的同一个值序列化结果逐字节相同")

	contains(text, "[\n    3,\n    1,\n    2\n  ]", "数组保持给定顺序（3,1,2 没有被排序）")
	contains(String(Canon.to_text({"schema": 1, "e": {}, "l": []})["text"]),
			"\"e\": {},\n  \"l\": []", "空对象 / 空数组写成 {} 与 []")

	# --- 2. 数字 --------------------------------------------------------------
	section("数字：整数写整数、非整数 %.6f（含 JSON 解析导致整数无法区分的后果）")
	contains(_canon_num(2400.0), "\"v\": 2400\n", "整数值的 float 写成整数 2400（不是 2400.000000）")
	contains(_canon_num(12), "\"v\": 12\n", "int 12 写成 12")
	contains(_canon_num(2.5), "\"v\": 2.500000\n", "2.5 写成 2.500000（定点 6 位）")
	contains(_canon_num(1.0 / 3.0), "\"v\": 0.333333\n", "1/3 写成 0.333333")
	contains(_canon_num(-0.0), "\"v\": 0\n", "负零归一为 0")
	contains(_canon_num(1e-09), "\"v\": 0.000000\n", "1e-9 写成 0.000000")
	contains(_canon_num(-1e-09), "\"v\": 0.000000\n", "-1e-9 不产生 -0.000000（符号被归一）")
	contains(_canon_num(1e20), "\"v\": 100000000000000000000\n", "1e20 写成整数位串（不用科学计数法）")
	contains(String(Canon.to_text({"schema": 5.0})["text"]), "\"schema\": 5\n",
			"schema 写成 float 5.0 时仍按整数写（读回再写才可能幂等）")

	var nan_r := Canon.to_text({"schema": 1, "v": NAN})
	ok(not bool(nan_r["ok"]), "NaN 被拒绝（不写成 nan）")
	contains(String(nan_r["reason"]), "$.v", "NaN 的报错指出键路径 $.v")
	var inf_r := Canon.to_text({"schema": 1, "v": INF})
	ok(not bool(inf_r["ok"]), "Inf 被拒绝（不写成 inf）")

	# --- 3. 定界符与编码 ------------------------------------------------------
	section("定界与编码：LF、恰好一个结尾换行、无 CR、无 BOM")
	ok(text.ends_with("\n"), "以换行结尾")
	ok(not text.ends_with("\n\n"), "结尾恰好一个换行（不是两个）")
	ok(not text.contains("\r"), "不含 CR（纯 LF）")
	eq(text.unicode_at(0), 0x7B, "首字符是 {（没有 UTF-8 BOM）")

	# --- 4. 字符串转义 --------------------------------------------------------
	section("字符串：转义后能被 JSON 解析回原值，中文不转成 \\uXXXX")
	var tricky := "引号\" 反斜杠\\ 换行\n 制表\t 中文"
	var esc := Canon.to_text({"schema": 1, "s": tricky})
	var back := Canon.from_text(String(esc["text"]))
	ok(bool(back["ok"]), "含转义的输出仍是合法 JSON")
	var decoded: Dictionary = back["value"]
	eq(String(decoded["s"]), tricky, "字符串往返逐字符相同")
	contains(String(esc["text"]), "中文", "中文按 UTF-8 原样写出（不转 \\uXXXX）")

	# --- 5. fail-fast：不支持的值必须报错并指出路径 ---------------------------
	section("fail-fast：不支持的值 / 非字符串键 / 缺 schema / 自引用")
	var bad_color := Canon.to_text({"schema": 1, "a": {"b": [1, Color.RED]}})
	ok(not bool(bad_color["ok"]), "Color 被拒绝（不会退化成 str()）")
	contains(String(bad_color["reason"]), "$.a.b[1]", "报错精确到 $.a.b[1]")
	contains(String(bad_color["reason"]), "Color", "报错说明是哪种类型")

	var bad_vec := Canon.to_text({"schema": 1, "v": Vector3(1, 2, 3)})
	ok(not bool(bad_vec["ok"]), "Vector3 被拒绝")
	contains(String(bad_vec["reason"]), "$.v", "Vector3 的报错指出 $.v")

	var bad_key := Canon.to_text({1: "x", "schema": 1})
	ok(not bool(bad_key["ok"]), "非字符串键被拒绝")
	contains(String(bad_key["reason"]), "键必须是 String", "报错说明键类型问题")

	var no_schema := Canon.to_text({"a": 1})
	ok(not bool(no_schema["ok"]), "顶层缺少 schema 被拒绝")
	contains(String(no_schema["reason"]), "schema", "报错提到 schema")

	var bad_schema := Canon.to_text({"schema": 1.5})
	ok(not bool(bad_schema["ok"]), "非整数 schema 被拒绝")
	contains(String(bad_schema["reason"]), "必须是整数", "报错说明 schema 必须整数")

	var cyclic := {"schema": 1}
	cyclic["self"] = cyclic
	var cyc_r := Canon.to_text(cyclic)
	ok(not bool(cyc_r["ok"]), "自引用结构被深度上限拦住（不爆栈）")
	contains(String(cyc_r["reason"]), "嵌套超过", "报错说明触发了嵌套上限")

	# --- 6. 幂等 + 反向对照 ---------------------------------------------------
	section("幂等：读回再写仍逐字节相同；反向对照：手写非规范 JSON 不会等于 Canon 输出")
	var first := String(Canon.to_text(sample)["text"])
	var once := Canon.from_text(first)
	ok(bool(once["ok"]), "Canon 的输出能被自己解析（往返前提）")
	var second := String(Canon.to_text(once["value"])["text"])
	eq(second, first, "同一份文本读回再序列化逐字节相同（幂等）")
	var third := String(Canon.to_text(Canon.from_text(second)["value"])["text"])
	eq(third, second, "再来一轮仍相同（不是靠一次巧合）")

	var hand_written := "{\n  \"schema\": 1,\n  \"b\": 1,\n  \"a\": 2\n}\n"
	ne(String(Canon.to_text(Canon.from_text(hand_written)["value"])["text"]), hand_written,
			"手写未排序的 JSON 与 Canon 输出不相等（证明排序不是空转）")
	eq(String(Canon.to_text(Canon.from_text(hand_written)["value"])["text"]),
			"{\n  \"a\": 2,\n  \"b\": 1,\n  \"schema\": 1\n}\n",
			"规范化后的键序是 a, b, schema")

	# --- 7. write_file -------------------------------------------------------
	section("write_file：两次写同值字节与 sha256 相同、回读可解析、失败不落盘")
	var path := "res://.verify/s1_1_canon_probe.json"
	var bad_path := "res://.verify/s1_1_canon_bad.json"
	var w1 := Canon.write_file(path, sample)
	var w2 := Canon.write_file(path, sample)
	ok(bool(w1["ok"]), "第一次写成功", String(w1.get("reason", "")))
	ok(bool(w2["ok"]), "第二次写成功", String(w2.get("reason", "")))
	eq(String(w1["sha256"]), String(w2["sha256"]), "两次写入 sha256 逐位相同")
	eq(int(w1["bytes"]), int(w2["bytes"]), "两次写入字节数相同")
	eq(FileAccess.get_file_as_string(path), first, "落盘内容与 to_text 输出逐字节相同")
	eq(FileAccess.get_sha256(path), String(w1["sha256"]), "报告的 sha256 就是磁盘上那份文件的 sha256")
	ok(bool(Canon.from_text(FileAccess.get_file_as_string(path))["ok"]), "落盘文件可被 JSON 解析")

	var wbad := Canon.write_file(bad_path, {"schema": 1, "v": Color.RED})
	ok(not bool(wbad["ok"]), "含不支持的值时 write_file 失败")
	eq(int(wbad["bytes"]), 0, "失败时报告 0 字节")
	ok(not FileAccess.file_exists(bad_path), "失败时根本没有落盘（不留半截文件）")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ok(not FileAccess.file_exists(path), "清理探针文件")


func _case_gen_params() -> void:
	await process_frame

	var table_path := "res://data/world/gen_params.json"
	var table_text := _read_text_file(table_path)

	# --- 1. 表文件本身 --------------------------------------------------------
	section("表文件：存在、是合法 JSON、且本身就是 Canon 规范形式")
	ok(FileAccess.file_exists(table_path), "data/world/gen_params.json 存在")
	ok(table_text.length() > 0, "表文件非空")
	var canon := Canon.canonicalize(table_text)
	ok(bool(canon["ok"]), "表文件可被 Canon 解析", String(canon.get("reason", "")))
	ok(String(canon["text"]) == table_text,
			"表文件逐字节等于它自己的规范化结果（手改破坏格式会被逮住）",
			"规范化后：\n%s" % String(canon["text"]))

	var parsed: Dictionary = _parse_json_silent(table_text)
	eq(int(parsed.get("schema", -1)), GenParams.SCHEMA, "表里 schema = 当前版本")

	# --- 2. 默认值 = ROADMAP 初值，且在安全区间内 -----------------------------
	section("默认值：等于 ROADMAP §6 S1.1 的初值，且全部落在安全区间内")
	var expected := {
		"map_size": 2400,
		"regions_min": 6,
		"regions_max": 9,
		"villages": 12,
		"towns": 4,
		"fortresses": 4,
		"factions": 3,
		"ai_parties": 24,
	}
	for key in expected.keys():
		var field := String(key)
		var want := int(expected[key])
		eq(int(GenParams.DEFAULTS[field]), want, "内置默认 `%s` = %d" % [field, want])
		eq(int(parsed.get(field, -1)), want, "表文件里的 `%s` = %d（表与代码默认值不漂移）" % [field, want])
		var bounds: Array = GenParams.RANGES[field]
		ge(float(GenParams.DEFAULTS[field]), float(bounds[0]), "`%s` 不低于安全下限 %d" % [field, int(bounds[0])])
		le(float(GenParams.DEFAULTS[field]), float(bounds[1]), "`%s` 不高于安全上限 %d" % [field, int(bounds[1])])
	var base := GenParams.defaults()
	var base_total := int(base["villages"]) + int(base["towns"]) + int(base["fortresses"])
	ge(float(base_total), float(GenParams.SETTLEMENTS_RANGE[0]), "默认聚落总数 %d 不低于下限" % base_total)
	le(float(base_total), float(GenParams.SETTLEMENTS_RANGE[1]), "默认聚落总数 %d 不高于上限" % base_total)

	# --- 2b. 高度参数（米制浮点，S1.1b） --------------------------------------
	section("高度参数：默认值 = 文档初值、以米计、且全程不被取整")
	var expected_float := {
		"water_level": 0.0,
		"base_height": -18.0,
		"hill_amplitude": 120.0,
		"detail_amplitude": 8.0,
		"settlement_min_spacing": 120.0,
		"settlement_slope_limit": 0.35,
	}
	for key in expected_float.keys():
		var field := String(key)
		var want := float(expected_float[key])
		near(float(GenParams.DEFAULTS[field]), want, 0.000001, "内置默认 `%s` = %s" % [field, str(want)])
		near(float(parsed.get(field, 0.0)), want, 0.000001,
				"表文件里的 `%s` = %s（表与代码默认值不漂移）" % [field, str(want)])
		var bounds: Array = GenParams.RANGES[field]
		ge(float(GenParams.DEFAULTS[field]), float(bounds[0]), "`%s` 不低于安全下限 %s"
				% [field, str(float(bounds[0]))])
		le(float(GenParams.DEFAULTS[field]), float(bounds[1]), "`%s` 不高于安全上限 %s"
				% [field, str(float(bounds[1]))])
		ok(GenParams.FLOAT_FIELDS.has(field), "`%s` 登记为浮点字段（不会被四舍五入）" % field)
	var float_names := PackedStringArray(GenParams.FLOAT_FIELDS)
	eq(float_names.size(), 6, "浮点字段恰好 6 个（与 ENGINEERING §9.6 一致）")
	for field in float_names:
		ok(GenParams.DEFAULTS.has(field), "浮点字段 `%s` 在 DEFAULTS 里" % field)
		ok(GenParams.RANGES.has(field), "浮点字段 `%s` 在 RANGES 里" % field)

	# --- 3. 真表加载 ----------------------------------------------------------
	section("load_from：真表零告警、字段与默认值一致")
	var loaded := GenParams.load_from()
	ok(bool(loaded["ok"]), "真表可用", String(loaded.get("reason", "")))
	eq(bool(loaded["used_defaults"]), false, "没有回退内置默认值")
	var loaded_warns := PackedStringArray(loaded["warnings"])
	eq(loaded_warns.size(), 0, "真表不产生任何告警")
	var loaded_params := Dictionary(loaded["params"])
	for key in expected.keys():
		var field := String(key)
		eq(int(loaded_params[field]), int(expected[key]), "加载后 `%s` = %d" % [field, int(expected[key])])

	# --- 4. 越界只钳制 + 告警 -------------------------------------------------
	section("越界：clamp 到安全区间并逐条告警（不崩、不静默）")
	var clamp_cases := [
		{"field": "map_size", "value": 100, "want": 600},
		{"field": "map_size", "value": 99999, "want": 4000},
		{"field": "factions", "value": 1, "want": 2},
		{"field": "factions", "value": 9, "want": 5},
		{"field": "ai_parties", "value": 100, "want": 40},
	]
	for c in clamp_cases:
		var field := String(c["field"])
		var out := GenParams.validate(_with(c["field"], c["value"]))
		var params := Dictionary(out["params"])
		var warns := PackedStringArray(out["warnings"])
		eq(int(params[field]), int(c["want"]),
				"`%s` = %d 钳制为 %d" % [field, int(c["value"]), int(c["want"])])
		eq(warns.size(), 1, "`%s` = %d 恰好产生 1 条告警（没有额外噪声）" % [field, int(c["value"])])
		contains(String(warns[0]), field, "告警点名了字段 `%s`" % field)
		eq(bool(out["used_defaults"]), false, "钳制不算整体回退")

	# 浮点字段走同一条越界闸门，但钳到浮点边界而不是取整
	var float_clamps := [
		{"field": "hill_amplitude", "value": 5.0, "want": 40.0},
		{"field": "hill_amplitude", "value": 9999.0, "want": 300.0},
		{"field": "water_level", "value": -999.0, "want": -60.0},
		{"field": "detail_amplitude", "value": 40.0, "want": 30.0},
	]
	for c in float_clamps:
		var ffield := String(c["field"])
		var fout := GenParams.validate(_with(c["field"], c["value"]))
		var fparams := Dictionary(fout["params"])
		var fwarns := PackedStringArray(fout["warnings"])
		near(float(fparams[ffield]), float(c["want"]), 0.000001,
				"`%s` = %s 钳制为 %s" % [ffield, str(c["value"]), str(c["want"])])
		eq(fwarns.size(), 1, "`%s` = %s 恰好 1 条告警" % [ffield, str(c["value"])])
		contains(String(fwarns[0]), ffield, "告警点名了 `%s`" % ffield)

	# --- 5. 类型错误 / 未知键 / 缺键 ------------------------------------------
	section("类型错误、未知键、缺键：逐项告警且只影响该字段")
	var bt := GenParams.validate(_with("map_size", "big"))
	eq(int(Dictionary(bt["params"])["map_size"]), 2400, "字符串类型的 map_size 回退默认 2400")
	contains(String(PackedStringArray(bt["warnings"])[0]), "类型错误", "告警说明是类型错误")

	var bb := GenParams.validate(_with("factions", true))
	eq(int(Dictionary(bb["params"])["factions"]), 3, "bool 类型回退默认 3")

	var un := GenParams.validate(_with("map_sizee", 2))
	eq(int(Dictionary(un["params"])["map_size"]), 2400, "未知键不影响实际字段")
	contains(String(PackedStringArray(un["warnings"])[0]), "map_sizee", "告警点名了拼错的键")

	var missing := GenParams.defaults()
	missing["schema"] = GenParams.SCHEMA
	missing.erase("factions")
	var mi := GenParams.validate(missing)
	eq(int(Dictionary(mi["params"])["factions"]), 3, "缺字段取默认值 3")
	contains(String(PackedStringArray(mi["warnings"])[0]), "缺少字段", "告警说明字段缺失")

	var fr := GenParams.validate(_with("towns", 3.7))
	eq(int(Dictionary(fr["params"])["towns"]), 4, "3.7 四舍五入为 4")
	contains(String(PackedStringArray(fr["warnings"])[0]), "四舍五入", "告警说明做了取整")

	# 浮点字段不吃这一套：区间内的非整数值必须原样保留（否则山坡高度会被悄悄抹平）
	var frac := GenParams.validate(_with("hill_amplitude", 137.5))
	near(float(Dictionary(frac["params"])["hill_amplitude"]), 137.5, 0.000001,
			"137.5 原样保留（浮点字段不取整）")
	eq(PackedStringArray(frac["warnings"]).size(), 0, "区间内的非整数值不产生告警")
	var ftyped := GenParams.validate(_with("water_level", "high"))
	near(float(Dictionary(ftyped["params"])["water_level"]), 0.0, 0.000001,
			"字符串类型的 water_level 回退默认 0.0")
	contains(String(PackedStringArray(ftyped["warnings"])[0]), "类型错误",
			"浮点字段的类型错误也走同一闸门")

	# --- 6. regions 顺序与聚落总数 -------------------------------------------
	section("跨字段约束：regions_min ≤ regions_max、聚落总数落在 [8, 40]")
	var regions := GenParams.defaults()
	regions["schema"] = GenParams.SCHEMA
	regions["regions_min"] = 9
	regions["regions_max"] = 6
	var rg := GenParams.validate(regions)
	var rg_params := Dictionary(rg["params"])
	le(float(rg_params["regions_min"]), float(rg_params["regions_max"]),
			"修正后 regions_min ≤ regions_max")
	contains(String(PackedStringArray(rg["warnings"])[0]), "regions_min", "告警点名 regions_min/regions_max")

	var cw := GenParams.validate(_with("villages", 40))
	var cw_params := Dictionary(cw["params"])
	var cw_total := int(cw_params["villages"]) + int(cw_params["towns"]) + int(cw_params["fortresses"])
	eq(cw_total, 40, "48 个聚落被裁到上限 40")
	eq(int(cw_params["villages"]), 32, "裁掉的是 villages（32），城镇与要塞不动")
	contains(String(PackedStringArray(cw["warnings"])[0]), "聚落总数", "告警说明聚落总数越界")

	var zero := GenParams.defaults()
	zero["schema"] = GenParams.SCHEMA
	zero["villages"] = 0
	zero["towns"] = 0
	zero["fortresses"] = 0
	var em := GenParams.validate(zero)
	var em_params := Dictionary(em["params"])
	eq(int(em_params["villages"]) + int(em_params["towns"]) + int(em_params["fortresses"]),
			8, "0 个聚落被补到下限 8")

	# --- 7. schema 版本 -------------------------------------------------------
	section("schema：缺失只告警、低版本只告警、高版本整表拒读")
	var no_schema := GenParams.defaults()
	no_schema.erase("schema")
	var ns := GenParams.validate(no_schema)
	ok(bool(ns["ok"]), "缺 schema 仍按当前版本读取")
	contains(String(PackedStringArray(ns["warnings"])[0]), "schema", "告警点名 schema 缺失")

	var future := GenParams.defaults()
	future["schema"] = 99
	var fu := GenParams.validate(future)
	ok(not bool(fu["ok"]), "schema 99 判定为不可用")
	eq(bool(fu["used_defaults"]), true, "高版本整表回退默认值")
	contains(String(fu["reason"]), "99", "理由里点名了实际版本 99")

	var array_root := GenParams.validate([1, 2, 3])
	ok(not bool(array_root["ok"]), "数组根判定为不可用")
	eq(int(Dictionary(array_root["params"])["map_size"]), 2400, "数组根回退默认值")

	# --- 8. 坏文件 -----------------------------------------------------------
	section("坏文件：不存在 / 非 JSON 一律回退默认值且不崩")
	var absent := GenParams.load_from("res://data/world/__absent__.json")
	ok(not bool(absent["ok"]), "不存在的表判定为不可用")
	contains(String(absent["reason"]), "不存在", "理由说明文件不存在")
	eq(int(Dictionary(absent["params"])["factions"]), 3, "回退后字段取默认值")

	var broken_path := "res://.verify/s1_1_broken_params.json"
	var fh := FileAccess.open(broken_path, FileAccess.WRITE)
	ok(fh != null, "创建坏表探针文件")
	if fh != null:
		fh.store_string("{ this is not json")
		fh.close()
	var broken := GenParams.load_from(broken_path)
	ok(not bool(broken["ok"]), "非 JSON 表判定为不可用")
	contains(String(broken["reason"]), "不是合法 JSON", "理由说明解析失败")
	eq(PackedStringArray(broken["warnings"]).size(), 1, "坏文件只给 1 条告警")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(broken_path))
	ok(not FileAccess.file_exists(broken_path), "清理坏表探针文件")


## =============================================================================
##  S1.1b 战略尺度：高度场 + region 划分
## =============================================================================
## 高度场（`scripts/world/height_field.gd`）。四组断言：
##   ① 决定论：同 seed 两个**独立实例** 5 625 点逐位相同（不是"看起来差不多"）；
##      换 seed 后 95% 以上的点变（反向对照：证明它不是常量场）；
##   ② 形状：中心是陆、四角是海、海陆都占相当比例、海岸线真的穿越地图、
##      值域被参数夹住、归一化公式可手算复核；
##   ③ 参数真的参与：`hill_amplitude` 减半后 400/400 个采样点必变，
##      `max_height` 随之同步 —— 这条防的是"参数读进来了但没人用"；
##   ④ 代价：75×75 采样的耗时（它是 S1.1 的 800 ms 预算里最贵的一块）。
func _case_height_field() -> void:
	await process_frame

	var loaded := GenParams.load_from()
	ok(bool(loaded["ok"]), "参数表可用（高度场只接受已校验的表）", String(loaded.get("reason", "")))
	var params := Dictionary(loaded["params"])
	var seed_a := 20250929
	var field := HeightField.new(seed_a, params)
	var step := 32.0
	var n := field.sample_count(step)
	var half := field.half_size

	section("决定论：同 seed 同参数，两个独立实例逐点逐位相同")
	eq(n, 75, "2400 / 32 → 每边 75 个采样点")
	var samples := field.sample_heights(step)
	eq(samples.size(), n * n * 3, "采样是 (x, z, h) 三元组，长度 = 75×75×3")
	var twin := HeightField.new(seed_a, params)
	ok(twin.sample_heights(step) == samples, "第二个实例的整张采样表与第一个逐位相同")
	eq(field.sample_count(0.0), 0, "步长 0 返回 0 个采样点（不除零、不崩）")
	eq(field.sample_heights(0.0).size(), 0, "步长 0 的采样表为空")

	section("反向对照：换 seed 后 95% 以上的采样点高度不同")
	var other := HeightField.new(987654, params)
	var other_samples := other.sample_heights(step)
	var differing := 0
	for i in range(2, samples.size(), 3):
		if samples[i] != other_samples[i]:
			differing += 1
	ge(float(differing), float(n * n) * 0.95, "75×75 中 %d 个点高度不同" % differing)
	ne(samples[2], other_samples[2], "第 1 个采样点的绝对值也不同（不只是整体偏移）")
	ne(field.height_at(123.0, -456.0), other.height_at(123.0, -456.0), "单点高度随 seed 改变")

	section("形状：中心是陆地、四角是海、海陆都占相当比例")
	ok(not field.is_water(0.0, 0.0), "地图中心 (0, 0) 是陆地")
	var corners := [
		Vector2(-half + 1.0, -half + 1.0), Vector2(half - 1.0, -half + 1.0),
		Vector2(-half + 1.0, half - 1.0), Vector2(half - 1.0, half - 1.0),
	]
	for c in corners:
		ok(field.is_water(c.x, c.y), "角落 (%s, %s) 是海" % [str(c.x), str(c.y)])
	var land := 0
	for i in range(2, samples.size(), 3):
		if samples[i] > field.water_level:
			land += 1
	var ratio := float(land) / float(n * n)
	ge(ratio, 0.25, "陆地占比 %s 不低于 25%%（不是一颗小石子）" % str(snappedf(ratio, 0.001)))
	le(ratio, 0.85, "陆地占比 %s 不高于 85%%（也不是一片没有海的沙盘）" % str(snappedf(ratio, 0.001)))

	section("海岸线：沿 z=0 的水陆切换次数 ≥ 2")
	var crossings := 0
	var prev_water := field.is_water(-half + 1.0, 0.0)
	var x := -half + 1.0
	while x < half - 1.0:
		x += 10.0
		var w := field.is_water(x, 0.0)
		if w != prev_water:
			crossings += 1
			prev_water = w
	ge(float(crossings), 2.0, "扫过 %d 次水陆切换（海岸线真的穿过地图）" % crossings)

	section("值域：无 NaN/INF、上下界由参数决定、归一化在 0..1")
	var bad := 0
	var lo := INF
	var hi := -INF
	for i in range(2, samples.size(), 3):
		var h := samples[i]
		if not is_finite(h):
			bad += 1
			continue
		lo = minf(lo, h)
		hi = maxf(hi, h)
	eq(bad, 0, "5 625 个采样点里没有 NaN / INF")
	var floor_h := field.base_height - field.hill_amplitude * HeightField.SHELF_DROP - field.detail_amplitude
	near(field.max_height, field.base_height + field.hill_amplitude * HeightField.RELIEF_CEILING
			+ field.detail_amplitude, 0.000001, "max_height = base + hill×RELIEF_CEILING + detail")
	ge(lo, floor_h - 1.0, "最低点 %s 不低于理论下界 %s"
			% [str(snappedf(lo, 0.01)), str(snappedf(floor_h, 0.01))])
	le(hi, field.max_height + 1.0, "最高点 %s 不高于理论上限 %s"
			% [str(snappedf(hi, 0.01)), str(snappedf(field.max_height, 0.01))])
	ge(hi, field.water_level + 40.0, "确实存在 40 m 以上的山地（不是一块平板）")
	near(field.normalized_height_at(0.0, 0.0),
			clampf((field.height_at(0.0, 0.0) - field.water_level)
			/ (field.max_height - field.water_level), 0.0, 1.0),
			0.000001, "归一化高度 = (h − water_level) / (max_height − water_level)")
	near(field.normalized_height_at(-half + 1.0, -half + 1.0), 0.0, 0.000001, "海面归一化为 0")

	section("坡度：slope_at 可手算复核、最陡处明显陡于海底")
	var e := HeightField.SLOPE_STEP
	var manual := sqrt(pow((field.height_at(e, 0.0) - field.height_at(-e, 0.0)) / (2.0 * e), 2.0)
			+ pow((field.height_at(0.0, e) - field.height_at(0.0, -e)) / (2.0 * e), 2.0))
	near(field.slope_at(0.0, 0.0), manual, 0.000001, "slope_at(0,0) 与手算中心差分一致")
	ge(field.slope_at(0.0, 0.0), 0.0, "坡度非负")
	var max_slope := 0.0
	for i in 400:
		var px := lerpf(-half, half, float(i % 20) / 19.0)
		var pz := lerpf(-half, half, float(i / 20) / 19.0)
		max_slope = maxf(max_slope, field.slope_at(px, pz))
	var shelf_slope := field.slope_at(-half + 1.0, -half + 1.0)
	ge(max_slope, 0.12, "陆地上存在 %s 的坡度（不是一块平板）" % str(snappedf(max_slope, 0.001)))
	ge(max_slope, shelf_slope, "最陡处 %s 不陡于深海底 %s 的反面（地形有高低差）"
			% [str(snappedf(max_slope, 0.001)), str(snappedf(shelf_slope, 0.001))])

	section("生物群系：水是 water、其余落在合法集合、且真的分层")
	eq(field.biome_at(-half + 1.0, -half + 1.0), HeightField.BIOME_WATER, "海面 biome = water")
	ok(field.biome_at(0.0, 0.0) != HeightField.BIOME_WATER, "地图中心 biome ≠ water")
	var unknown_biome := 0
	var seen := {}
	for i in 900:
		var px := lerpf(-half + 20.0, half - 20.0, float(i % 30) / 29.0)
		var pz := lerpf(-half + 20.0, half - 20.0, float(i / 30) / 29.0)
		var b := field.biome_at(px, pz)
		seen[b] = true
		if not HeightField.BIOMES.has(b):
			unknown_biome += 1
	eq(unknown_biome, 0, "900 个采样点的 biome 全在合法集合内")
	ge(float(seen.size()), 4.0, "一次扫描出现 %d 种 biome（水/滩/草/高地确实分层）" % seen.size())
	ok(seen.has(HeightField.BIOME_WATER), "扫描包含 water")
	ok(seen.has(HeightField.BIOME_GRASS), "扫描包含 grass")
	ok(HeightField.LAND_BIOMES.size() == 5, "陆地群系恰好 5 种（beach/grass/forest/highland/snow）")

	section("参数真的参与：hill_amplitude 减半后 400/400 个采样点必变")
	var raised := Dictionary(params.duplicate())
	raised["hill_amplitude"] = float(params["hill_amplitude"]) * 0.5
	var halved := HeightField.new(seed_a, raised)
	var moved := 0
	for i in 400:
		var px := lerpf(-half, half, float(i % 20) / 19.0)
		var pz := lerpf(-half, half, float(i / 20) / 19.0)
		if halved.height_at(px, pz) != field.height_at(px, pz):
			moved += 1
	eq(moved, 400, "400 / 400 个采样点高度都变了（参数不是摆设）")
	near(halved.max_height, halved.base_height + halved.hill_amplitude * HeightField.RELIEF_CEILING
			+ halved.detail_amplitude, 0.000001, "max_height 随参数同步（不是硬编码常量）")
	near(halved.hill_amplitude, float(params["hill_amplitude"]) * 0.5, 0.000001,
			"实例读到的 hill_amplitude 就是表里的一半")
	var again := HeightField.new(seed_a, Dictionary(params.duplicate()))
	near(again.height_at(123.0, -456.0), field.height_at(123.0, -456.0), 0.000001,
			"同参数重新构造后同一点复原（减法没有副作用）")

	section("代价：75×75 采样耗时（S1.1 的 800 ms 预算里最贵的一块）")
	var t0 := Time.get_ticks_usec()
	var fresh := field.sample_heights(step)
	var dt := float(Time.get_ticks_usec() - t0) / 1000.0
	eq(fresh.size(), samples.size(), "重采样长度一致")
	le(dt, 400.0, "5 625 点耗时 %s ms < 400 ms" % str(snappedf(dt, 0.1)))


## region 划分（`scripts/world/regions.gd`）。四组断言：
##   ① 数量与 id：落在 `regions_min..max`、无告警、id 稠密（删空后重编号）；
##   ② 面积守恒：每个陆地格恰属一个 region，水格 owner = -1，
##      面积和 = 陆地格数 × 32²（这条是"没有空洞"的可计算版本）；
##   ③ 点查询：每个中心点回到自己的 region、水点与地图外返回 -1；
##   ④ 决定论：重放同一 `Rng` 状态逐格相同，换 seed 必变（反向对照）。
func _case_regions() -> void:
	await process_frame

	var loaded := GenParams.load_from()
	ok(bool(loaded["ok"]), "参数表可用", String(loaded.get("reason", "")))
	var params := Dictionary(loaded["params"])
	var rng_node := get_root().get_node_or_null("Rng")
	ok(rng_node != null, "autoload Rng 可用（region 中心只用具名子流）")
	if rng_node == null or not bool(loaded["ok"]):
		return
	var stream: RandomNumberGenerator = rng_node.call("stream", "world_gen")
	ok(stream is RandomNumberGenerator, "world_gen 子流是 RandomNumberGenerator")
	var field := HeightField.new(20250929, params)
	var saved: int = stream.state

	var regs := WorldRegions.new(field, stream, params)
	var summary := regs.build()
	ok(bool(summary["ok"]), "build 成功")
	var warns := PackedStringArray(summary["warnings"])
	eq(warns.size(), 0, "真表 + 默认 seed 下没有告警（实际：%s）" % str(warns))
	var count := int(summary["count"])
	ge(float(count), float(params["regions_min"]), "region 数 %d 不低于 regions_min %d"
			% [count, int(params["regions_min"])])
	le(float(count), float(params["regions_max"]), "region 数 %d 不高于 regions_max %d"
			% [count, int(params["regions_max"])])

	section("id 稠密：0..count-1，没有因为删空 region 留下空洞")
	var ids_ok := true
	for i in count:
		if int(regs.regions[i]["id"]) != i:
			ids_ok = false
	ok(ids_ok, "%d 个 region 的 id 恰好是 0..%d" % [count, count - 1])
	eq(regs.region_info(count).size(), 0, "越界 id 的 region_info 返回空字典")
	eq(regs.region_info(-1).size(), 0, "负 id 的 region_info 返回空字典")

	section("面积守恒：陆地格恰属一个 region，水格无主，面积和 = 陆地面积")
	var total_cells := regs.grid_w * regs.grid_h
	eq(regs.grid_w, 75, "2400 / 32 → 每边 75 个归属格")
	eq(total_cells, 75 * 75, "75×75 = 5 625 个 32 m 格子")
	eq(regs.cell_count_total(), int(summary["land_cells"]), "各 region 格数之和 = 陆地格数")
	eq(regs.water_cell_count(), total_cells - int(summary["land_cells"]), "水格数 = 总格数 − 陆地格数")
	near(regs.area_total(), float(summary["land_cells"]) * regs.cell * regs.cell, 0.5,
			"面积和 = 陆地格数 × 32²")
	ok(regs.water_cell_count() > 0, "确实存在水格（否则『全覆盖』是真空通过）")
	var empty := 0
	for r in regs.regions:
		if int(r["cells"]) <= 0:
			empty += 1
	eq(empty, 0, "没有 0 格的空 region")

	section("全网格核对：水格 owner = -1、陆格 owner 合法（0 处矛盾）")
	var mismatched := 0
	var water_seen := 0
	var land_seen := 0
	for j in regs.grid_h:
		for i in regs.grid_w:
			var px := -regs.half_size + (float(i) + 0.5) * regs.cell
			var pz := -regs.half_size + (float(j) + 0.5) * regs.cell
			var who := regs.owner[j * regs.grid_w + i]
			if field.is_water(px, pz):
				water_seen += 1
				if who != -1:
					mismatched += 1
			else:
				land_seen += 1
				if who < 0 or who >= count:
					mismatched += 1
	eq(mismatched, 0, "5 625 格逐格核对无矛盾")
	eq(water_seen, regs.water_cell_count(), "逐格统计的水格数 = water_cell_count()")
	eq(land_seen, int(summary["land_cells"]), "逐格统计的陆格数 = land_cells")

	section("点查询：中心点回到自己的 region、水点与地图外返回 -1")
	for i in count:
		var c := regs.region_info(i)
		eq(regs.region_at(float(c["x"]), float(c["z"])), i,
				"区域 %d 的中心点落在自己区域内" % i)
	eq(regs.region_at(-regs.half_size - 10.0, 0.0), -1, "地图外的点返回 -1")
	eq(regs.region_at(0.0, regs.half_size + 10.0), -1, "地图外的点（另一侧）返回 -1")
	var water_centres := 0
	for r in regs.regions:
		if not HeightField.LAND_BIOMES.has(String(r["biome"])):
			water_centres += 1
	eq(water_centres, 0, "所有 region 中心都不是 water（中心只放在陆地上）")
	ge(float(regs.biome_counts().size()), 1.0, "biome_counts 非空")

	section("决定论：重放同一 Rng 状态逐格相同；换 seed 后必变（反向对照）")
	stream.state = saved
	var replay := WorldRegions.new(field, stream, params)
	var replayed := replay.build()
	eq(int(replayed["count"]), count, "重放后 region 数相同")
	ok(replay.owner == regs.owner, "重放后 5 625 格归属逐格相同")
	var alt_field := HeightField.new(20250930, params)
	stream.state = saved
	var altered := WorldRegions.new(alt_field, stream, params)
	altered.build()
	var identical := (int(altered.regions.size()) == count) and (altered.owner == regs.owner)
	ok(not identical, "换 seed 后数量或归属至少一项不同")

	section("代价：一次 build 的耗时")
	stream.state = saved
	var t0 := Time.get_ticks_usec()
	var perf := WorldRegions.new(field, stream, params)
	perf.build()
	var dt := float(Time.get_ticks_usec() - t0) / 1000.0
	le(dt, 500.0, "一次 build 耗时 %s ms < 500 ms" % str(snappedf(dt, 0.1)))
	eq(perf.grid_w, 75, "重复 build 不改变网格尺寸")


## =============================================================================
##  S1.1c 世界数据：聚落 / 道路 / 势力 / 队伍 + 手工锚点
## =============================================================================
func _case_world() -> void:
	await process_frame

	var loaded := GenParams.load_from()
	ok(bool(loaded["ok"]), "参数表可用", String(loaded.get("reason", "")))
	eq(PackedStringArray(loaded["warnings"]).size(), 0, "真表零告警")
	var params := Dictionary(loaded["params"])
	var world_seed := 20250929

	section("锚点表：3 条、字节规范、坐标全是有限数")
	var anchors_path := WorldData.PATH
	var raw := _read_text_file(anchors_path)
	ok(raw.length() > 0, "锚点表可读（%d 字符）" % raw.length())
	contains(raw, "\"schema\": 1", "锚点表带 schema = 1")
	var canon := Canon.canonicalize(raw)
	ok(bool(canon["ok"]), "锚点表是合法 JSON", String(canon.get("reason", "")))
	eq(String(canon.get("text", "")), raw, "锚点表逐字节等于自己的规范化结果")
	eq(raw.count("\r"), 0, "锚点表没有 CR")
	ok(raw.ends_with("\n") and not raw.ends_with("\n\n"), "锚点表末尾恰好一个换行")

	var loaded_anchors := WorldData.load_anchors()
	ok(bool(loaded_anchors["ok"]), "锚点表经 load_anchors 可读", String(loaded_anchors.get("reason", "")))
	eq(PackedStringArray(loaded_anchors["warnings"]).size(), 0, "真锚点表零告警")
	var anchor_list: Array = loaded_anchors["anchors"]
	eq(anchor_list.size(), 3, "锚点 3 条")
	var kinds_seen := {}
	for a in anchor_list:
		var k := String(a["kind"])
		kinds_seen[k] = int(kinds_seen.get(k, 0)) + 1
		ok(is_finite(float(a["x"])) and is_finite(float(a["z"])), "锚点 `%s` 坐标有限" % String(a["id"]))
	eq(kinds_seen.size(), 3, "三种 kind 各一条（村庄 / 城镇 / 要塞）")

	section("生成：配额全部放出来，零告警")
	var rng: Node = get_root().get_node_or_null("Rng")
	ok(rng != null, "Rng autoload 在位（--script 下经 tree root 取）")
	var stream: RandomNumberGenerator = rng.call("stream", "world_gen")
	var field := HeightField.new(world_seed, params)
	var regions := WorldRegions.new(field, stream, params)
	ok(bool(regions.build()["ok"]), "region 划分成功")
	var saved_state := stream.state

	var data := WorldData.new(world_seed, params, field, regions, stream, anchor_list)
	var built := data.build()
	ok(bool(built["ok"]), "世界构建成功", String(built.get("reason", "")))
	var warns := PackedStringArray(built["warnings"])
	eq(warns.size(), 0, "默认参数零告警（实际：%s）" % str(warns))

	var settlements: Array = built["settlements"]
	var roads: Array = built["roads"]
	var factions: Array = built["factions"]
	var parties: Array = built["parties"]
	var counts := Dictionary(built["counts"])
	eq(settlements.size(), 20, "聚落 20 个（12 + 4 + 4）")
	eq(int(counts.get("village", 0)), 12, "村庄 12")
	eq(int(counts.get("town", 0)), 4, "城镇 4")
	eq(int(counts.get("fortress", 0)), 4, "要塞 4")
	eq(int(counts.get("village", 0)) + int(counts.get("town", 0)) + int(counts.get("fortress", 0)),
			settlements.size(), "三类之和 = 总数（没有第四类混进来）")
	eq(factions.size(), 3, "势力 3 个")
	eq(parties.size(), 24, "AI 队伍 24 支")
	var no_region := 0
	for s in settlements:
		if int(s["region"]) < 0:
			no_region += 1
	eq(no_region, 0, "每个聚落都落在某个 region 里（region id ≥ 0）")

	section("合法性：陆地 + 坡度 + 间距")
	var spacing := float(built["spacing"])
	var limit := float(built["slope_limit"])
	eq(spacing, float(params["settlement_min_spacing"]), "间距取自参数表")
	eq(limit, float(params["settlement_slope_limit"]), "坡度上限取自参数表")
	var bad_spots := _world_violations(settlements, field, spacing, limit)
	eq(bad_spots.size(), 0, "20 个聚落全部合法（实际：%s）" % str(bad_spots))
	var bad_parties := _world_violations(parties, field, 0.0, limit)
	eq(bad_parties.size(), 0, "24 支队伍全部落在可站立处（实际：%s）" % str(bad_parties))
	var min_gap := INF
	for i in range(settlements.size()):
		for j in range(i + 1, settlements.size()):
			var d := Vector2(float(settlements[i]["x"]), float(settlements[i]["z"])).distance_to(
					Vector2(float(settlements[j]["x"]), float(settlements[j]["z"])))
			min_gap = minf(min_gap, d)
	ge(min_gap, spacing, "最小聚落间距 %s m ≥ %s m" % [str(snappedf(min_gap, 0.1)), str(spacing)])

	section("锚点 100% 生效：坐标逐位等于表，且排在最前")
	eq(_anchor_mismatches(settlements, anchor_list), 0, "3 个锚点全部 100% 命中")
	for a in anchor_list:
		var s := data.settlement_by_id(String(a["id"]))
		ok(not s.is_empty(), "锚点 `%s` 在聚落表里" % String(a["id"]))
		eq(float(s["x"]), float(a["x"]), "锚点 `%s` 的 x 逐位等于表" % String(a["id"]))
		eq(float(s["z"]), float(a["z"]), "锚点 `%s` 的 z 逐位等于表" % String(a["id"]))
		eq(String(s["kind"]), String(a["kind"]), "锚点 `%s` 的 kind 跟随表" % String(a["id"]))
		ok(bool(s["anchor"]), "锚点 `%s` 标记为手工锚点" % String(a["id"]))
	ok(settlements.size() >= 3 and bool(settlements[0]["anchor"]) and bool(settlements[1]["anchor"])
			and bool(settlements[2]["anchor"]), "前 3 个聚落都是锚点（先钉后撒）")

	section("势力：首都唯一且是城镇、每座聚落都有归属、每方都有队伍")
	var capitals := {}
	for f in factions:
		var cid := String(f["capital"])
		var cap := data.settlement_by_id(cid)
		ok(not cap.is_empty(), "势力 `%s` 的首都 `%s` 存在" % [String(f["id"]), cid])
		ok(not capitals.has(cid), "首都 `%s` 不与其他势力共用" % cid)
		capitals[cid] = true
		eq(String(cap.get("kind", "")), "town", "首都 `%s` 是城镇" % cid)
	for s in settlements:
		ge(float(s["faction"]), 0.0, "聚落 `%s` 有势力归属" % String(s["id"]))
		le(float(s["faction"]), float(factions.size() - 1), "聚落 `%s` 的势力号在范围内" % String(s["id"]))
	var per_faction := {}
	for p in parties:
		var fid := int(p["faction"])
		per_faction[fid] = int(per_faction.get(fid, 0)) + 1
	eq(per_faction.size(), factions.size(), "每个势力都有队伍")
	var fewest := 99
	var most := 0
	for fid in per_faction.keys():
		fewest = mini(fewest, int(per_faction[fid]))
		most = maxi(most, int(per_faction[fid]))
	le(float(most - fewest), 1.0, "各势力队伍数相差不超过 1（轮流分配，实际 %d..%d）" % [fewest, most])
	var party_ids := {}
	for p in parties:
		var hid := String(p["home"])
		ok(not data.settlement_by_id(hid).is_empty(), "队伍 `%s` 的母城存在" % String(p["id"]))
		eq(int(data.settlement_by_id(hid)["faction"]), int(p["faction"]), "队伍 `%s` 的母城属于同一势力" % String(p["id"]))
		ok(not party_ids.has(String(p["id"])), "队伍 id `%s` 唯一" % String(p["id"]))
		party_ids[String(p["id"])] = true

	section("道路图：单连通、无自环、无重边、长度可累加")
	eq(_graph_components(settlements, roads), 1, "整张图是 1 个连通分量")
	ge(float(roads.size()), float(settlements.size() - 1), "边数 %d ≥ n-1 = %d" % [roads.size(), settlements.size() - 1])
	var total := 0.0
	var seen_edges := {}
	for r in roads:
		var a := data.settlement_by_id(String(r["a"]))
		var b := data.settlement_by_id(String(r["b"]))
		ok(not a.is_empty() and not b.is_empty(), "边 %s-%s 两端都存在" % [String(r["a"]), String(r["b"])])
		ne(String(r["a"]), String(r["b"]), "没有自环")
		var key := "%s|%s" % [String(r["a"]), String(r["b"])]
		var key_rev := "%s|%s" % [String(r["b"]), String(r["a"])]
		ok(not seen_edges.has(key) and not seen_edges.has(key_rev), "边 %s 没有重复" % key)
		seen_edges[key] = true
		var d := Vector2(float(a["x"]), float(a["z"])).distance_to(Vector2(float(b["x"]), float(b["z"])))
		near(float(r["length"]), d, 0.001, "边长 = 两端直线距离")
		total += d
	near(float(built["road_length_total"]), total, 0.01, "总长 = 各边之和")

	section("反向对照：删掉一个聚落的全部边必须断开；挪到水面必须被检出；改锚点表必须失配")
	var isolated := String(settlements[0]["id"])
	var cut: Array = []
	for r in roads:
		if String(r["a"]) != isolated and String(r["b"]) != isolated:
			cut.append(r)
	ge(float(_graph_components(settlements, cut)), 2.0, "把 `%s` 的边全删掉后，连通分量 ≥ 2" % isolated)
	var sunk: Array = settlements.duplicate(true)
	sunk[1]["x"] = -1190.0
	sunk[1]["z"] = -1190.0
	ge(float(_world_violations(sunk, field, spacing, limit).size()), 1.0, "挪到海角的聚落被合法性检查逮住")
	var corrupt: Array = anchor_list.duplicate(true)
	corrupt[0]["x"] = float(corrupt[0]["x"]) + 100.0
	stream.state = saved_state
	var corrupt_data := WorldData.new(world_seed, params, field, regions, stream, corrupt)
	var corrupt_built := corrupt_data.build()
	var corrupt_settlements: Array = corrupt_built["settlements"]
	eq(_anchor_mismatches(corrupt_settlements, corrupt), 0, "锚点表被改后，新世界跟随新表（锚点仍 100% 生效）")
	eq(_anchor_mismatches(corrupt_settlements, anchor_list), 1, "但拿旧表去核，恰好 1 条失配（说明断言不是恒真）")

	section("坏锚点：kind 非法 / 落水 ⇒ 跳过并告警，配额照旧补齐")
	stream.state = saved_state
	var broken: Array = [
		{"id": "bad_kind", "kind": "castle", "name": "错类", "x": 0.0, "z": 0.0},
		{"id": "bad_water", "kind": "village", "name": "落水", "x": -1190.0, "z": -1190.0},
	]
	var broken_data := WorldData.new(world_seed, params, field, regions, stream, broken)
	var broken_built := broken_data.build()
	var broken_warns := PackedStringArray(broken_built["warnings"])
	ge(float(broken_warns.size()), 2.0, "两条坏锚点各留一条告警（实际：%s）" % str(broken_warns))
	ok(bool(broken_built["ok"]), "坏锚点不导致整次失败")
	eq(Array(broken_built["settlements"]).size(), 20, "跳过坏锚点后仍按配额补齐 20 个")

	section("间距不可行：降级为告警，不死循环、不崩")
	var tight := GenParams.defaults()
	tight["schema"] = GenParams.SCHEMA
	tight["settlement_min_spacing"] = 900.0
	stream.state = saved_state
	var tight_data := WorldData.new(world_seed, tight, field, regions, stream, anchor_list)
	var t_tight := Time.get_ticks_usec()
	var tight_built := tight_data.build()
	var tight_ms := float(Time.get_ticks_usec() - t_tight) / 1000.0
	ok(bool(tight_built["ok"]), "仍返回 ok（降级不是失败）")
	ge(float(PackedStringArray(tight_built["warnings"]).size()), 1.0, "有告警说明放不下")
	ge(float(Array(tight_built["settlements"]).size()), 1.0, "仍放下至少 1 个")
	ok(Array(tight_built["settlements"]).size() < 20, "数量确实少于 20")
	le(tight_ms, 3000.0, "降级路径 %s ms 内结束（不是死循环）" % str(snappedf(tight_ms, 0.1)))

	section("决定论：同 seed 两次构建指纹逐位相同")
	stream.state = saved_state
	var again := WorldData.new(world_seed, params, field, regions, stream, anchor_list)
	var again_built := again.build()
	eq(PackedStringArray(again_built["warnings"]).size(), 0, "复现时依旧零告警")
	eq(again.fingerprint(), data.fingerprint(), "两次构建的指纹逐位相同")

	section("反向对照：换 seed 后世界确实不同")
	stream.state = saved_state
	var field_b := HeightField.new(world_seed + 987654, params)
	var regions_b := WorldRegions.new(field_b, stream, params)
	regions_b.build()
	var other := WorldData.new(world_seed + 987654, params, field_b, regions_b, stream, anchor_list)
	other.build()
	ne(other.fingerprint(), data.fingerprint(), "换 seed 后指纹不同")
	var moved := 0
	var other_settlements: Array = other.settlements
	for i in range(mini(settlements.size(), other_settlements.size())):
		if float(settlements[i]["x"]) != float(other_settlements[i]["x"]) \
				or float(settlements[i]["z"]) != float(other_settlements[i]["z"]):
			moved += 1
	ge(float(moved), 10.0, "20 个聚落里 %d 个坐标变化（差异不只在 seed 那一行）" % moved)

	section("代价（S1.1d 的 C- 预算 800 ms）")
	stream.state = saved_state
	var t0 := Time.get_ticks_usec()
	WorldData.new(world_seed, params, field, regions, stream, anchor_list).build()
	var dt := float(Time.get_ticks_usec() - t0) / 1000.0
	le(dt, 800.0, "一次 build %s ms < 800 ms" % str(snappedf(dt, 0.1)))


## S1.1d — 序列化。同 seed 两次构建的文本**逐字节**相同、读回再写幂等、
## 数组按稳定键排序、锚点坐标逐位落进文本；换 seed 后文本不同。
## 同时量一次"整条生成链"（高度场 + region + 世界数据 + 序列化）的耗时。
func _case_world_gen() -> void:
	await process_frame
	var fx := _world_fixture()
	var params: Dictionary = fx["params"]
	var anchors: Array = fx["anchors"]
	var field: HeightField = fx["field"]
	var regions: WorldRegions = fx["regions"]
	var stream: RandomNumberGenerator = fx["stream"]
	var state: int = fx["state"]
	var world_seed: int = fx["seed"]

	section("序列化：同 seed 两次构建，文本逐字节相同")
	stream.state = state
	var a := WorldData.new(world_seed, params, field, regions, stream, anchors)
	a.build()
	var res_a := a.to_text()
	ok(bool(res_a["ok"]), "序列化成功", String(res_a.get("reason", "")))
	var text_a := String(res_a["text"])
	ok(text_a.length() > 0, "生成文本 %d 字符" % text_a.length())
	stream.state = state
	var b := WorldData.new(world_seed, params, field, regions, stream, anchors)
	b.build()
	var res_b := b.to_text()
	ok(bool(res_b["ok"]), "第二次序列化成功", String(res_b.get("reason", "")))
	var text_b := String(res_b["text"])
	eq(text_b, text_a, "两次构建的文本逐字节相同（%d 字符）" % text_a.length())
	eq(b.fingerprint(), a.fingerprint(), "指纹同样逐位相同")

	section("文本是 Canon 规范形式：读回再写幂等、LF、无 CR")
	eq(text_a.count("\r"), 0, "没有 CR")
	ok(text_a.ends_with("\n") and not text_a.ends_with("\n\n"), "末尾恰好一个换行")
	var back := Canon.from_text(text_a)
	ok(bool(back["ok"]), "能读回成 JSON", String(back.get("reason", "")))
	ok(typeof(back["value"]) == TYPE_DICTIONARY, "读回的是对象")
	var parsed := Dictionary(back["value"])
	var rewritten := Canon.to_text(parsed)
	ok(bool(rewritten["ok"]), "读回的对象能重新序列化", String(rewritten.get("reason", "")))
	eq(String(rewritten["text"]), text_a, "读回再序列化与原文逐字节相同（幂等）")
	var canon := Canon.canonicalize(text_a)
	ok(bool(canon["ok"]), "文本本身是合法 JSON", String(canon.get("reason", "")))
	eq(String(canon.get("text", "")), text_a, "文本逐字节等于自己的规范化结果")

	section("顶层键按码点升序（Canon 契约）")
	var keys: Array = parsed.keys()
	var sorted_keys: Array = keys.duplicate()
	sorted_keys.sort()
	eq(str(keys), str(sorted_keys), "顶层键顺序 = 码点升序（实际：%s）" % str(keys))
	for want in ["schema", "world_seed", "params", "metrics", "settlements", "roads",
			"factions", "parties"]:
		ok(parsed.has(want), "顶层含 `%s`" % want)
	eq(int(parsed.get("schema", 0)), WorldData.SCHEMA, "schema = %d" % WorldData.SCHEMA)
	eq(int(parsed.get("world_seed", 0)), world_seed, "world_seed 原样写出")

	section("内容完整：条数与内存一致（不写死 24 —— 边数取决于落点），且按稳定键排序")
	var p_settlements: Array = Array(parsed["settlements"])
	var p_roads: Array = Array(parsed["roads"])
	var p_factions: Array = Array(parsed["factions"])
	var p_parties: Array = Array(parsed["parties"])
	eq(p_settlements.size(), a.settlements.size(), "聚落条数 = 内存里的 %d" % a.settlements.size())
	eq(p_roads.size(), a.roads.size(), "道路条数 = 内存里的 %d" % a.roads.size())
	eq(p_factions.size(), a.factions.size(), "势力条数 = 内存里的 %d" % a.factions.size())
	eq(p_parties.size(), a.parties.size(), "队伍条数 = 内存里的 %d" % a.parties.size())
	eq(a.settlements.size(), 20, "聚落 20 个（12 + 4 + 4 配额）")
	eq(a.factions.size(), 3, "势力 3 个（参数表 factions）")
	eq(a.parties.size(), 24, "队伍 24 支（参数表 ai_parties）")
	ge(float(a.roads.size()), float(a.settlements.size()) - 1.0, "道路 ≥ n−1（单连通骨架，实际 %d 条）" % a.roads.size())
	eq(_sorted_by_field(p_settlements, "id"), true, "聚落按 id 升序")
	eq(_sorted_by_field(p_roads, "a"), true, "道路按 a 升序")
	eq(_sorted_by_field(p_factions, "id"), true, "势力按 id 升序")
	eq(_sorted_by_field(p_parties, "id"), true, "队伍按 id 升序")
	var anchors_out := 0
	for s in p_settlements:
		if bool(s["anchor"]):
			anchors_out += 1
	eq(anchors_out, 3, "3 条锚点都带 anchor = true")
	eq(_anchor_mismatches(p_settlements, anchors), 0, "序列化后的锚点坐标仍与表 100% 一致")
	var total_road := 0.0
	for r in p_roads:
		total_road += float(r["length"])
	# 每条边在文本里只保留 6 位小数，累加会攒到 n×5e-7；用 1 cm 容差，别按浮点后一位卡。
	le(absf(total_road - float(a.road_length_total())), 0.01, "道路长度之和可累加（%s m）" % str(snappedf(total_road, 0.1)))

	section("指标落在文本里，且与内存里的 metrics() 一致")
	var m_in := a.metrics()
	var m_out := Dictionary(Dictionary(parsed)["metrics"])
	eq(String(Canon.to_text(m_out)["text"]), String(Canon.to_text(m_in)["text"]), "文本里的 metrics 与内存一致（按 Canon 规范文本比对）")
	eq(int(m_out.get("settlement_count", 0)), 20, "settlement_count = 20")
	eq(int(m_out.get("road_count", 0)), a.roads.size(), "road_count = %d" % a.roads.size())
	le(absf(float(m_out.get("road_length", 0.0)) - float(a.road_length_total())), 0.01, "road_length 一致（6 位小数内）")
	ok(float(m_out.get("coastline_length", 0.0)) > 0.0, "海岸线长度 > 0（%s m）" % str(snappedf(float(m_out.get("coastline_length", 0.0)), 0.1)))
	ok(float(m_out.get("land_ratio", 0.0)) > 0.25 and float(m_out.get("land_ratio", 0.0)) < 0.85, "陆地占比在 25%%–85%%（%s）" % str(snappedf(float(m_out.get("land_ratio", 0.0)), 0.001)))
	eq(Array(m_out.get("region_areas", [])).size(), int(m_out.get("region_count", 0)), "region_areas 条数 = region_count")
	eq(Array(m_out.get("settlements_by_region", [])).size(), int(m_out.get("region_count", 0)), "settlements_by_region 条数 = region_count")
	var by_region_sum := 0
	for n in Array(m_out.get("settlements_by_region", [])):
		by_region_sum += int(n)
	eq(by_region_sum, 20, "按 region 的聚落计数之和 = 20（没有落在地图外的）")

	section("反向对照：换 seed 后文本不同（不是恒真）")
	stream.state = state
	var other_field := HeightField.new(world_seed + 424242, params)
	var other_regions := WorldRegions.new(other_field, stream, params)
	other_regions.build()
	var other := WorldData.new(world_seed + 424242, params, other_field, other_regions, stream, anchors)
	other.build()
	var other_res := other.to_text()
	ok(bool(other_res["ok"]), "另一 seed 也能序列化", String(other_res.get("reason", "")))
	ne(String(other_res["text"]), text_a, "换 seed 后文本不同")
	ne(str(other.metrics()), str(a.metrics()), "换 seed 后指标也不同")

	section("C- 整条链（高度场 + region + 世界数据 + 序列化）")
	var longest := 0.0
	var samples := PackedFloat32Array()
	for i in range(3):
		stream.state = state
		var t0 := Time.get_ticks_usec()
		var f := HeightField.new(world_seed, params)
		var r := WorldRegions.new(f, stream, params)
		r.build()
		var d := WorldData.new(world_seed, params, f, r, stream, anchors)
		d.build()
		var _t := d.to_text()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		samples.append(ms)
		longest = maxf(longest, ms)
	le(longest, 800.0, "最慢一轮 %s ms < 800 ms（三次：%s）" % [str(snappedf(longest, 0.1)), str(samples)])


## S1.1d — 宏观指标必须随 seed 变化。**不拿"聚落数"当指标**：默认配额固定
## （12 + 4 + 4），它恒为 20，恒真断言证明不了任何事；改用 `settlements_by_region`
## 这类真的会动的分布。见 `docs/ENGINEERING.md` §9.8。
func _case_world_variety() -> void:
	await process_frame
	var fx := _world_fixture()
	var params: Dictionary = fx["params"]
	var anchors: Array = fx["anchors"]
	var stream: RandomNumberGenerator = fx["stream"]
	var state: int = fx["state"]

	var seeds := [20250929, 20250930, 31415926]
	var metrics_list: Array = []
	var texts := PackedStringArray()
	for s in seeds:
		stream.state = state
		var field := HeightField.new(int(s), params)
		var regions := WorldRegions.new(field, stream, params)
		regions.build()
		var data := WorldData.new(int(s), params, field, regions, stream, anchors)
		data.build()
		metrics_list.append(data.metrics())
		var res := data.to_text()
		ok(bool(res["ok"]), "seed %s 序列化成功" % str(s), String(res.get("reason", "")))
		texts.append(String(res["text"]))

	section("三个 seed：文本两两不同")
	eq(texts.size(), 3, "三次构建都产出了文本")
	ne(texts[0], texts[1], "%s 与 %s 的文本不同" % [seeds[0], seeds[1]])
	ne(texts[1], texts[2], "%s 与 %s 的文本不同" % [seeds[1], seeds[2]])
	ne(texts[0], texts[2], "%s 与 %s 的文本不同" % [seeds[0], seeds[2]])

	section("四个宏观指标：换 seed 必须动（至少 3 项）")
	var moved := 0
	for key in WorldData.METRIC_VARIETY:
		var k := String(key)
		var differ := false
		for i in range(1, metrics_list.size()):
			if str(Dictionary(metrics_list[0]).get(k)) != str(Dictionary(metrics_list[i]).get(k)):
				differ = true
		ok(differ, "指标 `%s` 至少在一个 seed 上变化" % k)
		if differ:
			moved += 1
	ge(float(moved), 3.0, "至少 3 项指标随 seed 变化（实际 %d / %d）" % [moved, WorldData.METRIC_VARIETY.size()])

	section("为什么不拿聚落数当指标：它恒为 20")
	for i in range(metrics_list.size()):
		eq(int(Dictionary(metrics_list[i]).get("settlement_count", 0)), 20,
				"seed %s 的聚落数 = 20（配额固定 ⇒ 恒真）" % str(seeds[i]))

	section("指标的取值范围（顺带守住爆炸与塌缩）")
	for i in range(metrics_list.size()):
		var m: Dictionary = metrics_list[i]
		var label := str(seeds[i])
		var ratio := float(m.get("land_ratio", 0.0))
		ok(ratio > 0.25 and ratio < 0.85, "seed %s 陆地占比 %s 在 25%%–85%%" % [label, str(snappedf(ratio, 0.001))])
		var coast := float(m.get("coastline_length", 0.0))
		ok(coast > 1000.0 and coast < 40000.0, "seed %s 海岸线 %s m 在合理量级" % [label, str(snappedf(coast, 0.1))])
		var rc := int(m.get("region_count", 0))
		ok(rc >= 4 and rc <= 12, "seed %s 的 region 数 %d 落在安全区间 4–12" % [label, rc])
		var areas: Array = Array(m.get("region_areas", []))
		var area_min := INF
		var area_max := 0.0
		for area in areas:
			area_min = minf(area_min, float(area))
			area_max = maxf(area_max, float(area))
		ok(area_min > 0.0, "seed %s 每个 region 面积都 > 0" % label)
		ok(area_max / area_min < 50.0, "seed %s 最大/最小 region 面积比 %s < 50" % [label, str(snappedf(area_max / area_min, 0.01))])
		var by_region: Array = Array(m.get("settlements_by_region", []))
		eq(by_region.size(), rc, "seed %s 的分布向量长度 = region 数" % label)


## 世界入口（S1.2a）：`WorldSession.boot()` 先把子流拨回 seed 派生的起点，再按固定顺序
## 建高度场 → region → 世界数据。本用例证明三件事：boot 幂等；先污染子流也不影响结果
## （并有反向对照证明"污染确实会改世界"，所以断言不是恒真）；`strategic_map.tscn` 真的
## 把这个入口接上了。
func _case_world_session() -> void:
	var rng: Node = get_root().get_node_or_null("Rng")
	ok(rng != null, "Rng autoload 存在")
	if rng == null:
		return
	# 母种子回到项目默认值：boot() 自己会 `seed_from`，夹具则按当前母种子派生子流。
	rng.call("seed_from", 20250929)

	section("boot 的基本形状")
	var a := WorldSession.boot(rng, 20250929)
	ok(a.ok, "boot 成功（错误：%s）" % "; ".join(a.errors))
	eq(a.errors.size(), 0, "无致命错误")
	eq(a.warnings.size(), 0, "零告警")
	eq(a.world_seed, 20250929, "session 记住 seed")
	eq(a.region_count(), 8, "默认参数下 8 个 region")
	eq(a.data.settlements.size(), 20, "20 个聚落")
	eq(a.data.roads.size(), 24, "24 条道路")
	eq(a.data.parties.size(), 24, "24 支队伍")
	near(a.map_size(), 2400.0, 0.001, "地图边长 2400 m")
	ge(float(a.metrics().size()), 8.0, "指标至少有 8 个键")
	contains(a.summary_text(), "20 个聚落", "摘要可读")

	var base_text := String(Dictionary(a.to_text())["text"])
	ok(base_text.length() > 5000, "文本长度 > 5000 字符（实际 %d）" % base_text.length())

	section("同 seed 两次 boot 逐字节相同")
	var b := WorldSession.boot(rng, 20250929)
	eq(String(Dictionary(b.to_text())["text"]), base_text, "两次 boot 文本逐字节相同")

	section("反向对照：不重置子流，世界真的会变")
	var stream: RandomNumberGenerator = rng.call("stream", WorldSession.STREAM_NAME)
	for i in 200:
		stream.randf()
	var loaded := GenParams.load_from()
	var params := Dictionary(loaded["params"])
	var field := HeightField.new(20250929, params)
	var regions := WorldRegions.new(field, stream, params)
	regions.build()
	var anchors: Array = []
	var anchor_table := WorldData.load_anchors()
	if bool(anchor_table["ok"]):
		anchors = Array(anchor_table["anchors"])
	var dirty := WorldData.new(20250929, params, field, regions, stream, anchors)
	dirty.build()
	var dirty_text := String(Dictionary(dirty.to_text())["text"])
	ne(dirty_text, base_text, "先污染子流再直接建世界 ⇒ 文本不同（证明 seed 不是唯一输入时世界会漂）")

	section("正向：污染之后 boot 仍然给出同一个世界")
	var c := WorldSession.boot(rng, 20250929)
	eq(String(Dictionary(c.to_text())["text"]), base_text, "boot 内部的 seed_from 把污染抹掉")
	eq(c.data.roads.size(), a.data.roads.size(), "道路条数不受调用历史影响")

	section("换 seed 必变")
	var d := WorldSession.boot(rng, 20250930)
	ne(String(Dictionary(d.to_text())["text"]), base_text, "seed 20250930 的文本不同")
	eq(d.data.settlements.size(), 20, "换 seed 后聚落数仍是配额 20")

	section("boot 与既有夹具是同一个世界（没有另立一套生成顺序）")
	# 上一步 boot(20250930) 把母种子换掉了；夹具按**当前**母种子派生，所以先拨回来。
	rng.call("seed_from", 20250929)
	var fx := _world_fixture()
	var fx_data := WorldData.new(int(fx["seed"]), Dictionary(fx["params"]),
			fx["field"] as HeightField, fx["regions"] as WorldRegions,
			fx["stream"] as RandomNumberGenerator, Array(fx["anchors"]))
	var fx_result := fx_data.build()
	ok(bool(fx_result["ok"]), "夹具世界构建成功")
	eq(String(Dictionary(fx_data.to_text())["text"]), base_text,
			"boot() 与 _world_fixture() 的世界逐字节相同")

	section("strategic_map.tscn 真的接上了入口")
	var packed: PackedScene = load("res://scenes/world/strategic_map.tscn") as PackedScene
	ok(packed != null, "strategic_map.tscn 可加载")
	if packed != null:
		var scene := packed.instantiate()
		get_root().add_child(scene)
		await process_frame
		var wired: WorldSession = scene.get("session") as WorldSession
		ok(wired != null, "场景 _ready() 后 session 非空（boot 错误：%s）" % String(scene.get("boot_error")))
		eq(String(scene.get("boot_error")), "", "场景零 boot 错误")
		if wired != null:
			ok(wired.ok, "场景里的世界 build 成功")
			eq(wired.data.settlements.size(), 20, "场景里的世界 20 个聚落")
			eq(wired.warnings.size(), 0, "场景里的世界零告警")
			var state := get_root().get_node_or_null("GameState")
			if state != null:
				eq(wired.world_seed, int(state.get("world_seed")), "场景用的是 GameState.world_seed")
		scene.queue_free()
		await process_frame

	section("失败路径不抛异常")
	var broken := WorldSession.boot(null, 20250929)
	eq(broken.ok, false, "没有 Rng 时 ok = false")
	ge(float(broken.errors.size()), 1.0, "至少一条错误原因")
	contains(broken.summary_text(), "失败", "摘要说明失败")



## S1.2b：战略地形网格。断言分四组 —— 结构与预算、几何合法性、决定论、场景接线。
## 网格是 ield 的纯函数（着色只用位置哈希，不抽随机数），所以「逐字节一致」是可证的；
## 反向对照是换 seed 必须换几何，否则 11 250 三角只是数出来的常量。
func _case_strategic_mesh() -> void:
	var rng: Node = get_root().get_node("Rng")
	rng.call("seed_from", 20250929)
	var s := WorldSession.boot(rng, 20250929)
	ok(s.ok, "前置：世界建成（否则网格无从谈起）")

	section("结构与预算：32 m 网格 / 6×6 分块 / 三角预算")
	var t := StrategicTerrain.new()
	var usec := Time.get_ticks_usec()
	var st := t.build(s.field)
	var build_ms := float(Time.get_ticks_usec() - usec) / 1000.0
	ok(bool(st.get("ok", false)), "build() 成功", str(st.get("reason", "")))
	eq(int(st["cells"]), 75, "75 格：2400 m / 32 m")
	near(float(st["step"]), 32.0, 0.001, "格距恰为 32 m")
	eq(int(st["chunks"]), 36, "6×6 = 36 块")
	eq(int(st["land_tris"]), 11250, "陆面 75×75×2 = 11 250 三角")
	le(int(st["land_tris"]), 34611, "C- 面数不超上限（岛屿 21 632 × 1.6）")
	ok(int(st["water_tris"]) > 0, "有水面三角：%d" % int(st["water_tris"]))
	eq(int(st["water_tris"]) % 2, 0, "水面三角成对（整格拆分）")
	eq(int(st["skirt_tris"]), 1200, "外缘裙边：4 边 × 75 格 × 2 三角 × 2 段")
	ge(float(st["coast_cells"]), 20.0, "海岸墨线覆盖 %d 个干格" % int(st["coast_cells"]))
	var bands: Array = st["bands"]
	eq(bands.size(), 5, "五条色带都有统计")
	var band_sum := 0
	for v in bands:
		band_sum += int(v)
	eq(band_sum, 75 * 75, "色带计数覆盖每一格")
	ok(int(bands[1]) > 0, "海滩带非空：%d 格（海岸环定义，不看绝对高度）" % int(bands[1]))
	ok(int(bands[4]) > 0, "雪顶带非空：%d 格" % int(bands[4]))
	ge(float(st["rock_cells"]), 1.0, "陡坡露出岩石：%d 格" % int(st["rock_cells"]))
	ok(int(st["water_tris"]) > 0 and int(st["water_tris"]) < int(st["land_tris"]),
			"水面三角 %d 少于陆面（海只在低处）" % int(st["water_tris"]))
	le(build_ms, 400.0, "建网格耗时 %.1f ms < 400 ms" % build_ms)

	section("实测网格：数与统计一致、顶点合法、水面在海平面")
	var holder := t.get_node("Chunks")
	var land_nodes := _count_nodes(holder, "Land_")
	var water_nodes := _count_nodes(holder, "Water_")
	var curtain_nodes := _count_nodes(holder, "Curtain")
	eq(land_nodes, 36, "36 个陆块 = 6×6")
	eq(curtain_nodes, 1, "1 个外缘裙边")
	ge(float(water_nodes), 1.0, "水面块 %d 个（只在水下格子上才建，所以可能少于 36）" % water_nodes)
	eq(holder.get_child_count(), land_nodes + water_nodes + curtain_nodes, "块节点数 = 陆 + 水 + 裙边")
	eq(_count_mesh_tris(holder, "Land_"), 11250, "实测陆面三角 == 11 250")
	eq(_count_mesh_tris(holder, "Water_"), int(st["water_tris"]), "实测水面三角 == 统计值")
	var bad := 0
	var ymin := 1e30
	var ymax := -1e30
	var xmax := 0.0
	var zmax := 0.0
	var water_y_bad := 0
	var curtain_ymin := 1e30
	for child in holder.get_children():
		var mi := child as MeshInstance3D
		ok(mi != null and mi.mesh != null, "块 %s 有网格" % String(child.name))
		if mi == null or mi.mesh == null:
			continue
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var is_water := String(child.name).begins_with("Water_")
		var is_curtain := String(child.name).begins_with("Curtain")
		for v in verts:
			if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
				bad += 1
				continue
			if is_curtain:
				curtain_ymin = minf(curtain_ymin, v.y)
			elif is_water:
				if not is_equal_approx(v.y, 0.0):
					water_y_bad += 1
			else:
				ymin = minf(ymin, v.y)
				ymax = maxf(ymax, v.y)
				xmax = maxf(xmax, absf(v.x))
				zmax = maxf(zmax, absf(v.z))
	eq(bad, 0, "顶点无 NaN / Inf")
	eq(water_y_bad, 0, "水面顶点 y 恰为海平面")
	le(xmax, 1200.001, "陆面顶点在 ±1200 m 内（|x| 最大 %.3f）" % xmax)
	le(zmax, 1200.001, "陆面顶点在 ±1200 m 内（|z| 最大 %.3f）" % zmax)
	ge(ymax - ymin, 100.0, "垂直落差 > 100 m（真的有起伏：%.1f m）" % (ymax - ymin))
	le(curtain_ymin, ymin - 55.0, "外缘裙边比最低地形再低 ≥ 55 m（%.1f vs %.1f）" % [curtain_ymin, ymin])
	near(ymin, float(st["min_y"]), 0.02, "最低点与统计一致（%.2f m）" % float(st["min_y"]))
	near(ymax, float(st["max_y"]), 0.02, "最高点与统计一致（%.2f m）" % float(st["max_y"]))

	section("决定论：同 field 逐字节一致，换 seed 必变")
	var sig := _terrain_signature(t)
	ok(sig.length() > 0, "签名非空：%s" % sig)
	var t2 := StrategicTerrain.new()
	var st2 := t2.build(s.field)
	ok(bool(st2.get("ok", false)), "第二次 build 也成功")
	eq(_terrain_signature(t2), sig, "两次 build 几何逐字节一致")
	t2.build(s.field)
	eq(t2.get_node("Chunks").get_child_count(), holder.get_child_count(), "重复 build 不叠加块")
	rng.call("seed_from", 20250930)
	var s2 := WorldSession.boot(rng, 20250930)
	ok(s2.ok, "前置：换 seed 的世界建成")
	var t3 := StrategicTerrain.new()
	t3.build(s2.field)
	ne(_terrain_signature(t3), sig, "换 seed 几何必变（反向对照）")
	ne(int(t3.stats["max_y"]), int(st["max_y"]), "换 seed 最高点不同")

	section("场景接线：地形 + 舞台 + 相机（S1.2c 后根有 5 个子节点）")
	rng.call("seed_from", 20250929)
	var ps := load(WORLD_SCENE) as PackedScene
	ok(ps != null, "strategic_map.tscn 可加载")
	var inst: Node = ps.instantiate()
	get_root().add_child(inst)
	await process_frame
	ok(inst.terrain != null, "场景建出了 StrategicTerrain")
	eq(inst.get_child_count(), 5, "根 5 个子节点：地形 + 舞台三件 + 相机")
	eq(String(inst.get_child(0).name), "StrategicTerrain", "第一个子节点仍是地形")
	var sc: Dictionary = inst.terrain_stats()
	eq(int(sc.get("land_tris", 0)), 11250, "场景里的地形也是 11 250 三角")
	eq(int(sc.get("cells", 0)), 75, "场景里的地形也是 75 格")
	eq(inst.terrain.get_node("Chunks").get_child_count(), holder.get_child_count(), "场景里的块数与离树构建一致")
	inst.queue_free()

	# 清场：不留块节点，也不把母种子留在 20250930
	t.free()
	t2.free()
	t3.free()
	rng.call("seed_from", 20250929)
## 数一个容器下前缀匹配的子节点个数（`Land_` / `Water_` / `Curtain` 各算一类）。
func _count_nodes(container: Node, prefix: String) -> int:
	var total := 0
	for child in container.get_children():
		if String(child.name).begins_with(prefix):
			total += 1
	return total


## 数一个容器下前缀匹配的块里有多少三角（非索引网格：顶点数 / 3）。
func _count_mesh_tris(container: Node, prefix: String) -> int:
	var total := 0
	for child in container.get_children():
		if not String(child.name).begins_with(prefix):
			continue
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		total += verts.size() / 3
	return total


## 位置的定点哈希：跨实例比较「同一张网格」，只吃顶点坐标。
func _terrain_signature(t: StrategicTerrain) -> String:
	var acc := 2166136261
	var holder := t.get_node_or_null("Chunks")
	if holder == null:
		return ""
	for child in holder.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		acc = (acc * 16777619 + verts.size()) & 0x7fffffff
		for v in verts:
			acc = (acc * 16777619 + int(round(v.x * 1000.0))) & 0x7fffffff
			acc = (acc * 16777619 + int(round(v.y * 1000.0))) & 0x7fffffff
			acc = (acc * 16777619 + int(round(v.z * 1000.0))) & 0x7fffffff
	return str(acc)



## 一次"参数表 + 锚点表 + 高度场 + region"夹具。`state` 是 region 建好之后的
## `Rng` 状态，所有后续 `WorldData` 构建都从它重放（同 state ⇒ 同世界）。
##
## 子流在这里**拨回开局状态**（`Rng.reset()`），因为用例共享同一条
## `Rng.stream("world_gen")`：谁先跑谁就把状态推远了 —— 不拨回去的话，"同一个 seed
## 的世界"会随用例执行顺序变化（`--all` 里 26 条边 / 8916.9 m，单跑 24 条 /
## 7936.7 m，本批就是这么抓到的）。生产侧由 `WorldSession.boot()` 负责同一件事，
## 见 `scripts/world/world_session.gd`、`ENGINEERING.md` §9.8.5 与 §5 陷阱 26。
## S1.2c：战略镜头。四组断言 —— 档位契约、600 帧轨迹（无 NaN / 不越界 / 帧间连续 /
## 不入地）、决定论（同脚本逐位一致 + 反向对照）、场景接线（相机 current + 固定正午）。
func _case_strategic_camera() -> void:
	var rng: Node = get_root().get_node("Rng")
	rng.call("seed_from", 20250929)
	var s := WorldSession.boot(rng, 20250929)
	ok(s.ok, "前置：世界建成（镜头要读高度场）")

	section("档位契约：2600 / 700 / 170 m，GLOBAL 锁正交等距且焦点锁中心")
	var c0 := StrategicCamera.new()
	c0.setup(s.field)
	var rep := c0.report()
	eq(int(rep["tier"]), 0, "初始档 = GLOBAL")
	near(float(rep["size"]), 2600.0, 0.001, "全球档垂直跨度 2600 m（2400 m 图 + 边距）")
	eq(String(rep["projection"]), "ORTHO", "全球档固定正交")
	near(float(rep["yaw_deg"]), 45.0, 0.001, "全球档 yaw = 45°（等距）")
	near(float(rep["pitch_deg"]), -35.264, 0.01, "全球档 pitch = −35.264°")
	near(float(rep["bounds_half"]), 0.0, 0.001, "全球档焦点锁中心（视野比地图大，不允许漂到空白里）")
	ok(bool(rep["current"]), "相机是 current（否则视口还是黑的）")
	ge(float(rep["far"]), 2500.0, "far 覆盖整图（%.0f m）" % float(rep["far"]))
	near(float(rep["camera_y"]), 146.0 + 0.0, 4000.0, "相机在地图上方（y = %.1f）" % float(rep["camera_y"]))
	c0.set_tier(1)
	near(float(c0.report()["size_target"]), 700.0, 0.001, "区域档跨度 700 m")
	c0.set_tier(2)
	near(float(c0.report()["size_target"]), 170.0, 0.001, "近地档跨度 170 m")
	c0.set_tier(0)
	c0.toggle_projection()
	eq(String(c0.report()["projection"]), "ORTHO", "GLOBAL 档拒绝切透视（整图必须正交）")
	c0.set_tier(1)
	c0.toggle_projection()
	eq(String(c0.report()["projection"]), "PERSP", "区域档可切透视")
	c0.toggle_projection()
	eq(String(c0.report()["projection"]), "ORTHO", "再切回正交")
	# 焦点一旦离开中心，切回全球档必须被拉回边界内（否则整图会偏心）
	c0.set_tier(1)
	for i in 90:
		c0.step(1.0 / 60.0, Vector2(1, 0))
	ok(absf(c0.focus.x) > 0.5, "区域档确实能平移（x = %.2f）" % c0.focus.x)
	c0.set_tier(0)
	near(c0.focus.x, c0.report()["bounds_half"], 0.01, "切回全球档后焦点被钳回中心（x = %.2f）" % c0.focus.x)
	c0.free()

	section("600 帧轨迹：右移 → 第 200 帧进区域档 → 第 400 帧转 yaw")
	var cam := StrategicCamera.new()
	cam.setup(s.field)
	var dt := 1.0 / 60.0
	var bad_nan := 0
	var bad_bounds := 0
	var bad_step := 0
	var bad_ground := 0
	var max_step := 0.0
	var prev := cam.focus
	var tiers_seen := {}
	for i in 600:
		var move := Vector2.ZERO
		var zoom := 0
		var yaw_d := 0.0
		if i < 200:
			move = Vector2(1, 0)
		elif i == 200:
			zoom = 1
			move = Vector2(1, 0)
		elif i < 400:
			move = Vector2(1, 0)
		elif i == 400:
			yaw_d = 0.02
		else:
			move = Vector2(0, 1)
		cam.step(dt, move, yaw_d, 0.0, zoom)
		var r := cam.report()
		var f: Vector3 = r["focus"]
		tiers_seen[int(r["tier"])] = true
		if is_nan(f.x) or is_nan(f.y) or is_nan(f.z) \
				or is_inf(f.x) or is_inf(f.y) or is_inf(f.z):
			bad_nan += 1
			break
		var bh := float(r["bounds_half"])
		if absf(f.x) > bh + 0.01 or absf(f.z) > bh + 0.01:
			bad_bounds += 1
		var step_len := (f - prev).length()
		max_step = maxf(max_step, step_len)
		var allow := float(r["size"]) * StrategicCamera.PAN_FACTOR * dt * 1.35 + 0.001
		if step_len > allow:
			bad_step += 1
		if float(r["camera_y"]) < float(r["ground_y"]) + StrategicCamera.GROUND_CLEAR - 0.01:
			bad_ground += 1
		prev = f
	eq(bad_nan, 0, "600 帧里没有 NaN / INF")
	eq(bad_bounds, 0, "焦点始终在 ±bounds_half 内（越界帧数 = 0）")
	eq(bad_step, 0, "帧间位移 ≤ 视野×0.35×dt×1.35（最大实测 %.4f m）" % max_step)
	eq(bad_ground, 0, "相机始终比脚下地形高 ≥ 3 m（不入地）")
	ok(max_step > 0.0, "焦点确实在动（不是卡死）")
	eq(tiers_seen.size(), 2, "轨迹里经历过 2 个档（GLOBAL → REGION）")
	eq(int(cam.report()["tier"]), 1, "结束时停在区域档")
	ok(float(cam.report()["size"]) < 2600.0, "跨度已经向 700 m 收敛（%.1f m）" % float(cam.report()["size"]))
	cam.free()

	section("决定论：同脚本两次轨迹逐位一致，反向平移不同")
	var h1 := _camera_trace_hash(s.field, 1.0)
	var h2 := _camera_trace_hash(s.field, 1.0)
	eq(h1, h2, "同一输入脚本两次轨迹哈希相同")
	var h3 := _camera_trace_hash(s.field, -1.0)
	ne(h1, h3, "反向平移得到不同轨迹（反向对照）")

	section("场景接线：相机 current + 舞台固定正午")
	rng.call("seed_from", 20250929)
	var packed := load(WORLD_SCENE) as PackedScene
	ok(packed != null, "strategic_map.tscn 可加载")
	var inst: Node = packed.instantiate()
	get_root().add_child(inst)
	await process_frame
	ok(inst.camera != null, "场景建出了 StrategicCamera")
	var cr: Dictionary = inst.camera_report()
	eq(int(cr.get("tier", -1)), 0, "场景相机从全球档起步")
	near(float(cr.get("size", 0.0)), 2600.0, 1.0, "场景相机跨度 2600 m")
	ok(bool(cr.get("current", false)), "场景相机是 current")
	ok(inst.sun != null, "场景有 Sun")
	ok(inst.environment_owner != null and inst.environment_owner.environment != null,
			"WorldEnvironment 挂了 Environment（天空与雾）")
	ok(inst.day_night != null, "场景有 DayNight")
	eq(bool(inst.day_night.auto_cycle), false, "DayNight 自动循环关闭（截图可复现）")
	near(float(inst.day_night.time_of_day), 0.5, 0.0001, "固定在正午 0.5")
	inst.queue_free()
	await process_frame


## 固定 240 帧的平移轨迹，返回量化后的轨迹哈希。档位先拨到区域档，否则全球档的
## 焦点被钳在中心、两个方向都会得到同一条（空）轨迹。
## --- s1_2_perf ---------------------------------------------------------------
## `C-`：三档帧率 ≥ 60 fps + 三角面 ≤ 34 611，并且**反向对照**必须能分辨「地图」与
## 「空天空」——量不出差别的采样器没有资格当证据。同一用例顺带验 `B-` 取景工具的
## 两个旋钮（`--seed=` / `--tier=`）真的换了世界，而不是只在日志里写一行。
func _case_strategic_perf() -> void:
	await process_frame
	section("分档帧率（vsync 关闭，逐档 2 × 0.5 s）")
	var report_path := _opt_out.path_join("perf_map_verify_perf.json")
	if FileAccess.file_exists(report_path):
		DirAccess.remove_absolute(report_path)
	ok(not FileAccess.file_exists(report_path), "旧报告先删掉（旧文件不能冒充证据）")
	var out: Array = []
	var code := _exec_godot(PackedStringArray([
		"--script", "res://tools/perf_map.gd", "--",
		"--label=verify_perf", "--out=" + _opt_out,
		"--windows=2", "--window=0.5", "--warmup=30",
	]), out)
	eq(code, 0, "perf_map 子进程退出码 = 0（三档都达标才对）")
	ok(FileAccess.file_exists(report_path), "perf_map 写出了 JSON", report_path)
	var r := _read_json(report_path)
	if r.is_empty():
		ok(false, "报告可解析", report_path)
		return
	eq(String(r.get("vsync", "")), "disabled", "采样在 vsync 关闭下进行（否则量的是显示器）")
	var tiers: Array = r.get("tiers", [])
	eq(tiers.size(), 3, "三档都采到了")
	var slowest := INF
	var global_prims := 0
	var global_draws := 0
	for row in tiers:
		var tier_name := String(row.get("tier", "?"))
		var fps := float(row.get("fps_mean", 0.0))
		slowest = minf(slowest, fps)
		ge(fps, 60.0, "%s 档平均帧率 ≥ 60 fps（实测 %.1f）" % [tier_name, fps])
		var prims := int(row.get("primitives", 0))
		if tier_name == "global":
			global_prims = prims
			global_draws = int(row.get("draw_calls", 0))
		le(float(prims), 34611.0, "%s 档三角面 %d 不超 C- 上限 34 611" % [tier_name, prims])
	eq(global_prims, 16920,
			"全球档三角面 %d = 陆面 11 250 + 水面 4 470 + 裙边 1 200（与网格统计逐个对上）" % global_prims)
	le(float(global_draws), 120.0, "全球档绘制调用 %d ≤ 120（分块没有把批次数炸掉）" % global_draws)
	var empty: Dictionary = r.get("empty", {})
	var empty_fps := float(empty.get("fps_mean", 0.0))
	ok(empty_fps > slowest * 1.5,
			"反向对照：隐藏地图后帧率 > 最慢档 × 1.5（采样器能分辨地图与空天空）",
			"empty=%.1f vs slowest=%.1f" % [empty_fps, slowest])
	eq(bool(r.get("pass", false)), true, "工具自评 pass = true")
	near(float(r.get("slowest_fps", 0.0)), slowest, 0.02, "报告里的最慢档 = 用例自己算的最慢档")

	section("B- 取景工具接线：seed / tier 两个旋钮真的换了世界")
	var state := get_root().get_node_or_null("GameState")
	var seed_before := 20250929
	if state != null:
		seed_before = int(state.get("world_seed"))
	var stage := (load("res://scenes/dev/strategic_shots.tscn") as PackedScene).instantiate()
	get_root().add_child(stage)
	await process_frame
	stage.call("build", 20250930, "local")
	var map: Variant = stage.get("map")
	ok(map != null, "取景台建出了战略图")
	if map != null:
		var session: Variant = map.get("session")
		eq(int(session.get("world_seed")) if session != null else -1, 20250930,
				"build(20250930, local) 真的换了 seed")
		var cam: Variant = map.get("camera")
		eq(int(cam.get("tier")), 2, "档位切到 LOCAL")
		near(float(cam.get("size")), 170.0, 0.01, "LOCAL 跨度 170 m")
		var f: Vector3 = cam.get("focus")
		ok(is_finite(f.x) and is_finite(f.z) and Vector2(f.x, f.z).length() > 0.0,
				"LOCAL 取景落在据点而不是地图中心", str(f))
		var old_map: Variant = map
		stage.call("build", 20250929, "global")
		ok(not is_instance_valid(old_map), "重建时旧世界被释放（不是两张地图叠着）")
		map = stage.get("map")
		var cam2: Variant = map.get("camera")
		eq(int(cam2.get("tier")), 0, "切回 GLOBAL 档")
		near(float(cam2.get("size")), 2600.0, 0.01, "GLOBAL 跨度 2600 m")
		var f2: Vector3 = cam2.get("focus")
		eq(f2, Vector3.ZERO, "GLOBAL 焦点锁地图中心")
	stage.queue_free()
	await process_frame
	if state != null:
		state.set("world_seed", seed_before)


func _camera_trace_hash(p_field: HeightField, p_sign: float) -> String:
	var c := StrategicCamera.new()
	c.setup(p_field)
	c.set_tier(1)
	var acc := ""
	for i in 240:
		c.step(1.0 / 60.0, Vector2(p_sign, 0.0))
		var f := c.focus
		acc += "%.6f,%.6f,%.6f|" % [f.x, f.y, f.z]
	c.free()
	return str(acc.hash())

func _world_fixture(p_seed: int = 20250929) -> Dictionary:
	var loaded := GenParams.load_from()
	var params := Dictionary(loaded["params"])
	var rng: Node = get_root().get_node_or_null("Rng")
	# 把子流拨回"开局状态"：`Rng.reset()` 让每条子流重新等于 (master_seed, 名字) 派生的起点。
	# 用例共享同一条 `world_gen` 子流，不拨回去的话，同一个 seed 会因为前面用例多抽了几个数
	# 而生成不同的世界（本批实测：24 条边 vs 26 条边）。
	rng.call("reset")
	var stream: RandomNumberGenerator = rng.call("stream", "world_gen")
	var field := HeightField.new(p_seed, params)
	var regions := WorldRegions.new(field, stream, params)
	regions.build()
	var anchors: Array = []
	var table := WorldData.load_anchors()
	if bool(table["ok"]):
		anchors = Array(table["anchors"])
	return {
		"params": params,
		"anchors": anchors,
		"field": field,
		"regions": regions,
		"stream": stream,
		"state": stream.state,
		"seed": p_seed,
	}


## 数组是否按给定文本字段升序排列（空数组 / 单元素视为已排序）。
func _sorted_by_field(p_items: Array, p_key: String) -> bool:
	var prev := ""
	var first := true
	for item in p_items:
		var cur := String(Dictionary(item).get(p_key, ""))
		if not first and cur < prev:
			return false
		prev = cur
		first = false
	return true


## 聚落 / 队伍的位置合法性（空结果 = 全合法）。`p_spacing > 0` 时同时查两两间距。
func _world_violations(p_list: Array, p_field: HeightField, p_spacing: float, p_limit: float) -> PackedStringArray:
	var out := PackedStringArray()
	for item in p_list:
		var who := String(item.get("id", "?"))
		var x := float(item["x"])
		var z := float(item["z"])
		if p_field.is_water(x, z):
			out.append("%s 落在水面 (%.1f, %.1f)" % [who, x, z])
		var slope := p_field.slope_at(x, z)
		if slope > p_limit:
			out.append("%s 坡度 %.3f > %.2f" % [who, slope, p_limit])
	if p_spacing > 0.0:
		for i in range(p_list.size()):
			for j in range(i + 1, p_list.size()):
				var d := Vector2(float(p_list[i]["x"]), float(p_list[i]["z"])).distance_to(
						Vector2(float(p_list[j]["x"]), float(p_list[j]["z"])))
				if d < p_spacing:
					out.append("%s-%s 间距 %.1f < %.1f" % [String(p_list[i].get("id", "?")),
							String(p_list[j].get("id", "?")), d, p_spacing])
	return out


## 道路图的连通分量数（独立于 `WorldData` 的并查集实现，按边做 BFS）。
func _graph_components(p_settlements: Array, p_roads: Array) -> int:
	var ids := PackedStringArray()
	for s in p_settlements:
		ids.append(String(s["id"]))
	var adj := {}
	for id in ids:
		adj[id] = []
	for r in p_roads:
		var a := String(r["a"])
		var b := String(r["b"])
		adj[a].append(b)
		adj[b].append(a)
	var seen := {}
	var components := 0
	for id in ids:
		if seen.has(id):
			continue
		components += 1
		var queue := [id]
		seen[id] = true
		while not queue.is_empty():
			var cur: String = queue.pop_back()
			for nxt in adj[cur]:
				if not seen.has(nxt):
					seen[nxt] = true
					queue.append(nxt)
	return components


## 锚点表与聚落表的失配条数（坐标或 kind 不同、或压根没生成都算一条）。
func _anchor_mismatches(p_settlements: Array, p_anchors: Array) -> int:
	var by_id := {}
	for s in p_settlements:
		by_id[String(s["id"])] = s
	var bad := 0
	for a in p_anchors:
		var id := String(a["id"])
		if not by_id.has(id):
			bad += 1
			continue
		var s: Dictionary = by_id[id]
		if float(s["x"]) != float(a["x"]) or float(s["z"]) != float(a["z"]) \
				or String(s["kind"]) != String(a["kind"]):
			bad += 1
	return bad


## 造一份「默认值 + schema + 一个改动字段」的表，供上面的参数校验用。
func _with(field: Variant, value: Variant) -> Dictionary:
	var raw := GenParams.defaults()
	raw["schema"] = GenParams.SCHEMA
	raw[field] = value
	return raw


## =============================================================================
##  其它
## =============================================================================
func _print_cases() -> void:
	print("[verify] 可用用例（kind=headed 需去掉 --headless 运行）：")
	for id in CASES.keys():
		var m: Dictionary = CASES[id]
		var flags: Array = [m.get("kind", "pure")]
		if m.get("hidden", false):
			flags.append("hidden")
		print("  %-18s [%s]  %s" % [id, ", ".join(PackedStringArray(flags)), m.get("desc", "")])
	print("[verify] 共 %d 个（--all 会跳过 hidden）" % CASES.size())

## S1.3a：队伍棋子本体。断言分五组 —— 结构预算、描边契约、贴地、朝向、决定论。
## 贴地是这一批的 A- 项：棋子必须把脚底压在地图任意一点的高度上，所以用 100 个定种子
## 采样点量**最大**偏差，而不是挑一块平地量一次。描边契约单列一组，因为本批发现
## `MeshUtil` 的生成器把面法线写进切线槽会让反向外壳炸成散三角片（正常线宽下描边
## 完全不可见）；`smooth_verts` 就是这条修复的可读证据。
func _case_party_marker() -> void:
	var rng: Node = get_root().get_node("Rng")
	rng.call("seed_from", 20250929)
	var s := WorldSession.boot(rng, 20250929)
	ok(s.ok, "前置：世界建成（棋子要读高度场）")

	section("结构：零件合成单一 mesh、标称 22 m、脚底落在 y=0")
	var marker := PartyMarker.new()
	marker.setup(s.field)
	var mt := marker.metrics()
	eq(int(mt["surfaces"]), 1, "单一 surface（1 个 draw call）")
	ok(float(mt["min_y"]) > -0.02 and float(mt["min_y"]) < 0.02,
			"脚底正好在模型原点平面（min_y=%.4f m）" % float(mt["min_y"]))
	ok(absf(float(mt["height"]) - PartyMarker.NOMINAL_HEIGHT) < 0.6,
			"标称高度 22 m（实测 %.2f m）" % float(mt["height"]))
	ge(float(mt["tris"]), 96.0, "三角数 %d ≥ 96" % int(mt["tris"]))
	le(float(mt["tris"]), 3000.0, "三角数 %d ≤ 3000（低多边形预算）" % int(mt["tris"]))
	le(float(mt["verts"]), 9000.0, "顶点数 %d ≤ 9000（单 draw call 上限）" % int(mt["verts"]))
	var size: Vector3 = mt["size"]
	ok(float(size.x) < 12.0 and float(size.z) < 12.0,
			"占地上限：横向 %.2f × %.2f m 塞得进一个聚落广场" % [float(size.x), float(size.z)])
	ge(float(size.x), 4.0, "横向 %.2f m 不小于底座直径的量级" % float(size.x))

	section("描边契约：反向外壳挂在 next_pass，切线槽写的是平滑法线")
	ok(bool(mt["outline"]), "next_pass = outline.gdshader 且 enabled=1（描边真的会画）")
	ge(float(mt["smooth_verts"]), 30.0,
			"切线槽写入平滑法线：%d 个顶点与面法线不同（否则外壳炸成散片，描边不可见）"
			% int(mt["smooth_verts"]))
	le(float(mt["smooth_verts"]), float(mt["verts"]),
			"平滑顶点数不超过总顶点数")

	# 贴地由两件事共同保证：①模型自己的脚底就在原点平面（上面 min_y≈0 已断言），
	# ②place_at() 把 position.y 设成 height_at()。所以这里量的是"落点高度恒等于高度场"
	# 而不是两条独立来源的一致性 —— 说清楚它证的是哪一半，别把恒等式当成实测。
	section("贴地：100 个定种子采样点，落点高度 ≡ height_at（配合 min_y=0 才算贴地）")
	var pick := RandomNumberGenerator.new()
	pick.seed = 20251021
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var above := 0
	var below := 0
	for i in 100:
		var x := pick.randf_range(-1000.0, 1000.0)
		var z := pick.randf_range(-1000.0, 1000.0)
		var at := marker.place_at(x, z)
		var d := at.y - float(s.field.height_at(x, z))
		if d > 0.0:
			above += 1
		else:
			below += 1
		if absf(d) > worst:
			worst = absf(d)
			worst_at = Vector2(x, z)
	ok(worst < 0.05, "最大偏差 %.5f m（100 点，最差点 %s）" % [worst, str(worst_at)])
	near(float(mt["min_y"]), 0.0, 0.0001, "配套前提：模型脚底 min_y = 0（否则落点高度不等于脚底）")
	eq(above + below, 100, "每个采样点都算过一次")
	ok(above > 0 and below > 0,
			"偏差有正有负（%d 高 / %d 低），不是一路向上抬" % [above, below])
	var here := marker.place_at(120.0, -80.0)
	near(here.y, float(s.field.height_at(120.0, -80.0)), 0.05,
			"指定点 (120, -80) 的落点高度")
	near(here.x, 120.0, 0.0001, "落点 x 不被改写")
	near(here.z, -80.0, 0.0001, "落点 z 不被改写")

	section("朝向：四方向 + ±π 回绕，facing 落在 (−π, π]")
	near(marker.face_towards(Vector3(1, 0, 0)), PI * 0.5, 0.0001, "+X → +90°")
	near(marker.face_towards(Vector3(-1, 0, 0)), -PI * 0.5, 0.0001, "−X → −90°")
	near(absf(marker.face_towards(Vector3(0, 0, -1))), PI, 0.0001, "−Z → ±180°（回绕点）")
	near(marker.face_towards(Vector3(0, 0, 1)), 0.0, 0.0001, "+Z → 0°")
	var diag := marker.face_towards(Vector3(1, 0, -1))
	near(diag, PI * 0.75, 0.0001, "+X−Z → +135°")
	ok(marker.facing > -PI - 0.000001 and marker.facing <= PI + 0.000001,
			"facing 落在 (−π, π]：%.6f" % marker.facing)
	near(marker.face_to_point(Vector3(0.0, 0.0, 0.0)), marker.facing, 0.0001,
			"face_to_point 与 face_towards 同源")

	section("阵营：4 个阵营都能换色，且不重建几何（换色只改顶点色）")
	var keys := PartyMarker.FACTION_KEYS.size()
	eq(keys, 4, "阵营表 4 项")
	var v0 := int(mt["verts"])
	for f in keys:
		marker.set_faction(f)
		eq(int(marker.metrics()["faction"]), f, "阵营 %d 生效" % f)
	eq(int(marker.metrics()["verts"]), v0, "换色不改变顶点数")
	marker.set_faction(1)

	section("决定论：同参数两次构建完全一致")
	var twin := PartyMarker.new()
	twin.setup(s.field)
	var mt2 := twin.metrics()
	eq(int(mt2["verts"]), int(mt["verts"]), "顶点数一致")
	eq(int(mt2["tris"]), int(mt["tris"]), "三角数一致")
	near(float(mt2["height"]), float(mt["height"]), 0.0001, "高度一致")
	near(float(mt2["min_y"]), float(mt["min_y"]), 0.0001, "脚底一致")
	eq(int(mt2["smooth_verts"]), int(mt["smooth_verts"]), "平滑顶点数一致")
	twin.free()
	marker.free()
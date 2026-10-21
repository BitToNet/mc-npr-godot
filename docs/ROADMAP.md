# Pocket Sandbox 玩法扩展规划（ROADMAP）

> **文档版本**：v2.8 · 2026-10-20（版本变更一律登记在 §16）
> **状态**：执行中 · M0 全部闭环（S0.1–S0.6 已验收）；**M1 进行中**（**S1.0 已完工**：S1.0a/b/c/d 全部 ✅；**S1.1 数据层已验收**：批 1–4 全 ✅；`B-` 俯视图并入 S1.2；**S1.2 进行中**：批 1 ✅ 已验收 2026-10-20）
> **性质**：本文是本项目玩法扩展的**唯一计划来源与验收台账**（single source of truth）。
> 实现过程中的任何偏差、新增、删减，必须先回到本文更新，再动代码。
> **目标定位**：中型商用游戏项目（Windows 桌面）。

---

## 0. 怎么用这份文档（执行协议）

### 0.1 每一步的执行闭环（五步，缺一不可）

| 阶段 | 谁做 | 产出 |
|---|---|---|
| ① 细节对齐 | 我先列出该步的「实现细节待确认清单」，**你确认后**才动代码 | 对齐记录（追加到本文该步下方） |
| ② 实现 | 我只改该步范围内的文件 | 代码 + 交付物清单 |
| ③ 验收 | 我提交**验收证据**（命令输出 / 截图 / 数据断言），你判定 | 验收证据链接或路径 |
| ④ 标注 | **验收通过后**，才在 §15 台账把状态改为 `✅ 已验收` | 台账更新 + 日期 |
| ⑤ 提交推送 | **④ 完成后立即** `git commit` + `git push origin main` | 提交哈希 + 详细提交信息 |

未通过 → 记录失败原因 → 修正 → 重新验收；状态回退为 `🔁 返工中`，**不得**直接改回已完成。

**第 ⑤ 步细则**（强制定于 `AGENTS.md`【二、版本控制与提交推送规范】）：

- **两个必做节点**：阶段性修改验收通过后、单块功能完成后，各做一次提交与推送，不得合并拖延。
- **提交信息**必须含四段：`背景 / 为什么`、`改动内容`、`验收与验证`（含本步 A-/B-/C-/D- 各项通过情况与本步编号）、`影响与风险`；禁止一句话敷衍。
- **推送前**仓库必须可运行（`--headless` 启动主场景无 `ERROR` / `SCRIPT ERROR`）。
- 提交哈希与验收证据路径一并回填到 §15 台账「验收证据」列。

### 0.2 计划外功能的处理（硬性）

- 实现某一步时若需要**计划外的功能 / 资源 / 第三方依赖 / 目录结构变更**：
  **先停下来向你核实**，得到批准后 → 先更新本文（含验收标准）→ 再实现。
- 不允许「顺手做了」「先做着后面再补文档」。未登记的改动一律视为未完成。

### 0.3 验收标准的分级（本文所有验收项都带类型前缀）

| 前缀 | 类型 | 定义 | 是否可自动 |
|---|---|---|---|
| `A-` | 自动化断言 | headless 运行 verify 用例，退出码 0 且断言全绿 | ✅ 可自动 |
| `C-` | 数据/性能 | 数值、耗时、FPS、内存等可测量指标落在阈值内 | ✅ 可自动 |
| `B-` | 视觉证据 | `capture.gd` 出图 PNG，人工比对构图/风格/一致性 | ⚠️ 半自动 |
| `D-` | 主观手感 | 必须你**实机试玩**签字，不可自动化 | ❌ 人工 |

**规则**：任何一步的通过条件是「该步列出的全部验收项都通过」，`B-`/`D-` 缺一不可（战斗手感类步骤必须含 `D-`）。

### 0.4 台账更新规则

§15 台账每步记录：状态 / 验收日期 / 证据路径 / 偏差说明。状态取值只有五个：
`⏳ 未开始` `🚧 进行中` `🧪 待验收` `🔁 返工中` `✅ 已验收`。

### 0.5 变更控制

本文任何结构性变更（新增里程碑、调整顺序、改验收线）都记入 §16 变更日志，含日期、变更内容、原因、批准人。

---

## 1. 目标与已对齐决策

### 1.1 项目目标

在现有 NPR 微缩沙盘演示的基础上，扩展为一款**中型商用**游戏：

- **大地图**：类似《骑马与砍杀：战团》的沙盒战略层（时间推进、聚落、势力、AI 队伍、遭遇）。
- **战斗**：两条战斗线 —— **Boss 战**（横版 1v1 PK，黑神话/只狼式）与 **军团作战**（上帝视角指挥）。

### 1.2 已对齐的四项关键决策（2026-10-16 与用户确认）

| # | 决策项 | 结论 |
|---|---|---|
| D1 | 大地图形态 | **战略地图 + 独立战斗场景**：俯视微缩战略图上以「队伍棋子」移动，时间/遭遇触发后切入独立战斗场景，战斗结束回流战略层 |
| D2 | 阶段顺序 | **大地图 → Boss 战 → 装备系统 → 军团作战 → 兵团升级** |
| D3 | 战斗内核基线 | **横版 2.5D 专用战斗内核**：Boss 战锁 X/Y 平面、Z 仅作纵深演出；帧数据驱动（起手/判定/后摇/取消窗口）；命中用 `Area3D`。大地图与军团战沿用现有解析高度场方案 |
| D4 | 军团作战形态 | **小队编队指挥，60–120 单位**：玩家指挥 3–6 个小队（每队 10–20 人），核心是选队/移动/接敌/阵型/士气；`MultiMesh` + 轻量群体 AI |

### 1.3 核心玩法支柱（Boss 战，来自你的原话，逐条落实为可验收机制）

> 核心是弹反、闪避、蓄力技能等。弹反可续普攻，触发反击斩；闪避可触发提前蓄力；
> 蓄力可触发一些特殊攻击效果，如远程剑气、霸体连招等。

| 支柱 | 机制设计（初稿，见 §12 数值表） | 落在哪一步 |
|---|---|---|
| 弹反 | 起手极短帧内招架 = 完美弹反 → 对手硬直 + 允许普攻续接 → 触发**反击斩** | S2.4 |
| 闪避 | 无敌帧 + 位移；蓄力中闪避可**保留并提前蓄力等级** | S2.5 |
| 蓄力 | 3 级：强化普攻 / **霸体连招** / **远程剑气** | S2.6 |
| 反应链 | 弹反 ↔ 闪避 ↔ 蓄力三者互为取消与奖励路径，构成「攻防转换循环」 | S2.2 / S2.11 |

### 1.4 明确的非目标（本期不做，除非你另行批准）

- 不做**无缝开放大世界**（已选 D1 战略地图路线）。
- 不做方块/体素化地形（**永久禁止**，见 §3.1）。
- 不做写实 PBR 贴图/材质（与美术规范冲突）。
- 不做多人联机（本文全部假设单机）。
- 不做移动端/主机移植（目标平台 Windows 桌面）。

---

## 2. 现状盘点

### 2.1 已实现能力（可直接复用）

| 能力 | 位置 | 可复用性 |
|---|---|---|
| 程序化 NPR 岛屿地形（63m 见方、104×104 网格、面着色 + 逆壳描边） | `scripts/world/terrain.gd` | ★★★ 战略地图地形直接沿用同一套噪声与配色管线 |
| 全局美术中枢（调色板 / toon 材质工厂 / 3 阶渐变 ramp / 描边开关 / 像素级墨线宽度） | `scripts/core/style.gd` | ★★★ 所有新内容必须走它 |
| 低模几何工具库（`facet` 面着色、`combine`、`roughen`、`blob/cone/tapered_cylinder/superellipse_prism`） | `scripts/core/mesh_util.gd` | ★★★ 角色、Boss、单位、装备图标全部由它构建 |
| 角色运动（解析高度场绑定、加减速、跳跃、squash & stretch、姿态动画） | `scripts/actors/player.gd` | ★★☆ 军阀棋子 / 军团单位姿态可参考 |
| 正交等距相机（FOLLOW/ORBIT/FREE + 阻尼跟随 + 镜头属性） | `scripts/core/camera_rig.gd` | ★★☆ 战略层可扩为多档缩放；Boss 战需**另建**横版相机 |
| 昼夜系统（关键帧插值、太阳方位、天空/环境联动） | `scripts/world/day_night.gd` | ★★★ 直接接全局游戏时间 |
| 植被/道具散布（噪声生态 + `MultiMesh` 实例化 + 逐实例自定义数据） | `scripts/world/scatter.gd` | ★★★ 军团作战**单位实例化**的性能架构范本 |
| 水体（顶点色烘焙深度/泡沫 + 半透明 sheet） | `scripts/world/water.gd` | ★★☆ 战略层沿用 |
| 云层场 | `scripts/world/clouds.gd` | ★☆☆ |
| UI 语言（neo-brutalist：粗墨边、硬阴影、纯色块、方形滑块） | `scripts/ui/ui_panel.gd`、`scripts/ui/ui_slider.gd` | ★★★ 全部新 UI 必须延续 |
| 运行时输入映射 | `scripts/core/input_setup.gd` | ★★★ 扩展为战斗/指挥两套 binding |
| 截图与性能工具（`--shots` / `--shot=` / `--bench`） | `scripts/core/capture.gd` | ★★★ 验收工具链的起点 |
| 离线诊断脚本（`extends SceneTree` 模式） | `tools/diag.gd`、`tools/probe.gd`、`tools/analyze.gd`、`tools/windtest.gd` | ★★★ `tools/verify.gd` 的写法范本 |

### 2.2 关键既有 API（新系统依赖的契约，改动需评估影响面）

```
Terrain.instance.height_at(x, z) -> float      # 地表高度（渲染面精确一致）
Terrain.instance.normal_at(x, z) -> Vector3    # 地表法线
Terrain.instance.slope_at(x, z) -> float
Terrain.instance.spawn_point -> Vector3
Terrain.instance.generate(seed)                # 全量重建
Style.pal(key) / Style.toon(opts) / Style.water_material()
Style.set_outline(on) / Style.set_pixel_span(v) / Style.build_ramp(bands)
MeshUtil.facet / combine / roughen / blob / cone / tapered_cylinder / superellipse_prism
Main.rebuild(seed)                             # 世界重建入口
节点组：#main #player #camera_rig #terrain #water #day_night
```

### 2.3 缺口清单（本规划要补的东西）

- ❌ 无数据层（无任何游戏数据资源、无存档）
- ❌ 无场景管理（只有单一 `scenes/main.tscn`；无切换、无加载过渡）
- ❌ 无全局状态/事件总线（靠 `@onready` 硬连线）
- ❌ 无物理/碰撞（`Player` 是纯 `Node3D`，手写运动；无 `Area3D`/射线）
- ❌ 无战斗（状态机、帧数据、命中判定、伤害、AI 全部为零）
- ❌ 无敌人/单位/AI
- ❌ 无装备/背包/属性管线
- ❌ 无经济/时间日历/任务
- ❌ 无验收工具链（只有人工截图与 bench）
- ❌ 无工程规范文档（本仓库只有美术规范 `AGENTS.md`）

---

## 3. 全局技术约定（所有步骤共同遵守）

### 3.1 美术规范（强制，来自 `AGENTS.md`，不可折中）

1. **禁止立方体/方块/像素块/体素**：所有形体必须是平滑低模（球、胶囊、锥、渐细柱、超椭圆棱柱）。新增内容继承此约束，含幕布、栅栏、箱体、旗帜等"看起来像方块"的东西。
2. **面着色**：新网格一律经 `MeshUtil.facet()` 或 `from_faces()` 产出平法线面着色。
3. **Toon 管线**：新材质一律经 `Style.toon()`，绑定渐变 ramp（默认 3 阶），禁止使用标准 `StandardMaterial3D` 光照明暗。
4. **逆壳描边**：所有重要物体（地形、植被、角色、单位、Boss、道具）必须有反向外壳墨线。
5. **高饱和纯色调色板**：新颜色必须注册进 `Style.PALETTE`，禁止出现写实/低饱和脏色。
6. **正交 + 硬阴影**：光照沿用现有 `DirectionalLight3D`（PCF 硬阴影）+ 柔和环境光。
7. **Godot 落地说明**：原规范中 `MeshToonMaterial`/`PlaneGeometry`/`toNonIndexed`/`OrthographicCamera` 的 Three.js 术语，在本项目的 Godot 等价实现是：`toon.gdshader` + 渐变 ramp / `SurfaceTool` 程序化网格 / `MeshUtil.facet()` / `Camera3D.PROJECTION_ORTHOGONAL`。**等价映射已建立，不重新选型。**
8. **规范守卫**：`tools/verify.gd` 内置静态检查，禁止新增 `BoxMesh` / `CSGBox3D` / `StandardMaterial3D`（白名单外），违例直接验收失败。

### 3.2 工程约定

- **目录结构**（S0.1 落地）：
  ```
  scenes/    world/  battle/  ui/  dev/
  scripts/   core/   world/   actors/  battle/  legion/  data/  ui/  fx/  dev/
  shaders/   common/  terrain/  character/  fx/
  data/      units/  weapons/  frames/  world/  economy/     (资源与表)
  tools/     verify cases + 离线脚本
  docs/      本文 + 工程/美术/平衡文档
  .shots/    .verify/                        (产物，不进版本库)
  ```
- **逻辑固定步长 60Hz**：战斗帧数据以 60 FPS 为基准，逻辑与表现分离。
- **数据驱动**：招式帧表、兵种、武器、装备、经济参数、聚落模板一律走资源/JSON 表；代码里不硬编码数值。
- **可复现随机**：所有随机走 `Rng` 服务（按 seed 派生子流），禁止裸 `randf()`（verify 静态检查）。
  S0.3 已将其落为 autoload `Rng`（`scripts/core/rng.gd`）；既有 `terrain.gd` / `scatter.gd` 的裸 `randi()`
  仍在守卫白名单内（收编会改变随机序列 ⇒ 画面变化，故留到 M1 S1.1 与地形重构一起做）。
- **Autoload 上限 10 个**（2026-10-16 由 6 放宽，理由与批准见 §16）：`Style` `Capture` `Clock`（既有）
  + `GameState` `EventBus` `Rng` `SaveSystem` `SceneRouter`（S0.3 新增）+ `Debug`（S0.4 新增），**合计 9**；余量 1 个留给 M1–M6。超出需你批准。
  进度：**当前 9 / 10**（S0.5 复核更正，此前此处写"合计 8 / 当前 6"是过期数字）。
  注册顺序约束：`Rng` 先于 `GameState`、`SaveSystem` 在 `GameState` 之后、`Debug` 在 `SceneRouter` 之后，
  三条均由 `s0_3_state` 断言。
- **信号命名**（S0.5 按实际代码更正）：`*_pressed`（按钮）/ `xxx_changed`（状态）/ `xxx_requested`（请求）；
  全局事件总线上的**"已发生事实"信号**用过去式 `<subject>_<past_participle>`
  （`time_advanced` / `encounter_started` / `battle_finished` / `settlement_entered`，S0.3 登记）。
  > 原规则写的是 `on_xxx`（按钮），与既有 7 处实现不符（`ui_panel.gd` 的 `regenerate_pressed`
  > `outline_pressed` `bands_pressed` `camera_pressed` `autocycle_pressed`、`save_grid.gd` 的
  > `slot_pressed`、`debug_layer.gd` 的 `overlay_toggled`）。S0.5 对齐时决定**改规则不改代码**：
  > `*_pressed` 是 Godot 生态的既有惯例（`BaseButton.pressed`），改名会让 7 处信号与它们的
  > 连接点同时变动却换不来任何行为收益。完整清单与判定口径见 `docs/ENGINEERING.md` §7。
- **节点组**：沿用 `#main #player #camera_rig #terrain #water #day_night`；新增 `#overworld #battle #legion` 等。
- **既有文件不重写**：新系统包在外围；确需改动既有文件时，在该步交付物中显式列出并说明原因。

### 3.3 性能红线（所有 C- 类验收的公共基线）

| 场景 | 红线 |
|---|---|
| 基准分辨率/配置 | 1600×900，MSAA 2x，沿用现有 `project.godot` 渲染设置 |
| 战略层（全球缩放档） | ≥ 60 FPS；24 支 AI 队伍 |
| Boss 战（1v1） | ≥ 60 FPS；帧时间 < 16.7ms |
| 军团战（120 单位满编） | ≥ 60 FPS |
| 卡顿 | 60 秒采样内单帧 > 33ms 的次数 ≤ 1 |
| 内存 | 场景切换后回落到基线 ±5%；20 分钟游玩进程内存漂移 < 5% |
| 生成/切场景 | 世界生成 < 800ms；进出战斗 < 1.2s |

### 3.4 验收工具链（S0.2 建于 2026-10-16，全程使用）

以下命令均已**实机跑通**（S0.2 验收证据见 §15 台账）：

```powershell
$GODOT  = "G:\godot_project\_godotengine\Godot_v4.7-stable_win64_console.exe"
$GODOTG = "G:\godot_project\_godotengine\Godot_v4.7-stable_win64.exe"
$P      = "G:\godot_project\mc-npr-godot"

# A- / C- 类：全部断言用例（headless；C- 类用例自动跳过并记原因）退出码 0 = 全绿
& $GODOT --headless --path $P --script res://tools/verify.gd -- --all

# A- / C- 类：含 C- 类性能用例时**必须去掉 --headless**（headless 无渲染指标）
& $GODOT --path $P --script res://tools/verify.gd -- --all

# 单用例  /  列出全部用例
& $GODOT --headless --path $P --script res://tools/verify.gd -- --case=<case_id>
& $GODOT --headless --path $P --script res://tools/verify.gd -- --list

# C- 类：性能基线（四项指标 + 是否落盘；窗口模式）
& $GODOT --path $P --script res://tools/baseline.gd -- --label=main

# B- 类：视觉证据截图（必须显式给 --shots/--shot=/--capture 才会触发）
& $GODOTG --path $P -- --shots --case=<batch> --warmup=60 --frames=15 --out=res://.shots
& $GODOTG --path $P -- --shot=<name> --time=0.5 --mode=FOLLOW --size=36 --out=res://.shots

# B- 类：指定**参数化夹具场景**取景（S0.5 起；把场景路径位置参数化传入，
# 不经过 SceneRouter，因此不违反 scene_change_owner 守卫）
& $GODOTG --path $P res://scenes/dev/art_samples.tscn -- --shots --case=s0_5_samples --warmup=60 --frames=15 --out=res://.shots/s05

# B- 类：把正交相机对准一个绝对世界坐标（S0.5 起，`--at="x,y,z"`；
# 参数化夹具要在同一批里逐张换主体时用它，见 docs/ART_PIPELINE.md §2）
& $GODOTG --path $P -- --shot=<name> --at="-45,1.75,0" --size=5.4 --yaw=38 --out=res://.shots

# B- 类：指定场景取景（S1.0b 起；缺省仍取 project.godot 的 run/main_scene）
& $GODOTG --path $P -- --shots --case=<batch> --scene=res://scenes/dev/diorama.tscn --out=res://.shots

# B- 类：图像比对（退出码 0=在容差内 / 1=超容差或尺寸不一致 / 2=用法错误）
& $GODOT --headless --path $P --script res://tools/img_diff.gd -- --a=<png> --b=<png> [--tol=0.001]
```

**取证约定**

- 所有报告落 `res://.verify/`（已入 `.gitignore`）；截图与截图清单落 `res://.shots/`。
- `capture.gd` 每批截图额外产出 `<out>/<case>.json` 清单（每张图的尺寸 + sha256 + 相机参数），
  供 `B-` 证据链锚定。
- ⚠️ **`--case=` / `--out=` 是 verify 与 capture 共用的参数名**。为免验收运行器顺带触发一次截图批次
  （其 `quit(1)` 会覆盖运行器退出码），`capture.gd` 只在显式给出
  `--shots` / `--shot=` / `--capture` / `--bench` 时才工作，`--case=` / `--out=` / `--frames=` / `--warmup=`
  只作修饰符。
- ⚠️ **`B-` 阈值与 S0.6 的关系**：实测同参数、同构建的两次独立渲染差异原为 **1.62%–5.67%**
  （水波/风摆用内建 `TIME`、`scripts/clouds.gd` 直接读 `Time.get_ticks_msec()`，均不可冻结），
  即当时工程**字节层面不存在可复现帧**。Q13 已裁定选 (c)：改动画时钟为可注入 `u_time`，
  落地为 **S0.6**。⇒ **S0.6 完成前，任何 `B-` 项都不得判为通过**。
- ✅ **S0.6 已验收（2026-10-16）**：确定性模式下两个独立进程同参数截图实测
  **0 像素差异 / `img_diff` 0.0000% / sha256 逐位相同**。因此**自本步起 `B-` 一律按逐位一致判定**
  （比原定 `< 0.1%` 更严）；截图批次默认走确定性时钟，`--realtime` 仅用于 `D-` 类人工试玩。
  `B-` 的取证命令统一为 `tools/verify.gd --case=s0_6_repro` 的 `s0_6_repro` 口径（含反向对照）。

### 3.5 存档与菜单规范（用户 2026-10-16 裁定，所有涉及存档的步骤共同遵守）

> 决策来源：**Q10 结案**（见 §14）。本节是该决策的落地契约，**S0.3 / S1.9 / S3.6 / S5.6 / S6.3 均引用本节**；
> 与本节冲突的实现一律以本节为准，需要偏离时按 §0.2 先核实、先改本文。

**槽位与页面布局**

- 存档槽位**固定 9 个**，以**3×3 九宫格单页**呈现；不做滚动列表、不做分页、不做超过 9 槽的扩展。
- 主菜单的「继续 / 读取」与游戏内菜单页**复用同一个宫格组件**（同一份渲染与交互实现）。
- 空槽显示为「空槽位」，**不可读取**；不存在的内容不可删除。

**触发路径（唯一入口）**

- 游戏中按 `ESC` 打开菜单页 → 点击「**保存**」写入**当前槽**（无当前槽时等同「另存为」）；
  点击「**另存为**」→ 在宫格中选择目标槽后写入。
- **禁止自动存档**：任何时刻（进入战斗、离开战斗、切换场景、退出游戏、时间推进节点、任务结算）
  都**不得**静默写盘。写盘只由玩家显式点击「保存 / 另存为」（或等价的手动菜单项）触发。
- 退出游戏时若存在未保存进度，必须给出明确提示；不阻塞退出，但**不得静默丢弃**。
- **不做云同步**（Q10 同时裁定）。

**槽位卡片信息（每个非空槽显示）**

- 槽号；真实时间（写入时刻）；游戏内日期与时间；玩家队伍名与等级；累计游戏时长。
- 缩略图**可选**：若实现，须走 `B-` 视觉证据；不实现不影响任何步骤的验收通过。

**写入安全**

- 覆盖已有槽必须**二次确认**，且确认框需明确显示将被覆盖的槽号与写入时间。
- 写盘失败（磁盘满 / 无权限 / 路径不可写）**不得静默**：必须显示失败原因，并保持原存档不变
  （原子写入，禁止半截文件）。
- 「禁止半截文件」的**实测口径**（2026-10-16，批次 2，用例 `s0_3_atomic`）：引擎在 Windows 上的
  `rename` 覆盖是"**先删目标再改名**"、**不是**原子替换 —— 并发读者会撞上极短的"文件不存在"或
  "文件在但读不出来"瞬间（170 个样本里 17 + 22 次），因此**只靠写者做不到原子**。契约按此收窄：
  ①**任何时刻读得出来的内容必须是完整合法 JSON**（实测 131/131，无一次半截）；
  ②读者侧用**有界重试**吸收该窗口（实测并发读失败 42 → 0），空槽位（无同名 `.tmp`）不重试、不拖慢
  九宫格渲染；③写者失败时原档逐位不变、不留 `.tmp`。详见 §5 S0.3 陷阱 2 与
  `docs/ENGINEERING.md` §5 陷阱 6。

**与调试快捷键的关系**

- `F5` 快存 / `F9` 快读（见 S0.4）**仅存在于 Debug 构建**，且**不允许**绕过本节规则：
  仍写入 9 个槽位之一，**不得**新增隐藏槽位或旁路存档文件；发布构建必须完全禁用（S6.6 已断言）。
- 「覆盖已占用槽位必须二次确认」这一条对 `F5` 同样成立，只是**确认形式不同**：菜单里是弹窗，
  `F5` 是**再按一次 `F5`**（第一次只登记待确认、不写盘，120 帧窗口内再按才覆盖）。
  不弹菜单不等于不确认；`s0_4_quick` 用"第一次按完旧档 sha256 逐位不变"来守住这一点。

---

## 4. 里程碑总览与依赖

| 里程碑 | 名称 | 步骤数 | 规模 | 关键产出 | 依赖 |
|---|---|---|---|---|---|
| **M0** | 工程基础与验收管线 | 6 | M | 目录规范、verify 工具链、可复现渲染时钟、4 个核心单例、调试层 | — |
| **M1** | **大地图（战略层）** ← 最高优先 | **11** | L | 场景与路由迁移、世界数据、战略地图、棋子移动、时间、聚落、遭遇、经济、任务、存档 | M0 |
| **M2** | **Boss 战（横版 1v1）** | 11 | L | 战斗内核（帧数据）、弹反/闪避/蓄力、Boss AI、表现与 UI、结算 | M1 |
| **M3** | 装备系统 | 6 | M | 装备数据/属性管线/背包/强化/战斗绑定 | M2 |
| **M4** | 军团作战（上帝视角） | 9 | L | 战场、单位与小队、实例化渲染、阵型、指挥、结算 | M1（复用 M2 的单挑通道） |
| **M5** | 兵团升级系统 | 6 | M | 兵种升级树、招募训练、编成与带兵上限、大地图联动 | M4 |
| **M6** | 整合与商用打磨 | 6 | M | 完整循环、新手引导、设置与本地化、性能回归、内容管线、导出 | M1–M5 |

**关键路径**：M0 → **S1.0** → M1 其余 → M2 → M3 → M4 → M5 → M6（按 D2 串行）。

**排期裁定（2026-10-19）**：走**路线 B（按里程碑顺序，即上表顺序）**，**不设硬期限**，按里程碑出口把关。
- 理由与备选方案（路线 A 竖切片优先 / 路线 C 战斗优先）见 `docs/spec.md` §2.2；V0 竖切片降为**应急方案**，仅在
  「M1 出口 `D-` 四问 ≥2 个否 / 连续 3 步超估算 50% / 你要求提前看战斗」时重新讨论。
- 两个"能玩"节点：**M1 出口（约第 7 周，战略层单独可玩）**、**M2 出口（约第 15 周，战斗接入）**。
- 人日估算（±30%，单人 + AI，不含美术外包）：M0 收尾 4 / S1.0 2 / M1 31 / M2 40 / M3 14 / M4 30 / M5 14 / M6 20 ≈ **155 人日 ≈ 31 周**。
  此数用于"节奏感与超支判断"，**不是交付承诺**；超支时先查估算、再按 `docs/spec.md` §2.6 砍量，不压缩验收。

**可并行提示**（需你批准才调整）：M4 的兵种/小队数据结构（S4.2）与 M2 无依赖，可提前起草以缩短 M5 的前置等待；反之 M3 与 M4 技术上互不依赖。
S2.2 帧数据内核**曾考虑**提前到 M1 中期（§13 R4），**2026-10-19 裁定不提前** —— 它会让 M1 的验收被 M2 的中间态干扰。

**粗估**：S ≈ 1 人日内，M ≈ 2–4 人日，L ≈ 5–10 人日（含验收与返工，不含美术外包）。

---

## 5. 里程碑 M0：工程基础与验收管线

> 目的：把"能扩展、能验收"的地基铺好。这一步不做任何玩法，但后续每一步都依赖它。

### S0.1 目录与工程结构重组

**计划描述**
- 把扁平 `scripts/` 重组为 §3.2 约定的分层目录；`shaders/`、`scenes/` 同步分层。
- 保持行为**零变化**：主场景、启动参数、节点组、既有公开 API 全部不变。
- 生成 `docs/ENGINEERING.md` 记录目录职责与迁移映射表（旧路径 → 新路径）。

**执行方案（2026-10-16 与本会话对齐后定稿）**

目录映射表（旧路径 → 新路径）：

| 现路径 | 新路径 | 归类理由 |
|---|---|---|
| `scripts/main.gd` | `scripts/core/main.gd` | 场景入口与编排（S1.2 再拆为世界入口） |
| `scripts/style.gd` | `scripts/core/style.gd` | 全局调色板/材质服务（autoload） |
| `scripts/capture.gd` | `scripts/core/capture.gd` | 截图服务（autoload） |
| `scripts/render_clock.gd` | `scripts/core/render_clock.gd` | 时间服务（autoload） |
| `scripts/mesh_util.gd` | `scripts/core/mesh_util.gd` | 通用网格工具，被 world/actors 共用 |
| `scripts/input_setup.gd` | `scripts/core/input_setup.gd` | 输入映射（S0.4 扩三套 binding） |
| `scripts/camera_rig.gd` | `scripts/core/camera_rig.gd` | 相机控制（S1.2 扩多档缩放） |
| `scripts/terrain.gd` | `scripts/world/terrain.gd` | 地形 |
| `scripts/water.gd` | `scripts/world/water.gd` | 水体 |
| `scripts/scatter.gd` | `scripts/world/scatter.gd` | 植被散布（S4.3 复用其 MultiMesh 范本） |
| `scripts/clouds.gd` | `scripts/world/clouds.gd` | 云 |
| `scripts/day_night.gd` | `scripts/world/day_night.gd` | 昼夜（S1.4 接日历系统） |
| `scripts/player.gd` | `scripts/actors/player.gd` | 演示角色；S1.3 棋子/战斗角色同族 |
| `scripts/ui_panel.gd` | `scripts/ui/ui_panel.gd` | 调试面板（S0.4 抽公共控件工厂） |
| `scripts/ui_slider.gd` | `scripts/ui/ui_slider.gd` | 同上 |
| `shaders/toon.gdshader` | `shaders/common/toon.gdshader` | 全局 toon 材质，地形/植被/角色共用 |
| `shaders/outline.gdshader` | `shaders/common/outline.gdshader` | 逆壳描边，全场景通用 |
| `shaders/water.gdshader` | `shaders/terrain/water.gdshader` | 仅水体使用 |
| `scenes/main.tscn` | **S1.0a 已换路径** | 现为 `scenes/dev/diorama.tscn`（内容逐字节不变）；S0.1 恪守"主场景不变"，改名留到 S1.0a 单独一步做 |

> 约定增补：`shaders/common/` 为本次新增子目录（原 §3.2 只有 `terrain/ character/ fx/`）。
> 理由：`toon.gdshader` / `outline.gdshader` 是全场景共用材质，放进 `fx/` 或 `character/` 都名不符实。
> 已同步登记 §3.2 与 §16。

迁移批次（**每批一个独立提交，每批都必须先跑校验再提交**）：

| 批次 | 移动内容 | 同批必改项 | 校验 |
|---|---|---|---|
| **0** | —（不移动任何文件） | — | 采集"后 S0.6 时代"确定性基线：`--shots`（默认 6 机位）两次独立进程 sha256 必须相同，sha256 记入 `docs/ENGINEERING.md` |
| **1** | `scripts/core/` 7 个脚本（含 3 个 autoload 与 `main.gd`） | `project.godot` 的 3 条 autoload 路径；`GUARD_WHITELIST` 中 `main.gd` / `capture.gd` 条目 | `s0_2_boot` + `s0_2_scene_api`（19 符号）+ `s0_2_guard` + `s0_6_clock` + `B-` 6 机位逐位一致 |
| **2** | `scripts/world/` 5 个脚本 | `scenes/main.tscn` 的 `ext_resource` 路径；`GUARD_WHITELIST` 中 `terrain.gd` 条目 | 同上 + `B-` |
| **3** | `scripts/actors/player.gd`、`scripts/ui/` 2 个脚本 | `scenes/main.tscn` 引用 | 同上 + `B-` |
| **4** | `shaders/common/`（toon、outline）、`shaders/terrain/water.gdshader` | `scripts/core/style.gd` 与 `scripts/world/water.gd` 里的 `load()` 着色器路径 | 同上 + `B-` |
| **5** | —（文档） | `docs/ENGINEERING.md`（目录职责 + 映射表 + 基线 sha256）、§15 台账、`docs/成果.md` | 全量 `verify.gd --all`（窗口 + headless） |

回滚点：每批各自一个提交，出问题用 `git revert <该批提交>`；**禁止** `reset --hard` / `push --force`。

⚠️ 执行陷阱（已在验证脚本侧确认）：

1. **`.uid` 文件必须与其 `.gd` 同批、同目录移动**，否则 `res://` 引用解析失败或产生重复 UID。
2. **`GUARD_WHITELIST` 按「精确路径 + 行号」登记** → 移动白名单内的文件时，必须在**同一提交**内更新条目，
   否则 `s0_2_guard` 会立刻误报"未登记违例"。涉及：`main.gd`、`capture.gd`、`terrain.gd`。
3. 全仓共 **25 处** `res://scripts|shaders|scenes` 引用需同步改写（`project.godot` 4 处、
   `scenes/main.tscn` 的 `ext_resource`、脚本内 `load()/preload()`、`tools/` 内的加载路径）。
4. `tools/verify.gd` 的 `_walk()` 已确认**递归**扫描 `GUARD_SCAN_DIRS`，脚本进子目录后守卫不会漏扫。
5. **`.godot` 全局类缓存不随文件移动更新**（批次 1 实测踩到）：移动脚本后
   `.godot/global_script_class_cache.cfg` 仍保存旧路径，headless `--script` 会报
   `Could not find script for class "MeshUtil"`、`Could not parse global class "CameraRig" from
   "res://scripts/camera_rig.gd"`、`Class "CameraRig" hides a global script class`（新旧路径同时注册）。
   处置：删除 `global_script_class_cache.cfg`（必要时连 `uid_cache.bin`、`shader_cache/`）后执行
   `--headless --import` 重建。`.godot/` 为 gitignore 产物，可再生；此症状属**环境缓存**而非内容错误。
6. **着色器路径写错不报错，只静默退化**：`load()` 失败时材质回落默认，画面变样但日志干净，
   所以批次 4 必须靠 `B-` 6 机位逐位比对兜住，不能只看"退出码 0 且无 ERROR"。

**验收标准**
- `A-` headless 启动主场景 60 帧无 `ERROR`/`SCRIPT ERROR` 日志（可复用 `s0_2_boot`）。
- `A-` 既有公开 API 仍可解析：`Terrain.height_at` / `Style.toon` / `Main.rebuild` 等 19 个符号逐一点名断言存在（可复用 `s0_2_scene_api`）。
- `B-` 同 seed 同参数截图与重组前基线一致（`img_diff` 差异像素比 < 0.1%）。
  > Q13 已裁定选 (c)：改动画时钟为可注入 `u_time`。**前置 S0.6 已验收（2026-10-16）**。
  > S0.6 实测确定性模式下差异为 **0.0000%（逐位一致）**，故本项自本步起**收紧为逐位一致判定**：
  > 截图必须与迁移前基线**逐机位 sha256 相等**；基线为 S0.1 动工前采集的确定性 6 机位集合
  > （机位参数与完整 sha256 见 `docs/ENGINEERING.md` §4）。自动化口径另见
  > `tools/verify.gd --case=s0_6_repro`（2 机位 + 反向对照）。
  > ⚠️ 若重组本身**有意**改变画面，则须先在 §16 登记并留新基线，不得直接改判。
- `C-` `--bench` FPS 相对重组前基线下降 ≤ 3%（基线用 `tools/baseline.gd` 采集）。
  > 注意：本工程基线被 vsync 封顶在 60fps（`ms/frame` ≈ 16.667），该口径只能拦住
  > "跌破帧上限"级别的劣化；更细的劣化需比对 `ms/frame` 或三角面/绘制调用。

**依赖与风险**：无依赖（`B-` 项前置 S0.6 已验收）。风险：`.uid` 文件与 `res://` 路径引用遗漏 → 靠 `A-`/`B-` 拦截。
**状态**：✅ 已验收（2026-10-16，提交 `1bab8fd` + `16b7196` + `1aa739c` + `534e2bd`；产出 `docs/ENGINEERING.md`）

### S0.2 验收工具链 v1（verify 运行器 + 图像比对 + 性能基线）

**计划描述**
- `tools/verify.gd`（`extends SceneTree`，仿 `tools/diag.gd`）：`--case=<id>` 注册表、断言 API、JSON 报告落 `res://.verify/`、退出码 0/1/2、支持 `--all` / `--list` / `--out=`。
- `tools/img_diff.gd`：两图差异像素比（无外部依赖，纯 `Image` API + sha256 锚点）。
- `tools/baseline.gd`：采集并落盘性能基线（FPS / ms/frame / 内存 / 三角面数 / 绘制调用）。
- `capture.gd` 扩展：`--shots --case=<name>` 命名批次、`--frames=` / `--warmup=`、截图清单 JSON、输出目录参数统一。
- 规范守卫用例：静态扫描 `scenes/ scripts/ shaders/`，禁止 `BoxMesh`/`CSGBox3D`/白名单外 `StandardMaterial3D`/裸 `randf()`/裸 `randi()`；白名单命中项必须显式列出并附理由。
- `.gitignore` 增加 `.verify/`（`.shots/` 原已有）。

**验收标准**
- `A-` 故意失败的断言能让用例退出码 = 1；正常用例 = 0；JSON 报告含每条断言与耗时。
- `A-` `img_diff` 对同一文件输出 `0.0000%`；对人工改动后副本输出 > 0%。
- `A-` 规范守卫用例能各自捕获 1 个人造违例（5 类违例逐类造例，断言后删除）。
- `C-` `baseline.gd` 输出含 FPS、ms/frame、内存、三角面数四项且方差 < 5%（连续 3 次采样）。

**依赖与风险**：原定依赖 S0.1；经用户批准**前置执行**（见 §16）。
风险已由探针落实并修正（原猜测有误）：

- ~~「`SceneTree` 脚本无法访问 autoload」~~ → 实际是**编译期标识符不可解析**（`Identifier not found: Style`），
  而 autoload **节点**确实挂在 root 上。⇒ 运行器内禁止书写 autoload 标识符，改用
  `get_root().get_node("Style")`；全局 `class_name`（`MeshUtil`/`Terrain`）不受影响。
- 「加载主场景 + await」模式**实测可行**，无需子进程 hack；`add_child` 后须 `await` 一帧再查节点组。
- headless 下渲染指标恒为 0 ⇒ C- 类用例在 headless 下必须**跳过**而非判失败。
**状态**：🧪 待验收

### S0.3 全局服务骨架（GameState / EventBus / SceneRouter / SaveSystem v1）

**计划描述**
- `GameState`：世界 seed、游戏时间、玩家队伍引用、资源（金钱/粮草/补给）、当前场景类型。
- `EventBus`：全局信号 —— `time_advanced`、`encounter_started`、`battle_finished`、`resources_changed`、`settlement_entered`。
- `SceneRouter`：`goto_world()` / `goto_battle(ctx)` / `return_to_world(result)`，统一过渡与上下文传递（本步先做硬切+淡入淡出）。
- `SaveSystem` v1：`user://saves/slot_<n>.json`，含 `schema_version`、迁移钩子表、原子写入（临时文件 + 替换）、脏字段容错；**固定 9 个槽位**（契约见 §3.5）。
- 菜单页框架：`ESC` 打开 / 关闭游戏内菜单页，含「保存 / 另存为 / 读取 / 设置 / 返回游戏」入口。
- **3×3 九宫格存档页组件**（§3.5）：9 槽卡片、空槽态、覆盖二次确认。本步只做框架与 `GameState` 已登记字段的往返；全量世界状态留到 S1.9。

**执行方案（2026-10-16 与本会话对齐后定稿）**

本步交付面偏大（4 个服务 + 菜单框架 + 九宫格组件 + 7 项 `A-`），故拆为 **4 批**，
每批一个独立提交、一套独立校验、一次 `docs/成果.md` 续写；回滚同 §5 S0.1（`git revert <该批提交>`，
禁止 `reset --hard` / `push --force`）。

| 批 | 交付物 | 同批必改项 | autoload | 新增校验 |
|---|---|---|---|---|
| **1** | `scripts/core/game_state.gd`（`GameState`）、`scripts/core/event_bus.gd`（`EventBus`）、`scripts/core/rng.gd`（`Rng`） | `project.godot` 3 条新 autoload；`docs/ENGINEERING.md` §1/§6 的 autoload 清单 | 3 → 6 | `s0_3_state`（字段齐全、快照逐字段确定、5 个信号已声明、`Rng` 子流可复现） |
| **2** | `scripts/core/save_system.gd`（`SaveSystem`，9 槽 / `schema_version` / 原子写 / 脏字段容错 / 无自动存档） | `project.godot` autoload | 6 → 7 | `s0_3_roundtrip`（跨进程）、`s0_3_dirty`、`s0_3_no_autosave` |
| **3** | `scripts/core/scene_router.gd`（`SceneRouter`）+ `scenes/battle/battle_stub.tscn`（**占位靶子**，M2 替换） | `project.godot` autoload；守卫新增规则 `scene_change_owner`，同步更新 `s0_2_guard` 的类数描述 | 7 → 8 | `s0_3_router`（`goto_battle`→`return_to_world` 节点数 ±0、autoload ≤ 10） |
| **4** | `scripts/ui/menu_page.gd` + `scripts/ui/save_grid.gd`（含槽卡片），接入 `ESC` 与 `SaveSystem` | `scenes/main.tscn` 挂载菜单（**默认隐藏**） | 8 | `s0_3_slots`、`s0_3_overwrite` + `B-` 截图 4 张 |

**批次落地状态**：批次 1 ✅ 已完成（2026-10-16，提交 subject `feat(core): S0.3 批次 1 —— 新增 Rng / EventBus / GameState 三个全局服务`）；
批次 2 ✅ 已完成（2026-10-16，autoload 6 → 7：`scripts/core/save_system.gd` + `project.godot` 注册；新增 4 个用例
`s0_3_roundtrip` / `s0_3_dirty` / `s0_3_atomic` / `s0_3_no_autosave`，共 156 断言；
实测证据见 §15 台账与 `docs/成果.md`）；
批次 3 ✅ 已完成（2026-10-16，提交 `2036423`，autoload 7 → 8：`scripts/core/scene_router.gd` + `scenes/battle/battle_stub.tscn`
（占位靶子，M2 替换）+ 守卫规则 `scene_change_owner`；`s0_3_state` 的 autoload 契约 7 → 8，
`s0_2_guard` 类数描述 7 类 → 8 类，新增 `s0_3_router` 70 断言；实测证据见 §15 台账与 `docs/成果.md`）；
批次 4 ✅ 已完成（2026-10-16，提交 `f3006d3`，subject `feat(ui): S0.3 批次 4 —— 新增存档菜单与 3×3 九宫格，接入 ESC 暂停与 SaveSystem`：
新增 `scripts/ui/menu_page.gd`（菜单页 / `ESC` 层级 / 覆盖确认弹窗）与 `scripts/ui/save_grid.gd`（3×3 槽卡片），
`scenes/main.tscn` 挂载 `MenuLayer`（**默认隐藏**），autoload 保持 8（本批不新增服务）；
`Clock` / `scripts/ui/ui_panel.gd` / 菜单三者显式 `PROCESS_MODE_ALWAYS`（陷阱 1 落地）；
新增用例 `s0_3_slots` 100 断言 + `s0_3_overwrite` 34 断言 + 4 张 `B-` 菜单截图；
实测证据见 §15 台账与 `docs/成果.md`）。

**批次 4 的对齐结论（2026-10-16，与本会话逐项确认后定稿）**

| 决策点 | 结论 |
|---|---|
| 保存 / 另存为 | 「保存」写**当前槽位**；没有当前槽位时按 `save_current()` 的契约**跳九宫格**并显示服务给的拒绝理由（"保存等同另存为"）；「另存为」一律打开九宫格、选槽后写入 |
| 覆盖二次确认 | **整页确认弹窗**（"确认覆盖" / "取消（保留旧存档）"两个按钮），不是行内提示；弹窗期间与取消后旧档 sha256 + mtime **逐项不变** |
| 当前槽位也要问 | 主页「保存」写**已占用**的当前槽位时同样先问一次：服务是唯一裁决（`save_slot()` 的覆盖确认契约不区分"我自己的档"），宁可多问一次也不静默覆盖 |
| `B-` 四张 | ① 菜单主页面 ② 九宫格空槽态 ③ 九宫格满槽态 ④ 覆盖确认态 —— 状态由**注入的真实输入**（ESC / 点击）达成，产品码里没有"演示状态"后门 |
| 暂停契约 | `ESC` 打开菜单 ⇒ `get_tree().paused = true`；`Clock` / `ui_panel.gd` / 菜单三者显式 `PROCESS_MODE_ALWAYS`（陷阱 1 的落地与实测） |
| 菜单默认隐藏 | `scenes/main.tscn` 挂载后 `visible = false`：本批唯一还要守住 6 机位 `B-` 门禁的地方 |
| 淡入淡出过渡 | **未纳入本批**（本批对齐范围只有菜单 + 宫格 + 覆盖确认）。理由：幕布必须**活过场景切换**（`change_scene_to_file()` 会释放旧场景），所以它不能挂在任何场景内，需要一个持久属主（新 autoload，或路由器持有 UI）—— 这是要先对齐的设计决定，不在批次末尾顺手做。顺延为独立小步，已在 §15 台账登记 |

**批次 3 的对齐结论（2026-10-16，与本会话逐项确认后定稿）**

| 决策点 | 结论 |
|---|---|
| `switch_mode` | 真 `change_scene_to_file()` 切场景（不是隐藏/叠加）：世界会被真正卸载，返回时重建 |
| `route_state` | 浅栈（`world` → `battle`，深度上限 2）+ **越界显式失败**（`last_error` 指明原因，拒绝不改状态） |
| `signals` | 本批不发游戏事实信号；只发自身路由事实 `route_changed(from, to)`（`encounter_started` / `battle_finished` 留给 M1 / M2，避免将来双重发射） |
| `transition` | 本批只做硬切，只留 `_switch_to()` 接口位；淡入淡出属 UI，批次 4 与菜单一起做 |
| `stub` 保真度 | 极简但合规：正交相机 + `MeshUtil.facet()` 低模地面 + 逆壳描边 + `Style.PALETTE` 配色 + 一行 Label 说明 |

**验收门禁（每批都跑，不只最后跑一次）**
- `A-` headless 启动 60 帧 0 条 `ERROR`/`SCRIPT ERROR`（`--quit-after 60`）。
- `A-` `tools/verify.gd --all` 全绿（既有 8 用例不回归 + 本批新增用例）。
- `B-` **6 机位逐位一致**（对照 `docs/ENGINEERING.md` §4 基线）。菜单默认隐藏，故 S0.3 全程不应改变
  主视图任何像素 —— 这条同时充当"菜单/服务没有漏进主画面"的强断言。
- `D-`（仅第 4 批末尾）`ESC` 开合、宫格选槽、二次确认的手感确认，交给你试。

**已裁定的 5 个设计决定（2026-10-16，均取推荐项）**

| # | 决定 | 理由 |
|---|---|---|
| 1 | 拆 **4 批**：服务 / 存档 / 路由 / UI | 每批可独立验收与回滚；九宫格与菜单框架耦合紧，不再细分 |
| 2 | 新建 `scenes/battle/battle_stub.tscn` 作路由靶子 | 让 `goto_battle`→`return_to_world` 的"节点数 ±0"验收成立；M2 用真战斗场景替换。**占位身份在此登记**，不得当作正式战斗场景 |
| 3 | **`Rng` 纳入本步**（第 5 个 autoload：`Rng`），但**暂不收编** `terrain.gd`/`scatter.gd` 既有的裸 `randi()` | §3.2 要求"所有随机走 `Rng`"；现在有名额（上限 10）。既有两个文件的随机序列一旦改变，地形/植被布局即变、6 机位基线失效 —— 故收编留到 M1 S1.1 与地形重构一起做，届时按 §5 S0.1 口径登记并重录基线 |
| 4 | 存档用例**整体换名** `user://saves/` ↔ `user://saves.bak` 做隔离 | 零产品码改动、完全隔离、不碰真实存档；产品码里因此**不需要**任何"测试用保存根"后门（也就不会成为发布构建的旁路） |
| 5 | `ESC` 打开菜单时**暂停世界**，但 `Clock` 与 UI 节点保持 `PROCESS_MODE_ALWAYS` | 常规手感（菜单里世界不该继续跑）；`Clock` 保持运行则"可复现渲染时钟"与截图确定性均不受影响 |

**执行陷阱（预先登记）**
1. `get_tree().paused = true` 会**连带停掉 autoload 的 `_process`**（autoload 挂在 root 下、默认继承暂停）。
   故 `Clock` 与 UI 根节点必须显式设 `process_mode = PROCESS_MODE_ALWAYS`；`GameState` 保持默认
   （暂停时游戏时间不应推进）。
   **已实测（2026-10-16，批次 4）**：菜单打开后 `paused == true`、主场景 `can_process() == false`、
   菜单与 `Clock` 的 `can_process()` 均为 `true`，且**暂停中 `Clock.frame` 仍精确前进 30 帧 / `t` +0.5s**
   （确定性模式下可数，不是"看起来在动"）；暂停期间注入的真实点击仍能打开宫格 —— 这条同时证明了
   `PROCESS_MODE_ALWAYS` 确实生效（否则按钮收不到输入）。
2. ~~**Windows 上"原子覆盖"需实测**~~ **已实测结案（2026-10-16，批次 2）**：单进程探针先给出
   "`rename_absolute(tmp, 已存在且未打开的目标)` 返回 OK、内容被替换、无 `.tmp` 残留；目标被读句柄
   占用时返回 err=1 且原档不变"的结论；**但跨进程并发用例 `s0_3_atomic` 推翻了"无空窗"这半句**——
   子进程连写同一槽位 800 次、父进程同期取 170 个样本（另一轮复测 193 个），实测
   **17 / 28 次「文件不存在」+ 22 / 25 次「文件在但读不出来」**（引擎的覆盖实现是"先删目标再改名"，
   不是原子替换），而**没有任何一次半截内容**（每个读得出来的样本都是完整合法 JSON，
   `schema_version` 与 `game.money` 齐全，两轮分别 131 / 140 个全部合法），风暴结束后读者看到的
   最终版本与写者自述的最后一版 **sha256 逐位一致**。
   ⇒ **不做**"先写 `.tmp` → 备份旧档 → 换名 → 回滚"的两段式（它反而会把空窗拉长）；
   改为：写者 `.tmp` → 回读校验 → `rename` + 有界重试（20×3 ms），读者 `_read_slot_text()`
   同样有界重试，并以"同目录 `.tmp` 是否存在"区分「真空槽位」（立即返回，不拖慢九宫格渲染）与
   「发布中」（重试）。实测该重试把 170 次并发读的失败数压到 **0**。
3. ~~`change_scene_to_file()` 后旧场景**不是当帧释放**~~ **已实测量化（2026-10-16，批次 3）**：
   `--script`（SceneTree MainLoop）下调用返回 `err=0`，但 `SceneTree.current_scene` 在**第 1 帧仍是
   旧场景**（探针实测为 `null`）、**第 2 帧**才是新场景；旧场景及其节点组也不当帧释放。因此
   "节点数 ±0"断言不能写成固定 `await N` 帧，而是**等到目标场景真的成为 `current_scene` 再多等 2 帧**；
   路由器另用 `_expected_path` 标记"在飞行中"，此期间拒绝第二次切换（否则引擎只保留最后一次请求，
   栈与屏幕会不一致）。见 `docs/ENGINEERING.md` §5 陷阱 10。
4. `user://saves/` 目录需按需 `DirAccess.make_dir_recursive_absolute()` 创建，首次存档前不存在。
5. ~~`ESC` 的键位与 `ui_cancel` 默认动作、以及 `input_setup.gd` 既有映射需先核对是否冲突~~ **已核对
   （2026-10-16，批次 4）**：`project.godot` 没有 `[input]` 段、`input_setup.gd` 未占用 `ESC`，内建
   `ui_cancel` 已绑定 Escape；菜单同时认 `keycode` / `physical_keycode` / `ui_cancel` 三者，不改键位表。
   用例断言"`ui_cancel` 存在且绑在 Escape 上"（S0.4 注册 `F1/F3/F5/F9` 时不受影响）。
6. 菜单节点**默认必须隐藏**，否则 6 机位 `B-` 门禁立即变红（这也是本步最有价值的一条自动防线）。
   **已守住（2026-10-16，批次 4）**：`s0_3_slots` 断言"启动时 `visible == false`"，且 6 机位 sha256 与
   S0.1 基线**全等**（6/6）；三层 UI 的层号也纳入断言（菜单层 > 调试 HUD 层）。

**验收标准**
- `A-` 「新游戏 → 快存 → 退出进程 → 读档」后 seed/时间/金钱/粮草/玩家位置逐字段一致（用例 `s0_3_roundtrip`）。
- `A-` 存档 JSON 含 `schema_version: 1`；注入未知/缺失/类型错误字段后读档不崩溃并有明确告警（用例 `s0_3_dirty`）。
- `A-` `goto_battle` → `return_to_world` 后场景节点数回到基线 ±0，autoload 数量 ≤ 10（2026-10-16 由 ≤ 6 放宽，见 §16）。
- `A-` 并发写同一槽位**不产生半截文件**（用例 `s0_3_atomic`）：读者读得出来的每个样本都必须是完整
  合法 JSON（两轮实测 131/131、140/140）；引擎 rename 覆盖在 Windows 上的非原子窗口由**读者有界
  重试**吸收（实测并发 170~193 次读 **0 次失败**），且风暴结束后读者看到的最终内容与写者自述的
  最后一版 sha256 一致。
- `A-` 宫格页渲染 9 个槽位；空槽显示「空槽位」且不可读取（用例 `s0_3_slots`）。
  **已实测（2026-10-16，批次 4）**：9 张卡片正文逐个 == `SaveSystem.slot_info(slot).label`（宫格自己不算、不缓存槽位数据）；
  空槽位在读取态点击给出理由、`current_slot` 不变、一个文件都不写。
- `A-` **无自动存档**：启动 → 进战斗 → 返回 → 退出全流程中，除显式点击「保存 / 另存为」外，
  `user://saves/` 下所有文件的内容哈希与 mtime 均不发生任何变化（用例 `s0_3_no_autosave`）。
- `A-` 覆盖已有槽必须触发二次确认；取消后原存档哈希不变（用例 `s0_3_overwrite`）。
  **已实测（2026-10-16，批次 4）**：弹窗期间与取消后 `saves/` 逐项（sha256 + mtime）不变，且 `save_written`
  **一次都没发**；确认后才 +1 次写入。注意口径：同一秒内状态没变时两次存档的**字节可以逐位相同**
  （`saved_at` 只到秒），所以"文件内容变了"不能当判据，"发布了几次写入"才是。
- `D-` `ESC` 菜单页开合、宫格选槽与二次确认流程的手感确认。**已通过（2026-10-16，用户人工试玩）**：
  `ESC` 开合、宫格选槽、覆盖二次确认全流程手感确认通过，**无返工项** ⇒ S0.3 的 `A-` / `B-` / `C-` / `D-`
  全部闭环，§15 状态置 `✅ 已验收`。

**依赖与风险**：S0.2。风险：单例过多导致隐式耦合 → 约定只有 `SceneRouter` 能切场景、只有 `SaveSystem` 能读写 `user://`。
**状态**：✅ 已验收（2026-10-16；批次 1–4 全部落地，`A-` / `B-` / `C-` / `D-` 验收项全部闭环）

### S0.4 调试与观测层

**计划描述**
- 调试叠加层（默认关闭）：帧时间曲线、实体/AI 计数、当前状态机名、`SceneRouter` 栈、内存。
- 快捷键：`F1` 隐藏全部 UI、`F3` 调试层、`F5` 快存、`F9` 快读（在 `input_setup.gd` 注册，可重映射）。
- 观测数据可落盘 CSV，供 M1/M2/M4 的性能验收取证。

**验收标准**
- `A-` 调试层开关不改变任何游戏逻辑（前后世界状态哈希一致）。
- `C-` 调试层开启的额外开销 < 0.5ms/帧（120 实体场景采样）。
- `A-` 发布构建默认关闭（导出配置中不含调试快捷键启用状态）。

**批次划分（3 批）**

| 批 | 范围 | 状态 |
|---|---|---|
| 1 | **`UiKit` 公共控件工厂**：把 `ui_panel.gd` / `menu_page.gd` / `save_grid.gd` 三份重复的 stylebox / 阴影偏移 / 标签构造抽成 `scripts/ui/ui_kit.gd`（`Widget`/`UiKit` 全局类）。验收：三份 UI 的 `B-` 截图逐位不变 | ✅ `ed92e66` |
| 2 | **叠加层 + `F1`/`F3` + CSV**：新增 autoload `Debug`（8 → 9）；面板（帧时间曲线 / 节点与分组计数 / 场景与路由栈 / 时钟与 Rng 子流）；两条调试热键；`--obs-csv=` 落盘 | ✅ 已完成（2026-10-19） |
| 3 | **`F5` 快存 / `F9` 快读 + 菜单里的调试入口**：两条快存快读热键（仍写 9 个真槽位）、叠加层提示行与独立 toast、菜单「设置」页改为调试页（只读事实 + 打开叠加层） | ✅ 已完成（2026-10-19） |

**批次 2 的对齐结论（2026-10-19，三问三答，均取推荐项）**

| 决策点 | 结论 |
|---|---|
| 本步范围 | **只做批次 2**：叠加层 + `F1`/`F3` + CSV。`F5`/`F9` 与菜单调试入口不在本批 —— 二者都要求"必须走真实槽位"（§3.5），而 §3.5 的覆盖二次确认与槽位卡片刷新已由批次 4 落地，接线必须单独验一遍手感，混进来会让本批的 `C-` 与 `B-` 证据都变浑 |
| 属主 | **新增 autoload `Debug`**（8 → 9，上限 10），不挂场景：`SceneRouter` 会真 `change_scene_to_file()`，挂在场景里的面板每切一次场景就消失，且 `F1`/`F3` 得在每个场景各实现一遍 |
| `_case_baseline` 的 `--out=` 缺陷 | **单独提交修掉** ⇒ 实际核查结论：该缺陷已在 `93c25e6` 修好（`--out=` 从那一版起就透传给 `baseline.gd`），台账与 `docs/成果.md` 的"未修"记录是**过期**的。故本次不做无意义的重复修复，改为**补一条回归锚点断言**（`s0_2_baseline` 21 断言）+ 在 §16 更正记录 |

**批次 2 的三条硬约束（直接决定了实现写法）**
1. **默认隐藏**：S0.4 之前录下的 6 机位 `B-` 基线必须继续逐位不变 ⇒ 本节点开工第一件事就是把整个
   `CanvasLayer` 设为不可见。`s0_4_overlay` 把这条写成断言（默认 `is_panel_visible() == false`）。
2. **确定性模式只显示可复现量**：截图模式下"内存 / 对象数 / 真实帧时间"是环境噪声（同参数两次进程
   也不同），显示它们会让 `B-` 的 sha256 永远对不上。故 CSV 的 `draw_calls` / `prims` / `ms_process`
   三列在确定性模式下**留空**（不是写 0，0 也是值、也会冒充证据）。
3. **不引入不可冻结的时间源**：帧时间一律读 `Performance.TIME_PROCESS`，绝不碰
   `Time.get_ticks_msec/usec`（守卫 `unfreezable_time`）；测量用墙钟即便白名单放行也要写理由，
   能不引入就不引入。

**批次 2 的验收证据（2026-10-19，实测）**
- `A-` **开关不改世界**（原验收项）：`s0_4_overlay` 在同一进程内对"关 → 开 → 关"两轮采样，
  世界结构指纹、seed 派生量（`spawn_point` / `height_at` / 树石计数）、`GameState` 世界字段、
  **`Rng` 每条子流的内部 `state`** 逐项不变；`F1` 隐藏后结构指纹同样不变（隐藏 ≠ 卸载）。
  另外把"调试层顺手抽了个随机数"这种最常见的内伤纳入断言 —— 子流 `state` 变一点就会红。
- `C-` **开销 < 0.5 ms/帧**（原验收项）：`s0_4_cost` 用 120 个真实 `MeshInstance3D`
  （`MeshUtil.blob()` + `Style.toon()`，含逆壳描边）做夹具，**直接给叠加层自己的每帧工作计时**
  （`_push_sample()` 每帧 + `_refresh()` 每 6 帧，与 `_process()` 的真实节奏一致），5 轮 × 400 帧
  取中位数：**0.0044 ms/帧**（最大 0.0058）。
  **这一条改过一次写法，原因值得记住**：最初写的是"开层/关层帧时间差 < 0.5ms"，两次实测都证明
  它测不出东西 —— ① vsync 开着时差值是**负**的（关层 18.75 / 开层 17.84 ms，量到的是 vsync 等待
  与抖动）；② 关掉 vsync 改逐帧墙钟后，注入一个确定的 2ms/帧 自旋负载，**只回收 41%**
  （2.000 → 0.817）。即帧时间差对 0.5ms 量级既测不准也测不出，拿它写断言等于没写（叠加层再贵都绿）。
  现在另附一条**标尺**：用同一口径注入 0.5ms / 2ms 自旋，量到 0.5000 / 2.0000（回收率 ≈100%），
  先把"这套计时能分辨 0.5ms"证明掉，`< 0.5ms` 才是可证伪的断言。
  另加**反向对照**：开层后 `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 必须上升，否则"开销很小"可能只是"面板压根没画"。
- `A-` **发布构建默认关闭**（原验收项）：唯一闸门是 `InputSetup.ensure_debug_hotkeys(OS.is_debug_build())`，
  关掉时**删除 action**（不是留着不注册）；`s0_4_overlay` 断言"闸门关掉后按 F3/F1 完全没反应"，
  并扫描代码行证明 `OS.is_debug_build` 在 `res://scripts` 里**只出现 1 次**（两处判断迟早会不一致）。
  口径说明：本项验的是**运行时闸门**，不是导出配置里的一行开关 —— 后者可以被改坏而无人发现，
  前者在关掉 action 后连注入按键都无效。
- `B-` **默认隐藏可用截图证明**：`s0_4_overlay` / `s0_4_ui_hidden` 两批次各跑两个独立进程，
  同批次两轮 **sha256 逐位一致**、两批次互不相同；`s0_4_cost` 另做像素取证 —— 同机位下
  `F1` 后的图里 UI 面板底色（`UiKit.PAPER #fff9e8`）**精确 0 像素**，而有 HUD 的基准图有 3892 个
  采样像素 ⇒ `F1` 是"把 UI 从渲染里拿掉"，不是"调透明度"或"盖一层"。6 机位基线与 S0.1 基线
  **全等（6/6）**，故 S0.4 全程未改动主视图任何像素。

**批次 2 的三条实测结论（值得记住）**
1. **`SceneRouter` 开局本来就没有栈条目**：主场景是引擎直接加载的，不经路由器 ⇒ `current_route()`
   在开局是空串。调试层最初直接把空串画进 `SCENE` 行，于是"最常看的一行在最常见的状态下是空的"。
   修法是 `scene_label()` 两级回退（路由条目 → 当前场景文件名，用括号标出后者）。这条同时是
   `s0_4_overlay` 断言"CSV 的 `scene` 列与面板同源"的由来 —— 两处各算一次迟早会漂移。
2. **headless 下 `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 恒为 0**：CSV 的"实时模式有实测值"若在 headless
   子进程里验，会得到一堆 `0.000` 而断言照样通过（看起来有值、其实是零）。该探针必须开窗口跑，
   断言也必须是"**非零**行数 ≥ N"而不是"列非空"。
3. **中位数不是风格偏好，而是必要条件**：单次 OS 调度/GC 就能把一段 200 帧的均值拉偏 3 倍以上，
   而它与被测对象无关。**但仅靠中位数还不够** —— 见上面 `C-` 那条：换掉监视器、并加一条已知量的
   标尺，才让"< 0.5ms"从一句话变成一个可证伪的断言。教训归纳成一句：
   **凡是"某个东西很便宜"的断言，都必须同时证明"这套量法测得出它变贵"。**

**批次 3 的对齐结论（2026-10-19，两问两答）**

| 决策点 | 结论 |
|---|---|
| `F5` 撞上已占用槽位怎么办 | **只做直写，不弹菜单**。§3.5 的"覆盖必须二次确认"不因此豁免，而是把确认从"点弹窗"改成"再按一次 `F5`"：第一次 `F5` **不写**、只登记待确认并给出理由，`CONFIRM_WINDOW_FRAMES = 120` 帧内再按一次才真覆盖。这样"不弹菜单"与"不破坏契约"同时成立，且全程仍走 `SaveSystem.save_slot()`，本层不另立一套规则 |
| 菜单调试入口放哪 | **填实现有的「设置」页**（不加新页、不加提示行）。原来那句"设置页还没做"是死文案；改成调试页后按钮路径 `Root/Home/Panel/Col/Actions/Settings` 不变（`verify.gd` 的节点表依赖它），真正的设置项留到 M6（S6.3） |

**批次 3 的三条实现要点**
1. **闸门必须在函数里，不能只在 `_input` 里**：`_input` 只挡按键，挡不住"有人直接调
   `quick_save()`"。§3.5 要求发布构建**完全禁用**，所以 `quick_save()` / `quick_load()` 开头
   各自检查 `_quick_enabled()`（= 两个 action 在不在，与 `F1`/`F3` 同一个事实来源，
   不自己再判断构建类型 —— 那会破坏"全项目只有一处 `OS.is_debug_build`"）。
   验收用例正是直接调方法验的：闸门关掉后调用返回 `ok=false` 且存档目录零变化。
2. **提示必须独立于叠加层**：叠加层默认关着，若 `F5` 的反馈只画在面板里，按键就等于"什么都没发生"
   —— 比报错更糟。故另起 `ToastLayer`（`LAYER + 1`），只在有话时可见，且同样服从 `F1`
   （隐藏全部 UI 时不留一条浮字）。过期按**帧数**判定（`NOTICE_FRAMES = 180`），不用墙钟。
3. **本地拒绝的结果必须与 `SaveSystem` 同形**：`ok/slot/reason/requires_confirm/warnings/bytes`
   一个不少。否则调用方要区分"服务拒绝"与"本层拒绝"，`ok` 缺省会变成 `false` 还是 `true`
   取决于读法（实测踩过：`res.get("ok", true)` 把空字典读成了成功）。

**批次 3 的验收证据（2026-10-19，实测）**
- `A-` **仍写 9 个真槽位、无旁路文件**（§3.5 原文）：`s0_4_quick` 遍历 `user://saves`，
  除 `slot_1..9.json` 之外**任何文件都算失败**；并扫产品代码证明 `quicksave` 零命中
  （没有"快存专用文件"这种东西）。
- `A-` **覆盖确认没有被绕过**：空槽位一次 `F5` 就落盘且 `requires_confirm=false`；
  已占用槽位第一次 `F5` 后**旧档 sha256 逐位不变**、`is_confirm_pending()==true`，
  第二次才变 —— 这是"没有静默覆盖"的可观测证据，比只读返回值硬。
  另验**窗口过期**：把 `_confirm_until` 推到过去后单按一次 `F5` 又回到"先拒绝"。
- `A-` **无当前槽位时拒绝**：不发明槽位（目录哈希不变），并给出人话理由。
- `A-` **发布构建闸门**：`ensure_debug_hotkeys(false)` 后两个 action 被删除、
  `stats().quick_hotkeys==false`、直接调用 `quick_save()` 也不产生任何写入。
- `A-` **菜单调试页与 `Debug` 同源**：`debug_facts()` 的 `hotkeys` / `quick_hotkeys` /
  `overlay_on` / `scene` / `slot` 逐项等于 `Debug.stats()` 与 `SaveSystem.current_slot`；
  「打开叠加层」按钮真的驱动 `Debug.set_overlay(true)`；`ESC` 从调试页回主页（与宫格同层级）。
  ⚠️ 该用例是 `pure`（`--headless`），headless 下窗口尺寸 **0×0**、注入鼠标事件无处命中，
  故按钮验的是"在 + 连着处理器 + 处理器真驱动 Debug"，鼠标命中路径由 headed 的
  `s0_3_slots` 覆盖（同一套 `UiKit.button_page` 工厂与页面结构）。

**依赖与风险**：S0.3。风险：单例过多导致隐式耦合 → 约定只有 `SceneRouter` 能切场景、只有 `SaveSystem` 能读写 `user://`。
**状态**：✅ 已验收（批次 1 `ed92e66`、批次 2 2026-10-19、批次 3 2026-10-19；`D-` 人工手感已通过）

### S0.5 工程规范与美术管线文档

**计划描述**
- `docs/ENGINEERING.md`：目录职责、命名、信号、数据表格式、autoload 上限、允许/禁止清单。
- `docs/ART_PIPELINE.md`：§3.1 在 Godot 中的落地清单（含"如何新建一个合规物件"的 6 步模板与 3 个反例）。
- 与 `AGENTS.md` 交叉引用，冲突以 `AGENTS.md` 为准。

**验收标准**
- `A-` 文档中每条约定都能在代码里定位（抽查 5 条，verify 用例 `s0_5_doc_conventions` 用路径/符号断言）。
- `B-` 文档内嵌「合规样板」与「违例反例」各 3 张截图（由 S0.2 工具产出）。
- `D-` 你通读并确认两份文档与实际实现一致。

**依赖与风险**：S0.1/S0.2。
**状态**：✅ 已验收（`A-`/`B-`/`C-` 全部通过，`D-` 用户已于 2026-10-19 通读确认）

**落地记录（2026-10-19）**
- `docs/ENGINEERING.md` 补齐 §7–§13：命名规范（含 **12** 个 `class_name` 与 4 处路径引用点）、
  信号约定（25 条实测清单 + 4 类判定口径）、数据表格式（`Canon` 契约，**标注"未实现，S1.1 落地"**）、
  autoload 上限与顺序约束、允许/禁止清单、以及"如何新增一个合规物件"的交叉引用。
- `docs/ART_PIPELINE.md`（新建）：§3.1 的 Godot 落地清单 + 6 步新建模板 + 3 个反例，
  内嵌 6 张由真实工具链产出的截图（`docs/art/s0_5/*.png`）。
- 教材夹具：`scenes/dev/art_samples.tscn` + `scripts/dev/art_samples.gd`（6 个展台、3 对 A/B）。
  违例反例真的使用了被禁写法，故在 `GUARD_WHITELIST` 里逐条登记并写明理由，守卫报告每次
  运行都显式打印这两行 —— 不静默放过、也不藏进不扫描的 `tools/`。
- 工具链新增两个修饰符：`Capture --at="x,y,z"`（把正交相机对准绝对坐标）与
  位置参数化场景（`godot --path P res://scenes/dev/art_samples.tscn`）。
  后者绕开 `SceneRouter`，因此不触碰 `scene_change_owner` 守卫。
- 验收用例 `s0_5_doc_conventions`（`pure`）：对两份文档做**双向**断言 —— 正向要求
  每条约定在代码里定位得到，反向用**编造的锚点**证明"文档里有关键字"不会假绿；
  另断言 `docs/art/s0_5/` 的 6 张 PNG 存在且 sha256 与 `s0_5_samples` 批次清单一致。

**验收记录（2026-10-19 闭环，提交 `9070501`）**

| 项 | 结果 |
|---|---|
| `A-` 抽查 5 条约定能在代码定位 | **通过**（用例对 12 类 + 25 信号 + 9 autoload + 7 守卫规则逐条断言"文档有锚点 **且** 代码有实现"，远超 5 条） |
| `B-` 3 张合规 + 3 张违例 | **通过**（六张 sha256 与批次清单逐位一致；两次独立窗口进程拍同一批次 **6/6 相同**） |
| `B-` 6 机位基线回归 | **通过**（**6/6 sha256 全等**，本步未触碰主场景/着色器/`style.gd`/`scatter.gd`/`terrain.gd`/`camera_rig.gd`） |
| `C-` 性能基线回归 | **通过**（`s0_2_baseline`；FPS 极差 0.150%、ms/frame 极差 0.138%，均 < 5%） |
| `D-` 通读两份文档 | **通过**（用户 2026-10-19 确认） |
| 窗口 `--all` | **20 用例 / 0 失败 / 0 跳过 / 1108 断言 / 约 108s**，退出码 0，**连跑 2 轮全绿** |
| headless `--all` | 20 用例 / 0 失败 / 跳过 5（headed 用例），退出码 0 |
| 启动门禁 | `--headless --quit-after 60` 退出码 0，0 条 `ERROR` / `SCRIPT ERROR` |
| autoload | **9 / 10**（本步未新增） |

> **守卫为什么抓不到第 ③ 对反例**：`06_bad_smooth_ball` 不是"用了某个被禁的类"，
> 而是**少调了一次 `MeshUtil.facet()`**。守卫按 token 扫，扫不出"这个网格没有面着色"。
> 故 `docs/ART_PIPELINE.md` §2.2 明确写"守卫绿了不等于看起来对"，并把
> "拍了图并真的看了"写进提交前 checklist —— 这一条**只能靠人**。

**顺带修掉的既有缺陷（2026-10-19，同一提交）**

`tools/verify.gd::_click_control()` 与 `scripts/core/capture.gd::_click_path()` 原本只注入
`InputEventMouseButton` 的 press/release，**没有 `InputEventMouseMotion`**。Godot 的
`Viewport` 用 `gui.mouse_focus` 决定把按键投给谁，而该焦点**由鼠标移动事件更新**；
没有移动，按键就落在失效焦点上 ⇒ `s0_3_slots` 间歇性失败（**在 HEAD 上跑 5 次红 2 次**，
失败点每次不同：读取没跳宫格 / 另存为没进宫格 / 两轮截图 sha256 不一致）。
修法：点击前先发一个落在目标中心的 motion 事件，**不动产品码**。
修后 `s0_3_slots` **连跑 18 次全绿**、`--all` **连跑 2 轮全绿**。

> **两条可复用的判断法**：① **"偶发失败"要先证明它是既有的** —— 把
> `git show HEAD:tools/verify.gd` 导成临时脚本跑同一用例，它同样红，才说明不是自己引入的。
> ② **失败点漂移是"共享前置条件坏了"的典型特征** —— 每次都红同一条是那条断言的问题；
> 红点到处跑，说明更早的某一步（这里是"点击真的落下去了"）时灵时不灵，下游全是受害者。

### S0.6 可复现渲染时钟（可注入 `u_time`）

> 来源：Q13 裁定选 (c)。**本步是 S0.1 `B-` 门禁的前置**——没有可复现帧，`B-` 项无法判定。

**计划描述**
- 新增 `scripts/render_clock.gd`（autoload `Clock`）：唯一时间源。
  - 普通模式：按真实 `delta` 前进（**交互运行行为必须与现状逐帧一致**）。
  - 确定性模式：按固定步长 `1/step_hz`（默认 60Hz）前进，帧号 → 时间一一对应。
  - 对外暴露 `t`（累计秒）、`dt`（本帧步长）、`set_deterministic(on, hz)`、`reset()`。
- `project.godot` 声明**全局着色器参数** `shader_globals/render_time`（float），
  由 `Clock` 每帧 `RenderingServer.global_shader_parameter_set("render_time", t)` 写入。
- 着色器改用该 uniform，删除内建 `TIME`：
  `shaders/toon.gdshader:49`（风摆）、`shaders/water.gdshader:33/51/60`（波纹/泡沫）。
- 脚本动画改用 `Clock`，删除真实时间读取：
  `scripts/clouds.gd:78/79`（漂移用 `dt`）、`scripts/clouds.gd:81`（`Time.get_ticks_msec()` → `Clock.t`）。
- `capture.gd`：截图批次默认开启确定性模式（可 `--realtime` 关闭），并新增 `--clock-hz=`。
- 保留 `--realtime` 逃生门，供 D- 类人工试玩与后续玩法步骤使用。

**验收标准**
- `A-` 两个**独立进程**、同 seed 同参数截图，`img_diff` 差异 = **0.0000%**（逐位一致，sha256 相同）。
- `A-` 反向对照：故意改一个参数（如 `--yaw`）后差异 **> 0%**，排除"两张都是空图"的假通过。
- `A-` 时钟单测（`s0_6_clock`）：确定性模式下第 N 帧 `t == N/hz`；普通模式下 `t` 随真实 delta 前进；`reset()` 归零。
- `A-` 交互运行行为不变：非确定性模式下 `Clock.t` 与改动前的真实时间语义一致（用例断言单调、量级匹配）。
- `C-` 性能不回归：`tools/baseline.gd` 相对 S0.2 基线 FPS 下降 ≤ 3%。
- `A-` 既有 6 个用例全绿不回归（`verify.gd --all`）。

**依赖与风险**：S0.2。风险：全局着色器参数在 headless 下无效（预期无副作用，需实测）；
浮点累加误差导致长时间后仍有微差 → 确定性模式按**帧号乘步长**计算 `t`，而非累加。
**实测结论（2026-10-16）**：
- headless 下 `RenderingServer.global_shader_parameter_set()` 无副作用，启动日志干净（0 条 `ERROR`）。
- 但 `RenderingServer.global_shader_parameter_get_list()` **是编辑器专用 API**，运行期调用会报
  `This function should never be used outside the editor`，会污染"日志无 ERROR"推送门禁 ⇒
  `Clock.shader_param_ok` 改用 `ProjectSettings.has_setting("shader_globals/render_time")` 判定；
  「值是否真的进入着色器」由 `s0_6_repro` 的**帧数反向对照**实质验证，不靠渲染服务读回。
- 除着色器与 `clouds.gd` 外，`scripts/player.gd` 的竖直跟随也依赖物理步数（随真实帧率浮动），
  确定性模式下改为直接落到静止高度；`scripts/main.gd` 的 HUD FPS 读数同理固定为 `Clock.hz`
  （HUD 在取景范围内，实时 FPS 会让每张基准图都不一样）。
- 守卫已新增 `unfreezable_time` 规则拦截回归：着色器内建 `TIME` 与 GDScript
  `Time.get_ticks_msec/usec` 一律判违例（测量用墙钟走白名单登记）。
**状态**：✅ 已验收（2026-10-16，提交 `457a7d2` + `953fd0d`）

---

## 6. 里程碑 M1：大地图（战略层）—— 最高优先级

> 目的：先让"世界"活起来。玩家在微缩战略图上率队移动，时间流动，聚落可交互，AI 队伍活动并触发遭遇。
> 尚未接入战斗时，遭遇先以「结果结算占位」闭环（明确标注占位，S2.10 替换为真实战斗）。

> **设计参考（2026-10-19 纳入）**：`docs/骑砍数据反推/` 六册是对《骑马与砍杀：战团》Native 模块的逆向文档集
> （编译脚本字节码 + 随文件发布的数据表 + 可执行文件反编译），自带三级证据标签 **【实证】/【推断】/【未解】**。
> 它是 **M1 的设计输入，不是本项目的规范**：只借结构与量级，**不照抄数值**；引用时必须标明证据等级，
> 【未解】项一律不得填数（与本项目"不猜测"的验收文化同源）。
> 最直接的三条结论在 `02-玩法设计.md` 附录：① 工资/士气/食物**三条负反馈共同**挤出编制上限，缺一即失去"规模是资源"的手感；
> ② 剿匪同时供给金币、经验、战利品、兵源，是四条收益线的唯一交汇点；③ 城堡被刻意排除在经济系统之外（"占下就赚" vs 城镇村庄"占下先亏"）。
> 落地引用点：S1.1 的 `data/world/gen_params.json` 初值与 `Canon` 的钳制告警口径。

### S1.0 场景与路由迁移（S1.1/S1.2 的前置）

**计划描述**
- 目标：**战略图接管路由 `world`**，演示岛降为 `scenes/dev/diorama.tscn`（场景内容逐字节不变）。
- 为什么必须单列一步：`SceneRouter.SCENES` 现状是 `world → res://scenes/main.tscn`，`s0_3_router`
  有**逐字比对**该路径的断言，6 机位 `B-` 基线也取自 `main.tscn`，且 `project.godot` 的 `run/main_scene`
  指向同一文件 —— 三处事实源必须同时改，混进 S1.1 会让"数据层写错"与"场景搬坏"两种红无法区分。
  （**S1.0a 已落地**：三处已同时改到 `res://scenes/dev/diorama.tscn`，并新增断言
  `run/main_scene == scene_path_for("world")`，把这条人工核对升级成机器判定。）
- 拆四个可独立验收、各自可回滚的子步（**每步一个提交**）：

| 子步 | 动作 | 验收 | 状态 |
|---|---|---|---|
| S1.0a | `scenes/main.tscn` → `scenes/dev/diorama.tscn`（只改路径引用与 `run/main_scene`） | 6 机位 sha256 **仍逐位等于** `docs/ENGINEERING.md` §4 基线（证明"搬文件不改像素"） | ✅ 已完成（2026-10-19） |
| S1.0b | `capture.gd` 支持 `--scene=res://…`（缺省仍是主场景） | 同参数两次独立进程截图 sha256 相同；`--scene=res://scenes/dev/diorama.tscn` 得到与缺省**完全相同**的哈希组 | ✅ 已完成（2026-10-19） |
| S1.0c | 路由表加 `strategic`（新增空场景 `scenes/world/strategic_map.tscn`，`world` 暂时仍指 diorama） | `s0_3_router` 改断言后全绿；新增 `s1_0_routes`（表条目 / 路径存在 / `MAX_DEPTH` 不变 / 拒绝不改状态） | ✅ 已完成（2026-10-20） |
| S1.0d | `world` 改指 `strategic_map.tscn`，并**删掉临时路由名 `strategic`**（表回到 world / battle 两条）；diorama 降为仅供回归与取景 | 6 机位改为 `--scene=res://scenes/dev/diorama.tscn` 的**专用批次**（`.shots/diorama_*`）；新增 `s1_0_migration`（路由 → 文件 → 场景根类三者一致 + 开机认领且不重载） | ✅ 已完成（2026-10-20） |

**验收标准**
- `A-` 每个子步后 6 机位 `B-` 逐位一致（a/c/d 三步尤关键：它们动 `project.godot` 与路由表）。
- `A-` `s0_3_router` + 新增 `s1_0_routes` / `s1_0_migration` 全绿；`--all` 无新增跳过。
- `B-` diorama 专用批次 6 张与基线逐位一致 —— 这是"搬场景没搬坏"的唯一硬证据，不接受"看起来一样"。
- `A-` `--scene=` 的同参两次进程一致性（证明它是确定性通道，不是随机取景）。

**同批必改（漏一处就会红）**
- `tools/verify.gd`：`_case_router` 的 `scene_path_for("world")` 断言、`_load_diorama()`（原 `_load_main()`）的目标、
  以及**所有截片子进程**（`s0_6_repro` / `s0_4_overlay` / `s0_4_cost` / `s0_3_slots` / `s0_3_overwrite`）——缺省场景已无内容，必须显式 `--scene=diorama`。
- `docs/ENGINEERING.md` §4：6 机位采集命令补 `--scene=`。
- `docs/成果.md`：追加"基线已重定向"，**不改**历史条目（保持历史记录）。
- `project.godot`：`run/main_scene`（改完用 `git diff` 逐行确认 —— 编辑器会重写该文件，见 §16 2026-10-19 条）。

**S1.0a 落地与验收记录（2026-10-19）**

| 项 | 结果 |
|---|---|
| 改动 | `git mv scenes/main.tscn scenes/dev/diorama.tscn`（git 识别为 **100% 相似度重命名**，内容未改一字节）；`project.godot` 的 `run/main_scene`、`SceneRouter.SCENES[world]`、`tools/baseline.gd`、`tools/verify.gd::_load_main()` 同步换路径；两处注释里的旧路径一并更新 |
| `A-` 三处事实源一致 | `s0_3_router` 新增断言：`run/main_scene` == `scene_path_for("world")` == 文件真实存在。把原来靠 `git diff` 人工核对的约定升级成机器判定（改两处漏一处即红） |
| `B-` 6 机位 | **两条独立进程**重采（`.shots/s10a_verify` / `s10a_verify_b`），**6/6 sha256 与 `docs/ENGINEERING.md` §4 基线逐位相等**、且两次互等（`6e2137…` / `5bde25…` / `1a6066…` / `729db4…` / `f7725a…` / `c0858f…`）——"搬文件不改像素"成立 |
| `A-` 全量 | 窗口 `--all` **20 用例 / 0 失败 / 0 跳过 / 857 断言 / 109s**、退出码 0；headless `--all` 20 用例 / 0 失败 / 5 跳过（headed 用例按设计跳过）、退出码 0；headless 启动门禁 0 条 `ERROR`/`WARNING` |
| 附带修掉 | `s0_5_doc_conventions` 的"产品码不得引用 `dev/`"从零容忍改为**登记清单**：`scenes/dev/` 现允许 `scene_router.gd` 一处（S1.0d 后自然收紧回 0），并加反向对照证明清单不是恒真 |

**S1.0b 落地与验收记录（2026-10-19）**

| 项 | 结果 |
|---|---|
| 改动 | `scripts/core/capture.gd`：新增 `--scene=res://…`（**纯修饰符**，缺省仍取 `run/main_scene`）；`_swap_scene()` 换掉 `SceneTree.current_scene` 并自证四条（新实例接管 / 路径一致 / 旧场景已释放 / 相机组最多 1 台），任一不成立即退出码 1；截图清单新增 `scene` 字段自报"拍的是哪个场景" |
| 为什么不用 `change_scene_to_*` | `scene_change_owner` 守卫只放行 `SceneRouter`（§3.2）。这里做的是**取景工具换夹具**，不是游戏内转场 —— 走 `SceneTree` 公开成员手动换，且不动 `current_route`；`s1_0_scene_arg` 反向断言 `SCENE_CHANGE_OWNERS` 仍只有 1 个属主、`capture.gd` 不在其中 |
| `A-` 同参两次进程 | `--scene=res://scenes/dev/diorama.tscn` 两次独立进程各 2 张图：sha256 互等，且**与缺省批次逐位相同**（`10e29e93…` / `d56ada81…`） |
| `A-` 反向对照 | 换成 `res://scenes/battle/battle_stub.tscn` 后 2 张图哈希**全变**（`79b0610b…`），清单 `scene` 同步改为该路径 —— 证明 `--scene=` 真的生效，而不是"缺省恰好也是它"的假绿 |
| `A-` 新用例 | `s1_0_scene_arg` **32 断言 / 22442ms / PASS**（headed） |
| `A-` 全量 | 窗口 `--all` **21 用例 / 0 失败 / 0 跳过 / 889 断言 / 131s**、退出码 0；headless `--all` 21 用例 / 0 失败 / 6 跳过（headed 用例按设计跳过）、退出码 0；headless 启动门禁 0 条 `ERROR`/`WARNING` |
| `B-` 6 机位 | 改完 `capture.gd` 后另跑两条独立进程（`.shots/s10b_cam_a` / `s10b_cam_b`），**6/6 仍与 `docs/ENGINEERING.md` §4 基线逐位相等** —— 默认路径一个字节都没动 |
| 两个坑 | ① **改 `run/main_scene` 无效**：引擎在 autoload `_ready()` 之前就把主场景路径取走了，`--scene=<非默认场景>` 会静默加载默认场景；而自证若只比"当前场景 == 要求"，在指定值恰为默认场景时会**空洞通过** —— 这是本步最危险的假绿形状（`battle_stub` 反向对照就是专门防它的）。② **多等一帧足以毁掉逐位一致**：云是增量积分（`position.x += drift * Clock.dt`），`queue_free()` 后 `await process_frame` 会把云往前推一步，两张图肉眼一模一样、sha256 全不同 |

**S1.0c 落地与验收记录（2026-10-20）**

| 项 | 结果 |
|---|---|
| 改动 | 新增 `scenes/world/strategic_map.tscn`（**空壳**：`Node3D` 根 `StrategicMap`，无脚本 / 无子节点 / 无相机，真实内容留 S1.2）；`SceneRouter.SCENES` 追加 `strategic → 该文件`；`world` 与 `run/main_scene` **一个字节都没动**（切 `world` 是 S1.0d）；**不新增** `goto_strategic()`、不改 `goto_*` 语义 |
| 为什么"只登记不接线" | 本步的验收物就是"表条目在、接线面没扩大"。若顺手加一个 `goto_strategic()`，S1.0d 的"迁移"就会同时改路由表 + 导航语义 + `world` 指向，三种红混在一起无法区分 —— 与 S1.0 拆子步的理由同源 |
| 双向映射 | 表必须**双向**成立：`scene_path_for("strategic")` 与 `_route_for_path(该路径)` 同时为真。`_sync()` 靠后者在场景落地后认领路由；只测前者时"名字对、路径写错"仍会绿 |
| `A-` 新用例 | `s1_0_routes` **37 断言 / 0.94s / PASS**（pure）：三路由（含 `strategic`）且路径真实存在、三条互不相同、`run/main_scene` 仍指 diorama、path↔route 双向、`MAX_DEPTH` 仍为 2、场景可实例化且根节点为 `Node3D`/`StrategicMap`/零子节点/无脚本、**没有** `goto_strategic()`、`goto_world()` 在已处 world 时被拒且栈/路由/屏幕/表条目零变化；收尾释放场景，把现场交还后续用例 |
| `A-` 既有用例 | `s0_3_router` 由 73 → **74 断言**（路由名集合 2 → 3，并逐字断言 `strategic` 的路径），全绿；其余用例无回归 |
| `A-` 全量 | 窗口 `--all` **22 用例 / 0 失败 / 0 跳过 / 927 断言 / 138.3s**、退出码 0；headless `--all` 22 / 0 失败 / 6 跳过（headed 按设计跳过）/ 677 断言 / 33.4s、退出码 0；headless 启动门禁 0 条 `ERROR` / `WARNING` / `SCRIPT ERROR` |
| `B-` 6 机位 | 两条独立进程重采（`.shots/s10c_cam_a` / `s10c_cam_b`）：**6/6 sha256 与 `docs/ENGINEERING.md` §4 基线逐位相等**、两轮互等；manifest `det=True hz=60.0 t=2.5 frame=150` —— 新增场景没进主视图渲染路径 |
| 一个坑 | 用例为验"已在 world 被拒"必须真的切到 world；**不清理**会让下一个用例的 `_load_main()` 变成**第二个**世界（两个 `#main`、两台相机）。处置与 `s0_3_router` 同口径：`queue_free()` + 两帧 + `_restore_defaults()`，并断言收尾后 `current_route()` 归空 |
| 留给 S1.0d | `goto_world()` 目前只拒 `world` / `battle`。S1.0d 把 `world` 指到战略图后，开机即落在 `strategic`，此时 `goto_world()` 会重载同一个文件 —— 该语义必须在 S1.0d 决定（路由表头已写，本步**不预判**） |

**S1.0d 落地与验收记录（2026-10-20）**

| 项 | 结果 |
|---|---|
| 改动 | `project.godot` 的 `run/main_scene` → `res://scenes/world/strategic_map.tscn`；`SceneRouter.SCENES` 变成 `world → 战略图 / battle`，**删除** S1.0c 的临时名 `strategic`（一个文件只留一个名字，`_route_for_path()` 不再二义）；头注改成"WORLD IS THE STRATEGIC MAP"，并把 diorama 明确写成回归夹具 |
| `goto_world()` 的语义 | 不新增分支：开机由 `_sync()` 把引擎加载的场景认领成 `world`，此后 `goto_world()` 照旧被拒（"已经在世界场景"）且**不重载同一个文件**。S1.0c 留下的那个问题用"实例数不变"断言闭环，而不是靠注释承诺 |
| `A-` 迁移闭环 | 新增 `s1_0_migration` **22 断言 / PASS**：路由 world → 文件 → 根类（`Node3D` / `StrategicMap` / 无脚本 / 零子节点 / 自报路径）三者一致；`run/main_scene` 逐字相等且 ≠ diorama；diorama 仍存在且仍可加载；把战略图设成 `current_scene` 后 `_sync()` 认领为 `world`（depth=1）、`goto_world()` 被拒、**世界实例数仍为 1** |
| `A-` 既有用例 | `s1_0_routes` 37 断言（两条路由 / `STRATEGIC` 常量已删 / diorama 不再回指任何路由 / 拒绝后栈·屏幕·实例数零变化）；`s0_3_router` 74 → **76 断言**（空壳基线：指纹恒为 `StrategicMap:Node3D:0`、`#main` 组 0、地形 0、seed 派生值为空，并注明 S1.2 才接线）；`s0_2_boot` 把"日志含地形行"改成**反向断言**"不含 `[terrain]`" —— 开机确实换了场景，而不是偷偷还加载着 diorama |
| `A-` 全量 | 窗口 `--all` **23 用例 / 0 失败 / 0 跳过 / 956 断言 / 131.1s**、退出码 0；headless `--all` **23 / 0 失败 / 6 跳过 / 702 断言**、退出码 0；headless 启动门禁 0 条 `ERROR` / `WARNING` / `SCRIPT ERROR` |
| `B-` 6 机位 | diorama 专用批次两条独立进程（`.shots/s10d_a` / `s10d_b`）：**6/6 sha256 与 `docs/ENGINEERING.md` §4 基线逐位相等**、两轮互等 —— 主场景换掉之后，夹具的像素一个都没动 |
| 坑 1（最重要） | **缺省批次从此拍不到世界**：空壳没有相机/网格。于是 `s0_4_overlay` 的"draw_calls>0"、`s0_6_repro` 的反向对照、`s0_4_cost` 与 `s0_3_slots` 的"两张图必须不同"全部假红。处置：这些用例的截片子进程统一显式 `--scene=diorama`，"窗口真在渲染"的证据改由 `s0_4_cost`（headed，120 实体）与 diorama 批次承担 |
| 坑 2 | `_world_fingerprint()` 原本走 `#main` 组，空壳没有该组 ⇒ 指纹恒为空、"逐条一致"会**真空通过**。改成 `_world_fingerprint(root: Node = null)`：缺省仍走 `#main`（overlay 用例不受影响），路由用例显式传 `current_scene` |
| 坑 3 | 白名单收紧回 0 之后，**注释里的** `res://scenes/dev/` 也算泄漏（`capture.gd` / `scene_router.gd` 各一处被 `s0_5_doc_conventions` 抓住）。改写注释而不是放宽登记表 —— 这条门禁的用处正是"夹具别漏进正式构建" |
| 现在的产品状态 | 游戏开机落在**空的世界**（无相机、无内容、无导航入口）：这是 S1.0 的设计终点，不是缺陷。可玩入口要等 S1.2 填战略图、S1.4 接菜单 |

**依赖与风险**：M0 全部。风险：一步同时动三处事实源 ⇒ 拆 4 子步、每步独立提交，任一步红即 `git revert` 该步，**不"边修边推进"**。
**状态**：✅ 已完成（S1.0a / S1.0b / S1.0c / S1.0d 全部落地）

### S1.1 世界数据模型与程序化生成

**计划描述**
- `WorldData` 资源结构：`Regions`（生物群系分区）/ `Settlements`（城镇/村庄/要塞）/ `Roads`（道路图）/ `Factions`（势力与外交态）/ `Parties`（AI 队伍初始态）。
- `WorldGen`：由 seed 决定论生成，复用 `FastNoiseLite` 分层噪声 + `Terrain` 的高度/生物群系函数。
  - 生成与渲染必须共用**同一个** `height_at(x,z)`（新建 `scripts/world/height_field.gd` 供战略尺度使用，
    **不回改** `scripts/world/terrain.gd` —— 后者是 6 机位 `B-` 基线的承载者）。
  - 聚落落点：拒绝水面与 `slope > 0.35`；同类聚落有最小间距；落不下则重试**有上限**，上限内失败换噪声偏移（不是死循环）。
  - 道路图：最近邻骨架 + 对孤立分量补边直到连通（这就是下方"拓扑连通"断言的实现方式）。
  - 一切随机走 `Rng` 具名子流 `world_gen`，**禁止**全局 `randf()`（守卫会红）。
  - 序列化统一走 `Canon`（`scripts/core/canon.gd`，**S1.1a 已落地**：键按码点升序 + 整数值写整数、
    非整数 `%.6f` + LF + 顶层 `schema`）—— 否则"两次序列化字节一致"无法成立。
    格式与两处实测更正见 `docs/ENGINEERING.md` §9。
- 集中参数表（**2026-10-19 定为可改默认值**，落在 `data/world/gen_params.json`）：地图 2400×2400 单位、region 6–9 个、聚落 12 村庄 + 4 城镇 + 4 要塞、势力 3 个、同时活动 AI 队伍 24 支。
  - **这些数不是定案**：它们是 `gen_params.json` 的初值，安全区间为 地图 600–4000 / region 4–12 / 聚落 8–40 / 势力 2–5 / 队伍 4–40。
  - 改任一值必须重跑 `s1_1_gen`、`s1_1_variety`、`s1_10_soak`，并在 §16 登记（因为 S1.10 的 FPS 与内存判据是按 20 聚落 / 24 队伍标的）。
  - 参数校验：越界只 **clamp + 告警**，不崩溃（避免"改错一个数导致游戏起不来"）。
- **手工锚点覆盖表**（`data/world/anchors.json`）：手工钉死关键地标坐标/名称，避免"程序化生成的平庸感"。锚点**优先级最高**：表中指定的聚落坐标直接采用，生成器只负责周围地形适配。

**验收标准**
- `A-` 同 seed 生成两次，`WorldData` 序列化字节完全一致（确定性）。
- `A-` 换 seed 后，至少 3 项宏观指标变化：聚落数 / 海岸线长度 / region 面积分布（用例 `s1_1_variety`）。
- `A-` 拓扑连通：每个聚落都能经道路或合法陆路到达（图连通性断言）；无聚落落在水面或坡度 > 阈值的格子上。
- `A-` 锚点表生效：指定锚点的生成坐标与表中 100% 一致。
- `C-` 单次世界生成耗时 < 800ms。
- `B-` 输出 3 张不同 seed 的俯视全局图，聚落/道路/势力色可辨识。

**依赖与风险**：M0 全部。风险：纯程序化的"设计感缺失" → 锚点表 + 后续人工复核。

**批次拆分（2026-10-20 对齐定稿）**

一次做完会把五类红混在一起（序列化 / 生成器 / 拓扑 / 性能 / 像素），所以按依赖切 4 批：

| 批 | 范围 | 交付物 | 覆盖的验收项 | 状态 |
|---|---|---|---|---|
| 1（S1.1a） | 序列化地基 + 参数表 | `scripts/core/canon.gd`、`scripts/world/gen_params.gd`、`data/world/gen_params.json`、用例 `s1_1_canon` / `s1_1_params` | 为 `A-` 的"同 seed 字节一致"提供唯一出口；参数表初值 + 安全区间落地 | ✅ 已验收 2026-10-20（`7e7a001`） |
| 2（S1.1b） | 战略高度场与 region 划分 | `scripts/world/height_field.gd`（新建；从 `terrain.gd` **复制**而非继承）、`scripts/world/regions.gd`（新建；Voronoi 划分）、`gen_params.json` 扩 4 个高度字段、用例 `s1_1_height` / `s1_1_regions` | `A-` region 面积分布；与渲染共用同一个 `height_at` 的**唯一实现**先落地 | ✅ 已验收 2026-10-20（`c36d8e7`） |
| 3（S1.1c） | 聚落 / 道路 / 势力 / 队伍 + 手工锚点 | `scripts/world/world_data.gd`、`data/world/anchors.json` | `A-` 拓扑连通 / 不落水面 / 锚点 100% 生效 | ✅ 已验收 2026-10-20 |
| 4（S1.1d） | 序列化 + 宏观指标 + 耗时 | `WorldData.to_dict()/to_text()/metrics()`、用例 `s1_1_gen` / `s1_1_variety` | `A-` 同 seed 字节一致 / 换 seed 三项指标变化 / `C-` < 800ms | ✅ 已验收 2026-10-20 |
| — | 三张俯视全局图 | `B-` | ✅ **已裁定（2026-10-20 用户）：并入 S1.2 交付** —— 俯视图要有战略相机与地形渲染才能拍，二者都在 S1.2；本规划**不为它新建临时预览场景**，也不降级成占位图，S1.1 台账里保留"`B-` 由 S1.2 补拍"的显式欠账（**2026-10-21 结清**：三张 plate 见 §6 批 4 与 `.shots/s12d/global_20250929`、`global_20250930`、`global_20251001`） | ✅ 并入 S1.2 |

**S1.1a 落地与验收记录（2026-10-20）**

| 项 | 结果 |
|---|---|
| 改动 | 新增 `scripts/core/canon.gd`（`class_name Canon`，纯静态四入口 `to_text` / `from_text` / `canonicalize` / `write_file`，**不占 autoload**）；新增 `data/world/gen_params.json`（`schema: 1` + 8 个字段）与 `scripts/world/gen_params.gd`（`class_name GenParams`：`DEFAULTS` / `RANGES` / `SETTLEMENTS_RANGE` / `load_from()` / `validate()`，纯函数无日志）；新增用例 `s1_1_canon` **53 断言**、`s1_1_params` **100 断言**；`s0_5_doc_conventions` 90 → **102 断言**（`class_name` 12 → 14、`Canon` 从"未实现"改为"已落地"并断言三个入口都在、编造锚点 ① 换成 `Canon` 支持 `Vector3` 直写）；文档同批更新 `ENGINEERING.md` §1 / §7.2 / §9 / §5 陷阱 23 |
| 契约两处实测更正 | ① `String.unicode_compare` 在 Godot 4 **不存在**（照文档写会编译失败）⇒ 键序改用 `Array.sort()`（码点序）；② `JSON.parse` 把**每个**数字都变 float（`12` → `12.0`、`-0` → `0.0`）⇒ 纯 `%.6f` 永远无法"读回再写"一致，改为**整数值写整数、非整数 `%.6f`**。两处都写进 `ENGINEERING.md` §9.5 与 §5 陷阱 23 |
| `A-` 序列化确定性 | `s1_1_canon` 53/53：两次序列化逐字节相同、读回再写幂等（连续两轮）、乱序插入输出相同、数组保序；`2400.0` → `2400`、`2.5` → `2.500000`、`-0` → `0`、`-1e-9` → `0.000000`、`1e20` 不用科学计数法；末尾**恰好一个** LF、无 CR、无 BOM、中文不转 `\uXXXX`；**fail-fast**：`Color` / `Vector3` / 非字符串键 / `NAN` / 缺 `schema` / `schema: 1.5` / 自引用结构各自失败并给出键路径（`$.a.b[1]`）；**反向对照**：手写未排序 JSON ≠ Canon 输出，规范化后键序确为 `a, b, schema` |
| `A-` 参数表 | `s1_1_params` 100/100：表文件逐字节等于自己的 `canonicalize()` 结果；8 个初值 = 本节数值且全在安全区间；`load_from()` 真表**零告警**；越界 5 例 clamp + **恰好 1 条**告警；类型错 / 未知键 / 缺键 / 非整数逐项告警且只影响该字段；`regions_min > regions_max` 自动修正；聚落总数 48 → 40（裁 `villages` 到 32）、0 → 8（补 `villages`）；`schema: 99` 整表拒读、数组根拒读、缺文件 / 非 JSON 回退默认且不崩 |
| `A-` 全量回归 | 窗口 `--all` **25 用例 / 0 失败 / 0 跳过 / 1119 断言 / 134.7s**、退出码 0；headless **25 / 0 失败 / 6 跳过 / 865 断言 / 31.0s**、退出码 0；启动门禁 0 条 `ERROR` / `WARNING` / `SCRIPT ERROR` |
| `B-` 6 机位（"没碰渲染"的硬证据） | diorama 专用批次两条独立进程（`.shots/s11a_cam_a` / `s11a_cam_b`）：**6/6 sha256 与 `ENGINEERING.md` §4 基线逐位相等**、两轮互等 —— 本步只加数据层，像素零变化 |
| 明确未动 | `save_system.gd` 的写出路径**未改**（改了会让 9 槽位 / 原子写用例的字节断言全变；切 `Canon` 留 **S1.9**，见 `ENGINEERING.md` §9.3）；`terrain.gd`、任何场景、autoload 数量（仍 **9 / 10**）零改动 |
| 坑 | ① 新增 `class_name` 后必须 `--headless --import` 重建 `.godot/global_script_class_cache.cfg`，否则 `--script` 直接 `Identifier "Canon" not declared`（`ENGINEERING.md` §5 陷阱 1 的同类）；② 测试写法坑：`{1: "x"}` 这种"根缺 schema"的字典会**先**被 schema 检查拦下，想验"非字符串键"必须同时给出合法 `schema`；③ 见 §5 陷阱 23 |

**S1.1b 落地与验收记录（2026-10-20；提交 `c36d8e7`）**

**S1.1c 落地记录（2026-10-20；提交 `7838a49`）**

| 项 | 结果 |
|---|---|
| 改动 | 新增 `scripts/world/world_data.gd`（`class_name WorldData`，`RefCounted`，**不占 autoload**：`build()` 五步 = 锚点优先 → 配额补点 → 最远点采样定首都 → 最近邻骨架 + 补边至单连通 → 队伍挂母城；`load_anchors()` 静态读表；`fingerprint()` 供决定论比对）与 `data/world/anchors.json`（`schema: 1` + 3 条锚点 `town_seat` / `village_seat` / `fortress_seat`，Canon 规范形式，406 字节）；`gen_params.json` / `GenParams` 再扩 2 个**米制浮点**字段（`settlement_min_spacing` 120 / `settlement_slope_limit` 0.35，`FLOAT_FIELDS` 4 → **6**，安全区间 40–600 / 0.05–1.0）；新增用例 `s1_1_world` **308 断言**；`s1_1_params` 145 → **159**；`s0_5_doc_conventions` 106 → **108**（`class_name` 16 → 17） |
| 落点四条闸门 | ① 离地图边界 ≥ 80 m（`MAP_MARGIN`）；② 不落水（`HeightField.is_water`）；③ 坡度 ≤ `settlement_slope_limit`；④ 与所有已放聚落距离 ≥ `settlement_min_spacing`。每点最多试 `MAX_PLACE_TRIES = 200` 次，用完仍放不下 ⇒ **告警 + 按实际数量降级**（`ok` 仍 true）。队伍只查 ①②③。实测默认地形上 `slope ≤ 0.35` 的陆地格只占 **38.7%**（中位坡度 0.42）⇒ 这两个阈值必须参数化，否则"能放几个"会随地形悄悄变 |
| 道路 = 图，不是网格 | 每条边只记 `{a, b, length}`（聚落 id + 直线距离，米）；每点连最近 `ROAD_K = 2` 个邻居（去重）→ 仍有多个分量时反复挑"跨分量最近点对"补边直到单连通。**避水寻路 / 路面网格 / 桥隧留给 S1.2**。连通性断言用**独立实现的 BFS**，不调用被测的并查集 |
| `A-` 锚点 100% 生效 | 3 条锚点坐标**逐位**等于表、`kind` 跟随表、`anchor = true`，且**排在最前**（先钉后撒）；`_anchor_mismatches()` 统计失配数 = **0**。反向对照：把表里一条坐标 +100 m 后新世界跟随新表（仍 0 失配），但拿旧表核 ⇒ **恰好 1 条**失配（证明断言不是恒真） |
| `A-` 不落水面 / 坡度 | 20 个聚落 + 24 支队伍全部通过 `_world_violations()`（水面 / 坡度 / 间距三重扫描）零违规；实测最小聚落间距 **131.0 m** ≥ 120 m。反向对照：把 1 个聚落挪到海角 (−1190, −1190) ⇒ 立即报"落在水面" |
| `A-` 拓扑连通 | 连通分量 **1**、边数 **24** ≥ n−1 = 19、无自环 / 无重边、每条边 `length` = 两端直线距离（±0.001）、总长 **7936.7 m** = 各边之和。反向对照：把某聚落的边全删掉 ⇒ BFS 报 **≥ 2** 个分量 |
| 决定论 | 重放同一 `stream.state` 两次构建，`fingerprint()` 逐位相同且两次都 **0 告警**；反向对照：换 seed（同时换 `HeightField` / `WorldRegions`）后指纹不同且 **19 / 20** 个聚落坐标变化（差异不只在 seed 那一行） |
| 势力与队伍（实测） | 3 个势力，首都 = 最远点采样选出的城镇（`town_1` / `town_2` / `town_seat`），三方各 **8** 支队伍（轮流分配，相差 ≤ 1），每支队伍的母城存在且同势力；聚落按 region 分布 **4 / 3 / 6 / 2 / 2 / 1 / 1 / 1** |
| 降级路径 | `spacing = 900 m` ⇒ `ok` 仍 true、有告警、数量 &lt; 20、**3 s 内**结束（不是死循环）；`kind = castle` 与落水锚点各留一条告警、配额照旧补齐 20 个 |
| `C-` 代价（实测） | 一次 `build()` 中位 **2.31 ms**（min 2.23 / max 2.40，5 次；批 4 的 800 ms 预算含序列化，本批只量生成） |
| `A-` 全量回归 | 窗口 `--all` **28 用例 / 0 失败 / 0 跳过 / 1570 断言 / 129.2s**、退出码 0；headless **28 / 0 失败 / 6 跳过 / 1316 断言 / 31.7s**、退出码 0；启动门禁 `--headless --quit-after 60` 退出码 0、**0 条** `ERROR`/`WARNING`/`SCRIPT ERROR` |
| `B-` 6 机位 | diorama 专用批次两条独立进程（`.shots/s11c_cam_a` / `s11c_cam_b`）：**6/6 sha256 与 `ENGINEERING.md` §4 基线逐位相等**（`6e21376e` / `5bde250f` / `1a606659` / `729db4c1` / `f7725a5f` / `c0858f50`），且两轮互等 |
| 明确未动 | `terrain.gd`（6 机位基线承载者）、任何场景、任何 autoload（仍 **9 / 10**）、`save_system.gd`、渲染管线、批 2 的两个类 —— 零改动 |
| 坑 | ① `WorldData.KINDS` 是单数、参数表键是复数，第一版直接 `params.get(kind, 0)` ⇒ 三个配额全取到 0、锚点全被跳过、`settlements` 为空，而**没有任何报错**（见 `ENGINEERING.md` §5 陷阱 25）；② 反向对照"删一条边"不成立 —— 最近邻骨架本身带环，删一条边图仍连通，改成"删掉某个聚落的全部边"才必然断开 |
| 提交 | `7838a49`（feat(world): S1.1c 聚落/道路/势力/队伍与手工锚点（S1.1 批 3）），紧随的 docs(roadmap) 提交回填本哈希 |

**S1.1d 落地记录（2026-10-20）**

| 项 | 结果 |
|---|---|
| 改动 | `scripts/world/world_data.gd` 新增 `to_dict()` / `to_text()`（返回 Canon 的 `{ok, text, reason}`）/ `metrics()` / `_sorted_by()`；**无新文件、无新 `class_name`（仍 17）**、参数表字段不变、不碰 autoload（仍 9 / 10） |
| 序列化契约 | 顶层 `{schema: 1, world_seed, params, metrics, settlements[], roads[], factions[], parties[]}`，键按码点升序（由 Canon 保证）；四个数组**各自按稳定文本键排序**（`id` / `a`）后再写，**不依赖生成顺序**；坐标**不取整** —— 取整会改动批 3 已验收的落点，而 Canon 的 `%.6f` 已经保证字节稳定 |
| `A-` 同 seed 字节一致 | `s1_1_gen` **52 断言**：同一入口状态两次构建文本**逐字节相同**（10 298 字符）、指纹相同；读回再写**幂等**、文本 = 自己的 `canonicalize()`、无 CR、末尾恰好一个换行；顶层键序实测 `[factions, metrics, params, parties, roads, schema, settlements, world_seed]`；反向对照：换 seed 后文本与指标都不同 |
| `A-` 换 seed 指标变化 | `s1_1_variety` **33 断言**：三个 seed（20250929 / 20250930 / 31415926）两两文本不同；四项指标 **4 / 4** 全部随 seed 变化（海岸线 9216 / 9792 / 9216 m、陆地占比 0.629 / 0.621 / 0.610、region 面积比 9.69 / 7.34 / 10.58、聚落按 region 分布向量、道路总长）。**刻意不用「聚落数」**：默认配额固定（12 + 4 + 4）⇒ 它恒为 20，恒真断言证明不了任何事；用例把这一点显式断言成「恒为 20」 |
| `C-` 代价（实测） | 整条链（`HeightField` + `WorldRegions.build()` + `WorldData.build()` + `to_text()`）三次 **15.36 / 15.32 / 16.01 ms**，最慢 **16.0 ms** ≪ 800 ms（headless）；与批 2 的 region 10.5 ms、批 3 的 build 2.3 ms 分项相符 |
| 抓到的真实缺陷 | 用例共享同一条 `Rng.stream("world_gen")`：**不把子流拨回起点**，同一个 seed 会因前面用例多抽了几个数而生成不同的世界 —— `--all` 里跑出 **26 条边 / 8916.9 m**，单跑是 **24 条 / 7936.7 m**。夹具改为 `Rng.reset()`（= 开局状态）后两种跑法逐字节一致 ⇒ 记入 `ENGINEERING.md` §5 陷阱 26，并把「S1.2 组合根先 `Rng.reset()` / `seed_from(world_seed)` 再建世界」写成 S1.2 的开工前置 |
| 明确未动 | `terrain.gd`、任何场景、渲染管线、autoload（仍 9 / 10）、`save_system.gd`、批 2 / 批 3 的生成逻辑与参数表 —— 零改动（本批只在 `WorldData` 末尾追加读接口） |
| `A-` 全量回归 | 窗口 `--all` **30 用例 / 0 失败 / 0 跳过 / 1655 断言 / 130.2s**、退出码 0；headless **30 / 0 失败 / 6 跳过 / 1401 断言 / 31.2s**、退出码 0；启动门禁 `--headless --quit-after 60` 退出码 0、**0 条** `ERROR`/`WARNING`/`SCRIPT ERROR` |
| `B-` 6 机位 | `.shots/s11d_cam_a` / `s11d_cam_b` 两条独立进程：**6/6 sha256 与 §4 基线逐位相等**（`6e21376e` / `5bde250f` / `1a606659` / `729db4c1` / `f7725a5f` / `c0858f50`）且两轮互等 |
| 坑 | ① 引擎会重写 `project.godot`（注释全删、`[shader_globals]` 挪到文件尾），`git status` 变脏 —— 别提交它，`git checkout -- project.godot` 复原（§5 陷阱 27）；② `snappedf(v, 3)` 是把 `v` 吸到 **3 的整数倍**，不是「保留 3 位小数」，指标会被打成 `0.0`；③ 每条边只存 6 位小数，累加会攒出 ~`1e-5` 的差，和内存总和比较必须给 1 cm 容差，不能按浮点末位卡 |

**状态**：🟡 数据层四批全 ✅（2026-10-20）；`B-` 三张俯视全局图 ✅ 已裁定并入 S1.2 —— 该步要等 S1.2 补拍后才算完全闭环

### S1.2 战略地图场景与镜头

**计划描述**
- 复用 `Terrain`/`Style`/`MeshUtil` 生成**低模战略地形**（分辨率分级：全球档粗网格 + 近地档细化），与岛屿美术同一套配色与描边。
- 镜头三档缩放（全球 / 区域 / 近地），正交与透视可切，平移带边界钳制与阻尼，禁止穿地。
- 战略地形与 S1.3 棋子共用同一高度场 API（保证贴地一致）。

**验收标准**
- `B-` 三档缩放各 1 张截图：风格统一、地形起伏可读、**画面中不存在任何立方体/像素块**。
- `A-` 镜头平移不越界、缩放无抖动（连续 10s 移动的轨迹断言：无 NaN、无越界、帧间位移连续）。
- `C-` 全球档三角面数 ≤ 现有岛屿的 1.6 倍，且全球档 FPS ≥ 60。

**依赖与风险**：S1.1。风险：大范围地形生成内存 → 分块生成 + 按需卸载。

**批次拆分（2026-10-20 对齐定稿）**

S1.2 同时要"看见地形"和"镜头好用"，一次做完会把渲染红、手感红、像素红混在一起，所以按依赖切 4 批：

| 批 | 范围 | 交付物 | 覆盖的验收项 | 状态 |
|---|---|---|---|---|
| 1（S1.2a） | 世界入口 / 组合根 | `scripts/world/world_session.gd`（`class_name WorldSession`）、`scripts/world/strategic_map.gd`、`scenes/world/strategic_map.tscn` 接线、用例 `s1_2_boot` | 非验收项，但补掉 S1.1d 登记的 **S1.2 硬前置**（建世界前先重置子流） | ✅ 已验收 2026-10-20 |
| 2（S1.2b） | 战略地形低模网格 | `scripts/world/strategic_terrain.gd`（`class_name StrategicTerrain`）：32 m × 75×75 = 11 250 三角、6×6 分块、水面 + 外缘墨色裙边；用例 `s1_2_mesh` | `B-` 起伏可读、无立方体；`C-` 面数 ≤ 34 611（岛屿 21 632 × 1.6） | ✅ 已验收 2026-10-21 |
| 3（S1.2c） | 镜头三档 + 边界钳制 | `scripts/world/strategic_camera.gd`（`class_name StrategicCamera`）：GLOBAL 2600 / REGION 700 / LOCAL 170 m、正交 ⇄ 透视（`P`）、平移阻尼、中键拖动、禁止穿地；`WorldEnvironment` + `Sun` + `DayNight` 固定正午舞台；用例 `s1_2_camera` | `A-` 连续 10 s 轨迹（无 NaN / 不越界 / 帧间连续）；`B-`/`C-` 留给批 4 | ✅ 已验收 2026-10-21 |
| 4（S1.2d） | 截图与收口 | `B-` 三张截图（含 S1.1 欠账的俯视全局图）+ 实测数据 + 台账 | 全部 | ✅ 已验收 2026-10-21 |

**S1.2a 落地记录（2026-10-20）**

| 项 | 内容 |
|---|---|
| 新增文件 | `scripts/world/world_session.gd`（**第 18 个** `class_name`，`RefCounted`，不占 autoload）、`scripts/world/strategic_map.gd`（场景根脚本，无 `class_name`） |
| 改动文件 | `scenes/world/strategic_map.tscn`（根节点挂脚本；仍**零子节点、无相机**）、`tools/verify.gd`（新增 `s1_2_boot` + 类名表 18）、`docs/ENGINEERING.md`（§1 / §7.2 / §9.9 / §5 陷阱 28）、`docs/ROADMAP.md` |
| 入口契约 | `WorldSession.boot(rng, seed)` 先 `rng.seed_from(seed)`，再按固定顺序 `HeightField → WorldRegions.build() → WorldData.build()`；`Rng` **以参数注入**（`--script` 下 autoload 标识符不可用，也让用例能注入真身） |
| 失败语义 | `ok` / `errors`（致命，世界不存在）/ `warnings`（降级，世界仍可用）三级；参数表或 region 失败 ⇒ `ok = false` 并保留原因，锚点表坏掉只降级成告警 |
| 用例 | `s1_2_boot`（**31 断言**）：同 seed 两次 boot 文本逐字节相同（10 298 字符）/ 先污染 `world_gen` 再 boot 结果不变，且有**反向对照**证明污染确实会改世界 / 换 seed 必变 / 与既有 `_world_fixture()` 逐字节一致 / 场景实例化后 `session` 非空、零告警、20 聚落 / 无 `Rng` 时不抛异常 |
| `C-` 参考 | 一次 `boot()` ≈ 16 ms（批 4 实测整条链 15.36 / 15.32 / 16.01 ms）；`s1_2_boot` 含 6 次 boot + 夹具 + 场景实例化共 **114 ms** |
| 明确未动 | 渲染 / 相机 / autoload（仍 **9 / 10**）/ 参数表 / 批 1–4 生成逻辑 |

**验收（2026-10-20）**：三项判定 —— ① 世界入口收成唯一函数 WorldSession.boot()（注入 Rng、先重置再建）② 战略图场景批 1 只持有一个 session、不渲染 ③ S1.0 两条「根节点无脚本」断言的判据迁到「脚本是不是入口」（不弱化）—— 均获用户认可，§15 批 1 置 ✅ 已验收。

**S1.2b 落地记录（2026-10-20）**

| 项 | 内容 |
|---|---|
| 新增文件 | `scripts/world/strategic_terrain.gd`（**第 19 个** `class_name`，`Node3D`，不占 autoload） |
| 改动文件 | `scripts/world/strategic_map.gd`（`_ready()` 里把 `session.field` 交给地形；场景**唯一**子节点是 `StrategicTerrain`）、`tools/verify.gd`（新增 `s1_2_mesh` + 类名表 19）、`docs/ENGINEERING.md`（§1 / §7.2 / §9.10 / §5 陷阱 29、30） |
| 网格规格 | `cells = round(map_size / 32)` ⇒ 2400 m 上 **75 格 × 32.0 m**；`75 × 75 × 2 = 11 250` 三角；`_split(75, 6)` ⇒ 13/13/13/12/12/12 |
| 分块 | 6×6：36 个 `Land_` 块 + 按"含水下格"才建的水块（实测 22）+ 1 个 `Curtain` 外缘裙边 = **59 个块节点** |
| 水面 | 只在水下格上铺平面；顶点色 = 深度渐变 + 泡沫 alpha（8 m 内起沫）；材质复用 `water.gdshader`（`Style.water_material()`） |
| 描边取舍 | 陆面**不挂逆壳**（32 m 格距下会糊成黑带），改为"海岸一格墨线 + 外缘裙边墨色顶带"；这是与 `terrain.gd` 的刻意差异，已在 §9.10.3 记账 |
| 色带 | 归一化高度（除以 `max_height` 146 m）：滩 0.075 / 草 0.34 / 高 0.62；海滩按"接触水的干格"定义（纯高度只圈到 3 格），实测 309 格 |
| 用例 | `s1_2_mesh`（**105 断言 / 421 ms**）：结构与预算 / 实测三角数与统计一致 / 顶点有限且落在 ±1200 m / 水面 y 恰为海平面 / 裙边比最低地形再低 55 m / 两次 build 签名逐字节一致 / 换 seed 几何必变 / 场景接线后是唯一子节点 |
| 实测 | 建网格 **68.5 ms**（用例侧计时；产品码不调 `Time.*`，`s0_2_guard` 规则不允许）；高度 −78.24 … +113.26 m；色带 水 2 127 / 滩 309 / 草 1 237 / 高地 1 901 / 雪 51；岩石 22 格 |
| 判据迁移 | `s0_3_router` 的世界基线从「指纹恰为 `StrategicMap:Node3D:0`」改为「形如『根 → 地形 → 块容器』+ 每块都有 mesh + 仍无 `Camera3D`」（76 → 81 断言）；`s0_2_guard` 抓到产品码里 6 处 `Time.get_ticks_usec()`，计时器整体移到用例侧 |
| 全量回归 | 窗口 `--all` **32 用例 / 0 失败 / 0 跳过 / 1805 断言 / 135.3s**；headless **32 / 0 失败 / 6 跳过 / 1551 断言 / 34.3s**；主场景 headless `--quit-after 120` **0 ERROR / 0 WARNING** |
| 提交 | `febdceb`（feat(world): S1.2b 战略地形低模网格（32 m / 11 250 三角）），紧随的 docs(roadmap) 提交回填本哈希 |
| `B-` 6 机位（"没碰渲染"的硬证据） | diorama 六个独立目录各跑一次 `--shots`：**6/6 sha256 与 §4 基线逐位相等**（`6e21376e` / `5bde250f` / `1a606659` / `729db4c1` / `f7725a5f` / `c0858f50`，36 张图全一致） |
| 明确未动 | 相机 / 渲染参数 / autoload（仍 **9 / 10**）/ 参数表 / 水面动画细分 / 块级裁剪 |

**验收（2026-10-21）**：三项判定 —— ① 网格规格（32 m / 75 格 / 11 250 三角 / 6×6 分块，差一格不改格数）② 描边取舍（陆面无逆壳，只有海岸与外缘墨线）③ 判据迁移（`s0_3_router` 的世界基线改判「地形形状 + 每块有 mesh + 仍无 `Camera3D`」，未弱化）—— 均获用户认可，§15 批 2 置 ✅ 已验收。**`B-` 的肉眼判定仍未做**（场景无相机无灯光），随批 4 的三张截图一并判定，不在此处冒充通过。

**S1.2c 落地记录（2026-10-21）**

| 项 | 内容 |
|---|---|
| 新增文件 | `scripts/world/strategic_camera.gd`（**第 20 个** `class_name`，`Node3D`，不占 autoload） |
| 改动文件 | `scripts/world/strategic_map.gd`（`_rebuild_stage()` + `_rebuild_camera()`；舞台与相机都在 `boot()` 里建）、`tools/verify.gd`（新增 `s1_2_camera`、类名表 20、世界基线判据第二次迁移）、`docs/ENGINEERING.md`（§1 / §7.2 / §9.11 / §5 陷阱 31–32） |
| 三档 | GLOBAL 2600 m 正交、yaw 45° / pitch −35.264°、焦点锁中心；REGION 700 m 正交 ⇄ 透视（`P`）；LOCAL 170 m 默认透视、焦点跟随地形高度 |
| 边界与手感 | `bounds_half = 1200 − size_target/2 − 40`（全球 0 / 区域 810 / 近地 1075 m）；平移速度 = `size × 0.35 / s`、阻尼 8/s；缩放缓动 6/s（≈0.35 s 到九成）；中键拖动 1 px ≈ `size / 900` m |
| 防穿地 | 相机 y 先抬到 `height_at(cam) + 3 m` 以上再看向焦点；切档时**当前焦点也钳一次**（缩回全球档不会留在图外） |
| 舞台 | `WorldEnvironment` + `Sun` + `DayNight`（`set_auto_cycle(false)` + `set_time(0.5)` 固定正午）；日/夜玩法仍属 S1.7 |
| 场景结构 | 根 **5** 个子节点：`StrategicTerrain` + `WorldEnvironment` + `Sun` + `DayNight` + `StrategicCamera` |
| 用例 | `s1_2_camera`（**37 断言 / 242 ms**）：档位契约 / 600 帧脚本轨迹（右移 → 第 200 帧进区域档 → 第 400 帧转 yaw）逐帧无 NaN、无越界、帧间位移 ≤ `size×0.35×dt×1.35`、相机不低于地形 3 m / 同脚本两次轨迹哈希相同 + 反向平移不同 / 场景接线（相机 current、舞台固定正午、5 子节点） |
| 实测 | 全球档相机高度 **2026.5 m**、`far` 12 000 m；600 帧最大帧间位移 **7.45 m**；缓动 1 s 后跨度实测 **700.0 m**；用例输出 `ERROR:` 行 0 |
| 判据迁移（第二次） | `s0_3_router` 的世界基线从「根 → 地形、仍无相机」改为「根 → 地形 + 舞台 + 相机（5 子节点）+ 视口恰有一个 current 相机」（81 → **85 断言**）；仍是能力等价替换 |
| 全量回归 | headless **33 用例 / 0 失败 / 6 跳过 / 1594 断言 / 44.6 s**；窗口 **33 / 0 / 0 / 1848 断言 / 157.5 s**（其中 `s0_3_slots` 命中既有偶发 flake，单跑 20.1 s PASS，§16 已登记）；主场景 headless `--quit-after 120` 退出码 0、2 行日志、0 ERROR/WARNING |
| `B-` 6 机位 | 两轮各拍 6 张（`.shots/s12c_a` / `s12c_b`）：**6/6 与 §4 基线逐位相等**且两轮互等 —— 相机与舞台的加入没有碰岛屿夹具的像素 |
| 提交 | `6c9791f`（feat(world): S1.2c 战略三档镜头 + 边界钳制），紧随的 `docs(roadmap)` 提交 `3d26aea` 回填本哈希 |
| 明确未动 | `B-` 三档截图与 `C-` FPS 采样（批 4）/ 地形网格 / S1.1 数据 / autoload（仍 **9 / 10**）/ `camera_rig.gd` |

**验收（2026-10-21）**：三项判定均获认可 —— ① 三档数值与锁定（2600 / 700 / 170 m；GLOBAL 锁正交等距 + 焦点锁中心）② 手感与钳制（平移 0.35/s + 8/s 阻尼、滚轮整档 6/s 缓动、边界公式、防穿地 +3 m、切档时当前焦点一起钳）③ 决定论与判据迁移（`step()` 为唯一积分入口；`s0_3_router` 世界基线第二次迁移 81 → 85 断言，能力等价不弱化）。`ROADMAP` §15 批 3 置 `✅ 已验收`。

### S1.2d 落地记录（2026-10-21，批 4）

| 项 | 内容 |
|---|---|
| 取景台 | `scripts/dev/strategic_shots.gd` + `scenes/dev/strategic_shots.tscn`（**dev-only**）：只读 `--seed=` 与 `--tier=global/region/local`；`--shots` / `--warmup=` / `--frames=` / `--out=` 仍归 `capture.gd`。`build(seed, tier)` 公开，供用例证明两个旋钮真的换了世界 |
| 取景主体 | 「低地（`height_at ≤ 40 m`）优先 → 海拔 → 距中心距离」选**真实聚落**（确定性）。第一版按“最近聚落”选，seed 20250929 正好选中 92 m 的高原村庄，局部图拍成全白/青平面 —— 取证工具选错主体，图就没有证据力 |
| 落位接口 | `StrategicCamera.snap_to_target()` + `focus_on(x, z)`：截图必须落到档位终值（缩放缓动 6/s，抓帧会抓到变焦中途，同档两次不是同一张图）；`step()` 与全部已验收数值未动 |
| 帧率探针 | `tools/perf_map.gd`：逐档 2 × 0.5 s、**强关 vsync**（否则量的是显示器刷新率）、按档读 `RENDER_TOTAL_PRIMITIVES/DRAW_CALLS`；**反向对照**再量一次“隐藏地图的空天空”，两者分不开就自评 `pass=false` |
| `C-` 实测 | GLOBAL **994.8 fps** / 16 920 三角 / 59 draws；REGION **960.0** / 10 764 / 29；LOCAL **1034.0** / 5 238 / 11；空天空 **1 510** fps |
| 三角面核对 | 16 920 = 陆面 11 250 + 水面 4 470 + 裙边 1 200，与网格统计逐个对上；上限 34 611 |
| 用例 | `s1_2_perf`（**26 断言 / 6 457 ms**，`kind="headed"`，headless 自动 SKIP）：三档 ≥ 60 fps、全球档 prims == 16 920 且 ≤ 34 611、draws ≤ 120、空天空 > 最慢档 × 1.5、`build()` 的 seed/tier 与重建时旧世界释放 |
| `B-` 相册 | `.shots/s12d/`：`global_20250929`（`fbd83b40`）/ `region_20250929`（`ce307b39`）/ `local_20250929`（`fdc3cdef`）/ `global_20250930`（`f76e14fe`）/ `global_20251001`（`39a4b9c9`）；**两轮独立进程逐位相同、五张两两不同** |
| `B-` 6 机位 | `--shots --scene=diorama` 重采：**6/6 与 §4 基线逐位相等**（本批只加接口、没动画面） |
| 全量回归 | headless **34 用例 / 0 失败 / 7 跳过 / 36.4 s**；窗口 **34 / 0 / 0 / 149.4 s**（`s0_3_slots` 本轮未复现） |
| 提交 | `c6693af`（feat(tools): S1.2d 三档取景台 + 战略图分档帧率探针），紧随的 `docs(roadmap)` 提交 `3d26aea` 回填本哈希 |
| 明确未动 | 三档数值（2600 / 700 / 170 m，S1.2c 已验收）/ 地形网格 / S1.1 数据 / autoload（仍 **9 / 10**）/ `capture.gd` |

**验收（2026-10-21）**：`B-` 由用户判「接受三档现有数值」，`C-` 三条判据（平均 ≥ 60 fps、三角面 ≤ 34 611、反向对照可分辨）全绿；拍图暴露的三条内容级限制随批登记、**不改已验收档位**。`ROADMAP` §15 S1.2 置 `✅ 已验收`，S1.1 的 `B-` 欠账（三张俯视全局图）同时结清。

**已知限制（批 4 登记）**：
1. **海岸阶梯**：32 m 格距在 GLOBAL / REGION 上可见台阶；压到 16 m 会到 ~45 000 三角、超 `C-` 上限 —— 属 S1.2b 已验收的格距取舍，不是镜头问题。
2. **高原长相**：seed 20250929 的岛内部是一整块松石青高原，雪帽整格同色、读起来像“白色剪纸”（整格同色 + 32 m 面片 ⇒ 看不出立体），属 S1.1 世界长相。
3. **LOCAL 内容空**：170 m ≈ 5.3 格，纯地形阶段只有大色块，要等 S1.3 的据点与角色落位。

**状态**：✅ 已验收 2026-10-21（批 1 / S1.2a ✅ 2026-10-20；批 2 / S1.2b ✅ 2026-10-21；批 3 / S1.2c ✅ 2026-10-21；批 4 / S1.2d ✅ 2026-10-21）

### S1.3 队伍棋子与移动

**计划描述**
- 玩家队伍 = 微缩棋子（小人 + 旗帜/单位标记），全部走 `Style.toon` + 逆壳描边。
- 移动方式：点击地面/按键导航，优先沿道路寻路（A\* 或流场），非道路段有速度惩罚。
- 棋子朝向、贴地俯仰随地形；到达判定与转向平滑；行军速度预留负重/兵种接口（M5 接入）。

**验收标准**
- `A-` 寻路确定性：同起终点两次路径完全一致；路径合法（不穿水、不越界）。
- `A-` 沿道路段的移动速度提升比例符合参数（±5%）。
- `A-` 贴地误差：随机 100 个采样点，棋子脚底与 `height_at` 偏差 < 0.05m。
- `C-` 连续行军 60s 无抖动、无贴地穿模（轨迹断言）。
- `B-` 棋子/旗帜特写截图：描边完整、与地形色调统一。
- `D-` 手感：点击移动响应及时、无明显回弹或打滑。

**依赖与风险**：S1.2。风险：大网格寻路开销 → 道路图预计算 + 局部避让。

**分批计划（2026-10-21 对齐）**：四批 —— **`S1.3a`** 棋子本体 + 贴地 + 特写取证通道（→ `A-` 贴地）；**`S1.3b`** 道路图预计算 + 确定性 A\*（水/边界合法，道路提速参数进 `data/world/`，→ `A-` 寻路确定性、`A-` 提速 ±5%）；**`S1.3c`** 移动积分 / 转向 / 到达判定 + 点击与键盘输入 + 接进 `strategic_map.tscn`（`s0_3_router` 第三次迁移，→ `C-` 60 s 轨迹、`D-` 手感）；**`S1.3d`** `B-` 相册（三档 + 特写）+ 台账收口。

**S1.3a 落地记录（2026-10-21）**

| 项 | 内容 |
|---|---|
| 新增文件 | `scripts/world/party_marker.gd`（**第 21 个** `class_name`，`Node3D`，不占 autoload） |
| 改动文件 | `scripts/dev/strategic_shots.gd`（新增 `--party=1` 与 `--span=<m>`；取景台按跨度发布 `Style.pixel_span`）、`tools/verify.gd`（新增 `s1_3_party`） |
| 造型 | 12 个圆柱/球/旗面零件 `combine()` 成**单一 mesh**：底座（墨色唇 + 腿 + 奶油顶面）+ 两段斗篷 + 双臂 + 领口 + 头 + 兜帽 + 旗杆 + **有厚度**的旗面（正面 / 背面 / 四条边墙）；标称 22 m，脚底精确 `y = 0` |
| 描边契约 | 反向外壳挂在 `next_pass`；**切线槽必须写平滑法线** —— `MeshUtil` 的生成器把"面法线"同时写进法线与切线槽，外壳会沿各自面法线炸成散三角片，正常线宽下描边**完全不可见**（本批实测：线宽拉到 120 才看到几道碎屑）。`_with_smooth_tangents()` 按面积加权重算、只写切线槽，着色仍走面法线保面着色 |
| 阵营 | `FACTION_KEYS = ["cloth", "water_deep", "cloth_alt", "plinth"]`；换色只重写顶点色，不重建几何 |
| 贴地 | `place_at(x, z)` 把 `position.y` 设为 `height_at`；`metrics().min_y == 0` 是同一件事的另一半前提，两条一起才叫"脚底贴地" |
| 用例 | `s1_3_party`（**37 断言 / 86 ms**）：结构（单一 surface / 556 三角 / 1668 顶点 / 21.74 m / 占地 ≤ 12 m）· 描边契约（`next_pass` + `enabled=1` + **1494** 个顶点的切线槽是平滑法线）· 贴地（100 点最大偏差 0.00000 m、正负 52 / 48，配 `min_y = 0`）· 朝向（四方向 + ±π 回绕 + `facing ∈ (−π, π]`）· 阵营换色不重建几何 · 两次构建逐字节一致 |
| 全量回归 | headless `--all` **35 用例 / 0 失败 / 7 跳过（仅窗口态）/ 35.8 s**，退出码 0 |
| `B-` 取证 | `.shots/s13a/party_local`（LOCAL 170 m，sha256 `55aa66e6…`）、`.shots/s13a/party_close`（`--span=40` 真特写，`eebe7950…`） |
| 提交 | `6aefccc`（feat(world): S1.3a 队伍棋子本体 + 贴地 + 特写取证），紧随的 `docs(roadmap)` 提交 `3d26aea` 回填本哈希 |
| 明确未动 | 寻路 / 移动积分 / 输入 / `strategic_map.tscn` 接线（批 2–3）/ autoload（仍 **9 / 10**）/ 三档数值 |

**验收（2026-10-21）**：用户判定 `A-` 贴地（100 点最大偏差 0.00000 m + `min_y = 0`）与描边契约（`next_pass` 挂上且切线槽是平滑法线）成立，接受棋子现造型与配色，§15 批 1 置 `✅`。

**S1.3b 落地记录（2026-10-21）**

| 项 | 内容 |
|---|---|
| 新增文件 | `scripts/world/travel_graph.gd`（**第 22 个** `class_name`，`RefCounted`，不占 autoload）、`data/world/travel_params.json` |
| 参数表 | `grid_m 32` / `road_speed_bonus 0.35` / `slope_cost 1.6` / `water_margin 1.5`（米）/ `max_expanded 20000`；契约同 `GenParams`（越界钳制 + 告警、缺字段兜底、`schema` 越高整表拒绝），用例另断言"文件逐字节等于自己的 Canon 规范化结果" |
| 图结构 | 2400 m / 32 m = **75×75 = 5625 格**；可走 **3364** / 水 **2261**。可走 = 格心 + **四角**都高于 `water_level + 1.5 m`；对角另要求两个正交邻居可走（不许切角穿水） |
| 道路 | 19 条聚落直线用整数 DDA 栅格化成 **216** 个道路格（总路长/格距 = 248 的 0.87×）；**穿水 0 格** —— 穿水的格只记账，不会因此变可走 |
| 成本模型 | 每米系数：地面 `1 + 1.6 × slope`、道路 `1/(1+0.35) = 0.74074`；一步 = 步长 × 两格系数均值。同一张表供 `speed_factor_at()`（路上恒 1.35，b3 的移动积分直接读） |
| 决定论 | 二叉堆 `(f, 节点序号)` 双键全序 + 8 邻居固定展开序 + octile 启发式乘**全局最小系数**（乘 1.0 会让 A\* 不再最优）；同实例两次、重建图后 `path_key` 逐位一致，换 seed 必变 |
| `A-` 实测 | 建图 **46.7 ms**；最长路 `village_8→fortress_2`（直线 658.6 m）→ **21 点 / 折线 672.9 m / 成本 498.5 / 展开 21 格 / 路上 672.9 m、野外 0 m**；指纹 `21\|289.3956,549.1852\|…`；开/关提速成本比 **0.74074**（= 1/1.35，判据 ±5%）；道路格最慢 1.35 > 地面格最快 0.9871（**全序**，不是平均值） |
| 用例 | `s1_3_path`（**66 断言 / 224 ms**）：表契约（规范化 / 缺字段 / 钳制 / schema 越高拒绝）· 图结构（水陆互斥、路格同量级、穿水记账）· 合法性（零不可走格、零越界、中段单步 ≤ 一格对角、首末段 ≤ 一格 + 半格对角、首末点精确）· 失败原因（水 / 越界分别指名）· 决定论 · 提速 · 换 seed 反向对照 |
| `B-` 取证 | `.shots/s13b/route_region`（REGION 700 m；墨色点 = 路径、沙色点 = 图里的道路格，两层严丝合缝 ⇒ "确实沿路走"可肉眼对照） |
| 本批两个坑 | ① **成本必须对着报出的折线重算**：`_g[goal]` 只覆盖格心到格心，首末两段不在里面 —— 直接返回它会把 498.5 报成 483.9（低 3%）② **零断言用例会静默通过**：GDScript 运行时错误结束协程、`_run_one` 看不到异常，崩在半路的用例显示成绿色 0/0；现改为"零断言即失败"（§5 陷阱 37） |
| 全量回归 | headless `--all` **36 用例 / 0 失败 / 7 跳过（仅窗口态）/ 37.2 s**，退出码 0；主场景 `--quit-after 120` 退出码 0、0 ERROR |
| 明确未动 | 移动积分 / 转向 / 到达判定 / 点击与键盘输入 / `strategic_map.tscn` 接线（批 3）/ `PartyMarker` / `height_field.gd` / autoload（仍 **9 / 10**）/ 三档数值 |
| 提交 | `378c66b`（feat(world): S1.3b 行军图与确定性 A\*），紧随的 `docs(roadmap)` 提交回填本哈希 |

**S1.3c 落地记录（2026-10-21）**

| 项 | 内容 |
|---|---|
| 新增文件 | `scripts/world/party_mover.gd`（**第 23 个** `class_name`，`Node3D`，不占 autoload） |
| 改动文件 | `data/world/travel_params.json`（+`march_speed 24` / `turn_rate_deg 300` / `arrive_radius 6` / `max_pitch_deg 12`）、`scripts/world/travel_graph.gd`（`Params` 四字段 + `turn_rate_rad()` / `max_pitch_rad()`）、`scripts/world/strategic_camera.gd`（`screen_of()` / `pick_ground()`）、`scripts/world/strategic_map.gd`（第 6 个子节点 `PartyLayer` + `_process` + `_unhandled_input`）、`scripts/dev/strategic_shots.gd`（`--march=`）、`tools/verify.gd`（新增 `s1_3_move`，路由/网格用例迁移） |
| 一处数据源 | 速度 / 转向 / 到达半径 / 俯仰全在 `data/world/travel_params.json`；`Params` 只额外给弧度视图，产品码里不写第二遍数字 |
| 积分契约 | ① 每帧 `factor = speed_factor_at()`，`≤0` ⇒ `BLOCKED` ② `budget = 24 × factor × dt` 沿折线推进 ③ 位移按**弧长**记账（`推进前剩余 − 推进后剩余`）④ `remaining ≤ 6 m` ⇒ `ARRIVED`，**不吸附到终点** ⑤ 朝向以 `300°/s × dt` 为上限逼近段方向、`pitch` 夹 `±12°`（只作用于渲染）⑥ 棋子随之落位 |
| 点击移动 | 地形是裸 `ArrayMesh`、没有碰撞体 ⇒ 视线 4 m 步进 + 二分 10 次（实测 0.003 m）；`pick_ground()` 返回**地面高度**；正交档射线起点在地图外（§5 陷阱 38）；水 / 界外各有独立拒绝理由，且**被拒不打断原命令** |
| 接线 | `strategic_map.tscn` 根 **6 个子节点**（地形 + 舞台三件 + 相机 + `PartyLayer`）；`s0_3_router` 第三次迁移（指纹 `Node3D:6` + 三条能力断言：队伍在 / 棋子贴地 / 自带行军图）；`s1_2_mesh` 同步到 6 |
| `C-` 60 s 轨迹 | 3600 帧固定 1/60 步长：贴地 ≤ **0.000004 m**、位移 ≡ `24 × 系数 × dt` ≤ **0.000043 m**、帧间转角 **0.087266 = 300°/s × dt**（顶满上限）、俯仰峰值 **12.00°**、零 NaN、零帧进水；A→B **20.6 s** 到达并停在离终点 **5.497 m** 处，随后改令反向（两段行军） |
| `D-` 手感 | 下单当帧就动 **0.540 m**（不是先原地转身）；到达后 1 s 位移 **0.000000000 m**；改令 20 帧内离旧终点严格变远（不回弹）；点击移动不挪相机焦点 |
| 用例 | `s1_3_move`（**50 断言 / 239 ms**）；`s1_3_path` 加参数钉（24 / 300° / 6 / 12 m·° ，缺字段告警 9 条）；决定论：同一段 300 帧轨迹两次签名逐位一致 |
| `B-`/`D-` 取证 | `.shots/s13c/march_region`（REGION 700 m，1600×900，345 689 B，sha256 `7da08faa…`）：21 点折线与图里道路格重合，棋子走到 58%、离终点 284 m |
| 本批两个坑 | ① 正交射线起点在地图外 ⇒ 越界只能判"已命中"的点（§5 陷阱 38）② 到达吸附 = 最多 6 m 瞬移，且弦长 ≠ 弧长（§5 陷阱 39） |
| 全量回归 | headless `--all` **37 用例 / 0 失败 / 7 跳过（仅窗口态）/ 39.1 s**，退出码 0；主场景 `--quit-after 120` 退出码 0、0 ERROR |
| 明确未动 | **键盘行军（用户决定本批不做）**：方向键已被相机占用，键盘行军要和"选部队 / 编队"一起设计；路径平滑、多队伍 / 编队 / 补给 / 迷雾；`PartyMarker` / `height_field.gd` 未改；`ui_*` 输入未改；autoload 仍 **9 / 10**；三档数值未改 |
| 提交 | pending（feat(world): S1.3c 移动积分与点击移动），紧随的 `docs(roadmap)` 提交回填本哈希 |

**状态**：🟨 进行中 —— 批 1（S1.3a）✅ 2026-10-21；批 2（S1.3b）✅ 2026-10-21；批 3（S1.3c）✅ 2026-10-21；批 4（相册收口）待做

### S1.4 时间与日历系统

**计划描述**
- 全局游戏时间：1 现实秒 = 1 游戏分钟（1x），档位 `暂停 / 1x / 2x / 4x`。
- 日历：时/日/月/年；与 `DayNight` 联动（战略层光照随游戏时间变化）。
- 夜间与季节对移动速度、遭遇概率、补给消耗提供修正接口（数值表可调）。

**时钟收敛（本步的另一半工作，2026-10-19 定）**
现状是**三套时钟并存**，必须在本步收敛为一套，否则 S1.9 的"读档逐字段一致"永远做不干净：

| 现有时钟 | 现状 | 本步处理 |
|---|---|---|
| `Clock`（`scripts/core/render_clock.gd`） | 渲染用，可冻结，`shader_globals/render_time` | **保持渲染专用**，不参与游戏逻辑（S0.6 的确定性建立在它之上，不动） |
| `GameState.game_time` + `DEFAULT_DAY_LENGTH = 170.0` | 0..170 秒的**循环相位**，无日期 | **升级为唯一游戏时钟**：单位改为游戏秒、单向累加、含日期 |
| `scripts/world/day_night.gd` 自己的累计值 | 独立推进 24h 循环 | **改为派生**：只读 `game_time` 求相位，内部光照曲线不变 |

- **换算与历法**：1x 下 1 游戏日 = 1440 游戏秒 = 24 现实分钟；12 月 × 30 日 = 360 日/年。
  `day = floor(t/86400)+1`、`hour = floor(t/3600)%24`、`month = floor((day-1)/30)%12+1`。
- **变速实现 = 每帧执行 N 次完整固定步**（N=0/1/2/4），**不是**放大 delta。
  这样 1x 与 4x 走同一条浮点路径，只是步数不同 ⇒ "4x 跑完 N 日"与"1x 跑完 N 日"逐字段相同（下方断言）。
  代价：4x 时 CPU ×4（24 队伍 × 4 = 96 次/帧，微秒级，可接受）。
- **`day_length` 语义变更 ⇒ 存档必须迁移（schema v1 → v2）**：
  旧档的 `game_time` 是 0..170 的循环相位、不含日期，无法精确还原 ⇒ 映射为
  `day = 1`、`hour = round(old_t / 170 * 24)`，旧值保留到新增字段 `visual_day_length`，
  读档时给**一次性**提示「时间已按新历法重标定」。迁移钩子加在 `SaveSystem.migrations`（S1.9 接线）。
- 暂停沿用 `get_tree().paused`（与 `ESC` 契约一致），`Debug` 的叠加层与 `ToastLayer` 不受暂停影响。

**验收标准**
- `A-` 1x 下 60 现实秒推进 60 游戏分钟（误差 < 1 游戏秒）；2x/4x 速率符合倍率（±2%）。
- `A-` 暂停时：时间不推进，全部 AI 与动画冻结（世界状态哈希前后一致）。
- `A-` 长时间快进：模拟 365 游戏日无溢出/无精度漂移（日期单调、年月日合法）。
- `A-` **倍速等价性**（用例 `s1_4_speed`）：`speed=4` 连续推进 N 游戏日，与 `speed=1` 推进同一 N 日，
  世界状态**逐字段相同**（含 `Rng` 各子流 `state`）。这一条是"变速没改变结果"的唯一证据。
- `A-` **唯一时钟**：`DayNight` 的相位函数对 `game_time` 是纯函数（同 `game_time` 两次求值结果相同）；
  `GameState` 之外无第二处累加游戏时间（静态扫描 + 守卫）。
- `A-` **v1 存档迁移**：人工构造带 `DEFAULT_DAY_LENGTH = 170` 的 v1 快照，迁移后 `hour` 落在 `[0,23]`、
  `visual_day_length == 170.0`、且给出一次性提示；非法 `game_time`（负值/NaN）被拒读而不是崩溃。
- `B-` 同一地图在 04:00 / 12:00 / 21:00 三张截图，光照与 `DayNight` 关键帧一致。

**依赖与风险**：S1.2。风险：① 倍速下的帧率与逻辑耦合 → 逻辑固定步长 + 每帧多次 tick；② **改 `game_time` 语义会波及
`GameState.snapshot()` 的 `SNAPSHOT_FIELDS` 与 `s0_3_*` 四个既有用例** ⇒ 本步必须同时更新字段清单与迁移用例，
不能留到 S1.9 再补。
**状态**：⏳ 未开始

### S1.5 聚落与交互菜单

**计划描述**
- 聚落实体（城镇 / 村庄 / 要塞）在地图上有可见标记与势力归属色，进入范围可交互。
- 交互面板（沿用 brutalist UI）：**补给 / 招募 / 交易 / 任务 / 驻军**；本步先实现「补给、交易、任务列表入口」，招募在 M5、驻军在 S5.5 落地，未实现项必须显式标注"未开放"。
- 面板数据全部来自 `WorldData`，不硬编码。
- **本地化从本步起生效**（2026-10-19 裁定，原 §14 Q2）：本步所有新增文案**一律走 key**
  （`tr("UI_SETTLEMENT_SUPPLY")` 形式），`data/i18n/strings.csv` 本轮只填中文一列。
  数据表里的可读文本（聚落名、商品名）同样只存 `name_key`，**不存明文** —— 否则换语言要改存档。
- **先扩 `UiKit` 再写面板**：本步需要的列表行 / 分页 / 滚动区等控件，先补进 `scripts/ui/ui_kit.gd`
  并复用，**禁止**在 `settlement_panel.gd` 里另写 `_sb()`/`_label()` 之类的样式助手
  （S0.4 批次 1 刚把三份重复实现合一，不能倒退回分叉状态）。

**验收标准**
- `A-` 20 个聚落逐一进入交互无错误，面板字段与 `WorldData` 逐字段一致（用例 `s1_5_settlement`）。
- `A-` 势力归属变化后，标记颜色与交互权限随之变化（断言）；权限表：同势力=全开 / 中立=仅交易 / 敌对=仅补给。
- `A-` **文案零硬编码**：静态扫描 `scripts/ui/settlement_panel.gd` 与 `data/`，除 `strings.csv` 外不得出现
  面向玩家的中文字面量；`strings.csv` 的 key **只增不改**（改名 = 破坏旧存档与旧截图）。
- `A-` **无新增样式助手**：`settlement_panel.gd` 不出现自建 stylebox / 标签构造，全部经 `UiKit.*`。
- `B-` 城镇/村庄/要塞三种面板各 1 张截图，风格与现有 UI 一致（同一套边框/阴影/配色）。
- `D-` 交互路径不超过 2 次点击达成补给与交易。
- `D-` 未开放项（招募/驻军）必须一眼可辨为"未开放"（灰底 + 明确标签），**不允许**隐藏或点了没反应。

**依赖与风险**：S1.1/S1.3。风险：① UI 膨胀 → 复用 `UiKit` 工厂，新控件先抽公共件；
② 本地化 retro-fit 代价远高于初期 ⇒ 从本步第一行代码起就走 key，不留"以后统一改"。
**状态**：⏳ 未开始

### S1.6 遭遇、AI 队伍与追击

**计划描述**
- AI 队伍类型：商队 / 匪军 / 巡逻队 / 领主部队；行为：巡逻 / 追击 / 逃离 / 回城补给 / 避战。
- 视野与速度模型（受兵种、负重、地形、昼夜影响），追击判定距离与逃脱判定。
- 遭遇流程：对峙界面（**交战 / 谈判 / 逃离**）→ 交战按 D1 切入独立战斗场景（本步先接"占位结算"，S2.10 与 S4.8 替换为真实战斗）。
- 遭遇上下文（地形类型、双方兵力、时间、天气）打包成 `BattleContext` 传给战斗场景。

**本步的三个冻结项（2026-10-19 定，M2/M4 依赖它们，不能事后改）**

1. **`BattleContext` / `BattleResult` 字段表在此冻结**（只允许后续**加**可选字段 + 版本号，不许改语义或删字段）：
   ```
   BattleContext = { version:1, source:"encounter"|"quest"|"story",
     terrain:{biome,pos}, time:{game_time,day,hour}, weather:{kind,intensity},
     attacker:{party_id,faction_id,troops,hero_id,morale},
     defender:{…同上}, stake:{loot_money,captives,war_score},
     rules:{kind:"skirmish"|"boss", seed} }
   BattleResult  = { version:1, winner:"attacker"|"defender", rounds,
     losses:{attacker,defender}, loot:{money,food,supply}, captives, flags:[…], placeholder:bool }
   ```
   `hero_id` 本步为空串（单主角固定出身，见 §14 Q4 裁定），M3 起接装备。
2. **占位结算**：`placeholder_resolve.gd` 用 `Rng` 具名子流 `battle_roll` + 兵力/士气/地形修正产出 `BattleResult`，
   固定 `placeholder:true`；面板顶部**必须**显示「占位结算 · 真实战斗在 S2.10 接入」。
   S2.10 只替换 resolver，**不改契约**。
3. **战争迷雾两级**（原 §14 Q9 裁定）：`explored` 布尔图（分块粒度）——已探索 / 未探索。
   未探索区域不画聚落细节、不显示 AI 队伍；进入范围即标记已探索。
   **不做**视线遮挡 / 遮挡射线 / 逐格可见性计算（那是另一个量级的工作，且不影响本步玩法）。

**AI 必须是纯函数**：`ai_director.gd` 的 `static tick(world: Dictionary, dt: float, rng) -> void`，
不碰任何节点/渲染 API —— 因为下面的 soak 用例要在 `--script` 的 headless 下跑 10 个游戏日。
寻路结果缓存，只在目标变化时重算（24 队伍 × 每帧重算会吃掉 60 FPS 预算）。

**验收标准**
- `A-` 无卡死/无退化：24 支 AI 队伍连续模拟 10 游戏日，无 NaN、全部留在地图内、至少完成 1 次回城补给与 1 次追击成功（用例 `s1_6_ai_soak`）。
- `A-` 遭遇触发距离误差 < 5%（对照参数表）。
- `A-` `BattleContext` 字段完整且能往返序列化（用例 `s1_6_context`）。
- `A-` **占位结算确定性**（用例 `s1_6_placeholder`）：同 `BattleContext` + 同 seed 两次结算 `BattleResult` 逐字段相同，
  且 `placeholder == true`、`winner` 只取两个合法值。
- `A-` **状态机防抖**：切换条件带迟滞（连续 N 步满足才切）；构造边界场景（两队距离在阈值上抖动）断言
  10 日内状态切换次数 < 阈值（防止"抽搐"）。
- `A-` **迷雾两级**：未探索区域内的 AI 队伍不出现在可见集合中；进入后出现在集合中；已探索不回退。
- `B-` 对峙界面 + 地图上 24 支队伍分布截图各 1 张。
- `C-` 24 队伍下战略层 FPS ≥ 60（**必须附标尺**：证明这套量法测得出掉帧，参照 `s0_4_cost` 的写法）。

**依赖与风险**：S1.3/S1.4。风险：① AI 抖动 → 行为加冷却与迟滞（hysteresis）；② 本步冻结的 `BattleContext`
被 M2/M4 消费，字段设计不足会在 S2.1 返工 ⇒ 冻结前先跑通占位结算的往返序列化。
**状态**：⏳ 未开始

### S1.7 经济与补给 v1

**计划描述**
- 资源三项：**金钱 / 粮草 / 补给**（前者全局，后两者按队伍）。
- 每日消耗 = 队伍人数 × 系数（随兵种/季节修正）；粮草为 0 触发士气与速度惩罚。
- 聚落价格模型：简单供需均值回归（每聚落每商品一个价格与库存），波动有上下限。

**验收标准**
- `A-` 100 游戏日 headless 快进模拟：金钱/粮草/补给无 NaN、无非法负值溢出，价格始终落在设定区间内。
- `A-` 断粮状态确实触发惩罚标志与速度下降（对照参数，±5%）。
- `A-` 交易后买卖双方的金钱/库存变化守恒（审计断言）。
- `B-` 资源栏与交易面板各 1 张截图。

**依赖与风险**：S1.5。风险：经济数值无参考 → 初值集中在 `data/economy/*.json`，S1.10 做一次平衡审视。
**状态**：⏳ 未开始

### S1.8 事件与任务 v1

**计划描述**
- 模板化任务 4 类：剿匪 / 护送 / 运送 / 讨伐；生命周期：接取 → 追踪 → 完成 / 失败 → 结算。
- 与遭遇、聚落、资源、势力声望打通；全部状态可存档。
- 任务生成也走 seed 决定论。

**验收标准**
- `A-` 4 类模板各跑通 1 次完整生命周期（状态迁移日志断言）。
- `A-` 失败条件可触发：超时失败、护送目标死亡失败各 1 例。
- `A-` 任务状态「存档 → 读档」一致，进行中的任务进度不丢失。
- `B-` 任务列表与追踪 HUD 各 1 张截图。

**依赖与风险**：S1.6/S1.7。
**状态**：⏳ 未开始

### S1.9 大地图存档/读档完整性

**计划描述**
- 全量世界状态 = `seed` + **增量 diff**（聚落归属、AI 队伍位置/状态/目标、任务、资源、时间、玩家队伍、势力外交、价格表）。
  - 为什么不是全量：全量会随生成算法细节膨胀，且"改一个生成参数 ⇒ 全体旧档失效"。`base`（生成参数）+ `diff` 让体积与时间线性可控。
  - 落盘统一走 `Canon`（键字典序 + 浮点 `%.6f` + `\n`），否则"字节一致"只是说法。
- 版本化 + 迁移钩子；读档后世界与存档时刻**逐字段一致**，而非"大致一致"。
- **schema 升到 v2 + 字段清单机制**（2026-10-19 定）：
  - v1 → v2 的迁移在 **S1.4**（`day_length` / `game_time` 语义变更），本步负责把钩子接进 `SaveSystem.migrations` 并补用例。
  - 新增 `GameState.FIELD_MANIFEST` / `WorldData.FIELD_MANIFEST`（有序字段数组），与字段同一次提交更新。
    快照缺项/多项即失败 —— 这是"加了字段忘存档"的唯一有效拦截。
  - 演进规则：**只加不改**（新字段带默认值 + 版本号）；改语义 = 一次迁移；废弃字段先标 `deprecated`、两个版本后才删。
- 写入与读取入口 = §3.5 的 **3×3 九宫格 9 槽**；9 个槽位各自独立完整、互不串档。

**验收标准**
- `A-` 「存档 → 退出进程 → 读档」后逐字段一致：时间、三项资源、24 支队伍位置（误差 < 0.01）、任务状态、聚落归属、价格表（用例 `s1_9_full`）。
- `A-` 读档后继续模拟 10 日，与"不中断模拟"在同一固定 RNG 流下结果一致（确定性断言）。
- `A-` 旧版本存档（人工构造 schema v0）能被迁移读取或给出明确拒绝原因，不崩溃。
- `A-` **v1 → v2 迁移**：带 `DEFAULT_DAY_LENGTH = 170` 的 v1 快照读入后 `hour ∈ [0,23]`、
  `visual_day_length == 170.0`、且给一次性提示；v2 → v2 直读不触发迁移。
- `A-` **字段清单**：把某个可存档字段从 `snapshot()` 里临时删掉，用例必须失败（反向对照，证明清单真能拦）；
  恢复后通过。
- `C-` 单槽存档体积 < 256KB；读写各 < 150ms。
- `A-` **9 槽独立性**：9 个槽位分别写入 9 份不同进度，逐槽读档后状态与各自写入时刻一致、互不串档（用例 `s1_9_slots9`）。
- `A-` M1 全流程**零自动存档**（与 `s0_3_no_autosave` 同口径复测）。

**依赖与风险**：S1.6–S1.8。风险：① 漏存字段 → 用"反射式字段清单"断言，新增字段忘记登记时用例失败；
② 存档兼容性（§13 R5）成本随字段数线性上升 ⇒ 本步之后字段集应尽量稳定，再加字段必须走版本化。
**状态**：⏳ 未开始

### S1.10 大地图打磨与验收（M1 出口评审）

**计划描述**
- 可读性打磨：地标、道路、势力边界、交战热区；UI 缩放在多分辨率下自适应。
- 性能收口与内存回归；产出 `docs/WORLD.md`（地图参数、经济初值、AI 行为表）。
- **M1 出口**：战略层可独立试玩（无战斗亦可闭环游荡、接任务、赚钱、被追击）。

**出口判据要回答的具体问题（2026-10-19 定，路线 B 的门禁）**
按已裁定的排期（路线 B：M1 完整 → M2 → …，不设硬期限），**M1 会先单独撑 7–15 周**，
所以"M1 闷不闷"必须在离开 M1 之前得到真实回答，而不是"能跑就算过"。`D-` 评审逐条记录：

1. 你是否有过一次「粮草见底、被两队追、冲向最近城镇」的经历？（→ 时间压力与追逃是否成立）
2. 30 分钟里你做了几个**真正的选择**（走哪条路 / 打还是谈还是逃 / 在哪补给 / 接哪个任务）？目标 ≥ 1 个/分钟。
3. 有没有一次"因为路远而放弃某个目标"？（→ 地图尺度是否有意义）
4. 有没有一次"打赢后拿到的东西让我想去打下一场"？（→ 成长回路是否闭合）

**≥2 个"否"的处置**：先加**时间压力**（粮草消耗更快 / 敌人更主动），**不要**加系统；
若仍不成立，再按 `docs/spec.md` §2.2 的触发条件重新讨论排期（而不是闷头进 M2）。

**验收标准**
- `B-` 1600×900 / 1920×1080 / 2560×1440 三档截图：UI 不错位、地图元素可辨识。
- `C-` 全球档与区域档均 ≥ 60 FPS；20 分钟连续游玩进程内存漂移 < 5%（分块卸载要真释放，采样 `Performance.MEMORY_STATIC`）。
- `D-` 你实机试玩 20 分钟并确认："地图有探索欲、道路与聚落关系可读、追逃有压力"，且上面四问逐条作答。

**依赖与风险**：S1.1–S1.9。风险：M1 是**唯一没有战斗的一段**，若四问判负，问题几乎总在"压力不足"而不是"内容不足" ⇒ 优先调参不优先加系统。
**状态**：⏳ 未开始

---

## 7. 里程碑 M2：Boss 战（横版 1v1 战斗内核）

> 目的：实现你的核心卖点。弹反 / 闪避 / 蓄力三者的攻防转换循环，Boss 阶段化行为，以及战斗与大地图的往返闭环。

### S2.1 战斗场景框架与横版镜头

**计划描述**
- `BattleScene` 基类（战斗场景通用：入场、倒计时、结算、退出）+ 一个 diorama「剧场式」横版舞台场景。
- 横版正交侧视相机：锁定侧视方向、轻微推移/推近、锁定构图；**Boss 战场合不出现立方体舞台**（用超椭圆棱柱与低模地形）。
- 与 `SceneRouter` 打通：从 S1.6 的 `BattleContext` 进入，结算后回流。

**验收标准**
- `A-` 「大地图遭遇 → 战斗 → 返回」后战略层时间/位置/资源无丢失（用例 `s2_1_flow`）。
- `A-` 进出战斗场景后节点数与内存回到基线 ±2%；耗时 < 1.2s。
- `B-` 横版构图截图 2 张：角色剪影清晰、描边完整、无方块元素。
- `C-` 战斗场景空载 ≥ 60 FPS。

**依赖与风险**：S1.6。风险：舞台美术与"禁方块"约束冲突 → 先用既有 `superellipse_prism`/`blob` 塑造，必要时请你对新增轮廓方案确认。
**状态**：⏳ 未开始

### S2.2 帧数据战斗内核（状态机 + 帧窗口）

**计划描述**
- 状态机：`Idle / Move / Attack1-3 / Parry / ParrySuccess / Dodge / Charge / ChargeRelease / Hit / Stun / Dead / Victory`。
- 帧数据资源（`data/frames/*.json`）：每招含 起手帧 / 判定帧 / 后摇帧 / 取消窗口 / 可否移动 / 位移曲线 / 下一次可接招式。
- 固定 60Hz 逻辑步；输入缓冲 6 帧；招式取消规则集中在一张表里（不做散落 if）。

**验收标准**
- `A-` 帧数据一致性：逐帧日志中每招的起手/判定/后摇帧数与表**误差 = 0**（用例 `s2_2_frames`）。
- `A-` 输入缓冲：窗口内输入 100% 生效（≥ 1000 次随机输入模拟）。
- `A-` 非法状态迁移为 0（穷举状态 × 输入矩阵，记录越界迁移）。
- `B-` 普攻三段起手/判定/后摇逐帧截图各 1 张（姿态可辨识）。

**依赖与风险**：S2.1。风险：帧数据表设计返工 → 先冻结字段集，再填数值。
**状态**：⏳ 未开始

### S2.3 生命 / 韧性 / 削韧与受击

**计划描述**
- 属性：`HP`、`Poise`（韧性）、`PoiseDamage`（削韧）、硬直等级（轻/中/重）、受击位移与无敌帧。
- 伤害公式 v1：`伤害 = 招式倍率 × 攻击力 × (1 - 减伤) × 部位/状态修正`（集中一处，可单测）。
- 受击反馈：顿帧、击退、短暂无敌、姿态切换。

**验收标准**
- `A-` 20 组伤害用例与公式逐位一致（含上下限与暴击/格挡分支）。
- `A-` 韧性归零触发指定等级硬直；硬直期间不再叠加硬直（断言）。
- `A-` 受击无敌帧内第二次命中不结算（边界帧断言）。
- `C-` 顿帧时长按下表参数（采样帧间隔，误差 ≤ 1 帧）。

**依赖与风险**：S2.2。
**状态**：⏳ 未开始

### S2.4 弹反系统（招架窗口 / 完美弹反 / 弹反续普攻 / 反击斩）

**计划描述**
- 招架键：起手 **2 帧内命中 = 完美弹反**（有效窗口 12 帧）；窗口外为普通格挡（减伤 + 削韧消耗 + 自身小硬直）。
- 完美弹反 → 对手进入硬直 → **0.6s 内以普攻续接 → 触发「反击斩」**（高倍率、必硬直、专属动作与特效）。
- 弹反成功后前 3 帧内再次普攻可**取消弹反后摇**（这是"弹反可续普攻"的手感来源）。

**验收标准**
- `A-` 帧窗口：完美弹反窗口 [1,2] 帧命中率 100%，[13,∞) 帧一律判定为普通格挡（500 次随机时序模拟统计）。
- `A-` 链路：完美弹反 → 0.6s 内普攻 → 反击斩 100% 触发（状态迁移日志断言）。
- `A-` 超出 0.6s 后不再触发反击斩（边界断言）。
- `A-` 弹反取消后摇：第 1–3 帧内普攻可取消，第 4 帧起不可（边界断言）。
- `B-` 反击斩专属动作逐帧截图 4 张（起手/挥砍/命中/收招）。
- `D-` 手感：你实机确认"弹反有明显奖励感、反击斩值得追求"。

**依赖与风险**：S2.3。风险：窗口过严导致劝退 → 窗口初值集中在 §12，S2.11 统一标定。
**状态**：⏳ 未开始

### S2.5 闪避系统（无敌帧 / 位移 / 提前蓄力）

**计划描述**
- 8 方向闪避（横版下 = 前后 + 小纵深处移，纵深仅作演出与位置微调），无敌帧 6–10 帧，位移曲线（快出慢收），后摇 8 帧。
- **闪避成功（在对手判定帧内触发）且自身处于蓄力中 → 保留蓄力等级并「提前蓄力」**（下次蓄力所需时间缩短），这是你要的"闪避可触发提前蓄力"。
- 闪避不能无限连（体力或冷却约束，数值入表）。

**验收标准**
- `A-` 无敌帧边界：第 6 帧命中无效、第 11 帧命中有效（边界断言）。
- `A-` 蓄力中闪避后：蓄力等级保留（≥1 级不丢失），且下次蓄力耗时缩短 ≥ 30%（计时断言）。
- `A-` 冷却/体力约束生效：连续闪避第 N 次被拒绝（边界断言）。
- `B-` 闪避轨迹截图 3 张（起/中/落）+ 蓄力保留的视觉反馈 1 张。
- `D-` 手感：你实机确认"闪避有收益、能主动换节奏"。

**依赖与风险**：S2.3。风险：与弹反的优先级冲突（同帧既按弹反又按闪避）→ 明确优先级表并可验收。
**状态**：⏳ 未开始

### S2.6 蓄力系统（远程剑气 / 霸体连招）

**计划描述**
- 3 级蓄力：**1 级 0.35s** = 强化普攻；**2 级 0.9s** = 霸体连招（含霸体帧窗口，受击不打断）；**3 级 1.6s** = 远程剑气（投射物 + 击退 + 高削韧）。
- 蓄力期间移动惩罚、可被闪避打断并保留等级（S2.5）、视觉蓄力反馈（能量环/风压，NPR 管线，禁写实贴图）。
- 剑气投射物：飞行、命中、击退、削韧、可被弹反（可选开关，默认可弹反）。

**验收标准**
- `A-` 三级蓄力时长误差 ≤ 2 帧；中断/释放的状态迁移合法。
- `A-` 霸体窗口内受击不打断连招，窗口外被打断（边界断言）。
- `A-` 剑气命中结算正确（伤害/削韧/击退向量），飞行轨迹与发射朝向一致。
- `A-` 剑气可被弹反时，弹反判定与 S2.4 一致（复用同一判定路径，断言）。
- `B-` 三级蓄力各 1 张 + 剑气飞行 3 张截图。
- `C-` 同屏 6 个剑气投射物时帧率下降 < 5%。

**依赖与风险**：S2.4/S2.5。风险：远程剑气破坏近战博弈 → 用体力/冷却/前摇长度约束，S2.11 标定。
**状态**：⏳ 未开始

### S2.7 Boss AI 与阶段化行为

**计划描述**
- 招式表驱动 AI：每招含 触发距离区间 / 权重 / 冷却 / 可否接续 / 阶段可用性。
- 三阶段（按血量阈值切换）：阶段切换带演出与招式池变化；Boss 有独立帧数据表（与玩家同一套内核）。
- 难度参数：反应延迟、出招权重、弹反窗口宽容度（可分别调）。

**验收标准**
- `A-` 距离分布：AI 在 4 个距离区间的出招分布符合权重表（10 分钟模拟，偏差 < 10%）。
- `A-` 阶段切换在血量阈值 ±1% 内触发，且切换演出不产生无敌穿模。
- `A-` 无退化行为：不出现"连续 10s 不出招"或"同一招占比 > 70%"（断言）。
- `A-` 穷举 200 组随机对局无死锁、无卡在中间状态。
- `C-` 60s 对战平均帧时间 < 16.7ms。

**依赖与风险**：S2.3–S2.6。风险：AI 读招太强导致无解 → 难度参数暴露 + S2.11 标定。
**状态**：⏳ 未开始

### S2.8 战斗表现层（顿帧 / 镜头 / 特效 / 音效位）

**计划描述**
- 顿帧分级、镜头推移与轻震、命中特效（NPR 几何碎片/墨迹冲击，禁写实油贴图）、蓄力与弹反的专属视觉语言。
- 音效接口位（可播占位音；正式音频资产属美术/音频外包范畴，见 §14 开放问题）。

**验收标准**
- `B-` 关键帧截图 4 张：完美弹反火花 / 剑气 / 霸体 / 重击命中，风格与沙盘一致（描边 + 阶梯光影）。
- `C-` 特效峰值下帧时间 < 20ms。
- `A-` 表现层不影响逻辑判定（开关特效后，S2.4–S2.6 断言仍全绿）。
- `D-` 表现强度人工确认：有打击感但不遮盖判定信息。

**依赖与风险**：S2.4–S2.7。风险：特效遮挡判定 → 提供"简化特效"开关。
**状态**：⏳ 未开始

### S2.9 战斗 UI

**计划描述**
- 双方 HP 条 + 韧性条（Boss 条带阶段标记）、蓄力条、弹反窗口提示（可关）、可开关的伤害数字。
- 沿用 brutalist UI 语言；多分辨率自适应。

**验收标准**
- `A-` UI 数值与逻辑状态帧级同步（每帧断言，抽取 600 帧）。
- `A-` 提示开关生效且不改变逻辑。
- `B-` 1600×900 / 1920×1080 / 2560×1440 三档截图不错位。
- `D-` 可读性人工确认：能一眼读出"该弹反还是该闪避"。

**依赖与风险**：S2.7。
**状态**：⏳ 未开始

### S2.10 战斗结算与回流大地图

**计划描述**
- 胜负判定（含超时平局）；产出战利品 / 经验 / 剧情旗标 / 势力声望变化。
- 失败惩罚（被俘、损失兵员与金钱、掉落）；Boss 击败后写回世界状态（替换 S1.6 的占位结算）。
- 结算界面 + 回流战略层，全部后果持久化。

**验收标准**
- `A-` 胜 / 负 / 平三条路径各跑通 1 次，战略层状态变化逐字段符合预期（用例 `s2_10_result`）。
- `A-` 幂等：重复击败同一 Boss 不重复发奖（断言）。
- `A-` 结算后存档往返一致，且重开游戏后 Boss 仍处于已击败态。
- `B-` 胜利/失败结算界面各 1 张截图。

**依赖与风险**：S2.7/S1.9。
**状态**：⏳ 未开始

### S2.11 战斗数值标定与手感验收（M2 出口评审）

**计划描述**
- 用实机数据标定 §12 全部初稿（弹反窗口/无敌帧/蓄力时长/伤害曲线/Boss 难度/体力），产出 `docs/BALANCE.md` 与可复现调参流程。
- **M2 出口**：能完整打一场有来有回的 Boss 战，且弹反/闪避/蓄力三路都有正收益。

**验收标准**
- `D-` 你实机确认 3 场（普通 / 精英 / Boss 各 1 场），主观结论："弹反有奖励、闪避有收益、蓄力有必要"。
- `A-` 标定后参数表固化，verify 用例可复现全部关键帧窗口。
- `C-` 50 场脚本对战（AI vs AI）无死锁、无卡死、平均时长落在设计区间（如 45–180s）。
- `A-` `docs/BALANCE.md` 中的每个数值都能在 `data/frames/*.json` 中找到对应项（防文档漂移）。

**依赖与风险**：S2.1–S2.10。风险：手感是本项目最不可自动化的部分 → **必须**保留 D 类人工验收节点，不接受"看起来能跑"作为通过。
**状态**：⏳ 未开始

---

## 8. 里程碑 M3：装备系统

### S3.1 装备数据模型与数据表

**计划描述**
- 槽位：主手 / 副手 / 头盔 / 护甲 / 靴子 / 饰品 ×2；品质（普通/精良/稀有/传说）；词条（属性加成）；耐久。
- 数据表 `data/weapons/*.json`、`data/armor/*.json`，含"该武器挂载哪张招式帧表 + 动作变体"字段。
- 图标：程序化 NPR 风格（描边 + 纯色块），不引入写实图。

**验收标准**
- `A-` 表结构校验：必填字段缺失/取值越界/引用不存在的招式表 → 校验用例失败并指出行号。
- `A-` 全表加载 < 100ms，条目数 ≥ 设计基线（如武器 24 / 护甲 18）。
- `B-` 图标截图墙（≥ 12 个）风格统一、有描边。

**依赖与风险**：S2.11。风险：装备表与帧表耦合过深 → 用"招式表 ID"解耦。
**状态**：⏳ 未开始

### S3.2 属性管线与角色面板

**计划描述**
- 派生属性管线：基础属性（等级/成长）→ 装备加成 → 状态修正（buff/受伤/士气）→ 最终属性；每一步可单测。
- 角色面板 UI：属性明细、装备槽、词条说明。

**验收标准**
- `A-` 属性管线 30 组用例逐位一致；加成顺序改变可被检测（顺序敏感性断言）。
- `A-` 穿脱装备后属性即时刷新（同帧断言）。
- `B-` 角色面板截图 1 张（含 2 件不同品质装备对比）。

**依赖与风险**：S3.1。
**状态**：⏳ 未开始

### S3.3 背包 / 掉落 / 拾取

**计划描述**
- 背包（容量、排序、筛选、堆叠）；掉落表（按敌人类型/势力）；拾取流程与超额处理。
- 与战斗结算（S2.10）、交易（S1.7）打通。

**验收标准**
- `A-` 掉落表分布符合权重（10000 次抽样统计，偏差 < 2%）。
- `A-` 背包容量边界：满仓时拾取/交易的行为符合定义（拒绝并提示，不静默丢失）。
- `A-` 存读档后背包逐项一致（含耐久与词条）。
- `B-` 背包界面截图 1 张（含筛选态）。

**依赖与风险**：S3.2。
**状态**：⏳ 未开始

### S3.4 装备对战斗的绑定（招式表挂载与动作变体）

**计划描述**
- 不同武器挂载不同招式帧表（起手/判定/后摇/连招不同），并影响剑气形态、蓄力等级效果。
- 护甲影响受击硬直阈值与削韧抗性（与 S2.3 公式衔接）。

**验收标准**
- `A-` 切换武器后帧表随之切换（逐帧断言 3 种武器 × 3 段普攻）。
- `A-` 护甲对硬直阈值的影响符合公式（边界断言：刚好不硬直/刚好硬直）。
- `B-` 3 种武器的普攻判定帧截图各 1 张（可辨识差异）。
- `D-` 手感：至少 2 种武器"打起来明显不同"。

**依赖与风险**：S3.2/S2.2。风险：武器数量 × 帧表 = 工作量爆炸 → 表先做 3 把，其余走变体参数。
**状态**：⏳ 未开始

### S3.5 强化 / 修理 / 词条

**计划描述**
- 强化（消耗金钱 + 材料，等级上限与失败规则）；修理（耐久归零的惩罚）；词条重铸（可选）。
- 与聚落（S1.5）、经济（S1.7）联动。

**验收标准**
- `A-` 强化消耗与提升曲线符合表；资源不足时拒绝且不扣款（断言）。
- `A-` 耐久归零触发惩罚状态（伤害/防御下降，断言）。
- `A-` 强化/修理后存读档一致。
- `B-` 强化界面截图 1 张。

**依赖与风险**：S3.3。
**状态**：⏳ 未开始

### S3.6 装备存档与验收

**验收标准**
- `A-` 装备全状态（装备槽/背包/耐久/强化等级/词条）存读档往返逐字段一致。
- `A-` 旧版本存档迁移可用或明确拒绝。
- `D-` 你实机确认装备体系对战斗有实际影响、且有获取动机。

**依赖与风险**：S3.1–S3.5。
**状态**：⏳ 未开始

---

## 9. 里程碑 M4：军团作战（上帝视角指挥）

> 按 D4：小队编队指挥，60–120 单位，3–6 个小队（每队 10–20 人）。
> 玩家既是指挥官，也可亲自上阵（复用 M2 内核的单挑通道，S4.7）。

### S4.1 战场场景与上帝视角镜头

**计划描述**
- 战场场景：由 `BattleContext`（地形类型/兵力/时间）生成，复用战略地形高度场管线（同一套 NPR 美术）。
- 上帝视角镜头：俯视/斜俯、缩放 3 档、可旋转、可跟随某小队；战场边界与部署区。

**验收标准**
- `A-` 同一 `BattleContext` 生成同一战场（确定性）；不同地形类型产出可辨识差异（断言 + 截图）。
- `A-` 镜头缩放/旋转无抖动、不穿地、不越界（轨迹断言）。
- `B-` 3 档镜头截图（全局/战术/近地）风格统一、无方块元素。
- `C-` 空载战场 ≥ 60 FPS。

**依赖与风险**：S1.2/S1.6。风险：战场生成耗时 → 预生成池 + 异步构建。
**状态**：⏳ 未开始

### S4.2 单位与小队数据模型

**计划描述**
- 单位：兵种、攻/防/移速/射程/士气/体力/当前命令/状态（行进/接敌/交战/溃逃/倒地）。
- 小队：编制上限、阵型、队长存活加成、士气联动（队长阵亡 → 士气下跌）。
- 数据结构与 M5（兵团升级）**共用同一份定义**，避免两套。

**验收标准**
- `A-` 单位/小队字段可完整序列化往返（含战斗中状态）。
- `A-` 兵种表校验（字段完整、数值区间合法、升级指向存在）。
- `A-` 队长阵亡后小队士气下降并触发行为变化（断言）。

**依赖与风险**：S4.1。风险：M5 后期返工 → 本步即冻结字段集并写进 `docs/ENGINEERING.md`。
**状态**：⏳ 未开始

### S4.3 单位渲染与性能架构

**计划描述**
- 单位用 `MultiMesh` 实例化（沿用 `scatter.gd` 的成熟模式）+ 逐实例自定义数据（阵营色/朝向/动画相位/受伤态）。
- 简化姿态动画（姿态由少量关键帧或程序化驱动，不做骨骼动画）；LOD：远景简化细节。
- **描边方案**：实例化下的逆壳描边要么全量保留，要么提供受控 LOD 降级 —— 降级策略必须先经你批准（见 §14 Q3）。

**验收标准**
- `C-` 120 单位满编：≥ 60 FPS；单帧 > 33ms 次数 ≤ 1/60s 采样。
- `A-` 实例数变化（0/40/80/120）时帧时间线性可控，无突变（性能曲线断言）。
- `B-` 120 单位同屏截图：每个单位仍有可辨识轮廓与阵营色区分；若启用降级，需附降级前后对比图。
- `A-` 无单位穿地/悬浮（100 次采样贴地误差 < 0.08m）。

**依赖与风险**：S4.2。风险：NPR 描边在实例化下性能不过关 → **必须**提前做降级预案并与你确认，不得私自砍规范。
**状态**：⏳ 未开始

### S4.4 群体移动与阵型

**计划描述**
- 编队移动（小队作为整体寻路 + 成员局部避让），阵型模板（横列/纵列/楔形/方阵/散兵），阵型随地形自适应。
- 转向与队列维持，不出现成员互相推挤导致的死循环。

**验收标准**
- `A-` 120 单位在窄道/障碍/水岸场景下 5 分钟模拟无卡死、无穿模、无成员越界（用例 `s4_4_flow`）。
- `A-` 阵型误差：到位后成员与目标阵型位偏差 < 0.6m（统计断言）。
- `A-` 阵型切换耗时与参数一致（±10%）。
- `B-` 5 种阵型各 1 张截图。

**依赖与风险**：S4.3。风险：避让算法抖动 → 分层（小队层流场 + 成员层局部避让）。
**状态**：⏳ 未开始

### S4.5 指挥层（选队 / 命令 / 快捷指令）

**计划描述**
- 选择：单选 / 框选 / 全选；命令：移动、攻击目标、停止、切换阵型、冲锋、撤退、跟随。
- 快捷键 + 指令轮盘（沿用 brutalist UI）；指令必须在硬盘上显示预期路径/目标。

**验收标准**
- `A-` 全 7 种命令逐条断言：下达后单位最终状态符合预期（含被拒绝的情况）。
- `A-` 框选精度与数量正确（50 次随机框选断言）。
- `A-` 撤退命令确实让单位脱离接敌并保留建制（断言）。
- `B-` 指令轮盘 + 选队高亮截图各 1 张。
- `D-` 操作手感：你实机确认"指挥直觉、不需要说明书"。

**依赖与风险**：S4.4。
**状态**：⏳ 未开始

### S4.6 接敌与战斗结算（近战 / 远程 / 士气 / 溃逃）

**计划描述**
- 近战：接敌判定、攻击间隔、命中与格挡、个体战损；远程：射程、弹道（可简化为直射）、弹幕密度。
- 士气系统：伤亡、被包围、队长阵亡、体力耗尽 → 士气崩溃 → 溃逃（脱离战斗、可被追击）。

**验收标准**
- `A-` 同等兵力对撞的结果在固定 RNG 下可复现（确定性对局断言 10 组）。
- `A-` 士气崩溃阈值与参数一致；溃逃单位不再攻击且向战场边界移动（断言）。
- `A-` 无"永久僵持"：对局在设定上限时间内必然分出结果（100 组模拟断言）。
- `B-` 接敌混战 + 溃逃时刻截图各 1 张。
- `C-` 满编交战中 ≥ 60 FPS。

**依赖与风险**：S4.4/S4.5。风险：大规模命中判定开销 → 时间片轮转 + 空间哈希。
**状态**：⏳ 未开始

### S4.7 玩家亲自上阵（单挑 / 斩将）

**计划描述**
- 玩家可作为一支小队的成员/队长参战，并可在战中切入**单挑模式**（复用 M2 的横版战斗内核与帧数据）对敌方将领。
- 单挑结果影响军团士气（阵斩敌将 → 敌方士气大跌）。

**验收标准**
- `A-` 「军团战 → 单挑 → 返回军团战」上下文无损（时间/兵力/位置/士气一致）。
- `A-` 阵斩敌将后敌方可测量士气下降，且符合参数。
- `B-` 单挑切入/切出各 1 张截图。
- `D-` 手感：切入切出不割裂。

**依赖与风险**：S4.6/S2.2。风险：两套内核的输入映射冲突 → 进入模式时切换 `InputMap` 上下文并断言。
**状态**：⏳ 未开始

### S4.8 胜负条件与战斗结算

**计划描述**
- 胜负：全歼 / 撤退 / 时间上限 / 目标达成（护送/守点等）；结算：伤亡、俘虏、战利品、声望。
- 回流战略层：兵员损失写回队伍（与 M5 的编制联动）、战利品进背包（M3）。

**验收标准**
- `A-` 4 种胜负条件各 1 次完整断言（含战略层写回）。
- `A-` 幂等：重复结算不重复发奖/不重复扣兵。
- `A-` 结算后存读档一致（含俘虏与战利品）。
- `B-` 结算界面截图 1 张。

**依赖与风险**：S4.6。
**状态**：⏳ 未开始

### S4.9 规模与性能验收（M4 出口评审）

**计划描述**
- 压力与回归：120 单位满编、混合兵种、远程+近战同时交战、连续 20 分钟战斗。
- 产出 `docs/LEGION.md`（兵种数值、AI 参数、性能画像）。

**验收标准**
- `C-` 120 单位满编持续 20 分钟：FPS 均值 ≥ 60、单帧 > 33ms 次数 ≤ 1/60s 采样、内存漂移 < 5%。
- `A-` 20 分钟 soak 无脚本错误、无单位丢失、无状态机卡死。
- `B-` 满编大会战全景截图 1 张（作为对外展示级画面）。
- `D-` 你实机确认："指挥 60–120 人有战场感、不糊、不卡"。

**依赖与风险**：S4.1–S4.8。
**状态**：⏳ 未开始

---

## 10. 里程碑 M5：兵团升级系统

### S5.1 兵种与升级树

**计划描述**
- 兵种层级（新兵 → 老兵 → 精锐 → 特殊兵种）；升级树含分支（重步/弓手/骑兵等）、条件（经验/金钱/装备/建筑）、上限。
- 数据表 `data/units/tree.json`，与 S4.2 共用单位定义。

**验收标准**
- `A-` 升级树校验：无环、无悬空引用、每条路径可达、上限合法（图算法断言）。
- `A-` 树结构可视化产物（Mermaid 或截图）与表一致。

**依赖与风险**：S4.2。
**状态**：⏳ 未开始

### S5.2 招募 / 征募 / 训练与经验成长

**计划描述**
- 聚落招募（受人口/建筑/声望限制）、征募（即时但低质）、军营训练（耗时提升经验）。
- 战斗获得经验 → 单位成长 → 达阈值可升级。

**验收标准**
- `A-` 招募上限受人口与声望约束（边界断言：刚好可招/刚好不可招）。
- `A-` 经验成长曲线符合表；升级阈值处行为正确（边界断言）。
- `A-` 训练耗时随游戏时间推进正确结算（含倍速）。
- `B-` 招募/训练界面截图各 1 张。

**依赖与风险**：S5.1/S1.5/S1.7。
**状态**：⏳ 未开始

### S5.3 升级界面与消耗

**计划描述**
- 升级界面：显示可升级单位、消耗（金钱/装备/时间）、升级后属性对比、批量升级。
- 与装备（M3）联动：某些升级需要武器/护甲作为材料。

**验收标准**
- `A-` 批量升级的资源扣减与结果守恒（审计断言）；资源不足整批拒绝或按可承受数量部分执行（行为需明确并断言）。
- `A-` 属性对比数值与实际升级后属性一致。
- `B-` 升级界面截图 1 张（含前后对比）。
- `D-` 操作手感：批量升级不繁琐。

**依赖与风险**：S5.2/S3.3。
**状态**：⏳ 未开始

### S5.4 队伍编成 / 带兵上限 / 负重与忠诚

**计划描述**
- 编成：部队分组（前军/中军/后军或自定义槽），带兵上限受统率/声望/补给影响。
- 负重（速度惩罚）、忠诚/士气（长期断粮、连续战败、拖欠军饷 → 逃亡）。

**验收标准**
- `A-` 带兵上限边界与参数一致；超出时征募被拒绝（断言）。
- `A-` 负重对行军速度的影响符合曲线（采样断言）。
- `A-` 忠诚下降到阈值触发逃亡事件（断言），逃亡数量符合参数。
- `B-` 编成界面截图 1 张。

**依赖与风险**：S5.2/S1.3/S1.7。
**状态**：⏳ 未开始

### S5.5 大地图联动（驻军 / 补给 / 行军速度）

**计划描述**
- 聚村驻军（防守/征召）、补给线（粮草运输）、行军速度受编成/负重/地形/昼夜综合影响。
- 为后续"势力战争"预留扩展点（本期不做战争 AI 全局目标）。

**验收标准**
- `A-` 驻军后聚落防御数值变化符合参数；被围攻时可消耗驻军（断言）。
- `A-` 行军速度综合公式与 20 组采样逐位一致。
- `A-` 全套（时间/补给/驻军/编成）存读档往返一致。
- `B-` 驻军与补给线可视化截图各 1 张。

**依赖与风险**：S5.4/S1.9。
**状态**：⏳ 未开始

### S5.6 兵团升级存档与验收（M5 出口评审）

**验收标准**
- `A-` 全部兵团状态（树进度/经验/编成/驻军/忠诚）存读档往返逐字段一致。
- `A-` 旧版本存档迁移可用或明确拒绝。
- `D-` 你实机确认："看着部队从新兵成长为精锐有成就感"。

**依赖与风险**：S5.1–S5.5。
**状态**：⏳ 未开始

---

## 11. 里程碑 M6：整合与商用打磨

### S6.1 完整游戏循环串联

**计划描述**
- 新游戏 → 出身/起始 → 大地图 → 遭遇 → Boss 战 / 军团战 → 装备与升级 → 存档 → 继续；全链路无占位、无 TODO。
- 明确"游戏结束/失败"条件与重新开始流程。

**验收标准**
- `A-` 端到端脚本跑通 1 条完整链路（≥ 60 分钟游戏时间的 headless 快进），无脚本错误、无占位提示残留。
- `A-` 全仓库占位标记扫描：计划内允许的占位 = 0（verify 静态检查）。
- `B-` 全链路关键节点截图 6 张。

**依赖与风险**：M1–M5。
**状态**：⏳ 未开始

### S6.2 新手引导与教学

**计划描述**
- 分层教学：大地图基础操作 → 首场战斗（弹反/闪避/蓄力逐个引导）→ 首场军团战（编队指挥）。
- 教学可跳过、可在设置中重看。

**验收标准**
- `A-` 教学流程可完整跳过且不阻塞主线（断言）。
- `A-` 教学触发的条件不重复弹出（幂等断言）。
- `B-` 引导界面截图 3 张。
- `D-` 你实机确认：零文档上手 ≤ 10 分钟理解核心循环。

**依赖与风险**：S6.1。
**状态**：⏳ 未开始

### S6.3 设置 / 键位 / 存档管理 / 本地化接口

**计划描述**
- 设置：画面（分辨率/画质档/描边开关与粗细）、音频、键位重映射、游戏（难度/倍速默认）。
- 存档管理：复用 §3.5 的 **3×3 九宫格**（固定 9 槽）做删除与备份；删除同样需二次确认。
- 本地化接口：所有玩家可见文本走 key（中英双语待你确认，见 §14 Q2）。

**验收标准**
- `A-` 所有设置项持久化并在重启后生效。
- `A-` 键位重映射全部生效，且冲突有提示（断言）。
- `A-` 界面内无硬编码玩家可见文本（静态检查：未走 key 的字面量 = 0）。
- `A-` 删除槽位后该槽回到「空槽位」态，且其余 8 槽内容哈希不变（用例 `s6_3_slot_delete`）。
- `B-` 设置界面 + 存档管理界面（3×3 宫格）截图各 1 张；三档分辨率下宫格不错位。

**依赖与风险**：S6.1。风险：本地化在后期改造成本高 → 建议从 S1.5 起就使用 key（列入 §14 Q2，等你决定）。
**状态**：⏳ 未开始

### S6.4 性能与稳定性回归

**计划描述**
- 长时挂机（60 分钟）、反复切场景（200 次）、极端场景（120 单位 + 特效峰值 + 多剑气）、显存与内存画像。

**验收标准**
- `C-` 60 分钟挂机内存漂移 < 5%、无卡顿增长。
- `C-` 200 次场景往返后节点数/内存回到基线 ±5%。
- `A-` 极端场景无崩溃、无脚本错误。
- `C-` 全部红线（§3.3）复测通过。

**依赖与风险**：M1–M5。
**状态**：⏳ 未开始

### S6.5 内容量产管线

**计划描述**
- 数据表 + 校验工具 + 平衡批处理（批量模拟 N 场战斗输出胜率/时长分布）；策划可在不改代码的前提下加装备/兵种/任务。

**验收标准**
- `A-` 仅通过改数据表即可新增 1 件武器 / 1 个兵种 / 1 类任务，且校验与 verify 全绿。
- `C-` 平衡批处理 100 场模拟 < 5 分钟并输出分布报告。

**依赖与风险**：S6.1。
**状态**：⏳ 未开始

### S6.6 发布构建与导出验收

**计划描述**
- Windows 导出配置、启动参数清理、调试功能剔除、图标与版本信息、首次启动体验。

**验收标准**
- `A-` 导出包在干净路径下可独立启动，无调试控制台、无调试快捷键启用。
- `A-` 导出包上重跑 S6.4 的核心断言（性能/稳定性）全绿。
- `B-` 导出包运行截图 2 张。
- `D-` 你确认导出包可作为对外演示版本分发。

**依赖与风险**：S6.4。
**状态**：⏳ 未开始

---

## 12. 手感数值初稿（**待 S2.11 标定，此表仅为起点**）

> 单位：帧（60 FPS）。所有数值集中在 `data/frames/*.json`，本表与代码数值必须一致。

### 12.1 玩家基础

| 项目 | 初稿 | 说明 |
|---|---|---|
| 普攻 1 段 | 起手 8f / 判定 4f / 后摇 14f | 可取消窗口：判定后第 2f 起 |
| 普攻 2 段 | 起手 7f / 判定 4f / 后摇 16f | 接 3 段取消窗口 6f |
| 普攻 3 段 | 起手 12f / 判定 6f / 后摇 22f | 位移前压，硬直等级中 |
| 输入缓冲 | 6f | 窗口内输入必生效 |
| 移动速度 | 基准 5.4（沿用现有 `SPEED`） | 战斗内可下调 15% |

### 12.2 弹反（核心循环第 1 路）

| 项目 | 初稿 |
|---|---|
| 招架起手 | 2f |
| **完美弹反窗口** | **起手后 [1,2]f** |
| 普通格挡窗口 | [3,12]f（减伤 60%、削韧消耗、自身 8f 小硬直） |
| 完美弹反后对手硬直 | 30f |
| 弹反后摇取消窗口 | 成功后 [1,3]f 内可普攻取消 |
| **反击斩触发窗口** | 完美弹反后 **0.6s（36f）内普攻** |
| 反击斩倍率 | 普攻 ×2.4，必硬直，专属动作 |

### 12.3 闪避（核心循环第 2 路）

| 项目 | 初稿 |
|---|---|
| 闪避无敌帧 | [6,10]f（共 5f） |
| 闪避位移 | 3.2m，快出慢收曲线 |
| 后摇 | 8f |
| 冷却 / 体力 | 连续闪避消耗体力，体力见 12.5 |
| **蓄力中闪避** | 保留蓄力等级；下次蓄力耗时 **−30%** |
| 与弹反优先级 | 同帧同时按下 → **弹反优先**（需你确认此优先级） |

### 12.4 蓄力（核心循环第 3 路）

| 等级 | 蓄力时长 | 效果 |
|---|---|---|
| 1 级 | 0.35s（21f） | 强化普攻（倍率 ×1.6，削韧 ×1.5） |
| 2 级 | 0.9s（54f） | **霸体连招**：连招全程霸体，受击不打断（霸体窗口 90f） |
| 3 级 | 1.6s（96f） | **远程剑气**：投射物，伤害 ×1.8、击退 2.5m、削韧 ×2.2，可被弹反 |

### 12.5 生存与资源

| 项目 | 初稿 |
|---|---|
| 玩家 HP | 100 |
| 玩家韧性 | 40（重击削 20、轻击削 8） |
| 体力 | 100，闪避 25/次，格挡受击 12/次，回复 18/s |
| Boss HP | 三阶段：100% → 65% → 30% 触发阶段切换 |

---

## 13. 风险登记册

| # | 风险 | 影响 | 缓解措施 |
|---|---|---|---|
| R1 | **战斗手感无法自动化验收** | 高 | 每阶段固定 `D-` 类人工试玩节点；不接受"能跑"作为通过 |
| R2 | 程序化地图缺乏设计感 | 中 | 锚点覆盖表 + 每里程碑一次人工可玩性复评（S1.10/S4.9） |
| R3 | 120 单位下 NPR 逆壳描边性能不达标 | **高（与美术规范冲突）** | 提前做 LOD 降级预案；**降级策略必须先经你批准**（§14 Q3），不得私自砍规范 |
| R4 | 串行顺序导致 Boss 战反馈偏晚 | 中 | ~~若你同意，可把 S2.2/S2.3（内核白盒）提前到 M1 期间并行~~ **2026-10-19 裁定：不提前**。理由：M1 已按路线 B 完整做（不设硬期限），提前会让 M1 的 `A-`/`B-` 验收被 M2 的中间态污染；卖点验证滞后改由「每 2 周一个可运行构建 + M1 出口四问」对冲（见 §6 S1.10 与 `docs/spec.md` §2.7） |
| R5 | 存档兼容性随功能膨胀失守 | 中 | schema 版本化 + 迁移用例 + "反射式字段清单"断言（S1.9/S3.6/S5.6） |
| R6 | 范围膨胀超出中型项目预算 | **高** | 每里程碑出口评审，按优先级砍功能；砍功能必须更新本文并记录（§0.5） |
| R7 | 既有文件被大改导致美术回归 | 中 | S0.1 锁定 API 契约；每步附 `B-` 截图比对；`img_diff` 差异阈值门禁 |
| R8 | 帧数据表设计不当需返工 | 中 | S2.2 先冻结字段集并单测，再填数值 |

---

## 14. 开放问题（需要你后续决策，不阻塞 M0/M1 开工）

| # | 问题 | 为何重要 | 最晚需在哪步前答复 |
|---|---|---|---|
| Q1 | 美术资产来源：全部程序化自研 / 外包建模 / 采购资产包？ | 直接决定 M2 Boss 与 M4 单位的排期与工作量 | S2.7 前 |
| Q2 | ~~是否需要中英双语本地化（从 S1.5 起就是否走文本 key）？~~ **已裁定：从 S1.5 起全部文本走 key**（`tr("UI_xxx")` + `data/i18n/strings.csv`），数据表里的可读文本同样只存 `name_key`；本轮只填中文一列 | 后期改造代价远高于初期 | ✅ 已裁定（2026-10-19）；落地步骤 **S1.5**（见 §6 S1.5 的「本地化从本步起生效」） |
| Q3 | 军团单位若性能不达标，允许的降级方案（描边 LOD / 简化材质）边界在哪？ | 涉及违反 `AGENTS.md` 的例外授权 | S4.3 前 |
| Q4 | ~~单主角固定出身，还是骑砍式多出身/多势力开局？~~ **已裁定：单主角固定出身，势力归属可变**。`WorldData` 只需一个玩家势力指针；`BattleContext.hero_id` 本步为空串，M3 起接装备；多出身留到 M6 评估 | 影响 S1.1 数据模型与 M6 内容量 | ✅ 已裁定（2026-10-19）；落地步骤 **S1.1** |
| Q5 | 玩家是否可用多种武器类型（每种一套帧数据）？可接受几把？ | 帧数据工作量 = 武器数 × 招式数 | S3.4 前 |
| Q6 | Boss 战与军团战是否共用同一角色成长（等级/装备互通）？ | 影响 M3 属性管线的作用域 | S3.2 前 |
| Q7 | 是否需要手柄支持与完整键位重映射？ | 影响 S6.3 及战斗输入层设计 | S2.2 前 |
| Q8 | 目标可玩时长 / 内容体量基线（如主线 8 小时）？ | 决定聚落数、Boss 数、兵种数的量产目标 | S1.10 前 |
| Q9 | ~~是否需要战争迷雾 / 侦察机制？~~ **已裁定：两级迷雾 —— 已探索 / 未探索**（分块布尔图）。未探索区域不画聚落细节、不显示 AI 队伍；进入范围即标记已探索且不回退。**不做**视线遮挡/遮挡射线/逐格可见性 | 影响战略层渲染与 AI 信息模型 | ✅ 已裁定（2026-10-19）；落地步骤 **S1.6** |
| Q10 | ~~**存档：云同步 / 多存档位 / 自动存档？**~~ **已裁定：3×3 九宫格页面 / 固定 9 个槽位 / 不自动存档 / 不做云同步**；`ESC` 进菜单页，点击「保存」写当前槽、「另存为」选槽写入才触发存档 | 影响 SaveSystem 的槽位模型与菜单 UI 结构；越早定越省 | ✅ 已裁定（2026-10-16）；落地契约见 **§3.5**，落地步骤 **S0.3**（框架与宫格）→ **S1.9**（全量世界状态）→ **S6.3**（槽位管理） |
| Q11 | 音频与音乐资产来源（本规划只留接口位）？ | 影响 S2.8 与 S6.1 的验收标准 | S2.8 前 |
| Q12 | 是否允许为了手感把「横版」做成可微调纵深（2.5D → 2.7D）？ | 影响 S2.1 镜头与 S2.5 纵深闪避 | S2.1 前 |
| Q13 | ~~**`B-` 视觉门禁怎么定？**~~ **已裁定：选 (c) 改动画时钟为可注入 `u_time`**，落地为新增步骤 **S0.6**（见 §5）。原实测：同构建两次渲染差异 1.62%–5.67%（水波/云/风摆用 `TIME` 与 `Time.get_ticks_msec()`） | `B-` 是 S0.1 与后续每步美术回归的唯一自动化拦截手段；原 0.1% 阈值在动画不可冻结时客观不可达 | ✅ 已裁定（2026-10-16）；落地步骤 **S0.6 已于同日验收通过**（确定性模式实测 0.0000%），S0.1 的 `B-` 前置解除并收紧为逐位一致 |
| **Q14** | **S1.1 的地图参数（2400×2400 / 20 聚落 / 3 势力 / 24 队伍）是否维持？** | 这四个数会被写进 `data/world/gen_params.json`，并作为 S1.10 的 FPS/内存判据基准 | ✅ 已裁定（2026-10-19）：**暂按默认值生效**。它们只是数据表初值，安全区间 600–4000 / 8–40 / 2–5 / 4–40，改动**不需要改代码**，只需改表 + 重跑 `s1_1_gen` / `s1_1_variety` / `s1_10_soak`；改后须在 §16 登记 |

---

## 15. 步骤台账（唯一状态来源）

> 状态：`⏳ 未开始` / `🚧 进行中` / `🧪 待验收` / `🔁 返工中` / `✅ 已验收`
> 规则：**只有验收通过才可写 `✅`**，并在「验收证据」列填可追溯路径 + 对应提交哈希（见 §0.1 第 ⑤ 步）。

### M0 工程基础

| 步骤 | 名称 | 依赖 | 状态 | 验收证据 |
|---|---|---|---|---|
| S0.1 | 目录与工程结构重组 | —（`B-` 前置 S0.6 已验收） | ✅ 已验收 | 6 批迁移全部完成（批次 1–4 为代码移动，`1bab8fd` / `16b7196` / `1aa739c` / `534e2bd`）；验收：窗口 `--all` 8 用例 / 152 断言全通过 / 退出码 0，headless 8 用例 0 失败 2 跳过，推送门禁 0 条 ERROR，`B-` 6 机位与迁移前基线**逐位一致（6/6 sha256 全等）**；产出 `docs/ENGINEERING.md` |
| S0.2 | 验收工具链 v1 | —（原 S0.1，批准前置） | ✅ 已验收 | 提交 `1ff5283`；`tools/verify.gd --all` 窗口模式 6/6 用例、**87/87 断言通过**、退出码 0；headless 模式 5 通过 + 1 跳过、退出码 0；报告 `res://.verify/*.json`（gitignored）；结论见 `docs/成果.md` |
| S0.3 | 全局服务骨架 | S0.2 | ✅ 已验收 | 执行方案与 4 批划分见 §5 S0.3（2026-10-16 对齐定稿）。**批次 1 ✅ 已完成**（提交 `39f0c34`，subject `feat(core): S0.3 批次 1 —— 新增 Rng / EventBus / GameState 三个全局服务`）：新增 `scripts/core/{rng,event_bus,game_state}.gd` 三个 autoload（3 → 6），`project.godot` 注册顺序 `Rng` 先于 `GameState`；新增用例 `s0_3_state`（72 断言全通过）。验收：headless 启动 60 帧 0 条 `ERROR`/`WARNING`；`verify.gd --all` 9 用例 / 0 失败 / 2 跳过（178 断言）；**`B-` 6 机位逐位一致（6/6 sha256 全等）**，manifest `det=True hz=60.0 t=2.5 frame=150`。**批次 2 ✅ 已完成（2026-10-16，提交 `93c25e6`）**：新增 `scripts/core/save_system.gd`（autoload `SaveSystem`，注册在 `GameState` 之后，3 → 7）：9 固定槽位（1-based）+ `schema_version: 1` + `meta` 槽位卡片字段（真实时间 / 游戏内日期时间 / 队伍名与等级 / 累计时长）+ 脏存档容错（非法 JSON / 数组根 / 高版本 / 无迁移路径 / 缺 `game` 一律拒读且不改动当前状态；未知·缺失·类型错误字段逐条告警并保留当前值）+ `migrations` 版本链钩子 + **无自动存档**（无 `_ready`/`_process`/`EventBus` 订阅，`SAVE_DIR` 由首次写入惰性创建）。新增 4 用例：`s0_3_roundtrip` 63 断言（**真跨进程**：子进程写 → 父进程逐字段比对 → 另一子进程读回并回吐快照文件）、`s0_3_dirty` 47 断言、`s0_3_atomic` 29 断言（跨进程并发 800 次写 / 170 次观测，**0 次半截内容**、读者重试后 **0 次读取失败**、最终与写者自述 sha256 逐位一致）、`s0_3_no_autosave` 17 断言（启动 + 世界重建 + 五种全局事实 + 完整启动子进程后，`user://saves` 全部文件哈希与 mtime **零变化**，且有正对照证明该检查真能检出显式存档）。验收：headless 启动 60 帧 0 条 `ERROR`/`WARNING`；窗口 `verify.gd --all` **13 用例 / 0 失败 / 0 跳过（385 断言）/ 退出码 0**，headless 13 用例 / 0 失败 / 2 跳过；**`B-` 6 机位逐位一致（6/6 sha256 全等）**，manifest `det=True hz=60.0 t=2.5 frame=150`。**批次 3 ✅ 已完成（2026-10-16，提交 `2036423`）**：新增 `scripts/core/scene_router.gd`（autoload `SceneRouter`，7 → 8）与 `scenes/battle/battle_stub.tscn` + `scripts/battle/battle_stub.gd`（**占位靶子**，M2 替换）。`SceneRouter` 是**唯一**允许调用 `change_scene_to_file()` 的文件（守卫新规则 `scene_change_owner` 按属主路径放行）；浅栈 `world` → `battle`（`MAX_DEPTH=2`），越界一律显式失败并给出原因，拒绝不改动状态；栈与真实屏幕对账（场景被外部换掉/释放后 `current_route()` 归空，不沿用旧信念）；`_expected_path` 挡住同帧内的第二次切换（`change_scene_to_file` 只是登记，`current_scene` 要到帧末才更新）；只发自身事实 `route_changed(from,to)`，不发 `encounter_started`/`battle_finished`（留给 M1/M2，避免双重发射）；无 `_ready`、无 `_process`（批次 4 的 `paused` 不会卡住路由）。新增用例 `s0_3_router` 70 断言，覆盖：路由表与 API 契约、切换落地前的同帧语义、`world→battle→world` 后**节点数 ±0（101 → 101）**、世界子树**结构指纹逐条一致（92 条）**、**seed 派生值一致**（`spawn_point` + `height_at` + `Scatter.stats`）、栈深上限与三类越界的显式拒绝、`route_changed` 恰好 4 次且被拒调用一次不播报、占位场景正交相机/面着色网格（242 三角面）/`Style.toon()` + 逆壳描边、以及"栈不撒谎"。同批把 `s0_3_state` 的 autoload 契约 7 → 8、`s0_2_guard` 类数描述 7 类 → 8 类。验收：headless 启动 60 帧 0 条 `ERROR`/`WARNING`；窗口 `verify.gd --all` **14 用例 / 0 失败 / 0 跳过（460 断言）/ 退出码 0 / 50034 ms**，headless 14 用例 / 0 失败 / 2 跳过（411 断言）/ 13939 ms；**`B-` 6 机位逐位一致（6/6 sha256 全等）**，manifest `det=True hz=60.0 t=2.5 frame=150`；`C-` fps_mean 59.97–60.02、ms/frame 16.662–16.676、三角面 219,978、绘制调用 96。批次 4（菜单 + 九宫格）→ **已完成 ✅（2026-10-16，提交 `f3006d3`，subject `feat(ui): S0.3 批次 4 —— 新增存档菜单与 3×3 九宫格，接入 ESC 暂停与 SaveSystem`）**：新增 `scripts/ui/menu_page.gd`（`CanvasLayer`，`layer=20` / `PROCESS_MODE_ALWAYS` / `add_to_group("menu")`；主页五入口 + 宫格页 + 覆盖确认弹窗三页；`ESC` 四级层级＝弹窗→宫格→主页→关闭，`keycode`/`physical_keycode`/`ui_cancel` 三者都认）与 `scripts/ui/save_grid.gd`（`COLUMNS=3` / `SLOT_COUNT=9`、卡片 296×104、`slot_pressed(slot)`；卡片正文**只读** `SaveSystem.slot_info(slot).label`，宫格自己不算、不缓存槽位数据）。`scenes/main.tscn` 挂载 `MenuLayer`（**默认隐藏**，否则 6 机位 `B-` 立即变红）；`scripts/core/render_clock.gd` 与 `scripts/ui/ui_panel.gd` 补 `PROCESS_MODE_ALWAYS`（陷阱 1 落地）；`scripts/core/capture.gd` 的 `--shots` 新增 UI 步骤驱动（`ui:["esc","click:<控件相对路径>"]` + `ui_expect` 自证行；**产品码不留演示状态后门**，"拍错屏"直接以非 0 退出而不是产出一张看着正常的 PNG）。新增用例 `s0_3_slots` **100 断言**（装配与层号、暂停契约、无当前槽位的两条跳转、空槽位直写与卡片刷新、`ESC` 层级、4 张 `B-` 截图两轮逐位一致 + 两两不同 + 非空图）与 `s0_3_overwrite` **34 断言**（整页弹窗先问后写、弹窗期间与取消后目录逐项 sha256+mtime 不变、`save_written` 计数 0 → +1、主页「保存」写已占用的当前槽位同样先问）。验收：headless 启动 60 帧 0 条 `ERROR`/`WARNING`；窗口 `verify.gd --all` **16 用例 / 0 失败 / 0 跳过 / 594 断言 / 退出码 0 / 71843 ms**，headless 16 用例 / 0 失败 / **4 跳过** / 411 断言 / 14672 ms；**`B-` 6 机位与 S0.1 基线逐位一致（6/6 sha256 全等）**，manifest `det=True hz=60.0 t=2.5 frame=150`；`B-` 菜单 4 张（1600×900，两轮独立进程逐位一致）`01_menu_home eeec5d02…` / `02_grid_empty ce9175ce…` / `03_grid_full a504ec4e…` / `04_overwrite_confirm 1563abf8…`；`C-` fps_mean 60.0、ms/frame 16.667、三角面 219,978、绘制调用 96（与批次 3 全等），**静态内存 91.3 → 126.13 MB、对象 1778 → 2034** —— 增量经独立探针拆开量过：**菜单子树 77 节点 = 34.29 MB / 254 对象**（headless 侧 99.52 → 65.23 MB，与窗口侧 +34.8 MB 相互印证），主体是中文 `SystemFont`（匹配到系统 CJK 字体）及其字形缓存，登记为"若日后压内存，首选项是换子集化随包字体"。**两条负面结论已回写**：① `--all` 在同**一个进程**里顺序跑完所有用例，因此"上一个用例停在哪个槽位"属于必须显式复原的状态（`s0_3_roundtrip` 走后 `current_slot` 停在 3，导致 `s0_3_slots` 的"无当前槽位"整段失效 —— `_restore_defaults()` 已补 `SaveSystem.current_slot`/`last_error`，两个新用例自带前置条件）；② 同一秒内状态没变时两次存档的**字节可以逐位相同**（`saved_at` 只到秒），"文件内容变了"不能当"确实写过了"的判据，要用 `save_written` 的发布次数。**未闭环项**：淡入淡出过渡**未纳入本批**（幕布必须活过 `change_scene_to_file()` 的场景释放 ⇒ 需要一个不挂在任何场景里的持久属主，属要先对齐的设计决定，顺延为独立小步）。**`D-` 人工试玩已通过（2026-10-16，用户）**：`ESC` 开合 / 宫格选槽 / 覆盖二次确认手感确认通过、无返工项 ⇒ 本步 `A-`/`B-`/`C-`/`D-` 全部闭环，状态置 `✅ 已验收` |
| S0.4 | 调试与观测层 | S0.3 | ✅ 已验收 | **批次 1 ✅ `ed92e66`**：抽 `UiKit` 公共控件工厂（`ui_panel` / `menu_page` / `save_grid` 三份重复实现合一），三份 UI 的 `B-` 截图逐位不变。**批次 2 ✅ 2026-10-19**：新增 autoload `Debug`（8 → 9，`scripts/core/debug_layer.gd`）—— 默认隐藏的叠加层（层号 30 > 菜单 20 > HUD 10，整层 `MOUSE_FILTER_IGNORE`）、帧时间曲线（纵轴固定 0–33ms ⇒ 图形是采样值的纯函数）、节点/分组计数、场景与路由栈（两级回退，见 §5 S0.4 实测结论 1）、时钟与 Rng 子流；`input_setup.gd` 新增 `debug_ui_hide`（`F1`）/`debug_overlay`（`F3`）与唯一闸门 `ensure_debug_hotkeys(OS.is_debug_build())`（关掉时**删除 action**）；`capture.gd` 支持 `ui: ["key:f3"]` 步骤与 `ui_expect.overlay/ui_hidden` 自证；`debug_layer.gd` 支持 `--obs-csv=`（纯修饰符，不触发截图、不抢退出码）。**批次 3 ✅ 2026-10-19**：`F5` 快存 / `F9` 快读（`debug_quick_save` / `debug_quick_load`，仍写 9 个真槽位、无隐藏槽位与旁路文件；已占用槽位第一次只登记待确认、`CONFIRM_WINDOW_FRAMES = 120` 帧内再按一次才覆盖 ⇒ §3.5 的二次确认不被绕过；闸门做在函数内部而非只在 `_input`，发布构建直接调用也无动作）；快存快读反馈落在独立 `ToastLayer`（`LAYER + 1`，不依赖叠加层开着，服从 `F1`，按帧过期）；菜单「设置」页填实为调试页（只读事实与 `Debug.stats()` 同源 + 「打开叠加层」按钮，按钮路径 `Root/Home/Panel/Col/Actions/Settings` 不变）。新增用例 `s0_4_overlay` 70 断言 + `s0_4_cost` 32 断言 + `s0_4_quick` 62 断言。验收：窗口 `--all` **19 用例 / 0 失败 / 0 跳过 / 761 断言 / 108015 ms**、退出码 0；headless 同口径 0 失败、headed 用例跳过；`A-` 开关前后世界结构指纹 + seed 派生量 + `GameState` 字段 + **`Rng` 子流 state** 逐项不变；`C-` 120 实体夹具叠加层**每帧成本 0.0044 ms < 0.5**（附 0.5ms/2ms 自旋标尺回收率 ≈100% 证明可分辨），且有 draw_calls 反向对照；`B-` 两批次各两轮独立进程 sha256 逐位一致、互不相同，`F1` 后 UI 面板底色**精确 0 像素**（基准图 3892），6 机位与 S0.1 基线**全等 6/6**；`D-` 人工手感已由用户确认通过（批次 2 反馈"手感可以"） |
| S0.5 | 工程规范与美术管线文档 | S0.1/S0.2 | ✅ 已验收 | 提交 `9070501`。产出 `docs/ENGINEERING.md` §7–§13（命名规范 **12 个 `class_name`** · 信号约定 25 条实测清单 · `Canon` 契约**标注"未实现，S1.1 落地"** · autoload 9/10 与三条顺序约束 · 允许/禁止清单含 §11.3「守卫管不到」 · 三个新增 checklist）与新建 `docs/ART_PIPELINE.md`（Three.js→Godot 映射表 · 三对 A/B 对照 · 6 步新建物件模板 · 提交前自检 · 复现命令与 sha256 基线）。教材夹具 `scenes/dev/art_samples.tscn` + `scripts/dev/art_samples.gd`（6 展台、3 对 A/B 各只差一个变量；①共用同一 `ArrayMesh` 只换材质 ②`blob()` vs `BoxMesh` ③`blob()` vs 未 `facet()` 的 `SphereMesh`）。工具链新增 `--at="x,y,z"` 修饰符与位置参数化场景。新增用例 `s0_5_doc_conventions` **90 断言**：12 类 + 25 信号 + 9 autoload + 7 守卫规则**逐条双向**断言（文档有锚点 **且** 代码有实现）、`Canon` 未实现标记、教材目录**双向约束**（产品码 0 处引用 `dev/`、夹具命中数恰等于白名单登记数）、6 张 PNG 的 sha256 与批次清单逐位一致、**4 条编造锚点反向对照**。验收：窗口 `--all` **20 用例 / 0 失败 / 0 跳过 / 1108 断言 / 约 108s**、退出码 0、**连跑 2 轮全绿**；headless 20 用例 0 失败 5 跳过；启动门禁 0 条 `ERROR`；`B-` 6 机位与基线**全等 6/6**；`C-` FPS 极差 0.150% / ms-per-frame 极差 0.138%；`D-` 用户已通读确认。**顺带修掉既有缺陷**：`_click_control()` / `_click_path()` 缺 `InputEventMouseMotion` ⇒ `gui.mouse_focus` 失效 ⇒ `s0_3_slots` 间歇性失败（HEAD 上 5 跑 2 红、失败点漂移），先证既有再修，修后连跑 18 次全绿。结论见 `docs/成果.md` |
| S0.6 | 可复现渲染时钟（可注入 `u_time`） | S0.2 | ✅ 已验收 | 提交 `457a7d2`（实现）+ `953fd0d`（用例与守卫）；`tools/verify.gd --all` 窗口模式 **8/8 用例、152/152 断言**、退出码 0，headless 6 通过 + 2 跳过、退出码 0。关键证据 `s0_6_repro` 31/31：两独立进程同参数截图 `img_diff` **0 像素 / 0.0000%** 且 sha256 逐位相同（`s0_boot_follow`、`s0_boot_wide`），`--yaw=45→52` 与 `--frames=15→200` 反向对照均判不同；`s0_6_clock` 28/28；修复前同口径实测 1.62%–5.67%。`C-` 三次采样 ms/frame 16.685/16.667/16.667、三角面 219,978、绘制调用 96（vsync 封顶，仅证明未跌破上限）。结论与遗留见 `docs/成果.md` |

### M1 大地图

| 步骤 | 名称 | 依赖 | 状态 | 验收证据 |
|---|---|---|---|---|
| S1.0 | 场景与路由迁移 | M0 | ✅ 已完成 | **S1.0a ✅ 2026-10-19**（提交 `419785f`）：`scenes/main.tscn` → `scenes/dev/diorama.tscn`（git 判定 **100% 相似度重命名**，内容零改动）；`run/main_scene` / `SceneRouter.SCENES[world]` / `baseline.gd` / `verify.gd::_load_main()` 四处同行换路径，`s0_3_router` 新增「`run/main_scene` == 路由表 == 文件存在」断言（73 断言全绿）。证据：`B-` 6 机位由**两条独立进程**重采（`.shots/s10a_verify` / `.shots/s10a_verify_b`），**6/6 sha256 与 §4 基线逐位相等**且两次互等；窗口 `--all` **20 用例 / 0 失败 / 0 跳过 / 857 断言 / 109s**、退出码 0，headless 20 / 0 失败 / 5 跳过、退出码 0；headless 启动门禁 0 条 `ERROR`/`WARNING`。**S1.0b ✅ 2026-10-19**（提交 `5f03cc2`）：`capture.gd` 新增 `--scene=res://…` —— **纯修饰符**（与 `--case=`/`--out=` 同级，单独出现不触发批次也不抢退出码），`_swap_scene()` 手动换 `SceneTree.current_scene`（不碰 `change_scene_to_*`，属主仍只有 `SceneRouter`）并四条自证（新实例接管 / 路径一致 / 旧场景已释放 / 相机组 ≤1 台），任一不成立退出码 1；截图清单新增 `scene` 字段自报拍摄场景。证据：新用例 `s1_0_scene_arg` **32 断言 / 22.4s / PASS**（headed）——`--scene=diorama` 两次独立进程 × 2 图 sha256 互等**且与缺省逐位相同**（`10e29e93…` / `d56ada81…`），反向对照 `--scene=battle_stub` 2 图哈希全变（`79b0610b…`）、坏路径退出码 1、`--scene=` 独走不写清单；改完 `capture.gd` 后另跑两条独立进程，`B-` **6/6 仍与 §4 基线逐位相等**（默认路径零改动）；窗口 `--all` **21 用例 / 0 失败 / 0 跳过 / 889 断言 / 131s**、退出码 0。两个坑记在 §5：改 `run/main_scene` 对本次开机**无效**（引擎取路径早于 autoload，且自证会空洞通过）；`queue_free()` 后多等一帧会让云的增量积分前移一步 ⇒ 逐位一致立刻破产。**S1.0c ✅ 2026-10-20**（提交 `588ff28`）：路由表登记第三条 `strategic → res://scenes/world/strategic_map.tscn`（**空壳** `Node3D` 根 `StrategicMap`，无脚本 / 零子节点 / 无相机，内容留 S1.2），`world` 与 `run/main_scene` **未动**；**不接线**：无 `goto_strategic()`、`goto_*` 语义不变（由 `s1_0_routes` 的"没有这个入口"反向断言守住）。证据：新用例 `s1_0_routes` **37 断言**（三路由 / 路径存在且互异 / path↔route 双向 / `MAX_DEPTH` 仍 2 / 场景可实例化且根节点解剖 / 无新入口 / 拒绝零副作用 / 收尾交还现场），`s0_3_router` 73 → **74 断言**；窗口 `--all` **22 用例 / 0 失败 / 0 跳过 / 927 断言 / 138.3s**、headless 22 / 0 失败 / 6 跳过 / 677 断言 / 33.4s，均退出码 0；启动门禁 0 条 `ERROR`/`WARNING`；`B-` 6 机位两条独立进程 **6/6 与 §4 基线逐位相等**。**S1.0d ✅ 2026-10-20**（提交 `ac512b2`）：`run/main_scene` 与路由表 `world` 同时改指 `res://scenes/world/strategic_map.tscn`，**删除** S1.0c 的临时名 `strategic`（表回到 world / battle 两条，`_route_for_path()` 不再二义）；`goto_world()` 语义**不新增分支** —— 开机由 `_sync()` 认领，此后调用照旧被拒且**不重载同一文件**（S1.0c 留下的问题用"世界实例数仍为 1"断言闭环）。证据：新用例 `s1_0_migration` **22 断言**（路由→文件→根类三环一致 / `run/main_scene` 逐字相等且 ≠ diorama / diorama 仍可加载 / 开机认领且不重载），`s1_0_routes` 37、`s0_3_router` 74 → **76**（空壳基线：指纹 `StrategicMap:Node3D:0`、`#main` 0、地形 0、seed 派生值为空），`s0_2_boot` 改为反向断言"日志不含 `[terrain]`"；窗口 `--all` **23 用例 / 0 失败 / 0 跳过 / 956 断言 / 131.1s**、headless **23 / 0 失败 / 6 跳过 / 702 断言**，均退出码 0；启动门禁 0 条 `ERROR`/`WARNING`；`B-` 6 机位走 `--scene=diorama` 专用批次（`.shots/s10d_a` / `s10d_b`）**6/6 与 §4 基线逐位相等**且两轮互等。三个坑：缺省场景已无内容 ⇒ 所有截片子进程必须显式 `--scene=diorama`；`_world_fingerprint()` 走 `#main` 会在空壳上**真空通过**，加 `root` 形参；白名单收紧回 0 后**注释里的** `res://scenes/dev/` 也算泄漏。 |
| S1.1 | 世界数据模型与程序化生成 | S1.0 | ✅ 已验收 2026-10-20（批 1–4 全 ✅）；欠账 `B-` 俯视全局图已于 S1.2d 交付（2026-10-21） | **批 1（S1.1a）落地 2026-10-20**：新增 `scripts/core/canon.gd`（`class_name Canon`，四入口，不占 autoload）、`data/world/gen_params.json`（schema=1）与 `scripts/world/gen_params.gd`（`class_name GenParams`，初值 + 安全区间 + clamp/告警 + 坏表回退）；新增用例 `s1_1_canon` **53 断言**、`s1_1_params` **100 断言**，`s0_5_doc_conventions` 90 → **102**（`class_name` 12 → 14，`Canon` 由"未实现"改"已落地"并断言三入口在）。验收：窗口 `--all` **25 用例 / 0 失败 / 0 跳过 / 1119 断言 / 134.7s**、headless **25 / 0 失败 / 6 跳过 / 865 断言 / 31.0s**，均退出码 0；启动门禁 0 条 `ERROR`/`WARNING`/`SCRIPT ERROR`；`B-` 6 机位两条独立进程（`.shots/s11a_cam_a` / `s11a_cam_b`）**6/6 sha256 与 `ENGINEERING.md` §4 基线逐位相等**且两轮互等。落地时实测更正契约两处（`String.unicode_compare` 不存在；`JSON.parse` 数字全变 float ⇒ 整数写整数），见 §5 陷阱 23。用户 2026-10-20 判定通过（§0.1 第 ④ 步），提交 `7e7a001`。**批 2（S1.1b）落地 2026-10-20**：新增 `scripts/world/height_field.gd`（`class_name HeightField`：`height_at` 返回世界米 / `normalized_height_at` / `slope_at` 升跑比 / `biome_at` 六值 / `sample_heights`；5 层噪声以"跨地图周期数"表示频率、种子由 `world_seed` 派生 ⇒ **无随机**）与 `scripts/world/regions.gd`（`class_name WorldRegions`：Voronoi 中心 + 32 m 归属网格 + 面积统计，**显式接收** `RandomNumberGenerator`，不读 autoload、不裸 `randf()`）；`gen_params.json` / `GenParams` 扩 4 个**米制浮点**字段（`water_level` / `base_height` / `hill_amplitude` / `detail_amplitude`，`FLOAT_FIELDS` 分支不取整）。新增用例 `s1_1_height` **41 断言**、`s1_1_regions` **37 断言**；`s1_1_params` 100 → **145**；`s0_5_doc_conventions` 102 → **106**（`class_name` 14 → 16）。实测：陆地占比 **0.629**、最低 **−78.17** m / 最高 **107.71** m、最陡坡度 **1.245**、扫描出 **6/6** 种 biome、`region 数 8`（区间 6–9）、**面积守恒**（每格恰属一个 region、水格 owner=−1）、5 625 点采样 **6.9 ms**、`build()` **10.5 ms**；反向对照：换 seed 后 **5 624/5 625** 点高度变、`hill_amplitude` 减半后 **400/400** 点变且 `max_height` 同步。验收：窗口 `--all` **27 用例 / 0 失败 / 0 跳过 / 1246 断言 / 129.8s**、headless **27 / 0 失败 / 6 跳过 / 992 断言 / 30.5s**，均退出码 0；启动门禁 0 条 `ERROR`/`WARNING`/`SCRIPT ERROR`；`B-` 6 机位两条独立进程（`.shots/s11b_cam_a` / `s11b_cam_b`）**6/6 sha256 与 §4 基线逐位相等**且两轮互等。一次**既有偶发**（`s0_3_slots` 的 `04_overwrite_confirm` 两轮像素差 148668）登记为 §16 待查项，隔离 8 次未能复现，**不以"重跑绿了"当已修**。批 2 提交 `c36d8e7`。**批 3（S1.1c）落地 2026-10-20（待验收）**：新增 `scripts/world/world_data.gd`（`class_name WorldData`，`RefCounted`，**不占 autoload**：锚点优先 → 按配额补点（离边界 80 m / 不落水 / 坡度 ≤ 0.35 / 最小间距 120 m 四道闸门 + 每点 200 次上限）→ 最远点采样定三个首都 → 最近邻骨架 + 补边至单连通 → 24 支队伍挂母城）与 `data/world/anchors.json`（3 条手工锚点：`town_seat` / `village_seat` / `fortress_seat`，Canon 规范形式）；`gen_params.json` / `GenParams` 再扩 2 个浮点字段（`settlement_min_spacing` 120 m / `settlement_slope_limit` 0.35，`FLOAT_FIELDS` 4 → **6**）。新增用例 `s1_1_world` **308 断言**；`s1_1_params` 145 → **159**；`s0_5_doc_conventions` 106 → **108**（`class_name` 16 → 17）。实测：聚落 **20**（12 村 + 4 镇 + 4 要塞）、道路 **24 条 / 7936.7 m**、连通分量 **1**、最小聚落间距 **131.0 m**、三方各 **8** 支队伍、`build()` 中位 **2.31 ms**、换 seed 后 **19/20** 聚落坐标变、**0 告警**；反向对照：把某聚落的边全删后 BFS 报 **≥2** 分量、挪到海角必被合法性检查检出、改锚点表后旧表**恰好 1 条**失配、`spacing = 900 m` 降级为告警且 **3 s 内**结束。验收：窗口 `--all` **28 用例 / 0 失败 / 0 跳过 / 1570 断言 / 129.2s**、headless **28 / 0 / 6 跳过 / 1316 断言 / 31.7s**，均退出码 0；启动门禁 0 条 `ERROR`/`WARNING`/`SCRIPT ERROR`；`B-` 6 机位（`.shots/s11c_cam_a` / `s11c_cam_b`）**6/6 sha256 与 §4 基线逐位相等**且两轮互等。批 3 提交 `7838a49`。**批 4（S1.1d）落地 2026-10-20**：`WorldData` 增 `to_dict()` / `to_text()`（Canon 契约 `{ok, text, reason}`）/ `metrics()` / `_sorted_by()`，顶层 `{schema: 1, world_seed, params, metrics, settlements[], roads[], factions[], parties[]}`，四个数组按稳定文本键（`id` / `a`）排序后写出、坐标不取整；新增用例 `s1_1_gen` **52 断言**（同一入口状态两次构建文本**逐字节相同** 10 298 字符、读回再写幂等、顶层键码点升序、条数与内存一致、锚点逐位、指标按规范文本一致；反向对照换 seed 文本与指标都变）与 `s1_1_variety` **33 断言**（三个 seed 两两文本不同；海岸线 / region 面积分布 / 道路总长 / 聚落按 region 分布 **4 / 4** 随 seed 变化；**刻意不用「聚落数」**——配额固定使它恒为 20，恒真断言没有意义）。实测 `C-` 整条链（高度场 + region + 世界数据 + 序列化）**16.0 ms**（15.36 / 15.32 / 16.01）≪ 800 ms。**抓到并修掉一个真实缺陷**：用例共享同一条 `world_gen` 子流，不拨回起点时同一个 seed 会漂（`--all` 里 26 条边 / 8916.9 m vs 单跑 24 条 / 7936.7 m），夹具改用 `Rng.reset()` 后两种跑法逐字节一致；「S1.2 组合根先 `Rng.reset()` / `seed_from(world_seed)` 再建世界」立为 S1.2 开工前置（`ENGINEERING.md` §5 陷阱 26）。验收：窗口 `--all` **30 用例 / 0 失败 / 0 跳过 / 1655 断言 / 130.2s**、headless **30 / 0 / 6 跳过 / 1401 断言 / 31.2s**，均退出码 0；启动门禁 0 条 `ERROR`/`WARNING`/`SCRIPT ERROR`；`B-` 6 机位（`.shots/s11d_cam_a` / `s11d_cam_b`）**6/6 sha256 与 §4 基线逐位相等**且两轮互等。批 4 提交 `7c3dfe8` |
| S1.2 | 战略地图场景与镜头 | S1.1 | ✅ 已验收 2026-10-21（批 1 / S1.2a ✅ 2026-10-20；批 2 / S1.2b ✅ 2026-10-21；批 3 / S1.2c ✅ 2026-10-21；批 4 / S1.2d ✅ 2026-10-21） | 四批见 `docs/成果.md`；`B-` 五张 plate 与 `C-` 三档帧率在批 4，`fbd83b40` / `ce307b39` / `fdc3cdef` / `f76e14fe` / `39a4b9c9` |
| S1.3 | 队伍棋子与移动 | S1.2 | 🟨 进行中（批 1–3 ✅） | **S1.3a ✅ 2026-10-21**：`scripts/world/party_marker.gd`（第 21 个 `class_name`，不占 autoload）—— 12 个圆柱/球/旗面零件 `combine()` 成单一 mesh（556 三角 / 1668 顶点 / 1 个 draw call），标称 22 m、脚底 `y = 0`；反向外壳描边挂 `next_pass` 且**切线槽写平滑法线**（`MeshUtil` 把面法线写进切线槽会让外壳炸成散三角片、描边不可见，本批实测线宽 120 才见碎屑）；`FACTION_KEYS` 四阵营换色不重建几何；`place_at` 落点高度 ≡ `height_at`。用例 `s1_3_party` **37 断言 / 86 ms**：100 个定种子采样点最大偏差 **0.00000 m**（正负 52/48，配 `min_y = 0`）、1494 个顶点切线槽为平滑法线、四方向朝向含 ±π 回绕、两次构建逐字节一致。取证 `.shots/s13a/party_local`（`55aa66e6…`）/ `party_close`（`eebe7950…`）。全量 headless `--all` **35 用例 / 0 失败 / 7 跳过 / 35.8 s**。**S1.3b ✅ 2026-10-21**：`scripts/world/travel_graph.gd`（第 22 个 `class_name`，`RefCounted`）+ `data/world/travel_params.json`（32 m / 提速 0.35 / 坡度 1.6 / 水域余量 1.5 m / 展开预算 20 000）—— 75×75 = 5625 格（可走 3364 / 水 2261），可走 = 格心 + 四角都高于 `water_level + 1.5 m` 且对角不许切角；19 条道路直线经整数 DDA 栅格化成 216 个道路格（穿水 0 格，只记账不改可走性），道路的每米成本 ×`1/1.35`；A\* 用 `(f, 节点序号)` 双键堆 + 固定邻居序 + octile × 最小系数，同实例两次与重建图后 `path_key` 逐位一致、换 seed 必变。用例 `s1_3_path` **66 断言 / 224 ms**：最长路 `village_8→fortress_2`（直线 658.6 m）→ 21 点 / 折线 672.9 m / 成本 498.5 / 展开 21 格 / 路上 672.9 m、野外 0 m，开/关提速成本比 **0.74074** = `1/1.35`（±5% 判据），道路格最慢 1.35 > 地面格最快 0.9871（全序）。建图 **46.7 ms**；取证 `.shots/s13b/route_region`（墨色 = 路径、沙色 = 图里道路格，两层重合）。同时修两个坑：成本必须按报出的折线重算（`_g[goal]` 漏首末段，会把 498.5 报成 483.9）、零断言用例改为判失败（§5 陷阱 37）。全量 headless `--all` **36 用例 / 0 失败 / 7 跳过 / 37.2 s**。**S1.3c ✅ 2026-10-21**：`scripts/world/party_mover.gd`（第 23 个 `class_name`，`Node3D`，不占 autoload）+ `data/world/travel_params.json` 加 `march_speed 24` / `turn_rate_deg 300` / `arrive_radius 6` / `max_pitch_deg 12` —— 一帧一个入口：读 `speed_factor_at()` 算预算（`≤0` 直接 `BLOCKED`，不硬推着进水）→ 沿折线推进 → 位移按**弧长**记账 → `remaining ≤ 6 m` 判到达（**不吸附**，否则最后一帧最多瞬移 6 m）→ 朝向以 `300°/s × dt` 逼近段方向、`pitch` 夹 `±12°` 只作用于渲染。`StrategicCamera.pick_ground()`：地形没有碰撞体，视线 4 m 步进 + 二分 10 次（实测 0.003 m），返回**地面高度**；正交档射线起点在地图外，"采样点越界就退出"会让点击永远失败（§5 陷阱 38）。场景接线：根 **6 个子节点**（+`PartyLayer`），`s0_3_router` 第三次迁移（指纹 `Node3D:6` + 队伍在 / 棋子贴地 / 自带行军图三条能力断言）、`s1_2_mesh` 同步。用例 `s1_3_move` **50 断言 / 239 ms**：60 s × 3600 帧（固定 1/60，不读帧率）→ 贴地 ≤ **0.000004 m**、位移 ≡ `24 × 系数 × dt` ≤ **0.000043 m**、帧间转角 **0.087266 = 300°/s × dt**（顶满）、俯仰峰值 **12.00°**、零 NaN、零帧进水；A→B **20.6 s** 到达停在 **5.497 m**、改令立即反向（不回弹）；下单当帧就动 **0.540 m**、点击不挪相机焦点；同段 300 帧轨迹两次签名逐位一致。取证 `.shots/s13c/march_region`（`7da08faa…`）。全量 headless `--all` **37 用例 / 0 失败 / 7 跳过 / 39.1 s**；主场景 `--quit-after 120` 退出码 0、0 ERROR。**键盘行军按用户决定本批不做**（方向键已被相机占用，需与选部队 / 编队一起设计）。批 4（相册收口）待做 |
| S1.4 | 时间与日历系统 | S1.2 | ⏳ 未开始 | — |
| S1.5 | 聚落与交互菜单 | S1.1/S1.3 | ⏳ 未开始 | — |
| S1.6 | 遭遇、AI 队伍与追击 | S1.3/S1.4 | ⏳ 未开始 | — |
| S1.7 | 经济与补给 v1 | S1.5 | ⏳ 未开始 | — |
| S1.8 | 事件与任务 v1 | S1.6/S1.7 | ⏳ 未开始 | — |
| S1.9 | 大地图存档/读档完整性 | S1.6–S1.8 | ⏳ 未开始 | — |
| S1.10 | 大地图打磨与验收（M1 出口） | S1.0–S1.9 | ⏳ 未开始 | — |

> **M1 的设计输入（非本仓库产出）**：`docs/骑砍数据反推/` 六册（纳入经过见 §16 v1.8）。
> 它提供的是**可复核的量级与结构**（三条负反馈、剿匪作为唯一正向循环引擎、城堡被排除在经济系统外、
> 240 条部队/181 据点/23 旗帜的实体清单），不是可直接抄的数值。引用时的硬规则：
> **【实证】** 可直接采用 · **【推断】** 必须写明推理依据 · **【未解】** 一律不得填数。

### M2 Boss 战

| 步骤 | 名称 | 依赖 | 状态 | 验收证据 |
|---|---|---|---|---|
| S2.1 | 战斗场景框架与横版镜头 | S1.6 | ⏳ 未开始 | — |
| S2.2 | 帧数据战斗内核 | S2.1 | ⏳ 未开始 | — |
| S2.3 | 生命/韧性/削韧与受击 | S2.2 | ⏳ 未开始 | — |
| S2.4 | 弹反系统（反击斩） | S2.3 | ⏳ 未开始 | — |
| S2.5 | 闪避系统（提前蓄力） | S2.3 | ⏳ 未开始 | — |
| S2.6 | 蓄力系统（剑气/霸体） | S2.4/S2.5 | ⏳ 未开始 | — |
| S2.7 | Boss AI 与阶段化行为 | S2.3–S2.6 | ⏳ 未开始 | — |
| S2.8 | 战斗表现层 | S2.4–S2.7 | ⏳ 未开始 | — |
| S2.9 | 战斗 UI | S2.7 | ⏳ 未开始 | — |
| S2.10 | 战斗结算与回流大地图 | S2.7/S1.9 | ⏳ 未开始 | — |
| S2.11 | 战斗数值标定与手感验收（M2 出口） | S2.1–S2.10 | ⏳ 未开始 | — |

### M3 装备系统

| 步骤 | 名称 | 依赖 | 状态 | 验收证据 |
|---|---|---|---|---|
| S3.1 | 装备数据模型与数据表 | S2.11 | ⏳ 未开始 | — |
| S3.2 | 属性管线与角色面板 | S3.1 | ⏳ 未开始 | — |
| S3.3 | 背包/掉落/拾取 | S3.2 | ⏳ 未开始 | — |
| S3.4 | 装备对战斗的绑定 | S3.2/S2.2 | ⏳ 未开始 | — |
| S3.5 | 强化/修理/词条 | S3.3 | ⏳ 未开始 | — |
| S3.6 | 装备存档与验收 | S3.1–S3.5 | ⏳ 未开始 | — |

### M4 军团作战

| 步骤 | 名称 | 依赖 | 状态 | 验收证据 |
|---|---|---|---|---|
| S4.1 | 战场场景与上帝视角镜头 | S1.2/S1.6 | ⏳ 未开始 | — |
| S4.2 | 单位与小队数据模型 | S4.1 | ⏳ 未开始 | — |
| S4.3 | 单位渲染与性能架构 | S4.2 | ⏳ 未开始 | — |
| S4.4 | 群体移动与阵型 | S4.3 | ⏳ 未开始 | — |
| S4.5 | 指挥层（选队/命令） | S4.4 | ⏳ 未开始 | — |
| S4.6 | 接敌与战斗结算 | S4.4/S4.5 | ⏳ 未开始 | — |
| S4.7 | 玩家亲自上阵（单挑/斩将） | S4.6/S2.2 | ⏳ 未开始 | — |
| S4.8 | 胜负条件与战斗结算 | S4.6 | ⏳ 未开始 | — |
| S4.9 | 规模与性能验收（M4 出口） | S4.1–S4.8 | ⏳ 未开始 | — |

### M5 兵团升级

| 步骤 | 名称 | 依赖 | 状态 | 验收证据 |
|---|---|---|---|---|
| S5.1 | 兵种与升级树 | S4.2 | ⏳ 未开始 | — |
| S5.2 | 招募/征募/训练与经验 | S5.1/S1.5/S1.7 | ⏳ 未开始 | — |
| S5.3 | 升级界面与消耗 | S5.2/S3.3 | ⏳ 未开始 | — |
| S5.4 | 编成/带兵上限/负重与忠诚 | S5.2/S1.3/S1.7 | ⏳ 未开始 | — |
| S5.5 | 大地图联动（驻军/补给） | S5.4/S1.9 | ⏳ 未开始 | — |
| S5.6 | 兵团升级存档与验收（M5 出口） | S5.1–S5.5 | ⏳ 未开始 | — |

### M6 整合与商用打磨

| 步骤 | 名称 | 依赖 | 状态 | 验收证据 |
|---|---|---|---|---|
| S6.1 | 完整游戏循环串联 | M1–M5 | ⏳ 未开始 | — |
| S6.2 | 新手引导与教学 | S6.1 | ⏳ 未开始 | — |
| S6.3 | 设置/键位/存档管理/本地化接口 | S6.1 | ⏳ 未开始 | — |
| S6.4 | 性能与稳定性回归 | M1–M5 | ⏳ 未开始 | — |
| S6.5 | 内容量产管线 | S6.1 | ⏳ 未开始 | — |
| S6.6 | 发布构建与导出验收 | S6.4 | ⏳ 未开始 | — |

**合计**：**55 步**（M0:6 / **M1:11** / M2:11 / M3:6 / M4:9 / M5:6 / M6:6）。

---

## 16. 变更日志

| 日期 | 变更 | 原因 | 批准 |
|---|---|---|---|
| 2026-10-16 | 创建本文 v1.0；确认 D1–D4；定稿 M0–M6 共 53 步与验收标准 | 用户提出玩法扩展规划需求，本次仅做规划 | 用户（待审阅） |
| 2026-10-16 | v1.0 → v1.1：执行闭环由四步扩为五步，新增第 ⑤ 步「提交推送」；§15 台账「验收证据」列追加提交哈希要求；同步写入 `AGENTS.md`【二、版本控制与提交推送规范】 | 用户要求"每次阶段性修改验收通过后和单块功能完成后，做一次提交和推送，提交内容尽量详细" | 用户（本会话明确要求） |
| 2026-10-16 | v1.1 → v1.2：**S0.2 前置到 S0.1 之前执行**；§15 台账 S0.2 依赖改为「—（原 S0.1，批准前置）」；§5 S0.2 风险条目按探针实测结论改写 | S0.1 的验收项本身引用 `verify` 用例与 `img_diff`（S0.2 交付物），存在依赖倒置；§3.4 亦称工具链「S0.2 建成后全程使用」。用户在本会话选择「先做 S0.2 验收工具链」 | 用户（本会话明确选择） |
| 2026-10-16 | §3.4 验收工具链改为**实机跑通**的命令与取证约定；补充 `--case=`/`--out=` 在 verify 与 capture 间的归属规则（capture 仅在显式 `--shots`/`--shot=`/`--capture`/`--bench` 时工作） | 两工具共用同一 `OS.get_cmdline_user_args()` 命名空间，实测出现 verify 子进程被 capture 顺带触发、`quit(1)` 覆盖运行器退出码的缺陷 | 用户（本会话授权执行 S0.2） |
| 2026-10-16 | 新增 **Q13**：`B-` 视觉门禁阈值裁定；§5 S0.1 的 `B-` 项加注「阈值待裁定，裁定前不得判通过」；S0.1 `A-` 项符号数按实际契约更正为 19 个，并标注可复用 `s0_2_boot` / `s0_2_scene_api` | 实测同参数、同构建的两次独立渲染差异为 **1.62%–5.67%**（`shaders/toon.gdshader` 与 `shaders/water.gdshader` 用 `TIME`，`scripts/clouds.gd` 直接读 `Time.get_ticks_msec()`），原定 `< 0.1%` 客观不可达；不改阈值会让 S0.1 被一个恒失败的门禁阻塞 | **待用户裁定（Q13）**，本次仅登记与加注，未修改阈值本身 |
| 2026-10-16 | 附录 A 中 `scripts/capture.gd` 一行补注：触发条件由「任何取景参数」收紧为「显式截图标志」 | 同 §3.4 的缺陷修复，避免验收运行器被截图批次抢占退出码 | 用户（本会话授权执行 S0.2） |
| 2026-10-16 | **S0.2 验收通过 → `✅ 已验收`**，验收证据记入提交 `1ff5283`；同步写入 `docs/成果.md` 首条记录 | 用户在本会话确认「通过」；S0.2 四项验收标准均为 `A-`/`C-` 类且全绿 | 用户（本会话明确确认） |
| 2026-10-16 | v1.2 → v1.3：**Q13 裁定为选 (c)**「改动画时钟为可注入 `u_time`」；新增步骤 **S0.6 可复现渲染时钟**（M0 步骤数 5 → 6）；S0.1 的 `B-` 项恢复严格阈值并标注前置 S0.6；§15 台账 S0.1 依赖标注 `—（B- 需 S0.6）` | 原 0.1% 阈值在动画不可冻结时客观不可达；选 (c) 可换取真正逐位可复现渲染，长期收益最大（后续每步 `B-` 都能用严格门禁） | 用户（本会话三选一裁定） |
| 2026-10-16 | **S0.6 验收通过 → `✅ 已验收`**，验收证据记入提交 `457a7d2` + `953fd0d`；§3.4 的 `B-` 约定**收紧为逐位一致**（实测 0.0000%，比原定 `< 0.1%` 更严）；§5 S0.1 的 `B-` 前置条件解除，并补 `C-` 口径说明（基线被 vsync 封顶 60fps，只能拦"跌破上限"级劣化）；§5 S0.6 增补实测结论；§15 台账 S0.6 填证据、S0.1 依赖改为「前置 S0.6 已验收」；修正 §4 合计步数（M0 5→6，合计 53→54，v1.3 漏改） | 四项 `A-` 与 `C-` 全绿：两独立进程同参数截图 0 像素差异且 sha256 相同，`--yaw`/`--frames` 反向对照均正确触发（排除空图假通过与"动画被冻结"） | 用户（本会话批准执行 S0.6） |
| 2026-10-16 | 规范守卫新增规则 **`unfreezable_time`**：着色器内建 `TIME`（`.gdshader`）与 GDScript `Time.get_ticks_msec/usec`（`.gd`）一律判违例；测量用墙钟（`capture.gd` 的 `_benchmark` 计时、`terrain.gd` 的 `gen_ms` 统计）按既有白名单机制逐条登记理由。`tools/verify.gd` 新增 `_exec_user()`：强制在游戏侧参数前插入 `--`，并以 `--quit-after` 兜底 | 防止后续步骤重新引入不可冻结时间源；另实测缺失 `--` 会让 `OS.get_cmdline_user_args()` 为空、`capture.gd` 收不到 `--shots` 便不 `quit()`，而 `OS.execute` 无超时 ⇒ 整个验收套件静默挂死（实测 10 分钟），现退化为"清单没写出"的显式失败 | 用户（本会话批准执行 S0.6） |
| 2026-10-16 | **登记既有缺陷（本次未修）**：`tools/verify.gd` 的 `_case_baseline` 未把 `--out=` 透传给 `baseline.gd` 子进程 | 用 `--out=` 重定向报告目录时 `s0_2_baseline` 只得 3/7（找不到 baseline JSON）；默认目录下 15/15，故 S0.2 的既有验收结论不受影响。是否单独修复待用户决定 | 待用户决定 |
| 2026-10-16 | **Q10 结案：存档形态裁定为「3×3 九宫格 / 固定 9 槽 / 不自动存档 / 无云同步」**；新增 **§3.5 存档与菜单规范**作为公共契约（槽位布局、唯一触发路径、槽位卡片信息、写入安全、与调试快捷键的关系）；§5 S0.3 补菜单页与宫格框架及其 4 项 `A-` + 1 项 `D-`；§6 S1.9 补 9 槽独立性与零自动存档 2 项 `A-`；§11 S6.3 存档管理改为复用宫格并补删除与多分辨率项；§14 Q10 置为已裁定 | 用户在本会话明确要求：① 用 3×3 宫格页面给九个存档槽位；② **不自动存档**；③ `ESC` 到菜单页，点击「保存」「另存为」才触发存档。该决策决定 SaveSystem 槽位模型与菜单 UI 结构，必须在 S0.3 开工前固化 | 用户（本会话明确要求） |
| 2026-10-16 | **S0.1 执行方案登记**（§5 S0.1）：目录映射表（15 个脚本 + 3 个着色器逐项定去向）、6 批迁移顺序与独立提交/回滚点、4 条执行陷阱；`shaders/` 约定**增补子目录 `common/`**（§3.2 同步改写）；`scenes/main.tscn` 在 S0.1 **不移动**（改名留到 S1.2）；§15 台账 S0.1 置 `🚧 进行中` | 与本会话对齐后定稿：① 全部按 §3.2 九目录归类、不新增 scripts 子目录；② `toon`/`outline` 归入新增的 `shaders/common/`（放 `fx/` 或 `character/` 名不符实）；③ 主场景留到 S1.2 与 `main.gd` 拆分一起改名；④ 6 批迁移（批次 0 基线 + 5 批代码/文档），每批独立提交并各自跑 `A-`/`B-` 校验 | 用户（本会话四选一，均取推荐项） |
| 2026-10-16 | **S0.1 验收通过 → `✅ 已验收`**：6 批迁移全部完成（批次 1–4 代码移动记为 `1bab8fd` / `16b7196` / `1aa739c` / `534e2bd`）；产出 `docs/ENGINEERING.md`（目录职责 + 旧→新映射表 + 迁移前基线 sha256 + 执行陷阱）；§3.1 既有资产清单的路径同步为重组后路径；§5 S0.1 陷阱清单由 4 条增至 6 条 | 验收全绿：窗口 `verify.gd --all` 8 用例 / 152 断言全通过 / 退出码 0；headless 8 用例 0 失败 2 跳过；推送门禁 0 条 ERROR；**`B-` 6 机位与迁移前基线逐位一致（6/6 sha256 全等）**，且每批迁移后各自复跑过一次 | 用户（本会话批准执行 S0.1） |
| 2026-10-16 | §5 S0.1 陷阱清单补登两条实测结论：⑤ `.godot` 全局类缓存不随文件移动更新（须删缓存 + `--headless --import` 重建）；⑥ 着色器路径写错不报错、只静默回落默认材质 | 批次 1 首次执行即因⑤失败（`Could not find script for class "MeshUtil"` / `Class "CameraRig" hides a global script class`），属环境缓存而非内容错误；⑥ 决定了批次 4 必须用逐位比对而非"退出码 0 + 无 ERROR"判定 | 实测登记（S0.1 执行过程） |
| 2026-10-16 | `docs/ENGINEERING.md` 新增为**长期工程约定文件**（目录职责、引用规则、迁移映射表、基线哈希、执行陷阱）；§3.2 的目录约定仍是权威定义，本文件为其落地记录 | S0.1 交付物要求「记录目录职责与迁移映射表」；把"哪类文件该放哪 + 移动文件必改哪 4 处 + 5 条陷阱"固化下来，后续 M1–M6 新增模块可直接照做 | 用户（本会话批准执行 S0.1） |
| 2026-10-16 | **验收标准修改：Autoload 上限 6 → 10**。§3.2 的「Autoload 上限 6 个」改为 10 个；§5 S0.3 的 `A-` 由「autoload 数量 ≤ 6」改为「≤ 10」；§3.2 同时补齐既有 autoload 列表（原漏写 `Clock`，实际为 `Style` `Capture` `Clock` 3 个）；`docs/ENGINEERING.md` §1/§6 与 `docs/成果.md` 同步 | **S0.3 与自身验收标准冲突**：S0.3 要求「autoload ≤ 6」，却要新增 4 个（`GameState` `EventBus` `SceneRouter` `SaveSystem`），现有 3 个 → 共 7 个，必然违反。两条备选：① 合并服务（如 `SceneRouter` 并入 `GameState`、`SaveSystem` 延后）；② 放宽上限。**选 ②**：不为迁就一个数字把职责不同的服务硬塞成"上帝对象"，且 10 留 3 个余量给 M1–M6（含 §3.2 要求的 `Rng` 服务，若日后落为 autoload） | **用户（本会话明确指示"autoload 修改原有验收标准，把上限放宽到 10 个"）** |
| 2026-10-16 | **S0.3 执行方案登记**（§5 S0.3）：4 批划分（服务 / 存档 / 路由 / UI）与每批的交付物、同批必改项、autoload 计数（3 → 6 → 7 → 8）、新增校验用例；每批验收门禁；**5 个设计决定**（拆 4 批 / 新建 `scenes/battle/battle_stub.tscn` 作路由靶子 / `Rng` 纳入本步但暂不收编既有裸 `randi()` / 存档用例整体换名 `user://saves/` ↔ `saves.bak` 做隔离 / `ESC` 暂停世界但 `Clock` 与 UI 保持 `PROCESS_MODE_ALWAYS`）；**6 条预登记陷阱**；§3.2 的 autoload 列表补入 `Rng`（合计 8）并新增"已发生事实"信号命名族；§15 台账 S0.3 置 `🚧 进行中` | 与本会话对齐后定稿。关键权衡：① `Rng` 越晚收编越贵，但收编既有 `randi()` 会改变地形/植被随机序列 ⇒ 6 机位基线失效，故只建服务、不收编；② 存档测试若走"产品码支持测试保存根"会给发布构建留下旁路，故改用目录整体换名，零产品码改动；③ `get_tree().paused` 会连带停掉 autoload，故须逐节点显式设 `PROCESS_MODE_ALWAYS` | 用户（本会话五问五答，均取推荐项） |
| 2026-10-16 | **S0.3 批次 1 落地：autoload 3 → 6**。新增 `scripts/core/rng.gd`（`Rng`，FNV-1a 具名子流）、`scripts/core/event_bus.gd`（`EventBus`，5 个过去式事实信号、无状态）、`scripts/core/game_state.gd`（`GameState`，10 个存档字段 + `snapshot()`/`restore()` 容错 + `_physics_process` 固定逻辑步推进游戏时间）；`project.godot` 注册三者且 **`Rng` 先于 `GameState`**（后者 `_ready()` 要调用 `Rng.seed_from`）；§3.2/§5 S0.3/附录 A 的 autoload 计数与描述同步；`docs/ENGINEERING.md` §1/§6 同步。**记录两条负面结论（在 §15 与 `docs/成果.md` 展开）**：① `SceneTree.physics_frame` 在节点 `_physics_process` **之前**发射 ⇒ "N 次 await == N 步"是错的（实测 60 次 await 只推进 59 步），用例改断言"前进量恒为 1/60 的整数倍"；② `Script.get()` 读不到 `const`，读常量须用 `get_script_constant_map()` | 批次 1 是全 4 批里唯一"只加服务、不改画面"的一批，因此它的验收意义在于**证明新增 autoload 对渲染零影响**：`B-` 6 机位 sha256 与 S0.1 迁移前基线全等（6/6），manifest `det=True hz=60.0 t=2.5 frame=150`。`GameState.world_seed` 默认值刻意取 `20250929`（与 `main.gd` 的 `@export` 同值），使 S1.2 把场景入口接到本服务时世界逐位不变 —— 该同值性由 `s0_3_state` 断言守住 | 用户（本会话批准执行 S0.3 批次 1） |
| 2026-10-16 | **S0.3 批次 2 落地：autoload 6 → 7**。新增 `scripts/core/save_system.gd`（autoload `SaveSystem`，注册在 `GameState` **之后**）：`SAVE_DIR="user://saves"` / `SLOT_COUNT=9` / `schema_version:1` / `meta` 槽位卡片字段 / `migrations` 版本链钩子 / 脏存档与脏字段容错 / `save_written`·`save_failed`·`load_failed`·`slot_loaded` 四信号；**无 `_ready`、无 `_process`、不订阅 `EventBus`**，目录由首次写入惰性创建（无自动存档的静态与动态双证据）。`tools/verify.gd` 新增 4 用例（`s0_3_roundtrip` 63 / `s0_3_dirty` 47 / `s0_3_atomic` 29 / `s0_3_no_autosave` 17 断言）与 3 个隐藏探针（跨进程写 / 读回吐 / 狂写循环）；`s0_3_state` 的 autoload 契约 6 → 7 并把 `SaveSystem` 排在 `GameState` 之后的顺序纳入断言。**同时修好三个验收工具的坑（详见 `docs/ENGINEERING.md` §5 陷阱 6–9）**：① 引擎 rename 覆盖在 Windows 上非原子（读者须重试）；② `JSON.parse_string()` 解析失败会打引擎级 `ERROR`，坏存档是正常输入，改用 `JSON.new().parse()`；③ `OS.create_process()` 子进程不继承 stdout，子进程结论必须落文件；④ 子进程只认 `--` 之后的 `--out=`，`s0_2_baseline` 因此曾整例失败且有假通过风险（已修正并补"运行前删旧报告 + 断言不存在"） | 批次 2 的验收核心是**"没有自动存档"要能被证伪**：用例先证明检查本身有效（正对照：显式 `save_slot` 一定改变目录快照），再断言全流程零变化；同时用**真跨进程**（不是同进程两次调用）证明存档文件是进程间事实。另一个关键判断：单进程探针只看末态会得出"rename 覆盖无空窗"的错误结论，**跨进程并发观测才推翻它**——这条负面结论已写入 §5 S0.3 陷阱 2 与 `save_system.gd` 文件头，成为后续所有 `user://` 写入的既定约束 | 用户（本会话批准执行 S0.3 批次 2） |
| 2026-10-16 | **S0.3 批次 3 落地：autoload 7 → 8**。新增 `scripts/core/scene_router.gd`（autoload `SceneRouter`）与占位战斗场景 `scenes/battle/battle_stub.tscn`（`scripts/battle/battle_stub.gd`，M2 替换）。路由器是**唯一**允许调 `change_scene_to_file()` 的文件——守卫新增第 8 类规则 `scene_change_owner`（按属主路径白名单放行，`s0_2_guard` 由 7 类升为 8 类，并带正负对照：路由器路径 0 命中、`terrain.gd` 里同一句恰好 1 命中）。栈为浅栈 `world` → `battle`（`MAX_DEPTH = 2`），三类越界（重复进入、栈满、非战斗返回）各自给出**指名原因**且不改动状态；`_expected_path` 挡同帧第二次切换；栈与屏幕对账（`_sync()`），场景被外部释放后 `current_route()` 归空。`s0_3_state` 的 autoload 契约 7 → 8；新增 `s0_3_router` 70 断言。**本次记录 3 条实测结论（详见 `docs/ENGINEERING.md` §5 陷阱 10–12）**：① `change_scene_to_file()` 在 `--script`（SceneTree MainLoop）下**可用**，但 `current_scene` 第 1 帧仍为 `null`、第 2 帧才是新场景（陷阱 3 的量化确认）；② `SceneTree` 子类里**没有** `get_tree()`，应直接用 `current_scene` / `get_node_count()`；③ 节点自动名（`@MeshInstance3D@28`）含全局计数器，两次加载必然不同 ⇒ 结构指纹必须先把 `@` 开头名字归一为 `get_class()`，归一后 92 条指纹**逐位可复现**（`fe520385…`） | 批次 3 的验收核心是**"回到世界是不是同一片世界"**：只断言节点数 ±0 太弱（总数相同、结构换了也过），故加两层——世界子树的**结构指纹**（92 条 `名字/类:类:子节点数`）与 **seed 派生值**（`spawn_point`、`height_at` 采样、`Scatter.stats` 树石数）必须逐条一致；同时用"外部释放场景后路由归空"证明路由栈不是一份永不更新的自述。占位场景刻意保持**纯函数**（无 `Rng`/时钟/`_process`），只做"能当靶子"的最小合规：正交相机 + `MeshUtil.facet()` 低模地面 + 逆壳描边 + `Style.PALETTE`，故 `B-` 6 机位不受影响（6/6 逐位一致） | 用户（本会话批准执行 S0.3 批次 3） |
| 2026-10-16 | **S0.3 批次 4 落地（S0.3 最后一批）：菜单页 + 3×3 九宫格 + 覆盖二次确认**。新增 `scripts/ui/menu_page.gd`（三页：主页/宫格/确认弹窗；`ESC` 四级层级；`PROCESS_MODE_ALWAYS`）与 `scripts/ui/save_grid.gd`（9 张槽卡片，正文只读 `SaveSystem.slot_info()`）；`scenes/main.tscn` 挂载 `MenuLayer` 且**默认隐藏**；`render_clock.gd` / `ui_panel.gd` 补 `PROCESS_MODE_ALWAYS`；`capture.gd` 的 `--shots` 增加 UI 步骤驱动与 `ui_expect` 自证行（产品码无演示状态后门）。新增 `s0_3_slots` 100 断言、`s0_3_overwrite` 34 断言、4 张菜单 `B-` 截图。窗口 `--all` 16 用例 / 0 失败 / 0 跳过 / 594 断言 / 71843 ms；headless 16 / 0 失败 / 4 跳过 / 411 断言 / 14742 ms；`B-` 6 机位与 S0.1 基线全等（6/6）；菜单 4 张两轮逐位一致且两两不同。**两条负面结论**：① `--all` 是**同进程顺序跑**，用例间的全局残留（`SaveSystem.current_slot`）必须显式复原，否则后置用例会静默退化成"另一条分支"；② 同一秒内两次存档字节可以逐位相同（`saved_at` 到秒），判"确实写过"要看 `save_written` 的发布次数而不是哈希。**登记两项未闭环**：`D-` 人工试玩；淡入淡出过渡（幕布需活过场景释放 ⇒ 需先对齐属主设计，顺延独立小步）。`C-` 内存 91.3 → 126.13 MB 经独立探针拆分：菜单子树 77 节点 = 34.29 MB（主体是中文 `SystemFont` 及字形缓存），已登记"换子集字体可省 ~30 MB"为后续可选项 | 用户（本会话五问五答后批准执行 S0.3 批次 4；其中覆盖确认形态由用户在"行内提示 vs 独立弹窗"中选择**独立弹窗**） |
| 2026-10-16 | **S0.3 收尾：`D-` 人工试玩通过，本步置 `✅ 已验收`**。用户在批次 4 推送后自行试玩：`ESC` 菜单开合、宫格选槽、覆盖二次确认全流程手感确认通过，**无返工项**。据此：§5 S0.3 的 `D-` 由"待试"改为"已通过"、状态 `🚧 进行中` → `✅ 已验收`；§15 台账 S0.3 行同步。**仍留在台账里的两项不因此闭环**：① 淡入淡出过渡（幕布须活过场景释放 ⇒ 需先对齐持久属主，独立小步）；② UI 内存可选项（中文 `SystemFont` 占 34.29 MB，换子集化随包字体可省 ~30 MB）。用户明确指示：**先不做下一个任务**，故 S0.4 保持 `⏳ 未开始` | 用户（本会话明确反馈"调试通过，结论保存文档，先不进行下个任务"） |
| 2026-10-19 | **S0.4 拆为 3 批并登记批次 1**：批次 1 = 抽 `UiKit` 公共控件工厂（`scripts/ui/ui_kit.gd`，`ui_panel` / `menu_page` / `save_grid` 三份重复的 stylebox / 阴影偏移 / 标签构造合一），提交 `ed92e66`；批次 2 = 叠加层 + `F1`/`F3` + CSV；批次 3 = `F5`/`F9` + 菜单调试入口（顺延）。§5 S0.4 补批次表、§15 台账 S0.4 置 `🚧 进行中` | `ed92e66` 已按 §0.1 五步闭环推送，但 §5/§15 当时仍写 `⏳ 未开始`，台账与仓库事实不一致 —— 台账是唯一状态来源，不能落后于代码。批次 1 补登记为追溯性质，未重新执行 | 用户（本会话对齐时确认 `ed92e66` 属 S0.4 批次 1） |
| 2026-10-19 | **S0.4 批次 2 落地：autoload 8 → 9（新增 `Debug`）**。新增 `scripts/core/debug_layer.gd`（497 行，`extends Node`，autoload `Debug`）：默认隐藏的 `CanvasLayer` 30（层号 30 > 菜单 20 > HUD 10，整层 `MOUSE_FILTER_IGNORE`）、`_draw` 自绘帧时间曲线（纵轴固定 0–33ms ⇒ 图形是采样值的纯函数，不含任何墙钟）、节点/分组计数、场景与路由栈、时钟与 `Rng` 子流；`input_setup.gd` 新增 `debug_ui_hide`（`F1`）/`debug_overlay`（`F3`）与**唯一闸门** `ensure_debug_hotkeys(OS.is_debug_build())`（关掉时**删除 action**，不是留着不注册）；`capture.gd` 支持 `ui: ["key:f3"]` 步骤与 `ui_expect.overlay/ui_hidden` 自证；`debug_layer.gd` 支持 `--obs-csv=`（纯修饰符，不触发截图、不抢退出码；确定性模式下 `draw_calls`/`prims`/`ms_process` 三列**留空**而非写 0）。新增用例 `s0_4_overlay` 70 断言 + `s0_4_cost` 32 断言。窗口 `--all` **18 用例 / 0 失败 / 0 跳过 / 106755 ms**、退出码 0；headless 18 / 0 失败 / 5 跳过、退出码 0；`B-` 6 机位与 S0.1 基线**全等（6/6）** | 用户（本会话三问三答，均取推荐项：只做批次 2 / 新增 autoload `Debug` / `_case_baseline` 单独提交修掉） |
| 2026-10-19 | **更正过期台账：`_case_baseline` 的 `--out=` 透传缺陷其实早已修好**。2026-10-16 那行"登记既有缺陷（本次未修）"已过期 —— `git blame` 显示 `tools/verify.gd` 里 `--out=` 的透传由提交 `93c25e6` 引入，此后 `s0_2_baseline` 在任意 `--out=` 目录下都能拿到 baseline JSON。故**不做**无意义的重复修复，改为：① 在 `_case_baseline` 补一条**回归锚点**断言（换目录跑，报告必须落在新目录、且默认目录里没有它，防"两个目录都写"的假通过），`s0_2_baseline` 由 15 → 21 断言；② 在此更正记录。`docs/成果.md` 中两处"未修"同步更正 | 用户在批次 2 对齐时选择"单独提交修掉"，核查后发现无需修 —— 直接照办会造出一个改不动任何行为的空提交，且会把"已修"的事实继续留在"未修"的记录里 | 用户（对齐时的选择；核查结论回报后按推荐项改为补回归锚点） |
| 2026-10-19 | **`C-` 开销断言改写：从"帧时间差"改为"直接给叠加层每帧工作计时"**。原写法"开层/关层帧时间差 < 0.5ms"经两次实测证明**测不出东西**：① vsync 开着时差值是**负**的（关层 18.75 / 开层 17.84 ms，量到的是 vsync 等待与抖动）；② 关掉 vsync 改逐帧墙钟后，注入确定的 2ms/帧 自旋负载**只回收 41%**（2.000 → 0.817）。即该断言叠加层再贵也会绿。改为直接计时 `_push_sample()`（每帧）+ `_refresh()`（每 6 帧），与 `_process()` 真实节奏一致，实测 **0.0044 ms/帧**（5 轮 × 400 帧中位数）；并新增**标尺**断言：同口径注入 0.5ms / 2ms 自旋，量到 0.5000 / 2.0000（回收率 ≈100%），先证明这套计时能分辨 0.5ms。另把 `_sample_ms()` 的监视器由 `Performance.TIME_PROCESS` 换成逐帧 `Time.get_ticks_usec()` 墙钟 | 一条"某东西很便宜"的断言，必须同时证明"这套量法测得出它变贵"，否则只是沉默的绿灯。`Performance.TIME_PROCESS` 在本工程连 2ms 负载都测不出（关 vsync 后量化到 78.58 / 6.204 两个离散值，带负载反而更低），不可用于 0.5ms 量级 | 实测登记（S0.4 批次 2 验收过程） |
| 2026-10-19 | **`project.godot` 被编辑器改写的问题结案**。Godot 编辑器打开工程时会剥掉 `project.godot` 里的 `;` 注释并把 `[shader_globals]` 移到文件末尾 —— 本步期间发生两次。处理：`git checkout -- project.godot` 复原，再按 HEAD 的注释原样补回，并在末尾追加 `Debug` 的 4 行注释 + 注册行；复核 `git diff` 只含预期新增。**约定**：改 `project.godot` 后用 `git diff` 逐行确认，不要直接 `commit` | 编辑器把文件当作"自己的格式"重写，任何手写注释都会丢；若不复核就提交，会把无关的整文件重排混进功能提交（违反 §二 2.1「一次提交只承载一件事」） | 实测登记（S0.4 批次 2 验收过程） |
| 2026-10-19 | **S0.4 批次 3 落地：`F5` 快存 / `F9` 快读 + 菜单调试页**。`input_setup.gd` 新增 `debug_quick_save`（`F5`）/`debug_quick_load`（`F9`），与 `F1`/`F3` 共用同一个闸门；`debug_layer.gd` 新增 `quick_save()` / `quick_load()` / `notice()` / `is_confirm_pending()` 与独立 `ToastLayer`（`LAYER + 1`，按帧过期，服从 `F1`）；`capture.gd` 的 `KEY_BY_NAME` 补 `f5`/`f9`；`menu_page.gd` 的「设置」占位改为调试页（`show_debug()` / `debug_facts()` / 「打开叠加层」按钮），`ESC` 层级由三级变四级（弹窗 → 宫格/调试页 → 主页 → 关闭）。新增用例 `s0_4_quick` 62 断言。窗口 `--all` **19 用例 / 0 失败 / 0 跳过 / 761 断言 / 108015 ms**、退出码 0 | 用户（本会话两问两答：`F5` 只做直写不弹菜单 / 菜单调试入口填实现有的「设置」页） | 用户（本会话明确选择） |
| 2026-10-19 | **`F5` 的覆盖确认：不弹菜单，改为"再按一次"**。§3.5 要求覆盖已占用槽位必须二次确认，而批次 3 的对齐结论是"直写、不弹菜单"。两者同时成立的写法只有一种：确认落在按键上 —— 第一次 `F5` **不写盘**，只登记待确认（`CONFIRM_WINDOW_FRAMES = 120` 帧）并给出理由，窗口内再按一次才真覆盖。`s0_4_quick` 用"第一次按完旧档 sha256 逐位不变"取证，并另验窗口过期后单按一次又回到"先拒绝"。**注意**：这不是新增一套规则，写入仍全部走 `SaveSystem.save_slot()`，本层只决定"现在要不要发起这次写入" | 静默覆盖会直接违背 §3.5，也会让 `s0_3_overwrite` 那 34 条断言失去意义；而"不弹菜单"是用户对齐时的明确结论。若两者只能取一，应当回来问用户，而不是自行弱化其中一条 | 用户（对齐结论 + 本条补充说明） |
| 2026-10-19 | **闸门必须做在函数内部，不能只在 `_input` 里**。`_input` 只挡按键，挡不住"有人直接调 `quick_save()`"。§3.5 要求发布构建**完全禁用**，故 `quick_save()` / `quick_load()` 开头各自检查 `_quick_enabled()`（= 两个 action 在不在，与 `F1`/`F3` 同一个事实来源）。**不要**在调试页里再写一次 `OS.is_debug_build()`：`s0_4_overlay` 守着"全项目只有 `input_setup.gd` 一处判断构建类型"，本步第一版就是这么写坏的（调试页加了一行 `OS.is_debug_build()`，该断言立刻从 1 处变 2 处而红）。构建类型的等价观测就是"调试热键注册了没有" | 一条"发布构建完全禁用"的断言，若只在输入路径上挡，任何直接调用（含未来新加的 UI 入口、测试代码）都能绕过；而"两处判断构建类型"是同一个事实的二次表述，迟早漂移 | 实测登记（S0.4 批次 3 验收过程） |
| 2026-10-19 | **headless 下窗口尺寸 0×0 ⇒ `pure` 用例不能验鼠标命中**。本步给调试页按钮写点击断言时，`_click_control` 报告"矩形已排出、点击落下了"，但处理器一次都没跑。实测 `DisplayServer.get_name() == "headless"`、`window_get_size() == (0,0)`：注入的鼠标事件没有可命中的视口。改法：`pure` 用例只验"按钮在 + 连着处理器 + 处理器真驱动 `Debug`"（直接 `pressed.emit()`），鼠标命中路径交给 headed 的 `s0_3_slots`（同一套 `UiKit.button_page` 工厂与页面结构）。**一般结论**：凡是 `--headless` 下要验"点得着"，都得先问一句"这个视口存在吗" | 这是继陷阱 16–19 之后同一类的坑：headless 让某个观测维度整体归零，断言却照样绿或照样红，且失败信息（"点击落下了"）指向错误的方向。`_click_control` 的返回值只说明"矩形非退化"，不说明"事件被谁接住" | 实测登记（S0.4 批次 3 验收过程） |
| 2026-10-19 | **v1.3 → v1.4：合并 `docs/spec.md` 的 M1 契约与排期裁定（M-1…M-12 逐条落地）**。① **新增步骤 S1.0 场景与路由迁移**（M1 步骤数 10 → 11，合计 54 → 55），拆 4 个可独立回滚子步；② **S1.4 增「时钟收敛」**：`GameState.game_time` 升级为唯一游戏时钟、`DayNight` 改派生、`Clock` 保持渲染专用，变速实现定为"每帧 N 次完整固定步"，并新增 **`day_length` 语义变更 + 存档 schema v1→v2 迁移**与用例 `s1_4_speed`；③ **S1.9 增 schema v2 与 `FIELD_MANIFEST`**（含反向对照断言）；④ **S1.5 增本地化（Q2 裁定）与「先扩 `UiKit` 再写面板」**；⑤ **S1.6 冻结 `BattleContext`/`BattleResult` 字段表、占位结算、两级迷雾（Q9 裁定）**，并明确 AI 必须是纯函数；⑥ **S1.1 参数表改为"可改默认值"**（Q14 新增并裁定）+ 锚点优先级 + 生成实现要点；⑦ **S1.10 增 M1 出口四问**（路线 B 的门禁）；⑧ §3.4 增 `--scene=` 取景命令；⑨ §4 登记排期路线 B + 不设硬期限 + 人日估算；⑩ §13 R4 改为「不提前」；⑪ §14 Q2/Q4/Q9 置为已裁定、新增 Q14；⑫ §15 台账补 S1.0 行、S1.10 依赖改 S1.0–S1.9、合计改 55；⑬ 附录 A 更正 4 行（`main.gd` / `main.tscn` / `terrain.gd` / `camera_rig.gd` 的"不回改"结论）并补 5 个新增文件 | 与用户就 8 个决策点逐项对齐后写入 `docs/spec.md`（v0.1→v0.3），本条把其中**影响 ROADMAP 的 12 项**合并回来。合并前 `docs/spec.md` 只作辅助文档，ROADMAP 仍是唯一状态来源 —— 二者不一致时以本条为准 | 用户（2026-10-19 明确要求"先合并需求再执行任务"，并批准开始合并） |
| 2026-10-19 | **v1.4 → v1.5：S0.5 落地（工程规范 + 美术管线文档）并更正 4 处过期条文**。① **信号命名规则按实际代码更正**：`on_xxx`（按钮）→ `*_pressed`（按钮）。既有 7 处实现（`ui_panel.gd` ×5、`save_grid.gd` ×1、`debug_layer.gd` 的 `overlay_toggled`）一致用过去式，改名会让 7 个信号与其连接点同时变动却不带来行为收益 ⇒ **改规则不改代码**。② **§3.2 autoload 计数更正**：原文"合计 8 / 当前 6"，实际为 **9**（S0.4 批次 2 新增 `Debug` 后未同步）；余量 2 → 1。③ **§3.2 目录结构补 `scripts/dev/`**：教材夹具需要一处**允许故意违例**的目录，并配硬约束"产品码不得引用 `scripts/dev/`"。④ **`Canon` 明确标为未实现**：附录 A 列的 `scripts/core/canon.gd` 不存在，S0.5 只在文档里写契约（JSON 格式 + 读入钳制告警 + 文本存 key），落地留 S1.1；验收用例断言"待建"标记存在，而不是假装它已存在 | 与用户就 3 个决策点逐项对齐：**范围**=S0.5 全量一次做完（不拆批）、**信号**=以实际代码为准改规则（另两个选项"重命名 7 处信号""双约定并存"被否）、**Canon**=只写契约留给 S1.1。另附带修掉 `docs/ENGINEERING.md` §5 陷阱 3 的过期描述（`GUARD_WHITELIST` 实际按 `path`+`rule` 匹配，不含行号） | 用户（2026-10-19 对齐三轮问答后批准执行） |
| 2026-10-19 | **v1.6 → v1.7：S0.5 闭环（`D-` 用户确认）**。§5 S0.5 状态 `🧪 待验收` → `✅ 已验收` 并补「验收记录」表（`A-`/`B-`/`C-`/`D-` 逐项 + 窗口/headless `--all` 实测 + 启动门禁 + autoload 计数）；§15 台账 S0.5 行填实验收证据（提交 `9070501`）。同时更正两处我复核时发现的过期事实：① §5 S0.5 落地记录写"11 个 `class_name`"，实测为 **12**（`Select-String '^class_name '` 逐个数出 `Player`/`CameraRig`/`InputSetup`/`MeshUtil`/`UiKit`/`UiPanel`/`BrutalSlider`/`CloudField`/`DayNight`/`Scatter`/`Terrain`/`WaterSurface`）；② 落地记录原写"§7–§12"，实际已补到 **§13**。文档头部状态改为"M0 全部闭环，下一步进入 M1" | S0.5 的 `D-` 由用户于 2026-10-19 明确确认"确认"；两处数字更正来自 §15 填证据时的复核（避免把错误数字写进台账） | 用户 |
| 2026-10-19 | **v1.5 → v1.6：修掉注入点击的既有缺陷（缺鼠标移动）**。`tools/verify.gd::_click_control()` 与 `scripts/core/capture.gd::_click_path()` 原本只注入 `InputEventMouseButton` 的 press/release，**没有 `InputEventMouseMotion`**。Godot 的 `Viewport` 用 `gui.mouse_focus` 决定把按键投给谁，而该焦点**由鼠标移动事件更新**；没有移动，按键就落在失效焦点上 ⇒ `s0_3_slots` 间歇性失败（**在 HEAD 上跑 5 次红 2 次**，失败点每次不同：读取没跳宫格 / 另存为没进宫格 / 两轮截图 sha256 不一致）。修法：点击前先发一个落在目标中心的 motion 事件，**不动产品码**。修后 `s0_3_slots` 连跑 18 次全绿、`--all` 连跑 2 轮全绿。另给 `_shoot_menu_case()` 加了失败时打印子进程末尾 20 行的诊断（原来只知道"少了一次自证"，不知道少在哪一步） | 本步在 `--all` 里偶发命中该失败。**先证明了它是既有的**：把 `git show HEAD:tools/verify.gd` 导成临时脚本跑同一用例，同样红。**失败点漂移是"共享前置条件坏了"的典型特征** —— 每次都红同一条是断言的问题，红点到处跑说明更早的某一步时灵时不灵 | 用户（S0.5 验收过程中发现） |
| 2026-10-19 | **v1.7 → v1.8：纳入 `docs/骑砍数据反推/` 六册作为 M1 设计输入；并修掉 §16 表内 3 处空行**。① 新增 §6 M1 开头的「设计参考」引用块：六册是《战团》Native 模块的逆向文档（编译脚本字节码 + 数据表 + `mb_warband.exe` 反编译），自带 **【实证】/【推断】/【未解】** 三级标签；明确其为**设计输入而非本项目规范**，只借结构与量级、不照抄数值，【未解】项不得填数。② 落地引用点写明是 S1.1 的 `data/world/gen_params.json` 初值与 `Canon` 钳制告警口径。③ 六册共 6 文件 / 460,554 字节 / 6,563 行，单独一个 `docs` 提交入库（不与代码改动混提） | 用户 2026-10-19 指示："`docs/骑砍数据反推`，是我反编译骑砍的代码反推出来的玩法和数值设计相关文档，可以作为大地图设计的参考。" 三级证据标签与本项目"不猜测"的验收文化同源，故正式登记为 M1 输入 | 用户 |
| 2026-10-19 | **§16 表内 3 处空行修正**（格式缺陷，非内容变更）：v1.4→v1.5、v1.6→v1.7、v1.5→v1.6 三行之间各有 1 个空行，会把 Markdown 表格截断成 4 张独立表格。成因是 v1.7 那次"两行被合并成一行"的修复：拆分时在边界处留下了空行 | 复核 §16 表格时按行打印长度发现（`len=0` 夹在数据行之间）。**教训**：表格类编辑修完必须回读**相邻行**，只验证"被改的那行"看不出表格已被截断 | 自查（S1.0a 准备阶段） |
| 2026-10-19 | **v1.8 → v1.9：S1.0a 落地并闭环（搬场景不改像素）**。① `git mv scenes/main.tscn scenes/dev/diorama.tscn`，Git 判定 **100% 相似度重命名**（场景内容零改动）；② 三处事实源 + 两处工具同步换路径：`project.godot` 的 `run/main_scene`、`SceneRouter.SCENES[world]`、`tools/baseline.gd`、`tools/verify.gd::_load_main()`，注释里的旧路径一并更新；③ `s0_3_router` 由 70 → **73 断言**，新增「`run/main_scene` == `scene_path_for("world")` == 文件真实存在」——把过去靠 `git diff` 人工核对的约定变成机器判定（三处漏一处即红）；④ `s0_5_doc_conventions` 的「产品码不得引用 `dev/`」由零容忍改为**登记清单**：`scenes/dev/` 允许 `scene_router.gd` 一处（S1.0d 后自然收紧回 0），并加反向对照证明清单不是恒真；⑤ §5 S1.0 子步表由 3 列补为 **4 列**（原先 S1.0a 行末尾多挂一个单元格，整表渲染错位）；⑥ §15 台账 S1.0 置 `🚧 进行中`（a ✅ / b–d ⏳），头部版本 v1.8 → v1.9 | `B-` 是"搬文件不改像素"的唯一硬证据：重采 `.shots/s10a_post`，**6/6 sha256 与 `ENGINEERING.md` §4 基线逐位相等**；窗口 `--all` **20 用例 / 0 失败 / 0 跳过**、headless 20 / 0 失败 / 5 跳过，均退出码 0 | 用户（本会话四问四答，均取推荐项：只收尾 S1.0a / 窗口全量校验 + 重采 6 机位 / 单个提交 / 两处缺陷同批修） |
| 2026-10-19 | **v1.9 → v2.0：S1.0b 落地并闭环（`--scene=` 指定取景场景）**。① `scripts/core/capture.gd` 新增 `--scene=res://…`，定位为**纯修饰符**（与 `--case=` / `--out=` 同级：单独出现不触发批次、不抢退出码）；② `_swap_scene()` 手动换 `SceneTree.current_scene`（不调 `change_scene_to_*` —— `scene_change_owner` 属主仍只有 `SceneRouter`），并四条自证：新实例接管 / 新实例路径 == 要求 / 旧场景已释放 / 相机组最多 1 台，任一不成立退出码 1；③ 截图清单新增 `scene` 字段自报拍摄场景（图与参数可对账）；④ 新增用例 `s1_0_scene_arg` **31 断言**（headed）：缺省 / `--scene=diorama` ×2 / `--scene=battle_stub` 四个独立进程 + 坏路径退出码 1 + `--scene=` 独走不写清单 + `SCENE_CHANGE_OWNERS` 仍只有 1 个属主；⑤ §5 S1.0b 行置 ✅ 并补落地记录（含两个坑）；⑥ `docs/ENGINEERING.md` §4 基线命令补 `--scene=` 写法并声明"两种写法同一组哈希"；⑦ §15 台账 S1.0 置 `🚧 进行中（a✅ / b✅ / c–d ⏳）`，头部版本 v1.9 → v2.0 | `A-` `--scene=diorama` 两次独立进程 × 2 图 sha256 **互等且与缺省逐位相同**；`A-` 反向对照 `--scene=battle_stub` 2 图哈希**全变**；`B-` 改完 `capture.gd` 后另跑两条独立进程，6 机位 **6/6 仍与 §4 基线逐位相等**；窗口 `--all` **21 用例 / 0 失败 / 0 跳过**、headless 21 / 0 失败 / 6 跳过，均退出码 0 | 用户 2026-10-19 指示"接着做"（S1.0a 已闭环，按 §5 子步表推进 S1.0b） |
| 2026-10-20 | **v2.0 → v2.1：S1.0c 落地并闭环（路由表登记 `strategic`，只登记不接线）**。① 新增 `scenes/world/strategic_map.tscn` —— **空壳**（`Node3D` 根 `StrategicMap`，无脚本 / 零子节点 / 无相机），真实内容留 S1.2；② `SceneRouter.SCENES` 追加 `strategic`，`world` 与 `run/main_scene` **一个字节都没动**（切 `world` 是 S1.0d）；③ **不新增** `goto_strategic()`、不改 `goto_*` 语义 —— 本步的验收物就是"表条目在、接线面没扩大"，`s1_0_routes` 用"没有这个入口"的反向断言把范围钉死；④ `s0_3_router` 路由名集合 2 → 3（73 → 74 断言）；⑤ 新增 `s1_0_routes` **37 断言**（三路由 / 路径存在且互异 / `run/main_scene` 未动 / `MAX_DEPTH` 仍 2 / path↔route 双向 / 场景根节点解剖 / 无新入口 / 拒绝零副作用 / 收尾交还现场）；⑥ §5 S1.0c 行置 ✅ 并补落地记录（含"用例切到 world 后不清理会让下一个用例多出一个世界"的坑，以及留给 S1.0d 的 `goto_world()` 语义问题）；⑦ §15 台账、`ENGINEERING.md` 场景表与"只有两个路由"的过期表述同步；⑧ 修掉 §16 表内 `S0.3 批次 2` / `批次 3` 之间的 1 处空行（既有格式缺陷，会把表格截断成两张；本次编辑落在同一张表，顺带修正并回读相邻行） | `A-` 窗口 `--all` **22 用例 / 0 失败 / 0 跳过 / 927 断言 / 138.3s**、headless 22 / 0 失败 / 6 跳过 / 677 断言 / 33.4s，均退出码 0；启动门禁 0 条 `ERROR`/`WARNING`/`SCRIPT ERROR`；`B-` 两条独立进程重采 6 机位，**6/6 sha256 与 §4 基线逐位相等**、两轮互等（新场景未进渲染路径） | 用户 2026-10-20 对齐三问三答，均取推荐项（真空壳 / 完整门禁后直接两提交推送 / 只登记不接线） |
| 2026-10-20 | **v2.2：S1.0d 落地，S1.0（场景与路由迁移）闭环**。① `project.godot` 的 `run/main_scene` 与 `SceneRouter.SCENES[world]` 同时改指 `res://scenes/world/strategic_map.tscn`，**删除** S1.0c 的临时名 `strategic`（一个文件只留一个名字，`_route_for_path()` 不再二义）；② `goto_world()` **不新增分支** —— 开机由 `_sync()` 认领，此后调用照旧被拒且**不重载同一文件**，S1.0c 留的问题用"世界实例数仍为 1"断言闭环；③ 新增 `s1_0_migration`（22 断言），`s1_0_routes` 37、`s0_3_router` 76（空壳基线），`s0_2_boot` 改为反向断言"开机日志不含 `[terrain]`"；④ **所有截片子进程显式 `--scene=diorama`**（缺省场景已无内容，否则"逐位一致"会真空通过、"两图必须不同"会假红）；⑤ `_world_fingerprint()` 增加 `root` 形参（空壳没有 `#main` 组）；⑥ §5 的产品码 `scenes/dev/` 登记表收紧回 **0 条**（注释里的路径也算泄漏） | 战略图接管 `world` 是 §5 S1.0 的最后一步；不做这一步，S1.1 的数据层就只能挂在一个"演示岛兼任世界"的临时形态上 | 用户（本会话批准执行 S1.0d） |
| 2026-10-20 | S1.0d 验收证据入账：窗口 `--all` **23 用例 / 0 失败 / 0 跳过 / 956 断言 / 131.1s**、headless **23 / 0 失败 / 6 跳过 / 702 断言**，均退出码 0；`B-` 6 机位走 `--scene=diorama` 专用批次（`.shots/s10d_a` / `s10d_b`）**6/6 与 `docs/ENGINEERING.md` §4 基线逐位相等**且两轮互等；启动门禁 0 条 `ERROR`/`WARNING`/`SCRIPT ERROR` | §0.1 闭环第 ④ 步：验收结论必须可追溯到命令与实测数值 | 用户（本会话批准执行 S1.0d） |
| 2026-10-20 | **v2.2 → v2.3：S1.1 拆 4 批，批 1（S1.1a：序列化地基 + 参数表）落地待验收**。① §6 S1.1 增补「批次拆分」表（批 1 序列化+参数表 / 批 2 高度场+region / 批 3 聚落·道路·势力·队伍+锚点 / 批 4 `WorldData`+三个宏观指标+800ms）与「S1.1a 落地与验收记录」；② 新增 `scripts/core/canon.gd`（`class_name Canon`，`to_text` / `from_text` / `canonicalize` / `write_file` 四入口，**不占 autoload**）、`data/world/gen_params.json`（schema=1，8 字段）、`scripts/world/gen_params.gd`（`class_name GenParams`，`DEFAULTS`/`RANGES`/`SETTLEMENTS_RANGE`/`load_from`/`validate`）；③ **契约两处实测更正**：`String.unicode_compare` 在 Godot 4 不存在 ⇒ 键序改 `Array.sort()`（码点序）；`JSON.parse` 把每个数字变 float ⇒ 纯 `%.6f` 无法幂等，改为整数值写整数、非整数 `%.6f`；④ §6 S1.1 的 `Canon` 描述、附录 A 的 `canon.gd` 行（旧的"未实现"标记改写为"已落地"）与 `data/**` 行同步；⑤ `ENGINEERING.md` §1 目录职责、§7.2 `class_name` 12 → 14、§9 由"契约草案"改写为"实现说明"（含 §9.3 更正"`SaveSystem` 已经是键字典序 + `%.6f`"这处**过期且为假**的说法、§9.4 四入口、§9.5 两处实测）、§5 新增陷阱 23；⑥ 用例 `s1_1_canon` 53 / `s1_1_params` 100，`s0_5_doc_conventions` 90 → 102（编造锚点 ① 换成 `Canon` 支持 `Vector3` 直写）；⑦ §15 台账 S1.1 置 `🚧 进行中（批 1 🧪 待验收）` | 用户要求"拆分出当前最紧要的单步任务，单步计划不要规划过长"；S1.1 一次做完会把序列化 / 生成器 / 拓扑 / 性能 / 像素五类红混在一起，故按依赖切 4 批；批 1 是其余三批的唯一出口（没有 `Canon` 就没有"同 seed 字节一致"） | 用户 2026-10-20 对齐三问三答，均取推荐项：① 范围 = `Canon` + 参数表 ② 不动 `SaveSystem`、只更正文档 ③ 数字格式 = 整数值写整数 + 非整数 `%.6f` |
| 2026-10-20 | 登记一条**待裁定的验收项冲突**：S1.1 的 `B-`（3 张不同 seed 的俯视全局图）在 S1.2（战略地形与相机）之前无法拍摄 —— 本规划不为它新建临时预览场景，也不静默降级为"贴图占位"，而是记为 ⚠️ 待裁定（并入 S1.2 交付 / 建临时预览场景 / S1.2 后补拍），须在批 4 前定 | 避免"数据层做完了但验收项拍不出来"在批 4 才暴露；`B-` 的三张图要求"聚落/道路/势力色可辨识"，这既是渲染问题也是配色问题，需要一个相机与一套战略地形 | 实测登记（S1.1a 执行过程），裁定待用户 |
| 2026-10-20 | **S1.1a 验收通过 → 批 1 `✅ 已验收`**，验收证据记入提交 `7e7a001`（本行由紧随的 `docs(roadmap)` 提交回填哈希）；§6 S1.1 状态行与 §15 台账同步。**仍不因此闭环的两项**：① `B-` 三张俯视全局图 ⚠️ 待裁定（需要 S1.2 的战略相机与地形）；② 批 2–4 ⏳ 未开始（批 2 = `height_field.gd` + region 划分） | 用户 2026-10-20 判定通过（§0.1 第 ④ 步）：窗口 `--all` 25 用例 / 1119 断言全绿、headless 25 / 865 全绿、`B-` 6 机位 6/6 与 §4 基线逐位相等 | 用户（本会话「继续」，视为通过并放行提交推送） |
| 2026-10-20 | **v2.3 → v2.4：S1.1 批 2（S1.1b：战略高度场 + region 划分）落地待验收**（提交 `c36d8e7`）。① 新增 `scripts/world/height_field.gd`（`class_name HeightField`，**实例类**：`height_at` 返回世界米 / `normalized_height_at` 0–1 / `slope_at` 升跑比 / `is_water` / `moisture_at` / `biome_at` 六值 / `sample_heights` 三元组采样；5 层 `FastNoiseLite` 的种子由 `world_seed + 写死偏移` 派生 ⇒ **零随机、零 `Rng` 耦合**；频率一律"跨地图周期数"⇒ 改 `map_size` 是缩放地形）；② 新增 `scripts/world/regions.gd`（`class_name WorldRegions`：两轮松弛的排斥采样放中心 + 32 m 归属网格上做最近中心分配 + `prune` 删空区并重编号；`RandomNumberGenerator` **由调用方传入**，游戏侧来自 `Rng.stream("world_gen")`，`--script` 侧来自 `root.get_node("Rng").stream(...)`）；③ `gen_params.json` / `GenParams` 扩 4 个**米制浮点**字段 `water_level 0` / `base_height −18` / `hill_amplitude 120` / `detail_amplitude 8`（安全区间 ±60 / −120..40 / 40..300 / 0..30），新增 `FLOAT_FIELDS` 分支：**浮点字段只钳制、不取整**，int 输入自动升为 float；④ 用例 `s1_1_height` **41 断言**、`s1_1_regions` **37 断言**（每条正向断言都配反向对照：换 seed 5 624/5 625 点变、`hill_amplitude` 减半 400/400 点变、`regions` 重放 `Rng.state` 逐格相同、水格数 > 0 防"全覆盖"真空通过）；`s1_1_params` 100 → **145**（浮点默认值/钳制/不取整）、`s0_5_doc_conventions` 102 → **106**（`class_name` 14 → 16）；⑤ `ENGINEERING.md` §1 / §7.2（→ 16 个）/ §9.6（高度场与 region 的契约、实测值、重放技巧）/ §5 陷阱 24（`JSON` 里 int 与 float 不分 ⇒ 浮点字段必须在代码里区分，否则会被悄悄取整） | 批 1 只有"能序列化"和"有参数表"，还不能算出**一座岛**；批 2 把"地形长什么样"和"地怎么分区"变成可断言的数据，批 3 的聚落/道路才有落点，批 4 的三个宏观指标（面积分布 / 连通 / 同 seed 字节一致）也才有输入。`terrain.gd` 是 6 机位基线的承载者，故**另建** `height_field.gd` 而不是改它 —— 复制形状、不复制数值 | 用户 2026-10-20 对齐四问四答全取推荐项："按推荐执行"（世界米 + `normalized_height_at` 双出口 / 数值全进参数表 / Voronoi 分区且每个陆地格恰属一区 / 两个新用例各配反向对照），并裁定 `B-` 俯视图**并入 S1.2 交付** |
| 2026-10-20 | **`B-` 俯视图裁定：并入 S1.2 交付**（用户 2026-10-20 定）。三张不同 seed 的俯视全局图需要战略相机 + 战略地形渲染，二者都在 S1.2；本规划**不为它新建临时预览场景**、**不降级为贴图占位**，而是在 S1.1 台账里保留显式欠账，S1.2 完成后补拍并回填 §15 | "数据层做完了但验收项拍不出来"若拖到批 4 才暴露，会迫使在"造临时场景"和"降级验收"之间二选一，两者都比"明确欠账 + 到点补拍"差 | 用户（本会话「按推荐执行」，含此项） |
| 2026-10-20 | 登记一条**既有偶发**待查：窗口 `--all` 里 `s0_3_slots` 的 `04_overwrite_confirm 两轮差异像素 0（严格 channel=0）` 出现过 **1 次**失败（actual 148668），随后 2 次全量窗口运行 + 3 次 `s0_3_slots` + 5 次 `s0_3_overwrite` 隔离运行**全绿**，8 次尝试无法复现。该断言比较的是**两个独立窗口进程**各拍一次的 PNG；`capture.gd` 按**帧数**结算，若某一轮的帧结算跨过世界动画的相位，整片像素就会不同。**判定为既有偶发**（S1.1b 只新增 3 个数据脚本与 verify 分支，不碰菜单 / 截图 / 渲染）。待办：把 UI 步骤的结算从"等 N 帧"改成"等世界暂停 + 固定 `Clock` 推进"，或在截图批次里显式冻结世界动画 | 不以"重跑绿了"当已修 —— 这类偶发会在 CI 上以 1/3 的概率变红，必须给出机制而不是重试次数 | 实测登记（S1.1b 验收过程）；机制待查 |
| 2026-10-20 | **S1.1b 验收通过 → 批 2 `✅ 已验收`**（提交 `c36d8e7`，本行由紧随的 `docs(roadmap)` 提交回填）。用户判定依据：窗口 `--all` 27 用例 / 0 失败 / 0 跳过 / 1246 断言 / 129.8 s、headless 27 / 0 / 6 跳过 / 992 断言 / 30.5 s，均退出码 0；启动门禁 0 条 `ERROR`/`WARNING`/`SCRIPT ERROR`；`B-` 6 机位 6/6 与 `ENGINEERING.md` §4 基线逐位相等。**仍不闭环的两项**：① `B-` 三张俯视全局图并入 S1.2（已裁定）；② 批 3–4 ⏳ 未开始（批 3 = `world_data.gd` + `anchors.json`） |
| 2026-10-20 | **v2.4 → v2.5：S1.1 批 3（S1.1c：聚落 / 道路 / 势力 / 队伍 + 手工锚点）落地待验收**。① 新增 `scripts/world/world_data.gd`（`class_name WorldData`，`class_name` 16 → 17）与 `data/world/anchors.json`（3 条锚点）；② `gen_params.json` / `GenParams` 扩 2 个浮点字段（`settlement_min_spacing` / `settlement_slope_limit`，`FLOAT_FIELDS` 4 → 6）；③ 新增用例 `s1_1_world`（308 断言），`s1_1_params` 145 → 159、`s0_5_doc_conventions` 106 → 108；④ `ENGINEERING.md` 新增 §9.7（世界数据契约）与 §5 陷阱 25（单数/复数命名映射），§7.2 / §1 同步。落地提交 `7838a49`，本行由紧随的 `docs(roadmap)` 提交回填哈希 |
| 2026-10-20 | 修一处**文档控制字符**：§6 S1.1b 记录的"提交"行里 `feat` 的 `f` 曾被写成 **U+000C（换页符）**（上一批用 PowerShell 双引号写提交信息时 ` `f ` 被当成转义序列），已改回 `feat`，并复查四份文档控制字符计数为 0 |
| 2026-10-20 | **S1.1c 验收通过 → 批 3 `✅ 已验收`**（提交 `7838a49`，本行由紧随的 `docs(roadmap)` 提交回填）。用户判定依据：窗口 `--all` **28 用例 / 0 失败 / 0 跳过 / 1570 断言 / 129.2 s**、headless **28 / 0 / 6 跳过 / 1316 断言 / 31.7 s**，均退出码 0；启动门禁 0 条 `ERROR`/`WARNING`/`SCRIPT ERROR`；`B-` 6 机位 6/6 与 `ENGINEERING.md` §4 基线逐位相等。**仍不闭环的两项**：① `B-` 三张俯视全局图并入 S1.2（已裁定）；② 批 4 ✅ 已验收 2026-10-20：`WorldData` 序列化（`to_dict()` / `to_text()`）/ 四项宏观指标（海岸线、region 面积分布、道路总长、聚落按 region 分布）/ `C-` 整条链 **16.0 ms** 全部落地，用例 `s1_1_gen`（**52 断言**）与 `s1_1_variety`（**33 断言**）全绿，窗口 **30 / 0 / 0 / 1655 断言 / 130.2 s**、headless **30 / 0 / 6 跳过 / 1401 断言 / 31.2 s**，`B-` 6 机位 6/6（细节见 §6「批 4 落地记录」） |
| 2026-10-20 | **v2.6 → v2.7：S1.2 批 1（S1.2a：世界入口 / 组合根）落地待验收**。① 新增 `scripts/world/world_session.gd`（`class_name WorldSession`，**第 18 个**）：`boot(rng, seed)` 先 `seed_from(seed)` 再按 `HeightField → WorldRegions → WorldData` 固定顺序建世界，`Rng` 以参数注入；`ok / errors / warnings` 三级失败语义。② `scenes/world/strategic_map.tscn` 挂上 `strategic_map.gd`，`_ready()` 用 `GameState.world_seed` 走同一入口，**仍零子节点 / 无相机**（地形与镜头在批 2 / 批 3）。③ 用例 `s1_2_boot`（**31 断言**）：同 seed 两次 boot 逐字节相同、先污染子流仍相同（带反向对照）、换 seed 必变、与 `_world_fixture()` 逐字节一致、场景实例化后 session 非空零告警。④ `ENGINEERING.md` 新增 §9.9（入口与组合根）、§5 陷阱 28（母种子是会话级可变输入）。落地提交 `0030d8e`（哈希回填）；验收标注由紧随的 `docs(roadmap)` 提交补上 |
| 2026-10-20 | **S1.2a 验收通过 → 批 1 `✅ 已验收`**（提交 `0030d8e`，哈希回填 `408759c`，本行由紧随的 `docs(roadmap)` 提交回填）。用户判定依据：① 世界入口收成唯一函数 `WorldSession.boot()`（`Rng` 参数注入、先 `seed_from` 再按 `HeightField → WorldRegions → WorldData` 建）② 战略图场景批 1 只持有一个 session、不渲染（地形 / 镜头留批 2 / 批 3）③ S1.0 两条「根节点无脚本」断言迁到「脚本是不是入口」，判据未弱化。证据：`s1_2_boot` 31/31；headless `--all` 31 / 0 失败 / 1439 断言；windowed `--all` 31 / 0 / 1693 断言；开机闸门 0 坏行；`B-` 六张逐位不变 |
| 2026-10-20 | **v2.7 → v2.8：S1.2 批 2（S1.2b：战略地形低模网格）落地待验收**。① 新增 `scripts/world/strategic_terrain.gd`（`class_name StrategicTerrain`，第 19 个）：`cells = round(map_size / 32)` ⇒ 75 格 × 32.0 m、`75×75×2 = 11 250` 三角；6×6 分块（`_split` 切 13/13/13/12/12/12）；水面只在水下格上铺、顶点色带深度与泡沫；外缘裙边墨色顶带。② `strategic_map.gd` 把 `session.field` 交给地形，场景唯一子节点即 `StrategicTerrain`（仍无相机）。③ 描边取舍：陆面不挂逆壳（32 m 格距会糊成黑带），改"海岸一格墨线 + 外缘墨线"，与 `terrain.gd` 的差异记在 §9.10.3。④ `tools/verify.gd` 新增 `s1_2_mesh`（105 断言 / 421 ms），类名表 18 → 19。⑤ `ENGINEERING.md` 新增 §9.10、§5 陷阱 29（逐三角形取调色板 0.9 ms/次 ⇒ 建网格 9.2 s）与 30（离树 `get_tree()` / `queue_free()` 打 ERROR）。实测：建网格 68.5 ms（用例侧计时），高度 −78.24…+113.26 m，色带 水 2 127 / 滩 309 / 草 1 237 / 高地 1 901 / 雪 51，岩石 22 格。落地提交 `febdceb` |
| 2026-10-21 | **S1.2b 验收通过 → 批 2 `✅ 已验收`**（落地提交 `febdceb`，哈希回填 `cf0ad98`，本行由紧随的 `docs(roadmap)` 提交回填）。用户判定依据：① 网格规格 32 m / 75 格 / 11 250 三角 / 6×6 分块（`_split` 差一格不改格数）② 描边取舍：陆面无逆壳，只有海岸一格墨线 + 外缘裙边墨色顶带 ③ 判据迁移：`s0_3_router` 世界基线从「指纹恰为 `StrategicMap:Node3D:0`」改判「形如『根 → 地形 → 块容器』+ 每块都有 mesh + 仍无 `Camera3D`」（76 → 81 断言），未弱化。证据：`s1_2_mesh` 105/105（421 ms，`ERROR:` 行 0）；headless `--all` 1551/0 失败；窗口 `--all` 1805/0 失败；主场景 `--quit-after 120` 0 ERROR/WARNING；`B-` 36 张图 6/6 sha256 与 §4 基线逐位相等。**`B-` 肉眼判定仍未做**（无相机无灯光），随批 4 截图判定 |
| 2026-10-20 | **S1.1d 验收通过 → 批 4 `✅ 已验收`**（提交 `7c3dfe8`，哈希回填 `c1e66e2`，本行由紧随的 `docs(roadmap)` 提交回填）。用户判定依据：① 序列化契约（Canon 的 `{ok, text, reason}` 返回值 / 四数组按稳定键排序 / 坐标不取整）认可；② 指标集换成「海岸线 / region 面积分布 / 道路总长 / 聚落分布」、明确不用「聚落数」，认可；③ 子流入口缺陷按「用例侧 `Rng.reset()` 钉死 + S1.2 组合根开工前置」处置，认可。验收时点证据：窗口 `--all` **30 / 0 / 0 / 1655 断言 / 130.2 s**、headless **30 / 0 / 6 跳过 / 1401 断言 / 31.2 s**（均退出码 0）、启动门禁 0 条、`B-` 6 机位 6/6 与 §4 基线逐位相等、`C-` 整条链最慢 **16.0 ms**。**S1.1 四批全部闭环**；本步仍欠 `B-` 三张俯视全局图（已裁定并入 S1.2） |
| 2026-10-20 | **v2.5 → v2.6：S1.1 批 4（S1.1d）落地待验收**。① `scripts/world/world_data.gd` 增 `to_dict()` / `to_text()`（Canon 契约 `{ok, text, reason}`）/ `metrics()` / `_sorted_by()`，顶层 `{schema: 1, world_seed, params, metrics, settlements[], roads[], factions[], parties[]}`，四数组按稳定文本键（`id` / `a`）排序后写出、坐标不取整；② 新增用例 `s1_1_gen`（**52 断言**）/ `s1_1_variety`（**33 断言**），`class_name` 仍 **17**、参数表字段未变、autoload 仍 **9 / 10**；③ `ENGINEERING.md` 新增 §9.8（序列化与宏观指标契约）与 §5 陷阱 26 / 27。落地提交 `7c3dfe8` |
| 2026-10-20 | **登记一处真实决定论缺陷（已修）**：世界生成依赖 `Rng.stream("world_gen")` 的**入口状态**，而用例共享同一条子流 —— 不拨回起点时，同一个 seed 会因「前面用例多抽了几个数」生成不同的世界。实测证据：`--all` 里 `s1_1_gen` 跑出 **26 条边 / 8916.9 m**，单跑是 **24 条 / 7936.7 m**（同一 seed 20250929）。修法：夹具先 `Rng.reset()`（把每条子流拨回由 `(master_seed, 名字)` 派生的起点）再建世界，两种跑法随即**逐字节一致**。批 3 记录的 24 条边正是「开局状态」的世界，26 条边是「被污染子流」的世界，机制写进 `ENGINEERING.md` §5 陷阱 26；同时把「S1.2 组合根先 `Rng.reset()` / `seed_from(world_seed)` 再建世界」立为 **S1.2 开工前置** |
| 2026-10-20 | **登记一处工具陷阱**：引擎（编辑器 / 部分运行路径）会重写 `project.godot` —— 注释被整段删除、`[shader_globals]` 从原位置挪到文件尾，`git status` 因此变脏。处置：**不提交**该重写结果，`git checkout -- project.godot` 复原后再提交（本批即如此处理）。写进 `ENGINEERING.md` §5 陷阱 27 |

| 2026-10-21 | **v2.8 → v2.9：S1.2 批 3（S1.2c：镜头三档 + 边界钳制 + 固定正午舞台）落地待验收**。① 新增 `scripts/world/strategic_camera.gd`（`class_name StrategicCamera`，第 20 个全局类）：GLOBAL 2600 / REGION 700 / LOCAL 170 m，GLOBAL 锁正交等距且焦点锁中心，REGION/LOCAL 可 `P` 切透视；`step()` 是唯一积分入口（`_process` 喂输入、用例喂脚本轨迹）。② `strategic_map.gd` 增 `_rebuild_stage()`（`WorldEnvironment` + `Sun` + `DayNight`，自动循环关闭、`set_time(0.5)`）与 `_rebuild_camera()`；根子节点 1 → **5**。③ 新增 `s1_2_camera` **37 断言 / 242 ms**：600 帧轨迹无 NaN、无越界、帧间位移 ≤ `size×0.35×dt×1.35`、相机不低于地形 3 m，同脚本两次哈希相同 + 反向平移不同。④ 类名表 19 → **20**；`s0_3_router` 世界基线**第二次**迁移（81 → 85 断言，改成「5 子节点 + 视口恰一个 current 相机」）。⑤ `docs/ENGINEERING.md` 新增 §9.11 与陷阱 31（`enum Projection` 撞内置类型）/ 32（离树读 `global_position` 报 `!is_inside_tree()`）。⑥ 回归：headless 33 / 0 失败 / 6 跳过 / 1594 断言 / 44.6 s，窗口 33 / 0 / 0 / 1848 断言 / 157.5 s，`B-` 6/6 基线逐位相等。**未做**：`B-` 三档截图与 `C-` FPS ≥ 60（批 4）。落地提交 `6c9791f`（本行由紧随的 `docs(roadmap)` 提交回填哈希）。 |
| 2026-10-21 | 窗口 `--all` 再次命中**既有偶发** `s0_3_slots`（`04_overwrite_confirm 两轮 sha256 不一致`，19 426 差异像素），单跑 `--case=s0_3_slots` **PASS**（20 091 ms）⇒ 与本批改动无关，维持 §16 已登记的「待查，未修」状态。 |
| 2026-10-21 | **S1.2c 验收通过 → 批 3 `✅ 已验收`**（落地提交 `6c9791f`，哈希回填 `cf2b37b`，本行由紧随的 `docs(roadmap)` 提交回填）。用户判定依据：① 三档数值与锁定 ② 手感与钳制 ③ 决定论与判据迁移（`s0_3_router` 第二次迁移 81 → 85 断言）。§6 S1.2 批次表 / 状态行与 §15 台账同步；`B-` 三档截图与 `C-` FPS 仍留批 4。 |
| 2026-10-21 | **v2.9 → v2.10：S1.2 批 4（S1.2d：三档取景台 + 分档帧率探针）落地待验收**（提交 `c6693af`，`docs(roadmap)` 提交 `d09faea` 回填本行）。① `scripts/world/strategic_camera.gd` 加 `snap_to_target()` / `focus_on(x, z)` 两个**工具层**接口，`step()` 与已验收数值未动。② 新增 dev 取景台 `scripts/dev/strategic_shots.gd` + `scenes/dev/strategic_shots.tscn`（只读 `--seed=` / `--tier=`）与帧率探针 `tools/perf_map.gd`（强关 vsync + 空天空反向对照）。③ `tools/verify.gd` 新增 `s1_2_perf`（headed，26 断言）。④ `B-` 五张 plate 两轮逐位相同；diorama 6 机位与 §4 基线 6/6 相等。 |
| 2026-10-21 | **S1.2d 验收通过 → 批 4 `✅`，S1.2 整步 `✅ 已验收`**（`docs(roadmap)` 提交 `d09faea`，哈希回填提交紧随其后）。用户判定：`B-` **接受三档现有数值**（2600 / 700 / 170 m），三条已知限制（海岸阶梯 / 高原长相 / LOCAL 内容空）随批登记、不改档位；`C-` 三档 ≥ 60 fps（994.8 / 960.0 / 1034.0）与三角面 16 920 ≤ 34 611 全绿。S1.1 的 `B-` 欠账（三张俯视全局图）同时结清。 |
| 2026-10-21 | **v2.10 → v2.11：S1.3 批 1（S1.3a：棋子本体 + 贴地 + 特写取证通道）落地待验收**（提交 `6aefccc`，`docs(roadmap)` 提交 `3d26aea` 回填本行）。① 新增 `scripts/world/party_marker.gd`（第 21 个 `class_name`，不占 autoload）：12 个圆柱/球/旗面零件 `combine()` 成单一 mesh（556 三角 / 1668 顶点 / 1 draw call），标称 22 m、脚底 `y = 0`，`FACTION_KEYS` 四阵营换色不重建几何。② **本批挖出的真缺陷**：`MeshUtil` 的生成器把"面法线"同时写进法线与切线槽，反向外壳沿各自面法线炸成散三角片 —— 正常线宽下描边**完全不可见**（实测线宽 120 才见碎屑）；`_with_smooth_tangents()` 按面积加权重算平滑法线、只写切线槽（着色仍走面法线保面着色），合成类道具的"描边没画"自此有解。③ `scripts/dev/strategic_shots.gd` 新增 `--party=1` / `--span=<m>`，并按跨度发布 `Style.pixel_span`（否则外壳线宽随档位乱掉）。④ 用例 `s1_3_party` **37 断言 / 86 ms**：100 点贴地最大偏差 **0.00000 m**（正负 52/48，配 `min_y = 0`）、1494 个顶点切线槽为平滑法线、四方向朝向含 ±π 回绕、两次构建逐字节一致。⑤ 全量 headless `--all` **35 用例 / 0 失败 / 7 跳过 / 35.8 s**。取证 `.shots/s13a/party_local`（`55aa66e6…`）/ `party_close`（`eebe7950…`）。 |
| 2026-10-21 | **v2.11 → v2.12：S1.3 批 2（S1.3b：行军图预计算 + 确定性 A\*）落地待验收**（提交 `378c66b`，`docs(roadmap)` 提交回填本行）。① 新增 `scripts/world/travel_graph.gd`（第 22 个 `class_name`，`RefCounted`，不占 autoload）与 `data/world/travel_params.json`：2400 m / 32 m = 75×75 = 5625 格，可走 3364 / 水 2261；"可走"要求格心 + 四角都高于 `water_level + 1.5 m`，对角移动另要求两个正交邻居可走（不许切角穿水）；19 条聚落直线用整数 DDA 栅格化成 216 个道路格（穿水 0 格，只记 `road_water_crossings`，水格不会因为压了路被点亮），道路每米成本 ×`1/1.35 = 0.74074`。② 决定论三件套：二叉堆 `(f, 节点序号)` 双键全序、8 邻居固定展开序、octile 启发式乘**全局最小系数**（乘 1.0 会让道路格系数 < 1 的图不再最优）；同实例两次、重建图后 `path_key` 逐位一致，换 seed 后路格/可走格/指纹全变。③ `speed_factor_at()` 与寻路共用同一张成本表（路上恒 1.35），b3 的移动积分直接读，避免"算得便宜、走起来不快"。④ **本批挖出的两个真缺陷**：**成本必须沿着报出的折线重算** —— `_g[goal]` 只覆盖格心到格心，首末两段（精确点 ↔ 格心）不在里面，直接返回会把 498.5 报成 483.9（低 3%），"成本 ≥ 直线 × 最低系数"因此假红；**零断言用例会静默通过** —— GDScript 运行时错误只结束协程，`_run_one` 感知不到，崩在半路的用例显示成绿色 0/0，现改为"零断言即失败"。⑤ 用例 `s1_3_path` **66 断言 / 224 ms**：最长路 `village_8→fortress_2`（直线 658.6 m）→ 21 点 / 折线 672.9 m / 成本 498.5 / 展开 21 格 / 路上 672.9 m、野外 0 m；开/关提速成本比 **0.74074** = `1/1.35`（±5% 判据）；道路格最慢 1.35 > 地面格最快 0.9871（**全序**）。⑥ 取证 `.shots/s13b/route_region`（REGION 700 m；墨色点 = 路径、沙色点 = 图里道路格，两层严丝合缝）。⑦ 全量 headless `--all` **36 用例 / 0 失败 / 7 跳过 / 37.2 s**；主场景 `--quit-after 120` 退出码 0、0 ERROR。 |
| 2026-10-21 | **v2.12 → v2.13：S1.3 批 3（S1.3c：移动积分 + 点击移动 + 接进战略图）落地待验收**（提交 pending，`docs(roadmap)` 提交回填本行）。① 新增 `scripts/world/party_mover.gd`（第 23 个 `class_name`，`Node3D`，不占 autoload）：一帧一个入口 —— 读 `speed_factor_at()` 得系数（`≤0` 直接 `BLOCKED`，不硬推着进水）→ `budget = speed × factor × dt` 沿折线推进 → 位移按**弧长**记账 → `remaining ≤ arrive_radius` 判到达（**不吸附到终点**）→ 朝向以 `turn_rate × dt` 逼近段方向、`pitch` 夹 `±max_pitch` 只作用于渲染 → 棋子落位。② 四个手感数字进 `data/world/travel_params.json`（`march_speed 24` / `turn_rate_deg 300` / `arrive_radius 6` / `max_pitch_deg 12`），`Params` 另给弧度视图，产品码不写第二遍数字；24 m/s × 673 m ≈ 28 s 一段路，300°/s ⇒ 180° 掉头 0.6 s，6 m 在 REGION 档约 8 px，±12° 让棋子爬坡不躺倒。③ `StrategicCamera.pick_ground()`：地形是裸 `ArrayMesh`、没有碰撞体 ⇒ 视线 4 m 步进 + 二分 10 次（实测横向 **0.003 m**），返回**地面高度**；正交档 `project_ray_origin()` 落在地图外，"采样点越界就提前退出"会让点击永远失败（§5 陷阱 38）。④ 接进 `strategic_map.tscn`：根 **6 个子节点**（地形 + 舞台三件 + 相机 + `PartyLayer`），`_process` 推 `party.step()`、左键点击走 `pick_ground()` 再 `order_to()`；`s0_3_router` 第三次迁移（指纹 `Node3D:6` + 队伍在 / 棋子贴地 / 自带行军图三条能力断言）、`s1_2_mesh` 同步到 6。⑤ 用例 `s1_3_move` **50 断言 / 239 ms**：60 s × 3600 帧（固定 1/60 步长、不读帧率）→ 贴地 ≤ **0.000004 m**、位移 ≡ `24 × 系数 × dt` ≤ **0.000043 m**、帧间转角 **0.087266 = 300°/s × dt**（顶满上限）、俯仰峰值 **12.00°**、零 NaN、零帧落在不可走格；A→B **20.6 s** 到达并停在离终点 **5.497 m** 处、随后改令反向（两段行军、20 帧内离旧终点严格变远）；下单当帧就动 **0.540 m**、到达后 1 s 位移 **0.000000000 m**、点击不挪相机焦点；同段 300 帧轨迹两次签名逐位一致。⑥ **本批挖出的两个真缺陷**：正交射线起点在地图外（陷阱 38）；"到达吸附"= 最多 6 m 瞬移，且拿弦长当位移会在拐角帧假红（陷阱 39，实测偏差 0.258 m）。⑦ 取证 `.shots/s13c/march_region`（REGION 700 m，1600×900，345 689 B，sha256 `7da08faa…`）：21 点折线与图里道路格重合，棋子走到 58%、离终点 284 m。⑧ 全量 headless `--all` **37 用例 / 0 失败 / 7 跳过（仅窗口态）/ 39.1 s**，退出码 0；主场景 `--quit-after 120` 退出码 0、0 ERROR。⑨ **键盘行军本批不做（用户决定）**：方向键已被相机占用，键盘行军需与"选部队 / 编队"一并设计，硬塞只会变成两套互相打架的输入。 |

## 附录 A：本规划对现有代码的改动面预估

| 现有文件 | 预计改动 | 发生步骤 |
|---|---|---|
| `project.godot` | 新增 5 个 autoload、输入映射、可能的渲染分组；**S1.0a/d 会改 `run/main_scene`**（改后必须 `git diff` 逐行确认，编辑器会重写该文件） | S0.3、S0.4、**S1.0** |
| `scripts/main.gd` | **S1.0a 起拆分为世界入口**：演示岛保留为 `scenes/dev/diorama.tscn` + 其原脚本（内容不变，仅换路径）；战略图另建入口 | **S1.0**、S1.2 |
| `scripts/terrain.gd` | **不回改**（它是 6 机位 `B-` 基线的承载者）；S1.1 新建 `scripts/world/height_field.gd` 提供战略尺度的高度场，必要时从 `terrain.gd` **复制**而非继承 | S1.1、S1.2、S4.1 |
| `scripts/player.gd` | 保留不动（演示资产）；新增 `actors/` 下的棋子与战斗角色 | S1.3、S2.2 |
| `scripts/camera_rig.gd` | **保留不动**（基线承载者）；战略层新建 `scripts/world/strategic_camera.gd` 实现三档缩放；Boss 战另建横版相机 | S1.2、S2.1 |
| `scripts/input_setup.gd` | 扩展为「大地图 / 战斗 / 指挥」三套上下文 binding | S0.4、S2.2、S4.5 |
| `scripts/style.gd` | 仅新增调色板项与少量材质参数，**不重构** | 全程 |
| `scripts/capture.gd` | 扩展 `--case=` 批量案例表与截图清单 JSON；**触发条件收紧**：仅 `--shots`/`--shot=`/`--capture`/`--bench` 才启动截图批次，`--case=`/`--out=` 降为修饰符（避免与 verify 抢占退出码） | S0.2（已完成） |
| `scripts/capture.gd`（续） | **S1.0b 新增 `--scene=res://…`**（纯修饰符，缺省取 `run/main_scene`）：`_swap_scene()` 手动换 `SceneTree.current_scene` + 四条自证，清单新增 `scene` 字段。**不扩 `scene_change_owner` 属主**。**S1.0d 起这条参数是 diorama 的唯一入口**：缺省场景已是空壳（无相机），不指定 `--scene=` 的批次拍到的是纯背景图 | **S1.0b ✅**、S1.0d ✅ |
| `scripts/ui_panel.gd` | 保留为调试面板；新 UI 抽取公共控件工厂 | S0.4、S1.5 |
| `scripts/ui/menu_page.gd`、`scripts/ui/save_grid.gd`（新增） | 游戏内菜单页与 3×3 宫格组件（§3.5）；S0.4 在其上加调试入口、S6.3 在其上加槽位管理（删除/多分辨率） | S0.3 ✅、S0.4、S6.3 |
| `scenes/main.tscn` → **`scenes/dev/diorama.tscn`** | 挂载 `MenuLayer`（默认隐藏）；**S1.0a 换路径**，**S1.0d 起不再是主场景**（`run/main_scene` 改指战略图，它降为回归夹具）；`world_seed` 与两套时钟的收编改到战略图入口 | S0.3 ✅、**S1.0 ✅**、S1.2 |
| **`scripts/core/canon.gd`（新增；✅ 已落地 S1.1a）** | 规范化序列化（键**码点**升序 + 整数写整数/非整数 `%.6f` + LF + 顶层 `schema`），供世界生成与存档做字节级比对。**S0.5 只写契约不写实现**（当时 `docs/ENGINEERING.md` §9 标注"待建"），**S1.1a 落地**：`class_name Canon`、四个入口（`to_text` / `from_text` / `canonicalize` / `write_file`）、不支持的值 fail-fast 报键路径。落地时实测更正了契约两处（`String.unicode_compare` 不存在、纯 `%.6f` 无法幂等），见 `ENGINEERING.md` §9.5 与 §5 陷阱 23 | **S1.1a ✅**、S1.9 |
| **`scripts/world/gen_params.gd` + `data/world/gen_params.json`（新增；✅ 已落地 S1.1a）** | 世界生成参数表与加载器：初值（2400 / region 6–9 / 20 聚落 / 3 势力 / 24 队伍）、安全区间、越界 clamp + 告警、类型错回退默认、高版本 schema 整表拒读。表文件本身按 `Canon` 规范形式存放（`s1_1_params` 断言"文件 == 自己的规范化结果"） | **S1.1a ✅** |
| **`scripts/world/height_field.gd`（新增；✅ 已落地 S1.1b）** | 战略尺度高度场：世界米高度、0–1 归一化、升跑比坡度、6 值 biome、三元组采样。5 层噪声种子由 `world_seed` 派生 ⇒ **同 seed 逐点逐位相同**；频率用"跨地图周期数"表达 ⇒ 改 `map_size` 是缩放地形。`WorldGen` 与 `strategic_terrain` 共用同一 `height_at`（**唯一实现**，避免"渲染与逻辑两套地形"） | **S1.1b ✅**、S1.2 |
| **`scripts/world/regions.gd`（新增；✅ 已落地 S1.1b）** | Voronoi region 划分：排斥采样放中心（两轮松弛）+ 32 m 归属网格最近中心分配 + 删空区重编号；返回 `{ok, count, regions, cell, grid_w, grid_h, land_cells, water_cells, warnings}`，每个陆地格恰属一个 region、水格 `owner = -1`。随机源由调用方传入 `RandomNumberGenerator`（游戏侧 `Rng.stream("world_gen")`） | **S1.1b ✅**、S1.1c |
| **`scripts/world/world_data.gd` + `data/world/anchors.json`（新增；🚧 已落地 S1.1c 待验收）** | 聚落 / 道路 / 势力 / 队伍 + 手工锚点：五步生成（锚点优先 → 配额补点 → 最远点采样定首都 → 最近邻骨架 + 补边至单连通 → 队伍挂母城）；落点四条闸门 + 每点 200 次上限；道路是 `{a, b, length}` 图而非网格（铺设留 S1.2）；锚点坐标逐位采用、坏锚点只跳过并告警 | **S1.1c**、S1.1d |
| **`scripts/world/strategic_map.gd` / `strategic_camera.gd`（新增）** | 战略图场景根与三档缩放相机（不扩 `camera_rig.gd`） | S1.2 |
| **`scripts/world/ai_director.gd`（新增，纯静态）** | AI 行为与遭遇判定；必须能在 `--script` headless 下跑 10 日 soak | S1.6 |
| **`data/**`（新增目录）** | `world/` `economy/` `quests/` `i18n/`；所有玩法数值外置，代码只留结构常量 | S1.1a ✅（`world/gen_params.json`）、S1.1 起 |
| `scripts/scatter.gd` | 保留；其 MultiMesh 模式被 S4.3 复用为性能范本 | S4.3 |

## 附录 B：与既有美术规范的一致性自检

| `AGENTS.md` 条目 | 本规划如何落实 |
|---|---|
| 禁方块/体素 | §3.1.1 硬约束 + S0.2 规范守卫静态检查 + 每步 `B-` 截图门禁 |
| 平滑低模 + 面着色 | 一切新网格走 `MeshUtil.facet()`；S0.5 提供新建合规物件模板 |
| Toon 阶梯光影 | 一切新材质走 `Style.toon()` + 渐变 ramp；禁用 `StandardMaterial3D` |
| 逆壳描边 | 新角色/Boss/单位/道具全部 `attach_outline`；S4.3 的降级需 §14 Q3 授权 |
| 高饱和纯色调色板 | 新颜色必须注册 `Style.PALETTE`，禁止写实脏色 |
| 正交 + 硬阴影 | 光照沿用现有 Sun + PCF 硬阴影；战略层/横版/上帝视角一律正交投影 |

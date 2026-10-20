# 工程结构（Pocket Sandbox — NPR Diorama）

> 本文件由 **S0.1 目录与工程结构重组**产出（§1–§6），由 **S0.5 工程规范与美术管线文档**补齐
> §7–§12。**目录约定的权威定义在 `docs/ROADMAP.md` §3.2**；本文件是其落地记录与可执行细则。
>
> 与 `AGENTS.md`（项目级强制美术/版本控制规范）冲突时，**以 `AGENTS.md` 为准**：本文件是它的
> 工程化展开，不是对它的再解释。美术相关的落地清单另见 `docs/ART_PIPELINE.md`。
>
> 覆盖范围：§1 目录职责 · §2 迁移映射 · §3 引用规则 · §4 `B-` 基线 · §5 执行陷阱 ·
> §6 验收基线 · **§7 命名规范 · §8 信号约定 · §9 数据表格式（`Canon` 契约）·
> §10 autoload 上限 · §11 允许/禁止清单 · §12 新增物件 checklist · §13 S0.5 验收**。

---

## 1. 目录职责

| 目录 | 职责 | 当前内容（S0.1 后） |
|---|---|---|
| `scenes/` | 场景文件 | `world/strategic_map.tscn`（**主场景**，S1.0d：`run/main_scene` 与路由 `world` 同时指它；S1.2a 起根节点挂 `strategic_map.gd`、只持有 `WorldSession`（`_ready()` 里建世界），S1.2b 起再挂**一个** `StrategicTerrain` 地形子树（36 陆块 + 水块 + 外缘裙边）；**仍无相机** —— 镜头属 S1.2c）、`dev/diorama.tscn`（**回归夹具**，不再是主场景；S1.0a 由 `scenes/main.tscn` 换路径而来，**内容逐字节不变**；S0.3 批次 4 挂载 `MenuLayer`，**默认隐藏**；只能用 `--scene=` 或 `tools/` 进入）、`battle/battle_stub.tscn`（战斗**占位靶子**，S0.3 批次 3；M2 用真战斗场景替换）、`dev/art_samples.tscn`（S0.5 教材夹具，产品码不得引用） |
| `scripts/core/` | 与玩法无关的基础设施与服务 | `main.gd`（编排/autoload 宿主）、`style.gd`（美术中枢，autoload `Style`）、`capture.gd`（截图，autoload `Capture`）、`render_clock.gd`（时间，autoload `Clock`）、`rng.gd`（随机，autoload `Rng`，S0.3 批次 1）、`event_bus.gd`（全局事实信号，autoload `EventBus`，S0.3 批次 1）、`game_state.gd`（本局状态与存档字段，autoload `GameState`，S0.3 批次 1）、`save_system.gd`（存档服务，autoload `SaveSystem`，S0.3 批次 2）、`scene_router.gd`（场景路由，autoload `SceneRouter`，S0.3 批次 3；**唯一允许切场景的文件**）、`debug_layer.gd`（调试叠加层，autoload `Debug`，S0.4 批次 2；**默认隐藏**、`PROCESS_MODE_ALWAYS`、整层 `MOUSE_FILTER_IGNORE`）、`mesh_util.gd`（低模几何库）、`canon.gd`（**规范化序列化**，`class_name Canon`，S1.1a；见 §9）、`input_setup.gd`（输入映射；`F1`/`F3` 与唯一闸门 `ensure_debug_hotkeys()` 在此）、`camera_rig.gd`（正交等距相机） |
| `scripts/world/` | 世界生成与自然元素 | `terrain.gd`、`water.gd`、`scatter.gd`（植被散布/MultiMesh）、`clouds.gd`、`day_night.gd`、`gen_params.gd`（**世界生成参数表加载与钳制**，`class_name GenParams`，S1.1a；表在 `data/world/gen_params.json`）、`height_field.gd`（**战略尺度高度/生物群系场**，`class_name HeightField`，S1.1b；见 §9.6）、`regions.gd`（**Voronoi region 划分**，`class_name WorldRegions`，S1.1b）、`world_data.gd`（**聚落/道路/势力/队伍**，`class_name WorldData`，S1.1c；见 §9.7）、`world_session.gd`（**世界入口 / 组合根**，`class_name WorldSession`，S1.2a；先重置子流再按固定顺序建世界，见 §9.9）、`strategic_map.gd`（`scenes/world/strategic_map.tscn` 的根脚本，S1.2a；无 `class_name`）、`strategic_terrain.gd`（**战略尺度地形网格**，`class_name StrategicTerrain`，S1.2b；32 m × 75×75 = 11 250 三角、6×6 分块、水面 + 外缘墨色裙边，见 §9.10） |
| `scripts/actors/` | 可动实体 | `player.gd`（演示角色） |
| `scripts/ui/` | 界面 | `ui_kit.gd`（**公共控件工厂**，S0.4 批次 1：stylebox / 阴影偏移 / 标签构造，`ui_panel` / `menu_page` / `save_grid` 三处共用；`PAPER` 等常量在此）、`ui_panel.gd`（调试面板，S0.3 批次 4 起显式 `PROCESS_MODE_ALWAYS`，`group=hud`）、`ui_slider.gd`（方形滑块）、`menu_page.gd`（游戏内菜单页：主页 / 宫格 / **调试页** / 覆盖确认，S0.3 批次 4 + S0.4 批次 3）、`save_grid.gd`（3×3 存档宫格组件，S0.3 批次 4） |
| `scripts/battle/` | 战斗（M2 主体） | `battle_stub.gd`（战斗**占位靶子**，S0.3 批次 3；纯函数、无 `Rng`/时钟/`_process`，M2 替换） |
| `scripts/legion/`、`scripts/data/`、`scripts/fx/` | **待建** | 分别在 M4 / M1 / M3 建目录 |
| `shaders/common/` | 全场景共用着色器 | `toon.gdshader`（3 阶阶梯硬光影）、`outline.gdshader`（逆壳描边） |
| `shaders/terrain/` | 地形/水体专用 | `water.gdshader` |
| `shaders/character/`、`shaders/fx/` | **待建** | 角色与特效着色器（M3 起） |
| `data/` | 资源与数据表（`units/ weapons/ frames/ world/ economy/`） | **已建**（S1.1a 起）：`world/gen_params.json`（世界生成参数表，schema=1）。其余子目录随 M1 之后的数据驱动步骤逐个建 |
| `tools/` | 验收用例与离线脚本 | `verify.gd`（断言运行器）、`img_diff.gd`、`baseline.gd`、`analyze.gd`、`diag.gd`、`probe.gd`、`windtest.gd` |
| `docs/` | 文档 | `ROADMAP.md`（唯一事实来源）、`成果.md`（只追加成果台账）、`ENGINEERING.md`（本文件） |
| `.shots/`、`.verify/` | 产物目录，**不进版本库** | 截图与验收报告 |

**约定增补**：`shaders/common/` 是 S0.1 新增的子目录（原 §3.2 只有 `terrain/ character/ fx/`）。
理由：`toon.gdshader` / `outline.gdshader` 是全场景共用材质，归入 `fx/` 或 `character/` 都名不符实。
已同步登记 `ROADMAP` §3.2 与 §16。

---

## 2. 迁移映射表（旧路径 → 新路径）

S0.1 的 6 批迁移已全部完成，下表**全部为已生效状态**。`.uid` 文件与其 `.gd` / `.gdshader`
同批同目录移动，UID 全部保留。

### 2.1 `scripts/` → `scripts/core/`（批次 1）

| 旧路径 | 新路径 |
|---|---|
| `scripts/main.gd` | `scripts/core/main.gd` |
| `scripts/style.gd` | `scripts/core/style.gd` |
| `scripts/capture.gd` | `scripts/core/capture.gd` |
| `scripts/render_clock.gd` | `scripts/core/render_clock.gd` |
| `scripts/mesh_util.gd` | `scripts/core/mesh_util.gd` |
| `scripts/input_setup.gd` | `scripts/core/input_setup.gd` |
| `scripts/camera_rig.gd` | `scripts/core/camera_rig.gd` |

### 2.2 `scripts/` → `scripts/world/`（批次 2）

| 旧路径 | 新路径 |
|---|---|
| `scripts/terrain.gd` | `scripts/world/terrain.gd` |
| `scripts/water.gd` | `scripts/world/water.gd` |
| `scripts/scatter.gd` | `scripts/world/scatter.gd` |
| `scripts/clouds.gd` | `scripts/world/clouds.gd` |
| `scripts/day_night.gd` | `scripts/world/day_night.gd` |

### 2.3 `scripts/` → `scripts/actors/`、`scripts/ui/`（批次 3）

| 旧路径 | 新路径 |
|---|---|
| `scripts/player.gd` | `scripts/actors/player.gd` |
| `scripts/ui_panel.gd` | `scripts/ui/ui_panel.gd` |
| `scripts/ui_slider.gd` | `scripts/ui/ui_slider.gd` |

### 2.4 `shaders/` 分层（批次 4）

| 旧路径 | 新路径 |
|---|---|
| `shaders/toon.gdshader` | `shaders/common/toon.gdshader` |
| `shaders/outline.gdshader` | `shaders/common/outline.gdshader` |
| `shaders/water.gdshader` | `shaders/terrain/water.gdshader` |

### 2.5 未移动

| 路径 | 说明 |
|---|---|
| `tools/*` | 工具不属于分层约束范围，保持扁平 |

> `scenes/main.tscn` **已不再是未移动项**：S1.0a 把它换路径为 `scenes/dev/diorama.tscn`
> （内容逐字节不变，6 机位 `B-` 逐位仍等于基线）。**S1.0d 起它已从"主场景"降为"仅供回归与取景"**：
> `run/main_scene` 改指 `scenes/world/strategic_map.tscn`，diorama 只能经 `--scene=res://scenes/dev/diorama.tscn`
> 或 `tools/` 进入（缺省批次拍到的是没有相机的空壳）。

> ⚠️ `ROADMAP.md` 的 **§5 S0.6 叙述**、**§16 变更日志**与**附录 A/B** 保留重组前的历史路径
> （它们记录的是当时的事实）。以路径为准时，请查本表。

---

## 3. 引用规则（新增文件前先读）

1. **优先用 `class_name` 跨文件引用**。当前 11 个脚本以 `class_name` 互相引用
   （`Terrain` / `WaterSurface` / `Scatter` / `CloudField` / `DayNight` / `Player` / `CameraRig` /
   `MeshUtil` / `InputSetup` / `UiPanel` / `BrutalSlider`），Godot 按符号解析、**与路径无关**，
   所以移动这些文件不需要改任何引用方。
2. **只有 4 类位置是路径引用，移动文件时必须同批改写**：
   - `project.godot` 的 `[autoload]` 条目；
   - `scenes/*.tscn` 的 `[ext_resource ... path=...]`；
   - 脚本内的 `load()` / `preload()` 字面路径；
   - `tools/verify.gd` 的 `GUARD_WHITELIST`（按**精确路径 + 行号**登记）。
3. **新增脚本的落位**：玩法无关服务 → `core/`；世界生成 → `world/`；可动实体 → `actors/`；
   界面 → `ui/`；战斗 → `battle/`；军团 → `legion/`；数据表读写 → `data/`；特效 → `fx/`。
4. **新增着色器**：全场景共用 → `common/`；地形/水体 → `terrain/`；角色 → `character/`；特效 → `fx/`。
5. **不得**在运行期驱动画面的时间上使用内建 `TIME` 或 `Time.get_ticks_msec/usec()`
   —— 一律走 `Clock`（`scripts/core/render_clock.gd`）；`tools/verify.gd` 的 `unfreezable_time`
   规则会拦截。测量用途的墙钟按白名单登记理由。

---

## 4. 迁移前基线（S0.1 的 `B-` 判定基准）

**采集时间**：2026-10-16，S0.1 任何文件移动**之前**（提交 `437f08f` 时点）。
**命令**（确定性时钟，6 机位，1600×900；⚠️ **S1.0d 起必须带 `--scene=`**，见下方复现命令）：

```powershell
& "G:\godot_project\_godotengine\Godot_v4.7-stable_win64.exe" --path G:\godot_project\mc-npr-godot `
  -- --shots --warmup=60 --frames=15 --out=res://.shots/s01_pre_a
```

> **S1.0a 之后、S1.0d 之前**：`run/main_scene` 曾改指 `res://scenes/dev/diorama.tscn`，而场景内容逐字节
> 未变 —— 那段时间"不写 `--scene=`"取到的还是同一个演示岛（S1.0a 的验收口径就是"换路径后哈希逐位不变"）。
>
> **S1.0d 起这条裸命令拍不到基线了**：`run/main_scene` 已是战略图**空壳**（无相机、无内容），
> 不写 `--scene=` 得到的是一张纯背景图。**当前复现命令必须显式指定夹具**：
>
> ```powershell
> & "G:\godot_project\_godotengine\Godot_v4.7-stable_win64.exe" --path G:\godot_project\mc-npr-godot `
>   -- --shots --scene=res://scenes/dev/diorama.tscn --warmup=60 --frames=15 --out=res://.shots/s11_cam_a
> ```
>
> `--scene=` 是**纯修饰符**（和 `--case=` / `--out=` 同级），单独出现不触发截图批次。换场景
> 发生在快门之前且不额外消耗帧，所以"显式指定"与"缺省"在快门前的 dt 序列完全相同 ——
> 这一条不是容差，是逐位相等：云是增量积分（`position.x += drift * Clock.dt`），多跑一帧
> 哈希就变（实现时实测踩过）。S1.0b 曾用"显式 vs 缺省哈希相同"证明这一点，S1.0d 之后该对照
> 自动失效（缺省已无内容），`s1_0_scene_arg` 改为断言"缺省 ≠ 夹具"。

**基线 sha256**（`res://.shots/s01_pre_a/default.json`；同参数另一次独立进程实测 6/6 相同）：

| 机位 | 参数要点 | sha256 |
|---|---|---|
| `01_dawn` | FOLLOW, time 0.275, size 40, yaw 45 | `6e21376e5acce330c3487125ce0ffb3aee9cbb6d60dc597f1ee095c0815fa0bb` |
| `02_noon` | FOLLOW, time 0.50, size 36, yaw 45 | `5bde250f265a4e614d08f578441576b79c9b90b108629d13a777957233e14978` |
| `03_dusk` | FOLLOW, time 0.735, size 38, yaw 52 | `1a606659be0f3a0a4bf26db5e440bdf0c466c008420fa4383c6e151760f8788e` |
| `04_night` | FOLLOW, time 0.92, size 36, yaw 45 | `729db4c1067374e06a128c730d4b54778d7464c9ea1d80a8df2c4f5c58ba49d9` |
| `05_closeup` | FREE, time 0.40, size 16, yaw 35 | `f7725a5f9faa34dd793decf259e24eda004ed7d78a10bfd8767fd914a3095af4` |
| `06_wide` | FREE, time 0.33, size 66, yaw 40 | `c0858f509f72bcdb0fe61f0a58ae26fcaeed8d6a081edf5449dc434481805438` |

**判定方式**：`--out=res://.shots/<任意>` 重采一次，与上表**逐机位 sha256 相等**即为通过
（`B-` 自 S0.6 起按**逐位一致**判定，不再用百分比容差）。

**复核结果（2026-10-16）**：S0.1 批次 1 / 2 / 3 / 4 与最终回归，以及 S0.3 批次 1 / 2 / 3 / 4，
**每批 6/6 全等**。其中 S0.3 批次 4 新增了菜单与 3×3 宫格（`main.tscn` 里多了一整棵 UI 子树），
6 机位仍全等 —— 因为 `MenuLayer` 默认 `visible = false`，这条同时充当"UI 没有漏进主画面"的强断言。
菜单自身的 4 张 `B-` 截图是**另一组**基线（含中文文本，只在同一台机器上逐位可复现），
不与本表的 6 机位混用。

---

## 5. 执行陷阱（S0.1 实测踩到，后续移动文件必读）

| # | 陷阱 | 症状 | 处置 |
|---|---|---|---|
| 1 | **`.godot` 全局类缓存不随文件移动更新** | headless `--script` 报 `Could not find script for class "MeshUtil"`、`Could not parse global class "CameraRig" from "res://scripts/camera_rig.gd"`（旧路径）、`Class "CameraRig" hides a global script class`（新旧同时注册） | 删除 `.godot/global_script_class_cache.cfg`（必要时连 `.godot/uid_cache.bin`、`.godot/shader_cache/`），再执行 `--headless --import` 重建。`.godot/` 是 gitignore 产物，可再生 |
| 2 | **`.uid` 与脚本必须同批同目录移动** | `uid://` 引用断裂或 UID 被重新分配 | 用 `git mv` 成对移动；S0.1 全程 100% 成对 |
| 3 | **`GUARD_WHITELIST` 按「精确路径 + 规则名」登记，与行号无关** | 移动白名单内文件后 `s0_2_guard` 误报「未登记违例」；反过来，只改行号**不需要**动白名单 | 与文件移动**同批**更新白名单条目里的 `path`（涉及 `core/main.gd`、`core/capture.gd`、`world/terrain.gd`、`dev/art_samples.gd`）。判定口径见 `tools/verify.gd::_whitelist_reason()`：只比较 `path` 与 `rule` 两个字段，行号仅用于打印。⚠️ 本条原文写的是"精确路径 + 行号"，与实现不符，S0.5 更正 |
| 4 | **着色器路径错误会静默退化** | 不报错，但材质回落为默认（画面变样） | 靠 `B-` 6 机位逐位比对兜住；改 `style.gd` 的 3 条 `load()` 后必须复跑 |
| 5 | **`verify.gd` 的子进程必须带 `--` 分隔符** | 子进程收不到 `--shots`，不退出，`OS.execute` 无超时 ⇒ 整个套件静默挂死 | 用 `_exec_user()`（自动插 `--` 并加 `--quit-after` 兜底） |
| 6 | **引擎的「改名覆盖」在 Windows 上不是原子替换** | 跨进程狂写同一槽位时（`s0_3_atomic`，800 次写 / 170~193 次观测），读者会看到 17~28 次「文件不存在」、22~25 次「文件在但读不出来」；但**没有任何一次半截内容**（每一次读得出来的样本都是完整合法 JSON，两轮 131 / 140 个全部合法）。单进程探测只看末态会误判为「无空窗」 | 写者：`.tmp` → 回读校验 → `rename` + 有界重试；读者：`_read_slot_text()` 有界重试，并以「同目录 `.tmp` 是否存在」区分「真空槽位」（立即返回）与「发布中」（重试）。规则与实测数字见 `ROADMAP` §3.5 与 `scripts/core/save_system.gd` 文件头 |
| 7 | **`JSON.parse_string()` 解析失败会打引擎级 `ERROR`** | 坏存档是**正常输入**（玩家能改、磁盘能坏、`s0_3_atomic` 的并发样本），却让 `--headless` 日志出现 `ERROR: Parse JSON failed...`，掩盖真正的错误 | 一律改用 `JSON.new()` + `parse()` 实例接口（返回 `Error`、不打日志），自己把原因写进返回值与信号 |
| 8 | **`OS.create_process()` 的子进程不继承 stdout** | 子进程 `print()` 一行都不到父进程日志里（实测 `[probe] ...` 全部丢失），退出码之外无证据 | 子进程的结论必须**落成文件**（`_probe_loop_summary.json` / `_probe_read_snapshot.json`），父进程读文件断言 |
| 9 | **子进程只认 `--` 之后的 `--out=`** | 父进程用 `--out=res://.verify/<批次>` 隔离报告，子进程仍写默认目录 ⇒ `s0_2_baseline` 整例失败（且假如目录里恰有旧报告，会变成**假通过**） | 任何产出报告的子进程都要显式透传 `--out=`，并在运行前删除旧报告 + 断言其不存在 |
| 10 | **`change_scene_to_file()` 是"帧末生效"，不是"立即换场景"** | 调用返回 `err=0` 后，`SceneTree.current_scene` 在**第 1 帧仍是旧场景**（`--script` 实测为 `null`），**第 2 帧**才是新场景；旧场景及其节点组也不会当帧释放。若调用后立刻查场景状态，会把"已提交的意图"当成"已发生的事实" | 三处一起做：① 断言必须"等到目标场景真的成为 `current_scene` 再多等 2 帧"（`_await_route()`，绝不固定 `await N` 帧）；② 路由器用 `_expected_path` 标记"在飞行中"，此时拒绝第二次切换（否则引擎只保留最后一次请求，栈与屏幕会不一致）；③ 但 `current_route()` 仍如实返回**已提交的意图**，不因旧场景还在就撒谎 |
| 11 | **`SceneTree` 子类里没有 `get_tree()`** | `tools/verify.gd` 继承 `SceneTree`，写 `get_tree().current_scene` / `get_tree().get_node_count()` 直接**解析期报错**（`Function "get_tree()" not found in base self`），整个套件无法加载 | 直接用 `self` 上的成员与方法：`current_scene` / `get_node_count()` / `get_first_node_in_group()`。同一原因，autoload 标识符在 `--script` 里也不参与编译，必须 `get_root().get_node_or_null("Name")` |
| 12 | **节点自动名含全局计数器，不可作为结构指纹** | 同一场景加载两次，未命名节点拿到的是 `@MeshInstance3D@28` 与 `@MeshInstance3D@64`（计数器随进程增长），直接把 `name` 拿去哈希会得出"两次不一样"的错误结论 | 归一化：名字以 `@` 开头时改用 `get_class()`，再按子节点顺序逐条记录 `名字或类:类:子节点数`。归一后 92 条指纹跨次加载**逐位一致**（`fe520385…`）。`s0_3_router` 用它把"回到世界节点数 ±0"升级成"结构逐条相同" |
| 13 | **`verify.gd --all` 在同一个进程里顺序跑完全部用例** | 用例之间会通过全局服务互相污染：`s0_3_roundtrip` / `s0_3_no_autosave` 走后 `SaveSystem.current_slot` 停在 3，于是 `s0_3_slots` 的"没有当前槽位 ⇒ 保存等同另存为"整段**静默退化**成"直接写当前槽位"——**单跑该用例全绿、放进 `--all` 里 7 条失败**。这类失效模式最危险的地方是它只在组合运行下出现，而"每次验收都跑 `--all`"正是唯一能逮住它的手段 | 用例**自带前置条件**：`_restore_defaults()` 补上 `SaveSystem.current_slot` / `last_error` 的复原（`select_slot()` 只接受 1..9、没有公开的"清空"入口，故直接写回默认值），新用例在开头显式复位并把"起步是『没有选中槽位』"写成断言。**新增用例时必须问一句：它依赖上一个用例的残留状态吗？** |
| 14 | **同一秒内的两次存档可以逐位相同** | `s0_3_overwrite` 的"确认覆盖后文件字节确实换了"报失败：`saved_at` 只到秒、`meta` 里其余字段也都取自同一批状态，而整个流程（写 → 弹窗 → 取消 → 弹窗 → 确认）耗时 < 1s，于是覆盖前后**字节逐位相同**是**正确**行为，错的只是断言 | 判"到底写没写"要看**发布次数**而不是内容：订阅 `SaveSystem.save_written` 计数（取消必须 0 次、确认必须 +1），内容层面只断言"仍是完整合法 JSON"。推广：**"值变了" 不适用于幂等写，"发生了写" 才适用** |
| 15 | **UI 控件路径必须相对"菜单节点"写全，且要带自己的包装层** | `--shots` 注入点击时报 `ui 步骤找不到控件：Home/Panel/Col/Actions/SaveAs`（漏了菜单自己的 `Root` 包装层）与 `Root/GridPage/Panel/Col/Grid/Cards/Slot3`（漏了宫格内部的 `Col` 容器）两次 | 路径一律写成**相对菜单节点**的完整链（`Root/Home/...`）；新增 UI 前先用一次性探针把真实节点树打出来再写路径（本批用 `tools/_probe_menu.gd`，验收后删除）。配套约束：找不到控件必须以**非 0 退出**，绝不"拍一张当前画面的图"充当证据 |
| 16 | **`B-` 像素证据要挑"只属于 UI、世界里绝不存在"的颜色** | 想证明 `F1` 真的把界面拿掉了，用"两张图不一样"是不够的（随便一个动画像素也能让它们不同） | 用 `UiKit.PAPER`（`#fff9e8`）的**精确等值像素计数**：HUD 与调试面板的 stylebox 用它，3D 世界里不可能出现（`Style.PALETTE` 无同值色）⇒ `F1` 后该颜色必须为 **0 像素**。读图先 `resize(400,225, INTERPOLATE_NEAREST)` 再数（最近邻只挑真实像素，不插值）；全图 1.44M 像素在 GDScript 里太慢，而问题的答案只是"这颜色还在不在" |
| 17 | **`Performance.TIME_PROCESS` 在本工程对 0.5ms 量级没有分辨率** | ① vsync 开着时"开层/关层帧时间差"是**负**的（关层 18.75 / 开层 17.84 ms，量到的是 vsync 等待与抖动）；② 关掉 vsync 后又量化成 78.58 / 6.204 两个离散值，**挂一个确定的 2ms/帧 负载上去反而更低** | 不要用它做 `C-` 断言。改为**直接给被测代码的每帧工作计时**（`Time.get_ticks_usec()` 包住 `_push_sample`/`_refresh`），并**同时**用同一口径注入 0.5ms / 2ms 自旋作为标尺（实测回收率 ≈100%），先证明"这套量法分辨得出 0.5ms"。详见 `ROADMAP` §16 同名条目 |
| 18 | **Godot 编辑器会重写 `project.godot`：剥掉 `;` 注释、把 `[shader_globals]` 挪到末尾** | 本步期间发生两次。若不复核就 `commit`，会把整文件重排混进功能提交（违反"一次提交只承载一件事"） | 编辑器跑过之后一律 `git diff -- project.godot` 逐行确认；被改乱时 `git checkout -- project.godot` 复原，再按 HEAD 的注释原样补回新行。**注意**：正常的 `--path` 运行（含 `--headless`）**不会**改写它（已实测），只有编辑器会 |
| 19 | **headless 下渲染指标恒为 0，会让"列里有值"的断言假通过** | `--obs-csv=` 的"实时模式有实测值"若在 headless 子进程里验，会得到一列 `0.000` 而 `!= ""` 照样成立（看起来有值、其实是零）：`RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 在 dummy 渲染器下恒 0 | 该探针必须**开窗口**跑，断言写成"**非零**行数 ≥ N"（而不是"列非空"）。同理：`s0_4_cost` / `s0_3_slots` / `s0_3_overwrite` / `s0_2_baseline` / `s0_6_repro` 都标 `kind="headed"`，headless 下跳过而不是判失败 |
| 20 | **headless 下窗口尺寸是 0×0 ⇒ `pure` 用例验不了鼠标命中** | 给菜单调试页按钮写点击断言时，`_click_control` 报告"矩形已排出尺寸、点击真的落下去了"，但处理器**一次都没跑**、提示行原封不动。实测 `DisplayServer.get_name() == "headless"`、`DisplayServer.window_get_size() == (0, 0)`：注入的鼠标事件没有可命中的视口 | `pure` 用例只验"控件在 + 连着处理器 + 处理器真驱动目标"（直接 `pressed.emit()`），鼠标命中路径交给 `headed` 用例（同一套 `UiKit.button_page` 工厂与页面结构）。**注意** `_click_control` 的返回值只说明"矩形非退化"，**不说明事件被谁接住** —— 想区分这两件事，得让处理器留下可观测痕迹（如改写提示行） |
| 21 | **"发布构建完全禁用"的闸门不能只做在 `_input` 里** | `_input` 只挡按键，挡不住"有人直接调 `quick_save()`"（未来的新 UI 入口、测试代码、任何脚本调用都能绕过），于是"完全禁用"名不副实 | 闸门做进**函数内部**：`quick_save()` / `quick_load()` 开头检查 `_quick_enabled()`（= 对应 action 在不在，与 `F1`/`F3` 同一个事实来源）。**不要**为此再写一次 `OS.is_debug_build()` —— `s0_4_overlay` 守着"全项目只有 `input_setup.gd` 一处判断构建类型"，本步第一版就是因为在调试页多写了一行而把该断言变红 |
| 22 | **`var x := <返回 Variant 的调用>` 会编译失败，而不是警告** | 本步给 `capture.gd` 加 `--at=` 时写 `var p := _parse_point(...)`（该函数返回 `Variant`，成功给 `Vector3`、失败给 `null`）。工程开了"警告即错误"，于是 `Parse Error: The variable type is being inferred from a Variant value` ⇒ **整个 `capture.gd` 加载失败** ⇒ 9 个 autoload 里 `Capture` 挂了，引擎报 `Failed to instantiate an autoload` | 显式标注 `var p: Variant = _parse_point(...)`。**更值得记住的是排查路径**：窗口模式（`Godot_v4.7-stable_win64.exe`）跑截图时**静默挂死、一行输出都没有、进程还退干净了**；改用 `*_console.exe --headless --quit-after N` 跑同一场景，编译错误立刻打出来。**症状是"卡住/无输出"，病因往往在编译期，`*_console.exe` 是唯一的眼睛** |
| 23 | **Godot 的 JSON 只有 float 一种数字，且 `String.unicode_compare` 不存在** | 写 `Canon` 时两处实测：① `JSON.parse` 把 `12` 解成 `12.0`、`-0` 解成 `0.0` ⇒ 纯 `%.6f` 的"读回再写"永远不可能与原文相等；② 照文档写的 `String.unicode_compare` 直接编译失败（`Cannot find member "unicode_compare" in base "String"`） | ① 数字规则改为"整数值写整数、非整数 `%.6f`"（理由与边角见 §9.5）；② 键序用 `keys.sort()`（`Array.sort()` 对 String 就是码点序，实测 `["1","A","Z","_x","a","b","中文"]`）。**教训**：格式契约里每条"看起来该有"的 API 都要先跑一次探针再写进文档 —— 这条坑正是"文档先写、代码后写、没人验中间那句"的产物 |
| 24 | **参数表里 int 与 float 无从区分 ⇒ 米制字段会被"整数闸门"悄悄抹平** | S1.1a 的 `GenParams.validate()` 对所有字段一律 `int(roundf(v))`（计数类字段的正确做法）。S1.1b 加 `hill_amplitude` 等 4 个**米制浮点**字段后发现：`120.4` 会被四舍五入成 `120` 并附一条"不是整数"告警 —— 告警在 `warnings` 里，而**地形高度已经按 120 算了**，这种偏差在截图上看不出来，只会让"参数表里写的数"与"实际地形"永久对不上。另外 `Canon` 把整数值的 float 写成 `120`（JSON 无 int/float 之分），所以表文件里这些字段**看起来是整数**，更容易被误改成计数处理 | 显式维护 `GenParams.FLOAT_FIELDS`（S1.1c 起 **6 个**）并在 `validate()` 里**先分支**：浮点字段只 clamp、不取整、int 输入自动升为 float；整数字段保留"四舍五入 + 告警"。用例把两侧都钉住：`137.5` 原样保留且**零告警**（`s1_1_params`），`3.7` → `4` 且**恰好一条**告警。**教训**：`JSON` 没有数字类型，"读到的 `8` 是计数还是 8 米"只能由**代码里的字段清单**回答；新增数值字段时必须同时决定它属于哪一侧 |
| 25 | **"同类聚落"的命名在表里是复数、在代码里是单数 ⇒ 配额静默变 0** | `WorldData.KINDS` 用单数 `village / town / fortress`（它是聚落自己的 `kind` 值），而 `gen_params.json` 的键是复数 `villages / towns / fortresses`（它是计数）。第一版直接写 `params.get(kind, 0)`：三个配额全取到 0 ⇒ 三条锚点各报"超出配额：跳过"、随机点一个不放 ⇒ `settlements` 为空、`build()` 返回 `ok = false`。**没有崩溃、没有报错**，只有三条措辞像是"参数表配错了"的告警 | 用显式映射表 `KIND_PARAM = {village: "villages", ...}`，`_kind_quotas()` 只走它。**教训**：跨文件的两套命名（枚举值 vs 表键）必须在**一个地方**转换，且转换表要有用例覆盖（`s1_1_world` 的"配额全部放出来"就是这条的回归锁）；`Dictionary.get(key, 0)` 在缺键时**不告警**，是本坑能静默的直接原因 |
| 26 | **同一个 seed 生成出两个不同的世界 —— 子流的入口状态没钉住** | `Rng` 的每条子流是"按名字派生一次、之后一直用下去"的；`WorldData` 只承诺"从传入的 `stream` 当前状态开始重放"，**不承诺**"同一个 `world_seed` 永远同一个世界"。用例共享同一条 `world_gen` 子流，于是前一个用例多抽几个数，后一个用例的世界就变了：`--all` 里跑出 26 条边 / 8916.9 m，单跑 24 条 / 7936.7 m（同 seed 20250929）。**症状极具迷惑性** —— 看起来像"随机不稳定"，其实是"世界的定义漏了入口条件" | 定世界之前先定入口：`Rng.reset()`（把每条子流拨回由 `(master_seed, 名字)` 派生的起点）或 `seed_from(world_seed)`，然后再建 `HeightField` / `WorldRegions` / `WorldData`。用例侧见 `tools/verify.gd` 的 `_world_fixture()`；生产侧是 **S1.2 组合根的开工前置** —— 不钉住，"同一个存档种子重建同一个世界"会随玩家这一局先抽了多少随机数而漂移。诊断口径：任何"同一 seed 结果不同"的报障，先查**入口状态**，再查算法 |
| 27 | **引擎运行会悄悄重写 `project.godot`** | 某些引擎路径（编辑器启动、部分导出 / 导入流程）会整段删除 `project.godot` 里的注释、把 `[shader_globals]` 从原位置挪到文件尾。文件功能上仍能跑，但 `git status` 变脏，一不留神就跟着真正的改动一起提交，diff 里全是噪声 | 每次跑完引擎先 `git status --short`；若只有 `project.godot` 变了而你没打算改它，`git checkout -- project.godot` 复原（本批即如此处理），**不要**把它算进功能提交。判据：`git diff project.godot` 里只有"注释消失 + 段序变化"，没有任何值变化 |
| 28 | **`reset()` 只拨回"已存在"的子流，母种子是会话级可变输入** | 写 `s1_2_boot` 时：先 `boot(20250929)`、再 `boot(20250930)`，然后调既有夹具 `_world_fixture()` 想证明"入口与夹具是同一个世界" —— 结果 `region_areas` 全不一样。问题不在世界，而在**母种子已被上一步换成 20250930**：夹具用 `reset()` 按**当前**母种子派生，对照文本却来自 20250929。`Rng.master_seed` 是会话级可变状态，任何 `seed_from()` 都会改掉后续所有派生起点；跨阶段比对前必须把母种子显式拨回要对照的值（本批修法：夹具前 `seed_from(20250929)`） |
| 29 | **逐个三角形去问脚本常量（`Style.pal`）会把建网格拖成秒级** | `s1_2_mesh` 首轮 `build()` 实测 9.2 s：`sample` 6 ms、`classify` 28 ms，而 `land` 3.0 s、`water` 4.8 s。定位到 `_pal()` 每次都要跨 `preload` 的脚本对象取 `const PALETTE`，单次 ≈ **0.9 ms**；11 250 三角 × 数次取色 ≈ 5 s。vertex 本身不慢（同样 11 250 三角纯 `add_vertex` 只要 4 ms） | 调色板在 `build()` 入口**解析一次**存进 `_palette`，之后 `_pal()` 只做字典查找；同一张网格降到 **68.5 ms**（land 19 / water 10 / skirt 2） |
| 30 | **离树节点上 `get_tree()` / `queue_free()` 各打印一条 `ERROR: Parameter "data.tree" is null`** | `StrategicTerrain` 必须能离树构建（`--script` 里 verify 就是这么造的），但 `get_tree()` 一调就报错，且 `queue_free()` 找不到 `SceneTree` 同样报错。13 条 ERROR 全来自这两处，断言却全绿 —— 只看断言会漏 | 取 `Style` 前先 `is_inside_tree()`；清块时 `is_inside_tree() ? queue_free() : free()`。判据：用例输出 `ERROR:` 行数必须为 **0**，与断言同权 |

---

## 6. 当前验收基线

### 6.1 S0.1 验收时点（历史记录，勿重复统计）

| 项 | 结果 |
|---|---|
| 窗口模式 `tools/verify.gd --all` | **8 用例 / 失败 0 / 跳过 0 / 152 断言全通过** / 退出码 0（39.3s） |
| headless `tools/verify.gd --all` | 8 用例 / 失败 0 / 跳过 2（`s0_2_baseline`、`s0_6_repro` 需 GPU）/ 退出码 0 |
| 推送门禁 `--headless --quit-after 60` | 退出码 0，日志 **0 条** `ERROR` / `SCRIPT ERROR` |
| `B-` 6 机位 | 与 §4 基线 **6/6 sha256 全等** |
| autoload 数量 | 3 / 上限 **10**（`Style` `Capture` `Clock`；上限 2026-10-16 由 6 放宽，见 `ROADMAP` §16） |

### 6.2 S0.3 批次 1 验收时点（autoload 3 → 6，只加服务、未改画面）

| 项 | 结果 |
|---|---|
| 窗口模式 `tools/verify.gd --all` | **9 用例 / 失败 0 / 跳过 0 / 178 断言全通过** / 退出码 0（41.6s） |
| headless `tools/verify.gd --all` | 9 用例 / 失败 0 / 跳过 2（`s0_2_baseline`、`s0_6_repro` 需 GPU）/ 退出码 0 |
| 推送门禁 `--headless --quit-after 60` | 退出码 0，日志 **0 条** `ERROR` / `SCRIPT ERROR` / `WARNING` |
| 新增用例 | `s0_3_state`：72 断言全通过（autoload 清单与注册顺序、`SNAPSHOT_FIELDS` == `snapshot()` 键集、逻辑步整数倍、`Rng` 子流隔离与重放、`EventBus` 5 信号与投递、`restore()` 容错、快照往返） |
| `B-` 6 机位 | 与 §4 基线 **6/6 sha256 全等**（新增 3 个 autoload 对渲染零影响） |
| `C-` 性能（3 次采样极差全部 < 0.1%） | `fps_mean 59.98`（vsync 封顶，非真实上限）/ `ms_per_frame 16.671` / `primitives 219978` / `draw_calls 96` / `memory_static 90.95 MB` / `objects 1774` |
| `s0_6_repro` | 31/31 通过 —— 两个独立进程仍逐位一致，`GameState._physics_process` 未扰动可复现渲染 |
| autoload 数量 | **6** / 上限 10（`Style` `Capture` `Clock` `Rng` `EventBus` `GameState`；注册顺序 `Rng` 先于 `GameState`，由 `s0_3_state` 断言） |

> `primitives` 与 `draw_calls` 与 §6.1 完全相同，是"只加服务、未动画面"的第二种独立证据
> （第一种是 `B-` 6 机位 sha256 全等）。`memory_static` 由 89.1 MB 升至 90.95 MB，
> 增量即 3 个 autoload 脚本与其节点，属预期。

### 6.3 S0.3 批次 2 验收时点（autoload 6 → 7，只加服务、未改画面）

| 项 | 结果 |
|---|---|
| 窗口模式 `tools/verify.gd --all` | **13 用例 / 失败 0 / 跳过 0 / 385 断言全通过** / 退出码 0（50.2s） |
| headless `tools/verify.gd --all` | 13 用例 / 失败 0 / 跳过 2（`s0_2_baseline`、`s0_6_repro` 需 GPU）/ 退出码 0（13.1s） |
| 推送门禁 `--headless --quit-after 60` | 退出码 0，日志 **0 条** `ERROR` / `WARNING` / `SCRIPT ERROR` |
| 新增用例（共 156 断言） | `s0_3_roundtrip` 63/63（**真跨进程**：子进程写 → 父进程逐字段比对 → 另一子进程读回，快照以 UTF-8 文件回吐）/ `s0_3_dirty` 47/47（8 类坏档拒读 + 3 类脏字段告警保留当前值 + `v0→v1` 迁移钩子真能跑）/ `s0_3_atomic` 29/29（跨进程并发 800 写 / 170 观测）/ `s0_3_no_autosave` 17/17 |
| `s0_3_state` | 由 72 → **74/74**：autoload 契约 6 → 7，并新增"`SaveSystem` 注册在 `GameState` 之后"的顺序断言 |
| `B-` 6 机位 | 与 §4 基线 **6/6 sha256 全等**，manifest `det=True hz=60.0 t=2.5 frame=150` |
| `C-` 性能（3 次采样极差） | FPS **0.067%** / ms-per-frame **0.054%** / 静态内存 **0.948%** / 三角面 **0.000%** / 绘制调用 **0.000%**（全部 < 5%）；`fps_mean 59.93–59.97` / `ms_per_frame 16.676–16.685` / `primitives 219978` / `draw_calls 96` / `memory_static 91.15–92.02 MB` / `objects 1776–1779` |
| autoload 数量 | **7** / 上限 10（`Style` `Capture` `Clock` `Rng` `EventBus` `GameState` `SaveSystem`；`Rng` 先于 `GameState`、`SaveSystem` 后于 `GameState`，均由 `s0_3_state` 断言） |

> `primitives 219978` 与 `draw_calls 96` 自 §6.1 起三次验收完全不变，再次独立证明"只加服务"。
> `memory_static` 90.95 → 91.15~92.02 MB、`objects` ~1774 → 1776~1779，增量即 `SaveSystem` 节点与其脚本。
>
> **本批最值得记住的负面结论**（详见 §5 陷阱 6 与 `ROADMAP` §5 S0.3 陷阱 2）：单进程探针只看
> **末态**会得出"引擎 rename 覆盖无空窗"的错误结论；跨进程并发观测才测出 Windows 上它其实是
> **"先删目标再改名"**，读者会撞上"文件不存在"或"文件在但读不出来"的瞬间（两轮实测：
> 170 样本 → 17 + 22 次；193 样本 → 28 + 25 次）。结论不是加回滚备份，
> 而是**读者有界重试**——实测把并发读的失败数从 42 压到 **0**，且**从头到尾没有一次半截内容**
> （两轮 131 / 140 个可读样本全部是完整合法 JSON）。

### 6.4 S0.3 批次 3 验收时点（autoload 7 → 8；新增路由与占位战斗场景）

| 项 | 结果 |
|---|---|
| 窗口模式 `tools/verify.gd --all` | **14 用例 / 失败 0 / 跳过 0 / 460 断言全通过** / 退出码 0（50.0s） |
| headless `tools/verify.gd --all` | 14 用例 / 失败 0 / 跳过 2（`s0_2_baseline`、`s0_6_repro` 需 GPU）/ 退出码 0（13.9s） |
| 推送门禁 `--headless --quit-after 60` | 退出码 0，日志 **0 条** `ERROR` / `WARNING` / `SCRIPT ERROR` |
| 新增用例 `s0_3_router` | **70/70**：路由表与 API 契约（8 个公开符号）/ 切换落地前的同帧语义 / `world`→`battle`→`world` 后**节点数 ±0（101 → 101）** / 世界子树**结构指纹逐条一致（92 条，`fe520385…`）** / **seed 派生值一致**（`spawn_point` + `height_at` 两次采样 + `Scatter.stats` 树石数）/ 三类越界的显式拒绝（理由各自指名）/ `route_changed` 恰好 4 次且被拒调用一次不播报 / 占位场景合规（正交相机、242 三角面、`Style.toon()` 且 `next_pass` 非空）/ "场景被外部释放后路由归空" |
| `s0_3_state` | 由 74 → **76/76**：autoload 契约 7 → 8，新增 `SceneRouter` 存在性与"无 `_ready`/`_process`，与其它服务无顺序依赖"的说明性断言 |
| `s0_2_guard` | 由 16 → **19/19**：新增第 8 类违例规则 `scene_change_owner`（唯一属主 `res://scripts/core/scene_router.gd`），带正负对照（路由器路径 0 命中、`res://scripts/world/terrain.gd` 内同一句恰好 1 命中） |
| `B-` 6 机位 | 与 §4 基线 **6/6 sha256 全等**（新增 autoload 与占位场景对 `main.tscn` 渲染零影响），manifest `det=True hz=60.0 t=2.5 frame=150` |
| 占位场景目视复核 | `.shots/s0_3_stub/battle_stub.png`（1600×900，sha256 `79b0610b…`）：正交视角下的面着色沙面 + 岩色底座 + 逆壳描边 + 一行 Label，无立方体、无体素。**临时截图脚本未入库**（M2 真战斗场景会带正式机位），故这只算一次性目检 |
| `C-` 性能（3 次采样极差） | FPS **0.083%** / ms-per-frame **0.084%** / 静态内存 **0.416%** / 三角面 **0.000%** / 绘制调用 **0.000%**（全部 < 5%）；`fps_mean 59.97–60.02` / `ms_per_frame 16.662–16.676` / `primitives 219978` / `draw_calls 96` / `memory_static 91.25–91.63 MB` / `objects 1778–1782` |
| autoload 数量 | **8** / 上限 10（`Style` `Capture` `Clock` `Rng` `EventBus` `GameState` `SaveSystem` `SceneRouter`） |

> `primitives 219978` 与 `draw_calls 96` 自 §6.1 起四次验收完全不变，是"新增服务与占位场景都不在
> `main.tscn` 的渲染路径上"的第三种独立证据（前两种是 `B-` 6 机位 sha256 全等、`s0_3_router` 的
> 结构与 seed 一致性）。`memory_static` 91.15~92.02 → 91.25~91.63 MB、`objects 1776~1779` →
> 1778~1782，增量即 `SceneRouter` 节点与其脚本。
>
> **本批最值得记住的设计结论**：浅栈 + **显式越界失败**比"能回退到任意深度"更适合当前规模。
> 梯度上只有 `world → battle` 两段时，栈深上限（2）本身就隐含了"不能再进"，故把深度检查放在来源检查**之前**，
> 让拒绝理由说"栈已满"而不是"来源不对"——否则深度上限这条规则永远不可观测、等于没写。
> （S1.0d 起路由**表**回到 2 个名字：`world → strategic_map.tscn` / `battle`，可达梯度仍是这两段；
> S1.0c 那个临时名 `strategic` 已删，一个文件只留一个名字。）
> 同理，"回到世界是不是同一片世界"若不查结构与 seed，只查节点总数，那么"重建出一片同规模的
> 另一片地形"也会通过——**弱断言会让错误的实现在验收里活下来**。

### 6.5 S0.3 批次 4 验收时点（autoload 保持 8；新增存档菜单与 3×3 九宫格）

| 项 | 结果 |
|---|---|
| 窗口模式 `tools/verify.gd --all` | **16 用例 / 失败 0 / 跳过 0 / 594 断言全通过** / 退出码 0（71.8s） |
| headless `tools/verify.gd --all` | 16 用例 / 失败 0 / 跳过 **4**（`s0_2_baseline`、`s0_6_repro`、`s0_3_slots`、`s0_3_overwrite` 需 GPU）/ 退出码 0（14.7s） |
| 推送门禁 `--headless --quit-after 60` | 退出码 0，日志 **0 条** `ERROR` / `WARNING` / `SCRIPT ERROR` |
| 新增用例 `s0_3_slots` | **100/100**：装配（`MenuLayer` 默认隐藏、`group=menu` 唯一、菜单层号 > 调试 HUD 层号）/ **暂停契约**（`paused==true` 时主场景 `can_process()==false`，菜单与 `Clock` 为 `true`，且暂停中 `Clock.frame` 精确 +30 帧、`t` +0.5s、暂停中注入的真实点击仍能打开宫格）/ 无当前槽位时「保存」「读取」各自跳宫格并显示服务给的拒绝理由 / 空槽位写入（无需确认、卡片正文立刻 == `slot_info().label`、状态行显示"当前槽位：5"）/ `ESC` 四级层级 / 4 张 `B-` 菜单截图的两轮逐位一致 + 两两不同 + 非空图 |
| 新增用例 `s0_3_overwrite` | **34/34**：点已占用槽位弹出整页确认（标题含槽位号、正文含该档 `label` 与 `saved_at`）/ **弹窗期间与取消后 `saves/` 逐项 sha256+mtime 不变**、`save_written` 发布次数 0 → +1 / `ESC` 先取消弹窗而不关菜单 / 确认后才覆盖且仍是完整合法 JSON / 主页「保存」写已占用的当前槽位同样先问 |
| `B-` 6 机位 | 与 §4 基线 **6/6 sha256 全等**（菜单默认隐藏 ⇒ 主视图零像素变化），manifest `det=True hz=60.0 t=2.5 frame=150` |
| `B-` 菜单 4 张（新增） | 1600×900，两个数据状态 × 两轮独立窗口进程：`01_menu_home eeec5d02…` / `02_grid_empty ce9175ce…` / `03_grid_full a504ec4e…` / `04_overwrite_confirm 1563abf8…`；每张两轮 sha256 逐位一致（`img_diff` `channel=0` 差异像素 0）、四张两两不同、平均亮度 0.2088~0.4615（非空图判定） |
| `C-` 性能（3 次采样极差） | FPS **0.000%** / ms-per-frame **0.000%** / 静态内存 **0.000%** / 三角面 **0.000%** / 绘制调用 **0.000%**；`fps_mean 60.0` / `ms_per_frame 16.667` / `primitives 219978` / `draw_calls 96`（与 §6.1–§6.4 全等）/ `memory_static 126.13 MB` / `objects 2034` |
| `D-` 人工试玩 | **通过（2026-10-16，用户）**：`ESC` 菜单开合、宫格选槽、覆盖二次确认全流程手感确认通过，**无返工项** ⇒ S0.3 置 `✅ 已验收` |
| autoload 数量 | **8** / 上限 10（本批**不新增服务**，菜单是场景内的 UI 节点而非 autoload） |

> `primitives 219978` 与 `draw_calls 96` 自 §6.1 起五次验收完全不变：菜单虽是 `main.tscn` 里的真实
> 节点树，但默认隐藏 ⇒ 不在渲染路径上。
>
> `memory_static` 91.25~91.63 → **126.13 MB**、`objects` 1778~1782 → **2034**。这 +34.8 MB 没有靠猜，
> 用独立探针（headless 加载主场景 → 只释放 `MenuLayer` 子树 → 再读监视器）拆开量过：
> **菜单子树 77 节点 = 34.29 MB / 254 对象**（99.52 → 65.23 MB），窗口侧 +34.8 MB 与之相互印证。
> 主体是中文 `SystemFont`（`SystemFont.font_names` 匹配到系统 CJK 字体）及其字形缓存。
> 本步不动它（UI 必须能显示中文），但**登记一条后续可选项**：若日后要压内存，首选项是把
> `SystemFont` 换成子集化的随包字体，预计可省 ~30 MB。
>
> **本批最值得记住的两条负面结论**（已回写 §5 陷阱 13/14 与 `ROADMAP` §5 S0.3/§15）：
> ① `verify.gd --all` 是**同一个进程里顺序跑完所有用例**，所以"上一个用例停在哪个槽位"属于必须显式
> 复原的状态——`s0_3_roundtrip` 走后 `SaveSystem.current_slot` 停在 3，`s0_3_slots` 的"无当前槽位"
> 整段**静默退化**成另一条分支（单跑该用例全绿、`--all` 里 7 条失败）；② 同一秒内状态没变时两次存档的
> **字节可以逐位相同**（`saved_at` 只到秒），所以"文件内容变了"不能当"确实写过了"的判据，
> 要用 `save_written` 的发布次数（取消必须 0 次、确认必须 +1）。
>
> **本批最值得记住的设计结论**：截图状态由**注入的真实输入**（`Input.parse_input_event`）达成，
> 而不给产品码加"演示状态"钩子。代价是控件路径必须写对，收益是子进程能自证"我到达了声明的界面"
> （`ui_expect`），对不上就以非 0 退出——两个路径 bug（漏了菜单自己的 `Root` 包装层、漏了宫格的
> `Col` 容器）都是这样被当场逮住的，而不是产出一张看着正常的错误截图。

### 6.6 S0.4 批次 1–3 验收时点（autoload 8 → 9：新增 `Debug`）

| 项 | 结果 |
|---|---|
| 窗口模式 `tools/verify.gd --all` | **19 用例 / 失败 0 / 跳过 0 / 761 断言全通过** / 退出码 0（108.0s） |
| headless `tools/verify.gd --all` | 19 用例 / 失败 0 / 跳过 **5**（`s0_2_baseline`、`s0_6_repro`、`s0_4_cost`、`s0_3_slots`、`s0_3_overwrite` 需 GPU）/ 退出码 0 |
| 推送门禁 `--headless --quit-after 60` | 退出码 0，日志 0 条 `ERROR` / `SCRIPT ERROR` |
| 新增用例 `s0_4_overlay` | **70/70**：装配（`Debug` 就位、默认隐藏、层号 30 > 菜单 20 > HUD 10、整层不吃鼠标）/ **开关只改观测不改世界**（关→开→关两轮采样，世界结构指纹 + seed 派生量 + `GameState` 字段 + **`Rng` 每条子流 `state`** 逐项不变）/ `F3` 开合 / `F1` 隐藏 / 菜单开着时按 `F1` / **发布构建门禁**（闸门关掉后注入按键完全无反应，并静态断言 `OS.is_debug_build` 在 `scripts/` 里只出现 1 次）/ 单一闸门 / 确定性口径 / **CSV 双进程逐位一致** / `--obs-csv=` 是纯修饰符（不触发截图、不抢退出码，且"实时模式有非零实测值"开窗口验） |
| 新增用例 `s0_4_cost` | **32/32**：120 实体夹具（`MeshUtil.blob()` + `Style.toon()`，含逆壳描边）/ 叠加层每帧成本 **0.0044 ms**（5 轮 × 400 帧中位数，最大 0.0058）< 0.5ms / **标尺**：同口径注入 0.5ms、2ms 自旋，量到 0.5000、2.0000（回收率 ≈100%）⇒ 阈值可分辨 / 反向对照 `draw_calls` 必须上升 / `B-` 两批次各两轮逐位一致且互不相同 / `vsync` 模式复原 |
| 新增用例 `s0_4_quick`（批次 3） | **62/62**：热键注册（`F5`/`F9` 的 action 与物理键）/ 无当前槽位时拒绝且不发明槽位（目录哈希不变）/ 空槽位一次 `F5` 直写且**全程不打开菜单** / **已占用槽位第一次按 `F5` 后旧档 sha256 逐位不变**、第二次才覆盖（§3.5 的确认没被绕过）/ 确认窗口按帧过期（过期后单按一次又回到"先拒绝"）/ `F9` 真的应用存档字段 / **存档目录里只有 `slot_1..9.json`**（无隐藏槽位、无旁路文件；产品代码 `quicksave` 零命中）/ 发布构建闸门（action 被删 + 直接调用也无写入）/ 菜单调试页事实与 `Debug.stats()` + `SaveSystem.current_slot` 同源、「打开叠加层」按钮真驱动 `Debug`、`ESC` 从调试页回主页 |
| `A-` 开关不改世界（原验收项） | 见 `s0_4_overlay` 第 2 节：两轮采样逐项不变，**含每条 `Rng` 子流的内部 `state`**（覆盖"调试层顺手抽了个随机数"这种内伤） |
| `C-` 开销 < 0.5ms（原验收项） | **0.0044 ms/帧**，且**附可分辨性证明**（见 §5 陷阱 17 为什么必须加这条） |
| `A-` 发布构建默认关闭（原验收项） | 唯一闸门 `InputSetup.ensure_debug_hotkeys(OS.is_debug_build())`，关掉时**删除 action**；用例断言"闸门关掉后按 F3/F1/F5/F9 完全没反应" + 静态扫描证明判断只出现 1 处。**`F5`/`F9` 的闸门做在 `quick_save()`/`quick_load()` 函数内部**，不只是 `_input`（见 §5 陷阱 21） |
| `B-` 6 机位 | 与 §4 基线 **6/6 sha256 全等**（叠加层默认隐藏 ⇒ 主视图零像素变化） |
| `B-` 调试层（新增） | `s0_4_overlay`（面板开）与 `s0_4_ui_hidden`（`F3`+`F1` 全隐藏）各两轮独立窗口进程：同批次两轮 sha256 逐位一致、两批次互不相同；`F1` 后 UI 面板底色 `#fff9e8` **精确 0 像素**（有 HUD 的同机位基准图为 3892 采样像素）⇒ `F1` 是"拿掉"而不是"调透明/盖一层" |
| autoload 数量 | **9** / 上限 10（本批新增 `Debug`，注册在 `SceneRouter` 之后；它自带隐藏 `CanvasLayer`，位置无顺序要求） |

> **批次 1（`ed92e66`）的验收**：抽出 `scripts/ui/ui_kit.gd` 后，`ui_panel` / `menu_page` / `save_grid`
> 三份 UI 的 `B-` 截图逐位不变（4 张菜单 + 6 机位），说明"只搬代码不改画面"。
>
> **本批最值得记住的一条**：`C-` 那条断言原本写成"开层/关层的帧时间差 < 0.5ms"，两次实测都证明它
> **测不出东西**（vsync 开着差值为负；关掉 vsync 注入 2ms 负载只回收 41%）。这类"沉默的绿灯"比失败
> 更危险 —— 它让一个从未被验证过的数字长期挂在验收表上。处置见 §5 陷阱 17：把被测代码的每帧工作
> 直接计时，并**同时**用已知量标尺证明这套计时能分辨该阈值。
>
> **另一条**：`--obs-csv=` 的"实时模式有实测值"最初在 headless 子进程里验，得到一列 `0.000` 而
> `!= ""` 依旧成立（见 §5 陷阱 19）。**"列非空"与"列有真值"是两件事**，后者必须断言数值特征。

---

## 7. 命名规范

### 7.1 文件与目录

| 对象 | 规则 | 例子 |
|---|---|---|
| 脚本文件 | `snake_case.gd`，一个文件一个职责 | `save_system.gd`、`mesh_util.gd` |
| 场景文件 | `snake_case.tscn` | `main.tscn`、`battle_stub.tscn` |
| 着色器 | `snake_case.gdshader`，按用途分目录 | `common/toon.gdshader`、`terrain/water.gdshader` |
| `.uid` 文件 | **与脚本成对同批移动**，不得单独删除或改名 | 见 §5 陷阱 2 |

目录职责见 §1；新增目录须先在 `ROADMAP` §3.2 登记。

### 7.2 `class_name`（全局类）

**17 个**（S0.5 实测 12 个，S1.1a 新增 `Canon` / `GenParams`，S1.1b 新增 `HeightField` / `WorldRegions`，
S1.1c 新增 `WorldData`；`grep -n "^class_name" scripts/**/*.gd`）：

| 类名 | 文件 | 用途 |
|---|---|---|
| `Player` | `scripts/actors/player.gd` | 演示角色 |
| `CameraRig` | `scripts/core/camera_rig.gd` | 正交等距相机 |
| `InputSetup` | `scripts/core/input_setup.gd` | 输入映射 + 唯一调试热键闸门 |
| `MeshUtil` | `scripts/core/mesh_util.gd` | 低模几何库 |
| `Canon` | `scripts/core/canon.gd` | 规范化序列化（S1.1a，§9） |
| `UiKit` | `scripts/ui/ui_kit.gd` | 公共控件工厂 |
| `UiPanel` | `scripts/ui/ui_panel.gd` | 调试 HUD 面板 |
| `BrutalSlider` | `scripts/ui/ui_slider.gd` | 方形滑块 |
| `CloudField` | `scripts/world/clouds.gd` | 云层 |
| `DayNight` | `scripts/world/day_night.gd` | 昼夜与光照 |
| `Scatter` | `scripts/world/scatter.gd` | 植被散布 |
| `Terrain` | `scripts/world/terrain.gd` | 地形生成（演示岛尺度） |
| `WaterSurface` | `scripts/world/water.gd` | 水面 |
| `HeightField` | `scripts/world/height_field.gd` | 战略尺度高度/生物群系场（S1.1b，§9.6） |
| `WorldRegions` | `scripts/world/regions.gd` | Voronoi region 划分（S1.1b） |
| `WorldData` | `scripts/world/world_data.gd` | 聚落 / 道路 / 势力 / 队伍 + 手工锚点（S1.1c，§9.7） |
| `GenParams` | `scripts/world/gen_params.gd` | 世界生成参数表加载与钳制（S1.1a） |
| `WorldSession` | `scripts/world/world_session.gd` | 世界入口 / 组合根：先 seed_from(seed)，再按固定顺序建世界（S1.2a，§9.9） |
| `StrategicTerrain` | `scripts/world/strategic_terrain.gd` | 战略尺度地形网格：32 m × 75×75 = 11 250 三角、6×6 分块、水面 + 外缘墨色裙边（S1.2b，§9.10） |

**规则**：`class_name` 用 `PascalCase`；**新增全局类必须先问"真的需要全局可见吗"** ——
只在两个文件之间用的类型应走 `preload()` 常量（见 §3），因为全局类会进
`.godot/global_script_class_cache.cfg`，改名/移动时要连带清缓存（§5 陷阱 1）。

### 7.3 变量与函数

| 种类 | 规则 | 例子 |
|---|---|---|
| 私有成员 | `_snake_case` 前缀下划线 | `_rng`、`_focus`、`_toon_materials` |
| 常量 | `SCREAMING_SNAKE_CASE` | `SPACING`、`PALETTE`、`GUARD_WHITELIST` |
| 公开方法 | `snake_case()`，动词开头 | `snap_to()`、`set_time()`、`build_ramp()` |
| 私有方法 | `_snake_case()` | `_apply()`、`_build_stage()` |
| 信号处理器 | `_on_<源>_<事件>()` | `_on_regenerate()` |
| 枚举 | `PascalCase` 类型 + `SCREAMING_SNAKE` 值 | `enum Mode { FOLLOW, ORBIT, FREE }` |

### 7.4 类型标注

**一律显式标注**（项目开了 `untyped_declaration` 警告即错误）。特别地：

```gdscript
var p := _parse_point(text)      # ❌ 从 Variant 返回值推断 → 警告升级为错误
var p: Variant = _parse_point(text)   # ✅ 显式声明
```

这条在 S0.5 真的把 autoload 打崩过一次：`capture.gd` 的
`var p := _parse_point(...)`（返回 `Variant`）导致 **整个 `capture.gd` 解析失败**，
连带 9 个 autoload 全部加载不了。见 §5 陷阱 22。

---

## 8. 信号约定

### 8.1 四类命名口径（S0.5 按实际代码更正）

| 类别 | 规则 | 实测清单（25 条声明） |
|---|---|---|
| **按钮/交互** | `*_pressed` | `ui_panel.gd`：`regenerate_pressed` / `outline_pressed` / `bands_pressed` / `camera_pressed` / `autocycle_pressed`；`save_grid.gd`：`slot_pressed` |
| **状态变化** | `*_changed` | `style.gd`：`style_changed`；`day_night.gd`：`cycle_changed(on)`；`ui_slider.gd`：`value_changed(v)`；`debug_layer.gd`：`ui_hidden_changed(hidden)`；`scene_router.gd`：`route_changed(from, to)` |
| **请求** | `*_requested` | **暂无实现**（约定保留；出现时按此命名） |
| **已发生事实** | 过去式 `<subject>_<past_participle>` | `event_bus.gd`：`time_advanced` / `encounter_started` / `battle_finished` / `settlement_entered` / `resources_changed`；`save_system.gd`：`save_written` / `save_failed` / `load_failed` / `slot_loaded`；`terrain.gd`：`generated(stats)`；`menu_page.gd`：`opened` / `closed`；`debug_layer.gd`：`overlay_toggled(on)`；`ui_panel.gd`：`time_scrubbed(t)` |

> **为什么规则改成了 `*_pressed`**：`ROADMAP` §3.2 原文的按钮信号口径是 `on_` 前缀 + 动词，
> 但既有 7 处实现一致用过去式。S0.5 对齐时有两个选项 —— 改代码或改规则。
> **选了改规则**：`*_pressed` 是 Godot 生态的既有惯例（`BaseButton.pressed` 就是过去式），
> 改名会让 7 个信号与它们的全部连接点同时变动，却换不来任何行为收益。
> 判定口径：**信号名描述"已经发生的事"，不描述"该做什么"** —— 这条同时解释了
> `*_pressed`、`*_changed` 和过去式事实信号为什么是一套而不是三套。

### 8.2 事件总线 vs 局部信号

| 放哪里 | 判据 |
|---|---|
| `EventBus`（autoload） | 跨模块的**全局事实**：时间推进、遭遇、战斗结束、资源变化、进入聚落 |
| 组件自身 | 只有父子/兄弟关系知道的**局部事实**：按钮按下、滑块拖动、页面开关、存档槽点击 |

**判据的实操形式**：如果订阅者需要 `get_node("../../..")` 才能拿到发信号的节点，
那它就该走 `EventBus`；如果订阅者就在同一个场景子树里，走局部信号。
把局部信号塞进 `EventBus` 会让"谁在听"变得无法追踪。

### 8.3 连接与断开

- 一律用 `signal.connect(callable)`，不用字符串形式的 `connect("name", ...)`（后者拼错是运行时静默失败）。
- 长生命周期节点连短生命周期节点时用 `CONNECT_ONE_SHOT` 或显式 `disconnect()`，避免悬挂回调。
- **不要**在 `_process` 里 `connect`（会重复连接并抛错）。

---

## 9. 数据表格式（`Canon` 契约）

> ✅ **`Canon` 已落地**（S1.1a）：`scripts/core/canon.gd`，`class_name Canon`（不是 autoload，
> 纯静态，余量留给 M1–M6）。本节由"契约草案"改为"实现说明"；`s0_5_doc_conventions`
> 断言的是"本节标了已落地 + `canon.gd` 真的存在 + 三个入口都在"，以及"旧的『未实现』标记已清空"。

### 9.1 为什么需要规范化序列化

世界生成与存档要做**字节级比对**（"同一个 seed 是否真的生成了同一个世界"）。
`JSON.stringify()` 的键序取决于字典插入顺序、浮点打印位数也不固定，同一份数据能写出
不同字节。所以需要一个规范化出口。

### 9.2 契约

| 项 | 规定 |
|---|---|
| 编码 | UTF-8，**不带 BOM** |
| 换行 | `\n`（LF），**不用** `\r\n`；文件末尾**恰好一个** `\n` |
| 键序 | 按 Unicode **码点**升序（`Array.sort()`），嵌套对象递归排序。⚠️ 原文写的是 `String.unicode_compare` —— **该 API 在 Godot 4 不存在**（实测 `Cannot find member "unicode_compare" in base "String"`），S1.1a 更正 |
| 浮点 | 非整数值 `%.6f`（定点 6 位，不用科学计数法）；**整数值写成整数**（`2400.0` → `2400`）。原因见 §9.5 ① |
| 整数 | 十进制，无前导零；`\|x\| > 2^53` 的整数值 float 用 `%.0f`（仍是纯整数位串，不用 `1e+20`） |
| 负零 | 归一为 `0` / `0.000000`：`-1e-9` 不会被写成 `-0.000000` |
| 布尔/null | `true` / `false` / `null` |
| 数组 | **保序**（不排序；顺序是数据，不是迭代副作用） |
| 空容器 | `{}` / `[]`，写在一行 |
| schema 字段 | 每个顶层对象必须含 `"schema": <整数>`，用于版本迁移（§3.5）。写成 `1.0` 也接受（读回按整数写），写成 `1.5` 拒绝 |
| 不支持的值 | `Vector3` / `Color` / `Object` / 非字符串键 / `NAN`·`Inf` → **整次序列化失败**并报出键路径（如 `$.a.b[1]`）。**绝不退化成 `str()`** —— 那会把"逐字节相等"偷偷降级成"`str()` 相等" |
| 嵌套上限 | 64 层（自引用结构会在这里被拦住，而不是爆栈） |
| 文本 | 一律存 **key**（如 `"ui.menu.save"`），不存已翻译的字符串 —— 语言切换时存档不用重写 |
| 读入容错 | 数值超范围时**钳制到合法区间**，不静默接受、也不整份拒读。⚠️ 原因写进返回值的 `warnings`，**由调用方决定是否 `push_warning`**（`GenParams` 与 `SaveSystem` 同口径；纯函数保持可测、不打日志） |

### 9.3 与 `SaveSystem` 的边界（并更正一处过期说法）

⚠️ 本节原文声称"`SaveSystem`（S0.3，已实现）**已经**是键字典序 + `%.6f` + `\n`"，
**S1.1a 实测为假**：`save_system.gd` 用的是
`JSON.stringify(_build_payload(slot), "  ", false)` —— 键序是**插入序**（`false` 是"不排序"），
浮点是**最短往返表示**（`0.1 + 0.2` 打成 `0.3`）。`Canon` 因此是**新写的**纯序列化层，
不是"从 `SaveSystem` 抽出来"的。

所以 **S1.1a 不动 `SaveSystem` 的写出路径**（改了会让 9 槽位 / 原子写用例的字节断言全变），
分工先记为：

| | 负责 | 格式 |
|---|---|---|
| `SaveSystem` | 存档：槽位、原子写、迁移钩子 | 暂不动（插入序 + 最短浮点） |
| `Canon` | 世界生成 / 数据表 / 任何要逐字节比对的产物 | 本节契约 |

统一留到 **S1.9（存档 schema v2）**：那时一次性把存档写出切到 `Canon`，并重跑 `s0_3_*`。

### 9.4 四个入口

```gdscript
Canon.to_text(value)          # → {ok, text, reason}
Canon.from_text(text)         # → {ok, value, reason}（数字一律是 float，见 §9.5 ①）
Canon.canonicalize(text)      # 解析后重新规范化 → {ok, text, reason}（判断"这个文件是否规范"）
Canon.write_file(path, value) # → {ok, path, bytes, sha256, reason}（写后回读校验，失败不落盘）
```

返回 `Dictionary` 而不是裸 `String`：空串与"合法但为空"无法区分，想忽略错误的人必须显式忽略 `ok`。

**第一张按本契约落地的表**：`data/world/gen_params.json`（`scripts/world/gen_params.gd`，
`GenParams.load_from()` / `validate()`）。它的表文件逐字节等于自己的 `canonicalize()` 结果 ——
手改破坏格式会被 `s1_1_params` 逮住（`docs/ROADMAP.md` §6 S1.1）。

### 9.5 两处实测更正（S1.1a）

① **Godot 的 JSON 解析把每个数字都变 float**：`parse("12")` → `12.0`，`parse("-0")` → `0.0`。
若坚持纯 `%.6f`，`schema: 1` 会写成 `1.000000`、读回再写仍是 `1.000000`（看似幂等），
但任何 int 字段一旦经过一次解析就永久变成浮点形态；而"整数值写整数"让
`表文件 == canonicalize(表文件)` 这种**文件级**断言成立。这是选它的唯一理由，不是为了好看。

② **`%.6f` 的两个边角**：`"%.6f" % 1e-9` → `0.000000`（很小但非零的数会被写没，属可接受的定点损失）；
`"%.6f" % -1e-9` → `-0.000000`（负零噪声，已归一到 `0.000000`）。
`is_finite(NAN) == false`，所以非有限数走失败分支而不是写成 `nan`。

### 9.6 战略尺度高度场与 region 划分（S1.1b）

> ✅ **已落地**：`scripts/world/height_field.gd`（`class_name HeightField`）、
> `scripts/world/regions.gd`（`class_name WorldRegions`）。两者都是 `RefCounted` 实例类，
> **不占 autoload**（仍 9 / 10）。用例 `s1_1_height`（41 断言）/ `s1_1_regions`（37 断言）。

#### 9.6.1 单位与坐标系（唯一约定，不许有第二种）

| 量 | 单位 / 取值 | 说明 |
|---|---|---|
| `height_at(x, z)` | **世界米**，原点在地图中心 | 与渲染面同轴；海平面 = 参数 `water_level`（默认 0） |
| `normalized_height_at(x, z)` | `0..1` | `(h − water_level) / (max_height − water_level)`，水下钳到 0 |
| `max_height` | 米 | `base_height + hill_amplitude × 1.30 + detail_amplitude`，**由参数算出**；`RELIEF_CEILING = 1.30` 是结构常量不是玩法数值 |
| `slope_at(x, z)` | 米/米（升跑比） | 中心差分，探距 `SLOPE_STEP = 8.0 m`；`0.3` 以上算陡坡（`ROCK_SLOPE`） |
| `map_size` 与 `GRID` | 米 / 格 | `world_half = map_size / 2`；归属网格 `CELL = 32.0 m` ⇒ 默认 2400 米 = **75 × 75** 格 |
| `biome_at` | 6 个字符串之一 | `water` / `beach` / `grass` / `forest` / `highland` / `snow`；陆地 5 种在 `LAND_BIOMES` |

**为什么高度返回米而不是 0–1**：`strategic_terrain` 要拿它直接顶点定位、聚落要判"是否在水下"、
镜头要算包围盒 —— 全都需要米。归一化只留给需要 0–1 的消费方（配色 ramp、坡度直方图），
且它必须是**另一个显式函数**，否则"我拿到的是米还是比例"会靠猜。

#### 9.6.2 决定论：高度场里没有随机

- 5 层 `FastNoiseLite`（`_n_coast` / `_n_base` / `_n_ridge` / `_n_detail` / `_n_moisture`）的种子
  = `world_seed + {0, 977, 4241, 7331, 1699}`，**偏移是写死的**；同 `world_seed` + 同参数 ⇒
  逐点逐位相同（用例用 `PackedFloat32Array ==` 比对整张 75×75×3 采样表，而不是抽样近似）。
- 噪声频率一律用**"跨地图周期数"**表达（`_cycles(c) = c / map_size`，取 3 / 4 / 7 / 60 / 5）：
  改 `map_size` 是**缩放**地形，不是改变"地形里能放几座山"。写成"每米频率"会得到相反的行为，
  而且要到 S1.2 接渲染时才会发现。
- 随机只出现在 **region 中心**：`WorldRegions._init(field, stream, params)` 显式接收一个
  `RandomNumberGenerator`。游戏侧传 `Rng.stream("world_gen")`；`verify.gd` 是 `--script` 模式
  （没有 autoload 标识符），用 `get_root().get_node("Rng").call("stream", "world_gen")`。
  **不读 autoload、不裸 `randf()`** —— 否则同一 seed 的重放会取决于"之前谁抽过随机"。

#### 9.6.3 重放随机序列的最省事办法：`RandomNumberGenerator.state`

`state` 是可读写的 `int`。用例的做法是：`saved = stream.state` → `build()` → `stream.state = saved`
→ 再 `build()`，然后逐格比较 `owner`。这比"另建一个同 seed 的 RNG"更严格 —— 它验证的是
**同一条序列**，而不是"另一个从同一起点出发、可能走岔的实现"。反向对照：换 `world_seed`
后数量或归属必有一项不同（否则"重放相同"就退化成恒真）。

#### 9.6.4 region 划分契约

- 中心数 = `stream.randi_range(regions_min, regions_max)`（默认 6–9）；放不下时**告警并降级**
  （`regions` 里如实给出实际数量），不崩、不静默补位。
- 归属：每个单元格就近中心（`owner[i] = argmin`），**陆地格恰属一个 region**、水格 `owner = -1`。
  因此"面积和 = 陆地格数 × 32²"是可以直接算出来对账的，不需要额外记账。
- `prune()` 删掉 0 格 region 并**重编号**（`id` 保持 `0..count-1` 稠密）—— 稠密 id 让存档、
  UI、AI 都能用数组下标，不必维护"id → 槽"的映射。
- 返回 `{ok, count, regions, cell, grid_w, grid_h, land_cells, water_cells, warnings}`；
  查询面只暴露 `region_at(x, z)` / `region_info(id)` / `area_total()` / `cell_count_total()` /
  `water_cell_count()` / `biome_counts()`，**外部不直接改 `owner`**。

#### 9.6.5 实测（2026-10-20，默认参数 2400 米 / seed 20250929）

| 指标 | 值 |
|---|---|
| 陆地占比 | **0.629**（75×75 采样点中 62.9% 高于海平面） |
| 高度区间 | 最低 **−78.17 m**、最高 **107.71 m**（理论上限 146 m） |
| 最陡坡度 | **1.245**（深海底 0.262） |
| biome | 900 点扫描出现 **6 / 6** 种 |
| region | **8 个**（区间 6–9），面积守恒，中心点各自归位 |
| 采样代价 | 5 625 点 **6.9 ms** |
| `build()` 代价 | **10.5 ms** |

#### 9.6.6 与 `terrain.gd` 的关系：复制形状，不复制数值

`terrain.gd` 是 6 机位 `B-` 基线的承载者（§4），**本批一字节未动**。`HeightField` 借鉴它的
手法（掩码 + 岛屿幂 + 噪声叠加 + 山脊），但**参数、尺度、返回值语义都另立**（63 米演示岛 ↔
2400 米战略图）。不要为了"少写一份"去改 `terrain.gd` 的签名或常量：那会同时改动 6 张基线图
和 S0.3 的 `spawn_point` / `height_at` 断言。

### 9.7 世界数据：聚落 / 道路 / 势力 / 队伍（S1.1c）

> ✅ **已落地**：`scripts/world/world_data.gd`（`class_name WorldData`，`RefCounted`，**不占 autoload**）
> + `data/world/anchors.json`。用例 `s1_1_world`（308 断言）。

#### 9.7.1 生成顺序（先钉锚点，再撒随机，最后连图）

`build()` 固定五步，顺序本身是契约：

1. `_place_anchors()` —— 锚点表逐条校验后**直接采用坐标**（见 9.7.4）；
2. `_place_generated()` —— 按 `villages / towns / fortresses` 的配额补齐（村庄先撒，城镇与要塞后挑）；
3. `_assign_factions()` —— 首都 = 最远点采样选出的城镇，聚落按最近首都归属；
4. `_build_roads()` —— 最近邻骨架 + 补边直至单连通；
5. `_spawn_parties()` —— 每支队伍挂一个母城，在母城周围 40–200 m 环带里找可站立点。

**为什么锚点必须先放**：随机点会挤占锚点周围的最小间距。先撒随机再钉锚点，就只能"把随机点
删掉给锚点腾位置"，那会让同 seed 的世界依赖锚点表的长度 —— 锚点表一改，整张图全变。

#### 9.7.2 落点合法性：四条闸门 + 有上限的重试

一个点算"能放聚落"必须同时满足：① 在 `|x|,|z| ≤ map_size/2 − 80 m` 内；② 不在水面
（`HeightField.is_water`）；③ `slope_at ≤ settlement_slope_limit`（默认 **0.35**）；④ 与所有已放
聚落距离 `≥ settlement_min_spacing`（默认 **120 m**）。队伍只查 ①②③。

- 每个聚落最多试 `MAX_PLACE_TRIES = 200` 次（**结构常量**，不进参数表：它不是玩法旋钮）。
  用完仍放不下 ⇒ **告警 + 按实际数量降级**，`ok` 仍为 `true`。这是 ROADMAP 里"落不下则重试
  有上限、上限内失败换噪声偏移（不是死循环）"的落地方式；`s1_1_world` 用 `spacing = 900 m`
  把这条路径压出来，并断言 3 秒内结束。
- 阈值参数化而非硬编码：`settlement_min_spacing` / `settlement_slope_limit` 都在
  `gen_params.json`（安全区间 40–600 m / 0.05–1.0）。测过：默认地形上 `slope ≤ 0.35` 的陆地格
  只占 **38.7%**（中位坡度 0.42），所以这两个数一动，"能放几个"会立刻变 —— 必须能调。

#### 9.7.3 道路是图，不是网格

每条路只记 `{a, b, length}`（两端聚落 id + 直线距离，米）。**本批不铺几何**：避水寻路、路面网格、
桥与隧道都属于 S1.2 的战略渲染，现在铺一遍只会被相机换代推翻。

连通性用并查集保证：每点连最近 `ROAD_K = 2` 个邻居（去重）→ 仍有多个分量时，反复挑"跨分量的
最近点对"补边，直到单连通。因此**边数不是定值**（默认参数实测 24 条 / 7936.7 m），但
"连通分量 = 1"是硬不变量。`s1_1_world` 的连通性断言用**独立实现的 BFS**，不调用 `WorldData`
的并查集 —— 否则等于用被测代码验证被测代码。反向对照：把某个聚落的边全删掉，BFS 必须报出 ≥ 2 个分量。

#### 9.7.4 锚点表契约（优先级最高，坏锚点只跳过）

`data/world/anchors.json`：`{schema: 1, anchors: [{id, kind, name, x, z}]}`，`kind` ∈
`village / town / fortress`，`id` 是稳定标识（存档与后续事件都靠它）。

- **坐标逐位采用**，不抖动、不吸附、不重算 —— 这是 `A-`"锚点 100% 生效"能被逐位断言的前提。
- 坏锚点（kind 非法 / 落水 / 坡度超限 / 与已放聚落太近 / 超出该类配额 / id 重复）⇒
  **跳过 + 一条告警**，世界继续生成，配额由随机点补足。**绝不悄悄挪到"附近合法位置"**：
  锚点的全部价值就是"它在那儿"。
- 锚点坐标本身也是被断言的对象：地形参数一改导致锚点落水，`s1_1_world` 会立刻红 ——
  这是特性（锚点与环境必须一致），不是误报。
- 读表走 `WorldData.load_anchors()`（`{ok, anchors, warnings, reason}`）；表文件本身必须是
  `Canon` 规范形式（用例逐字节比对 `Canon.canonicalize(file)`），且 `_read_text_file` 读到的
  内容里 `\r` 必须为 0。

#### 9.7.5 势力与队伍

- 势力数 = `factions`（2–5）。**首都用最远点采样**从城镇里选（先取离地图中心最远的城镇，之后每次取
  离已选集合最远的），全程无随机 —— 换 seed 时城镇自己会动，不需要再抽一次。
- 聚落归属 = 最近首都（平局取小编号）。队伍数 = `ai_parties`，按 `i % factions` 轮流分配，
  所以各方队伍数相差 ≤ 1；母城从本方聚落里随机取，落点在母城环带内找，找不到就退回母城坐标并
  汇总一条告警。

#### 9.7.6 实测（2026-10-20，默认参数 2400 米 / seed 20250929）

| 指标 | 值 |
|---|---|
| 聚落 | **20**（12 村庄 + 4 城镇 + 4 要塞），锚点 3 条全部命中，**0 告警** |
| 道路 | **24 条**，总长 **7936.7 m**，连通分量 **1** |
| 最小聚落间距 | **131.0 m**（下限 120 m） |
| 队伍 | **24** 支，三方各 **8** 支 |
| 聚落按 region 分布 | 8 个 region 分到 4 / 3 / 6 / 2 / 2 / 1 / 1 / 1 |
| `build()` 代价 | 中位 **2.31 ms**（min 2.23 / max 2.40，5 次） |
| 换 seed | 20 个聚落里 **19** 个坐标变化 |
### 9.8 世界数据的序列化与宏观指标（S1.1d）

#### 9.8.1 为什么序列化放在 `WorldData`，而不是新开一个类

`WorldData` 已经握着**唯一的**世界真相（聚落 / 道路 / 势力 / 队伍 + 生成时的参数快照）。再拆一个
`WorldSerializer` 只会有两种下场：要么它 `duplicate()` 一份字典、从此有两份真相要同步；要么它反过来
读 `WorldData` 的私有字段，等于把封装拆了。所以 `to_dict()` / `to_text()` / `metrics()` 都挂在这里。

**它不碰 `user://`**。落盘是 `SaveSystem` 的事（§9.3），本批只产出**字符串**；"读回再写幂等"这个
判据在内存里用 `Canon.from_text` → `Canon.to_text` 就能证，不需要写一次磁盘再读回来。

#### 9.8.2 契约

- `to_dict() -> Dictionary`：顶层 `{schema, world_seed, params, metrics, settlements, roads,
  factions, parties}`。`params` 是生成时的**快照**（`duplicate(true)`），不是活引用 —— 之后改参数表
  不会让已生成的世界"看起来不一样"。
- 四个数组**各自按稳定文本键排序**后再写（聚落 / 势力 / 队伍按 `id`，道路按 `a`）：`id` 是
  `kind_序号` 形式的本地名（`village_3`），`a` 是小端序聚落 id。排序的目的不是好看，而是**不依赖生成
  顺序** —— 将来生成顺序一变（比如先撒队伍后撒聚落），存档仍然可逐字节比对。这两个键都不做本地化，
  不进 UI 文案，所以可以当稳定键用。
- **坐标不取整**。取整会改动批 3 已验收的落点（间距下限 131.0 m 会立刻变），而 Canon 的 `%.6f`
  已经保证同样的浮点写同样的字节，取整于是只有坏处没有好处。
- `to_text() -> Dictionary`：**返回 Canon 契约** `{ok, text, reason}`，不是裸 `String`。理由同 §9.2：
  空串和"合法但为空"分不开，想忽略错误就必须显式忽略一个 `ok` 标志。
- `metrics() -> Dictionary`：`{land_ratio, coastline_length, region_count, region_areas,
  settlements_by_region, settlement_count, road_count, road_length, party_count}`。
  **海岸线长度的定义**：在 `regions.owner` 的 4 邻域里数"陆地格 ↔ 水格"的**内部边**，乘
  `WorldRegions.CELL`（32 m）；地图外框的四条边**不计**，否则"地图有多大"会混进"海岸有多长"。
  region 全空时整组指标退化为 0（不报错），调用方自己看 `region_count`。

#### 9.8.3 为什么不拿"聚落数"当"换 seed 必变"的指标

默认配额是 `villages 12 + towns 4 + fortresses 4`，于是**聚落数恒为 20**，不管 seed 怎么换。拿它做
断言就是恒真断言 —— 红灯永远不会亮，绿灯什么也没证明。本批换成四项**真的会动**的分布指标，并要求
**至少 3 项**同时变化（实测 4 / 4 全动）：

| 指标 | seed 20250929 | seed 20250930 | seed 31415926 |
|---|---|---|---|
| 海岸线长度 | 9216.0 m | 9792.0 m | 9216.0 m |
| 陆地占比 | 0.629 | 0.621 | 0.610 |
| region 数 | 8 | 8 | 8 |
| 最大/最小 region 面积比 | 9.69 | 7.34 | 10.58 |
| 道路总长 | 7936.7 m | 变化 | 变化 |
| 聚落按 region 分布 | 变化 | 变化 | 变化 |
| 聚落数 | 20 | 20 | 20（**恒真，故不用**） |

`settlements_by_region` 是长度 = `region_count` 的整数向量，比较时比整条向量，不比"哪一格最大" ——
后者会把"4/3/6/2/2/1/1/1"和"4/3/6/2/2/2/0/1"看成一样。

#### 9.8.4 实测：整条链仍然远低于预算

`C-` 的 800 ms 预算覆盖的是"生成 + 序列化"整条链。默认参数、headless、三次：

| 阶段 | 中位耗时 |
|---|---|
| `HeightField` + `WorldRegions.build()` | ≈ 13 ms（批 2 的 region 划分 10.5 ms 为主） |
| `WorldData.build()` | 2.3 ms（§9.7.6） |
| `to_text()`（10 298 字符） | ≈ 0.4 ms |
| **合计** | **15.36 / 15.32 / 16.01 ms，最慢 16.0 ms** |

#### 9.8.5 决定论的真实边界：子流的**入口状态**也要钉住

`A-` 说的是"同一个 seed 生成两次，序列化结果字节完全一致"。本批把它做成用例时踩到一个**真实缺陷**：
世界生成用的是 `Rng.stream("world_gen")`，而同一进程里所有用例**共享**这一条子流。谁先跑，谁就把状态
推远了：

| 跑法 | 道路 | 总长 |
|---|---|---|
| 单跑 `--case=s1_1_gen` | 24 条 | 7936.7 m |
| `--all`（前面用例先抽过数） | 26 条 | 8916.9 m |

同一个 seed、同一份参数表，世界不一样 —— 这不是"用例不稳定"，是"世界的定义漏了入口条件"。修法是把
入口钉死：`Rng.reset()` 会把每条子流重新拨回 `(master_seed, 名字)` 派生的起点（`scripts/core/rng.gd`
的 `reset()` 就是为这个语义准备的），夹具先 `reset()` 再建世界，两种跑法随即**逐字节一致**，且与批 3
记录的 24 条边 / 7936.7 m 完全吻合（说明批 3 那次量到的正是"开局状态"的世界）。

**这条对 S1.2 是硬前置**：组合根在建世界之前必须 `Rng.reset()` 或 `seed_from(world_seed)`，否则"同一
个存档种子重建同一个世界"会随玩家这一局先抽了多少随机数而悄悄漂移。`ENGINEERING.md` §5 陷阱 26。

---

### 9.9 世界入口与组合根（S1.2a）

#### 9.9.1 为什么要有"入口"，而不是每个场景自己 `new`

`HeightField` / `WorldRegions` / `WorldData` 都是**被动**的：它们从传入的 `RandomNumberGenerator`
**当前状态**接着抽数，谁先抽、抽了几个，它们一概不知道。于是"同一个 seed 同一个世界"这句话，
在这三个类的契约里根本不成立 —— 它只有在"调用方先把子流拨回 seed 派生的起点"时才成立。
S1.1d 就是这么抓到 26 条边 vs 24 条边的（§9.8.5、§5 陷阱 26）。

`WorldSession` 就是那个调用方，也是**唯一**的调用方：场景不 `new` 三个对象，只 `boot()` 一次；
顺序、重置、参数装载、告警汇总都收在这一个函数里。这样"世界的定义"从一句话变成一段代码，
后来加多少场景都不会各自漂。

#### 9.9.2 契约

| 项 | 内容 |
|---|---|
| 入口 | `WorldSession.boot(rng: Node, seed: int, params := {}, params_path := GenParams.PATH, anchors_path := WorldData.PATH) -> WorldSession` |
| `rng` | **参数注入**，不取 autoload：`--script` 下 autoload 标识符不可编译，且用例要能注入真身（见 §9.9.3 的反向对照） |
| 第一步 | `rng.seed_from(seed)` —— 丢掉所有旧子流，`stream("world_gen")` 因此只由 seed 决定 |
| 顺序 | `HeightField`（地形）→ `WorldRegions.build()`（划分）→ `WorldData.build()`（聚落/道路/势力/队伍）。反过来会读到还没算出来的高度 / region |
| 只读视图 | `ok` / `errors` / `warnings` / `world_seed` / `params` / `field` / `regions` / `data` / `anchors` / `metrics()` / `to_text()` / `map_size()` / `region_count()` / `summary_text()` |
| 不做什么 | 不写 `user://`（落盘归 `SaveSystem`）、不建网格、不碰渲染、不注册 autoload |

#### 9.9.3 失败语义：三级，不是一个 `bool`

| 字段 | 含义 | 世界存在吗 |
|---|---|---|
| `ok` | 完整世界建成了 | — |
| `errors` | 致命原因（参数表不可用 / 拿不到子流 / region 一个都没落下 / 聚落全部放不下） | **否**，`ok = false`，调用方应显示原因而不是继续 |
| `warnings` | 降级原因（锚点表坏了、某类配额没放满、region 中心不足……） | **是**，`ok` 仍为 true，世界可玩但已知缺了什么 |

锚点表坏掉被**故意**降级为告警：手工锚点是"更好看"，不是"能不能开局"。而参数表坏掉是致命的：
没有地图尺寸就没有世界。

#### 9.9.4 场景接线（`strategic_map.tscn`）

- 根节点 `StrategicMap` 挂 `scripts/world/strategic_map.gd`，`_ready()` 里 `boot()` 一次；
  `session` 与 `boot_error` 都是可读成员，方便用例与调试层。
- **autoload 按路径取**（`/root/Rng`、`/root/GameState`），不写标识符：`--script` 模式照样能
  实例化这个场景做接线断言。`GameState` 缺失时退回常量 `FALLBACK_SEED = 20250929`（与
  `GameState.DEFAULT_WORLD_SEED` / `Rng.DEFAULT_MASTER_SEED` 同值）。
- 本批**不渲染**：节点仍零子节点、无相机。批 2 往这个根上挂地形网格，批 3 挂镜头 —— 它们都从
  `session` 取世界，不再自己建。

#### 9.9.5 实测（2026-10-20）

| 项 | 数值 |
|---|---|
| 一次 `boot()` | ≈ **16 ms**（批 4 实测整条链 15.36 / 15.32 / 16.01 ms，含高度场 + region + 世界数据 + 序列化） |
| `s1_2_boot` 用例 | **31 断言 / 114 ms**（含 6 次 `boot()` + 一次 `_world_fixture()` + 场景实例化） |
| 世界文本 | 10 298 字符（seed 20250929，20 聚落 / 24 道路 / 3 势力 / 24 队伍） |
| 与批 4 的一致性 | `boot()` 的文本与 `_world_fixture()` **逐字节相同** ⇒ 入口没有另立一套生成顺序 |

**已知边界**：`WorldSession` 只保证"从 seed 重放一次世界"。它不缓存、不做增量、也不定义
"读档后如何重建"（S1.9）—— 那时要的是"从存档里的 `world_seed` 重放 + 状态覆盖"，同样走这个入口。

---

### 9.10 战略地形网格（S1.2b）

**要解决的问题**：`HeightField` 是 2400 m 尺度的场，`terrain.gd` 是 63 m 的岛屿回归夹具。两者不能共用
一个网格模块 —— 格距相差 50 倍，色带阈值、描边策略、水面做法全都要另算。`StrategicTerrain` 是前者
的网格化，只做"把场变成可看的三角面"，不做镜头（§9.11，S1.2c）。

#### 9.10.1 为什么格距是"派生"的

```gdscript
cells = maxi(2, int(round(field.map_size / CELL_TARGET)))   # 2400 / 32 = 75
step  = field.map_size / float(cells)                        # 75 格 ⇒ 32.0 m 整
```

写死 75 会在换 `map_size` 时让格距漂移；写死 32 会在 2400 以外的地图上留边条。派生一次两边都守住：
格距永远≈32 m，网格永远正好铺满 `[-half, +half]`。三角数是 `75 × 75 × 2 = 11 250`，约为岛屿夹具
（21 632）的一半、`C-` 上限（34 611）的三分之一。

**6×6 分块不能整除 75**（75 / 6 = 12.5），`_split()` 切成 `13/13/13/12/12/12` —— 块大小差一格（32 m），
比把格数改成 78（格距 30.77 m）更值得，因为"32 m / 11 250 三角"是写进验收表的数字。

#### 9.10.2 契约

| 项 | 值 |
|---|---|
| 入口 | `StrategicTerrain.build(field: HeightField) -> Dictionary`，可重复调用（先清旧块） |
| 节点结构 | `StrategicTerrain` → `Chunks` → `Land_cx_cz`（36）、`Water_cx_cz`（按需，实测 22）、`Curtain`（1） |
| `stats` 键 | `ok / cells / chunks / land_tris / water_tris / skirt_tris / tris / step / size / min_y / max_y / coast_cells / rock_cells / bands / timing` |
| 纯函数性 | 不抽随机数：色相抖动来自位置哈希 `_hash2()`，所以"两次 build 逐字节一致"是可证事实 |
| 材质来源 | 在树里用 `/root/Style`；离树（`--script`）走同一 `toon.gdshader` / `water.gdshader` 的降级材质，调色板始终取 `StyleScript.PALETTE`（与 `Style` 的 const 同源） |

#### 9.10.3 与岛屿地形（`terrain.gd`）的四处刻意差异

| 项 | 岛屿（63 m / 104 格） | 战略（32 m / 75 格） | 为什么 |
|---|---|---|---|
| 描边 | 全地形逆壳（`outline.gdshader`，`ink: 3.0`） | **陆面不挂逆壳**；海岸一格墨线 + 外缘裙边墨色顶带 | 32 m 格距下逆壳膨胀量相对格子太大，陡坡接缝会把海岸糊成一条黑带 |
| 色带 | 米制阈值（沙 < 1.8 m / 草 < 7.0 / 高 < 9.7，`MAX_HEIGHT` 12.6） | **归一化高度**（0–1，除以 `field.max_height` 146 m） | `hill_amplitude` 是 120 而非 12.6，米制阈值搬过来只会得到一个全草的球 |
| 水面 | `WaterSurface` 贴合岛屿轮廓的 56 格网格 | 只在水下格上铺平面，顶点色带深度渐变 + 泡沫 alpha，复用同一 `water.gdshader` | 战略图的海是背景板，不需要岛屿那套岸线贴合 |
| 随机 | RNG 抽数 + 3×3 模糊 + 多数票 | **只有位置哈希**（`_hash2`），模糊/多数票仍用于去抖动 | 要让"同一 field ⇒ 同一网格"可断言，而不是"大概率一样" |

海滩带不按绝对高度切：战略海岸落差快，纯高度阈值实测只圈到 **3 格**沙。改成"接触水的那一圈干格
即海滩"（209 格海岸环），再叠加多数票去抖动，实测 **309 格**。

#### 9.10.4 实测（seed 20250929）

| 项 | 实测 |
|---|---|
| 三角 | 陆 **11 250** + 水 4 470（2 235 格）+ 裙边 1 200 = **16 920** |
| 建网格 | **68.5 ms**（用例侧计时）。产品码里**没有** `Time.*`：`s0_2_guard` 的 `unfreezable_time` 规则不允许（§5 陷阱 29 里那 9.2 s 的分段数字是临时插桩测的） |
| 块节点 | 36 陆 + 22 水 + 1 裙边 = **59**（只在水下格存在时才建水块，所以不是 36 块水） |
| 高度 | −78.24 m … +113.26 m（落差 **191.5 m**） |
| 色带格数 | 水 2 127 / 海滩 309 / 草 1 237 / 高地 1 901 / 雪 51 |
| 裸露岩石 | 22 格（梯度判据：滩 0.50 / 草 0.65 / 高 0.85 / 雪 0.95） |
| `s1_2_mesh` | **105 断言 / 421 ms**；用例输出 `ERROR:` 行 **0** |

#### 9.10.5 已知边界

1. **本批没有肉眼验收**。`B-` 三张截图要等 S1.2c 的镜头；本批用几何断言替代（顶点有限、落在 ±1200 m、
   水面 y 恰为海平面、海岸环与色带非空、两次 build 签名一致、换 seed 必变）。
2. 水面是"水下格上的平面"，起伏由 `water.gdshader` 的 `render_time` 统一驱动；没有逐顶点波浪，也没有
   b 批之后才会有的岸线细分。
3. 岩石率很低（22 / 5 625 格），因为战略尺度的绝大多数坡缓于梯度 0.5；这是判据正确而不是漏算。
4. 分块目前只为"以后能裁剪/LOD"服务：本批不按距离隐藏，36+22 块始终全画。`C-` 的 FPS 采样在 S1.2c 之后。
5. **两条既有判据随本批迁移（不是弱化）**：`s0_3_router` 的世界基线从"指纹恰为 `StrategicMap:Node3D:0`"改为"指纹形如『根 → 地形 → 块容器』+ 每块都有 mesh + 仍无 `Camera3D`"（76 → 81 断言）；`s0_2_guard` 抓到产品码里的 6 处 `Time.get_ticks_usec()`，计时器整体移到用例侧。

---

## 10. autoload 上限与顺序

**当前 9 / 上限 10**（S0.4 批次 2 新增 `Debug` 后；`ROADMAP` §3.2 已同步更正）。
余量 1 个，留给 M1–M6。

| # | 名称 | 文件 | 顺序约束 |
|---|---|---|---|
| 1 | `Style` | `scripts/core/style.gd` | 无（但 `toon()` 会被其它 autoload 调用，故排最前） |
| 2 | `Capture` | `scripts/core/capture.gd` | 无 |
| 3 | `Clock` | `scripts/core/render_clock.gd` | 无 |
| 4 | `Rng` | `scripts/core/rng.gd` | **必须在 `GameState` 之前**（`GameState._ready()` 调 `Rng.seed_from`） |
| 5 | `EventBus` | `scripts/core/event_bus.gd` | 无 |
| 6 | `GameState` | `scripts/core/game_state.gd` | 在 `Rng` 之后 |
| 7 | `SaveSystem` | `scripts/core/save_system.gd` | **必须在 `GameState` 之后**（读写 `GameState.snapshot()`） |
| 8 | `SceneRouter` | `scripts/core/scene_router.gd` | 无（无 `_ready` / `_process`） |
| 9 | `Debug` | `scripts/core/debug_layer.gd` | 无（自带隐藏 `CanvasLayer`） |

三条顺序约束由 `s0_3_state` 断言（不是靠注释维持）。`project.godot` 里每条 autoload
上方都写了顺序理由 —— 编辑器会剥掉 `;` 注释（§5 陷阱见 S0.4 结案记录），所以**改完要复核**。

**新增 autoload 前必须回答**：① 它真的需要全局唯一吗（能不能做成场景内节点）？
② 余量够吗？③ 有没有顺序依赖，谁断言它？

---

## 11. 允许 / 禁止清单

### 11.1 允许

| 项 | 说明 |
|---|---|
| `MeshUtil` 的全部生成器 | `blob` / `cone` / `tapered_cylinder` / `superellipse_prism` / `combine` / `facet` / `roughen` |
| `Style.toon()` / `Style.pal()` / `Style.lit()` | 唯一合法的材质与取色入口 |
| `Rng.stream(name)` / `rng.randf()` / `rng.randi_range()` | 成员调用是正确写法 |
| `Clock.dt` / `Clock.t` / `render_time`（着色器） | 唯一合法的时间来源 |
| `SceneRouter` 切场景 | 只有它能调 `change_scene_to_file` 等 |
| `SaveSystem` 读写 `user://` | 只有它能碰存档目录 |
| `JSON.new().parse()` | 解析不可信输入（不打引擎日志） |
| `InputSetup.ensure_debug_hotkeys(OS.is_debug_build())` | 唯一的调试热键闸门 |

### 11.2 禁止（守卫自动检查，白名单外一律验收失败）

| 禁用 | 守卫规则 | 理由 |
|---|---|---|
| `BoxMesh` | `box_mesh` | `AGENTS.md` §一：绝对禁止立方体 |
| `CSGBox3D` | `csg_box` | 同上（CSG 的方块） |
| `StandardMaterial3D` | `standard_material` | 破坏 3 阶阶梯与描边（见 `ART_PIPELINE.md` §2.2 ⑤） |
| 裸 `randf()` / `randi()` / `*_range()` | `bare_randf` / `bare_randi` | 破坏可复现性 |
| 着色器内建 `TIME` | `unfreezable_time` | 截图无法逐位复现 |
| GDScript `Time.get_ticks_msec/usec()` | `unfreezable_time` | 同上（测量用墙钟走白名单） |
| 非 `scene_router.gd` 里的 `change_scene_*` | `scene_change_owner` | 「屏幕为什么变了」将无法定位 |

### 11.3 守卫管不到的（**只能靠人**）

| 项 | 为什么管不到 | 怎么防 |
|---|---|---|
| 未 `facet()` 的引擎 primitive | 不是"用了某个类"，而是"少调了一次函数" | `ART_PIPELINE.md` §4 清单 + 看图 |
| 硬编码颜色 | 无法区分"调色板色"与"随手写的 RGB" | code review |
| 材质没走 `Style.toon()` | 自建 `ShaderMaterial` 也是合法的 | 表现为"关描边后这个物件还有黑边" |
| 网格法线朝内 | 静态扫不出几何朝向 | 看图（会被光照照黑） |

> **这一节比前两节更重要**。守卫绿了只说明"没有明显违规"；`SphereMesh` 不改一行代码
> 就能绕过全部 7 条规则（`ART_PIPELINE.md` §2.2 ⑥ 就是活证据）。

---

## 12. 新增一个物件 / 一个用例 / 一个 autoload

### 12.1 新增合规物件

见 `docs/ART_PIPELINE.md` §3 的 6 步模板（选形状 → 保证面着色 → 取色 → `Style.toon()` →
挂场景 → 跑守卫 + 看图）。本文件不重复。

### 12.2 新增一个 verify 用例

1. 在 `tools/verify.gd` 的 `CASES`（第 74 行）注册 `id` + `desc` + `kind`（`pure` / `headed`）。
2. 在 `_dispatch()`（第 510 行）加 `match` 分支。
3. 写 `_case_<id>()`，**开头必须 `await process_frame`**（等 autoload 就位）。
4. `pure` 用例在 headless 下必须能跑；`headed` 用例要真 GPU 指标，headless 下自动 SKIP。
5. 用 `section()` 分段、`ok()` / `eq()` / `ne()` / `ge()` / `le()` / `contains()` 断言。
6. **问一句：它依赖上一个用例的残留状态吗？**（§5 陷阱 13 —— 这条坑过一次，
   单跑全绿、`--all` 里 7 条失败）
7. **问第二句：反向对照是什么？**（"文档里有关键字"不等于"文档是对的" ——
   见 `s0_5_doc_conventions` 用编造的锚点证明这一点）

### 12.3 新增一个 autoload

见 §10 的三个必答问题；改完 `project.godot` 后必须 `git diff` 逐行确认
（编辑器会重写该文件并剥掉注释），并同步更新 `s0_3_state` 里的 `expected` 数组。

---

## 13. S0.5 验收时点（2026-10-19）

| 项 | 结果 |
|---|---|
| 窗口模式 `tools/verify.gd --all` | **20 用例 / 失败 0 / 跳过 0 / 1108 断言全通过** / 退出码 0（约 108s），**连跑 2 轮均绿** |
| headless `tools/verify.gd --all` | 20 用例 / 失败 0 / 跳过 **5**（`s0_2_baseline`、`s0_6_repro`、`s0_4_cost`、`s0_3_slots`、`s0_3_overwrite` 需 GPU）/ 退出码 0 |
| 新增用例 `s0_5_doc_conventions` | **90/90**（`pure`，70ms）：12 个 `class_name` 双向定位 / 4 类信号口径各有实例 / `Canon` 标注"未实现"且 `canon.gd` 确实不存在 / autoload 9 与顺序约束 / 7 条守卫规则名逐条"文档有 + 守卫真能报出" / `ART_PIPELINE` 6 步模板 + 6 张图引用齐全 / **教材目录双向约束**（产品码 0 处引用 `dev/`，夹具命中数恰等于白名单登记数） / 6 张 PNG 的 sha256 与批次清单逐位一致 / **4 条编造锚点反向对照** |
| `A-` 抽查 5 条约定能在代码定位（原验收项） | 用例对 **12 个类 + 25 条信号 + 9 个 autoload + 7 条守卫规则** 逐条断言"文档有锚点"**且**"代码里有对应实现"，远超抽查 5 条 |
| `B-` 3 张合规 + 3 张违例（原验收项） | `docs/art/s0_5/` 六张 PNG 的 sha256 与 `s0_5_samples` 批次清单逐位一致；两次独立窗口进程拍同一批次 **6/6 相同** |
| `B-` 6 机位基线（回归） | 与 §4 基线 **6/6 sha256 全等**（本步未触碰主场景、着色器、`style.gd`、`scatter.gd`、`terrain.gd`、`camera_rig.gd`） |
| `C-` 性能基线（回归） | `s0_2_baseline` 通过；FPS 极差 0.150% / ms-per-frame 极差 0.138%（均 < 5%） |
| `D-` 你通读两份文档（原验收项） | **通过**（用户 2026-10-19 确认）；状态与台账已置 `✅ 已验收` |
| autoload 数量 | **9** / 上限 10（本步未新增 autoload） |

### 13.1 顺手修掉的既有缺陷：注入点击缺鼠标移动

`_click_control()` / `_click_path()` 原本只注入 `pressed` / `released` 两个
`InputEventMouseButton`，**没有 `InputEventMouseMotion`**。后果是 `s0_3_slots`
间歇性失败 —— 在 **HEAD（本步改动之前）** 上跑 5 次就红了 2 次，失败点每次不同
（有时是"读取没跳宫格"，有时是"另存为没进宫格"，有时是两轮截图 sha256 不一致）。

根因：Godot 的 `Viewport` 在处理鼠标按键时用 `gui.mouse_focus` 决定投递给谁，
而该焦点**由鼠标移动事件更新**；没有移动，按键就落在一个失效的焦点上。

修法：点击前先发一个落在目标中心的 `InputEventMouseMotion`（**不改产品码**，
只让注入序列符合真实输入 —— 真人点击之前一定先移动鼠标）。修后
`s0_3_slots` **连跑 18 次全绿**，`--all` 连跑 2 轮全绿。

> **值得记住的两点**：
> ① **"偶发失败"要先证明它是既有的**。做法是把 `git show HEAD:tools/verify.gd`
> 导成一个临时脚本跑同样的用例 —— 它同样红，才说明不是自己引入的。
> ② **失败点漂移是"共享前置条件坏了"的典型特征**。如果每次都红在同一条断言，
> 那是那条断言的问题；红点到处跑，说明更早的某一步（这里是"点击真的落下去了"）
> 时灵时不灵，下游全是受害者。
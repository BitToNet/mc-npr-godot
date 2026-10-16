# 工程结构（Pocket Sandbox — NPR Diorama）

> 本文件由 **S0.1 目录与工程结构重组**产出，记录目录职责、旧→新路径映射、迁移前基线哈希
> 与执行陷阱。**目录约定的权威定义在 `docs/ROADMAP.md` §3.2**；本文件是其落地记录。
>
> ⚠️ **本文件尚未完成**：按 `ROADMAP` §5 S0.5，本文件还需补齐**命名规范、信号约定、
> 数据表格式、autoload 上限（当前 8 / 上限 10）、允许/禁止清单**；S0.5 另产出
> `docs/ART_PIPELINE.md`（含「新建合规物件」6 步模板与 3 个反例 + 内嵌截图）。
> 当前内容仅覆盖 S0.1 的交付范围。

---

## 1. 目录职责

| 目录 | 职责 | 当前内容（S0.1 后） |
|---|---|---|
| `scenes/` | 场景文件 | `main.tscn`（主场景；**S0.1 未移动**，改名 `scenes/dev/diorama.tscn` 留到 S1.2 与 `main.gd` 拆分一起做；S0.3 批次 4 挂载 `MenuLayer`，**默认隐藏**）、`battle/battle_stub.tscn`（战斗**占位靶子**，S0.3 批次 3；M2 用真战斗场景替换） |
| `scripts/core/` | 与玩法无关的基础设施与服务 | `main.gd`（编排/autoload 宿主）、`style.gd`（美术中枢，autoload `Style`）、`capture.gd`（截图，autoload `Capture`）、`render_clock.gd`（时间，autoload `Clock`）、`rng.gd`（随机，autoload `Rng`，S0.3 批次 1）、`event_bus.gd`（全局事实信号，autoload `EventBus`，S0.3 批次 1）、`game_state.gd`（本局状态与存档字段，autoload `GameState`，S0.3 批次 1）、`save_system.gd`（存档服务，autoload `SaveSystem`，S0.3 批次 2）、`scene_router.gd`（场景路由，autoload `SceneRouter`，S0.3 批次 3；**唯一允许切场景的文件**）、`mesh_util.gd`（低模几何库）、`input_setup.gd`（输入映射）、`camera_rig.gd`（正交等距相机） |
| `scripts/world/` | 世界生成与自然元素 | `terrain.gd`、`water.gd`、`scatter.gd`（植被散布/MultiMesh）、`clouds.gd`、`day_night.gd` |
| `scripts/actors/` | 可动实体 | `player.gd`（演示角色） |
| `scripts/ui/` | 界面 | `ui_panel.gd`（调试面板，S0.3 批次 4 起显式 `PROCESS_MODE_ALWAYS`）、`ui_slider.gd`（方形滑块）、`menu_page.gd`（游戏内菜单页：主页 / 宫格 / 覆盖确认三页，S0.3 批次 4）、`save_grid.gd`（3×3 存档宫格组件，S0.3 批次 4） |
| `scripts/battle/` | 战斗（M2 主体） | `battle_stub.gd`（战斗**占位靶子**，S0.3 批次 3；纯函数、无 `Rng`/时钟/`_process`，M2 替换） |
| `scripts/legion/`、`scripts/data/`、`scripts/fx/` | **待建** | 分别在 M4 / M1 / M3 建目录 |
| `shaders/common/` | 全场景共用着色器 | `toon.gdshader`（3 阶阶梯硬光影）、`outline.gdshader`（逆壳描边） |
| `shaders/terrain/` | 地形/水体专用 | `water.gdshader` |
| `shaders/character/`、`shaders/fx/` | **待建** | 角色与特效着色器（M3 起） |
| `data/` | 资源与数据表（`units/ weapons/ frames/ world/ economy/`） | **待建**（M1 起，数据驱动要求见 §3.2） |
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
| `scenes/main.tscn` | S0.1 恪守「主场景不变」；改名 `scenes/dev/diorama.tscn` 留到 S1.2 |
| `tools/*` | 工具不属于分层约束范围，保持扁平 |

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
**命令**（确定性时钟，6 机位，1600×900）：

```powershell
& "G:\godot_project\_godotengine\Godot_v4.7-stable_win64.exe" --path G:\godot_project\mc-npr-godot `
  -- --shots --warmup=60 --frames=15 --out=res://.shots/s01_pre_a
```

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
| 3 | **`GUARD_WHITELIST` 按精确路径 + 行号登记** | 移动白名单内文件后 `s0_2_guard` 误报「未登记违例」 | 与文件移动**同批**更新白名单条目（涉及 `core/main.gd`、`core/capture.gd`、`world/terrain.gd`） |
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
> 只有两个路由时，栈深上限（2）本身就隐含了"不能再进"，故把深度检查放在来源检查**之前**，
> 让拒绝理由说"栈已满"而不是"来源不对"——否则深度上限这条规则永远不可观测、等于没写。
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
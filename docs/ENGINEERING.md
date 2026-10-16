# 工程结构（Pocket Sandbox — NPR Diorama）

> 本文件由 **S0.1 目录与工程结构重组**产出，记录目录职责、旧→新路径映射、迁移前基线哈希
> 与执行陷阱。**目录约定的权威定义在 `docs/ROADMAP.md` §3.2**；本文件是其落地记录。
>
> ⚠️ **本文件尚未完成**：按 `ROADMAP` §5 S0.5，本文件还需补齐**命名规范、信号约定、
> 数据表格式、autoload 上限（当前 3 / 上限 6）、允许/禁止清单**；S0.5 另产出
> `docs/ART_PIPELINE.md`（含「新建合规物件」6 步模板与 3 个反例 + 内嵌截图）。
> 当前内容仅覆盖 S0.1 的交付范围。

---

## 1. 目录职责

| 目录 | 职责 | 当前内容（S0.1 后） |
|---|---|---|
| `scenes/` | 场景文件 | `main.tscn`（主场景；**S0.1 未移动**，改名 `scenes/dev/diorama.tscn` 留到 S1.2 与 `main.gd` 拆分一起做） |
| `scripts/core/` | 与玩法无关的基础设施与服务 | `main.gd`（编排/autoload 宿主）、`style.gd`（美术中枢，autoload `Style`）、`capture.gd`（截图，autoload `Capture`）、`render_clock.gd`（时间，autoload `Clock`）、`mesh_util.gd`（低模几何库）、`input_setup.gd`（输入映射）、`camera_rig.gd`（正交等距相机） |
| `scripts/world/` | 世界生成与自然元素 | `terrain.gd`、`water.gd`、`scatter.gd`（植被散布/MultiMesh）、`clouds.gd`、`day_night.gd` |
| `scripts/actors/` | 可动实体 | `player.gd`（演示角色） |
| `scripts/ui/` | 界面 | `ui_panel.gd`（调试面板）、`ui_slider.gd`（方形滑块） |
| `scripts/battle/`、`scripts/legion/`、`scripts/data/`、`scripts/fx/` | **待建** | 分别在 M2 / M4 / M1 / M3 建目录 |
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

**复核结果（2026-10-16）**：批次 1 / 2 / 3 / 4 与最终回归，**每批 6/6 全等**。

---

## 5. 执行陷阱（S0.1 实测踩到，后续移动文件必读）

| # | 陷阱 | 症状 | 处置 |
|---|---|---|---|
| 1 | **`.godot` 全局类缓存不随文件移动更新** | headless `--script` 报 `Could not find script for class "MeshUtil"`、`Could not parse global class "CameraRig" from "res://scripts/camera_rig.gd"`（旧路径）、`Class "CameraRig" hides a global script class`（新旧同时注册） | 删除 `.godot/global_script_class_cache.cfg`（必要时连 `.godot/uid_cache.bin`、`.godot/shader_cache/`），再执行 `--headless --import` 重建。`.godot/` 是 gitignore 产物，可再生 |
| 2 | **`.uid` 与脚本必须同批同目录移动** | `uid://` 引用断裂或 UID 被重新分配 | 用 `git mv` 成对移动；S0.1 全程 100% 成对 |
| 3 | **`GUARD_WHITELIST` 按精确路径 + 行号登记** | 移动白名单内文件后 `s0_2_guard` 误报「未登记违例」 | 与文件移动**同批**更新白名单条目（涉及 `core/main.gd`、`core/capture.gd`、`world/terrain.gd`） |
| 4 | **着色器路径错误会静默退化** | 不报错，但材质回落为默认（画面变样） | 靠 `B-` 6 机位逐位比对兜住；改 `style.gd` 的 3 条 `load()` 后必须复跑 |
| 5 | **`verify.gd` 的子进程必须带 `--` 分隔符** | 子进程收不到 `--shots`，不退出，`OS.execute` 无超时 ⇒ 整个套件静默挂死 | 用 `_exec_user()`（自动插 `--` 并加 `--quit-after` 兜底） |

---

## 6. 当前验收基线（S0.1 验收时点）

| 项 | 结果 |
|---|---|
| 窗口模式 `tools/verify.gd --all` | **8 用例 / 失败 0 / 跳过 0 / 152 断言全通过** / 退出码 0（39.3s） |
| headless `tools/verify.gd --all` | 8 用例 / 失败 0 / 跳过 2（`s0_2_baseline`、`s0_6_repro` 需 GPU）/ 退出码 0 |
| 推送门禁 `--headless --quit-after 60` | 退出码 0，日志 **0 条** `ERROR` / `SCRIPT ERROR` |
| `B-` 6 机位 | 与 §4 基线 **6/6 sha256 全等** |
| autoload 数量 | 3 / 上限 6（`Style` `Capture` `Clock`） |
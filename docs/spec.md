# 开发规格 spec.md —— Pocket Sandbox · NPR Diorama

> **版本**：v0.1（2026-10-19，本会话与用户 8 问对齐后成稿）
> **定位**：`ROADMAP.md` 管「做什么 / 什么算通过 / 现在到哪一步」；**本文管「怎么做」** ——
> 契约长什么样、动手前必须定死什么、每步的完成定义（DoD）与取证命令。
> **分工原则**：状态与验收结论**只**写在 ROADMAP §15 台账；本文不复制状态，只写设计与契约，
> 避免两份文档互相漂移。
> **与上游的关系**：`AGENTS.md`（美术 + 提交规范）> `ROADMAP.md`（计划与验收）> 本文（实现细节）。
> 三者冲突时以更上游为准，并回头改本文。

---

## 0. 三分钟读懂

| 项 | 内容 |
|---|---|
| 现在在哪 | M0 只剩 **S0.4 批次 3**（`F5`/`F9` + 菜单调试入口）与 **S0.5**（纯文档）；M1 十步全部未开始 |
| 下一步做什么 | **S1.0 场景与路由迁移**（本文建议新增，见 §5）→ 再进 S1.1 |
| 为什么不是直接写 S1.1 | 战略图要接管 `world` 路由并把演示岛降级；这件事会动到**已验收的** `s0_3_router` 断言与 6 机位基线，必须先做完、单独提交、单独验收 |
| 三条最容易踩的坑 | ① autoload 只剩 1 个名额（9/10），M1 一律不许新增；② 现在是**三个时钟**（`Clock` 渲染 / `GameState.game_time` 世界 / `DayNight` 视觉），S1.4 必须收敛成一个；③ 6 机位 sha256 基线是逐位门禁，战略图一上线它就必须**重定向**而不是"看起来一样" |

---

## 1. 已对齐决策（2026-10-19 本会话，8 问）

| # | 决策点 | 结论 | 主要落点 |
|---|---|---|---|
| A-1 | 本文范围 | **M1–M6 全景摘要 + M1 详细** | §6 §7 |
| A-2 | 战略图与路由 | **战略图接管 `world`**，演示岛降为 `scenes/dev/diorama.tscn`（内容不变） | §5 |
| A-3 | 世界状态归属 | **不新增 autoload**，世界状态并入 `GameState` | §3 §4.1 |
| A-4 | 游戏时钟 | **`GameState.game_time` 是唯一游戏时钟**，`DayNight`/HUD 全部派生 | §4.5 |
| A-5 | 未接战斗时的遭遇 | **冻结 `BattleContext` + 确定性自动结算**，面板显式标注「占位」 | §4.4 §6.6 |
| A-6 | 主角出身（原 Q4） | **单主角固定出身，势力归属可变** | §6.1 |
| A-7 | 本地化（原 Q2） | **从 S1.5 起全部文本走 key**（`tr()` + CSV） | §6.5 |
| A-8 | 战争迷雾（原 Q9） | **两级：已探索 / 未探索**，不做视线遮挡 | §6.6 |

**既有裁定（沿用，不再讨论）**：D1 战略图 + 独立战斗场景 / D2 阶段顺序 大地图→Boss→装备→军团→兵团 /
D3 横版 2.5D 帧数据内核 / D4 小队编队 60–120 单位 / Q10 九宫格 9 槽不自动存档 / Q13 确定性时钟（S0.6 已验收）。

---

## 2. 全局不变式（Invariants）

新代码必须满足；验收时逐条查。违反任一条即为返工，不接受"以后补"。

| id | 不变式 | 怎么查 |
|---|---|---|
| I-1 | **autoload 冻结在 9 个**（上限 10，最后 1 个名额保留）。M1 一律不新增；M2–M5 如需新增必须先改本文与 ROADMAP | `s0_4_overlay` 的 autoload 清单断言 |
| I-2 | **唯一游戏时钟 = `GameState.game_time`**；`Clock` 只服务渲染与 HUD；新动画禁读 `TIME` / `Time.get_ticks_*` | `s0_6_clock` + 守卫 `unfreezable_time` |
| I-3 | 只有 `SceneRouter` 能切场景；只有 `SaveSystem` 能读写 `user://` | 守卫 `scene_change_owner` / `s0_3_state` |
| I-4 | 一切新 UI 走 `UiKit`；**禁止**任何页面再自建 `_sb()`/`_label()` 样式助手 | `s1_5_settlement` 静态扫描 |
| I-5 | 禁方块/体素；几何走 `MeshUtil`，材质走 `Style.toon()`，新颜色必须进 `Style.PALETTE` | 守卫 + 每步 `B-` |
| I-6 | **确定性**：同 seed 同输入 ⇒ 序列化字节一致 / 截图 sha256 一致；随机一律走 `Rng` 具名子流 | 各步 `A-` + `s0_6_repro` |
| I-7 | 所有可存档状态必须出现在 `GameState.snapshot()` 的**字段清单**里；漏登记即用例失败 | §4.3 字段清单断言（S1.9） |
| I-8 | 存档：9 槽、无自动存档、覆盖二次确认 | `s0_3_slots` / `s0_3_no_autosave` |
| I-9 | 验收分级 `A-/B-/C-/D-`；`B-` 用 **sha256 逐位一致**；`C-` 必须附「这套量法能测出变贵」的标尺 | `s0_4_cost` 的标尺写法是范本 |
| I-10 | 逻辑层必须是**纯函数**（`RefCounted`/`static`），能在 `--script` 的 headless 下跑；渲染只是它的投影 | 每个 `s1_*` 用例都在 `--script` 模式下跑 |

---

## 3. 分层与目录映射

| 类别 | 位置 | 现有例子 | M1 新增 | 规则 |
|---|---|---|---|---|
| **autoload**（9 个，冻结） | `scripts/core/*.gd` | `GameState` `SceneRouter` `SaveSystem` `Debug`… | 无 | 新增必须改本文 + ROADMAP |
| **纯函数库** | 任意，`class_name` + `RefCounted` + `static` | `MeshUtil` `InputSetup` `UiKit` | `WorldGen` `HeightField` `RoadGraph` `AiDirector` `Calendar` `Canon` | 不持状态、不读场景、可在 headless 跑 |
| **场景根** | `scenes/**` | `main.tscn` | `scenes/world/strategic_map.tscn`、`scenes/dev/diorama.tscn` | 只有一个根脚本；切换只经 `SceneRouter` |
| **场景内节点/控件** | `scripts/world` `scripts/ui` | `terrain.gd` `menu_page.gd` | `strategic_terrain.gd` `strategic_camera.gd` `party_pawn.gd` `settlement_panel.gd` | 只做"投影"与输入，不藏逻辑 |
| **数据表** | `data/**/*.json` | ——（当前无数据层） | `data/world/anchors.json`、`data/economy/*.json`、`data/quests/*.json` | 人读可编辑、进版本库、加载即校验 |
| **文档** | `docs/` | `ROADMAP` `ENGINEERING` `成果` | `WORLD.md`（S1.10）、`BALANCE.md`（S2.11） | 数值表与代码双向可追溯 |

**三条硬规矩**

1. **逻辑不下场景**：AI、生成、经济、寻路都在纯函数库里；场景节点只负责把结果画出来。理由不是洁癖 —— `s1_6_ai_soak` 要跑 10 个游戏日，只能在 headless 里跑。
2. **不碰已验证的渲染路径**：`scripts/world/terrain.gd`、`camera_rig.gd`、`day_night.gd` 是 6 机位基线的承载者。M1 需要相似能力时**新建**脚本（复制公式、不复用节点），不回改它们。
3. **每个新文件先想"它属于哪一层"**；想不清就先别写（这是 §0.2「计划外改动先停」的预防面）。

---

## 4. 数据契约

> 所有契约都以「字段表 + 序列化往返用例」的形式冻结。改字段 = 改 schema 版本 + 写迁移。

### 4.1 `WorldData`（S1.1 产出，内存态是一个 `Dictionary`）

```
WorldData = {
  schema_version: int,          # 与存档 schema 分开编号
  seed: int,
  params: { map_size, region_count, settlement_count:{village,town,fort}, faction_count, party_count },
  regions:    [ { id, name_key, biome, centroid:[x,z], area, neighbors:[id] } ],       # biome ∈ 现有 5 种
  settlements:[ { id, name_key, kind, region_id, faction_id, pos:[x,z], tier, market_id } ],
  roads:      { nodes:[[x,z]…], edges:[ {a,b,len,cost} … ] },                          # a/b 为 nodes 下标
  factions:   [ { id, name_key, color_hex, relation:{faction_id:int}, at_war_with:[id] } ],
  parties:    [ { id, kind, faction_id, pos:[x,z], target:[x,z], state, troops, cargo } ],
  anchors:    [ { id, kind, pos:[x,z], name_key } ],                                   # 来自 anchors.json
}
```

- `kind`：`village|town|fort`；`parties.kind`：`caravan|bandit|patrol|lord`；`state` 见 §6.6。
- **排序即契约**：所有数组在序列化前按 `id`（无 id 按坐标 `[x,z]` 字典序）排序，键按字典序输出 ⇒ 同一内存状态两次序列化**字节相同**（`s1_1_gen` 的判据）。
- 名字**不入档**：只存 `name_key`，真实文案走本地化表（A-7）。这样换语言不改存档。

### 4.2 规范化序列化（`Canon`）

- 新文件 `scripts/core/canon.gd`（`class_name Canon`，纯静态，不占 autoload）。
- 规则：键字典序；浮点 `%.6f`；整数不带小数点；`\n` 行尾；UTF-8 无 BOM；无尾随空白。
- **所有**"确定性比对"与**所有**落盘 JSON 都走它 —— 否则"字节一致"是空话。

### 4.3 存档 = seed + diff（S1.9）

```
{ schema_version: 2, seed, saved_at_game_time,
  base: { params… },                                   # 能重建 WorldData 的最小生成参数
  diff: { date, factions:{...}, settlements:{id:{faction_id}},
          parties:{id:{pos,state,target,troops,cargo}},
          economy:{id:{good:{price,stock}}}, tasks:[…], flags:[…] } }
```

- 为什么不是全量：全量会随生成算法细节膨胀，且"改一个生成参数 ⇒ 全体旧档失效"。seed + diff 让体积与时间线性可控。
- 预算：单槽 < 256KB、读写各 < 150ms（ROADMAP 已定）。
- **字段清单**：`FIELD_MANIFEST`（有序字段数组）随 `GameState`/`WorldData` 一起维护；快照缺项或多项即失败 —— 这是"新增字段忘记存档"的唯一有效拦截（`s1_9_full`）。
- 迁移：`SaveSystem` 已有 `migrations: {source_version → Callable}` 机制（v1 现状可用），S1.9 加 v1→v2 钩子，见 §4.5。

### 4.4 `BattleContext` / `BattleResult`（S1.6 冻结，M2/M4 消费）

```
BattleContext = { version:1, source:"encounter"|"quest"|"story",
  terrain:{ biome, pos:[x,z] }, time:{ game_time, day, hour }, weather:{ kind, intensity },
  attacker:{ party_id, faction_id, troops, hero_id, morale },
  defender:{ …同上 },
  stake:{ loot_money, captives, war_score }, rules:{ kind:"skirmish"|"boss", seed } }

BattleResult = { version:1, winner:"attacker"|"defender", rounds,
  losses:{attacker:int, defender:int}, loot:{money,food,supply}, captives:int,
  flags:[…], placeholder:bool }
```

- S1.6 的占位结算返回 `placeholder:true`；S2.10 换成真实战斗时**字段不变**，只把 `placeholder` 置 false。
- 冻结形式：字段表 + 往返序列化用例（`s1_6_context`）。
- `hero_id` 现在是空串（A-6 单主角固定出身），M3 起接装备。

### 4.5 日历与时间（A-4 的核心）

**换算（1x）**：1 现实秒 = 1 游戏分钟 ⇒ 1 游戏日 = 1440 游戏秒 = 24 现实分钟；1 游戏时 = 60 游戏秒。
**历法**：12 月 × 30 日 = 360 日/年（整除好算，避免月末特例）；`game_time` 单位 = 游戏秒，从 0 起。

```
day   = floor(game_time / 86400) + 1
hour  = floor(game_time / 3600) % 24
month = floor((day-1) / 30) % 12 + 1
year  = floor((day-1) / 360) + 1
```

**变速**：`暂停 / 1x / 2x / 4x` 实现为**每帧执行 N 次固定逻辑步**（N=0/1/2/4），
而不是"放大 delta"。理由是确定性：1x 与 4x 走的是同一条浮点路径，只是步数不同，
于是"4x 跑完 10 日"与"1x 跑完 10 日"的世界状态**逐字段相同**（这条写成 `s1_4_speed` 断言）。
代价是 4x 时 CPU ×4（24 队伍 × 4 = 96 次/帧，微秒级，可接受）。

**`day_length` 语义变更（必须迁移）**
现状：`GameState.day_length = 170.0` 是"一个 24h 昼夜循环 = 170 秒"，且 `hour_index` 由它派生。
新语义：历法由 86400 游戏秒决定，昼夜相位 = `(game_time % 86400) / 86400`。
迁移（schema v1 → v2）：旧档的 `game_time` 是"0..170 的循环相位"，不含日期信息 ⇒
映射为 `day=1, hour=round(game_time / 170 * 24)`，旧值保留到 `visual_day_length` 字段，
读档时给一次性提示「时间已按新历法重标定」。**这条要写进 S1.4 与 S1.9 的验收**。

**`DayNight` 派生**：`day_night.gd` 不改内部曲线，只把输入从"自己的累计值"改为"由 game_time 求出的相位"；
`Clock` 仍负责渲染平滑（它冻结时昼夜也应冻结 —— 这是截图可复现的前提）。

### 4.6 经济与价格（S1.7）

```
data/economy/goods.json = [ { id, name_key, base_price, elasticity, kind:"food"|"supply"|"trade" } ]
market[settlement_id][good_id] = { price: float, stock: int }
price' = clamp(price + (base - price) * k + noise(seed, settlement, good) , base*0.6, base*1.6)
```
守恒：买卖双方 `money` 与 `stock` 的变化必须抵消（`s1_7_trade` 审计断言）。

### 4.7 任务（S1.8）

```
task = { id, template:"suppress"|"escort"|"deliver"|"subjugate", state:"accepted"|"tracking"|"done"|"failed",
         giver_settlement_id, target:{kind,id,pos}, deadline_game_time, reward:{money,food,relation}, progress:int }
```
状态机只许沿 `accepted→tracking→(done|failed)` 单向走；非法迁移记 0 次（穷举断言）。

---

## 5. S1.0 场景与路由迁移（本文建议新增，开工第一件事）

现状：`SceneRouter.SCENES = { world: res://scenes/main.tscn, battle: …battle_stub.tscn }`，
`s0_3_router` 里有逐字比对这条路径的断言（`scene_path_for("world") == "res://scenes/main.tscn"`），
6 机位基线也取自 `main.tscn`。

目标：

```
scenes/world/strategic_map.tscn   ← 新，接管路由 world（S1.2 起才是真正的世界）
scenes/dev/diorama.tscn           ← 由 main.tscn 平移而来（内容逐字节不变）
scenes/main.tscn                  ← 删除（或保留为 world 的临时别名，见下）
```

**四个可独立验收的小步（每步一个提交）**

| 子步 | 动作 | 验收 |
|---|---|---|
| S1.0a | `main.tscn` → `scenes/dev/diorama.tscn`（只改路径引用，场景内容不动） | 6 机位 sha256 **仍逐位等于 §4 基线**（证明搬文件不改像素） |
| S1.0b | `capture.gd` 支持 `--scene=res://…`（默认仍是主场景） | 同参数两次进程截图 sha256 相同；`--scene` 指向 diorama 时得到同一组哈希 |
| S1.0c | `SceneRouter` 路由表加 `strategic`，`world` 暂时仍指 diorama；`strategic_map.tscn` 先放**空场景 + 一个地面平面** | `s0_3_router` 改断言后全绿；新增 `s1_0_routes` 断言新表 |
| S1.0d | `world` 切到 `strategic_map.tscn`，diorama 降为 `dev/diorama`（仅供回归与截图） | 6 机位基线改为 `--scene=dev/diorama` 的**专用批次**（`.shots/diorama_*`）；`s1_0_migration` 断言路由与文件都到位 |

**受影响清单（必须同步改，否则验收会红）**

- `tools/verify.gd`：`_case_router` 中 `scene_path_for("world")` 断言、`_case_slots`/`_case_overwrite` 的 `_load_main()` 目标、`s0_2_baseline` 的取景场景。
- `docs/ENGINEERING.md` §4：6 机位基线的**采集命令**加上 `--scene=dev/diorama`。
- `docs/成果.md`：新增一条"基线已重定向"的记录（保持历史，不改旧条目）。
- 回滚点：任何子步失败即 `git revert`，不要"边修边推进"。

**为什么值得单列一步**：它不产出任何玩法，但它是唯一会同时惊动「路由契约 + 截图基线 + 台账」的改动。
混进 S1.1 会让"数据层写错了"与"场景搬坏了"两种红混在一起，无法定位。

---

## 6. M1 详细规格（S1.1–S1.10）

> 每步格式：**目标 / 交付物 / 实现要点 / 契约 / 验收 / 不做**。
> 验收项除注明外，均沿用 ROADMAP 该步已定的 `A-/B-/C-/D-`，本文只补"怎么实现才验得过"。

### 6.0 执行顺序与批次

| 批 | 内容 | 提交粒度 | 备注 |
|---|---|---|---|
| 0 | S1.0a–d | 4 个提交 | 不含玩法，先落地 |
| 1 | S1.1 | 1 提交 | 纯数据层，无 UI |
| 2 | S1.2（含 `--scene` 复用） | 1–2 提交 | 首个 `B-` 截图步 |
| 3 | S1.3 + S1.4 | 2 提交 | 移动与时间互不依赖，可交换顺序 |
| 4 | S1.5（先扩 `UiKit` 再写面板） | 2 提交 | 本地化 key 从这一步开始 |
| 5 | S1.6 | 1–2 提交 | 冻结 `BattleContext` |
| 6 | S1.7 → S1.8 | 2 提交 | 经济先行，任务消费它 |
| 7 | S1.9 | 1 提交 | 全量存档 + 9 槽复测 |
| 8 | S1.10 | 1 提交 + 文档 | 出口评审 |

---

### 6.1 S1.1 世界数据模型与程序化生成

**目标**：由 seed 生成一份**确定、连通、可读**的世界数据，且不依赖渲染。

**交付物**
- `scripts/world/world_gen.gd`（`class_name WorldGen`，`static generate(seed:int, params:Dictionary) -> Dictionary`）
- `scripts/world/height_field.gd`（`static height_at(x,z,seed) -> float`，战略尺度专用；**不改** `terrain.gd`）
- `data/world/anchors.json`（手工锚点：`{id, kind, pos:[x,z], name_key}`）
- `data/world/gen_params.json`（地图尺寸、region/聚落/势力/队伍数量，集中可调）

**实现要点**
1. **参数初值暂用 ROADMAP 原值**：2400×2400、region 6–9、聚落 12 村 + 4 镇 + 4 要塞、势力 3、AI 队伍 24。
   这些是"能改的数"，唯一约束是 `C-` 生成 < 800ms 与 `C-` 24 队伍下 ≥ 60 FPS。
2. 高度场：`FastNoiseLite` 3 层叠加（大陆/丘陵/细节），**同一函数**供生成与渲染（避免"地图说能走、棋子却穿地"）。
3. 聚落落点：拒绝水面与 `slope > 0.35`；同类聚落之间最小间距（参数化）；落不下就重试 **有上限**（上限内失败 ⇒ 换噪声偏移，不是死循环）。
4. 道路图：先连最近邻生成骨架，再对"孤立分量"补边直到**连通**（`s1_1_gen` 的图连通断言）。
5. 锚点表优先级最高：`anchors.json` 里指定的聚落坐标**直接采用**，生成器只负责周围地形适配。
6. 一切随机走 `Rng` 具名子流（`world_gen`），**禁止**全局 `randf`（守卫会红）。
7. 产出可序列化；`Canon.to_json()` 后两次运行字节相同。

**契约**：`WorldData` 字段表见 §4.1；`gen_params.json` 的键即 `WorldData.params`。

**验收**
- ROADMAP 五项（确定性、换 seed 三项宏观指标、拓扑连通、锚点 100% 生效、生成 < 800ms、3 张 `B-`）+ `s1_1_gen` / `s1_1_variety` 两个用例。
- 本文补：`s1_1_gen` 必须在 `--script` headless 下跑通（I-10）。

**不做**：不做河流/河流寻路、不做多岛屿、不做"文明演化"式生成。

---

### 6.2 S1.2 战略地图场景与镜头

**目标**：把 `WorldData` 画成微缩沙盘，三档缩放可读，且 60 FPS。

**交付物**
- `scenes/world/strategic_map.tscn` + `scripts/world/strategic_map.gd`（场景根）
- `scripts/world/strategic_terrain.gd`（分块生成 + 卸载）
- `scripts/world/strategic_camera.gd`（**新建**，不改 `camera_rig.gd`）

**实现要点**
1. 分块：全球档 8×8 块（每块 300 单位），按镜头距离加载/卸载；近地档对可视区做一次细化。
2. 三角面预算：现有岛屿 219,978 ⇒ 全球档目标 ≤ 352k（1.6 倍），实测写进 §6.2 表格与台账。
3. 三档：全球（正交，覆盖全图）/ 区域（覆盖 ~600）/ 近地（覆盖 ~180，可透视）。切换用**阻尼插值**，禁止瞬切。
4. 相机贴地约束：`cam.y ≥ height_at + 6`；陡坡自动抬升；平移钳制在 `[0,map_size]`。
5. 风格：`Style.toon()` + 逆壳描边；**不得**出现平面方块舞台。
6. `B-` 取景走 S1.0b 的 `--scene=`；三档各一张，另加一张"标注密度最大时刻"（聚落 + 道路 + 24 队伍同屏）。
7. 性能取证：`Performance` 三件套 + `Debug` 的 CSV（S0.4 已具备，`--obs-csv=`），把 24 队伍下的一段 60s 采样存进 `.verify/`。

**验收**：ROADMAP 三项（三档 `B-` 无方块、平移不越界无抖动、面数与 FPS）+ 本文补"24 队伍同屏 FPS ≥ 60"。

**不做**：不做 LOD 降级（那是 S4.3 + §14 Q3 的事）、不做地形破坏。

---

### 6.3 S1.3 队伍棋子与移动

**目标**：一支队伍在图上的移动手感成立（点哪走哪、沿路更快、贴地不穿）。

**交付物**
- `scripts/world/party_pawn.gd`（棋子：`MeshUtil` 小人 + 旗 + 势力色）
- `scripts/world/road_graph.gd`（`static find_path(nodes, edges, from, to) -> PackedInt32Array`）
- `scripts/world/party_mover.gd`（移动状态机：`idle|moving|arrived`）

**实现要点**
1. 寻路用道路图 A*；**tie-break 按节点 id**（不用时间/随机）⇒ 同起终点两次路径逐位相同。
2. 道路段速度 ×1.0、非道路 ×0.65（参数入 `gen_params.json`），并按昼夜/负重预留乘子（M5 接）。
3. 贴地：脚底 = `height_at(x,z)`；法线对齐用 `normal_at` 但限制俯仰角（避免倒挂）。
4. 输入：新增一套战略层 binding（`strategic_select/move/speed_up/speed_down`），与 S0.4 的 `F1/F3` 共存；**不得**复用 `move_forward` 等战斗语义键。
5. 到达判定：距离阈值 + 到时吸附到道路节点（防止"永远差 0.2m"抖动）。

**验收**：ROADMAP 六项（寻路确定性、道路加速 ±5%、贴地 < 0.05m、60s 无抖动、棋子特写 `B-`、`D-` 手感）。

**不做**：不做队伍编队多选（S4.5）、不做行军补给消耗（S1.7 才有粮草）。

---

### 6.4 S1.4 时间与日历系统

**目标**：一个时钟驱动世界，且变速不改变结果。

**交付物**
- `GameState` 扩展：`game_time`（游戏秒，权威）、`speed`（0/1/2/4）、`date` 派生函数 `Calendar.from_seconds()`。
- `scripts/core/calendar.gd`（纯函数：秒 ↔ 年月日时分，见 §4.5）。
- `scripts/world/day_night.gd` 改读 `GameState` 相位（**只改输入来源**，不改曲线）。

**实现要点**
1. 逻辑步：`GameState._physics_process` 内在 1x 时推进 60 游戏秒/秒（= 1 游戏分/现实秒）；2x/4x 每帧执行 2/4 次**完整固定步**。
2. 暂停 = `get_tree().paused`（现有 ESC 契约），`GameState` 默认 `process_mode` 已被暂停挡住 ⇒ 无需额外分支。
3. HUD 时钟：`时:分` + `第 N 日`；确定性模式下 HUD 读数也须可复现（沿用 S0.6 的做法：显示量由 game_time 决定，不由真实帧率决定）。
4. 季节：先只做"月份 → 视觉色调乘子"的接口位，不实现天气。
5. 长时快进测试：`s1_4_speed` 直接构造 `speed=4` 跑 365 日（headless，不需真实 24 分钟）。

**验收**：ROADMAP 四项（60 现实秒 = 60 游戏分、暂停冻结、365 日无漂移、三时刻 `B-`）+ 本文补
`day_length` 迁移（v1→v2）与"4x 与 1x 跑完同 N 日逐字段相同"。

**不做**：不做天气系统、不做节日/事件日历（S1.8 可加）。

---

### 6.5 S1.5 聚落与交互菜单

**目标**：走到聚落能补给、交易、接任务；未开放项诚实标注。

**交付物**
- `scripts/ui/ui_kit.gd` 扩展：`list_row()`、`tabs()`、`scroll_box()`（**先扩控件再写面板**，I-4）
- `scripts/ui/settlement_panel.gd`（沿用 `menu_page.gd` 的 `CanvasLayer` + `_input` 结构，但作为独立面板）
- `data/i18n/strings.csv`（本轮只中文，key 齐全）

**实现要点**
1. 所有文案 `tr("UI_SETTLEMENT_SUPPLY")` 形式；`data/i18n/strings.csv` 一份中文列（A-7）。
2. 面板字段**全部**来自 `WorldData`（价格来自 §4.6 的 market），零硬编码。
3. 势力归属变化 ⇒ 标记颜色 + 可交互权限随之变化（**权限表**：同势力=全开、中立=仅交易、敌对=仅补给或以战代谈）。
4. 未开放项（招募 M5、驻军 S5.5）必须画成"未开放"样式的按钮（灰底 + 明确标签），**不可**隐藏或点了没反应。
5. `D-` 手感目标"≤2 次点击完成补给/交易"：主页 → 补给（1 次点击）。
6. 焦点/键盘：`focus_mode = NONE` 的截图契约不变；键盘导航用显式高亮，不用引擎焦点环。

**验收**：ROADMAP 四项（20 聚落逐字段一致、归属变色与权限、三种面板 `B-`、`D-` 两次点击）+ 本文补"`UiKit` 无新增样式助手"的静态扫描。

**不做**：不做招募/驻军的实际逻辑、不做多语言切换 UI（S6.3）。

---

### 6.6 S1.6 遭遇、AI 队伍与追击

**目标**：24 支队伍会自己跑、会追、会逃、会回城补给，并在接触时给玩家一个"打还是跑"的选择。

**交付物**
- `scripts/world/ai_director.gd`（`static tick(world:Dictionary, dt:float, rng) -> void`，纯函数）
- `data/world/ai_params.json`（视野、速度、遭遇半径、迟滞阈值）
- `scripts/battle/placeholder_resolve.gd`（`static resolve(ctx, rng) -> Dictionary` 返回 `BattleResult`）
- 对峙 UI（复用 `UiKit`）

**状态机（`parties.state`）**：`patrol | chase | flee | resupply | avoid`
- 切换需连续 `N` 步满足条件（迟滞），否则会在边界抖成"抽搐"（ROADMAP 明确点名的风险）。
- `chase` 目标 = 玩家或敌对队伍；`flee` 触发条件 = 兵力比 < 阈值；`resupply` = 粮草 < 阈值且距最近己方聚落 < X。

**实现要点**
1. AI 必须能在 headless 跑 10 游戏日（`s1_6_ai_soak`）⇒ 不碰任何节点/渲染 API。
2. 遭遇判定：`dist < encounter_radius` ⇒ `SceneRouter` 之外不切场景（对峙是 UI 层），玩家选"交战"才进战斗路由。
3. **占位结算**（A-5）：`Rng` 子流 `battle_roll` + 兵力/士气/地形修正 ⇒ `BattleResult{placeholder:true}`；面板顶部固定显示「占位结算 · 真实战斗在 S2.10 接入」。
4. `BattleContext` 打包时机 = 玩家点"交战"那一刻；字段见 §4.4，往返序列化必须一致。
5. 迷雾（A-8）：`explored` 布尔图（分块粒度），未探索区域不画聚落细节、不显示 AI 队伍；进入范围即标记已探索。**不做**视线遮挡。
6. 24 队伍同屏性能：AI 的寻路结果缓存（不必每帧重算），只在目标变化时重算。

**验收**：ROADMAP 五项（10 日 soak 无 NaN + 全在地图内 + 至少 1 次回城与 1 次追击成功、遭遇距离 ±5%、`BattleContext` 往返、`B-` 两张、24 队伍 ≥ 60 FPS）+ 本文补 `s1_6_context`、`s1_6_placeholder`（占位结算确定性：同 seed 两次相同）。

**不做**：不做真实战斗（S2.1）、不做谈判系统（S1.8 只做任务，不做外交博弈）、不做势力外交 AI 主动宣战。

---

### 6.7 S1.7 经济与补给 v1

**目标**：钱粮会花完，价格会波动，且可被 100 日快进验证。

**交付物**：`data/economy/goods.json`、`scripts/world/economy.gd`（纯函数 `static tick(world, day)` + `static trade(...)`）。

**实现要点**
1. 三项资源：`money` 全局；`food`/`supply` 按队伍（`GameState.party` 已有雏形）。
2. 日消耗 = 人数 × 系数（兵种/季节修正）；`food==0` ⇒ 士气惩罚 + 速度下降（乘子入表）。
3. 价格均值回归 + 限幅（§4.6），随机项走 `Rng` 子流 `economy`。
4. 交易守恒：买卖双方 `money`/`stock` 变化抵消（审计断言）。

**验收**：ROADMAP 四项（100 日快进无 NaN/无负溢出、断粮惩罚 ±5%、守恒、`B-` 两图）。

**不做**：不做商队路线经济、不做通胀模型、不做税收。

---

### 6.8 S1.8 事件与任务 v1

**目标**：四类模板任务跑完整生命周期并存得下。

**交付物**：`data/quests/templates.json`、`scripts/world/quests.gd`（纯函数 `static tick(world, dt)`）。

**实现要点**
1. 四类：剿匪 / 护送 / 运送 / 讨伐；生成也走 `Rng` 子流 `quest`（seed 决定论）。
2. 生命周期 `accepted→tracking→done|failed`，非法迁移记 0。
3. 失败条件：超时（`deadline_game_time`）、护送目标死亡。
4. 与遭遇/聚落/资源/声望打通：完成 ⇒ 发奖 + 势力 relation 变化。

**验收**：ROADMAP 四项（四类各跑通一次、两种失败可触发、存档往返一致、`B-` 两图）。

**不做**：不做剧情脚本引擎、不做任务链/前置依赖图（后续里程碑可加）。

---

### 6.9 S1.9 大地图存档/读档完整性

**目标**：读档后世界与存档时刻**逐字段**一致，9 槽互不串档。

**交付物**
- `SaveSystem` schema **v2** + `migrations[1] = _migrate_v1_to_v2`（`day_length` 语义，见 §4.5）
- `GameState.FIELD_MANIFEST` / `WorldData` 字段清单
- 用例 `s1_9_full` / `s1_9_slots9` / `s1_9_offline`（跨进程）

**实现要点**
1. 存档内容 = §4.3 的 `seed + base + diff`；读写走 `Canon`。
2. 读档流程：读 base → 重建 `WorldData`（同 seed + 同 params ⇒ 与存档时刻逐字段相同）→ 应用 diff → 校验字段清单。
3. 9 槽独立性：每个槽写不同进度，逐槽读回比对（`s1_9_slots9`）。
4. 跨进程：写 → 退出进程 → 读（沿用 `s0_3_roundtrip` 的子进程模式，注意陷阱 5/8/9：必须带 `--`、stdout 落文件、透传 `--out=`）。
5. **零自动存档**：与 `s0_3_no_autosave` 同口径复测（文件哈希 + mtime 零变化）。

**验收**：ROADMAP 六项（逐字段一致、10 日续跑一致、旧版可迁移或明确拒绝、体积/耗时、9 槽独立、零自动存档）。

**不做**：不做云同步（Q10 已裁定）、不做槽位删除 UI（S6.3）。

---

### 6.10 S1.10 大地图打磨与验收（M1 出口）

**目标**：战略层能独立试玩 20 分钟不崩、不掉帧、有话可做。

**交付物**
- `docs/WORLD.md`（地图参数、经济初值、AI 行为表 —— 与 `data/**` 逐项对应）
- 三档分辨率 `B-`（1600×900 / 1920×1080 / 2560×1440）
- `s1_10_soak`（20 分钟连续游玩的内存漂移）

**实现要点**
1. 可读性：地标图标、道路描边、势力边界、交战热区；UI 随分辨率缩放（沿用 `canvas_items` stretch）。
2. 内存漂移：分块卸载要真的释放（`queue_free` + 引用置空），用 `Performance.MEMORY_STATIC` 采样。
3. 出口判据（ROADMAP）：FPS ≥ 60 两档、20 分钟内存漂移 < 5%、`D-` 你实机 20 分钟。
4. **M1 出口不等于项目完成**：允许"没有战斗"也闭环（游荡、接任务、赚钱、被追）。

**不做**：不做新手引导（S6.2）、不做设置菜单（S6.3）。

---

## 7. M2–M6 全景摘要

| 里程碑 | 一句话目标 | 关键交付 | 出口判据 | 与前一里程碑的接缝 |
|---|---|---|---|---|
| **M2 Boss 战**（S2.1–S2.11） | 横版 1v1 攻防转换循环：弹反→反击斩 / 闪避→提前蓄力 / 蓄力→剑气与霸体 | `BattleScene` 基类、帧数据内核、弹反/闪避/蓄力三系统、Boss 三阶段 AI、战斗 UI 与结算 | 三路都有正收益；3 场实机（普通/精英/Boss）`D-` 通过；`BALANCE.md` 与 `data/frames/*.json` 双向一致 | 消费 S1.6 的 `BattleContext`，回吐 `BattleResult`（字段已冻结） |
| **M3 装备系统**（S3.1–S3.6） | 装备 → 招式帧表 → 战斗手感 的绑定 | 装备表（武器 24/护甲 18）、属性管线、背包/掉落、强化、装备存档 | 表校验用例全绿；30 组属性管线逐位一致；图标墙 `B-` | 属性加成注入 M2 的伤害公式；`hero_id` 开始有内容 |
| **M4 军团作战**（S4.1–S4.9） | 上帝视角指挥 3–6 小队 × 10–20 人（60–120 单位） | 战场场景、`MultiMesh` 单位架构、群体移动/阵型、指挥层、接敌结算、单挑斩将 | 120 单位 ≥ 60 FPS；无死锁；`D-` 指挥手感 | 消费 S1.3 的棋子数据形状；回吐 `BattleResult`；**描边降级需 Q3 授权** |
| **M5 兵团升级**（S5.1–S5.6） | 兵种树 + 招募/训练 + 带兵上限 + 大地图联动 | 升级树、经验成长、升级 UI、编成/负重/忠诚、驻军补给、存档 | 升级树全路径可达；驻军与补给接进 S1.5/S1.7；存档往返 | 消费 S1.5 的聚落面板与 S1.7 的经济；向 M4 提供兵种 |
| **M6 整合与商用**（S6.1–S6.6） | 把五块拼成一款能卖的游戏 | 完整循环、新手引导、设置/键位/存档管理/本地化、性能回归、内容量产管线、导出验收 | 全流程无阻断；导出构建可跑；性能与稳定性回归 | 收口全部上面四块；发布闸门在这里（`F5/F9` 等调试入口必须彻底关闭） |

**跨里程碑铁律**：阶段顺序 D2 不跳；每块出口都要 `D-` 人工验收（R1：手感不可自动化）。

---

## 8. 跨里程碑接口缝（现在只冻结，不实现）

| 缝 | 生产者 | 消费者 | 冻结时机 | 冻结形式 |
|---|---|---|---|---|
| `BattleContext` v1 | S1.6 | S2.1 / S2.10 / S4.1 | **S1.6** | §4.4 字段表 + `s1_6_context` 往返用例 |
| `BattleResult` v1 | S1.6 占位 / S2.10 真实 / S4.8 | 战略层 | **S1.6** | 同上；`placeholder` 位区分真假 |
| 棋子/队伍数据形状 | S1.3 | S4.2 / S4.7 | S1.3 | `parties` 条目字段表 |
| 属性加成注入点 | S3.2 | S2.3 / S4.6 | S3.2 | `StatModifiers` 字典 + 顺序敏感断言 |
| 驻军/补给接口 | S5.5 | S1.5 / S1.7 | S5.5 | 聚落面板与经济的扩展字段 |
| 本地化 key 表 | S1.5 | S6.3 | S1.5 | `data/i18n/strings.csv`（key 只增不改） |

**冻结的意思**：字段可以**加**（新增可选字段 + 版本号 + 默认值），不可以**改语义**或**删**；改就是一次迁移。

---

## 9. 待合并进 ROADMAP 的条目（开工前置）

> 用户明确要求：**本文不直接改 `ROADMAP.md`**（避免影响正在进行的 S0.4 任务）。
> 下列条目在 M1 开工前合并进 ROADMAP，合并后再动手。

| # | 目标位置 | 要写什么 | 为什么 |
|---|---|---|---|
| M-1 | §6 新增 **S1.0** | 场景与路由迁移（四子步，见 §5）；§15 台账加行；合计步数 54 → 55 | 战略图接管 `world` 会动既有断言与基线，必须独立成步 |
| M-2 | §6 S1.4 | `day_length` 语义变更 + schema v1→v2 迁移要求 | 现状 170s/天与"1 现实秒=1 游戏分"直接冲突 |
| M-3 | §6 S1.9 | 存档 schema v2、`FIELD_MANIFEST` 字段清单机制 | 防"新增字段忘记存" |
| M-4 | §14 | Q4 / Q2 / Q9 标记「✅ 已裁定（2026-10-19）」并写结论 | 三条都卡在 S1.1/S1.5/S1.6 之前 |
| M-5 | §14 新增 Q14 | 地图尺寸/聚落数/势力数/队伍数是否维持 2400×2400 · 20 · 3 · 24 | S1.1 会把这四个数写死进 `gen_params.json` |
| M-6 | §3.4 验收工具链 | `capture.gd` 增加 `--scene=`；`B-` 采集命令更新 | S1.2 起截图不再只取主场景 |
| M-7 | §15 台账 | 新增用例 id：`s1_0_migration` `s1_0_routes` `s1_1_gen` `s1_1_variety` `s1_2_camera` `s1_3_path` `s1_4_speed` `s1_5_settlement` `s1_6_ai_soak` `s1_6_context` `s1_6_placeholder` `s1_7_economy` `s1_8_quests` `s1_9_full` `s1_9_slots9` `s1_9_offline` `s1_10_soak` | 验收要能按 id 取证 |
| M-8 | §16 变更日志 | v1.3 → v1.4：登记本次 8 项裁定与 S1.0 新增 | 保持可追溯 |
| M-9 | §5 S0.4 | 批次 3（`F5`/`F9` + 菜单调试入口）与 `D-` 的最终状态 | 目前是"⏳ 顺延"，收尾时要回填 |

---

## 10. 未决事项与暂定假设

| # | 事项 | 本文暂定 | 影响面 | 最晚确认 |
|---|---|---|---|---|
| Q1 | 美术资产来源（全程序化 / 外包 / 采购） | 默认**全程序化**，不排外包 | M2 Boss 与 M4 单位工作量 | S2.7 前 |
| Q5 | 是否多武器类型 | 默认 **1 套武器 + 3 段普攻**，M3 再扩 | 帧数据量 = 武器数 × 招式数 | S3.4 前 |
| Q6 | Boss 战与军团战是否共用成长 | 默认**共用**（一套等级/装备） | M3 属性管线作用域 | S3.2 前 |
| Q7 | 手柄与完整键位重映射 | 默认**只做键盘 + 可重映射**，手柄留接口 | S6.3 与战斗输入层 | S2.2 前 |
| Q8 | 内容体量基线 | 暂按**主线约 8 小时**：20 聚落 / 3 势力 / 3–5 个 Boss / 4 兵种树 | 聚落数、Boss 数、兵种数量产目标 | S1.10 前 |
| Q11 | 音频资产来源 | 只留接口位，不做正式音频 | S2.8 / S6.1 | S2.8 前 |
| Q12 | 横版是否允许微调纵深（2.7D） | 默认**允许 ±1.5m 纵深演出**，判定仍在 X/Y 平面 | S2.1 镜头与 S2.5 闪避 | S2.1 前 |

**Q8 的说明**：这是唯一会反向影响 M1 参数的一条（20 聚落 / 24 队伍就是按"8 小时主线"估的）。
若你后续把体量改小，先在 `gen_params.json` 调，再看 `s1_1_variety` 与 `s1_10_soak` 是否仍成立。

---

## 11. 变更记录

| 日期 | 版本 | 变更 | 依据 |
|---|---|---|---|
| 2026-10-19 | v0.1 | 首稿：8 项对齐决策、10 条不变式、分层与目录映射、5 类数据契约、S1.0 迁移方案、M1 十步详细规格、M2–M6 摘要、接口缝、待合并清单、未决假设 | 用户要求"M1–M6 全景摘要 + M1 详细"，并就 8 个决策点逐项裁定 |

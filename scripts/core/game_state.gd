extends Node
## GameState — the single source of truth for "what is true about this run".
##
## S0.3 batch 1.  Holds the fields a save file has to round-trip (ROADMAP §5 S0.3):
## the world seed, in-game time, the party reference, the three resources and the
## current scene kind — plus the last known player position, which that step's
## round-trip criterion names explicitly.
##
## WHY NOTHING RENDERS FROM IT YET.  `main.gd` still owns the live `world_seed`
## export and drives the diorama itself (ROADMAP §3.2 "既有文件不重写"); S1.2 splits
## that scene entry point and points it here.  Until then this node is a **field
## holder**: no scene reads it, so introducing it cannot change a single pixel —
## which is exactly what this step's `B-` gate checks (6 camera positions,
## bit-identical against `docs/ENGINEERING.md` §4).
##
## TIME (S1.4a: ONE game clock).  `game_time` is **game seconds** — a monotonic counter
## that only ever grows.  It advances in `_physics_process` on Godot's fixed logical
## step (60 Hz, ROADMAP §3.2) in whole `TICK_GAME_SECONDS` chunks, so after the first
## step the value is an integer and a 365 day fast-forward cannot drift.  This node
## keeps the default `process_mode`, so `get_tree().paused = true` (the ESC menu,
## S0.3 batch 4) stops the game clock: pausing must not let the world drift on behind
## the menu.
##
## THE CALENDAR IS DERIVED, NEVER STORED.  `game_day()` / `month()` / `hour_of_day()` /
## `time_of_day()` are pure functions of `game_time` (1 day = 86400 game seconds,
## 12 × 30 = 360 days per year), so a save only carries the counter and every date
## field recomputes identically.  `DayNight` no longer keeps a phase of its own: it
## reads `time_of_day()` from here (S1.4a retired the second clock that S0.6 had wired
## to `Clock`), which is also why `scripts/core/render_clock.gd` stays render-only.
##
## SPEED (S1.4b) multiplies the **number of ticks per frame**, never the tick size —
## see `TICK_GAME_SECONDS`: that is what makes 4x and 1x land on the same floats.
##
## ⚠️ `tools/verify.gd` runs as a `--script` MainLoop where autoload identifiers do
## not compile; reach this node as `root.get_node("GameState")` there.

## Where the player currently is.  Only `SceneRouter` is allowed to set it
## (ROADMAP §5 S0.3 risk note: "只有 SceneRouter 能切场景").
enum SceneKind { NONE, WORLD, BATTLE }

## Same value as `scripts/core/main.gd`'s `@export var world_seed`, on purpose: when
## S1.2 points the scene entry point at this service, the diorama must generate the
## identical world — otherwise every `B-` baseline hash moves for no real reason.
const DEFAULT_WORLD_SEED := 20250929
## ⚠️ S1.4a legacy.  The pre-S1.4 clock ran one full 24 h loop every 170 s, so saves
## written before this step store a 0..170 **phase** in `game_time` and a matching
## `day_length`.  Nothing reads it any more (a day is `SECONDS_PER_DAY` now); the field
## survives only so v1 saves still round-trip until S1.4c migrates it into
## `visual_day_length`.  Do not add new readers.
const DEFAULT_DAY_LENGTH := 170.0

# --- calendar (S1.4a) ------------------------------------------------------------
## 24 h × 60 min × 60 s of game time per in-game day.
const SECONDS_PER_DAY := 86400.0
const SECONDS_PER_HOUR := 3600.0
const HOURS_PER_DAY := 24
const MINUTES_PER_HOUR := 60
## 12 months × 30 days = 360 days per year, no leap days (§6 S1.4 换算与历法).
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const DAYS_PER_YEAR := DAYS_PER_MONTH * MONTHS_PER_YEAR
## One logical step advances exactly this much game time.  At 1x a 60 Hz frame is
## 1 game second, i.e. 60 game seconds per real second = 1 real second per game
## minute.  Speed multiplies the **number of steps**, so 4x walks the 1x code path
## four times instead of scaling a delta — that is what keeps the results bit-equal.
const TICK_GAME_SECONDS := 1.0
## Game seconds per real second at 1x, spelled out so the two cannot disagree.
const GAME_SECONDS_PER_REAL_SECOND := 60.0

## Exactly the keys `snapshot()` writes.  `restore()` uses the same list to report
## unknown keys, so the writer and the validator cannot drift apart.
const SNAPSHOT_FIELDS := [
	"world_seed", "game_time", "day_length", "party",
	"money", "food", "supply", "scene_kind", "player_pos", "playtime",
]

# --- saved fields: every one of these round-trips through SaveSystem ----------
var world_seed := DEFAULT_WORLD_SEED
## Total in-game seconds since the run started (see the TIME note at the top).
var game_time := 0.0
## Legacy (see `DEFAULT_DAY_LENGTH`): only ever written back to a v1 save verbatim.
var day_length := DEFAULT_DAY_LENGTH
## The player's army.  S1.x replaces this dictionary with a real party object.
var party := {"name": "无名军团", "level": 1}
var money := 0
var food := 0
var supply := 0
## One of `SceneKind`.
var scene_kind := SceneKind.NONE
## Last known player world position; the world keeps it fresh from S1.2 on.
var player_pos := Vector3.ZERO
## Real seconds spent in this run.  Advances with `game_time`, so it also stops
## while the tree is paused.
var playtime := 0.0

## Last in-game hour announced on `EventBus.time_advanced`.  -1 forces the first
## announcement ("day 1, 00:00") on the very first logical step.
var _last_hour_tick := -1
## Sub-tick remainder of the real-time delta.  A frame contributes 0.9999 or 1.0001
## game seconds depending on float rounding; carrying the remainder keeps the
## **average** rate at exactly `GAME_SECONDS_PER_REAL_SECOND` in both cases.
var _tick_residual := 0.0


func _ready() -> void:
	# Root the random streams at this run's seed.  `Rng` is registered before
	# `GameState` in project.godot for exactly this call; `s0_3_state` asserts that
	# order, because a silent reorder would leave the streams on their own default.
	Rng.seed_from(world_seed)


func _physics_process(delta: float) -> void:
	# Real seconds: `playtime` is what the save card shows and it must not grow with
	# the speed setting (S1.4b), so it takes the raw delta while `game_time` takes
	# whole ticks.  The two are deliberately separate numbers.
	playtime += delta
	_tick_residual += delta * GAME_SECONDS_PER_REAL_SECOND
	while _tick_residual >= TICK_GAME_SECONDS:
		_tick_residual -= TICK_GAME_SECONDS
		_advance_one_tick()


## One logical step.  Kept separate from the loop above so S1.4b can call it N times
## per frame without touching the accumulator, and so a test can drive it directly.
func _advance_one_tick() -> void:
	game_time += TICK_GAME_SECONDS
	# One announcement per in-game hour.  Announcing every tick would put 60 signals/s
	# on the bus to say nothing new.
	var hour_index := hour_of_day()
	if hour_index != _last_hour_tick:
		_last_hour_tick = hour_index
		EventBus.time_advanced.emit(game_day(), time_of_day())


## 1-based in-game day; day 1 starts at `game_time == 0`.
func game_day() -> int:
	return int(game_time / SECONDS_PER_DAY) + 1


## 1-based day inside the year (1..360).
func day_of_year() -> int:
	return (game_day() - 1) % DAYS_PER_YEAR + 1


## 1-based year; each one is exactly `DAYS_PER_YEAR` game days long.
func year_of_run() -> int:
	return int((game_day() - 1) / DAYS_PER_YEAR) + 1


## 1-based month (1..12), 30 days each.
func month() -> int:
	return int((day_of_year() - 1) / DAYS_PER_MONTH) + 1


## 1-based day of the month (1..30).
func day_of_month() -> int:
	return (day_of_year() - 1) % DAYS_PER_MONTH + 1


## 0..23
func hour_of_day() -> int:
	return int(fmod(game_time, SECONDS_PER_DAY) / SECONDS_PER_HOUR)


## 0..59
func minute_of_day() -> int:
	return int(fmod(game_time, SECONDS_PER_HOUR) / 60.0)


## 0..59
func second_of_day() -> int:
	return int(fmod(game_time, 60.0))


## 0.0..1.0 through the day, 0 = midnight — the `DayNight.time_of_day` convention.
## Pure function of `game_time`: same counter in, same phase out (S1.4 `A-` 唯一时钟).
func time_of_day() -> float:
	return fmod(game_time, SECONDS_PER_DAY) / SECONDS_PER_DAY


## Every derived date field at once — the shape the HUD, the save card and the tests
## share, so none of them can invent a fifth way to spell a date.
func time_parts() -> Dictionary:
	return {
		"year": year_of_run(), "month": month(), "day": day_of_month(),
		"day_of_year": day_of_year(), "day_index": game_day(),
		"hour": hour_of_day(), "minute": minute_of_day(), "second": second_of_day(),
	}


## "第 N 天 HH:MM" — what the §3.5 save-slot card shows.
func clock_text() -> String:
	return "第 %d 天 %02d:%02d" % [game_day(), hour_of_day(), minute_of_day()]


## "第 Y 年 M 月 D 日 HH:MM" — the full calendar form.
func date_text() -> String:
	return "第 %d 年 %d 月 %d 日 %02d:%02d" % [
		year_of_run(), month(), day_of_month(), hour_of_day(), minute_of_day(),
	]


## A save may only carry a finite, non-negative counter; S1.4c rejects everything
## else instead of deriving a nonsense date from it.
func is_valid_time(t: float) -> bool:
	return is_finite(t) and t >= 0.0


## Starts a fresh run.  The seed is a **parameter**, never drawn here: S0.3 gives
## `Rng` no entropy source on purpose (see `scripts/core/rng.gd`), so the
## new-game flow (S1.x, main menu) picks it and passes it down.  `Rng` is re-rooted
## from it so world generation and gameplay share one reproducible root.
func new_game(p_world_seed: int) -> void:
	world_seed = p_world_seed
	game_time = 0.0
	playtime = 0.0
	day_length = DEFAULT_DAY_LENGTH
	party = {"name": "无名军团", "level": 1}
	money = 0
	food = 0
	supply = 0
	scene_kind = SceneKind.NONE
	player_pos = Vector3.ZERO
	_tick_residual = 0.0
	_last_hour_tick = -1
	Rng.seed_from(p_world_seed)


## JSON-safe copy of every saved field.  `Vector3` is written as `[x, y, z]` because
## `JSON.stringify()` cannot encode engine math types; `restore()` accepts that
## array and a `{x, y, z}` dictionary alike, so a hand-edited save still loads.
func snapshot() -> Dictionary:
	return {
		"world_seed": world_seed,
		"game_time": game_time,
		"day_length": day_length,
		"party": party.duplicate(true),
		"money": money,
		"food": food,
		"supply": supply,
		"scene_kind": scene_kind,
		"player_pos": [player_pos.x, player_pos.y, player_pos.z],
		"playtime": playtime,
	}


## Applies a snapshot.  Never throws and never half-applies in silence: a field
## that is missing or ill-typed keeps its current value and is named in the returned
## warnings, and a key this build does not know is reported rather than dropped
## quietly (a save written by a newer build must be visible, not mysterious).
## `SaveSystem` relays these warnings to the player — §5 S0.3 `s0_3_dirty`.
func restore(d: Dictionary) -> PackedStringArray:
	var warn := PackedStringArray()
	for key in d.keys():
		if not SNAPSHOT_FIELDS.has(String(key)):
			warn.append("未知字段 `%s`：已忽略" % String(key))
	for field in SNAPSHOT_FIELDS:
		if not d.has(field):
			warn.append("字段缺失 `%s`：保留当前值" % field)

	world_seed = _take_int(d, "world_seed", warn, world_seed)
	game_time = _take_float(d, "game_time", warn, game_time)
	day_length = _take_float(d, "day_length", warn, day_length)
	playtime = _take_float(d, "playtime", warn, playtime)
	money = _take_int(d, "money", warn, money)
	food = _take_int(d, "food", warn, food)
	supply = _take_int(d, "supply", warn, supply)
	scene_kind = _take_int(d, "scene_kind", warn, scene_kind)
	party = _take_party(d, "party", warn, party)
	player_pos = _take_pos(d, "player_pos", warn, player_pos)
	return warn


## Called by `SceneRouter` only (ROADMAP §5 S0.3: "只有 `SceneRouter` 能切场景").
func set_scene_kind(k: int) -> void:
	scene_kind = k


func scene_kind_name() -> String:
	var names := ["NONE", "WORLD", "BATTLE"]
	if scene_kind < 0 or scene_kind >= names.size():
		return "?"
	return names[scene_kind]


# --- field coercion helpers --------------------------------------------------
# Each returns the current value unchanged and appends exactly one warning when the
# incoming value is unusable, so `restore()` can never leave a field in limbo.

func _take_int(d: Dictionary, field: String, warn: PackedStringArray, fallback: int) -> int:
	if not d.has(field):
		return fallback
	var v: Variant = d[field]
	if typeof(v) == TYPE_INT:
		return v
	# JSON writers disagree on whether `3` or `3.0` means an integer, so accept an
	# integral float — but reject 3.5 rather than truncating it behind the author's back.
	if typeof(v) == TYPE_FLOAT and float(v) == floorf(float(v)):
		return int(v)
	warn.append(_type_warn(field, "int", v))
	return fallback


func _take_float(d: Dictionary, field: String, warn: PackedStringArray, fallback: float) -> float:
	if not d.has(field):
		return fallback
	var v: Variant = d[field]
	if typeof(v) == TYPE_FLOAT:
		return v
	if typeof(v) == TYPE_INT:
		return float(v)
	warn.append(_type_warn(field, "float", v))
	return fallback


func _take_party(d: Dictionary, field: String, warn: PackedStringArray, fallback: Dictionary) -> Dictionary:
	if not d.has(field):
		return fallback
	var v: Variant = d[field]
	if typeof(v) == TYPE_DICTIONARY and not (v as Dictionary).is_empty():
		# Deep copy: an incoming save must never alias the caller's dictionary.
		return (v as Dictionary).duplicate(true)
	warn.append(_type_warn(field, "非空 Dictionary", v))
	return fallback


func _take_pos(d: Dictionary, field: String, warn: PackedStringArray, fallback: Vector3) -> Vector3:
	if not d.has(field):
		return fallback
	var v: Variant = d[field]
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v
		if a.size() == 3 and _is_number(a[0]) and _is_number(a[1]) and _is_number(a[2]):
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
	elif typeof(v) == TYPE_DICTIONARY:
		var dd: Dictionary = v
		if dd.has("x") and dd.has("y") and dd.has("z") \
				and _is_number(dd["x"]) and _is_number(dd["y"]) and _is_number(dd["z"]):
			return Vector3(float(dd["x"]), float(dd["y"]), float(dd["z"]))
	warn.append(_type_warn(field, "Vector3（[x,y,z] 或 {x,y,z}）", v))
	return fallback


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _type_warn(field: String, expect: String, got: Variant) -> String:
	return "字段 `%s` 类型错误：期望 %s，实际 %s（值 %s）——保留当前值" % [
		field, expect, type_string(typeof(got)), str(got).substr(0, 48),
	]
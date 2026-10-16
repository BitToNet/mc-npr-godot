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
## TIME.  `game_time` advances in `_physics_process`, i.e. on Godot's fixed logical
## step (60 Hz, ROADMAP §3.2) — frame-rate independent and reproducible, unlike a
## `_process` accumulation.  This node keeps the default `process_mode`, so
## `get_tree().paused = true` (the ESC menu, S0.3 batch 4) stops the game clock:
## pausing must not let the world drift on behind the menu.
##
## ⚠️ `DayNight.time_of_day` is still a clock of its own (S0.6 wired it to `Clock`).
## The two are deliberately NOT joined yet — S1.4 unifies the calendar.  Until then
## `game_time` is authoritative for the save file and `DayNight` for the sky, and
## the duplicated `day_length` below is the visible symptom of that split.
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
## Mirrors `scripts/world/day_night.gd`'s `day_length` (one full 24 h loop).
const DEFAULT_DAY_LENGTH := 170.0
const HOURS_PER_DAY := 24

## Exactly the keys `snapshot()` writes.  `restore()` uses the same list to report
## unknown keys, so the writer and the validator cannot drift apart.
const SNAPSHOT_FIELDS := [
	"world_seed", "game_time", "day_length", "party",
	"money", "food", "supply", "scene_kind", "player_pos", "playtime",
]

# --- saved fields: every one of these round-trips through SaveSystem ----------
var world_seed := DEFAULT_WORLD_SEED
## Total in-game seconds since the run started.
var game_time := 0.0
## Seconds in one in-game day.
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


func _ready() -> void:
	# Root the random streams at this run's seed.  `Rng` is registered before
	# `GameState` in project.godot for exactly this call; `s0_3_state` asserts that
	# order, because a silent reorder would leave the streams on their own default.
	Rng.seed_from(world_seed)


func _physics_process(delta: float) -> void:
	game_time += delta
	playtime += delta
	# One announcement per in-game hour.  Announcing every logical step would put
	# 60 signals/s on the bus to say nothing new.
	var hour_index := int(game_time / maxf(day_length, 1.0) * float(HOURS_PER_DAY))
	if hour_index != _last_hour_tick:
		_last_hour_tick = hour_index
		EventBus.time_advanced.emit(game_day(), time_of_day())


## 1-based in-game day; day 1 starts at `game_time == 0`.
func game_day() -> int:
	return int(game_time / maxf(day_length, 1.0)) + 1


## 0.0..1.0 through the day, 0 = midnight — the `DayNight.time_of_day` convention.
func time_of_day() -> float:
	var span := maxf(day_length, 1.0)
	return fmod(game_time, span) / span


## "第 N 天 HH:MM" — what the §3.5 save-slot card shows.
func clock_text() -> String:
	var minutes := int(time_of_day() * float(HOURS_PER_DAY) * 60.0)
	return "第 %d 天 %02d:%02d" % [game_day(), minutes / 60, minutes % 60]


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
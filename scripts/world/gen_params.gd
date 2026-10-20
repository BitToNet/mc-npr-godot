class_name GenParams
extends RefCounted
## World-generation parameter table (`data/world/gen_params.json`, S1.1a).
##
## Why a table instead of constants: `docs/ROADMAP.md` §6 Q14 ruled that the map
## numbers (2400×2400 / 20 settlements / 3 factions / 24 AI parties) are **data
## initial values** — changing them must be a table edit + a re-run of the
## generation cases, never a code change. The code keeps only the *safe ranges*
## and the built-in defaults below (used when the table is missing or broken).
##
## Contract (`docs/ENGINEERING.md` §9.2):
##   * out-of-range values are clamped into the safe range, never fatal;
##   * type errors fall back to the built-in default for that field only;
##   * unknown keys and missing keys are reported, not silently accepted;
##   * a `schema` higher than this build is refused as a whole (forward compat);
##   * every deviation is reported through `warnings` — this file never logs, so
##     the caller decides whether to surface it (same split as `SaveSystem`).
##
## The table itself is kept in canonical form: `Canon.canonicalize(file)["text"]`
## must reproduce the file byte-for-byte (`s1_1_params` asserts exactly that), so
## a hand edit that breaks the format is caught instead of ignored.

const PATH := "res://data/world/gen_params.json"
const SCHEMA := 1

## Built-in defaults. Changing these requires the same-batch edits of
## `data/world/gen_params.json`, `docs/ROADMAP.md` §6 S1.1 and §16.
const DEFAULTS := {
	"map_size": 2400,
	"regions_min": 6,
	"regions_max": 9,
	"villages": 12,
	"towns": 4,
	"fortresses": 4,
	"factions": 3,
	"ai_parties": 24,
	"water_level": 0.0,
	"base_height": -18.0,
	"hill_amplitude": 120.0,
	"detail_amplitude": 8.0,
}

## Fields measured in metres, not counts.  They are kept separate because the
## integer gate must not round them: `hill_amplitude = 120.4` is a legitimate
## value, and silently snapping it to 120 would make the terrain not match the
## table.  `Canon` still writes an integral float as `120` (JSON has no int/float
## distinction), so the table reads back as `120.0` — stable, but worth knowing
## before you edit it by hand.
const FLOAT_FIELDS := ["water_level", "base_height", "hill_amplitude", "detail_amplitude"]

## Safe ranges (ROADMAP §6 Q14: 600–4000 / 4–12 / 8–40 / 2–5 / 4–40).
## Settlement counts are also bounded *in total* by `SETTLEMENTS_RANGE`.
## Height ranges are wide on purpose: they are art knobs, and the failure mode of a
## too-narrow band is "clamped without anyone noticing".
const RANGES := {
	"map_size": [600, 4000],
	"regions_min": [4, 12],
	"regions_max": [4, 12],
	"villages": [0, 40],
	"towns": [0, 40],
	"fortresses": [0, 40],
	"factions": [2, 5],
	"ai_parties": [4, 40],
	"water_level": [-60.0, 60.0],
	"base_height": [-120.0, 40.0],
	"hill_amplitude": [40.0, 300.0],
	"detail_amplitude": [0.0, 30.0],
}
const SETTLEMENTS_RANGE := [8, 40]


## A fresh copy of the built-in defaults (callers may mutate their copy).
static func defaults() -> Dictionary:
	return DEFAULTS.duplicate()


## Read + validate the real table. `{ok, params, warnings, used_defaults, reason, path}`.
## `ok` is false only when the table as a whole was unusable (missing file, bad
## JSON, forward `schema`, non-object root) — clamping and per-field fallbacks
## keep `ok` true and show up in `warnings`.
static func load_from(path: String = PATH) -> Dictionary:
	var out: Dictionary
	if not FileAccess.file_exists(path):
		out = _fallback("参数表不存在：%s" % path)
	else:
		var text := FileAccess.get_file_as_string(path)
		if text.strip_edges().is_empty():
			out = _fallback("参数表为空或不可读：%s" % path)
		else:
			var parsed := Canon.from_text(text)
			if not bool(parsed["ok"]):
				out = _fallback("参数表不是合法 JSON：%s" % String(parsed["reason"]))
			else:
				out = validate(parsed["value"])
	out["path"] = path
	return out


## Pure validation of an already-parsed table (no file access, no logging).
static func validate(raw: Variant) -> Dictionary:
	var warnings := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		warnings.append("参数表根必须是对象（实际 `%s`）：全部取内置默认值" % type_string(typeof(raw)))
		return _result(DEFAULTS.duplicate(), warnings, true, "根不是对象")

	var table: Dictionary = raw

	# --- schema -------------------------------------------------------------
	if not table.has("schema"):
		warnings.append("缺少 `schema` 字段：按当前版本 %d 读取" % SCHEMA)
	elif not Canon.is_integral(table["schema"]):
		warnings.append("`schema` 不是整数（实际 `%s`）：按当前版本 %d 读取"
				% [type_string(typeof(table["schema"])), SCHEMA])
	elif int(table["schema"]) > SCHEMA:
		warnings.append("`schema` = %d 高于本构建支持的 %d：整表回退内置默认值"
				% [int(table["schema"]), SCHEMA])
		return _result(DEFAULTS.duplicate(), warnings, true,
				"schema 版本过高（表 %d > 本构建 %d）" % [int(table["schema"]), SCHEMA])
	elif int(table["schema"]) < SCHEMA:
		warnings.append("`schema` = %d 低于当前 %d：按当前版本读取（暂无迁移钩子）"
				% [int(table["schema"]), SCHEMA])

	var params := DEFAULTS.duplicate()

	# --- per-field: type → integral → clamp ---------------------------------
	for key in DEFAULTS.keys():
		var field := String(key)
		if not table.has(field):
			warnings.append("缺少字段 `%s`：取默认值 %s" % [field, str(DEFAULTS[key])])
			continue
		var value: Variant = table[field]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			warnings.append("字段 `%s` 类型错误（实际 `%s`，值 %s）：取默认值 %s"
					% [field, type_string(typeof(value)), str(value), str(DEFAULTS[key])])
			continue
		var number := float(value)
		if not is_finite(number):
			warnings.append("字段 `%s` 是非有限数（%s）：取默认值 %s"
					% [field, str(value), str(DEFAULTS[key])])
			continue
		var bounds: Array = RANGES[field]
		if FLOAT_FIELDS.has(field):
			var flow := float(bounds[0])
			var fhigh := float(bounds[1])
			if number < flow or number > fhigh:
				var fclamped := clampf(number, flow, fhigh)
				warnings.append("字段 `%s` = %s 超出安全区间 [%s, %s]：钳制为 %s"
						% [field, str(number), str(flow), str(fhigh), str(fclamped)])
				number = fclamped
			params[field] = number
			continue
		var rounded := int(roundf(number))
		if absf(number - roundf(number)) > 0.0001:
			warnings.append("字段 `%s` 不是整数（%s）：四舍五入为 %d" % [field, str(value), rounded])
		var low := int(bounds[0])
		var high := int(bounds[1])
		if rounded < low or rounded > high:
			var clamped := clampi(rounded, low, high)
			warnings.append("字段 `%s` = %d 超出安全区间 [%d, %d]：钳制为 %d"
					% [field, rounded, low, high, clamped])
			rounded = clamped
		params[field] = rounded

	# --- region ordering ----------------------------------------------------
	if int(params["regions_min"]) > int(params["regions_max"]):
		warnings.append("`regions_min`(%d) > `regions_max`(%d)：把 `regions_max` 抬到 `regions_min`"
				% [int(params["regions_min"]), int(params["regions_max"])])
		params["regions_max"] = params["regions_min"]

	# --- unknown keys -------------------------------------------------------
	var unknown: Array = []
	for key in table.keys():
		var field := String(key)
		if field == "schema" or DEFAULTS.has(field):
			continue
		unknown.append(field)
	unknown.sort()
	for field in unknown:
		warnings.append("未知字段 `%s`：忽略（检查是否拼错）" % String(field))

	# --- settlement total ---------------------------------------------------
	_balance_settlements(params, warnings)

	return _result(params, warnings, false, "")


## Keep villages + towns + fortresses within `SETTLEMENTS_RANGE`.
## Over the cap: trim villages first, then towns, then fortresses (villages are
## the bulk and the least structural). Under the cap: top villages up.
static func _balance_settlements(params: Dictionary, warnings: PackedStringArray) -> void:
	var total := int(params["villages"]) + int(params["towns"]) + int(params["fortresses"])
	var low := int(SETTLEMENTS_RANGE[0])
	var high := int(SETTLEMENTS_RANGE[1])
	if total > high:
		var over := total - high
		for field in ["villages", "towns", "fortresses"]:
			if over <= 0:
				break
			var available := int(params[field])
			var take := mini(available, over)
			if take <= 0:
				continue
			params[field] = available - take
			over -= take
			warnings.append("聚落总数 %d > %d：从 `%s` 减 %d" % [total, high, String(field), take])
	elif total < low:
		var deficit := low - total
		params["villages"] = int(params["villages"]) + deficit
		warnings.append("聚落总数 %d < %d：给 `villages` 补 %d" % [total, low, deficit])


static func _fallback(reason: String) -> Dictionary:
	return _result(DEFAULTS.duplicate(), PackedStringArray([reason]), true, reason)


static func _result(params: Dictionary, warnings: PackedStringArray,
		used_defaults: bool, reason: String) -> Dictionary:
	return {
		"ok": not used_defaults,
		"params": params,
		"warnings": warnings,
		"used_defaults": used_defaults,
		"reason": reason,
	}

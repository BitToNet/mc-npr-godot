extends Node
## SaveSystem — the only code in this project that reads or writes `user://saves/`.
##
## S0.3 batch 2 (ROADMAP §5 S0.3, contract in §3.5).  Nine fixed slots, one JSON
## file each, no cloud, **no autosave**: this node writes a file only when
## `save_slot()` / `save_current()` is called explicitly.  It has no `_process`,
## subscribes to no `EventBus` signal, and does not touch the disk in `_ready`
## (there is no `_ready` at all) — the directory is created lazily by the first
## save.  `s0_3_no_autosave` tests that claim by hashing the whole directory
## before and after a full boot + world rebuild, so "it happens not to write
## today" cannot pass silently: it also asserts the same check *detects* an
## explicit save.
##
## FILE LAYOUT
## ```json
## { "schema_version": 1,
##   "saved_at": "2026-10-16 16:20:00",  "saved_at_unix": 1760600000,
##   "meta": { ...card fields for the 3x3 grid: day, clock, party, playtime... },
##   "game": { ...exactly GameState.snapshot()... } }
## ```
## `meta` exists so the slot grid can render a card **without** loading a world,
## and `game` is applied through `GameState.restore()`, which owns field
## validation.  One writer list, one validator list: `SNAPSHOT_FIELDS`.
##
## WHY THE REAL WALL CLOCK IS ALLOWED HERE.  `saved_at` is a fact about the real
## world, not a game-time source: nothing renders it during a screenshot, and
## freezing it would make the grid show "1 second ago" for every save.  This is
## the one sanctioned `Time.get_*` family in the project — S0.6 banned the
## animation clock, not timestamps.
##
## ATOMIC WRITE, MEASURED — INCLUDING ITS LIMIT (ROADMAP §5 S0.3 pre-registered
## trap 2).  A single-process probe on this machine (Godot 4.7 / Windows) first
## looked like it settled the question: `DirAccess.rename_absolute(tmp, target)` over
## an existing, *not open* target returned OK, replaced the content, and left no
## `.tmp`; the same call returned err=1 while a reader held the target open, leaving
## the old content untouched.
##
## The cross-process `s0_3_atomic` case then showed what an end-state probe cannot:
## the engine's replace is **not atomic on Windows**.  While a child process wrote the
## same slot 800 times, a polling parent took ~170-190 samples per run; in every run a
## slice of them found the slot file absent (17, then 28 in a second run) and another
## slice found it present but unreadable (22, then 25) — i.e. the engine removes the
## target and then renames, and for a few microseconds the slot cannot be read.  **Not
## one sample was ever half-written**: every readable sample (131, then 140) was
## complete, valid JSON with the expected fields, which is exactly the property the
## acceptance wording demands.
##
## Consequences, all measured rather than assumed:
##   1. Writer: write `.tmp` -> read it back and compare -> rename over the slot with
##      a bounded retry (losing a race with an open reader is transient).  On final
##      failure the old save is intact, the `.tmp` is removed, and the caller gets
##      `ok=false` with a reason.
##   2. Reader: a bounded retry too, because the writer *cannot* offer atomicity here.
##      `_read_slot_text()` therefore tolerates both "the name blinked out" and "the
##      name is there but the file is delete-pending", using a sibling `.tmp` to tell a
##      publish in flight from a genuinely empty slot (which returns at once, so an
##      empty 3x3 grid pays no delay).  Measured effect on the same storm: concurrent
##      reads that failed went 42 -> 0.
##   3. `rename_absolute` also moves directories (target must not exist) — used by the
##      test harness for slot isolation, not by this service.
##
## ⚠️ `tools/verify.gd` runs as a `--script` MainLoop where autoload identifiers do
## not compile; reach this node as `root.get_node("SaveSystem")` there.

const SAVE_DIR := "user://saves"
## Slot numbers are 1-based and fixed: the 3x3 grid in §3.5 shows exactly these.
const SLOT_COUNT := 9
const SLOT_PREFIX := "slot_"
const SLOT_EXT := ".json"
const TMP_SUFFIX := ".tmp"

## First (and for now only) format this project ever wrote.  Bump only together
## with a `migrations` entry that can bring the previous version forward.
const SCHEMA_VERSION := 1

## Retry budget for the measured "target is open, rename fails" race (measured with
## the batch-2 probe: a read handle on the target makes `rename` return `Failed` and
## leaves the old file untouched).  20 x 3 ms is far longer than any real
## open/read/close window and still invisible to a player.
const RENAME_RETRIES := 20
const RENAME_RETRY_MS := 3

## Reader-side retry budget, mirroring the writer's: the measured gap between the
## engine's remove and its rename is microseconds, so 20 x 3 ms is generous headroom.
## It is only ever paid when a save is being replaced underneath the reader.
const READ_RETRIES := 20
const READ_RETRY_MS := 3

## Migration hooks: `source schema version -> Callable(Dictionary) -> Dictionary`.
## Empty by default because v1 is the first format that exists, so there is nothing
## to migrate *from* yet; a file claiming a version with no hook is refused with a
## reason naming that version — never silently reinterpreted.  It is a `var`, not a
## `const`, so the chain is reachable in tests (a const Dictionary is read-only in
## GDScript, which would make the loop below untestable dead code).
var migrations := {}

## The slot the in-game menu last wrote or read; 0 = none.  Per §3.5, "保存" with
## no current slot behaves as "另存为": the caller must ask for a slot first.
var current_slot := 0

## Newest failure reason, for a debug overlay (S0.4) that does not want to listen.
var last_error := ""

## A slot file was published.  Past tense per ROADMAP §3.2: this bus-local signal
## reports a fact, it never asks the listener to approve anything.
signal save_written(slot: int, path: String)
## A save was refused or failed; the previous file, if any, is untouched.
signal save_failed(slot: int, reason: String)
## A save file could not be read or was structurally unusable.
signal load_failed(slot: int, reason: String)
## A save file was read and applied to `GameState`.
signal slot_loaded(slot: int)


## --- paths and queries --------------------------------------------------------

func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


func slot_path(slot: int) -> String:
	return SAVE_DIR.path_join("%s%d%s" % [SLOT_PREFIX, slot, SLOT_EXT])


func slot_exists(slot: int) -> bool:
	return is_valid_slot(slot) and FileAccess.file_exists(slot_path(slot))


## Remembers which slot "保存" targets.  Returns false for an invalid slot.
func select_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		last_error = "槽位号 %d 非法（合法范围 1..%d）" % [slot, SLOT_COUNT]
		return false
	current_slot = slot
	return true


## Slot card data for the 3x3 grid (§3.5).  Pure read: it never applies anything
## to `GameState`, so opening the menu cannot disturb a running game.  An
## unreadable file reports `exists=false` with `label` = 损坏的存档 rather than
## pretending to be empty; `load_slot()` gives the precise reason.
func slot_info(slot: int) -> Dictionary:
	var info := {
		"slot": slot, "exists": false, "label": "空槽位", "path": slot_path(slot),
		"saved_at": "", "saved_at_unix": 0, "schema_version": 0,
		"game_day": 0, "clock_text": "", "party_name": "", "party_level": 0,
		"playtime": 0.0, "playtime_text": "", "world_seed": 0,
	}
	if not is_valid_slot(slot):
		info["label"] = "非法槽位"
		return info
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return info
	var d := _read_dict(path)
	if d.is_empty():
		info["label"] = "损坏的存档"
		return info
	var meta_v: Variant = d.get("meta", {})
	var meta: Dictionary = meta_v if typeof(meta_v) == TYPE_DICTIONARY else {}
	info["exists"] = true
	info["schema_version"] = int(d.get("schema_version", 0))
	info["saved_at"] = String(d.get("saved_at", ""))
	info["saved_at_unix"] = int(d.get("saved_at_unix", 0))
	info["game_day"] = int(meta.get("game_day", 0))
	info["clock_text"] = String(meta.get("clock_text", ""))
	info["party_name"] = String(meta.get("party_name", ""))
	info["party_level"] = int(meta.get("party_level", 0))
	info["playtime"] = float(meta.get("playtime", 0.0))
	info["playtime_text"] = String(meta.get("playtime_text", format_playtime(info["playtime"])))
	info["world_seed"] = int(meta.get("world_seed", 0))
	info["label"] = "%s · %s · Lv%d · %s" % [
		info["clock_text"], info["party_name"], info["party_level"], info["playtime_text"],
	]
	return info


## All nine slots in order, ready for the grid to render.
func list_slots() -> Array:
	var out: Array = []
	for slot in range(1, SLOT_COUNT + 1):
		out.append(slot_info(slot))
	return out


## "HH:MM:SS" for the accumulated playtime shown on a slot card.
func format_playtime(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


## --- saving -------------------------------------------------------------------

## Writes `GameState.snapshot()` into `slot`.
##
## `overwrite` is the second confirmation, expressed as data rather than as a
## dialog: with the default `false` an occupied slot is **refused** and the existing
## file is not touched, and the result carries `requires_confirm=true` so the
## S0.3 batch 4 menu knows to ask.  Only an explicit `true` publishes over a save.
func save_slot(slot: int, overwrite: bool = false) -> Dictionary:
	if not is_valid_slot(slot):
		return _fail(slot, "槽位号 %d 非法（合法范围 1..%d）" % [slot, SLOT_COUNT])
	var path := slot_path(slot)
	if FileAccess.file_exists(path) and not overwrite:
		return _fail(slot, "槽位 %d 已有存档（%s）；覆盖需二次确认" % [
			slot, String(slot_info(slot).get("saved_at", "?")),
		], true)
	var text := JSON.stringify(_build_payload(slot), "  ", false)
	var written := _atomic_write(path, text)
	if not written["ok"]:
		return _fail(slot, String(written["reason"]))
	current_slot = slot
	last_error = ""
	save_written.emit(slot, path)
	return {
		"ok": true, "slot": slot, "path": path, "reason": "", "warnings": PackedStringArray(),
		"requires_confirm": false, "bytes": text.length(),
	}


## "保存" per §3.5: writes the current slot, or asks for one when there is none.
func save_current(overwrite: bool = false) -> Dictionary:
	if current_slot == 0:
		return _fail(0, "当前没有选中槽位：保存等同『另存为』，请先选择槽位", true)
	return save_slot(current_slot, overwrite)


## --- loading ------------------------------------------------------------------

## Reads `slot` and applies it through `GameState.restore()`.
##
## Two failure classes, deliberately kept apart: a file that cannot be *used*
## (unreadable, not a JSON object, unreadable schema version, no `game` section)
## returns `ok=false` with a reason and changes nothing; a file that is usable but
## dirty (missing/unknown/mistyped fields) returns `ok=true` and hands every
## complaint back in `warnings`.  Neither path may crash the game, which is the
## acceptance wording.
func load_slot(slot: int) -> Dictionary:
	if not is_valid_slot(slot):
		return _load_fail(slot, "槽位号 %d 非法（合法范围 1..%d）" % [slot, SLOT_COUNT])
	var path := slot_path(slot)
	var text := _read_slot_text(path)
	if text.strip_edges() == "":
		if not FileAccess.file_exists(path):
			return _load_fail(slot, "槽位 %d 是空槽位：不存在可读取的存档" % slot)
		return _load_fail(slot, "槽位 %d 的存档读不出内容（0 字节，或正被另一个进程改写）" % slot)
	var parsed: Variant = _parse_json_text(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _load_fail(slot, "槽位 %d 的存档不是合法 JSON 对象（解析结果 %s）" % [
			slot, type_string(typeof(parsed)),
		])
	var d: Dictionary = parsed
	var warnings := PackedStringArray()

	var version := SCHEMA_VERSION
	if not d.has("schema_version"):
		warnings.append("缺少 schema_version：按当前版本 %d 读取" % SCHEMA_VERSION)
	elif not _is_int_like(d["schema_version"]):
		warnings.append("schema_version 类型错误（%s，值 %s）：按当前版本 %d 读取" % [
			type_string(typeof(d["schema_version"])), str(d["schema_version"]).substr(0, 24), SCHEMA_VERSION,
		])
	else:
		version = int(d["schema_version"])

	if version > SCHEMA_VERSION:
		return _load_fail(slot, "存档 schema_version = %d 高于本构建支持的 %d：拒绝读取（存档来自更新的版本）" % [
			version, SCHEMA_VERSION,
		])
	var hops := 0
	while version < SCHEMA_VERSION:
		if not migrations.has(version):
			return _load_fail(slot, "存档 schema_version = %d 无迁移路径（已注册来源版本：%s）：拒绝读取" % [
				version, str(migrations.keys()),
			])
		var hook: Callable = migrations[version]
		var migrated: Variant = hook.call(d)
		if typeof(migrated) != TYPE_DICTIONARY:
			return _load_fail(slot, "schema v%d -> v%d 的迁移钩子未返回字典：拒绝读取" % [
				version, version + 1,
			])
		d = migrated
		version = int(d.get("schema_version", version + 1))
		hops += 1
		if hops > 16:
			return _load_fail(slot, "迁移链超过 16 跳（疑似循环）：拒绝读取")

	var game_v: Variant = d.get("game", null)
	if typeof(game_v) != TYPE_DICTIONARY:
		return _load_fail(slot, "存档缺少 game 段或类型错误（%s）：拒绝读取" % type_string(typeof(game_v)))
	warnings.append_array(GameState.restore(game_v))

	current_slot = slot
	last_error = ""
	slot_loaded.emit(slot)
	var meta_v: Variant = d.get("meta", {})
	return {
		"ok": true, "slot": slot, "path": path, "reason": "",
		"warnings": warnings, "requires_confirm": false,
		"meta": meta_v if typeof(meta_v) == TYPE_DICTIONARY else {},
		"schema_version": version,
	}


## --- internals ----------------------------------------------------------------

## The exact bytes a slot file will hold.  `meta` is derived from the same snapshot
## that goes into `game`, so a card can never disagree with the save it describes.
func _build_payload(slot: int) -> Dictionary:
	var game: Dictionary = GameState.snapshot()
	var party_v: Variant = game.get("party", {})
	var party: Dictionary = party_v if typeof(party_v) == TYPE_DICTIONARY else {}
	var playtime := float(game.get("playtime", 0.0))
	return {
		"schema_version": SCHEMA_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"meta": {
			"slot": slot,
			"game_day": GameState.game_day(),
			"clock_text": GameState.clock_text(),
			"party_name": String(party.get("name", "")),
			"party_level": int(party.get("level", 0)),
			"playtime": playtime,
			"playtime_text": format_playtime(playtime),
			"world_seed": int(game.get("world_seed", 0)),
		},
		"game": game,
	}


## Publish `text` as the whole content of `path`, or leave the previous file alone.
##
## Three steps, each of which the probe above justified: write a sibling `.tmp`,
## read it back and compare (a short write is caught *before* it can become the
## slot), then rename it over the slot with a bounded retry (rename-over-existing
## works, but loses a race with a reader).
func _atomic_write(path: String, text: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var tmp := path + TMP_SUFFIX
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "reason": "无法创建临时文件 %s（%s）" % [
			tmp, error_string(FileAccess.get_open_error()),
		]}
	f.store_string(text)
	f.flush()
	f.close()
	var written := FileAccess.get_file_as_string(tmp)
	if written != text:
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "reason": "临时文件写回校验失败（落盘 %d 字符，期望 %d 字符）" % [
			written.length(), text.length(),
		]}
	var err := OK
	for _attempt in RENAME_RETRIES:
		err = DirAccess.rename_absolute(tmp, path)
		if err == OK:
			return {"ok": true, "reason": ""}
		OS.delay_msec(RENAME_RETRY_MS)
	DirAccess.remove_absolute(tmp)
	return {"ok": false, "reason": "覆盖 %s 失败（%s，已重试 %d 次）：原存档保持不变" % [
		path, error_string(err), RENAME_RETRIES,
	]}


func _read_dict(path: String) -> Dictionary:
	var parsed: Variant = _parse_json_text(_read_slot_text(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## A slot's text, tolerating the measured non-atomic replace window above.
##
## The window has two shapes, both seen in `s0_3_atomic`'s samples: the name is
## briefly *absent* (the engine removed the target and has not renamed yet), or the
## name is there but the file is *delete-pending* and cannot be opened.  A writer in
## the middle of a publish is also leaving its `.tmp` behind, so that `.tmp` is the
## discriminator: a name that was never there **and** has no sibling `.tmp` is a
## genuinely empty slot and must return immediately (rendering an empty 3x3 grid must
## not pay nine read timeouts), while an absence next to a live `.tmp` is a publish in
## flight and is retried.
## Returns "" once the budget is spent; the caller reports that as a failed read.
func _read_slot_text(path: String) -> String:
	var writer_active := FileAccess.file_exists(path + TMP_SUFFIX)
	for _attempt in READ_RETRIES:
		if FileAccess.file_exists(path):
			var text := FileAccess.get_file_as_string(path)
			if text.strip_edges() != "":
				return text
			writer_active = true
		elif not writer_active:
			return ""
		OS.delay_msec(READ_RETRY_MS)
	return ""


## 解析可能损坏的文本，失败时**保持安静**。
##
## 刻意不用 `JSON.parse_string()`：它在解析失败时会打出引擎级的
## `ERROR: Parse JSON failed...`。坏存档是本服务的正常输入（玩家能改、磁盘能坏），
## 它有自己的报告通道——返回值里的 reason 和 `load_failed` 信号——不该顺手污染
## `--headless` 日志，那会掩盖真正的错误（第 0 条工程纪律：日志里的 ERROR 必须有意义）。
func _parse_json_text(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


func _is_int_like(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f := float(v)
		return f == floorf(f) and not is_nan(f) and not is_inf(f)
	return false


func _fail(slot: int, reason: String, requires_confirm: bool = false) -> Dictionary:
	last_error = reason
	save_failed.emit(slot, reason)
	return {
		"ok": false, "slot": slot, "path": slot_path(slot) if is_valid_slot(slot) else "",
		"reason": reason, "warnings": PackedStringArray(),
		"requires_confirm": requires_confirm, "bytes": 0,
	}


func _load_fail(slot: int, reason: String) -> Dictionary:
	last_error = reason
	load_failed.emit(slot, reason)
	return {
		"ok": false, "slot": slot, "path": slot_path(slot) if is_valid_slot(slot) else "",
		"reason": reason, "warnings": PackedStringArray(),
		"requires_confirm": false, "schema_version": 0, "meta": {},
	}
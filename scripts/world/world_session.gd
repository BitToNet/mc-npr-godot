class_name WorldSession
extends RefCounted

## One assembled world: height field + region partition + world data, built from a
## single seed in one fixed order.
##
## WHY THIS CLASS EXISTS (S1.2a).  `HeightField`, `WorldRegions` and `WorldData`
## each take the generator they are handed and start drawing **wherever that
## generator happens to be**.  So "same seed, same world" only holds if the caller
## also pins the stream's *entry state*: draw one extra number before building and
## the world changes while the seed stays the same.  That is not hypothetical —
## S1.1d measured 24 road edges in an isolated run and 26 in a full-suite run for
## the same seed (`docs/ENGINEERING.md` §9.8.5, §5 trap 26).  This class is that
## missing caller: it reseeds the injected `Rng` from the seed **before** drawing
## anything, and it is the single place that decides the build order.
##
## INJECTED, NOT FETCHED.  `boot()` takes the `Rng` node as a parameter instead of
## reaching for the autoload.  Two reasons: `tools/verify.gd` runs as a `--script`
## MainLoop where autoload identifiers do not compile, and a test that cannot
## inject the generator also cannot prove that the reseed happened.
##
## NOT AN AUTOLOAD.  `RefCounted` with `class_name` — the project is at 9 / 10
## autoloads and the strategic map owns exactly one session, so there is nothing
## for a global singleton to hold.

## Sub-stream world generation draws from.  One name, one sequence — the same name
## must be used by every caller, otherwise two worlds interleave on one stream.
const STREAM_NAME := "world_gen"

## Build stages, in the only order that is correct: terrain first (region picking
## reads heights), then the partition (settlement placement reads regions), then
## the world (roads and parties read both).
const STAGE_ORDER := ["field", "regions", "data"]

var world_seed: int
var params: Dictionary
var field: HeightField
var regions: WorldRegions
var data: WorldData
var anchors: Array = []
## Union of the warnings produced by the parameter table, the anchor table, the
## region partition and the world build — in that order, duplicates preserved.
## Empty is the healthy case; a non-empty list means something degraded (never
## that the world failed to exist).
var warnings := PackedStringArray()
## Reasons the world could not be assembled at all (`ok == false`).  Empty when
## `ok` is true.
var errors := PackedStringArray()
var ok := false


## Builds one world from `p_seed_value` and returns it.
##
## `p_rng` is the `Rng` autoload (or any node exposing `seed_from(int)` and
## `stream(String) -> RandomNumberGenerator`); `tests` inject the real one.
## An empty `p_params` loads `data/world/gen_params.json`; an empty `p_anchors_path`
## loads `data/world/anchors.json`.  Passing explicit `p_params` is what lets a
## caller (and the verify cases) exercise degraded tables without touching disk.
static func boot(p_rng: Node, p_seed_value: int,
		p_params: Dictionary = {}, p_params_path: String = GenParams.PATH,
		p_anchors_path: String = WorldData.PATH) -> WorldSession:
	var session := WorldSession.new()
	session.world_seed = p_seed_value

	var table := Dictionary(p_params)
	if table.is_empty():
		var loaded := GenParams.load_from(p_params_path)
		table = Dictionary(loaded["params"])
		for w in loaded.get("warnings", []):
			session.warnings.append(String(w))
		if not bool(loaded.get("ok", false)):
			session.errors.append("参数表不可用：%s" % String(loaded.get("reason", "未知原因")))
			return session
	session.params = table

	# THE PRECONDITION.  `seed_from()` drops every existing stream, so the next
	# `stream(STREAM_NAME)` is derived from this seed alone — no history, no
	# leftover state from whatever drew before us.  Doing it here (instead of
	# trusting every future caller) is what makes the seed the *only* input.
	if p_rng != null and p_rng.has_method("seed_from"):
		p_rng.call("seed_from", p_seed_value)
	var stream: RandomNumberGenerator = null
	if p_rng != null and p_rng.has_method("stream"):
		stream = p_rng.call("stream", STREAM_NAME) as RandomNumberGenerator
	if stream == null:
		session.errors.append("拿不到随机子流（Rng 未注入或缺少 stream()）")
		return session

	var anchor_table := WorldData.load_anchors(p_anchors_path)
	for w in anchor_table.get("warnings", []):
		session.warnings.append(String(w))
	if not bool(anchor_table.get("ok", false)):
		# A missing anchor table only costs the hand-placed seats, not the world:
		# `WorldData` falls back to generated placements, so this is a warning.
		session.warnings.append("锚点表不可用：%s" % String(anchor_table.get("reason", "未知原因")))
	else:
		session.anchors = Array(anchor_table["anchors"])

	session.field = HeightField.new(p_seed_value, table)
	session.regions = WorldRegions.new(session.field, stream, table)
	var region_result := session.regions.build()
	for w in region_result.get("warnings", []):
		session.warnings.append(String(w))
	if not bool(region_result.get("ok", false)):
		session.errors.append("region 划分失败：一个 region 都没落下")
		return session

	session.data = WorldData.new(p_seed_value, table, session.field,
			session.regions, stream, session.anchors)
	var world_result := session.data.build()
	for w in world_result.get("warnings", []):
		session.warnings.append(String(w))
	if not bool(world_result.get("ok", false)):
		session.errors.append("世界生成失败：%s" % String(world_result.get("reason", "未知原因")))
		return session

	session.ok = true
	return session


# --- read-only views --------------------------------------------------------

## Macro indicators, straight from the world data (see `WorldData.metrics()`).
func metrics() -> Dictionary:
	if data == null:
		return {}
	return data.metrics()


## Canonical text of the world, for "same seed, same bytes" checks.
func to_text() -> Dictionary:
	if data == null:
		return {"ok": false, "text": "", "reason": "世界尚未生成"}
	return data.to_text()


## Territory size in metres (square map).
func map_size() -> float:
	return float(params.get("map_size", 2400))


## Number of regions in the partition.
func region_count() -> int:
	if regions == null:
		return 0
	return regions.regions.size()


## Human-readable one-liner for logs / the debug overlay.
func summary_text() -> String:
	if not ok:
		return "世界生成失败：%s" % "; ".join(errors)
	return "seed %d · %d 个 region · %d 个聚落 · %d 条道路 · %d 支队伍 · %d 条告警" % [
		world_seed, region_count(), data.settlements.size(), data.roads.size(),
		data.parties.size(), warnings.size()]

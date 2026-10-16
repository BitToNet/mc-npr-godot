extends Node
## Rng — the only sanctioned source of randomness in this project.
##
## ROADMAP §3.2: "所有随机走 Rng 服务（按 seed 派生子流），禁止裸 randf()（verify
## 静态检查）".  The guard in `tools/verify.gd` enforces the second half.
##
## WHY SUB-STREAMS, NOT ONE GENERATOR.  A single shared generator makes randomness
## order-dependent: if terrain generation draws one extra number, every later draw
## shifts, and "same seed, same result" quietly stops holding.  Here each subsystem
## asks for its **own named stream** — `Rng.stream("terrain")` — whose seed depends
## only on the master seed and the name.  The terrain stream therefore yields the
## same sequence no matter what the scatter, cloud, battle or loot code did first.
##
## DERIVATION.  FNV-1a (32-bit) over the UTF-8 bytes of the stream name, XORed with
## the master seed.  Deliberately not Godot's builtin `hash()`: FNV-1a is spelled
## out in full below, so a stream seed can never change because the engine changed
## its string hashing — which would silently move every `B-` baseline.
##
## NO ENTROPY SOURCE ON PURPOSE.  S0.3 does not hand this service a clock or
## `randomize()`: a "new game" seed is passed in explicitly by the caller (the
## main-menu / new-game flow, S1.x) and reaches here through
## `GameState.new_game()`.  Reading a wall clock for a seed would be an
## unfreezable time source — exactly what S0.6 banned.
##
## ⚠️ `tools/verify.gd` runs as a `--script` MainLoop where autoload identifiers do
## not compile; reach this node as `root.get_node("Rng")` there.

const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619
const MASK32 := 0xFFFFFFFF
## Stream seeds must stay positive; `RandomNumberGenerator.seed` is an int but a
## negative seed is a needless edge case to reason about.
const SEED_MASK := 0x7FFFFFFF

## Same value as `GameState.DEFAULT_WORLD_SEED`, so an unwired boot reproduces the
## diorama exactly as it is before S0.3.
const DEFAULT_MASTER_SEED := 20250929

## Master seed every stream is derived from.  `seed_from()` replaces it.
var master_seed := DEFAULT_MASTER_SEED

## stream name -> RandomNumberGenerator
var _streams := {}


## Sets the master seed and drops every existing stream, so the next `stream()`
## call rebuilds from scratch.  Reproducibility contract: the same master seed plus
## the same stream name always yields the same sequence.
func seed_from(p_seed: int) -> void:
	master_seed = p_seed
	_streams.clear()


## Derived seed for one stream name.  A pure function of `(master_seed, name)`,
## exposed so the derivation itself is testable without drawing any numbers.
func stream_seed(name: String) -> int:
	return (master_seed ^ _fnv1a(name)) & SEED_MASK


## Returns the named stream, creating it on first use.  The same name always maps
## to the same generator, so repeated calls do not restart the sequence.
func stream(name: String) -> RandomNumberGenerator:
	if _streams.has(name):
		return _streams[name]
	var gen := RandomNumberGenerator.new()
	gen.seed = stream_seed(name)
	_streams[name] = gen
	return gen


## Re-seeds every stream created so far without forgetting it — the state a fresh
## `seed_from()` plus the same sequence of `stream()` calls would have produced.
func reset() -> void:
	for name in _streams.keys():
		(_streams[name] as RandomNumberGenerator).seed = stream_seed(String(name))


## Names of the streams created so far (diagnostics; the S0.4 debug layer shows it).
func stream_names() -> PackedStringArray:
	return PackedStringArray(_streams.keys())


## Convenience wrappers so call sites read as `Rng.randf_in("loot", 0.0, 1.0)`
## instead of reaching three levels into a generator.
func randf_in(name: String, lo: float, hi: float) -> float:
	return stream(name).randf_range(lo, hi)


func randi_in(name: String, lo: int, hi: int) -> int:
	return stream(name).randi_range(lo, hi)


## FNV-1a over the UTF-8 bytes.  32-bit arithmetic is kept by masking after every
## step, so this is identical on any platform and in any engine version.
func _fnv1a(s: String) -> int:
	var h := FNV_OFFSET
	for byte in s.to_utf8_buffer():
		h = (h ^ int(byte)) & MASK32
		h = (h * FNV_PRIME) & MASK32
	return h
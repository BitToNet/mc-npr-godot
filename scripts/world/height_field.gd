class_name HeightField
extends RefCounted
## HeightField — the strategic-scale height / biome field (S1.1b).
##
## One square map (default 2400 m, see `data/world/gen_params.json`), sampled by
## pure functions of `(world_seed, params, x, z)`.  The generator (S1.1c), the
## renderer (S1.2) and the settlement placer all call the **same** `height_at()`,
## so a town can never float above the ground it stands on — this shared field is
## the whole reason the step exists (ROADMAP §6 S1.1: 与渲染共用同一个 `height_at`).
##
## WHY A NEW FILE INSTEAD OF `terrain.gd`.  `terrain.gd` is the diorama island and
## the carrier of the six-camera `B-` baseline (`docs/ENGINEERING.md` §4).  Its
## constants are tuned for a 63 m tile with 12.6 m of relief; the strategic map is
## 2400 m wide with ~120 m of relief.  Reusing it would mean either breaking that
## baseline or bending one set of constants to two scales, so the *shape* of the
## code is copied and every number is not (ROADMAP §6 S1.1: 复制而非继承).
##
## NO RANDOMNESS IN HERE.  Every noise seed is derived arithmetically from
## `world_seed`, and all frequencies are expressed in "cycles across the map", so
## sampling order cannot influence the result and `2400` needs no magic constant.
## Anything that genuinely needs randomness (region centres, later settlement
## jitter) takes an `Rng` substream explicitly — see `regions.gd`.
##
## UNITS.  `height_at()` returns **world metres** on the same axis as the rendered
## surface (sea level is `water_level`, default 0).  `normalized_height_at()`
## rescales that to 0..1 above sea level for shading / biome decisions, so a
## palette threshold does not have to know `hill_amplitude`.

# --- shape constants (deliberately not gameplay numbers) --------------------
## Superellipse exponent of the island footprint: 2 would be an ellipse, higher
## values square it off.  3.0 keeps a readable landmass whose edges are not a
## mathematical rectangle.
const ISLAND_POWER := 3.0
## How far the coastline may wander, in units of the normalised radius.
const COAST_WOBBLE := 0.14
## Normalised radius where land is still whole / where it has fully drowned.
const COAST_IN := 0.70
const COAST_OUT := 1.10
## How far the sea floor drops below `base_height`, in units of `hill_amplitude`.
const SHELF_DROP := 0.45
## Conservative upper bound of the relief term (`relief` in `height_at`).
const RELIEF_CEILING := 1.30
## Finite-difference probe distance for `slope_at`, in world metres.  Small enough
## to describe a hillside, large enough not to measure single noise cells.
const SLOPE_STEP := 8.0

# --- biome thresholds ------------------------------------------------------
const BIOME_WATER := "water"
const BIOME_BEACH := "beach"
const BIOME_GRASS := "grass"
const BIOME_FOREST := "forest"
const BIOME_HIGHLAND := "highland"
const BIOME_SNOW := "snow"
## Every value `biome_at()` may return.  Exposed so callers can assert membership
## instead of re-spelling the list.
const BIOMES := [
	BIOME_WATER, BIOME_BEACH, BIOME_GRASS, BIOME_FOREST, BIOME_HIGHLAND, BIOME_SNOW,
]
const LAND_BIOMES := [BIOME_BEACH, BIOME_GRASS, BIOME_FOREST, BIOME_HIGHLAND, BIOME_SNOW]

## Normalised height bounds between beach / highland / snow.
const BEACH_TOP := 0.045
const HIGHLAND_BOTTOM := 0.48
const SNOW_BOTTOM := 0.70
## Slope (rise over run, world units) above which a hillside reads as bare rock.
const ROCK_SLOPE := 0.30
## Moisture above which grassland becomes forest.
const FOREST_MOISTURE := 0.60

# --- state ------------------------------------------------------------------
var world_seed := 0
var params := {}
var map_size := 2400.0
var half_size := 1200.0
var water_level := 0.0
var base_height := -18.0
var hill_amplitude := 120.0
var detail_amplitude := 8.0
## Highest height this parameter set can reach; the denominator of
## `normalized_height_at()`.  Computed, never hand-tuned, so it cannot drift away
## from `height_at()` when a param changes.
var max_height := 0.0

var _n_coast: FastNoiseLite
var _n_base: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_moisture: FastNoiseLite


## `p_params` is a *validated* parameter table (see `GenParams.validate()`); this
## class does not clamp or warn, because by the time the world is generated the
## table has already been through that gate exactly once.
func _init(p_seed_value: int, p_params: Dictionary) -> void:
	world_seed = p_seed_value
	params = p_params
	map_size = float(p_params.get("map_size", 2400))
	half_size = map_size * 0.5
	water_level = float(p_params.get("water_level", 0.0))
	base_height = float(p_params.get("base_height", -18.0))
	hill_amplitude = float(p_params.get("hill_amplitude", 120.0))
	detail_amplitude = float(p_params.get("detail_amplitude", 8.0))
	max_height = base_height + hill_amplitude * RELIEF_CEILING + detail_amplitude
	_setup_noise()


# ---------------------------------------------------------------------------
# noise
# ---------------------------------------------------------------------------
## Frequencies are "cycles across the map", so changing `map_size` rescales the
## terrain instead of changing how many hills fit in it.
func _cycles(c: float) -> float:
	return c / map_size


func _make_noise(p_seed: int, p_freq: float, p_octaves: int, p_type: int, p_gain: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = p_freq
	n.fractal_type = p_type
	n.fractal_octaves = p_octaves
	n.fractal_lacunarity = 2.03
	n.fractal_gain = p_gain
	return n


func _setup_noise() -> void:
	# Offsets are spelled out rather than hashed so a seed is reproducible across
	# engines and platforms (same reasoning as `Rng`'s hand-written FNV-1a).
	_n_coast = _make_noise(world_seed, _cycles(3.0), 2, FastNoiseLite.FRACTAL_FBM, 0.5)
	_n_base = _make_noise(world_seed + 977, _cycles(4.0), 5, FastNoiseLite.FRACTAL_FBM, 0.48)
	_n_ridge = _make_noise(world_seed + 4241, _cycles(7.0), 5, FastNoiseLite.FRACTAL_RIDGED, 0.52)
	_n_detail = _make_noise(world_seed + 7331, _cycles(60.0), 3, FastNoiseLite.FRACTAL_FBM, 0.5)
	_n_moisture = _make_noise(world_seed + 1699, _cycles(5.0), 3, FastNoiseLite.FRACTAL_FBM, 0.5)


# ---------------------------------------------------------------------------
# height
# ---------------------------------------------------------------------------
## Normalised radius: 0 at the middle, 1 where the land runs out.  The squared
## superellipse plus a low-frequency wobble gives a coastline that meanders
## instead of tracing a rounded rectangle.
func _radius(x: float, z: float) -> float:
	var nx := x / (half_size * 0.96)
	var nz := z / (half_size * 0.96)
	var d := pow(pow(absf(nx), ISLAND_POWER) + pow(absf(nz), ISLAND_POWER), 1.0 / ISLAND_POWER)
	return d + _n_coast.get_noise_2d(x, z) * COAST_WOBBLE


## World-space height in metres.  Monotone in `hill_amplitude` and
## `detail_amplitude` by construction, which is what makes "the params really do
## drive the terrain" testable instead of a matter of trust.
func height_at(x: float, z: float) -> float:
	var d := _radius(x, z)
	var mask := clampf(1.0 - smoothstep(COAST_IN, COAST_OUT, d), 0.0, 1.0)
	var inner := smoothstep(0.02, 0.88, mask)
	var ridge_amt := smoothstep(0.30, 0.95, mask)
	var macro := _n_base.get_noise_2d(x, z) * 0.5 + 0.5
	var ridge := pow(_n_ridge.get_noise_2d(x, z) * 0.5 + 0.5, 1.4)
	var detail := _n_detail.get_noise_2d(x, z)
	# A soft central summit gives the island a readable silhouette from above
	# (S1.2's camera looks straight down most of the time).
	var peak := smoothstep(0.80, 0.10, d) * 0.28
	var relief := macro * 0.58 + ridge * 0.42 * ridge_amt + peak * inner
	var land := relief * inner
	var sea := (1.0 - inner) * SHELF_DROP
	return base_height + (land - sea) * hill_amplitude + detail * detail_amplitude


## Height rescaled to 0..1 above sea level (0 for anything at or below the water
## line).  Shading and biome rules use this so they stay valid when
## `hill_amplitude` changes.
func normalized_height_at(x: float, z: float) -> float:
	var span := max_height - water_level
	if span <= 0.0:
		return 0.0
	return clampf((height_at(x, z) - water_level) / span, 0.0, 1.0)


## Rise over run (dimensionless), measured with a central difference.  This is the
## quantity S1.1's settlement rules compare against 0.35, so it is reported in
## world units and not normalised away.
func slope_at(x: float, z: float) -> float:
	var dx := (height_at(x + SLOPE_STEP, z) - height_at(x - SLOPE_STEP, z)) / (2.0 * SLOPE_STEP)
	var dz := (height_at(x, z + SLOPE_STEP) - height_at(x, z - SLOPE_STEP)) / (2.0 * SLOPE_STEP)
	return sqrt(dx * dx + dz * dz)


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) <= water_level


## 0..1, independent of height: drives forest vs grassland.
func moisture_at(x: float, z: float) -> float:
	return _n_moisture.get_noise_2d(x, z) * 0.5 + 0.5


## One of `BIOMES`.  Order matters: water and beach win over slope, because a
## cliff plunging into the sea is still coast.
func biome_at(x: float, z: float) -> String:
	var h := height_at(x, z)
	if h <= water_level:
		return BIOME_WATER
	var span := max_height - water_level
	var n := 0.0 if span <= 0.0 else (h - water_level) / span
	if n < BEACH_TOP:
		return BIOME_BEACH
	if n > SNOW_BOTTOM:
		return BIOME_SNOW
	if n > HIGHLAND_BOTTOM or slope_at(x, z) > ROCK_SLOPE:
		return BIOME_HIGHLAND
	if moisture_at(x, z) > FOREST_MOISTURE:
		return BIOME_FOREST
	return BIOME_GRASS


# ---------------------------------------------------------------------------
# sampling helpers
# ---------------------------------------------------------------------------
## Flat `[x, z, height]` triples over a square grid of `p_step` metres, centred on
## the map.  Used by the acceptance case and later by the region builder, so the
## grid convention — cell centres at `-half + step/2` — is written once.
func sample_heights(p_step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if p_step <= 0.0:
		return out
	var n := int(floor(map_size / p_step))
	var start := -half_size + p_step * 0.5
	for iz in n:
		var z := start + float(iz) * p_step
		for ix in n:
			var x := start + float(ix) * p_step
			out.append(x)
			out.append(z)
			out.append(height_at(x, z))
	return out


## Number of grid samples `sample_heights()` yields per side.
func sample_count(p_step: float) -> int:
	if p_step <= 0.0:
		return 0
	return int(floor(map_size / p_step))

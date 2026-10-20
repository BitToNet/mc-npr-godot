class_name WorldRegions
extends RefCounted
## WorldRegions — the coarse region partition of the strategic map (S1.1b).
##
## Regions are Voronoi cells around a handful of land centres: every land cell
## belongs to exactly one region, every water cell to none.  They are the unit the
## map is *talked about* in ("the north-west highlands"), and later the unit that
## ownership and supply are aggregated over (S1.7), so two properties matter more
## than the exact shapes: **no holes** (a land cell can never be ownerless) and
## **conservation** (the areas must add up to the land, not to the whole square).
##
## WHERE THE RANDOMNESS COMES FROM.  Centre placement needs randomness, so it takes
## an explicit `RandomNumberGenerator` — in the game that is `Rng.stream("world_gen")`,
## in `tools/verify.gd` it is reached as `root.get_node("Rng").stream(...)` because
## autoload identifiers do not compile in `--script` mode.  Passing the generator in
## (instead of reading an autoload) also makes "same seed, same regions" provable
## without a SceneTree.
##
## DETERMINISM.  The only inputs are `(field, stream state, params)`, and the stream
## is consumed in a fixed order, so the same seed always yields the same centres,
## the same grid and the same areas.

## Side of one assignment cell, in metres.  32 m keeps the partition fine enough to
## follow a coastline (the map is 75 cells across) while staying cheap: 5 625 cells
## against at most 9 centres is ~50 k distance tests.
const CELL := 32.0
## Upper bound on draws per centre when rejecting water / crowded candidates.
const CENTER_TRIES := 400
## Centres live inside this fraction of the map, so a region's centre is never in
## the sea margin where its own cells cannot reach.
const CENTER_MARGIN := 0.86
## Minimum centre spacing, in units of `map_size / (count * SPACING_FACTOR)`.
const SPACING_FACTOR := 1.7
## Land clearance above the water line a centre must have, in metres.
const LAND_CLEARANCE := 4.0
## Second pass spacing multiplier when the first pass cannot place every centre.
const RELAX := 0.55

var field: HeightField
var stream: RandomNumberGenerator
var params := {}
var map_size := 2400.0
var half_size := 1200.0
var cell := CELL
var grid_w := 0
var grid_h := 0
## `grid_w * grid_h` entries; `-1` means water (belongs to no region).
var owner := PackedInt32Array()
var regions: Array[Dictionary] = []
var warnings := PackedStringArray()
## Land cells seen by the last `build()`; water cells are the remainder.
var _land_cells := 0


func _init(p_field: HeightField, p_stream: RandomNumberGenerator, p_params: Dictionary) -> void:
	field = p_field
	stream = p_stream
	params = p_params
	map_size = float(p_params.get("map_size", 2400))
	half_size = map_size * 0.5


## Builds the partition.  Returns a summary dictionary so callers never have to
## read this object's fields to find out whether the build was sane.
func build() -> Dictionary:
	regions.clear()
	warnings.clear()
	var want := stream.randi_range(int(params.get("regions_min", 6)), int(params.get("regions_max", 9)))
	var centres := _pick_centres(want)
	if centres.size() < want:
		warnings.append("region 中心只放下 %d / %d 个（陆地面积不足或间距过严）" % [centres.size(), want])
	_allocate()
	_assign(centres)
	_prune()
	return {
		"ok": regions.size() > 0,
		"count": regions.size(),
		"regions": regions.duplicate(true),
		"cell": cell,
		"grid_w": grid_w,
		"grid_h": grid_h,
		"land_cells": _land_cells,
		"water_cells": grid_w * grid_h - _land_cells,
		"warnings": warnings.duplicate(),
	}


# ---------------------------------------------------------------------------
# centre placement
# ---------------------------------------------------------------------------
## Rejection sampling inside the land area: random points, at least `min_dist`
## apart.  A two-pass relaxation (spacing × `RELAX`) keeps the count from silently
## collapsing when a seed happens to make a small island.
func _pick_centres(p_want: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if p_want <= 0:
		return out
	var min_dist := map_size / (float(p_want) * SPACING_FACTOR)
	for relax in 2:
		var need := p_want - out.size()
		if need <= 0:
			break
		var spacing := min_dist * (1.0 if relax == 0 else RELAX)
		var tries := 0
		var added := 0
		while added < need and tries < need * CENTER_TRIES:
			tries += 1
			var x := stream.randf_range(-half_size * CENTER_MARGIN, half_size * CENTER_MARGIN)
			var z := stream.randf_range(-half_size * CENTER_MARGIN, half_size * CENTER_MARGIN)
			if field.height_at(x, z) <= field.water_level + LAND_CLEARANCE:
				continue
			if _too_close(out, x, z, spacing):
				continue
			out.append(Vector2(x, z))
			added += 1
	return out


func _too_close(p_out: Array[Vector2], p_x: float, p_z: float, p_spacing: float) -> bool:
	var limit := p_spacing * p_spacing
	for c in p_out:
		var dx := c.x - p_x
		var dz := c.y - p_z
		if dx * dx + dz * dz < limit:
			return true
	return false


# ---------------------------------------------------------------------------
# assignment
# ---------------------------------------------------------------------------
func _allocate() -> void:
	grid_w = int(ceil(map_size / cell))
	grid_h = grid_w
	owner = PackedInt32Array()
	owner.resize(grid_w * grid_h)
	owner.fill(-1)
	_land_cells = 0


## Cell centres sit at `-half + (i + 0.5) * cell`, i.e. the cell's middle — the
## same convention `HeightField.sample_heights()` uses, so the two grids agree.
func _cell_x(p_i: int) -> float:
	return -half_size + (float(p_i) + 0.5) * cell


func _cell_z(p_j: int) -> float:
	return -half_size + (float(p_j) + 0.5) * cell


func _assign(p_centres: Array[Vector2]) -> void:
	var counts := PackedInt32Array()
	counts.resize(p_centres.size())
	counts.fill(0)
	for j in grid_h:
		var z := _cell_z(j)
		for i in grid_w:
			var x := _cell_x(i)
			if field.height_at(x, z) <= field.water_level:
				continue
			var best := -1
			var best_d := INF
			for k in p_centres.size():
				var dx := p_centres[k].x - x
				var dz := p_centres[k].y - z
				var d := dx * dx + dz * dz
				if d < best_d:
					best_d = d
					best = k
			if best < 0:
				continue
			owner[j * grid_w + i] = best
			counts[best] += 1
			_land_cells += 1
	regions.clear()
	for k in p_centres.size():
		regions.append({
			"id": k,
			"x": p_centres[k].x,
			"z": p_centres[k].y,
			"biome": field.biome_at(p_centres[k].x, p_centres[k].y),
			"cells": counts[k],
			"area": float(counts[k]) * cell * cell,
		})


## Drops regions that received no cell and renumbers the survivors, so "region id"
## is always a dense `0..count-1` — a sparse id space would make every later
## iteration (`for id in count`) quietly skip land.
func _prune() -> void:
	var remap := PackedInt32Array()
	remap.resize(regions.size())
	remap.fill(-1)
	var kept: Array[Dictionary] = []
	for r in regions:
		if int(r["cells"]) <= 0:
			continue
		remap[int(r["id"])] = kept.size()
		var copy := r.duplicate(true)
		copy["id"] = kept.size()
		kept.append(copy)
	if kept.size() == regions.size():
		return
	for idx in owner.size():
		var old := owner[idx]
		if old >= 0:
			owner[idx] = remap[old]
	regions = kept


# ---------------------------------------------------------------------------
# queries
# ---------------------------------------------------------------------------
## Region id containing a world point, or `-1` for water / outside the map.
func region_at(x: float, z: float) -> int:
	if grid_w <= 0:
		return -1
	var i := int(floor((x + half_size) / cell))
	var j := int(floor((z + half_size) / cell))
	if i < 0 or j < 0 or i >= grid_w or j >= grid_h:
		return -1
	return owner[j * grid_w + i]


func region_info(p_id: int) -> Dictionary:
	if p_id < 0 or p_id >= regions.size():
		return {}
	return regions[p_id].duplicate(true)


func area_total() -> float:
	var total := 0.0
	for r in regions:
		total += float(r["area"])
	return total


func cell_count_total() -> int:
	var total := 0
	for r in regions:
		total += int(r["cells"])
	return total


func water_cell_count() -> int:
	return grid_w * grid_h - _land_cells


func biome_counts() -> Dictionary:
	var out := {}
	for r in regions:
		var key := String(r["biome"])
		out[key] = int(out.get(key, 0)) + 1
	return out

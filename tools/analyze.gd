extends SceneTree
## Terrain auditor.
##
##   Godot --path . --headless --script res://tools/analyze.gd
##   Godot --path . --headless --script res://tools/analyze.gd -- 12345 999
##
## Runs the *real* Terrain.generate() path (no duplicated sampling logic, so the
## numbers can never drift from the mesh that ships) and prints the band areas
## it reports, plus a seed sweep so the palette balance can be checked for
## robustness instead of being tuned against one lucky seed.

func _load_style() -> Node:
	var st: Node = root.get_node_or_null("Style")
	if st == null:
		var s = load("res://scripts/core/style.gd").new()
		s.name = "Style"
		root.add_child(s)
		st = s
	return st


func _initialize() -> void:
	_load_style()
	var terrain_script = load("res://scripts/world/terrain.gd")
	var t = terrain_script.new()
	root.add_child(t)

	var seeds: Array = [20250929]
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			seeds.append(int(a))

	var total_ms := 0
	for k in seeds.size():
		var s: int = seeds[k]
		var t0 := Time.get_ticks_msec()
		t.generate(s)
		var ms := Time.get_ticks_msec() - t0
		total_ms += ms
		var st: Dictionary = t.stats
		var hr: Array = st["height_range"]
		print("[analyze] seed=%d  gen=%d ms  tris=%d  h=[%.2f .. %.2f]" % [
			s, ms, int(st["triangles"]), hr[0], hr[1]])
		var bands: Dictionary = st["bands"]
		var n := 0
		for key in bands.keys():
			n += int(bands[key])
		var order := ["water", "sand", "grass", "high", "snow"]
		var line := "          "
		for key in order:
			line += " %s=%.0f%%" % [key, 100.0 * float(bands[key]) / float(maxi(n, 1))]
		line += "  rock=%.1f%%" % [100.0 * float(st["rock_area"]) / float(maxi(n, 1))]
		print(line)
	print("[analyze] average generate time: %.0f ms" % (float(total_ms) / float(seeds.size())))
	print("ANALYZE DONE")
	quit()

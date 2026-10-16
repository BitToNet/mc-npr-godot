extends Node
## Style — the single source of truth for the diorama's art direction.
##
## Owns:
##   * the high-saturation palette (pure flat colours, no photographic maps)
##   * the dynamically generated 3-step grayscale gradient map used as the
##     toon ramp (the Godot equivalent of MeshToonMaterial's gradientMap)
##   * material factories that always pair a toon material with its
##     inverted-hull outline pass
##   * global switches: outline on/off, cel band count, ink thickness
##   * the runtime input map (kept out of project.godot on purpose)

signal style_changed

# --- palette ---------------------------------------------------------------
# Lemon-yellow shallows, apple-green lowlands, turquoise highlands, pure-white
# snow caps, clear translucent water.  Authored in sRGB, converted to linear
# when handed to the renderer.
const PALETTE := {
	"sand": Color("ffe45c"),
	"sand_deep": Color("e8bd4a"),
	"seabed": Color("3f8f92"),
	"grass": Color("7ed957"),
	"grass_dark": Color("6ace49"),
	"high": Color("2ecfc4"),
	"high_dark": Color("26bdb6"),
	"snow": Color("ffffff"),
	"snow_shade": Color("e6f4ff"),
	"rock": Color("7d93a4"),
	"rock_dark": Color("5d7186"),
	"soil": Color("a9714b"),
	"trunk": Color("7a4b2e"),
	"leaf": Color("63d64a"),
	"leaf_dark": Color("3fae4b"),
	"pine": Color("2fa36b"),
	"pine_dark": Color("1f7d55"),
	"cloud": Color("fffdf6"),
	"cloud_shade": Color("dbe6f2"),
	"water": Color("8ef0e6"),
	"water_deep": Color("1b8ac6"),
	"ink": Color("13101b"),
	"stone": Color("9aa7b4"),
	"plinth": Color("3b3550"),
	"plinth_lip": Color("241f36"),
	"skin": Color("ffcfa4"),
	"cloth": Color("ff6b4a"),
	"cloth_alt": Color("ffd166"),
	"cream": Color("fff3d6"),
	"hair": Color("33304d"),
}

const INK := Color("13101b")

var toon_shader: Shader
var outline_shader: Shader
var water_shader: Shader
var ramp_texture: GradientTexture1D
var ramp: Gradient
var outline_enabled := true
var band_count := 3
var ink_scale := 1.0
## world units covered by one screen pixel, published by the camera every frame
## so outlines keep a constant, hand-drawn weight at any zoom level.
var pixel_span := 0.04

var _outline_materials: Array[ShaderMaterial] = []
var _toon_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	toon_shader = load("res://shaders/toon.gdshader")
	outline_shader = load("res://shaders/outline.gdshader")
	water_shader = load("res://shaders/water.gdshader")
	build_ramp(band_count)
	InputSetup.ensure()


## Builds the 3-step (or n-step) grayscale gradient map with CONSTANT
## interpolation, i.e. hard cel terraces instead of a smooth falloff.
func build_ramp(bands: int = 3) -> void:
	band_count = max(2, bands)
	ramp = Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	# darkest -> lightest, evenly spaced hard steps
	for i in band_count:
		offsets.append(float(i) / float(band_count))
		# 0.38 .. 1.0 in linear space
		var v: float = lerp(0.38, 1.0, float(i) / float(max(1, band_count - 1)))
		colors.append(Color(v, v, v, 1.0))
	ramp.offsets = offsets
	ramp.colors = colors
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp_texture = GradientTexture1D.new()
	ramp_texture.gradient = ramp
	ramp_texture.width = 64
	ramp_texture.use_hdr = false
	# refresh every already-built material
	for m in _toon_materials:
		if is_instance_valid(m):
			m.set_shader_parameter("ramp", ramp_texture)


func pal(key: String) -> Color:
	return PALETTE.get(key, Color.MAGENTA)


func lit(key: String) -> Color:
	## sRGB authored colour -> linear, ready for vertex colours.
	return pal(key).srgb_to_linear()


## Material factory.  `opts` keys:
##   tint (Color), shade_min, shade_max, shade_shift, rim, rim_color, spec,
##   spec_sharp, wind, wind_speed, wind_bias, outline (bool), ink (float),
##   emission, emission_color, unshaded
func toon(opts: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = toon_shader
	m.set_shader_parameter("ramp", ramp_texture)
	var tint: Color = opts.get("tint", Color.WHITE)
	m.set_shader_parameter("albedo_tint", tint)
	m.set_shader_parameter("shade_min", float(opts.get("shade_min", 0.42)))
	m.set_shader_parameter("shade_max", float(opts.get("shade_max", 1.0)))
	m.set_shader_parameter("shade_shift", float(opts.get("shade_shift", 0.0)))
	m.set_shader_parameter("exposure_gain", float(opts.get("exposure_gain", 1.0)))
	m.set_shader_parameter("rim_amount", float(opts.get("rim", 0.0)))
	m.set_shader_parameter("rim_color", opts.get("rim_color", Color(1.0, 0.98, 0.88)))
	m.set_shader_parameter("rim_power", float(opts.get("rim_power", 2.4)))
	m.set_shader_parameter("spec_amount", float(opts.get("spec", 0.0)))
	m.set_shader_parameter("spec_sharp", float(opts.get("spec_sharp", 48.0)))
	m.set_shader_parameter("spec_color", opts.get("spec_color", Color.WHITE))
	m.set_shader_parameter("emission_amount", float(opts.get("emission", 0.0)))
	m.set_shader_parameter("emission_color", opts.get("emission_color", Color.WHITE))
	m.set_shader_parameter("wind_strength", float(opts.get("wind", 0.0)))
	m.set_shader_parameter("wind_speed", float(opts.get("wind_speed", 1.0)))
	m.set_shader_parameter("wind_top_bias", float(opts.get("wind_bias", 1.0)))
	_toon_materials.append(m)
	if bool(opts.get("outline", true)):
		attach_outline(m, float(opts.get("ink", 2.0)))   # ink = pixels
	return m


## Creates the inverted-hull pass and links it as `next_pass`.
func outline_material(width: float) -> ShaderMaterial:
	var o := ShaderMaterial.new()
	o.shader = outline_shader
	o.set_shader_parameter("ink", INK)
	o.set_shader_parameter("width", width)
	o.set_shader_parameter("width_scale", ink_scale)
	o.set_shader_parameter("pixel_span", pixel_span)
	o.set_shader_parameter("enabled", 1.0 if outline_enabled else 0.0)
	_outline_materials.append(o)
	return o


func attach_outline(m: ShaderMaterial, width: float) -> ShaderMaterial:
	var o := outline_material(width)
	m.next_pass = o
	return o


func set_pixel_span(v: float) -> void:
	if absf(v - pixel_span) < 0.00001:
		return
	pixel_span = maxf(v, 0.0001)
	for o in _outline_materials:
		if is_instance_valid(o):
			o.set_shader_parameter("pixel_span", pixel_span)


func set_outline(on: bool) -> void:
	outline_enabled = on
	for o in _outline_materials:
		if is_instance_valid(o):
			o.set_shader_parameter("enabled", 1.0 if on else 0.0)
	style_changed.emit()


func set_ink_scale(v: float) -> void:
	ink_scale = clampf(v, 0.0, 3.0)
	for o in _outline_materials:
		if is_instance_valid(o):
			o.set_shader_parameter("width_scale", ink_scale)
	style_changed.emit()


func water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = water_shader
	m.set_shader_parameter("ramp", ramp_texture)
	m.set_shader_parameter("shallow_color", pal("water"))
	m.set_shader_parameter("deep_color", pal("water_deep"))
	m.set_shader_parameter("foam_color", Color(1, 1, 0.98))
	return m

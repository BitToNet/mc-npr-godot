class_name DayNight
extends Node3D
## Dynamic sun bearing + full day/night round trip.
##
## The sun travels a tilted arc, so as the day advances the shadows sweep
## around the diorama and stretch out long at dawn and dusk — the exact moment
## the faceted cel shading turns into crisp, graphic shadow slices.  Below the
## horizon the light flips to the opposite bearing and becomes cool moonlight
## instead of switching off, so the toy never goes pitch black.

signal cycle_changed(on: bool)

const KEYS := [
	{"t": 0.00, "top": "#0a1030", "hor": "#1b2550", "gb": "#06091c", "gh": "#131a38",
		"sun": "#9fb4ff", "energy": 0.50, "amb": "#2b3a6b", "amb_e": 0.30},
	{"t": 0.20, "top": "#22306e", "hor": "#6a5a90", "gb": "#0d1230", "gh": "#33355f",
		"sun": "#ffb27a", "energy": 0.55, "amb": "#4a4a80", "amb_e": 0.34},
	{"t": 0.27, "top": "#5fa2e2", "hor": "#ffc27a", "gb": "#25406b", "gh": "#8f9fc0",
		"sun": "#ffb066", "energy": 1.05, "amb": "#8f86a0", "amb_e": 0.44},
	{"t": 0.36, "top": "#4fb4f2", "hor": "#cfeeff", "gb": "#3f6c92", "gh": "#bcd8e6",
		"sun": "#fff2d8", "energy": 1.15, "amb": "#a8c4e0", "amb_e": 0.52},
	{"t": 0.50, "top": "#37a6f5", "hor": "#dff4ff", "gb": "#4a86ac", "gh": "#cfe8f2",
		"sun": "#fffaee", "energy": 1.28, "amb": "#b6cfe8", "amb_e": 0.58},
	{"t": 0.63, "top": "#45aef0", "hor": "#d8f0ff", "gb": "#4a7fa8", "gh": "#c6e2ec",
		"sun": "#fff0cf", "energy": 1.20, "amb": "#aec6e0", "amb_e": 0.54},
	{"t": 0.73, "top": "#f08a58", "hor": "#ffd18a", "gb": "#5a3450", "gh": "#d09a80",
		"sun": "#ff9a52", "energy": 1.02, "amb": "#c08a80", "amb_e": 0.46},
	{"t": 0.80, "top": "#3b3d86", "hor": "#ff8f6b", "gb": "#141a3c", "gh": "#5a4a6e",
		"sun": "#ff8a5a", "energy": 0.62, "amb": "#5a5688", "amb_e": 0.36},
	{"t": 0.90, "top": "#101a44", "hor": "#26305f", "gb": "#070a1c", "gh": "#1a2246",
		"sun": "#9fb4ff", "energy": 0.52, "amb": "#2b3a6b", "amb_e": 0.32},
	{"t": 1.00, "top": "#0a1030", "hor": "#1b2550", "gb": "#06091c", "gh": "#131a38",
		"sun": "#9fb4ff", "energy": 0.50, "amb": "#2b3a6b", "amb_e": 0.30},
]

var time_of_day := 0.32     # 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset
var auto_cycle := true
var day_length := 170.0     # seconds for a full 24h loop
var sun_yaw := 38.0
var sun_tilt := 24.0

var sun: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial

var _env_owner: WorldEnvironment


func setup(sun_light: DirectionalLight3D, env_owner: WorldEnvironment) -> void:
	sun = sun_light
	_env_owner = env_owner
	environment = Environment.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_curve = 0.12
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 1.6
	sky_material.sun_curve = 0.06
	sky_material.use_debanding = true
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.14
	environment.adjustment_contrast = 1.03
	environment.adjustment_brightness = 1.0
	environment.fog_enabled = true
	environment.fog_density = 0.0
	environment.fog_sky_affect = 0.0
	env_owner.environment = environment

	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 110.0
	sun.shadow_bias = 0.028
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 0.35
	sun.light_angular_distance = 0.0
	sun.light_specular = 0.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	apply()


func _process(delta: float) -> void:
	if auto_cycle:
		time_of_day = fmod(time_of_day + delta / maxf(day_length, 1.0), 1.0)
		apply()


func set_time(t: float) -> void:
	time_of_day = fmod(maxf(t, 0.0), 1.0)
	apply()


func set_auto_cycle(on: bool) -> void:
	auto_cycle = on
	cycle_changed.emit(on)


func clock_string() -> String:
	var minutes := int(round(time_of_day * 24.0 * 60.0)) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func sun_elevation_deg() -> float:
	var ang := (time_of_day - 0.25) * TAU
	var elev := sin(ang)
	if elev < 0.0:
		elev = -elev * 0.85          # moonlight keeps a shallower arc
	return clampf(rad_to_deg(asin(clampf(elev, -1.0, 1.0))) * 0.94, -12.0, 74.0)


func _sample_keys(t: float) -> Dictionary:
	var a: Dictionary = KEYS[0]
	var b: Dictionary = KEYS[KEYS.size() - 1]
	for i in KEYS.size() - 1:
		if t >= KEYS[i]["t"] and t <= KEYS[i + 1]["t"]:
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var span: float = maxf(b["t"] - a["t"], 0.0001)
	var k := smoothstep(0.0, 1.0, (t - a["t"]) / span)
	return {
		"top": Color(a["top"]).lerp(Color(b["top"]), k),
		"hor": Color(a["hor"]).lerp(Color(b["hor"]), k),
		"gb": Color(a["gb"]).lerp(Color(b["gb"]), k),
		"gh": Color(a["gh"]).lerp(Color(b["gh"]), k),
		"sun": Color(a["sun"]).lerp(Color(b["sun"]), k),
		"energy": lerpf(a["energy"], b["energy"], k),
		"amb": Color(a["amb"]).lerp(Color(b["amb"]), k),
		"amb_e": lerpf(a["amb_e"], b["amb_e"], k),
	}


func apply() -> void:
	if environment == null:
		return
	var k := _sample_keys(time_of_day)
	sky_material.sky_top_color = k["top"]
	sky_material.sky_horizon_color = k["hor"]
	sky_material.ground_bottom_color = k["gb"]
	sky_material.ground_horizon_color = k["gh"]
	environment.ambient_light_color = k["amb"]
	environment.ambient_light_energy = k["amb_e"]

	var ang := (time_of_day - 0.25) * TAU
	var elev := sin(ang)
	var night := elev < 0.015
	var use_ang := ang + (PI if night else 0.0)
	var arc := Vector3(cos(use_ang), sin(use_ang), 0.0)
	var basis := Basis(Vector3.UP, deg_to_rad(sun_yaw)) * Basis(Vector3.FORWARD, deg_to_rad(sun_tilt))
	var dir := (basis * arc)
	dir.y = maxf(dir.y, 0.16)        # never let the light graze the exact horizon
	dir = dir.normalized()
	if sun != null:
		sun.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), Vector3.ZERO)
		sun.light_color = k["sun"]
		sun.light_energy = k["energy"]
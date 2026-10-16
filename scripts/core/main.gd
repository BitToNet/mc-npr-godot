extends Node3D
## Main — assembles the diorama and owns the world rebuild.
##
## Node layout lives in scenes/main.tscn: WorldEnvironment, Sun, Terrain,
## Water, Scatter, Clouds, Player, CameraRig, DayNight, UI.  Everything inside
## those nodes is generated at runtime from the height field.

@export var world_seed := 20250929
@export var start_time := 0.32
@export var auto_new_seed_on_start := false

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var terrain: Terrain = $Terrain
@onready var water: WaterSurface = $Water
@onready var scatter: Scatter = $Scatter
@onready var clouds: CloudField = $Clouds
@onready var player: Player = $Player
@onready var rig: CameraRig = $CameraRig
@onready var day_night: DayNight = $DayNight
@onready var ui: CanvasLayer = $UI

var _pending_seed := 0


func _ready() -> void:
	InputSetup.ensure()
	add_to_group("main")
	player.add_to_group("player")
	rig.add_to_group("camera_rig")
	day_night.add_to_group("day_night")
	terrain.add_to_group("terrain")
	water.add_to_group("water")
	player.terrain = terrain
	player.camera_rig = rig
	rig.target = player
	day_night.setup(sun, world_env)
	day_night.set_time(start_time)

	ui.regenerate_pressed.connect(_on_regenerate)
	ui.outline_pressed.connect(_on_toggle_outline)
	ui.bands_pressed.connect(_on_cycle_bands)
	ui.camera_pressed.connect(_on_cycle_camera)
	ui.autocycle_pressed.connect(_on_toggle_cycle)
	ui.time_scrubbed.connect(_on_time_scrubbed)

	if auto_new_seed_on_start:
		world_seed = randi()
	rebuild(world_seed)


func rebuild(seed_value: int) -> void:
	world_seed = seed_value
	terrain.generate(world_seed)
	player.reset_to(terrain.spawn_point)
	water.build(terrain)
	scatter.scatter(terrain, world_seed)
	clouds.build(world_seed)
	rig.snap_to(player.global_position)


func _process(_delta: float) -> void:
	ui.sync({
		"seed": world_seed,
		"outline": Style.outline_enabled,
		"bands": Style.band_count,
		"camera": rig.mode_name(),
		"autocycle": day_night.auto_cycle,
		"time": day_night.time_of_day,
		"clock": day_night.clock_string(),
		"trees": scatter.stats.get("trees", 0),
		"rocks": scatter.stats.get("rocks", 0),
		# S0.6: the HUD is inside the captured viewport, so a live FPS readout would
		# put a different number in every screenshot and keep a baseline from ever
		# being byte-reproducible.  In deterministic capture the step rate is the
		# only meaningful figure anyway, so report that instead of a wall-clock
		# measurement.  Interactive play still shows the real FPS.
		"fps": Clock.hz if Clock.deterministic else Engine.get_frames_per_second(),
	})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regen"):
		_on_regenerate()
	elif event.is_action_pressed("toggle_outline"):
		_on_toggle_outline()
	elif event.is_action_pressed("cycle_camera"):
		_on_cycle_camera()
	elif event.is_action_pressed("toggle_cycle"):
		_on_toggle_cycle()


func _on_regenerate() -> void:
	var next := randi()
	if next == world_seed:
		next += 1
	rebuild(next)


func _on_toggle_outline() -> void:
	Style.set_outline(not Style.outline_enabled)


func _on_cycle_bands() -> void:
	var n := Style.band_count + 1
	if n > 4:
		n = 2
	Style.build_ramp(n)


func _on_cycle_camera() -> void:
	rig.cycle_mode()


func _on_toggle_cycle() -> void:
	day_night.set_auto_cycle(not day_night.auto_cycle)


func _on_time_scrubbed(t: float) -> void:
	day_night.set_auto_cycle(false)
	day_night.set_time(t)
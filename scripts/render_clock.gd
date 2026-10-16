extends Node
## RenderClock — the one and only time source for anything that moves on screen.
##
## S0.6.  Why this exists: the `B-` visual gate (`img_diff`) could not be used at
## all, because two runs of the same build with the same seed and the same camera
## produced images that differed by 1.6 %–5.7 % of their pixels.  The culprits
## were all clocks that cannot be frozen:
##
##   * `TIME` in shaders/toon.gdshader (vegetation sway) and shaders/water.gdshader
##     (waves, foam, sparkle) — the builtin is real engine time.
##   * `Time.get_ticks_msec()` in scripts/clouds.gd — wall-clock, not even
##     `Engine.time_scale` can reach it.
##   * the real `delta` fed to every `_process` — frame pacing is never identical.
##
## This node replaces all three.  Shaders read the global shader parameter
## `render_time` (declared in project.godot under `[shader_globals]`), scripts read
## `Clock.t` / `Clock.dt`.
##
## TWO MODES
##   * interactive (`deterministic == false`) — `t` advances by the real frame
##     delta, so gameplay and feel are **exactly** what they were before S0.6.
##   * deterministic (`deterministic == true`) — frame *N* always means
##     `t == N / hz`.  The value is **computed, never accumulated**, so float
##     drift cannot creep in over a long run.  This is what makes a screenshot
##     byte-reproducible.
##
## ⚠️ `tools/verify.gd` and `tools/*.gd` run as `--script` MainLoops, where
## autoload *identifiers* do not compile (`Identifier not found: Clock`).  Inside
## those, reach this node as `root.get_node("Clock")`.  Scene tree scripts may use
## the `Clock` identifier directly.

const PARAM := "render_time"
const DEFAULT_HZ := 60.0

## Seconds since the clock started (or since the last `reset()`).
var t := 0.0
## Step for the current frame: real delta, or exactly `1.0 / hz`.
var dt := 0.0
## Frame counter; only meaningful in deterministic mode.
var frame := 0
## When true, `t` is a pure function of `frame` and `hz`.
var deterministic := false
## Steps per second used in deterministic mode.
var hz := DEFAULT_HZ

## True when project.godot declares the `shader_globals/render_time` entry the
## shaders bind to.  If it is missing, `_push()` still succeeds silently and the
## shaders sit at `render_time = 0` — i.e. the scene looks *frozen*, which would
## also look "reproducible".  That failure mode is nasty enough to be worth
## detecting.
##
## ⚠️ Do NOT detect it with `RenderingServer.global_shader_parameter_get_list()`:
## that API is editor-only and errors out at runtime
## ("This function should never be used outside the editor, it can severely
## damage performance"), which would spam an ERROR into every windowed run and
## break this project's "logs must be free of ERROR" push gate.
## The project setting is the reliable, side-effect-free source of truth.
## Whether the value actually *reaches* the shaders is proven functionally by the
## `s0_6_repro` case instead (frames 15 vs 200 must render differently).
var shader_param_ok := false


func _ready() -> void:
	# No `process_mode` tricks: the clock must keep ticking even while paused so
	# that a capture is never taken against a frozen `t`.  A very low priority
	# makes sure `t` is already correct by the time scene scripts read it.
	process_priority = -1000
	shader_param_ok = ProjectSettings.has_setting("shader_globals/" + PARAM)
	if not shader_param_ok:
		printerr("[clock] project.godot 未声明 [shader_globals] ", PARAM,
				"；着色器会停在 render_time=0（画面看起来是冻结的）")
	_push()


func _process(delta: float) -> void:
	if deterministic:
		frame += 1
		dt = 1.0 / maxf(hz, 1.0)
		t = float(frame) / maxf(hz, 1.0)
	else:
		dt = delta
		t += delta
	_push()


## Switches mode and rewinds to frame 0.  Deterministic capture must start from a
## known state, otherwise the warm-up length would leak into the result.
func set_deterministic(on: bool, p_hz: float = DEFAULT_HZ) -> void:
	deterministic = on
	hz = maxf(p_hz, 1.0)
	reset()


func reset() -> void:
	t = 0.0
	dt = 0.0
	frame = 0
	_push()


## True once `t` is a pure function of the frame count.
func is_reproducible() -> bool:
	return deterministic and shader_param_ok


func _push() -> void:
	RenderingServer.global_shader_parameter_set(PARAM, t)

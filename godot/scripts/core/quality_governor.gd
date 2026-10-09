class_name QualityGovernor
extends Node
## Keeps the game smooth on laptops that heat up and slow their GPU down after a
## while: it watches how long the GPU takes per frame and, when it gets close
## to the 60 fps budget, quietly drops the least noticeable extras one step at
## a time (ambient occlusion, then glow and the far grass, then far shadows).
## When there is room again, it brings them back. The 3D resolution never goes
## below what Game set up. `--quality=high` turns it off.

const CHECK_EVERY := 2.0
const TOO_SLOW := 13.5      # ms of GPU time per frame
const ROOM_AGAIN := 9.5

var level := 0
var _t := 0.0
var _sum := 0.0
var _n := 0


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	if Game.options.get("quality", "") == "high":
		return
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if gpu > 0.0:
		_sum += gpu
		_n += 1
	_t += delta
	if _t < CHECK_EVERY or _n == 0:
		return
	var avg := _sum / _n
	_t = 0.0
	_sum = 0.0
	_n = 0
	if avg > TOO_SLOW and level < 3:
		level += 1
		_apply()
	elif avg < ROOM_AGAIN and level > 0:
		level -= 1
		_apply()


func _apply() -> void:
	var atm: Atmosphere = Game.atmosphere
	if atm == null or atm.env == null:
		return
	atm.env.ssao_enabled = level < 1
	atm.env.glow_enabled = level < 2
	var gm := GrassField._mat
	if gm:
		gm.set_shader_parameter("fade_end", (GrassField.RANGE - 1.0) if level < 2 else 18.0)
	if atm.sun:
		atm.sun.directional_shadow_max_distance = 40.0 if level < 3 else 26.0
	print("[quality] GPU budget level %d" % level)

class_name Atmosphere
extends Node3D
## Sun, sky, fog and post-processing, with time-of-day presets that chapters can
## pick (a sunny afternoon, golden hour, a starry night). Presets blend smoothly.

const SKY_SHADER := preload("res://shaders/sky.gdshader")

const PRESETS := {
	"day": {
		"sun_elev": 52.0, "sun_azim": -35.0, "sun_color": Color(1.0, 0.95, 0.86), "sun_energy": 1.0,
		"zenith": Color(0.33, 0.60, 0.93), "horizon": Color(0.82, 0.92, 0.99), "below": Color(0.55, 0.78, 0.88),
		"cloud_lit": Color(1, 1, 1), "cloud_shade": Color(0.74, 0.80, 0.92), "cloud_cover": 0.5,
		"ambient": 0.7, "fog": Color(0.78, 0.88, 0.98), "fog_density": 0.0007, "exposure": 1.0, "lamps": 0.0,
		"shadow_tint": Color(0.45, 0.5, 0.9, 0.6),
	},
	"golden": {
		"sun_elev": 13.0, "sun_azim": -28.0, "sun_color": Color(1.0, 0.74, 0.50), "sun_energy": 1.15,
		"zenith": Color(0.40, 0.52, 0.85), "horizon": Color(1.0, 0.78, 0.60), "below": Color(0.78, 0.62, 0.62),
		"cloud_lit": Color(1.0, 0.86, 0.74), "cloud_shade": Color(0.70, 0.58, 0.72), "cloud_cover": 0.45,
		"ambient": 0.75, "fog": Color(1.0, 0.82, 0.68), "fog_density": 0.003, "exposure": 1.05, "lamps": 0.7,
		"shadow_tint": Color(0.62, 0.45, 0.85, 0.55),
	},
	"night": {
		"sun_elev": 38.0, "sun_azim": 150.0, "sun_color": Color(0.62, 0.70, 1.0), "sun_energy": 0.32,
		"zenith": Color(0.04, 0.07, 0.19), "horizon": Color(0.16, 0.20, 0.36), "below": Color(0.08, 0.12, 0.22),
		"cloud_lit": Color(0.32, 0.36, 0.52), "cloud_shade": Color(0.12, 0.14, 0.24), "cloud_cover": 0.35,
		"ambient": 0.55, "fog": Color(0.12, 0.16, 0.30), "fog_density": 0.003, "exposure": 1.25, "lamps": 1.0,
		"shadow_tint": Color(0.2, 0.26, 0.55, 0.35),
	},
}
const ORDER := ["day", "golden", "night"]

var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var cam_attr: CameraAttributesPractical
var current := "day"
var _state := {}
var _tween: Tween


func _ready() -> void:
	Game.atmosphere = self
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	# Soft, contact-hardening shadows (PCSS) like a sunny storybook afternoon.
	sun.shadow_blur = 2.2
	sun.light_angular_distance = 2.2
	sun.shadow_opacity = 0.92
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_light_affect = 0.15
	# Screen-space indirect light (as in Godot's GI demo): sunlit grass and walls
	# bounce a little colour onto what is next to them. It costs ~2.5 ms on the
	# MacBook's Radeon 5300M (dropping the island below 60 fps), so it is opt-in:
	# run with `--ssil` on a faster GPU.
	env.ssil_enabled = Game.options.has("ssil")
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.9
	env.ssil_sharpness = 0.9
	env.ssil_normal_rejection = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.15
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	cam_attr = CameraAttributesPractical.new()
	# A soft far blur gives the diorama / tilt-shift feel.
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 70.0
	cam_attr.dof_blur_far_transition = 60.0
	cam_attr.dof_blur_amount = 0.035
	world_env.camera_attributes = cam_attr
	add_child(world_env)
	_state = PRESETS["day"].duplicate()
	_apply(_state)


func set_preset(preset_name: String, blend_time: float = 0.0) -> void:
	if not PRESETS.has(preset_name):
		return
	current = preset_name
	var target: Dictionary = PRESETS[preset_name]
	if _tween:
		_tween.kill()
	if blend_time <= 0.0:
		_state = target.duplicate()
		_apply(_state)
		return
	var from := _state.duplicate()
	_tween = create_tween()
	_tween.tween_method(func(u: float) -> void:
		for k in target:
			var a = from[k]
			var b = target[k]
			if a is float:
				_state[k] = lerpf(a, b, u)
			elif a is Color:
				_state[k] = (a as Color).lerp(b, u)
		_apply(_state), 0.0, 1.0, blend_time).set_trans(Tween.TRANS_SINE)


func cycle_preset() -> String:
	var i := ORDER.find(current)
	var next: String = ORDER[(i + 1) % ORDER.size()]
	set_preset(next, 2.5)
	return next


func _apply(s: Dictionary) -> void:
	var elev := deg_to_rad(s["sun_elev"])
	var azim := deg_to_rad(s["sun_azim"])
	# Light points *towards* -Z of its basis; build a direction from the sun to the ground.
	var to_sun := Vector3(sin(azim) * cos(elev), sin(elev), cos(azim) * cos(elev))
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = s["sun_color"]
	sun.light_energy = s["sun_energy"]
	sky_mat.set_shader_parameter("zenith", s["zenith"])
	sky_mat.set_shader_parameter("horizon", s["horizon"])
	sky_mat.set_shader_parameter("below", s["below"])
	sky_mat.set_shader_parameter("cloud_lit", s["cloud_lit"])
	sky_mat.set_shader_parameter("cloud_shade", s["cloud_shade"])
	sky_mat.set_shader_parameter("cloud_cover", s["cloud_cover"])
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = s["ambient"]
	env.fog_light_color = s["fog"]
	env.fog_density = s["fog_density"]
	env.tonemap_exposure = s["exposure"]
	var tint: Color = s.get("shadow_tint", Color(0.45, 0.5, 0.9, 0.6))
	RenderingServer.global_shader_parameter_set("shadow_tint", Vector4(tint.r, tint.g, tint.b, tint.a))
	if Game.world and Game.world.has_method("set_lamps"):
		Game.world.set_lamps(s["lamps"])
	for lamp in get_tree().get_nodes_in_group("lamp_lights"):
		(lamp as Light3D).light_energy = s["lamps"] * float(lamp.get_meta("max_energy", 2.0))
		lamp.visible = s["lamps"] > 0.02

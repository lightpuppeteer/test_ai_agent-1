class_name Volcano
extends Node3D
## The big volcano behind the oasis: lazy smoke most of the time, and a
## very well-timed eruption on cue (erupt()).

var _smoke: GPUParticles3D
var _lava: GPUParticles3D
var _plume: GPUParticles3D
var _glow: OmniLight3D
var _crater_mat: ShaderMaterial
const HEIGHT := 46.0


func _ready() -> void:
	# Cone with layered rock bands.
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 7.0
	cm.bottom_radius = 40.0
	cm.height = HEIGHT
	cm.radial_segments = 28
	cm.rings = 6
	cone.mesh = cm
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/volcano.gdshader")
	cone.material_override = sm
	cone.position.y = HEIGHT * 0.5
	add_child(cone)
	# Glowing lava lake in the crater.
	var crater := MeshInstance3D.new()
	var cr := CylinderMesh.new()
	cr.top_radius = 6.2
	cr.bottom_radius = 6.2
	cr.height = 0.5
	crater.mesh = cr
	# Cozy material (so it follows the world curve like the cone); the glow is
	# tweened on eruption through the emission_energy parameter.
	_crater_mat = ShaderMaterial.new()
	_crater_mat.shader = preload("res://shaders/cozy.gdshader")
	_crater_mat.set_shader_parameter("albedo", Color(1.0, 0.4, 0.1))
	_crater_mat.set_shader_parameter("emission", Color(1.0, 0.35, 0.05))
	_crater_mat.set_shader_parameter("emission_energy", 2.0)
	crater.material_override = _crater_mat
	crater.position.y = HEIGHT - 0.5
	add_child(crater)
	# Lava streaks down the sides.
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		var st := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4, 0.3, 30.0)
		st.mesh = bm
		st.material_override = _crater_mat
		var r := 22.0
		st.position = Vector3(cos(a) * r, HEIGHT * 0.5 - 1.0, sin(a) * r)
		st.look_at_from_position(st.position, Vector3(cos(a) * 6.8, HEIGHT, sin(a) * 6.8))
		st.translate_object_local(Vector3(0, 0.6, 0))
		add_child(st)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.45, 0.15)
	_glow.light_energy = 3.0
	_glow.omni_range = 40.0
	_glow.position.y = HEIGHT + 4.0
	add_child(_glow)
	_smoke = _particles(40, 9.0, Color(0.55, 0.52, 0.5, 0.5), 3.0, Vector3(0, 2.5, 0), 6.0, false)
	_smoke.position.y = HEIGHT
	_smoke.emitting = true
	_plume = _particles(160, 6.0, Color(0.35, 0.32, 0.32, 0.7), 5.0, Vector3(0, 9.0, 0), 25.0, false)
	_plume.position.y = HEIGHT
	_lava = _particles(220, 3.5, Color(1.0, 0.5, 0.1, 1.0), 1.6, Vector3(0, 22.0, 0), 35.0, true)
	_lava.position.y = HEIGHT


func _particles(amount: int, life: float, color: Color, size: float, vel: Vector3, spread: float, glow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-80, -60, -80), Vector3(160, 160, 160))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = vel.y * 0.6
	pm.initial_velocity_max = vel.y
	pm.gravity = Vector3(0, -9.8, 0) if glow else Vector3(1.0, 0.6, 0.5)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3 if not glow else 1.0))
	c.add_point(Vector2(1, 1.6 if not glow else 0.4))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.albedo_texture = FX.dot_texture()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.1)
		m.emission_energy_multiplier = 4.0
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p


## The big moment.
func erupt(seconds: float = 9.0) -> void:
	_lava.emitting = true
	_plume.emitting = true
	Sound.play("eruption", 0.0)
	Game.rumble(0.8, 1.0, 1.5)
	var tw := create_tween()
	tw.tween_property(_glow, "light_energy", 14.0, 0.4)
	tw.parallel().tween_property(_crater_mat, "shader_parameter/emission_energy", 6.0, 0.4)
	if Game.camera_rig:
		Game.camera_rig.shake(0.5, 1.6)
	await get_tree().create_timer(seconds).timeout
	_lava.emitting = false
	_plume.emitting = false
	var tw2 := create_tween()
	tw2.tween_property(_glow, "light_energy", 3.0, 3.0)
	tw2.parallel().tween_property(_crater_mat, "shader_parameter/emission_energy", 2.0, 3.0)

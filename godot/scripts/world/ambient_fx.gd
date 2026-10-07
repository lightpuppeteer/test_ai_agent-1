class_name AmbientFX
extends Node3D
## Drifting petals and pollen around the camera, and fireflies at night.

var petals: GPUParticles3D
var fireflies: GPUParticles3D


func _ready() -> void:
	petals = _make(90, 9.0, Vector3(16, 5, 16), Vector2(0.11, 0.08), Color(1.0, 0.82, 0.86), false)
	var pm := petals.process_material as ParticleProcessMaterial
	pm.gravity = Vector3(0.35, -0.25, 0.2)
	pm.angular_velocity_min = -120.0
	pm.angular_velocity_max = 120.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	fireflies = _make(60, 6.0, Vector3(22, 3, 22), Vector2(0.07, 0.07), Color(1.0, 0.9, 0.45), true)
	var fm := fireflies.process_material as ParticleProcessMaterial
	fm.gravity = Vector3.ZERO
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 1.2
	fireflies.emitting = false


func _make(amount: int, life: float, box: Vector3, size: Vector2, color: Color, glow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.visibility_aabb = AABB(-box * 1.5, box * 3.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.direction = Vector3(1, 0, 0.5)
	pm.spread = 60.0
	var c := Curve.new()
	c.add_point(Vector2(0, 0))
	c.add_point(Vector2(0.15, 1))
	c.add_point(Vector2(0.85, 1))
	c.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = Person._blob_texture()
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var f := -cam.global_transform.basis.z
		global_position = cam.global_position + Vector3(f.x, 0, f.z).normalized() * 8.0 + Vector3(0, -2.0, 0)
	var night: bool = Game.atmosphere != null and Game.atmosphere.current == "night"
	fireflies.emitting = night
	petals.emitting = not night

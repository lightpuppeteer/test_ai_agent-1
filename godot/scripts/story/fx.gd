class_name FX
extends RefCounted
## Small one-off visual effects: hearts, fireworks, sparkles, splashes.

static var _heart_tex: Texture2D
static var _dot_tex: Texture2D


static func heart_texture() -> Texture2D:
	if _heart_tex:
		return _heart_tex
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			# Classic implicit heart curve.
			var u := (x - S * 0.5) / (S * 0.42)
			var v := -(y - S * 0.55) / (S * 0.42)
			var f := pow(u * u + v * v - 1.0, 3.0) - u * u * v * v * v
			var a := clampf(-f * 6.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.42, 0.55, a))
	img.generate_mipmaps()
	_heart_tex = ImageTexture.create_from_image(img)
	return _heart_tex


static func dot_texture() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var S := 32
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var d := Vector2(x - S / 2.0 + 0.5, y - S / 2.0 + 0.5).length() / (S / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


static func _billboard_mat(tex: Texture2D, color: Color = Color.WHITE, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


## A burst of floating hearts at `pos` (auto-frees).
static func hearts(parent: Node, pos: Vector3, amount: int = 14) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.2
	p.one_shot = true
	p.explosiveness = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	var c := Curve.new()
	c.add_point(Vector2(0, 0))
	c.add_point(Vector2(0.15, 1))
	c.add_point(Vector2(0.8, 1))
	c.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.material = _billboard_mat(heart_texture(), Color(1, 1, 1), 0.6)
	p.draw_pass_1 = q
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## One firework: a rocket climbs, then bursts into a sphere of coloured sparks.
static func firework(parent: Node, from: Vector3, height: float, color: Color) -> void:
	var tree := parent.get_tree()
	var rocket := GPUParticles3D.new()
	rocket.amount = 24
	rocket.lifetime = 0.5
	rocket.local_coords = false
	var rm := ParticleProcessMaterial.new()
	rm.gravity = Vector3(0, -2, 0)
	rm.initial_velocity_min = 0.0
	rm.initial_velocity_max = 0.3
	rm.spread = 180.0
	rocket.process_material = rm
	var rq := QuadMesh.new()
	rq.size = Vector2(0.25, 0.25)
	rq.material = _billboard_mat(dot_texture(), Color(1.0, 0.85, 0.6), 4.0)
	rocket.draw_pass_1 = rq
	parent.add_child(rocket)
	rocket.global_position = from
	var tw := rocket.create_tween()
	var top := from + Vector3(randf_range(-3, 3), height, randf_range(-3, 3))
	tw.tween_property(rocket, "global_position", top, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Sound.play("firework_launch", -14.0, randf_range(0.9, 1.1))
	await tw.finished
	if not is_instance_valid(rocket):
		return
	rocket.emitting = false
	var burst := GPUParticles3D.new()
	burst.amount = 220
	burst.lifetime = 2.0
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.local_coords = false
	var bm := ParticleProcessMaterial.new()
	bm.direction = Vector3.UP
	bm.spread = 180.0
	bm.initial_velocity_min = 8.0
	bm.initial_velocity_max = 10.5
	bm.gravity = Vector3(0, -3.0, 0)
	bm.damping_min = 2.5
	bm.damping_max = 3.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1))
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	g.add_point(0.2, color)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	bm.color_ramp = gt
	burst.process_material = bm
	var bq := QuadMesh.new()
	bq.size = Vector2(0.8, 0.8)
	bq.material = _billboard_mat(dot_texture(), Color.WHITE, 5.0)
	burst.draw_pass_1 = bq
	parent.add_child(burst)
	burst.global_position = top
	burst.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 6.0
	flash.omni_range = 60.0
	parent.add_child(flash)
	flash.global_position = top
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 1.2)
	ft.tween_callback(flash.queue_free)
	Sound.play("firework_boom", -8.0, randf_range(0.8, 1.15))
	Game.rumble(0.2, 0.1, 0.15)
	rocket.queue_free()
	await tree.create_timer(2.5).timeout
	if is_instance_valid(burst):
		burst.queue_free()


## Sparkly glitter (chest opening, rewards).
static func sparkle(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.9, 0.5), amount: int = 40) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.8
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -1.5, 0)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	q.material = _billboard_mat(dot_texture(), color, 3.0)
	p.draw_pass_1 = q
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func splash(parent: Node, pos: Vector3) -> void:
	sparkle(parent, pos, Color(0.8, 0.95, 1.0), 60)
	Sound.play("splash", -6.0)

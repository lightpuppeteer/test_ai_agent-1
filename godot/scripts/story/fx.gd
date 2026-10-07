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
## A firework: a sparkly rocket, then a burst of the given kind.
## kind: peony | ring | willow | glitter | heart | letters
static func firework(parent: Node, from: Vector3, height: float, color: Color, kind: String = "peony") -> void:
	var tree := parent.get_tree()
	var rocket := GPUParticles3D.new()
	rocket.amount = 40
	rocket.lifetime = 0.6
	rocket.local_coords = false
	var rm := ParticleProcessMaterial.new()
	rm.gravity = Vector3(0, -3, 0)
	rm.initial_velocity_min = 0.2
	rm.initial_velocity_max = 0.8
	rm.spread = 180.0
	rm.color_ramp = _ramp([Color(1, 0.95, 0.75), Color(1.0, 0.6, 0.25, 0.0)])
	rocket.process_material = rm
	var rq := QuadMesh.new()
	rq.size = Vector2(0.22, 0.22)
	rq.material = _billboard_mat(dot_texture(), Color(2.0, 1.8, 1.2), 4.0)
	rocket.draw_pass_1 = rq
	parent.add_child(rocket)
	rocket.global_position = from
	var tw := rocket.create_tween()
	var top := from + Vector3(randf_range(-3, 3), height, randf_range(-3, 3))
	tw.tween_property(rocket, "global_position", top, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Sound.play("firework_launch", -14.0, randf_range(0.9, 1.1))
	await tw.finished
	if not is_instance_valid(rocket):
		return
	rocket.emitting = false
	match kind:
		"heart":
			_shape_burst(parent, top, FireworkShapes.HEART, 4.2, color)
		"letters":
			_shape_burst(parent, top, FireworkShapes.T_HEART_M, 4.0, color)
		_:
			_burst(parent, top, color, kind)
	if kind == "glitter" or kind == "willow" or randf() < 0.3:
		_glitter(parent, top, 5.0 if kind != "willow" else 6.5)
	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 7.0
	flash.omni_range = 60.0
	parent.add_child(flash)
	flash.global_position = top
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 1.3)
	ft.tween_callback(flash.queue_free)
	Sound.play("firework_boom", -8.0, randf_range(0.8, 1.15))
	Game.rumble(0.2, 0.1, 0.15)
	await tree.create_timer(1.0).timeout
	if is_instance_valid(rocket):
		rocket.queue_free()


static func _ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / (cols.size() - 1), cols[i])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static func _burst(parent: Node, at: Vector3, color: Color, kind: String) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.97
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 180.0
	var white := Color(1, 1, 1)
	match kind:
		"ring":
			p.amount = 140
			p.lifetime = 2.2
			m.flatness = 1.0          # all in one plane: a ring
			m.direction = Vector3.RIGHT
			m.initial_velocity_min = 11.0
			m.initial_velocity_max = 11.5
			m.gravity = Vector3(0, -2.0, 0)
			m.damping_min = 3.0
			m.damping_max = 3.2
			m.color_ramp = _ramp([white, color, Color(color.r, color.g, color.b, 0.0)])
		"willow":
			p.amount = 200
			p.lifetime = 3.6
			m.initial_velocity_min = 7.0
			m.initial_velocity_max = 9.0
			m.gravity = Vector3(0, -3.5, 0)
			m.damping_min = 4.0
			m.damping_max = 5.0
			var gold := Color(1.0, 0.78, 0.35)
			m.color_ramp = _ramp([white, gold, gold.darkened(0.3), Color(gold.r, gold.g, gold.b, 0.0)])
		_:
			p.amount = 260
			p.lifetime = 2.2
			m.initial_velocity_min = 9.0
			m.initial_velocity_max = 11.0
			m.gravity = Vector3(0, -3.0, 0)
			m.damping_min = 2.5
			m.damping_max = 3.0
			# Two-tone peonies: the outer stars change colour as they fade.
			var second := Color.from_hsv(fmod(color.h + 0.12, 1.0), color.s, color.v)
			m.color_ramp = _ramp([white, color, second, Color(second.r, second.g, second.b, 0.0)])
	m.scale_min = 0.7
	m.scale_max = 1.2
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	# HDR-bright stars so the glow pass blooms them.
	q.material = _billboard_mat(dot_texture(), Color(2.4, 2.4, 2.4), 5.5)
	p.draw_pass_1 = q
	parent.add_child(p)
	p.global_position = at
	if kind == "ring":
		p.rotation = Vector3(randf_range(-0.9, 0.9), randf() * TAU, randf_range(-0.5, 0.5))
	p.emitting = true
	p.finished.connect(p.queue_free)


## A delayed shimmer of white twinkles where a burst just was.
static func _glitter(parent: Node, at: Vector3, radius: float) -> void:
	await parent.get_tree().create_timer(0.7).timeout
	if not is_instance_valid(parent):
		return
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = 160
	p.lifetime = 1.1
	p.explosiveness = 0.4
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = radius
	m.gravity = Vector3(0, -1.5, 0)
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.4
	m.scale_min = 0.3
	m.scale_max = 0.7
	m.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 0.9), Color(1, 1, 1, 0), Color(1, 0.95, 0.8), Color(1, 1, 1, 0)])
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.material = _billboard_mat(dot_texture(), Color(2.6, 2.6, 2.6), 6.0)
	p.draw_pass_1 = q
	parent.add_child(p)
	p.global_position = at + Vector3(0, -1.0, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Stars that fly out into a picture (a heart, our initials) facing the camera,
## hang there for a moment, then drift down and fade.
static func _shape_burst(parent: Node, at: Vector3, pts: PackedVector2Array, scale: float, color: Color) -> void:
	var cam := parent.get_viewport().get_camera_3d()
	var right := cam.global_transform.basis.x if cam else Vector3.RIGHT
	var up := Vector3.UP
	right.y = 0.0
	right = right.normalized()
	var mat := _billboard_mat(dot_texture(), color, 5.5)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(3, 3, 3)
	var hot := Color(color.r * 2.4, color.g * 2.4, color.b * 2.4)
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	q.material = mat
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = at
	for pt in pts:
		var s := MeshInstance3D.new()
		s.mesh = q
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(s)
		var dest := right * pt.x * scale + up * pt.y * scale
		var tw := s.create_tween()
		tw.tween_property(s, "position", dest, 0.55).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.1)
		tw.tween_property(s, "position", dest + Vector3(0, -1.6, 0), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Colour: white-hot, then the burst colour, then fade out.
	var ct := holder.create_tween()
	ct.tween_property(mat, "albedo_color", hot, 0.6)
	ct.tween_interval(1.0)
	ct.tween_property(mat, "albedo_color", Color(hot.r, hot.g, hot.b, 0.0), 1.5)
	ct.tween_callback(holder.queue_free)


## Sparkly glitter (chest opening, rewards).
## A few popcorn kernels hopping out of a bucket and tumbling away.
static var _kernel_mesh: Mesh
static var _kernel_mat: StandardMaterial3D

static func popcorn_pop(parent: Node, pos: Vector3, count: int = 2) -> void:
	if _kernel_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.06
		sm.radial_segments = 6
		sm.rings = 3
		_kernel_mesh = sm
		_kernel_mat = StandardMaterial3D.new()
		_kernel_mat.albedo_color = Color(1.0, 0.96, 0.78)
		_kernel_mat.roughness = 0.7
	for i in count:
		var k := MeshInstance3D.new()
		k.mesh = _kernel_mesh
		k.material_override = _kernel_mat
		k.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(k)
		var start := pos + Vector3(randf_range(-0.04, 0.04), 0.08, randf_range(-0.04, 0.04))
		k.global_position = start
		var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.08, 0.35)
		var h := randf_range(0.25, 0.6)
		var drop := randf_range(0.3, 0.7)
		var dur := randf_range(0.7, 1.0)
		var tw := k.create_tween()
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(k):
				k.global_position = start + side * t + Vector3(0, 4.0 * h * t * (1.0 - t) - drop * t * t, 0)
				k.rotation = Vector3(t * 9.0, t * 5.0, 0), 0.0, 1.0, dur)
		tw.tween_property(k, "scale", Vector3.ZERO, 0.25)
		tw.tween_callback(k.queue_free)


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

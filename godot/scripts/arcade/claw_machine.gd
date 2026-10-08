extends ArcadeGame
## CLAW CRANE — a little 3D claw machine full of plushes (its own tiny world in
## a SubViewport). Move the claw, drop it, and hope. Prizes dropped down the
## chute go home with you (onto the plush shelf in the house).

const BOUNDS := Vector2(0.62, 0.36)        # claw x/z range
const TOP_Y := 1.32
const CHUTE := Vector3(-0.62, 0, 0.36)
const TIME := 20.0
const MOVE_SPEED := 0.55

var _vp: SubViewport
var _world: Node3D
var _claw: Node3D
var _cable: MeshInstance3D
var _prongs: Array[Node3D] = []
var _prizes: Array = []        # {node, kind, vy, held}
var _claw_pos := Vector2.ZERO
var _claw_y := TOP_Y
var _open := 1.0
var _phase := "idle"           # idle | aim | down | close | up | home | release | done
var _phase_t := 0.0
var _time_left := TIME
var _grabbed: Dictionary = {}
var _target_y := 0.2
var _won_kind := ""
var _overlay: Control
var _curve_was := 0.0
var _whirr_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	box.add_child(_vp)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	# The world curve would bend this tiny scene too: flatten it while we play.
	var cv: Variant = RenderingServer.global_shader_parameter_get("curve_amount")
	_curve_was = float(cv) if (cv is float or cv is int) else float(ProjectSettings.get_setting("shader_globals/curve_amount", {}).get("value", 0.0))
	RenderingServer.global_shader_parameter_set("curve_amount", 0.0)
	_build_scene()
	_scatter_prizes()


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("curve_amount", _curve_was)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _vp:
		_vp.size = Vector2i(size)


func _build_scene() -> void:
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.12, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.7, 0.9)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	_world.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.6, 0.4)
	lamp.light_color = Color(1.0, 0.85, 0.95)
	lamp.light_energy = 1.2
	lamp.omni_range = 3.5
	_world.add_child(lamp)
	var cab := Color(0.62, 0.52, 0.98)
	var parts := [
		# Prize pit floor and the cabinet walls around it.
		Props3D.b(Vector3(1.7, 0.1, 1.1), Vector3(0, -0.05, 0), Color(0.95, 0.82, 0.9), {"bevel": 0.02}),
		Props3D.b(Vector3(1.9, 1.8, 0.08), Vector3(0, 0.8, -0.6), cab.darkened(0.15), {"bevel": 0.03}),
		Props3D.b(Vector3(0.08, 1.8, 1.25), Vector3(-0.92, 0.8, 0), cab, {"bevel": 0.03}),
		Props3D.b(Vector3(0.08, 1.8, 1.25), Vector3(0.92, 0.8, 0), cab, {"bevel": 0.03}),
		Props3D.b(Vector3(1.9, 0.16, 1.25), Vector3(0, 1.62, 0), cab.darkened(0.25), {"bevel": 0.04}),
		# Gantry rails.
		Props3D.b(Vector3(1.6, 0.04, 0.04), Vector3(0, 1.5, -0.42), Color(0.85, 0.85, 0.9), {"mat": "glossy"}),
		Props3D.b(Vector3(1.6, 0.04, 0.04), Vector3(0, 1.5, 0.42), Color(0.85, 0.85, 0.9), {"mat": "glossy"}),
		# The chute: a little walled box in the front-left corner.
		Props3D.b(Vector3(0.34, 0.24, 0.03), Vector3(CHUTE.x, 0.12, CHUTE.z - 0.17), Color(1, 1, 1), {"bevel": 0.01}),
		Props3D.b(Vector3(0.03, 0.24, 0.34), Vector3(CHUTE.x + 0.17, 0.12, CHUTE.z), Color(1, 1, 1), {"bevel": 0.01}),
		Props3D.b(Vector3(0.3, 0.02, 0.3), Vector3(CHUTE.x, 0.005, CHUTE.z), Color(0.2, 0.15, 0.25), {"bevel": 0.005}),
	]
	# Back wall stars and a "WIN!" arrow over the chute.
	for i in 7:
		parts.append(Props3D.b(Vector3(0.07, 0.07, 0.02), Vector3(-0.75 + i * 0.25, 1.25 - (i % 2) * 0.12, -0.55), Color(1.0, 0.9, 0.5), {"mat": "glow", "rot": Vector3(0, 0, 45)}))
	_world.add_child(Props3D.blocks(parts))
	var win := Label3D.new()
	win.text = "WIN ↓"
	win.font = FONT
	win.font_size = 64
	win.pixel_size = 0.0017
	win.modulate = Color(1.0, 0.9, 0.4)
	win.outline_size = 12
	win.outline_modulate = Color(0.5, 0.2, 0.5)
	win.position = Vector3(CHUTE.x, 0.36, CHUTE.z - 0.16)
	_world.add_child(win)
	# The claw: carriage on the rails, cable, hub and three prongs.
	_claw = Node3D.new()
	_world.add_child(_claw)
	_claw.add_child(Props3D.blocks([
		Props3D.b(Vector3(0.16, 0.06, 0.9), Vector3(0, 0, 0), Color(0.7, 0.7, 0.76), {"mat": "glossy", "bevel": 0.02}),
	]))
	_cable = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008
	cm.bottom_radius = 0.008
	cm.height = 1.0
	_cable.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.3, 0.3, 0.32)
	_cable.material_override = cmat
	_world.add_child(_cable)
	var hub := Node3D.new()
	hub.name = "Hub"
	_world.add_child(hub)
	hub.add_child(Props3D.blocks([Props3D.b(Vector3(0.1, 0.07, 0.1), Vector3(0, 0.0, 0), Color(0.9, 0.85, 0.3), {"mat": "gold", "bevel": 0.025})]))
	for i in 3:
		var pivot := Node3D.new()
		pivot.rotation.y = TAU * i / 3.0
		hub.add_child(pivot)
		var arm := Node3D.new()
		arm.position = Vector3(0, -0.02, 0.04)
		pivot.add_child(arm)
		arm.add_child(Props3D.blocks([
			Props3D.b(Vector3(0.022, 0.13, 0.022), Vector3(0, -0.065, 0), Color(0.85, 0.85, 0.9), {"mat": "glossy", "bevel": 0.008}),
			Props3D.b(Vector3(0.022, 0.06, 0.022), Vector3(0, -0.14, -0.02), Color(0.85, 0.85, 0.9), {"mat": "glossy", "bevel": 0.008, "rot": Vector3(-40, 0, 0)}),
		]))
		_prongs.append(arm)
	var cam := Camera3D.new()
	cam.fov = 42.0
	_world.add_child(cam)
	cam.position = Vector3(0.0, 1.95, 2.3)
	cam.look_at(Vector3(0, 0.62, -0.1))
	cam.current = true
	_update_claw()


func _scatter_prizes() -> void:
	for p in _prizes:
		p["node"].queue_free()
	_prizes.clear()
	_rng.randomize()
	var n := 11
	var tries := 0
	while _prizes.size() < n and tries < 200:
		tries += 1
		var pos := Vector3(_rng.randf_range(-0.72, 0.72), 0.0, _rng.randf_range(-0.42, 0.42))
		if Vector2(pos.x - CHUTE.x, pos.z - CHUTE.z).length() < 0.32:
			continue
		var ok := true
		for p in _prizes:
			if Vector2(p["node"].position.x - pos.x, p["node"].position.z - pos.z).length() < 0.2:
				ok = false
		if not ok:
			continue
		var kind: String = Plushes.KINDS[_rng.randi() % Plushes.KINDS.size()]
		var node := Plushes.build(kind)
		node.scale = Vector3.ONE * 0.6
		node.position = pos
		node.rotation = Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.2, 0.2))
		_world.add_child(node)
		_prizes.append({"node": node, "kind": kind, "vy": 0.0, "held": false, "falling": false, "out": false})


func _reset() -> void:
	_claw_pos = Vector2(0.3, 0.0)
	_claw_y = TOP_Y
	_open = 1.0
	_phase = "aim"
	_phase_t = 0.0
	_time_left = TIME
	_grabbed = {}
	_won_kind = ""
	_scatter_prizes()


func result_note() -> String:
	return "You won the %s!" % Plushes.NAMES.get(_won_kind, "plush") if _won_kind != "" else ""


func _process(delta: float) -> void:
	super._process(delta)
	if not running:
		# Attract mode: the claw drifts about.
		_claw_pos = Vector2(sin(t * 0.7) * 0.5, sin(t * 0.45) * 0.25)
		_update_claw()
	_drop_falling(delta)
	_overlay.queue_redraw()


func _tick(delta: float) -> void:
	_phase_t += delta
	match _phase:
		"aim":
			_time_left -= delta
			var mv := Vector2(float(held("right")) - float(held("left")), float(held("down")) - float(held("up")))
			var stick := Game.move_input()
			if stick.length() > 0.2:
				mv = stick
			_claw_pos += mv.limit_length(1.0) * MOVE_SPEED * delta
			_claw_pos.x = clampf(_claw_pos.x, -BOUNDS.x, BOUNDS.x)
			_claw_pos.y = clampf(_claw_pos.y, -BOUNDS.y, BOUNDS.y)
			if mv.length() > 0.1:
				_whirr(delta)
			if pressed("a") or _time_left <= 0.0:
				_target_y = _landing_height()
				_set_phase("down")
				Sound.play("arcade_claw", -10.0, 0.9)
		"down":
			_claw_y = move_toward(_claw_y, _target_y, delta * 0.7)
			if _claw_y <= _target_y + 0.001:
				_set_phase("close")
				Sound.play("arcade_grab", -6.0)
		"close":
			_open = maxf(0.0, 1.0 - _phase_t / 0.45)
			if _phase_t > 0.55:
				_try_grab()
				_set_phase("up")
				Sound.play("arcade_claw", -10.0, 1.1)
		"up":
			_claw_y = move_toward(_claw_y, TOP_Y, delta * 0.6)
			# A wobbly grip sometimes lets go on the way up.
			if not _grabbed.is_empty() and _grabbed.get("slip_at", -1.0) > 0.0 and _claw_y >= _grabbed["slip_at"]:
				_release_grabbed()
				Sound.play("arcade_wrong", -10.0)
			if _claw_y >= TOP_Y - 0.001:
				_set_phase("home")
		"home":
			var to := Vector2(CHUTE.x, CHUTE.z) - _claw_pos
			_claw_pos += to.limit_length(MOVE_SPEED * 1.1 * delta)
			_whirr(delta)
			if to.length() < 0.01:
				_set_phase("release")
		"release":
			_open = minf(1.0, _phase_t / 0.3)
			if not _grabbed.is_empty() and _phase_t > 0.15:
				_release_grabbed()
			if _phase_t > 1.6:
				_set_phase("done")
		"done":
			score = 1 if _won_kind != "" else 0
			end_round()
	_update_claw()


func _set_phase(p: String) -> void:
	_phase = p
	_phase_t = 0.0


func _whirr(delta: float) -> void:
	_whirr_t -= delta
	if _whirr_t <= 0.0:
		_whirr_t = 0.45
		Sound.play("arcade_claw", -16.0, 1.3)


## How low the claw goes: onto the top of whatever is under it.
func _landing_height() -> float:
	var y := 0.16
	for p in _prizes:
		var n: Node3D = p["node"]
		if p["out"]:
			continue
		if Vector2(n.position.x - _claw_pos.x, n.position.z - _claw_pos.y).length() < 0.13:
			y = maxf(y, n.position.y + 0.26)
	return y


func _try_grab() -> void:
	var best: Dictionary = {}
	var bd := 0.16
	for p in _prizes:
		if p["out"]:
			continue
		var n: Node3D = p["node"]
		var d := Vector2(n.position.x - _claw_pos.x, n.position.z - _claw_pos.y).length()
		if d < bd:
			bd = d
			best = p
	if best.is_empty():
		return
	var chance := 0.8 if bd < 0.07 else 0.5
	if best["kind"] == "yoggi":
		chance *= 0.8       # he's slippery, just like the real one
	if _rng.randf() > chance:
		# Brushed it: the plush wobbles and stays.
		var n: Node3D = best["node"]
		var tw := n.create_tween()
		tw.tween_property(n, "rotation:z", n.rotation.z + 0.4, 0.15)
		tw.tween_property(n, "rotation:z", n.rotation.z, 0.3)
		return
	best["held"] = true
	_grabbed = best
	_grabbed["slip_at"] = _rng.randf_range(0.6, 1.1) if _rng.randf() < 0.18 else -1.0
	_grabbed["off"] = best["node"].position - Vector3(_claw_pos.x, _claw_y - 0.2, _claw_pos.y)


func _release_grabbed() -> void:
	if _grabbed.is_empty():
		return
	_grabbed["held"] = false
	_grabbed["falling"] = true
	_grabbed["vy"] = 0.0
	_grabbed = {}


func _drop_falling(delta: float) -> void:
	for p in _prizes:
		var n: Node3D = p["node"]
		if p["held"]:
			n.position = Vector3(_claw_pos.x, _claw_y - 0.24, _claw_pos.y)
			continue
		if not p["falling"]:
			continue
		p["vy"] -= 4.5 * delta
		n.position.y += p["vy"] * delta
		var in_chute := Vector2(n.position.x - CHUTE.x, n.position.z - CHUTE.z).length() < 0.16
		var floor_y := -0.6 if in_chute else 0.0
		if n.position.y <= floor_y:
			n.position.y = floor_y
			p["falling"] = false
			if in_chute and not p["out"]:
				p["out"] = true
				n.visible = false
				_won_kind = p["kind"]
				Plushes.add_won(_won_kind)
				Sound.play("arcade_win", -6.0)
			else:
				Sound.play("arcade_plop", -8.0)


func _update_claw() -> void:
	if _claw == null:
		return
	_claw.position = Vector3(_claw_pos.x, 1.5, 0)
	var hub: Node3D = _world.get_node("Hub")
	hub.position = Vector3(_claw_pos.x, _claw_y, _claw_pos.y)
	var len := 1.5 - _claw_y
	_cable.position = Vector3(_claw_pos.x, _claw_y + len * 0.5, _claw_pos.y)
	_cable.scale = Vector3(1, maxf(len, 0.01), 1)
	for arm in _prongs:
		arm.rotation.x = lerpf(-0.05, -0.6, _open)


func _draw_overlay() -> void:
	if not running:
		return
	var w := size.x
	if _phase == "aim":
		var col := Color(1, 1, 1) if _time_left > 5.0 else Color(1.0, 0.45, 0.4)
		var tt := "⏱ %d" % ceili(maxf(_time_left, 0.0))
		_overlay.draw_string_outline(FONT, Vector2(28, 64), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, 10, Color(0.3, 0.15, 0.4))
		_overlay.draw_string(FONT, Vector2(28, 64), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, col)
	elif _won_kind != "":
		_overlay.draw_string_outline(FONT, Vector2(0, 80), "YOU GOT ONE!", HORIZONTAL_ALIGNMENT_CENTER, w, 56, 12, Color(0.4, 0.15, 0.4))
		_overlay.draw_string(FONT, Vector2(0, 80), "YOU GOT ONE!", HORIZONTAL_ALIGNMENT_CENTER, w, 56, Color(1.0, 0.9, 0.45))


func _draw() -> void:
	pass

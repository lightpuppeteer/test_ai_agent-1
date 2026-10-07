class_name MiniMap
extends Control
## Round mini-map (bottom left): the island painted from the terrain, you, him,
## the neighbours and a heart for the current quest goal (pinned to the rim
## when it's off the map). N / D-pad right cycles the zoom.

const SIZE := 210.0
const MAP_PX := 384
const ZOOMS := [35.0, 70.0, 130.0]     # metres from centre to rim

var _tex: ImageTexture
var _map_mat: ShaderMaterial
var _zoom_i := 1
var _rect: TextureRect
var _icons: Control
var _label: Label
var _hud: HUD


func setup(hud: HUD) -> void:
	_hud = hud
	custom_minimum_size = Vector2(SIZE, SIZE)
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 24
	offset_top = -SIZE - 28
	offset_right = 24 + SIZE
	offset_bottom = -28
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture = _blank()
	_map_mat = ShaderMaterial.new()
	_map_mat.shader = preload("res://shaders/minimap.gdshader")
	_rect.material = _map_mat
	add_child(_rect)
	_icons = Control.new()
	_icons.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.draw.connect(_draw_icons)
	add_child(_icons)
	_label = hud._label("", 17, HUD.INK, hud._bold_font)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(0, SIZE + 2)
	_label.size = Vector2(SIZE, 24)
	add_child(_label)
	_build_texture.call_deferred()


func _blank() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.8, 0.9))
	return ImageTexture.create_from_image(img)


func _build_texture() -> void:
	var t: Terrain = Game.terrain
	if t == null:
		return
	var img := Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	var half := Terrain.SIZE * 0.5
	for py in MAP_PX:
		var z := -half + (py + 0.5) / MAP_PX * Terrain.SIZE
		for px in MAP_PX:
			var x := -half + (px + 0.5) / MAP_PX * Terrain.SIZE
			var h := t.height_at(x, z)
			var c: Color
			if h < -0.05:
				c = Color(0.55, 0.85, 0.9).lerp(Color(0.3, 0.6, 0.85), clampf(-h / 4.0, 0.0, 1.0))
			elif h < 1.4:
				c = Color(0.97, 0.9, 0.7)
			else:
				c = Color(0.55, 0.8, 0.45).lerp(Color(0.42, 0.68, 0.38), clampf((h - 2.0) / 3.0, 0.0, 1.0))
				var sp := t.splat_at(x, z)
				if sp.b > 0.5:
					c = Color(0.85, 0.8, 0.72)
				elif sp.g > 0.5:
					c = Color(0.93, 0.88, 0.8)
				elif sp.r > 0.5:
					c = Color(0.85, 0.72, 0.52)
				var n := t.normal_at(x, z)
				if n.y < 0.75:
					c = c.darkened(0.25)
			img.set_pixel(px, py, c)
	# Causeway
	var a := Places.CAUSEWAY_FROM
	var b := Places.CAUSEWAY_TO
	for i in 200:
		var p := a.lerp(b, i / 199.0)
		_dot(img, p.x, p.z, 2.2, Color(0.93, 0.88, 0.8))
	# Buildings
	for spot_name in ["pizza_door", "cinema_door", "house_door", "hotel_door"]:
		var s := Places.spot(spot_name)
		if s:
			var d: Door = s
			_dot(img, d.global_position.x, d.global_position.z, 2.2, Color(0.75, 0.45, 0.4))
	_tex = ImageTexture.create_from_image(img)
	_rect.texture = _tex


func _dot(img: Image, x: float, z: float, r_m: float, c: Color) -> void:
	var half := Terrain.SIZE * 0.5
	var cx := (x + half) / Terrain.SIZE * MAP_PX
	var cy := (z + half) / Terrain.SIZE * MAP_PX
	var r := r_m / Terrain.SIZE * MAP_PX
	for y in range(int(cy - r - 1), int(cy + r + 2)):
		for xx in range(int(cx - r - 1), int(cx + r + 2)):
			if xx >= 0 and y >= 0 and xx < MAP_PX and y < MAP_PX and Vector2(xx - cx, y - cy).length() <= r:
				img.set_pixel(xx, y, c)


func cycle_zoom() -> void:
	_zoom_i = (_zoom_i + 1) % ZOOMS.size()
	Sound.play("ui_blip", -14.0)


func _process(_delta: float) -> void:
	var p: Node3D = Game.player
	var inside := Game.location != "outside"
	_rect.visible = not inside
	if inside:
		var it: Interior = Places.interiors.get(Game.location)
		_label.text = "🏠 " + (it.title if it else Game.location)
	else:
		_label.text = ""
	if p == null or _tex == null:
		_icons.queue_redraw()
		return
	var half := Terrain.SIZE * 0.5
	var r: float = ZOOMS[_zoom_i]
	var uv_center := Vector2((p.global_position.x + half) / Terrain.SIZE, (p.global_position.z + half) / Terrain.SIZE)
	_map_mat.set_shader_parameter("center", uv_center)
	_map_mat.set_shader_parameter("radius", r / Terrain.SIZE)
	_icons.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map_zoom"):
		cycle_zoom()


func _to_map(world: Vector3) -> Vector2:
	var p: Node3D = Game.player
	var r: float = ZOOMS[_zoom_i]
	var d := Vector2(world.x - p.global_position.x, world.z - p.global_position.z) / r
	return Vector2(SIZE, SIZE) * 0.5 + d * SIZE * 0.5


func _draw_icons() -> void:
	var c := Vector2(SIZE, SIZE) * 0.5
	var R := SIZE * 0.5
	var p: Node3D = Game.player
	var inside := Game.location != "outside"
	if inside:
		_icons.draw_circle(c, R, Color(1, 0.975, 0.91, 0.85))
	if p and not inside:
		# Neighbours
		for v in get_tree().get_nodes_in_group("villagers"):
			var mp := _to_map((v as Node3D).global_position)
			if mp.distance_to(c) < R - 4:
				_icons.draw_circle(mp, 3.5, Color(0.95, 0.65, 0.4))
		# Car
		var car: Node3D = get_tree().current_scene.get_node_or_null("Car") if get_tree().current_scene else null
		if car:
			var cp := _to_map(car.global_position)
			if cp.distance_to(c) < R - 4:
				_icons.draw_rect(Rect2(cp - Vector2(4, 4), Vector2(8, 8)), Color(0.9, 0.35, 0.3))
		# Him
		var him: Node3D = Game.partner
		if him:
			var hp := _to_map(him.global_position)
			if hp.distance_to(c) < R - 4:
				_icons.draw_circle(hp, 5.0, Color(0.45, 0.66, 0.95))
				_icons.draw_arc(hp, 5.0, 0, TAU, 16, Color(1, 1, 1), 1.5)
	# Quest goal: a heart, pinned to the rim when far away (or shown as an arrow from inside).
	if Game.quests:
		var t: Variant = Game.quests.current_target()
		if t != null and p and not inside:
			var tp := _to_map(t)
			var off := tp - c
			var edge := off.length() > R - 12
			if edge:
				tp = c + off.normalized() * (R - 12)
			_draw_heart(tp, 9.0 if not edge else 7.0, Color(1.0, 0.42, 0.55))
	# Her (centre), pointing where she faces.
	if p and not inside:
		var f := -p.global_transform.basis.z
		var dir := Vector2(f.x, f.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([c + dir * 9.0, c - dir * 6.0 + side * 6.0, c - dir * 3.0, c - dir * 6.0 - side * 6.0])
		_icons.draw_colored_polygon(pts, Color(0.95, 0.5, 0.62))
		_icons.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1), 1.5)
	# Rim
	_icons.draw_arc(c, R - 1.5, 0, TAU, 64, Color(1, 0.975, 0.91), 4.0)
	_icons.draw_arc(c, R - 4.0, 0, TAU, 64, Color(0.98, 0.62, 0.45, 0.8), 2.0)
	# North marker
	_icons.draw_string(_hud._title_font, c + Vector2(-5, -R + 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.35, 0.28))


func _draw_heart(at: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(at + Vector2(x, y) * s / 16.0)
	_icons.draw_colored_polygon(pts, col)
	_icons.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1), 1.5)

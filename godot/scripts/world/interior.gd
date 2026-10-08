class_name Interior
extends Node3D
## A cosy room (or a few rooms) built far away from the island; doors on the
## island teleport you here with a fade. Floors, walls with a door gap, a
## ceiling, warm lights and fake daylight windows.

var id := "room"
var title := "Room"
var size := Vector3(10, 3.2, 8)       # width (x), height, depth (z)
var floor_color := Color(0.78, 0.6, 0.42)
var wall_color := Color(0.98, 0.92, 0.84)
var trim_color := Color(0.62, 0.42, 0.3)
var floor_tiles := false
## Inside spawn (local) and facing, next to the door in the front (+Z) wall.
var spawn := Vector3.ZERO
var spawn_yaw := 0.0
var exit_door: Door
var _body: StaticBody3D


func build() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = Game.PHYS_WORLD
	add_child(_body)
	var w := size.x
	var d := size.z
	var h := size.y
	# Floor with a plank or tile pattern.
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	pm.subdivide_width = int(w)
	pm.subdivide_depth = int(d)
	fl.mesh = pm
	fl.material_override = _floor_material()
	add_child(fl)
	_box_collider(Vector3(w + 1, 0.4, d + 1), Vector3(0, -0.2, 0))
	# "Dollhouse" shell: walls are one-sided panels facing the room, so the camera
	# can look in from outside/above; invisible boxes block the sun and people.
	_shadow_box(Vector3(w + 0.5, 0.3, d + 0.5), Vector3(0, h + 0.15, 0))
	_shell(Vector3(w, h, 0), Vector3(0, h * 0.5, -d * 0.5), Vector3.BACK, wall_color)
	_shell(Vector3(d, h, 0), Vector3(-w * 0.5, h * 0.5, 0), Vector3.RIGHT, wall_color.darkened(0.03))
	_shell(Vector3(d, h, 0), Vector3(w * 0.5, h * 0.5, 0), Vector3.LEFT, wall_color.darkened(0.03))
	_shell(Vector3(w, h, 0), Vector3(0, h * 0.5, d * 0.5), Vector3.FORWARD, wall_color.lightened(0.02), 1.6)
	var door_w := 1.6
	# Door slab (closed look) + skirting boards.
	_wall_mesh(Vector3(door_w - 0.2, 2.2, 0.08), Vector3(0, 1.1, d * 0.5 - 0.05), trim_color, false)
	for sgn in [-1.0, 1.0]:
		_wall_mesh(Vector3(0.12, 0.14, d), Vector3(sgn * (w * 0.5 - 0.06), 0.07, 0), trim_color, false)
	_wall_mesh(Vector3(w, 0.14, 0.12), Vector3(0, 0.07, -d * 0.5 + 0.06), trim_color, false)
	# Warm lights.
	var nx := maxi(1, int(w / 6.0))
	var nz := maxi(1, int(d / 6.0))
	for i in nx:
		for j in nz:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.86, 0.7)
			l.light_energy = 1.4
			l.omni_range = 9.0
			l.shadow_enabled = false
			l.position = Vector3(-w * 0.5 + w * (i + 0.5) / nx, h - 0.5, -d * 0.5 + d * (j + 0.5) / nz)
			add_child(l)
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.18
			sm.height = 0.3
			bulb.mesh = sm
			var bm := StandardMaterial3D.new()
			bm.albedo_color = Color(1, 0.95, 0.85)
			bm.emission_enabled = true
			bm.emission = Color(1, 0.9, 0.75)
			bm.emission_energy_multiplier = 2.0
			bulb.material_override = bm
			bulb.position = l.position + Vector3(0, 0.25, 0)
			add_child(bulb)
	# Cosy indoor ambience instead of the bright sky light.
	var probe := ReflectionProbe.new()
	probe.size = Vector3(w + 2, h + 2, d + 2)
	probe.position.y = h * 0.5
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.85, 0.72, 0.62)
	probe.ambient_color_energy = 0.55
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)
	spawn = Vector3(0, 0.05, d * 0.5 - 1.1)
	spawn_yaw = 0.0
	exit_door = Door.new()
	exit_door.prompt = "Go outside"
	exit_door.position = Vector3(0, 1.0, d * 0.5 - 0.3)
	add_child(exit_door)


## A fake window: bright pane + frame on a wall (local position, facing +Z by default).
func window(at: Vector3, yaw_deg: float, w: float = 1.4, h: float = 1.2) -> void:
	var n := Node3D.new()
	n.position = at
	n.rotation.y = deg_to_rad(yaw_deg)
	add_child(n)
	var pane := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	pane.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.9, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.7, 0.88, 1.0)
	m.emission_energy_multiplier = 0.9
	pane.material_override = m
	pane.position.z = 0.02
	n.add_child(pane)
	for p in [[Vector3(w + 0.16, 0.1, 0.08), Vector3(0, h * 0.5, 0)], [Vector3(w + 0.16, 0.1, 0.08), Vector3(0, -h * 0.5, 0)],
			[Vector3(0.1, h, 0.08), Vector3(-w * 0.5, 0, 0)], [Vector3(0.1, h, 0.08), Vector3(w * 0.5, 0, 0)], [Vector3(0.06, h, 0.06), Vector3.ZERO]]:
		var f := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = p[0]
		f.mesh = bx
		f.material_override = _mat(trim_color.lightened(0.3))
		f.position = p[1] + Vector3(0, 0, 0.04)
		n.add_child(f)


## Places a Kenney prop inside the room (local coords), centred on its footprint.
func prop(prop_id: String, at: Vector3, yaw_deg: float = 0.0, mul: float = 1.0, collide: String = "box") -> Node3D:
	var bb := Props.model_aabb(prop_id)
	var s := Props.kit_scale(prop_id) * mul
	var n := Props.place(self, prop_id, at, yaw_deg, mul, "", {})
	var m: Node3D = n.get_node("Model")
	m.position = -Vector3(bb.get_center().x, bb.position.y, bb.get_center().z) * s
	if collide != "":
		var body := StaticBody3D.new()
		body.collision_layer = Game.PHYS_PROPS
		n.add_child(body)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = bb.size * s * Vector3(0.9, 1.0, 0.9)
		cs.shape = box
		cs.position = Vector3(0, bb.size.y * s * 0.5, 0)
		body.add_child(cs)
	return n


## One wall of the shell: a panel facing `inward` (normal into the room), with an
## optional door gap in the middle; plus a shadow caster and a collider.
func _shell(sz: Vector3, at: Vector3, inward: Vector3, color: Color, door_gap: float = 0.0) -> void:
	var w := sz.x
	var h := sz.y
	var right := Vector3.UP.cross(inward).normalized()     # along the wall
	var pieces := [[w, at, h]]
	if door_gap > 0.0:
		var side := (w - door_gap) * 0.5
		pieces = [[side, at - right * (door_gap * 0.5 + side * 0.5), h], [side, at + right * (door_gap * 0.5 + side * 0.5), h]]
		var top_h := h - 2.3
		var mi := _panel(Vector2(door_gap, top_h), at + Vector3(0, 2.3 + top_h * 0.5 - h * 0.5, 0), inward, color)
		add_child(mi)
		_shadow_box(Vector3(door_gap if absf(inward.z) > 0.5 else 0.3, top_h, 0.3 if absf(inward.z) > 0.5 else door_gap), at + Vector3(0, 2.3 + top_h * 0.5 - h * 0.5, 0) - inward * 0.15)
	for pc in pieces:
		var pw: float = pc[0]
		var c: Vector3 = pc[1]
		add_child(_panel(Vector2(pw, pc[2]), c, inward, color))
		var bs := Vector3(pw, h, 0.3) if absf(inward.z) > 0.5 else Vector3(0.3, h, pw)
		_shadow_box(bs, c - inward * 0.15)
		_wall_collider(bs, c - inward * 0.15)


func _panel(size2: Vector2, at: Vector3, inward: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size2
	mi.mesh = q
	mi.material_override = _mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	# QuadMesh faces +Z; turn it to face `inward`.
	mi.basis = Basis.looking_at(-inward, Vector3.UP)
	return mi


func _shadow_box(sz: Vector3, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	mi.position = at
	add_child(mi)


func _wall_collider(sz: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.PHYS_WALLS
	body.collision_mask = 0
	add_child(body)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = sz
	cs.shape = b
	cs.position = at
	body.add_child(cs)


func _box_collider(sz: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = sz
	cs.shape = b
	cs.position = at
	_body.add_child(cs)


func _wall_mesh(sz: Vector3, at: Vector3, color: Color, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = at
	add_child(mi)
	if collide:
		_wall_collider(sz, at)


static var _mat_cache := {}

func _mat(c: Color) -> StandardMaterial3D:
	if _mat_cache.has(c):
		return _mat_cache[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	_mat_cache[c] = m
	return m


func _floor_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/floor.gdshader")
	sm.set_shader_parameter("base", floor_color)
	sm.set_shader_parameter("tiles", floor_tiles)
	return sm

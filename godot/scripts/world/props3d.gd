class_name Props3D
extends RefCounted
## Hand-built chunky props (same bevelled-block style as the avatars):
## food, popcorn, signs, the chest, the cinema seats, the giant bed…

const A = preload("res://scripts/characters/avatar.gd")
static var _mats := {}


## Builds a static mesh from block parts: {size, at, color, rot?, taper?, bevel?, mat?, shade?}.
static func blocks(parts: Array) -> MeshInstance3D:
	var by_mat := {}
	for p in parts:
		var m: String = p.get("mat", "matte")
		if not by_mat.has(m):
			by_mat[m] = []
		by_mat[m].append(p)
	var mesh := ArrayMesh.new()
	for m in by_mat:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in by_mat[m]:
			_block(st, p)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(m))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


static func material(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match kind:
		"glow":
			m.emission_enabled = true
			m.emission_energy_multiplier = 1.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"gold":
			m.metallic = 0.85
			m.roughness = 0.25
		"glossy":
			m.roughness = 0.3
		_:
			m.roughness = 0.82
	_mats[kind] = m
	return m


static func _block(st: SurfaceTool, p: Dictionary) -> void:
	var size: Vector3 = p["size"]
	var h := size * 0.5
	var c := minf(float(p.get("bevel", 0.02)), minf(h.x, minf(h.y, h.z)) * 0.6)
	var at: Vector3 = p["at"]
	var col: Color = p["color"]
	var shade: float = p.get("shade", 0.08)
	var rot: Vector3 = p.get("rot", Vector3.ZERO)
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	var taper: Vector2 = p.get("taper", Vector2.ONE)
	var tris := A._bevel_box_tris(h, c)
	for i in range(0, tris.size(), 3):
		var vs: Array[Vector3] = []
		var us: Array[float] = []
		for k in 3:
			var v: Vector3 = tris[i + k]
			var u := (v.y + h.y) / size.y
			v = Vector3(v.x * lerpf(taper.x, 1.0, u), v.y, v.z * lerpf(taper.y, 1.0, u))
			vs.append(at + basis * v)
			us.append(u)
		var n := (vs[2] - vs[0]).cross(vs[1] - vs[0]).normalized()
		for k in 3:
			st.set_color(col.darkened(shade * (1.0 - us[k])))
			st.set_normal(n)
			st.add_vertex(vs[k])


static func b(size: Vector3, at: Vector3, color: Color, extra: Dictionary = {}) -> Dictionary:
	var d := {"size": size, "at": at, "color": color}
	d.merge(extra)
	return d


# ---------------------------------------------------------------------------
# Food & treats (sized for the characters' laps / tables, in model units ×1)
# ---------------------------------------------------------------------------

static func popcorn() -> Node3D:
	var parts := [b(Vector3(0.09, 0.11, 0.09), Vector3(0, 0.055, 0), Color(0.95, 0.25, 0.25), {"taper": Vector2(0.8, 0.8), "bevel": 0.01})]
	for i in 4:
		var a := i * PI * 0.5
		parts.append(b(Vector3(0.012, 0.11, 0.094), Vector3(cos(a) * 0.04, 0.055, sin(a) * 0.04), Color(1, 0.97, 0.92), {"rot": Vector3(0, rad_to_deg(-a), 0), "taper": Vector2(0.8, 0.8), "shade": 0.0}))
	for i in 9:
		parts.append(b(Vector3(0.03, 0.03, 0.03), Vector3(randf_range(-0.03, 0.03), 0.115 + randf() * 0.02, randf_range(-0.03, 0.03)), Color(1.0, 0.92, 0.6), {"rot": Vector3(randf() * 90, randf() * 90, 0), "bevel": 0.01, "shade": 0.0}))
	var n := Node3D.new()
	n.add_child(blocks(parts))
	return n


static func drink() -> Node3D:
	var parts := [
		b(Vector3(0.07, 0.12, 0.07), Vector3(0, 0.06, 0), Color(0.3, 0.55, 0.95), {"taper": Vector2(0.8, 0.8), "bevel": 0.01}),
		b(Vector3(0.075, 0.015, 0.075), Vector3(0, 0.125, 0), Color(1, 1, 1), {"shade": 0.0}),
		b(Vector3(0.008, 0.08, 0.008), Vector3(0.012, 0.16, 0), Color(1.0, 0.4, 0.45), {"rot": Vector3(0, 0, -12), "shade": 0.0}),
	]
	var n := Node3D.new()
	n.add_child(blocks(parts))
	return n


## A whole pizza (world units, ~0.7 m across) with pepperoni.
static func pizza(slices_missing: int = 0) -> Node3D:
	var n := Node3D.new()
	var crust := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.36
	cm.bottom_radius = 0.36
	cm.height = 0.04
	cm.radial_segments = 24
	crust.mesh = cm
	crust.material_override = _flat(Color(0.93, 0.72, 0.42))
	n.add_child(crust)
	var cheese := MeshInstance3D.new()
	var ch := CylinderMesh.new()
	ch.top_radius = 0.31
	ch.bottom_radius = 0.31
	ch.height = 0.045
	ch.radial_segments = 24
	cheese.mesh = ch
	cheese.material_override = _flat(Color(1.0, 0.86, 0.45))
	cheese.position.y = 0.005
	n.add_child(cheese)
	for i in 9:
		var p := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.045
		pm.bottom_radius = 0.045
		pm.height = 0.012
		p.mesh = pm
		p.material_override = _flat(Color(0.78, 0.18, 0.14))
		var a := i * TAU / 9.0 + 0.3
		var r := 0.12 + (i % 3) * 0.06
		p.position = Vector3(cos(a) * r, 0.032, sin(a) * r)
		n.add_child(p)
	var board := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.42
	bm.bottom_radius = 0.42
	bm.height = 0.03
	board.mesh = bm
	board.material_override = _flat(Color(0.65, 0.45, 0.28))
	board.position.y = -0.03
	n.add_child(board)
	return n


static func _flat(c: Color, rough: float = 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## The over-prepared picnic spread (world units, centred on the blanket).
static func picnic_feast() -> Node3D:
	var n := Node3D.new()
	var parts: Array = []
	# Cooler
	parts.append(b(Vector3(0.7, 0.45, 0.45), Vector3(-1.4, 0.225, -0.9), Color(0.3, 0.6, 0.9), {"bevel": 0.04}))
	parts.append(b(Vector3(0.74, 0.08, 0.49), Vector3(-1.4, 0.47, -0.9), Color(1, 1, 1), {"bevel": 0.03}))
	# Roast chicken
	parts.append(b(Vector3(0.36, 0.22, 0.28), Vector3(-0.35, 0.13, -0.35), Color(0.82, 0.52, 0.24), {"bevel": 0.08}))
	parts.append(b(Vector3(0.08, 0.08, 0.2), Vector3(-0.2, 0.2, -0.2), Color(0.85, 0.58, 0.3), {"rot": Vector3(30, 40, 0), "bevel": 0.03}))
	parts.append(b(Vector3(0.5, 0.03, 0.5), Vector3(-0.35, 0.015, -0.35), Color(1, 1, 1), {"shade": 0.0}))
	# Three cheeses
	for i in 3:
		parts.append(b(Vector3(0.18, 0.12, 0.14), Vector3(0.25 + i * 0.22, 0.06, -0.55), [Color(1, 0.88, 0.45), Color(1, 0.95, 0.75), Color(0.98, 0.75, 0.3)][i], {"taper": Vector2(1.0, 0.3), "bevel": 0.015}))
	# Baguette
	parts.append(b(Vector3(0.9, 0.12, 0.13), Vector3(0.6, 0.06, 0.45), Color(0.9, 0.66, 0.35), {"rot": Vector3(0, 25, 0), "bevel": 0.05}))
	# Potato salad + pasta bowls
	for i in 2:
		parts.append(b(Vector3(0.32, 0.12, 0.32), Vector3(-0.6 + i * 0.45, 0.06, 0.35), Color(1, 1, 1), {"taper": Vector2(0.7, 0.7), "bevel": 0.03}))
		parts.append(b(Vector3(0.28, 0.05, 0.28), Vector3(-0.6 + i * 0.45, 0.12, 0.35), [Color(1, 0.95, 0.65), Color(1.0, 0.75, 0.35)][i], {"bevel": 0.06, "shade": 0.0}))
	# Emergency backup ham
	parts.append(b(Vector3(0.38, 0.3, 0.3), Vector3(0.0, 0.15, 0.85), Color(0.95, 0.55, 0.6), {"bevel": 0.1}))
	parts.append(b(Vector3(0.06, 0.06, 0.18), Vector3(0.22, 0.2, 0.85), Color(1, 0.97, 0.93), {"rot": Vector3(0, 90, 0), "bevel": 0.02}))
	# Grapes and the single strawberry
	for i in 7:
		parts.append(b(Vector3(0.06, 0.06, 0.06), Vector3(0.85 + (i % 3) * 0.05, 0.03 + (i / 3) * 0.04, -0.1 + (i % 2) * 0.04), Color(0.55, 0.3, 0.75), {"bevel": 0.025, "shade": 0.0}))
	parts.append(b(Vector3(0.07, 0.08, 0.07), Vector3(1.05, 0.04, 0.2), Color(0.95, 0.2, 0.25), {"taper": Vector2(0.4, 0.4), "bevel": 0.02}))
	parts.append(b(Vector3(0.07, 0.015, 0.07), Vector3(1.05, 0.085, 0.2), Color(0.3, 0.7, 0.3), {"shade": 0.0}))
	n.add_child(blocks(parts))
	return n


static func boombox() -> Node3D:
	var n := Node3D.new()
	n.add_child(blocks([
		b(Vector3(0.5, 0.28, 0.16), Vector3(0, 0.14, 0), Color(0.95, 0.45, 0.5), {"bevel": 0.03}),
		b(Vector3(0.12, 0.12, 0.02), Vector3(-0.14, 0.14, 0.085), Color(0.2, 0.2, 0.25), {"bevel": 0.04, "shade": 0.0}),
		b(Vector3(0.12, 0.12, 0.02), Vector3(0.14, 0.14, 0.085), Color(0.2, 0.2, 0.25), {"bevel": 0.04, "shade": 0.0}),
		b(Vector3(0.36, 0.03, 0.03), Vector3(0, 0.34, 0), Color(0.3, 0.3, 0.35), {"shade": 0.0}),
	]))
	return n


# ---------------------------------------------------------------------------
# Furniture & fixtures
# ---------------------------------------------------------------------------

static func chest() -> Node3D:
	var n := Node3D.new()
	var wood := Color(0.62, 0.38, 0.2)
	var gold := Color(1.0, 0.8, 0.3)
	n.add_child(blocks([
		b(Vector3(1.0, 0.55, 0.65), Vector3(0, 0.275, 0), wood, {"bevel": 0.04}),
		b(Vector3(1.04, 0.08, 0.69), Vector3(0, 0.05, 0), gold, {"mat": "gold", "shade": 0.0}),
		b(Vector3(0.08, 0.57, 0.69), Vector3(-0.35, 0.29, 0), gold, {"mat": "gold", "shade": 0.0}),
		b(Vector3(0.08, 0.57, 0.69), Vector3(0.35, 0.29, 0), gold, {"mat": "gold", "shade": 0.0}),
	]))
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.55, -0.32)
	lid.add_child(blocks([
		b(Vector3(1.0, 0.25, 0.65), Vector3(0, 0.12, 0.32), wood.lightened(0.05), {"bevel": 0.06, "taper": Vector2(1.0, 1.0)}),
		b(Vector3(0.14, 0.14, 0.04), Vector3(0, 0.0, 0.66), gold, {"mat": "gold", "shade": 0.0}),
	]))
	n.add_child(lid)
	return n


static func cinema_seat(color: Color = Color(0.78, 0.15, 0.2)) -> Node3D:
	var n := Node3D.new()
	n.add_child(blocks([
		b(Vector3(0.7, 0.18, 0.6), Vector3(0, 0.38, 0.05), color, {"bevel": 0.05}),
		b(Vector3(0.7, 0.8, 0.16), Vector3(0, 0.62, -0.25), color, {"bevel": 0.06}),
		b(Vector3(0.1, 0.5, 0.6), Vector3(-0.38, 0.4, 0.0), Color(0.25, 0.22, 0.25), {"bevel": 0.03}),
		b(Vector3(0.1, 0.5, 0.6), Vector3(0.38, 0.4, 0.0), Color(0.25, 0.22, 0.25), {"bevel": 0.03}),
		b(Vector3(0.5, 0.3, 0.4), Vector3(0, 0.15, -0.05), Color(0.2, 0.18, 0.2), {"bevel": 0.03}),
	]))
	return n


## The enormous hotel bed (about 4 × 4.6 m) with a mountain of pillows.
static func giant_bed() -> Node3D:
	var n := Node3D.new()
	var parts := [
		b(Vector3(4.0, 0.5, 4.6), Vector3(0, 0.25, 0), Color(0.55, 0.38, 0.28), {"bevel": 0.08}),
		b(Vector3(3.8, 0.4, 4.4), Vector3(0, 0.68, 0.05), Color(0.98, 0.97, 0.95), {"bevel": 0.15}),
		b(Vector3(3.84, 0.12, 2.6), Vector3(0, 0.86, 0.85), Color(0.75, 0.86, 0.95), {"bevel": 0.08}),
		b(Vector3(4.2, 1.6, 0.25), Vector3(0, 0.8, -2.35), Color(0.55, 0.38, 0.28), {"bevel": 0.1}),
	]
	for i in 12:
		var x := -1.55 + (i % 6) * 0.62
		var row := i / 6
		parts.append(b(Vector3(0.6, 0.32, 0.36), Vector3(x, 1.05 + row * 0.25, -1.9 + row * 0.25), Color(1, 1, 1) if i % 3 else Color(0.95, 0.85, 0.75), {"bevel": 0.12, "rot": Vector3(-15, 0, 0), "shade": 0.04}))
	n.add_child(blocks(parts))
	return n


## A shop sign: coloured board with a big label.
static func sign(text: String, bg: Color, fg: Color = Color(1, 1, 1), width: float = 4.0, height: float = 0.9) -> Node3D:
	var n := Node3D.new()
	n.add_child(blocks([b(Vector3(width, height, 0.15), Vector3.ZERO, bg, {"bevel": 0.06})]))
	var l := Label3D.new()
	l.text = text
	l.font = Game.hud._title_font if Game.hud else null
	l.font_size = 96
	l.pixel_size = height / 140.0
	l.modulate = fg
	l.outline_size = 0
	l.position = Vector3(0, 0, 0.08)
	n.add_child(l)
	return n


static func room_label(text: String, size: float = 0.006, color: Color = Color(0.36, 0.27, 0.2)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	if Game.hud:
		l.font = Game.hud._bold_font
	l.font_size = 48
	l.pixel_size = size
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(1, 1, 1, 0.8)
	l.double_sided = false   # dollhouse rooms: hidden from behind instead of mirrored
	return l

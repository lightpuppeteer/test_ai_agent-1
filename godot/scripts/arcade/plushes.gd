class_name Plushes
extends RefCounted
## Soft little plush toys (claw machine prizes): Yoggi, a pizza slice, a
## volcano, a heart, a bunny and a penguin. Built from rounded boxes; about
## 0.4 m tall at scale 1, origin at the bottom centre, facing +Z.
## Won plushes sit on a shelf in the living room of our house.

const KINDS := ["yoggi", "pizza", "volcano", "heart", "bunny", "penguin"]
const NAMES := {"yoggi": "Yoggi plush", "pizza": "pizza slice plush", "volcano": "volcano plush",
	"heart": "heart plush", "bunny": "bunny plush", "penguin": "penguin plush"}

const BLACK := Color(0.12, 0.1, 0.12)
const BLUSH := Color(1.0, 0.6, 0.65)

static var _cache := {}


static func build(kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind)
	mi.name = "Plush_" + kind
	return mi


static func mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var soft := SurfaceTool.new()
	soft.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shiny := SurfaceTool.new()
	shiny.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"yoggi":
			var fur := Color(0.6, 0.63, 0.69)
			var light := Color(0.78, 0.8, 0.84)
			_s(soft, Vector3(0.34, 0.24, 0.28), Vector3(0, 0.13, -0.02), fur, 0.11)
			_s(soft, Vector3(0.32, 0.27, 0.27), Vector3(0, 0.36, 0.03), fur, 0.12)
			for sx in [-1.0, 1.0]:
				_s(soft, Vector3(0.09, 0.1, 0.05), Vector3(sx * 0.095, 0.5, 0.02), fur, 0.03, Vector2(0.25, 1.0), Vector3(0, 0, -sx * 14.0))
				_s(soft, Vector3(0.08, 0.06, 0.08), Vector3(sx * 0.08, 0.035, 0.12), light, 0.035)
				_s(shiny, Vector3(0.06, 0.07, 0.02), Vector3(sx * 0.065, 0.38, 0.165), Color(0.35, 0.78, 0.38), 0.025)
				_s(shiny, Vector3(0.022, 0.05, 0.02), Vector3(sx * 0.065, 0.38, 0.172), BLACK, 0.01)
				_s(soft, Vector3(0.05, 0.025, 0.01), Vector3(sx * 0.11, 0.32, 0.165), BLUSH, 0.01)
			_s(soft, Vector3(0.15, 0.08, 0.03), Vector3(0, 0.31, 0.16), light, 0.035)
			_s(soft, Vector3(0.035, 0.025, 0.02), Vector3(0, 0.335, 0.177), Color(0.9, 0.55, 0.6), 0.01)
			_s(soft, Vector3(0.06, 0.06, 0.22), Vector3(0.11, 0.08, -0.18), fur.darkened(0.12), 0.03, Vector2.ONE, Vector3(0, -25, 0))
		"pizza":
			_s(soft, Vector3(0.34, 0.36, 0.09), Vector3(0, 0.24, 0), Color(1.0, 0.84, 0.42), 0.04, Vector2(0.12, 1.0))
			_s(soft, Vector3(0.4, 0.09, 0.12), Vector3(0, 0.05, 0), Color(0.88, 0.6, 0.32), 0.045)
			for p in [Vector2(-0.07, 0.15), Vector2(0.08, 0.13), Vector2(0.0, 0.3)]:
				_s(soft, Vector3(0.06, 0.06, 0.02), Vector3(p.x, p.y, 0.05), Color(0.82, 0.22, 0.18), 0.028)
			for sx in [-1.0, 1.0]:
				_s(shiny, Vector3(0.03, 0.04, 0.02), Vector3(sx * 0.045, 0.22, 0.05), BLACK, 0.012)
				_s(soft, Vector3(0.04, 0.02, 0.01), Vector3(sx * 0.09, 0.19, 0.05), BLUSH, 0.008)
			_s(soft, Vector3(0.04, 0.012, 0.01), Vector3(0, 0.19, 0.05), Color(0.6, 0.25, 0.2), 0.005)
		"volcano":
			_s(soft, Vector3(0.4, 0.34, 0.36), Vector3(0, 0.17, 0), Color(0.62, 0.5, 0.48), 0.08, Vector2(0.45, 0.45))
			_s(soft, Vector3(0.17, 0.06, 0.15), Vector3(0, 0.345, 0), Color(1.0, 0.45, 0.2), 0.03)
			for i in 3:
				_s(soft, Vector3(0.04, 0.12 - i * 0.02, 0.03), Vector3(-0.05 + i * 0.05, 0.3, 0.1 - absf(i - 1) * 0.02), Color(1.0, 0.55, 0.22), 0.015)
			for sx in [-1.0, 1.0]:
				_s(shiny, Vector3(0.035, 0.045, 0.02), Vector3(sx * 0.055, 0.17, 0.155), BLACK, 0.014)
				_s(soft, Vector3(0.05, 0.025, 0.01), Vector3(sx * 0.11, 0.13, 0.15), BLUSH, 0.01)
			_s(soft, Vector3(0.06, 0.02, 0.01), Vector3(0, 0.12, 0.165), Color(0.4, 0.2, 0.2), 0.008)
		"heart":
			var pink := Color(1.0, 0.45, 0.55)
			for sx in [-1.0, 1.0]:
				_s(soft, Vector3(0.21, 0.21, 0.14), Vector3(sx * 0.075, 0.3, 0), pink, 0.1)
				_s(shiny, Vector3(0.035, 0.05, 0.02), Vector3(sx * 0.05, 0.24, 0.07), BLACK, 0.014)
				_s(soft, Vector3(0.05, 0.025, 0.01), Vector3(sx * 0.1, 0.2, 0.068), Color(1.0, 0.75, 0.8), 0.01)
			_s(soft, Vector3(0.2, 0.2, 0.135), Vector3(0, 0.17, 0), pink, 0.05, Vector2.ONE, Vector3(0, 0, 45))
		"bunny":
			var w := Color(0.98, 0.97, 0.95)
			_s(soft, Vector3(0.28, 0.22, 0.24), Vector3(0, 0.11, 0), w, 0.1)
			_s(soft, Vector3(0.26, 0.23, 0.22), Vector3(0, 0.31, 0.02), w, 0.1)
			for sx in [-1.0, 1.0]:
				_s(soft, Vector3(0.07, 0.22, 0.05), Vector3(sx * 0.06, 0.5, 0.0), w, 0.033, Vector2.ONE, Vector3(0, 0, -sx * 8.0))
				_s(soft, Vector3(0.035, 0.16, 0.01), Vector3(sx * 0.06, 0.5, 0.026), Color(1.0, 0.75, 0.8), 0.015, Vector2.ONE, Vector3(0, 0, -sx * 8.0))
				_s(shiny, Vector3(0.035, 0.045, 0.02), Vector3(sx * 0.055, 0.33, 0.13), BLACK, 0.014)
				_s(soft, Vector3(0.045, 0.022, 0.01), Vector3(sx * 0.09, 0.28, 0.128), BLUSH, 0.01)
			_s(soft, Vector3(0.03, 0.02, 0.02), Vector3(0, 0.3, 0.135), Color(1.0, 0.55, 0.65), 0.008)
			_s(soft, Vector3(0.08, 0.08, 0.06), Vector3(0, 0.08, -0.13), w, 0.04)
		"penguin":
			var navy := Color(0.18, 0.22, 0.34)
			_s(soft, Vector3(0.3, 0.4, 0.26), Vector3(0, 0.2, 0), navy, 0.12)
			_s(soft, Vector3(0.22, 0.28, 0.04), Vector3(0, 0.17, 0.115), Color(0.98, 0.98, 0.98), 0.06)
			_s(soft, Vector3(0.22, 0.1, 0.04), Vector3(0, 0.3, 0.112), Color(0.98, 0.98, 0.98), 0.04)
			_s(soft, Vector3(0.07, 0.04, 0.07), Vector3(0, 0.27, 0.15), Color(1.0, 0.65, 0.2), 0.02)
			for sx in [-1.0, 1.0]:
				_s(shiny, Vector3(0.035, 0.045, 0.02), Vector3(sx * 0.05, 0.32, 0.136), BLACK, 0.014)
				_s(soft, Vector3(0.07, 0.03, 0.09), Vector3(sx * 0.07, 0.015, 0.08), Color(1.0, 0.65, 0.2), 0.014)
				_s(soft, Vector3(0.05, 0.18, 0.1), Vector3(sx * 0.16, 0.2, 0), navy, 0.025, Vector2.ONE, Vector3(0, 0, sx * 12.0))
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, soft.commit_to_arrays())
	m.surface_set_material(0, _mat(false))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shiny.commit_to_arrays())
	m.surface_set_material(1, _mat(true))
	_cache[kind] = m
	return m


static var _mats := {}

static func _mat(glossy: bool) -> StandardMaterial3D:
	if _mats.has(glossy):
		return _mats[glossy]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.3 if glossy else 0.95
	_mats[glossy] = m
	return m


## Soft rounded box; taper narrows the top (x, z); rot in degrees.
static func _s(st: SurfaceTool, size: Vector3, at: Vector3, col: Color, r: float, taper: Vector2 = Vector2.ONE, rot: Vector3 = Vector3.ZERO) -> void:
	var h := size * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.98)
	var rb: Array = Avatar._round_box(h, r)
	var pos: PackedVector3Array = rb[0]
	var nrm: PackedVector3Array = rb[1]
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	for i in pos.size():
		var v: Vector3 = pos[i]
		var u := (v.y + h.y) / size.y
		v.x *= lerpf(1.0, taper.x, u)
		v.z *= lerpf(1.0, taper.y, u)
		st.set_color(col.darkened(0.08 * (1.0 - u)))
		st.set_normal((basis * nrm[i]).normalized())
		st.add_vertex(at + basis * v)


# ---------------------------------------------------------------------------
# The plush shelf in our house
# ---------------------------------------------------------------------------

static func won() -> Array:
	if Game.quests == null:
		return []
	return Game.quests.flags.get("plushes", [])


static func add_won(kind: String) -> void:
	if Game.quests == null:
		return
	var list: Array = Game.quests.flags.get("plushes", [])
	list.append(kind)
	Game.quests.flags["plushes"] = list
	Game.quests.save_now()
	refresh_house()


## A floating shelf on the living-room wall with one of each plush won.
static func refresh_house() -> void:
	var house: Interior = Places.interiors.get("house")
	if house == null:
		return
	var old := house.get_node_or_null("PlushShelf")
	if old:
		old.queue_free()
	var kinds: Array = []
	for k in won():
		if k not in kinds:
			kinds.append(k)
	if kinds.is_empty():
		return
	var shelf := Node3D.new()
	shelf.name = "PlushShelf"
	house.add_child(shelf)
	# On the left (-X) wall of the living room, facing into the room.
	shelf.position = Vector3(-house.size.x * 0.5 + 0.14, 1.75, 0.7)
	shelf.rotation.y = PI * 0.5
	shelf.add_child(Props3D.blocks([
		Props3D.b(Vector3(2.5, 0.06, 0.32), Vector3(0, 0, 0.12), Color(0.85, 0.66, 0.46), {"bevel": 0.02}),
		Props3D.b(Vector3(0.05, 0.16, 0.2), Vector3(-1.0, -0.1, 0.06), Color(0.75, 0.55, 0.38), {"bevel": 0.01}),
		Props3D.b(Vector3(0.05, 0.16, 0.2), Vector3(1.0, -0.1, 0.06), Color(0.75, 0.55, 0.38), {"bevel": 0.01}),
	]))
	for i in kinds.size():
		var p := build(kinds[i])
		shelf.add_child(p)
		p.scale = Vector3.ONE * 0.85
		p.position = Vector3(-1.0 + (i + 0.5) * 2.0 / maxf(kinds.size(), 1.0), 0.03, 0.14)
		p.rotation.y = randf_range(-0.25, 0.25)

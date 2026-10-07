class_name Props
extends RefCounted
## Asset catalogue helpers: load Kenney GLBs by short id ("nature-kit/tree_oak"),
## place them with a world scale, add simple colliders, swap in the wind-sway
## shader and recolour palette textures.

const ROOT := "res://assets/kenney/"
const SWAY_SHADER := preload("res://shaders/foliage_sway.gdshader")

## Per-kit default scale so that everything matches the 1.25 m tall characters.
const KIT_SCALE := {
	"nature-kit": 3.2,
	"fantasy-town-kit": 2.4,
	"city-kit-suburban": 4.2,
	"pirate-kit": 1.3,
	"watercraft-kit": 1.25,
	"holiday-kit": 1.6,
	"survival-kit": 2.6,
	"furniture-kit": 2.2,
	"car-kit": 1.25,
	"cube-pets": 0.7,
	"mini-characters": 1.6,
}

static var _scenes := {}
static var _aabbs := {}
static var _meshes := {}
static var _recolored := {}


static func path(id: String) -> String:
	return ROOT + id + ".glb"


static func scene(id: String) -> PackedScene:
	if not _scenes.has(id):
		var ps: PackedScene = load(path(id))
		if ps == null:
			push_error("Props: missing asset " + id)
		_scenes[id] = ps
	return _scenes[id]


static func kit_scale(id: String) -> float:
	return KIT_SCALE.get(id.get_slice("/", 0), 1.0)


## Instantiates the raw model (no scale applied).
static func model(id: String) -> Node3D:
	var ps := scene(id)
	return ps.instantiate() if ps else Node3D.new()


## Bounding box of a model in its own (unscaled) space.
static func model_aabb(id: String) -> AABB:
	if not _aabbs.has(id):
		var n := model(id)
		_aabbs[id] = node_aabb(n)
		n.free()
	return _aabbs[id]


static func node_aabb(root: Node, xf: Transform3D = Transform3D.IDENTITY) -> AABB:
	var out := [null]
	_collect_aabb(root, xf, out, true)
	return out[0] if out[0] != null else AABB()


static func _collect_aabb(n: Node, t: Transform3D, out: Array, is_root: bool) -> void:
	if n is Node3D and not is_root:
		t = t * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		out[0] = a if out[0] == null else (out[0] as AABB).merge(a)
	for c in n.get_children():
		_collect_aabb(c, t, out, false)


## Places a prop. Returns the unscaled root (a Node3D) whose child "Model" is scaled.
## collide: "" (none), "box", "cylinder" or "mesh" (trimesh, static only).
static func place(parent: Node, id: String, pos: Vector3, yaw_deg: float = 0.0, scale_mul: float = 1.0,
		collide: String = "", opts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = id.get_file().to_pascal_case()
	parent.add_child(root)
	root.position = pos
	root.rotation.y = deg_to_rad(yaw_deg)
	var s := kit_scale(id) * scale_mul
	var m := model(id)
	m.name = "Model"
	m.scale = Vector3.ONE * s
	root.add_child(m)
	if opts.get("sway", 0.0) > 0.0 or id.begins_with("nature-kit/"):
		restyle(m, opts.get("sway", 0.0), opts.get("sway_only", ""))
	if opts.has("recolor"):
		recolor(m, opts["recolor"])
	if collide != "":
		add_collider(root, id, s, collide, opts.get("collider_shrink", 1.0))
	return root


static func add_collider(root: Node3D, id: String, s: float, kind: String, shrink: float = 1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = Game.PHYS_PROPS
	body.collision_mask = 0
	root.add_child(body)
	var bb := model_aabb(id)
	var size := bb.size * s
	var center := bb.get_center() * s
	match kind:
		"box":
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(size.x * shrink, size.y, size.z * shrink)
			cs.shape = sh
			cs.position = center
			body.add_child(cs)
		"cylinder":
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = max(size.x, size.z) * 0.5 * shrink
			sh.height = size.y
			cs.shape = sh
			cs.position = Vector3(center.x, center.y, center.z)
			body.add_child(cs)
		"trunk":
			# Thin cylinder at the base of trees: walk under the canopy, bump the trunk.
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = max(0.25, min(size.x, size.z) * 0.09) * shrink
			sh.height = size.y * 0.6
			cs.shape = sh
			cs.position = Vector3(center.x, size.y * 0.3, center.z)
			body.add_child(cs)
		"mesh":
			var model_node := root.get_node("Model")
			for mi in _mesh_instances(model_node):
				var cs := CollisionShape3D.new()
				cs.shape = mi.mesh.create_trimesh_shape()
				cs.transform = root.global_transform.affine_inverse() * mi.global_transform if root.is_inside_tree() \
						else _relative_xf(root, mi)
				body.add_child(cs)
	return body


static func _relative_xf(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


static func _mesh_instances(n: Node, out: Array = []) -> Array:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_mesh_instances(c, out)
	return out


## First mesh of a model plus its transform relative to the model root (for MultiMesh scattering).
static func mesh_of(id: String) -> Array:
	if not _meshes.has(id):
		var n := model(id)
		var mis := _mesh_instances(n)
		if mis.is_empty():
			_meshes[id] = [null, Transform3D.IDENTITY]
		else:
			_meshes[id] = [mis[0].mesh, _relative_xf(n, mis[0])]
		n.free()
	return _meshes[id]


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

## Replaces materials with the wind-sway shader. `only` restricts to material names
## containing that substring (e.g. "leaf"); empty sways the whole model.
static func apply_sway(model_root: Node, strength: float, only: String = "") -> void:
	var bb := node_aabb(model_root)
	for mi in _mesh_instances(model_root):
		var mesh: Mesh = mi.mesh
		for si in mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			if only != "" and (mat == null or not mat.resource_name.to_lower().contains(only)):
				continue
			mi.set_surface_override_material(si, sway_material(mat, strength, max(bb.size.y, 0.01), bb.position.y))


static var _sway_cache := {}
static var _restyle_cache := {}
static var _restyled_meshes := {}

## Brighter, warmer colours for the nature kit (its teal greens read cold next to the AC-style palette).
const NATURE_PALETTE := {
	"leafsGreen": Color(0.45, 0.78, 0.31),
	"leafsDark": Color(0.29, 0.62, 0.31),
	"leafsFall": Color(0.98, 0.62, 0.30),
	"grass": Color(0.47, 0.80, 0.33),
	"stone": Color(0.80, 0.79, 0.76),
	"stoneDark": Color(0.64, 0.64, 0.65),
	"woodBark": Color(0.62, 0.43, 0.31),
	"woodBarkDark": Color(0.52, 0.36, 0.28),
	"wood": Color(0.80, 0.56, 0.38),
	"colorRed": Color(0.98, 0.40, 0.46),
	"colorRedDark": Color(0.86, 0.30, 0.36),
	"colorYellow": Color(1.0, 0.84, 0.32),
	"colorPurple": Color(0.74, 0.56, 1.0),
	"colorWhite": Color(1.0, 0.98, 0.95),
}


## Applies the palette and (optionally) the sway shader to every surface of a model.
static func restyle(model_root: Node, sway: float = 0.0, sway_only: String = "") -> void:
	var bb := node_aabb(model_root)
	for mi in _mesh_instances(model_root):
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			var nm := mat.resource_name if mat else ""
			var m2 := styled_material(mat, sway if (sway_only == "" or nm.to_lower().contains(sway_only)) else 0.0, bb)
			if m2 != mat:
				mi.set_surface_override_material(si, m2)


static func styled_material(mat: Material, sway: float, bb: AABB) -> Material:
	var nm := mat.resource_name if mat else ""
	var col = NATURE_PALETTE.get(nm, null)
	if sway > 0.0:
		var sm := sway_material(mat, sway, maxf(bb.size.y, 0.01), bb.position.y)
		if col != null:
			sm = sm.duplicate()
			sm.set_shader_parameter("albedo", col)
		return sm
	if col != null and mat is BaseMaterial3D:
		if not _restyle_cache.has(nm):
			var d: BaseMaterial3D = mat.duplicate()
			d.albedo_color = col
			d.roughness = 0.85
			_restyle_cache[nm] = d
		return _restyle_cache[nm]
	return mat


## A copy of a model's first mesh with palette/sway materials baked in (for MultiMesh).
static func restyled_mesh(id: String, sway: float = 0.0) -> Array:
	var key := id + "|" + str(sway)
	if not _restyled_meshes.has(key):
		var src: Array = mesh_of(id)
		var mesh: Mesh = src[0]
		if mesh == null:
			return [null, Transform3D.IDENTITY]
		var copy: ArrayMesh = mesh.duplicate()
		var bb := mesh.get_aabb()
		for si in copy.get_surface_count():
			copy.surface_set_material(si, styled_material(mesh.surface_get_material(si), sway, bb))
		_restyled_meshes[key] = [copy, src[1]]
	return _restyled_meshes[key]

static func sway_material(src: Material, strength: float, height: float, base: float = 0.0) -> ShaderMaterial:
	var key := [src, snappedf(strength, 0.01), snappedf(height, 0.01), snappedf(base, 0.01)]
	if _sway_cache.has(key):
		return _sway_cache[key]
	var sm := ShaderMaterial.new()
	sm.shader = SWAY_SHADER
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		sm.set_shader_parameter("albedo", b.albedo_color)
		if b.albedo_texture:
			sm.set_shader_parameter("albedo_tex", b.albedo_texture)
			sm.set_shader_parameter("use_tex", true)
	sm.set_shader_parameter("strength", strength)
	sm.set_shader_parameter("height", height)
	sm.set_shader_parameter("base", base)
	_sway_cache[key] = sm
	return sm


## Recolours a palette-textured model. `mapping` is {Color(from): Color(to)}; pixels
## within a small distance of `from` are replaced (keeping their shading offset).
static func recolor(model_root: Node, mapping: Dictionary) -> void:
	for mi in _mesh_instances(model_root):
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			if not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).albedo_texture == null:
				continue
			mi.set_surface_override_material(si, _recolored_material(mat, mapping))


const PALETTE_SWAP := preload("res://shaders/palette_swap.gdshader")

static func _recolored_material(mat: BaseMaterial3D, mapping: Dictionary) -> Material:
	var key := [mat, str(mapping)]
	if _recolored.has(key):
		return _recolored[key]
	var sm := ShaderMaterial.new()
	sm.shader = PALETTE_SWAP
	sm.set_shader_parameter("albedo_tex", mat.albedo_texture)
	sm.set_shader_parameter("uv_scale", mat.uv1_scale)
	sm.set_shader_parameter("uv_offset", mat.uv1_offset)
	var keys := mapping.keys()
	sm.set_shader_parameter("from_a", keys[0])
	sm.set_shader_parameter("to_a", mapping[keys[0]])
	if keys.size() > 1:
		sm.set_shader_parameter("use_b", true)
		sm.set_shader_parameter("from_b", keys[1])
		sm.set_shader_parameter("to_b", mapping[keys[1]])
	_recolored[key] = sm
	return sm

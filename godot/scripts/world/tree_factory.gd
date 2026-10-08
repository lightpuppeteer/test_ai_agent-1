class_name TreeFactory
extends RefCounted
## Soft, rounded storybook trees (Animal Crossing style): chunky tapered trunks
## with puffy canopies, cedars of stacked rounded cones, and fruit trees.
## Meshes are generated once per variant and shared.

const LEAF_GREENS := [Color(0.34, 0.62, 0.32), Color(0.4, 0.66, 0.33), Color(0.3, 0.58, 0.34), Color(0.45, 0.68, 0.32)]
const CEDAR_GREENS := [Color(0.22, 0.55, 0.36), Color(0.27, 0.6, 0.38)]
const BARK := Color(0.55, 0.38, 0.25)
const FRUITS := {"orange": Color(1.0, 0.6, 0.15), "apple": Color(0.9, 0.2, 0.2), "peach": Color(1.0, 0.7, 0.62), "pear": Color(0.75, 0.85, 0.3), "cherry": Color(0.85, 0.12, 0.25)}

static var _meshes := {}
static var _mat: Material


static func material() -> Material:
	if _mat == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.9
		m.set_meta("near_fade", true)     # dissolve if the camera slips into a canopy
		_mat = m
	return _mat


## kind: "round" | "cedar" | "fruit". Returns a Node3D (mesh + trunk collider),
## about 4 m tall at scale 1.
static func make(kind: String, variant: int, fruit: String = "") -> Node3D:
	var key := "%s_%d_%s" % [kind, variant, fruit]
	if not _meshes.has(key):
		_meshes[key] = _build(kind, variant, fruit)
	var n := Node3D.new()
	n.name = "Tree"
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	n.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Game.PHYS_PROPS
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.32
	cyl.height = 2.2
	cs.shape = cyl
	cs.position.y = 1.1
	body.add_child(cs)
	n.add_child(body)
	return n


static func _build(kind: String, variant: int, fruit: String) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"cedar":
			_trunk(st, 0.22, 0.13, 1.3, rng)
			var g: Color = CEDAR_GREENS[variant % CEDAR_GREENS.size()]
			var y := 0.9
			var r := 1.45
			for i in 4:
				var h := 1.35 - i * 0.12
				_cone(st, Vector3(0, y, 0), r, h, g.lightened(i * 0.05), g.darkened(0.18))
				y += h * 0.55
				r *= 0.74
			_blob(st, Vector3(0, y + 0.15, 0), 0.22, g.lightened(0.18), g, rng, 0.0)
		_:
			_trunk(st, 0.26, 0.16, 1.9, rng)
			var g: Color = LEAF_GREENS[variant % LEAF_GREENS.size()]
			# A puffy cloud of leaf balls: big middle, a ring, a crown.
			var centre := Vector3(0, 2.75, 0)
			_blob(st, centre, 1.25, g.lightened(0.08), g.darkened(0.2), rng, 0.06)
			var ring := 5 + variant % 2
			var tops: Array[Vector3] = []
			for i in ring:
				var a := TAU * i / ring + rng.randf() * 0.4
				var p := centre + Vector3(cos(a) * 0.95, rng.randf_range(-0.35, 0.05), sin(a) * 0.95)
				var r := rng.randf_range(0.7, 0.88)
				_blob(st, p, r, g.lightened(0.05), g.darkened(0.25), rng, 0.05)
				tops.append(p + Vector3(0, r * 0.8, 0) + (p - centre).normalized() * r * 0.4)
			var crown := centre + Vector3(rng.randf_range(-0.2, 0.2), 0.95, rng.randf_range(-0.2, 0.2))
			_blob(st, crown, 0.85, g.lightened(0.16), g.darkened(0.05), rng, 0.05)
			if kind == "fruit" and FRUITS.has(fruit):
				var fc: Color = FRUITS[fruit]
				for i in 6:
					var a := TAU * i / 6.0 + 0.3
					var p := centre + Vector3(cos(a) * 1.55, rng.randf_range(-0.35, 0.45), sin(a) * 1.55)
					_blob(st, p, 0.17, fc.lightened(0.15), fc.darkened(0.1), rng, 0.0, 8, 6)
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	return mesh


## A tapered trunk with a little root flare and a slight lean.
static func _trunk(st: SurfaceTool, r0: float, r1: float, h: float, rng: RandomNumberGenerator) -> void:
	var lean := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
	var prof: Array[Vector2] = [Vector2(r0 * 1.35, 0.0), Vector2(r0 * 1.05, 0.12), Vector2(r0, 0.3), Vector2((r0 + r1) * 0.5, h * 0.6), Vector2(r1, h), Vector2(r1 * 0.6, h + 0.3)]
	_lathe(st, Vector3.ZERO, prof, 10, BARK.lightened(0.05), BARK.darkened(0.2), lean / h)


## A rounded cone (cedar layer): wide soft rim, pointed top.
static func _cone(st: SurfaceTool, base: Vector3, r: float, h: float, top: Color, bottom: Color) -> void:
	var prof: Array[Vector2] = [Vector2(0.0, -0.05), Vector2(r * 0.85, 0.0), Vector2(r, 0.1), Vector2(r * 0.92, 0.22), Vector2(r * 0.55, h * 0.55), Vector2(r * 0.15, h * 0.92), Vector2(0.0, h)]
	_lathe(st, base, prof, 16, top, bottom, Vector3.ZERO)


## Surface of revolution around Y from (radius, height) profile points.
static func _lathe(st: SurfaceTool, base: Vector3, prof: Array[Vector2], seg: int, top: Color, bottom: Color, shear: Vector3) -> void:
	var hmin := prof[0].y
	var hmax := prof[prof.size() - 1].y
	for i in prof.size() - 1:
		var a := prof[i]
		var b := prof[i + 1]
		# Profile normal (outward, in the r-y plane).
		var t := (b - a).normalized()
		var n2 := Vector2(t.y, -t.x)
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var quad: Array[Vector3] = []
			var norms: Array[Vector3] = []
			var cols: Array[Color] = []
			for q: Vector2 in [Vector2(0, a0), Vector2(1, a0), Vector2(1, a1), Vector2(0, a1)]:
				var p := a if q.x == 0.0 else b
				var ang := q.y
				var dir := Vector3(cos(ang), 0, sin(ang))
				quad.append(base + dir * p.x + Vector3(0, p.y, 0) + shear * p.y)
				norms.append((dir * n2.x + Vector3(0, n2.y, 0)).normalized())
				cols.append(bottom.lerp(top, clampf((p.y - hmin) / maxf(hmax - hmin, 0.01), 0.0, 1.0)))
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_color(cols[idx])
				st.set_normal(norms[idx])
				st.add_vertex(quad[idx])


## A soft, slightly lumpy ball of leaves (smooth normals, lighter on top).
static func _blob(st: SurfaceTool, c: Vector3, r: float, top: Color, bottom: Color, rng: RandomNumberGenerator, lump: float, seg: int = 14, rings: int = 9) -> void:
	var phase := rng.randf() * TAU
	var verts := []
	for j in rings + 1:
		var v := float(j) / rings
		var phi := v * PI
		var row := []
		for i in seg + 1:
			var u := float(i) / seg
			var th := u * TAU
			var dir := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var rr := r * (1.0 + lump * sin(th * 3.0 + phase) * sin(phi * 2.0 + phase))
			if dir.y < -0.3:
				rr *= 0.92     # a slightly flatter underside
			row.append([c + dir * rr, dir, bottom.lerp(top, clampf(dir.y * 0.5 + 0.5, 0.0, 1.0))])
		verts.append(row)
	for j in rings:
		for i in seg:
			var q := [verts[j][i], verts[j + 1][i], verts[j + 1][i + 1], verts[j][i + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var vv: Array = q[idx]
				st.set_color(vv[2])
				st.set_normal(vv[1])
				st.add_vertex(vv[0])

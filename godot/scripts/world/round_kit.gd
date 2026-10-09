class_name RoundKit
extends RefCounted
## Soft, rounded replacements for the blocky Kenney props (Animal Crossing
## style): flowers with round petals, leafy grass tufts, puffy bushes, smooth
## boulders, dotted mushrooms, palm trees, round lamp posts, a cosy park bench,
## hedges, fences and planters. Each one fits the original model's bounding
## box, so placement, colliders and scattering keep working unchanged.
## Built once per id, in the kit's model space (world size / kit scale).

const LEAF := Color(0.42, 0.72, 0.33)
const LEAF_DARK := Color(0.25, 0.5, 0.25)
const STEM := Color(0.36, 0.62, 0.28)
const WOOD := Color(0.84, 0.58, 0.38)
const WOOD_DARK := Color(0.66, 0.44, 0.3)
const NAVY := Color(0.3, 0.36, 0.55)
const FLOWER_COLS := {
	"red": [Color(0.98, 0.4, 0.47), Color(1.0, 0.86, 0.4)],
	"yellow": [Color(1.0, 0.84, 0.3), Color(0.95, 0.55, 0.2)],
	"purple": [Color(0.72, 0.55, 1.0), Color(1.0, 0.92, 0.55)],
}

static var _cache := {}
static var _mats := {}


static func kind(id: String) -> String:
	if id.begins_with("nature-kit/flower_"):
		return "flower"
	if id.begins_with("pirate-kit/palm"):
		return "palm"
	match id:
		"nature-kit/grass", "nature-kit/grass_large", "nature-kit/grass_leafs":
			return "grass"
		"nature-kit/plant_bush", "nature-kit/plant_bushDetailed":
			return "bush"
		"nature-kit/mushroom_redGroup":
			return "mushroom"
		"nature-kit/rock_largeA", "nature-kit/rock_largeC", "nature-kit/rock_smallA", "nature-kit/stone_smallFlatA":
			return "rock"
		"nature-kit/log":
			return "log"
		"nature-kit/fence_simple":
			return "fence"
		"fantasy-town-kit/hedge", "fantasy-town-kit/hedge-large":
			return "hedge"
		"holiday-kit/lantern":
			return "lantern"
		"holiday-kit/bench":
			return "bench"
		"city-kit-suburban/planter":
			return "planter"
	return ""


static func has(id: String) -> bool:
	return not Game.options.has("kenney") and kind(id) != ""


static func model(id: String) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh(id)
	if kind(id) in ["flower", "grass", "mushroom"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


static func mesh(id: String) -> ArrayMesh:
	if _cache.has(id):
		return _cache[id]
	var b := MB.new(1.0 / Props.kit_scale(id), hash(id))
	match kind(id):
		"flower":
			_flower(b, id)
		"grass":
			_grass(b, id)
		"bush":
			_bush(b, id == "nature-kit/plant_bushDetailed")
		"mushroom":
			_mushrooms(b)
		"rock":
			_rock(b, id)
		"log":
			_log(b)
		"fence":
			_fence(b)
		"hedge":
			_hedge(b, id == "fantasy-town-kit/hedge-large")
		"lantern":
			_lantern(b)
		"bench":
			_bench(b)
		"palm":
			_palm(b, id)
		"planter":
			_planter(b)
	var m := b.commit()
	_cache[id] = m
	return m


static func material(kind_name: String) -> StandardMaterial3D:
	if _mats.has(kind_name):
		return _mats[kind_name]
	var m := StandardMaterial3D.new()
	m.resource_name = "round_" + kind_name
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.88
	match kind_name:
		"leaf":
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"glow":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.82, 0.5)
			m.emission_energy_multiplier = 1.6
		"glossy":
			m.roughness = 0.35
	_mats[kind_name] = m
	return m


# ---------------------------------------------------------------------------
# Mesh builder (world units in, kit units out)
# ---------------------------------------------------------------------------

class MB:
	var k := 1.0
	var st := {}
	var rng := RandomNumberGenerator.new()

	func _init(scale_inv: float, seed_v: int) -> void:
		k = scale_inv
		rng.seed = seed_v

	func _st(mat: String) -> SurfaceTool:
		if not st.has(mat):
			var s := SurfaceTool.new()
			s.begin(Mesh.PRIMITIVE_TRIANGLES)
			st[mat] = s
		return st[mat]

	func tri(mat: String, a: Array, b: Array, c: Array) -> void:
		var s := _st(mat)
		# Godot's front faces wind clockwise seen from outside: orient every
		# triangle by its normals so single-sided materials never show the inside.
		var pa: Vector3 = a[0]
		var fn := ((b[0] as Vector3) - pa).cross((c[0] as Vector3) - pa)
		var order := [a, b, c]
		if fn.dot((a[1] as Vector3) + (b[1] as Vector3) + (c[1] as Vector3)) > 0.0:
			order = [a, c, b]
		for v in order:
			s.set_color(v[2])
			s.set_normal(v[1])
			s.add_vertex(v[0] * k)

	func commit() -> ArrayMesh:
		var m := ArrayMesh.new()
		for mat in ["matte", "leaf", "glossy", "glow"]:
			if st.has(mat):
				m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (st[mat] as SurfaceTool).commit_to_arrays())
				m.surface_set_material(m.get_surface_count() - 1, RoundKit.material(mat))
		return m

	## Lumpy ellipsoid with a vertical colour gradient.
	func blob(c: Vector3, rad: Vector3, top: Color, bottom: Color, seg := 12, rings := 8, lump := 0.0, basis := Basis(), mat := "matte", flat_bottom := false) -> void:
		var ph := rng.randf() * TAU
		var grid := []
		for j in rings + 1:
			var phi := PI * j / rings
			var row := []
			for i in seg + 1:
				var th := TAU * i / seg
				var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
				var rr := 1.0 + lump * sin(th * 3.0 + ph) * sin(phi * 2.0 + ph * 0.7) + lump * 0.5 * sin(th * 5.0 - ph)
				var p := Vector3(d.x * rad.x, d.y * rad.y, d.z * rad.z) * rr
				if flat_bottom and p.y < -rad.y * 0.35:
					p.y = -rad.y * 0.35 + (p.y + rad.y * 0.35) * 0.15
				var n := Vector3(d.x / rad.x, d.y / rad.y, d.z / rad.z).normalized()
				row.append([c + basis * p, (basis * n).normalized(), bottom.lerp(top, clampf(d.y * 0.5 + 0.5, 0.0, 1.0))])
			grid.append(row)
		for j in rings:
			for i in seg:
				var a: Array = grid[j][i]
				var b2: Array = grid[j + 1][i]
				var cc: Array = grid[j + 1][i + 1]
				var dd: Array = grid[j][i + 1]
				tri(mat, a, cc, b2)
				tri(mat, a, dd, cc)

	## Rounded box (soft corners) with a vertical gradient.
	## `lo` uses one row per rounded edge instead of three (for small, numerous bits).
	func rbox(size: Vector3, at: Vector3, top: Color, bottom: Color, r: float, rot := Vector3.ZERO, mat := "matte", lo := false) -> void:
		var h := size * 0.5
		r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.98)
		# Rows per rounded edge: small parts (slats, frames, legs) need only one,
		# mid-sized ones two; only big soft shapes get three.
		var big := maxf(size.x, maxf(size.y, size.z))
		var m := 1 if (lo or big < 1.2 or r < 0.06) else (2 if big < 3.0 else 3)
		var rb: Array = Avatar._round_box(h, r, m)
		var pos: PackedVector3Array = rb[0]
		var nrm: PackedVector3Array = rb[1]
		var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
		for i in range(0, pos.size(), 3):
			var vs := []
			for q in 3:
				var v: Vector3 = pos[i + q]
				var u := (v.y + h.y) / size.y
				vs.append([at + basis * v, (basis * nrm[i + q]).normalized(), bottom.lerp(top, u)])
			tri(mat, vs[0], vs[1], vs[2])

	## Smooth tube along a polyline (radius and colour per point), closed tip cap.
	func tube(pts: Array, radii: Array, cols: Array, seg := 8, mat := "matte") -> void:
		var rings := []
		for i in pts.size():
			var p: Vector3 = pts[i]
			var t: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
			var side := t.cross(Vector3.FORWARD if absf(t.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
			var up := side.cross(t).normalized()
			var ring := []
			for s in seg + 1:
				var a := TAU * s / seg
				var n := (side * cos(a) + up * sin(a)).normalized()
				ring.append([p + n * float(radii[i]), n, cols[i]])
			rings.append(ring)
		for i in rings.size() - 1:
			for s in seg:
				tri(mat, rings[i][s], rings[i][s + 1], rings[i + 1][s + 1])
				tri(mat, rings[i][s], rings[i + 1][s + 1], rings[i + 1][s])
		var last: Vector3 = pts[pts.size() - 1]
		var tip_n: Vector3 = (last - (pts[pts.size() - 2] as Vector3)).normalized()
		var tipc: Color = cols[cols.size() - 1]
		for s in seg:
			tri(mat, rings[rings.size() - 1][s], [last + tip_n * float(radii[radii.size() - 1]) * 0.6, tip_n, tipc], rings[rings.size() - 1][s + 1])

	## A soft leaf / blade: a ribbon along pts, `side` is the width direction,
	## with a raised midrib (folded).
	func ribbon(pts: Array, widths: Array, side_hint: Vector3, base_col: Color, tip_col: Color, fold := 0.25, mat := "leaf") -> void:
		var n_pts := pts.size()
		var rows := []
		for i in n_pts:
			var p: Vector3 = pts[i]
			var t: Vector3 = ((pts[mini(i + 1, n_pts - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
			var side := (side_hint - t * side_hint.dot(t))
			if side.length() < 0.01:
				side = t.cross(Vector3.RIGHT)
			side = side.normalized()
			var nrm := side.cross(t).normalized()
			var w: float = widths[i]
			var col := base_col.lerp(tip_col, float(i) / (n_pts - 1))
			rows.append([
				[p - side * w, (nrm - side * 0.6).normalized(), col.darkened(0.08)],
				[p + nrm * w * fold, nrm, col.lightened(0.06)],
				[p + side * w, (nrm + side * 0.6).normalized(), col.darkened(0.08)],
			])
		for i in n_pts - 1:
			for c in 2:
				tri(mat, rows[i][c], rows[i + 1][c], rows[i + 1][c + 1])
				tri(mat, rows[i][c], rows[i + 1][c + 1], rows[i][c + 1])

	## A flat, slightly cupped ellipse (a petal or clover leaf) facing `n`.
	func disc(c: Vector3, n: Vector3, along: Vector3, rx: float, ry: float, center: Color, edge: Color, seg := 9, cup := 0.25, mat := "leaf") -> void:
		n = n.normalized()
		var ax := (along - n * along.dot(n)).normalized()
		var ay := n.cross(ax).normalized()
		var mid := [c, n, center]
		var rim := []
		for i in seg + 1:
			var a := TAU * i / seg
			var p := c + ax * cos(a) * rx + ay * sin(a) * ry + n * cup * maxf(rx, ry)
			rim.append([p, (n + (p - c).normalized() * 0.25).normalized(), edge])
		for i in seg:
			tri(mat, mid, rim[i], rim[i + 1])

	func jitter(a: float) -> float:
		return rng.randf_range(-a, a)


# ---------------------------------------------------------------------------
# Plants
# ---------------------------------------------------------------------------

static func _flower(b: MB, id: String) -> void:
	var fname := id.get_file().trim_prefix("flower_")   # redA, yellowB…
	var letter := fname.right(1)
	var colour := fname.left(fname.length() - 1)
	var pal: Array = FLOWER_COLS.get(colour, FLOWER_COLS["red"])
	var petal: Color = pal[0]
	var heart: Color = pal[1]
	var h := 0.56 if letter != "C" else 0.5
	var lean := Vector3(b.jitter(0.05), 0, b.jitter(0.05))
	var top := Vector3(0, h, 0) + lean
	b.tube([Vector3(0, -0.05, 0), top], [0.028, 0.02], [STEM.darkened(0.2), STEM.lightened(0.1)], 4)
	# Two leaves at the base.
	for s in [-1.0, 1.0]:
		var d := Vector3(s, 0, b.jitter(0.4)).normalized()
		b.ribbon([Vector3(0, 0.02, 0), d * 0.12 + Vector3(0, 0.12, 0), d * 0.25 + Vector3(0, 0.15, 0)],
				[0.012, 0.055, 0.0], d.cross(Vector3.UP), LEAF_DARK, LEAF, 0.3)
	match letter:
		"A":
			# Tulip: a cup of three round petals.
			for i in 3:
				var a := TAU * i / 3.0
				var d := Vector3(cos(a), 0, sin(a))
				b.blob(top + d * 0.04 + Vector3(0, 0.08, 0), Vector3(0.075, 0.12, 0.05), petal.lightened(0.1), petal.darkened(0.12), 5, 3, 0.0,
						Basis(Vector3.UP, -a))
		"B":
			# Cosmos / pansy: five round petals around a round heart.
			var face := (Vector3.UP + Vector3(0.35, 0, 0.0)).normalized()
			var ax := face.cross(Vector3.FORWARD).normalized()
			for i in 5:
				var a := TAU * i / 5.0
				var d := (ax.rotated(face, a)).normalized()
				b.disc(top + d * 0.08 + face * 0.01, face, d, 0.085, 0.065, petal.lightened(0.12), petal, 5, 0.18)
			b.blob(top + face * 0.03, Vector3(0.045, 0.03, 0.045), heart, heart.darkened(0.2), 5, 3)
		_:
			# Pompom: a round, lumpy flower ball.
			b.blob(top + Vector3(0, 0.08, 0), Vector3(0.12, 0.11, 0.12), petal.lightened(0.15), petal.darkened(0.15), 6, 4, 0.12)


static func _grass(b: MB, id: String) -> void:
	var base := Color(0.32, 0.58, 0.26)
	var tip := Color(0.56, 0.8, 0.36)
	if id == "nature-kit/grass_leafs":
		# A clover patch: little stems with round three-part leaves.
		for i in 4:
			var a := TAU * i / 4.0 + b.jitter(0.4)
			var p := Vector3(cos(a), 0, sin(a)) * b.rng.randf_range(0.04, 0.14)
			var hh := b.rng.randf_range(0.12, 0.2)
			b.tube([p + Vector3(0, -0.03, 0), p + Vector3(0, hh, 0)], [0.012, 0.01], [base, base], 4)
			for l in 3:
				var la := TAU * l / 3.0 + a
				var d := Vector3(cos(la), 0, sin(la))
				b.disc(p + Vector3(0, hh, 0) + d * 0.045, Vector3.UP + d * 0.25, d, 0.05, 0.045, tip, base.lightened(0.1), 8, 0.1)
		return
	var n := 9 if id == "nature-kit/grass_large" else 7
	var hmax := 0.95 if id == "nature-kit/grass_large" else 0.75
	for i in n:
		var a := TAU * i / n + b.jitter(0.5)
		var d := Vector3(cos(a), 0, sin(a))
		var hh := b.rng.randf_range(hmax * 0.6, hmax)
		var root := d * b.rng.randf_range(0.02, 0.16)
		var bend := b.rng.randf_range(0.12, 0.22)
		var pts := []
		for s in 5:
			var t := s / 4.0
			pts.append(root + d * bend * t * t + Vector3(0, hh * t - 0.04, 0))
		b.ribbon(pts, [0.06, 0.065, 0.055, 0.035, 0.0], d.cross(Vector3.UP), base, tip, 0.35)


static func _bush(b: MB, detailed: bool) -> void:
	var top := LEAF.lightened(0.04)
	var bot := LEAF_DARK
	var parts := [[Vector3(0, 0.34, 0), Vector3(0.45, 0.4, 0.45)], [Vector3(0.36, 0.24, 0.12), Vector3(0.3, 0.27, 0.3)],
		[Vector3(-0.28, 0.24, 0.24), Vector3(0.3, 0.26, 0.3)], [Vector3(0.0, 0.22, -0.36), Vector3(0.28, 0.24, 0.28)]]
	var k := 1.0
	if detailed:
		k = 1.5
		parts.append([Vector3(-0.3, 0.3, -0.25), Vector3(0.32, 0.3, 0.32)])
	for p in parts:
		b.blob((p[0] as Vector3) * k, (p[1] as Vector3) * k, top, bot, 8, 5, 0.07)
	if detailed:
		# Little azalea flowers dotted over the top.
		var col: Color = [Color(1.0, 0.55, 0.72), Color(1.0, 0.78, 0.35), Color(0.95, 0.45, 0.45)][b.rng.randi() % 3]
		for i in 9:
			var a := b.rng.randf() * TAU
			var e := b.rng.randf_range(0.35, 1.2)
			var d := Vector3(cos(a) * sin(e), cos(e), sin(a) * sin(e))
			var c := Vector3(0, 0.34, 0) * k + Vector3(d.x * 0.5, d.y * 0.45, d.z * 0.5) * k
			b.blob(c, Vector3(0.085, 0.06, 0.085), col.lightened(0.1), col.darkened(0.05), 5, 3)


static func _mushrooms(b: MB) -> void:
	for m in [[Vector3(0, 0, 0), 1.0], [Vector3(0.2, 0, 0.12), 0.7], [Vector3(-0.16, 0, 0.16), 0.55]]:
		var p: Vector3 = m[0]
		var s: float = m[1]
		b.tube([p + Vector3(0, -0.04, 0), p + Vector3(0, 0.26 * s, 0)], [0.07 * s, 0.06 * s], [Color(0.95, 0.9, 0.82), Color(1, 0.97, 0.9)], 7)
		var cap := p + Vector3(0, 0.28 * s, 0)
		b.blob(cap, Vector3(0.2, 0.14, 0.2) * s, Color(0.95, 0.33, 0.3), Color(0.8, 0.22, 0.22), 11, 7, 0.0, Basis(), "glossy", true)
		for i in 5:
			var a := TAU * i / 5.0 + b.jitter(0.3)
			var e := 0.55 if i > 0 else 0.0
			var d := Vector3(cos(a) * sin(e), cos(e), sin(a) * sin(e))
			b.disc(cap + Vector3(d.x * 0.19, d.y * 0.135, d.z * 0.19) * s, d, Vector3.RIGHT, 0.035 * s, 0.035 * s, Color(1, 1, 1), Color(0.97, 0.95, 0.92), 7, 0.0)


static func _rock(b: MB, id: String) -> void:
	var top := Color(0.8, 0.79, 0.76)
	var bot := Color(0.58, 0.58, 0.62)
	match id:
		"nature-kit/rock_largeA":
			b.blob(Vector3(0, 0.25, 0), Vector3(1.15, 0.62, 1.5), top, bot, 14, 9, 0.08, Basis(), "matte", true)
			b.blob(Vector3(0.5, 0.12, -0.9), Vector3(0.6, 0.42, 0.55), top, bot, 10, 7, 0.1, Basis(), "matte", true)
		"nature-kit/rock_largeC":
			b.blob(Vector3(-0.3, 0.3, 0), Vector3(1.3, 0.75, 1.3), top, bot, 14, 9, 0.08, Basis(), "matte", true)
			b.blob(Vector3(0.95, 0.15, 0.6), Vector3(0.65, 0.45, 0.6), top, bot, 10, 7, 0.1, Basis(), "matte", true)
		"nature-kit/stone_smallFlatA":
			b.blob(Vector3(0, 0.0, 0), Vector3(0.72, 0.16, 0.62), top, bot, 12, 6, 0.06, Basis(), "matte", true)
		_:
			b.blob(Vector3(0, 0.18, 0), Vector3(0.52, 0.42, 0.5), top, bot, 12, 8, 0.1, Basis(), "matte", true)


static func _log(b: MB) -> void:
	var bark := Color(0.6, 0.42, 0.3)
	b.tube([Vector3(0, 0.22, -1.0), Vector3(0, 0.23, 0.0), Vector3(0, 0.22, 1.0)], [0.27, 0.28, 0.26], [bark, bark.lightened(0.05), bark], 12)
	for z in [-1.0, 1.0]:
		b.disc(Vector3(0, 0.22, z * 1.0), Vector3(0, 0, z), Vector3.UP, 0.25, 0.25, Color(0.92, 0.78, 0.55), Color(0.82, 0.64, 0.42), 14, 0.0, "matte")
	b.ribbon([Vector3(0.18, 0.4, 0.2), Vector3(0.3, 0.55, 0.25), Vector3(0.36, 0.62, 0.3)], [0.02, 0.05, 0.0], Vector3.FORWARD.cross(Vector3.UP), LEAF_DARK, LEAF, 0.3)


# ---------------------------------------------------------------------------
# Street furniture
# ---------------------------------------------------------------------------

static func _fence(b: MB) -> void:
	var zc := -1.488
	for x in [-1.48, 1.48]:
		b.rbox(Vector3(0.17, 1.02, 0.17), Vector3(x, 0.47, zc), WOOD, WOOD_DARK, 0.07)
	for y in [0.45, 0.8]:
		b.rbox(Vector3(3.0, 0.13, 0.08), Vector3(0, y, zc), WOOD.lightened(0.05), WOOD, 0.05)


static func _hedge(b: MB, large: bool) -> void:
	var w := 0.96 if large else 0.6
	var h := 1.44 if large else 0.6
	var xc := 0.72 if large else 0.9
	var top := Color(0.4, 0.7, 0.34)
	var bot := Color(0.24, 0.48, 0.25)
	b.rbox(Vector3(w, h * 0.82, 2.36), Vector3(xc, h * 0.41, 0), top.darkened(0.04), bot, minf(w, h) * 0.38)
	for i in 5:
		var z := -0.96 + i * 0.48
		b.blob(Vector3(xc + b.jitter(0.04), h * 0.8, z), Vector3(w * 0.42, h * 0.22, 0.3), top, top.darkened(0.15), 9, 6, 0.08)


static func _lantern(b: MB) -> void:
	var dark := NAVY.darkened(0.1)
	b.rbox(Vector3(0.5, 0.16, 0.5), Vector3(0, 0.08, 0), NAVY, dark, 0.07)
	b.rbox(Vector3(0.32, 0.18, 0.32), Vector3(0, 0.24, 0), NAVY, dark, 0.07)
	b.tube([Vector3(0, 0.3, 0), Vector3(0, 1.3, 0), Vector3(0, 2.2, 0)], [0.075, 0.062, 0.055], [dark, NAVY, NAVY.lightened(0.05)], 10)
	b.rbox(Vector3(0.24, 0.08, 0.24), Vector3(0, 2.2, 0), NAVY.lightened(0.05), NAVY, 0.035)
	b.rbox(Vector3(0.42, 0.05, 0.42), Vector3(0, 2.27, 0), NAVY.lightened(0.05), NAVY, 0.024)
	# Glowing round lamp under a little dome hat with a knob on top.
	b.blob(Vector3(0, 2.46, 0), Vector3(0.17, 0.2, 0.17), Color(1.0, 0.95, 0.75), Color(1.0, 0.82, 0.5), 12, 8, 0.0, Basis(), "glow")
	b.blob(Vector3(0, 2.66, 0), Vector3(0.27, 0.1, 0.27), NAVY.lightened(0.1), NAVY.darkened(0.15), 14, 6, 0.0, Basis(), "glossy", true)
	b.blob(Vector3(0, 2.74, 0), Vector3(0.05, 0.05, 0.05), Color(1.0, 0.85, 0.4), Color(0.9, 0.7, 0.3), 7, 5, 0.0, Basis(), "glossy")


static func _bench(b: MB) -> void:
	var metal := Color(0.36, 0.46, 0.62)
	var metal_d := metal.darkened(0.2)
	# Seat slats (front is +Z), seat top at 0.47.
	for z in [0.24, 0.06, -0.12]:
		b.rbox(Vector3(1.68, 0.07, 0.16), Vector3(0, 0.435, z), WOOD.lightened(0.04), WOOD_DARK, 0.03)
	# Backrest slats, leaning back.
	for y in [0.72, 0.94]:
		b.rbox(Vector3(1.68, 0.14, 0.06), Vector3(0, y, -0.3 - (y - 0.6) * 0.18), WOOD.lightened(0.04), WOOD_DARK, 0.03, Vector3(-12, 0, 0))
	# Rounded iron sides: legs, armrests.
	for sx in [-0.8, 0.8]:
		b.tube([Vector3(sx, 0.0, 0.28), Vector3(sx, 0.38, 0.27)], [0.045, 0.04], [metal_d, metal], 8)
		b.tube([Vector3(sx, 0.0, -0.26), Vector3(sx, 0.45, -0.3), Vector3(sx, 1.05, -0.42)], [0.045, 0.042, 0.04], [metal_d, metal, metal], 8)
		b.tube([Vector3(sx, 0.4, 0.27), Vector3(sx, 0.64, 0.22), Vector3(sx, 0.66, -0.05), Vector3(sx, 0.62, -0.33)], [0.04, 0.04, 0.04, 0.04], [metal, metal, metal, metal], 8)
		b.blob(Vector3(sx, 0.64, 0.24), Vector3(0.055, 0.055, 0.055), metal.lightened(0.1), metal, 7, 5)


static func _planter(b: MB) -> void:
	var pot := Color(0.88, 0.52, 0.36)
	b.rbox(Vector3(1.6, 0.5, 1.2), Vector3(0, 0.25, 0), pot, pot.darkened(0.2), 0.14)
	b.rbox(Vector3(1.66, 0.1, 1.26), Vector3(0, 0.5, 0), pot.lightened(0.08), pot, 0.05)
	b.rbox(Vector3(1.46, 0.06, 1.06), Vector3(0, 0.53, 0), Color(0.45, 0.32, 0.24), Color(0.4, 0.28, 0.2), 0.03)
	b.blob(Vector3(0, 0.7, 0), Vector3(0.55, 0.28, 0.4), LEAF, LEAF_DARK, 12, 7, 0.08)
	var cols := [Color(1.0, 0.45, 0.55), Color(1.0, 0.84, 0.3), Color(0.75, 0.6, 1.0), Color(1, 1, 1)]
	for i in 7:
		var a := TAU * i / 7.0
		var p := Vector3(cos(a) * 0.45, 0.82 + b.jitter(0.04), sin(a) * 0.3)
		var c: Color = cols[i % cols.size()]
		b.blob(p, Vector3(0.08, 0.06, 0.08), c.lightened(0.1), c.darkened(0.1), 7, 4, 0.1)


static func _palm(b: MB, id: String) -> void:
	var bend := id.contains("bend")
	var top := Vector3(-1.9, 5.0, 0.0) if bend else Vector3(0.0, 5.1, 0.0)
	var n_seg := 9
	var pts := []
	for i in n_seg + 1:
		var t := float(i) / n_seg
		var x := top.x * t * t if bend else sin(t * 2.5) * 0.12
		pts.append(Vector3(x, top.y * t, 0.0))
	var bark := Color(0.7, 0.5, 0.34)
	# Trunk: stacked rounded rings, slightly fatter at the bottom of each.
	for i in n_seg:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var r := lerpf(0.26, 0.17, float(i) / n_seg)
		var c := bark if i % 2 == 0 else bark.darkened(0.1)
		b.tube([p0, p0.lerp(p1, 0.15), p0.lerp(p1, 0.85), p1], [r * 1.1, r * 1.16, r * 0.98, r * 0.96], [c.darkened(0.08), c, c.lightened(0.04), c], 10)
	# Coconuts.
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		b.blob(top + Vector3(cos(a) * 0.2, -0.22, sin(a) * 0.2), Vector3(0.15, 0.16, 0.15), Color(0.55, 0.38, 0.24), Color(0.42, 0.28, 0.18), 8, 6, 0.0, Basis(), "glossy")
	# Droopy rounded fronds with a folded midrib.
	var n_leaves := 9 if id.contains("detailed") else 8
	for i in n_leaves:
		var a := TAU * i / n_leaves + b.jitter(0.15)
		var d := Vector3(cos(a), 0, sin(a))
		var length := b.rng.randf_range(2.0, 2.5)
		var lift := b.rng.randf_range(0.35, 0.65)
		var lpts := []
		var widths := []
		for s in 8:
			var t := s / 7.0
			lpts.append(top + d * length * t + Vector3(0, lift * t - 1.6 * t * t * t, 0) + Vector3(0, 0.05, 0))
			widths.append([0.06, 0.26, 0.38, 0.4, 0.36, 0.28, 0.16, 0.0][s])
		b.ribbon(lpts, widths, d.cross(Vector3.UP), Color(0.28, 0.58, 0.3), Color(0.48, 0.78, 0.36), 0.3)

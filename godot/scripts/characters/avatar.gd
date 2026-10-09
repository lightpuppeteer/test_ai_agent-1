class_name Avatar
extends RefCounted
## Builds custom chibi characters out of bevelled blocks on the Kenney
## mini-character skeleton, so all of its animations (walk, sit, drive…)
## work unchanged. A look is a list of parts; each part is a block rigidly
## bound to one bone, plus a painted face texture.
##
## Units below are the Kenney model's own (≈0.7 tall); Person scales the model.

const BASE := "mini-characters/character-female-f"
const BONES := {"root": 0, "leg-left": 1, "leg-right": 2, "torso": 3, "arm-left": 4, "arm-right": 5, "head": 6}

# Body landmarks (model space, rest pose). The model faces +Z; "left" is +X.
const HIP_Y := 0.176
const SHOULDER := Vector3(0.0999, 0.2878, -0.0173)
const LEG_X := 0.0836
const HEAD_BOTTOM := 0.343
const HEAD_SIZE := Vector3(0.40, 0.34, 0.36)
const HEAD_CENTER := Vector3(0.0, 0.343 + 0.17, -0.005)
const HEAD_FRONT := HEAD_CENTER.z + 0.18
const TORSO_SIZE := Vector3(0.26, 0.205, 0.18)
const TORSO_CENTER := Vector3(0.0, 0.272, -0.028)
const ARM_END := 0.335

static var _materials := {}


## Returns a ready model (Node3D with Skeleton3D + AnimationPlayer) for a look.
static func build(look: Dictionary) -> Node3D:
	var model := Props.model(BASE)
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	for c in sk.get_children():
		if c is MeshInstance3D:
			sk.remove_child(c)
			c.free()
	var parts: Array = look.get("parts", [])
	var by_mat := {}
	for p in parts:
		var m: String = p.get("mat", "matte")
		if not by_mat.has(m):
			by_mat[m] = []
		by_mat[m].append(p)
	var mesh := ArrayMesh.new()
	for m in by_mat:
		var st := SurfaceTool.new()
		st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in by_mat[m]:
			_add_block(st, p)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(m))
	# Face: a textured quad just in front of the head.
	var face_tex := paint_face(look.get("face", {}))
	var fst := SurfaceTool.new()
	fst.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fw := HEAD_SIZE.x * 0.92
	var fh := HEAD_SIZE.y * 0.92
	var fz := HEAD_FRONT + 0.0025
	var fc := Vector3(0, HEAD_CENTER.y - 0.01, fz)
	var hb: Dictionary = look.get("head_ball", {})
	if not hb.is_empty():
		# Round heads: the face is a curved decal hugging the front of the head.
		_face_patch(fst, hb, fc, fw, fh)
	else:
		var quad := [
			[fc + Vector3(-fw / 2, -fh / 2, 0), Vector2(0, 1)], [fc + Vector3(fw / 2, -fh / 2, 0), Vector2(1, 1)],
			[fc + Vector3(fw / 2, fh / 2, 0), Vector2(1, 0)], [fc + Vector3(-fw / 2, fh / 2, 0), Vector2(0, 0)],
		]
		for idx in [0, 2, 1, 0, 3, 2]:
			fst.set_normal(Vector3(0, 0, 1))
			fst.set_uv(quad[idx][1])
			fst.set_bones(PackedInt32Array([BONES["head"], 0, 0, 0]))
			fst.set_weights(PackedFloat32Array([1, 0, 0, 0]))
			fst.add_vertex(quad[idx][0])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fst.commit_to_arrays())
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = face_tex
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fm.alpha_scissor_threshold = 0.5
	fm.set_meta("near_fade", 0.9)
	fm.roughness = 0.7
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mesh.surface_set_material(mesh.get_surface_count() - 1, fm)

	var mi := MeshInstance3D.new()
	mi.name = "AvatarMesh"
	mi.mesh = mesh
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = sk.create_skin_from_rest_transforms()
	return model


## A grid over the face rectangle, each point pushed onto the head's surface.
static func _face_patch(st: SurfaceTool, hb: Dictionary, fc: Vector3, fw: float, fh: float) -> void:
	var size: Vector3 = hb["size"]
	var h := size * 0.5
	var at: Vector3 = hb["at"]
	var pw: float = hb.get("power", 2.4)
	const N := 18
	var pts := []
	for i in N + 1:
		var row := []
		for j in N + 1:
			var uv := Vector2(float(j) / N, float(i) / N)
			var x := fc.x + (uv.x - 0.5) * fw
			var y := fc.y + (0.5 - uv.y) * fh
			var nx := (x - at.x) / h.x
			var ny := (y - at.y) / h.y
			var rem := 1.0 - pow(absf(nx), pw) - pow(absf(ny), pw)
			var nz := pow(maxf(rem, 0.0), 1.0 / pw)
			var g := Vector3(_spow(nx, pw - 1.0) / h.x, _spow(ny, pw - 1.0) / h.y, pow(nz, pw - 1.0) / h.z).normalized()
			var p := Vector3(x, y, at.z + nz * h.z) + g * 0.0035
			row.append([p, g, uv])
		pts.append(row)
	for i in N:
		for j in N:
			var a: Array = pts[i][j]
			var b: Array = pts[i][j + 1]
			var c: Array = pts[i + 1][j + 1]
			var d: Array = pts[i + 1][j]
			# Seen from the front (+Z), clockwise: a (top-left) → b → c, a → c → d.
			for v: Array in [a, b, c, a, c, d]:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.set_bones(PackedInt32Array([BONES["head"], 0, 0, 0]))
				st.set_weights(PackedFloat32Array([1, 0, 0, 0]))
				st.add_vertex(v[0])


static func material(kind: String) -> Material:
	if _materials.has(kind):
		return _materials[kind]
	var m := StandardMaterial3D.new()
	m.set_meta("near_fade", 0.9)   # dissolve if the camera ends up inside a head
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match kind:
		"shiny":         # silver dress, sunglasses
			m.metallic = 0.55
			m.roughness = 0.3
			m.metallic_specular = 0.7
		"glossy":
			m.roughness = 0.35
			m.metallic_specular = 0.6
		"satin":
			m.roughness = 0.55
		"hair":          # open shells (hair caps, beards): seen from both sides
			m.roughness = 0.65
			m.metallic_specular = 0.4
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			m.roughness = 0.85
			m.metallic_specular = 0.3
	_materials[kind] = m
	return m


# ---------------------------------------------------------------------------
# Blocks
# ---------------------------------------------------------------------------

## Part keys: bone, size (Vector3), at (centre, model space), color, mat,
## bevel (default 0.012), rot (degrees), taper (Vector2 bottom x/z scale),
## shade (bottom darkening, default 0.1), color2 (bottom colour gradient).
static func _add_block(st: SurfaceTool, p: Dictionary) -> void:
	if p.get("shape", "") == "ball":
		_add_ball(st, p)
		return
	var size: Vector3 = p["size"]
	var h := size * 0.5
	var c := minf(float(p.get("bevel", 0.012)), minf(h.x, minf(h.y, h.z)) * 0.6)
	var at: Vector3 = p["at"]
	var col: Color = p["color"]
	var col2: Color = p.get("color2", col)
	var shade: float = p.get("shade", 0.1)
	var rot: Vector3 = p.get("rot", Vector3.ZERO)
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	var taper: Vector2 = p.get("taper", Vector2.ONE)   # x/z scale at the bottom (top stays 1)
	var bone: int = BONES[p["bone"]]
	if ROUNDED:
		# Soft, rounded blocks with smooth normals (the cozy look).
		var frac: float = p.get("round", 0.62)     # corner radius as a share of the smallest half-size
		var r := minf(maxf(c * 2.0, minf(h.x, minf(h.y, h.z)) * frac), minf(h.x, minf(h.y, h.z)) * 0.95)
		var rb := _round_box(h, r, 2)
		var pos: PackedVector3Array = rb[0]
		var nrm: PackedVector3Array = rb[1]
		for i in pos.size():
			var v: Vector3 = pos[i]
			var u := (v.y + h.y) / size.y
			var sx := lerpf(taper.x, 1.0, u)
			var sz := lerpf(taper.y, 1.0, u)
			v = Vector3(v.x * sx, v.y, v.z * sz)
			var nn: Vector3 = nrm[i]
			nn = (basis * Vector3(nn.x / maxf(sx, 0.01), nn.y, nn.z / maxf(sz, 0.01))).normalized()
			var cc := col2.lerp(col, u)
			cc = cc.darkened(shade * (1.0 - u))
			st.set_color(cc)
			st.set_normal(nn)
			st.set_bones(PackedInt32Array([bone, 0, 0, 0]))
			st.set_weights(PackedFloat32Array([1, 0, 0, 0]))
			st.add_vertex(at + basis * v)
		return
	var tris := _bevel_box_tris(h, c)
	for i in range(0, tris.size(), 3):
		var vs: Array[Vector3] = []
		var ys: Array[float] = []
		for k in 3:
			var v: Vector3 = tris[i + k]
			var u := (v.y + h.y) / size.y            # 0 bottom … 1 top
			var sx := lerpf(taper.x, 1.0, u)
			var sz := lerpf(taper.y, 1.0, u)
			v = Vector3(v.x * sx, v.y, v.z * sz)
			vs.append(at + basis * v)
			ys.append(u)
		var n := (vs[2] - vs[0]).cross(vs[1] - vs[0]).normalized()
		for k in 3:
			var cc := col2.lerp(col, ys[k])
			cc = cc.darkened(shade * (1.0 - ys[k]))
			st.set_color(cc)
			st.set_normal(n)
			st.set_bones(PackedInt32Array([bone, 0, 0, 0]))
			st.set_weights(PackedFloat32Array([1, 0, 0, 0]))
			st.add_vertex(vs[k])


## A soft "ball" part: a superellipsoid (power 2 = ellipsoid, higher = boxier
## but still pillowy). Extra keys: power, segs/rings (resolution), and `cut`, a
## list of [min, max] Vector3 boxes in the ball's normalised space (-1…1): any
## triangle whose centre falls inside one is left out. That is how hair shells
## get their face opening and beards their mouth line. Shells can be seen from
## inside, so use them with a double-sided material ("hair").
static func _add_ball(st: SurfaceTool, p: Dictionary) -> void:
	var size: Vector3 = p["size"]
	var h := size * 0.5
	var at: Vector3 = p["at"]
	var col: Color = p["color"]
	var col2: Color = p.get("color2", col)
	var shade: float = p.get("shade", 0.08)
	var rot: Vector3 = p.get("rot", Vector3.ZERO)
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	var taper: Vector2 = p.get("taper", Vector2.ONE)
	var bone: int = BONES[p["bone"]]
	var cuts: Array = p.get("cut", [])
	var power := float(p.get("power", 2.4))
	var grid := _ball_grid(power, int(p.get("segs", 20)), int(p.get("rings", 14)))
	var qs: PackedVector3Array = grid[0].duplicate()
	var ns: PackedVector3Array = grid[1].duplicate()
	var idx: PackedInt32Array = grid[2]
	# Which triangles survive the cuts.
	var keep := PackedInt32Array()
	var used := {}
	for t in range(0, idx.size(), 3):
		var skip := false
		if not cuts.is_empty():
			var c: Vector3 = (qs[idx[t]] + qs[idx[t + 1]] + qs[idx[t + 2]]) / 3.0
			for box in cuts:
				if box is Dictionary:
					if _in_window(c, box):
						skip = true
						break
					continue
				var mn: Vector3 = box[0]
				var mx: Vector3 = box[1]
				if c.x >= mn.x and c.x <= mx.x and c.y >= mn.y and c.y <= mx.y and c.z >= mn.z and c.z <= mx.z:
					skip = true
					break
		if skip:
			continue
		keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		for k in 3:
			used[idx[t + k]] = true
	# Kept vertices that poke into an elliptical window slide onto its rim, so
	# the opening is a smooth curve instead of a staircase of triangles.
	for box in cuts:
		if not box is Dictionary:
			continue
		var el: Vector4 = box["ell"]
		for i: int in used:
			var q: Vector3 = qs[i]
			if not _in_window(q, box):
				continue
			var d := Vector2((q.x - el.x) / el.z, (q.y - el.y) / el.w)
			if d.length() < 1e-4:
				continue
			d = d.normalized()
			var x := el.x + d.x * el.z
			var y := el.y + d.y * el.w
			var rem := 1.0 - pow(absf(x), power) - pow(absf(y), power)
			var z := pow(maxf(rem, 0.0), 1.0 / power) * (1.0 if q.z >= 0.0 else -1.0)
			qs[i] = Vector3(x, y, z)
			var g := Vector3(_spow(x, power - 1.0), _spow(y, power - 1.0), _spow(z, power - 1.0))
			ns[i] = g.normalized() if g.length() > 1e-6 else Vector3(0, 0, 1)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var cols := PackedColorArray()
	pos.resize(qs.size())
	nrm.resize(qs.size())
	cols.resize(qs.size())
	for i in qs.size():
		var q: Vector3 = qs[i]
		var u := (q.y + 1.0) * 0.5
		var sx := lerpf(taper.x, 1.0, u)
		var sz := lerpf(taper.y, 1.0, u)
		var v := Vector3(q.x * h.x * sx, q.y * h.y, q.z * h.z * sz)
		var n: Vector3 = ns[i]
		n = Vector3(n.x / (h.x * maxf(sx, 0.01)), n.y / h.y, n.z / (h.z * maxf(sz, 0.01)))
		pos[i] = at + basis * v
		nrm[i] = (basis * n).normalized()
		cols[i] = col2.lerp(col, u).darkened(shade * (1.0 - u))
	for t in keep.size():
		var i: int = keep[t]
		st.set_color(cols[i])
		st.set_normal(nrm[i])
		st.set_bones(PackedInt32Array([bone, 0, 0, 0]))
		st.set_weights(PackedFloat32Array([1, 0, 0, 0]))
		st.add_vertex(pos[i])


## Elliptical window on the front of a ball: {"ell": Vector4(cx, cy, rx, ry), "z": min z}.
static func _in_window(q: Vector3, w: Dictionary) -> bool:
	var el: Vector4 = w["ell"]
	return q.z >= float(w.get("z", 0.0)) and pow((q.x - el.x) / el.z, 2.0) + pow((q.y - el.y) / el.w, 2.0) <= 1.0


static var _ball_cache := {}

## Unit superellipsoid: [points on the surface (-1…1), gradient directions, triangle indices].
static func _ball_grid(power: float, segs: int, rings: int) -> Array:
	var key := [power, segs, rings]
	if _ball_cache.has(key):
		return _ball_cache[key]
	var e := 2.0 / power
	var qs := PackedVector3Array()
	var ns := PackedVector3Array()
	for i in rings + 1:
		var v := -PI * 0.5 + PI * float(i) / rings
		for j in segs + 1:
			var u := -PI + TAU * float(j) / segs
			var q := Vector3(_spow(cos(v), e) * _spow(cos(u), e), _spow(sin(v), e), _spow(cos(v), e) * _spow(sin(u), e))
			qs.append(q)
			var g := Vector3(_spow(q.x, power - 1.0), _spow(q.y, power - 1.0), _spow(q.z, power - 1.0))
			ns.append(g.normalized() if g.length() > 1e-6 else Vector3(0, signf(q.y), 0))
	var idx := PackedInt32Array()
	for i in rings:
		for j in segs:
			var a := i * (segs + 1) + j
			var b := a + 1
			var c := a + segs + 2
			var d := a + segs + 1
			for tri: Array in [[a, b, c], [a, c, d]]:
				var p0: Vector3 = qs[tri[0]]
				var p1: Vector3 = qs[tri[1]]
				var p2: Vector3 = qs[tri[2]]
				var fn := (p1 - p0).cross(p2 - p0)
				if fn.length() < 1e-7:
					continue
				# Godot front faces are clockwise seen from outside.
				if fn.dot(p0 + p1 + p2) > 0.0:
					idx.append_array([tri[0], tri[2], tri[1]])
				else:
					idx.append_array([tri[0], tri[1], tri[2]])
	_ball_cache[key] = [qs, ns, idx]
	return _ball_cache[key]


static func _spow(x: float, e: float) -> float:
	return signf(x) * pow(absf(x), e)


static var _box_cache := {}
const ROUNDED := true
static var _round_cache := {}

## A rounded box (half extents h, corner radius r) as a triangle list with
## smooth normals: [positions, normals]. Extra rows near the edges keep the
## curves smooth while flat faces stay cheap.
static func _round_box(h: Vector3, r: float, M: int = 3) -> Array:
	var key := [h, r, M]
	if _round_cache.has(key):
		return _round_cache[key]
	var e := h - Vector3(r, r, r)
	var coords := []
	for axis in 3:
		var cs: Array[float] = []
		for k in M + 1:
			cs.append(-h[axis] + (h[axis] - e[axis]) * float(k) / M)
		for k in M + 1:
			cs.append(e[axis] + (h[axis] - e[axis]) * float(k) / M)
		coords.append(cs)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	for axis in 3:
		var a := (axis + 1) % 3
		var b := (axis + 2) % 3
		for s: float in [-1.0, 1.0]:
			var ca: Array[float] = coords[a]
			var cb: Array[float] = coords[b]
			for i in ca.size() - 1:
				for j in cb.size() - 1:
					var quad: Array[Vector3] = []
					for q: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
						var v := Vector3.ZERO
						v[axis] = s * h[axis]
						v[a] = ca[i + q.x]
						v[b] = cb[j + q.y]
						quad.append(v)
					var pts: Array[Vector3] = []
					var ns: Array[Vector3] = []
					for v in quad:
						var inner := Vector3(clampf(v.x, -e.x, e.x), clampf(v.y, -e.y, e.y), clampf(v.z, -e.z, e.z))
						var d := v - inner
						var n := d.normalized() if d.length() > 1e-6 else Vector3.ZERO
						if n == Vector3.ZERO:
							n[axis] = s
						pts.append(inner + n * r)
						ns.append(n)
					# Godot front faces are clockwise seen from outside.
					var face_n := (pts[1] - pts[0]).cross(pts[2] - pts[0])
					var order := [0, 2, 1, 0, 3, 2] if face_n.dot(ns[0] + ns[2]) > 0.0 else [0, 1, 2, 0, 2, 3]
					for k in order:
						pos.append(pts[k])
						nrm.append(ns[k])
	_round_cache[key] = [pos, nrm]
	return [pos, nrm]

## Triangles of a chamfered box (half extents h, bevel c), wound counter-clockwise seen from outside.
static func _bevel_box_tris(h: Vector3, c: float) -> PackedVector3Array:
	var key := [h, c]
	if _box_cache.has(key):
		return _box_cache[key]
	var out := PackedVector3Array()
	var e := h - Vector3(c, c, c)
	var polys: Array = []
	# 6 faces
	for axis in 3:
		for s: float in [-1.0, 1.0]:
			var a := (axis + 1) % 3
			var b := (axis + 2) % 3
			var poly: Array[Vector3] = []
			for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var v := Vector3.ZERO
				v[axis] = s * h[axis]
				v[a] = q.x * e[a]
				v[b] = q.y * e[b]
				poly.append(v)
			polys.append(poly)
	# 12 edge bevels
	for axis in 3:           # the edge runs along `axis`
		var a := (axis + 1) % 3
		var b := (axis + 2) % 3
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				var poly: Array[Vector3] = []
				for t: float in [-1.0, 1.0]:
					var v1 := Vector3.ZERO
					v1[axis] = t * e[axis]
					v1[a] = sa * h[a]
					v1[b] = sb * e[b]
					var v2 := Vector3.ZERO
					v2[axis] = t * e[axis]
					v2[a] = sa * e[a]
					v2[b] = sb * h[b]
					poly.append(v1)
					poly.append(v2)
				polys.append([poly[0], poly[1], poly[3], poly[2]])
	# 8 corners
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				polys.append([Vector3(sx * h.x, sy * e.y, sz * e.z), Vector3(sx * e.x, sy * h.y, sz * e.z), Vector3(sx * e.x, sy * e.y, sz * h.z)])
	for poly in polys:
		var centroid := Vector3.ZERO
		for v in poly:
			centroid += v
		centroid /= poly.size()
		for i in range(1, poly.size() - 1):
			var v0: Vector3 = poly[0]
			var v1: Vector3 = poly[i]
			var v2: Vector3 = poly[i + 1]
			# Godot uses clockwise front faces: make the normal point outwards for CW order.
			var n := (v1 - v0).cross(v2 - v0)
			if n.dot(centroid) > 0.0:
				out.append_array([v0, v2, v1])
			else:
				out.append_array([v0, v1, v2])
	_box_cache[key] = out
	return out


# ---------------------------------------------------------------------------
# Face painting
# ---------------------------------------------------------------------------

## face keys: eyes ("round" | "happy"), brows (Color), mouth ("smile" | "grin" | "none"),
## blush (bool), skin (Color, for eyelids), lash (bool)
static func paint_face(f: Dictionary) -> ImageTexture:
	var S := 256
	var img := Image.create(S, S, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.16, 0.11, 0.1)
	var eye_y := 118.0
	# Animal extras: a pale face mask (penguin), whiskers, a little cat mouth.
	var mask: Color = f.get("mask", Color(0, 0, 0, 0))
	if mask.a > 0.0:
		_ellipse(img, Vector2(88, 128), 46.0, 58.0, mask)
		_ellipse(img, Vector2(168, 128), 46.0, 58.0, mask)
		_ellipse(img, Vector2(128, 170), 62.0, 40.0, mask)
	if f.get("whiskers", false):
		for sx: float in [-1.0, 1.0]:
			for k in 3:
				_line(img, Vector2(128.0 + sx * 46.0, 150.0 + k * 9.0), Vector2(128.0 + sx * 104.0, 140.0 + k * 14.0), 3.0, Color(0.35, 0.22, 0.18, 0.8))
	var eye_dx := 50.0
	var eyes: String = f.get("eyes", "round")
	for sx: float in [-1.0, 1.0]:
		var cx := 128.0 + sx * eye_dx
		if eyes == "happy":
			_arc(img, Vector2(cx, eye_y + 10), 17.0, PI * 1.12, PI * 1.88, 7.0, ink)
		else:
			_ellipse(img, Vector2(cx, eye_y), 13.0, 19.0, ink)
			_ellipse(img, Vector2(cx + 4.0, eye_y - 7.0), 4.5, 5.5, Color(1, 1, 1))
			_ellipse(img, Vector2(cx - 4.0, eye_y + 8.0), 2.2, 2.2, Color(1, 1, 1, 0.9))
		if f.get("lash", false):
			_line(img, Vector2(cx + sx * 12.0, eye_y - 14.0), Vector2(cx + sx * 20.0, eye_y - 20.0), 4.0, ink)
		var brow: Color = f.get("brows", Color(0, 0, 0, 0))
		if brow.a > 0.0:
			_line(img, Vector2(cx - 14.0, eye_y - 32.0 - sx * 1.5), Vector2(cx + 14.0, eye_y - 32.0 + sx * 1.5), 6.0, brow)
	if f.get("blush", true):
		for sx: float in [-1.0, 1.0]:
			_ellipse(img, Vector2(128.0 + sx * 72.0, 152.0), 17.0, 9.0, Color(1.0, 0.5, 0.5, 0.55))
	match f.get("mouth", "smile"):
		"smile":
			_arc(img, Vector2(128, 150), 15.0, PI * 0.15, PI * 0.85, 5.0, ink)
		"cat":
			_arc(img, Vector2(120, 156), 8.0, PI * 0.1, PI * 0.9, 4.0, ink)
			_arc(img, Vector2(136, 156), 8.0, PI * 0.1, PI * 0.9, 4.0, ink)
		"grin":
			# Open happy mouth: a filled half-moon with a hint of teeth.
			for y in range(150, 176):
				for x in range(100, 157):
					var d := Vector2((x - 128.0) / 27.0, (y - 150.0) / 24.0)
					if d.length() <= 1.0:
						img.set_pixel(x, y, Color(0.45, 0.13, 0.16) if y > 157 else Color(1, 1, 1))
			_ellipse(img, Vector2(128, 170), 11.0, 5.0, Color(0.95, 0.5, 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var base := img.get_pixel(x, y)
	var aa := c.a * a
	var out := Color(lerpf(base.r, c.r, aa), lerpf(base.g, c.g, aa), lerpf(base.b, c.b, aa), maxf(base.a, aa))
	if base.a == 0.0:
		out = Color(c.r, c.g, c.b, aa)
	img.set_pixel(x, y, out)


static func _ellipse(img: Image, c: Vector2, rx: float, ry: float, col: Color) -> void:
	for y in range(int(c.y - ry - 2), int(c.y + ry + 3)):
		for x in range(int(c.x - rx - 2), int(c.x + rx + 3)):
			var d := Vector2((x + 0.5 - c.x) / rx, (y + 0.5 - c.y) / ry).length()
			var a := clampf((1.0 - d) * minf(rx, ry) + 0.5, 0.0, 1.0)
			if a > 0.0:
				_blend(img, x, y, col, a)


static func _arc(img: Image, c: Vector2, r: float, a0: float, a1: float, w: float, col: Color) -> void:
	for y in range(int(c.y - r - w), int(c.y + r + w + 1)):
		for x in range(int(c.x - r - w), int(c.x + r + w + 1)):
			var p := Vector2(x + 0.5, y + 0.5) - c
			var ang := fposmod(atan2(p.y, p.x), TAU)
			if ang < a0 or ang > a1:
				continue
			var d := absf(p.length() - r)
			var a := clampf(w * 0.5 - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				_blend(img, x, y, col, a)


static func _line(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(w, w)
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(w, w)
	var ab := b - a
	for y in range(int(mn.y), int(mx.y) + 1):
		for x in range(int(mn.x), int(mx.x) + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			var al := clampf(w * 0.5 - d + 0.5, 0.0, 1.0)
			if al > 0.0:
				_blend(img, x, y, col, al)

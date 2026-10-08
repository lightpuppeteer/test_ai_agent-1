class_name GrassField
extends RefCounted
## A carpet of short, soft grass tufts over the island's lawns (Animal Crossing
## style), as chunked MultiMeshes that fade out with distance. The blades sway
## and bend away from Tatiana and Marco (shaders/grass_field.gdshader).

const CELL := 12.0
const SPACING := 0.42          # average distance between tufts
const RANGE := 34.0            # visible up to this distance

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://shaders/grass_field.gdshader")
	return _mat


## One tuft: 7 soft blades (3 triangles each) fanning out, ~0.2 m tall. UV.y = height fraction.
static func mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n := 7
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		var side := d.cross(Vector3.UP).normalized()
		var hh := rng.randf_range(0.14, 0.24)
		var lean := rng.randf_range(0.04, 0.09)
		var root := d * rng.randf_range(0.0, 0.07)
		var widths := [0.04, 0.034, 0.0]
		var rows := []
		for s in 3:
			var t := s / 2.0
			var p := root + d * lean * t * t + Vector3(0, hh * t - 0.02, 0)
			var w: float = widths[s]
			rows.append([p - side * w, p + side * w, t])
		for s in 2:
			var r0: Array = rows[s]
			var r1: Array = rows[s + 1]
			if s == 1:
				# Pointed tip: a single triangle.
				_v(st, r0[0], r0[2]); _v(st, r1[0], r1[2]); _v(st, r0[1], r0[2])
				continue
			_v(st, r0[0], r0[2]); _v(st, r1[0], r1[2]); _v(st, r1[1], r1[2])
			_v(st, r0[0], r0[2]); _v(st, r1[1], r1[2]); _v(st, r0[1], r0[2])
	_mesh = st.commit()
	return _mesh


static func _v(st: SurfaceTool, p: Vector3, h: float) -> void:
	st.set_uv(Vector2(0.5, h))
	st.set_normal(Vector3.UP)
	st.add_vertex(p)


## Scatter tufts over grassy ground (not paths, paving, sand, cliffs or props).
static func build(b: IslandBuilder) -> void:
	var t0 := Time.get_ticks_msec()
	var T: Terrain = b.T
	# Occupied circles bucketed on a coarse grid for quick "is clear" checks.
	var occ := {}
	for c in b.occupied:
		var r: float = c.z
		for gx in range(floori((c.x - r) / 4.0), floori((c.x + r) / 4.0) + 1):
			for gz in range(floori((c.y - r) / 4.0), floori((c.y + r) / 4.0) + 1):
				var k := Vector2i(gx, gz)
				if not occ.has(k):
					occ[k] = []
				occ[k].append(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var cells := {}
	var count := 0
	var x := -72.0
	while x < 72.0:
		var z := -68.0
		while z < 28.0:
			var px := x + rng.randf_range(-0.45, 0.45) * SPACING
			var pz := z + rng.randf_range(-0.45, 0.45) * SPACING
			z += SPACING
			var h := b.ground(px, pz)
			if h < 1.45:
				continue
			var sp := T.splat_at(px, pz)
			if sp.r > 0.25 or sp.g > 0.25 or sp.b > 0.25 or sp.a > 0.3:
				continue
			if T.normal_at(px, pz).y < 0.84:
				continue
			var clear := true
			for c in occ.get(Vector2i(floori(px / 4.0), floori(pz / 4.0)), []):
				if Vector2(c.x, c.y).distance_to(Vector2(px, pz)) < c.z * 0.85:
					clear = false
					break
			if not clear:
				continue
			var key := Vector2i(floori(px / CELL), floori(pz / CELL))
			if not cells.has(key):
				cells[key] = []
			cells[key].append([Vector3(px, h - 0.01, pz), rng.randf() * TAU, rng.randf_range(0.75, 1.25), rng.randf()])
			count += 1
		x += SPACING
	var m := mesh()
	for key in cells:
		var list: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m
		mm.instance_count = list.size()
		for i in list.size():
			var it: Array = list[i]
			var s: float = it[2]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, it[1]).scaled(Vector3(s, s * randf_range(0.85, 1.15), s)), it[0]))
			mm.set_instance_custom_data(i, Color(it[3], 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass_%d_%d" % [key.x, key.y]
		mmi.multimesh = mm
		mmi.material_override = material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = RANGE
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		b.add_child(mmi)
	if Game.options.has("navdump") or Game.options.has("grassinfo"):
		print("[grass] %d tufts in %d cells, %d ms" % [count, cells.size(), Time.get_ticks_msec() - t0])

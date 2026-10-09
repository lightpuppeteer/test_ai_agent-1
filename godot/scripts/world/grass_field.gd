class_name GrassField
extends RefCounted
## A thick carpet of short, soft grass over the island's lawns (Animal Crossing
## style). Each MultiMesh instance is a whole 1 m turf of single-triangle blades;
## the shader (shaders/grass_field.gdshader) sits every blade on the real ground
## height, hides blades that land on paths, paving, sand or soil, hands over
## smoothly between three detail levels out to 100 m, sways them in the wind and
## bends them away from Tatiana and Marco.

const CELL := 12.0             # metres per culling chunk
const SPACING := 0.78          # distance between turf centres
const RANGE := 100.0           # the lawn is drawn out to this distance
const FADE := 6.0              # metres over which one detail level hands over to the next

## Detail levels, all on the same turfs: near ones have many fine blades, far
## ones a few wide ones (the same coverage at a fraction of the triangles).
## [blades per turf, blade width scale, from (m), to (m)]
const LODS := [
	[92, 1.0, 0.0, 30.0],
	[30, 1.7, 30.0 - FADE, 62.0],
	[10, 2.8, 62.0 - FADE, RANGE],
]

static var _meshes := {}
static var _mats: Array[ShaderMaterial] = []


static func material(t: Terrain, lod: int) -> ShaderMaterial:
	while _mats.size() <= lod:
		_mats.append(null)
	if _mats[lod] == null:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/grass_field.gdshader")
		m.set_shader_parameter("height_tex", t.height_texture)
		m.set_shader_parameter("height_info", Vector3(Terrain.SIZE, float(Terrain.N), 0.0))
		m.set_shader_parameter("splat", t.splat_texture)
		var r := Terrain.SPLAT_RECT
		m.set_shader_parameter("splat_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		var l: Array = LODS[lod]
		var from: float = l[2]
		var to: float = l[3]
		# Grow in over [from, from + FADE] (not the nearest level), shrink out over [to - FADE, to].
		m.set_shader_parameter("lod_in", Vector2(from, from + FADE) if lod > 0 else Vector2(-2.0, -1.0))
		m.set_shader_parameter("lod_out", Vector2(to - FADE, to))
		_mats[lod] = m
	return _mats[lod]


## Pull the far edge of the lawn in (the quality governor does this when the
## GPU is struggling) or back out to RANGE.
static func set_far_limit(metres: float) -> void:
	for i in _mats.size():
		var m := _mats[i]
		if m == null:
			continue
		var to: float = minf(float(LODS[i][3]), metres)
		m.set_shader_parameter("lod_out", Vector2(to - FADE, to))


## One turf: single-triangle blades scattered over a 1 m square (with a little
## spill so neighbouring turfs knit together). UV.y = height fraction,
## UV.x = per-blade random, UV2 = the blade's root (x, z) in the turf.
static func mesh(lod: int) -> ArrayMesh:
	if _meshes.has(lod):
		return _meshes[lod]
	var blades: int = LODS[lod][0]
	var wk: float = LODS[lod][1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + lod
	for i in blades:
		var root := Vector3(rng.randf_range(-0.56, 0.56), 0, rng.randf_range(-0.56, 0.56))
		var a := rng.randf() * TAU
		var side := Vector3(cos(a), 0, sin(a))
		var lean_dir := side.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
		var h := rng.randf_range(0.13, 0.27)
		var w := rng.randf_range(0.03, 0.045) * wk
		var tip := root + lean_dir * rng.randf_range(0.02, 0.08) + Vector3(0, h, 0)
		var r := rng.randf()
		var r2 := Vector2(root.x, root.z)
		for v: Array in [[root - side * w - Vector3(0, 0.03, 0), 0.0], [tip, 1.0], [root + side * w - Vector3(0, 0.03, 0), 0.0]]:
			st.set_uv(Vector2(r, v[1]))
			st.set_uv2(r2)
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-0.7, -3.0, -0.7), Vector3(1.4, 6.0, 1.4))
	_meshes[lod] = m
	return m


## Lay turfs over every grassy patch (the shader trims the edges per blade).
static func build(b: IslandBuilder) -> void:
	var t0 := Time.get_ticks_msec()
	var T: Terrain = b.T
	# Occupied circles (houses, props) bucketed on a coarse grid for quick checks.
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
		while z < 30.0:
			var px := x + rng.randf_range(-0.3, 0.3) * SPACING
			var pz := z + rng.randf_range(-0.3, 0.3) * SPACING
			z += SPACING
			var h := b.ground(px, pz)
			if h < 1.3:
				continue
			# Keep turfs whose centre is grassy or right next to grass.
			var sp := T.splat_at(px, pz)
			if sp.r > 0.7 or sp.g > 0.7 or sp.b > 0.7 or sp.a > 0.7:
				continue
			if T.normal_at(px, pz).y < 0.8:
				continue
			var clear := true
			for c in occ.get(Vector2i(floori(px / 4.0), floori(pz / 4.0)), []):
				if Vector2(c.x, c.y).distance_to(Vector2(px, pz)) < c.z * 0.75:
					clear = false
					break
			if not clear:
				continue
			var key := Vector2i(floori(px / CELL), floori(pz / CELL))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.15)), Vector3(px, h, pz)))
			count += 1
		x += SPACING
	for key in cells:
		var list: Array = cells[key]
		for lod in LODS.size():
			var l: Array = LODS[lod]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh(lod)
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Grass_%d_%d_%d" % [key.x, key.y, lod]
			mmi.multimesh = mm
			mmi.material_override = material(T, lod)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Whole chunks switch on/off a little outside each level's band (the
			# shader does the smooth hand-over per blade).
			mmi.visibility_range_begin = maxf(float(l[2]) - CELL * 0.75, 0.0)
			mmi.visibility_range_end = float(l[3]) + CELL * 0.75
			b.add_child(mmi)
	if Game.options.has("navdump") or Game.options.has("grassinfo"):
		print("[grass] %d turfs in %d cells x %d detail levels, %d ms" % [count, cells.size(), LODS.size(), Time.get_ticks_msec() - t0])

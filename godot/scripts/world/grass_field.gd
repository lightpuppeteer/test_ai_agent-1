class_name GrassField
extends RefCounted
## A thick carpet of short, soft grass over the island's lawns (Animal Crossing
## style). Each MultiMesh instance is a whole 1 m turf of single-triangle blades;
## the shader (shaders/grass_field.gdshader) sits every blade on the real ground
## height, hides blades that land on paths, paving, sand or soil, shrinks them
## into the ground towards the edge of the draw distance, sways them in the
## wind and bends them away from Tatiana and Marco.

const CELL := 12.0             # metres per culling chunk
const SPACING := 0.78          # distance between turf centres
const BLADES := 92             # blades per turf
const RANGE := 27.0            # drawn up to this distance (blades shrink away before it)

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial


static func material(t: Terrain) -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://shaders/grass_field.gdshader")
		_mat.set_shader_parameter("height_tex", t.height_texture)
		_mat.set_shader_parameter("height_info", Vector3(Terrain.SIZE, float(Terrain.N), 0.0))
		_mat.set_shader_parameter("splat", t.splat_texture)
		var r := Terrain.SPLAT_RECT
		_mat.set_shader_parameter("splat_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		_mat.set_shader_parameter("fade_end", RANGE - 1.0)
	return _mat


## One turf: BLADES single-triangle blades scattered over a 1 m square (with a
## little spill so neighbouring turfs knit together). UV.y = height fraction,
## UV.x = per-blade random, UV2 = the blade's root (x, z) in the turf.
static func mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in BLADES:
		var root := Vector3(rng.randf_range(-0.56, 0.56), 0, rng.randf_range(-0.56, 0.56))
		var a := rng.randf() * TAU
		var side := Vector3(cos(a), 0, sin(a))
		var lean_dir := side.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
		var h := rng.randf_range(0.13, 0.27)
		var w := rng.randf_range(0.03, 0.045)
		var tip := root + lean_dir * rng.randf_range(0.02, 0.08) + Vector3(0, h, 0)
		var r := rng.randf()
		var r2 := Vector2(root.x, root.z)
		for v: Array in [[root - side * w - Vector3(0, 0.03, 0), 0.0], [tip, 1.0], [root + side * w - Vector3(0, 0.03, 0), 0.0]]:
			st.set_uv(Vector2(r, v[1]))
			st.set_uv2(r2)
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	_mesh = st.commit()
	_mesh.custom_aabb = AABB(Vector3(-0.7, -3.0, -0.7), Vector3(1.4, 6.0, 1.4))
	return _mesh


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
	var m := mesh()
	var mat := material(T)
	for key in cells:
		var list: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass_%d_%d" % [key.x, key.y]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = RANGE + CELL * 0.7
		b.add_child(mmi)
	if Game.options.has("navdump") or Game.options.has("grassinfo"):
		print("[grass] %d turfs (%d blades) in %d cells, %d ms" % [count, count * BLADES, cells.size(), Time.get_ticks_msec() - t0])

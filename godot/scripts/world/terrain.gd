class_name Terrain
extends Node3D
## The island ground: a heightfield generated from WorldLayout, rendered with the
## painted-ground shader and mirrored by a HeightMapShape3D collider.
## `height_at()` uses the same grid (bilinear), so gameplay, collision and the
## water shader all agree.

const SIZE := 240.0                 # metres covered by the heightfield (square, centred at origin)
const N := 481                      # vertices per side (0.5 m spacing)
const CHUNK := 48                   # cells per mesh chunk side (24 m)
const SPLAT_RECT := Rect2(-80.0, -72.0, 160.0, 118.0)   # x, z, width, depth (island bounds)
const SPLAT_PX_PER_M := 2.0
const SHADER := preload("res://shaders/terrain.gdshader")

var heights := PackedFloat32Array()
var height_texture: ImageTexture
var splat_texture: ImageTexture
var splat_image: Image
var material: ShaderMaterial
var _noise := FastNoiseLite.new()


func _ready() -> void:
	Game.terrain = self
	var t0 := Time.get_ticks_msec()
	_noise.seed = 1717
	_noise.frequency = 0.035
	_noise.fractal_octaves = 3
	_build_heights()
	_build_textures()
	_build_mesh()
	_build_collider()
	print("[terrain] built in %d ms" % (Time.get_ticks_msec() - t0))


# ---------------------------------------------------------------------------
# Heights
# ---------------------------------------------------------------------------

func compute_height(x: float, z: float) -> float:
	var L := WorldLayout
	var sd := L.island_sd(x, z)
	var bw := L.beach_width(z)
	var hill := L.hill_mask(x, z)
	var flat := L.is_flat_zone(x, z)
	var land := lerpf(L.LAND_HEIGHT, L.HILL_HEIGHT, hill)
	# Gentle rolling meadows, kept flat where the town needs it.
	land += _noise.get_noise_2d(x, z) * 0.45 * (1.0 - flat) * (1.0 - 0.6 * hill)
	# Beach: from the top of the sandbank down to the waterline, then the sea floor.
	var beach_top := 1.15
	var beach: float
	if sd < 0.0:
		var u := clampf((sd + bw) / bw, 0.0, 1.0)
		beach = beach_top * (1.0 - u) * (1.0 - 0.25 * u * (1.0 - u))
	else:
		beach = -minf(sd * 0.22 + sd * sd * 0.004, 7.0)
	var bank := smoothstep(-(bw + 2.6), -bw, sd)
	var h := lerpf(land, beach, bank)
	# The little oasis island out at sea (south-east).
	var od := Vector2(x, z).distance_to(Places.OASIS) - Places.OASIS_R + 1.2 * sin(atan2(z - Places.OASIS.y, x - Places.OASIS.x) * 3.0)
	if od < 14.0:
		var oh: float
		if od < -5.0:
			oh = 1.6 + _noise.get_noise_2d(x * 2.0, z * 2.0) * 0.15
			# Pond dip in the middle.
			var pd := Vector2(x, z).distance_to(Places.OASIS + Vector2(3.0, 2.0))
			oh -= 1.1 * smoothstep(3.6, 2.0, pd)
		elif od < 0.0:
			var u := (od + 5.0) / 5.0
			oh = lerpf(1.6, 0.0, smoothstep(0.0, 1.0, u))
		else:
			oh = -minf(od * 0.35, 7.0)
		h = maxf(h, oh)
	return h


func _build_heights() -> void:
	heights.resize(N * N)
	var half := SIZE * 0.5
	var step := SIZE / float(N - 1)
	for j in N:
		var z := -half + j * step
		for i in N:
			var x := -half + i * step
			heights[j * N + i] = compute_height(x, z)


func height_at(x: float, z: float) -> float:
	var half := SIZE * 0.5
	var step := SIZE / float(N - 1)
	var fx := clampf((x + half) / step, 0.0, N - 1.001)
	var fz := clampf((z + half) / step, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	# Same triangle split as HeightMapShape3D / the render mesh (diagonal from (i,j) to (i+1,j+1)).
	var h00 := heights[j * N + i]
	var h10 := heights[j * N + i + 1]
	var h01 := heights[(j + 1) * N + i]
	var h11 := heights[(j + 1) * N + i + 1]
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


# ---------------------------------------------------------------------------
# Textures (ground paint + height for the water shader)
# ---------------------------------------------------------------------------

func _build_textures() -> void:
	var L := WorldLayout
	var w := int(SPLAT_RECT.size.x * SPLAT_PX_PER_M)
	var h := int(SPLAT_RECT.size.y * SPLAT_PX_PER_M)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		var z := SPLAT_RECT.position.y + (py + 0.5) / SPLAT_PX_PER_M
		for px in w:
			var x := SPLAT_RECT.position.x + (px + 0.5) / SPLAT_PX_PER_M
			# r: dirt path, g: paving (plaza + promenade), b: road cobbles, a: flower-bed soil
			var path := smoothstep(L.PATH_WIDTH * 0.5 + 0.35, L.PATH_WIDTH * 0.5 - 0.35, L.path_sd(x, z))
			var plaza_d := Vector2(x, z).distance_to(L.PLAZA_CENTER)
			var plaza := smoothstep(L.PLAZA_RADIUS + 0.3, L.PLAZA_RADIUS - 0.3, plaza_d)
			var prom := 0.0
			if x > L.PROMENADE_X.x and x < L.PROMENADE_X.y:
				prom = smoothstep(L.PROMENADE_Z.x - 0.3, L.PROMENADE_Z.x + 0.3, z) * smoothstep(L.PROMENADE_Z.y + 0.3, L.PROMENADE_Z.y - 0.3, z)
			var road := smoothstep(L.ROAD_WIDTH * 0.5 + 0.3, L.ROAD_WIDTH * 0.5 - 0.3, L.road_sd(x, z))
			# Where the branch road crosses the promenade, the road wins.
			img.set_pixel(px, py, Color(path * (1.0 - road), maxf(plaza, prom) * (1.0 - road), road, 0.0))
	splat_image = img
	splat_texture = ImageTexture.create_from_image(img)

	var himg := Image.create(N, N, false, Image.FORMAT_RF)
	for j in N:
		for i in N:
			himg.set_pixel(i, j, Color(heights[j * N + i], 0, 0))
	height_texture = ImageTexture.create_from_image(himg)


## Paints extra ground marks (e.g. soil under flower beds) into the alpha channel.
func paint_soil(center: Vector2, radius: float) -> void:
	var img := splat_image
	var r_px := int(ceil(radius * SPLAT_PX_PER_M)) + 1
	var cx := int((center.x - SPLAT_RECT.position.x) * SPLAT_PX_PER_M)
	var cy := int((center.y - SPLAT_RECT.position.y) * SPLAT_PX_PER_M)
	for py in range(cy - r_px, cy + r_px + 1):
		for px in range(cx - r_px, cx + r_px + 1):
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			var d := Vector2(px - cx, py - cy).length() / SPLAT_PX_PER_M
			var a := smoothstep(radius, radius - 0.4, d)
			var c := img.get_pixel(px, py)
			c.a = maxf(c.a, a)
			img.set_pixel(px, py, c)
	splat_texture.update(img)


func splat_at(x: float, z: float) -> Color:
	var img := splat_image
	var px := int((x - SPLAT_RECT.position.x) * SPLAT_PX_PER_M)
	var py := int((z - SPLAT_RECT.position.y) * SPLAT_PX_PER_M)
	if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
		return Color(0, 0, 0, 0)
	return img.get_pixel(px, py)


# ---------------------------------------------------------------------------
# Mesh + collider
# ---------------------------------------------------------------------------

func _build_mesh() -> void:
	var half := SIZE * 0.5
	var step := SIZE / float(N - 1)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(N * N)
	normals.resize(N * N)
	uvs.resize(N * N)
	for j in N:
		for i in N:
			var x := -half + i * step
			var z := -half + j * step
			var k := j * N + i
			verts[k] = Vector3(x, heights[k], z)
			var hl := heights[j * N + maxi(i - 1, 0)]
			var hr := heights[j * N + mini(i + 1, N - 1)]
			var hd := heights[maxi(j - 1, 0) * N + i]
			var hu := heights[mini(j + 1, N - 1) * N + i]
			normals[k] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			uvs[k] = Vector2(float(i) / (N - 1), float(j) / (N - 1))
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("splat", splat_texture)
	material.set_shader_parameter("splat_rect", Vector4(SPLAT_RECT.position.x, SPLAT_RECT.position.y, SPLAT_RECT.size.x, SPLAT_RECT.size.y))
	# Chunks, so the camera and each shadow split only draw the bits they can see.
	var ground := Node3D.new()
	ground.name = "Ground"
	add_child(ground)
	var C := CHUNK
	var cj := 0
	while cj < N - 1:
		var ci := 0
		while ci < N - 1:
			var w := mini(C, N - 1 - ci)
			var h := mini(C, N - 1 - cj)
			var cv := PackedVector3Array()
			var cn := PackedVector3Array()
			var cu := PackedVector2Array()
			var top := -INF
			for j in range(cj, cj + h + 1):
				for i in range(ci, ci + w + 1):
					var k := j * N + i
					cv.append(verts[k])
					cn.append(normals[k])
					cu.append(uvs[k])
					top = maxf(top, verts[k].y)
			var idx := PackedInt32Array()
			var row := w + 1
			for j in h:
				for i in w:
					var a := j * row + i
					var b := a + 1
					var c := a + row
					var d := c + 1
					# Diagonal a–d, matching height_at().
					idx.append_array([a, b, d, a, d, c])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = cv
			arrays[Mesh.ARRAY_NORMAL] = cn
			arrays[Mesh.ARRAY_TEX_UV] = cu
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, material)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci / C, cj / C]
			mi.mesh = mesh
			# Sea floor never needs to cast shadows.
			if top < -0.5:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ground.add_child(mi)
			ci += C
		cj += C


func _build_collider() -> void:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = Game.PHYS_WORLD
	body.collision_mask = 0
	add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var step := SIZE / float(N - 1)
	cs.scale = Vector3(step, 1.0, step)
	body.add_child(cs)

class_name CorsaMesh
extends RefCounted
## A cute, slightly chunky early-2000s supermini (think Corsa C): rounded hatch
## body, big teardrop headlights, tall glasshouse with room for two big chibi
## heads. Built from soft rounded boxes; car faces +Z, origin at axle height 0.
## Proportions are stylised (wider and taller than the real thing).

const PAINT := Color(0.78, 0.13, 0.14)
const GLASS := Color(0.36, 0.52, 0.7, 0.72)
const TRIM := Color(0.16, 0.16, 0.18)
const CHROME := Color(0.78, 0.8, 0.84)
const HEAD := Color(1.0, 0.97, 0.88)
const TAIL := Color(0.95, 0.12, 0.1)
const AMBER := Color(1.0, 0.62, 0.15)

const WIDTH := 2.08
const LENGTH := 3.9
const WHEEL_R := 0.37
const WHEEL_X := 0.9
const WHEEL_Z := 1.26

static var _cache := {}


## {"body": ArrayMesh, "wheel": ArrayMesh}
static func build(paint: Color = PAINT) -> Dictionary:
	var key := paint.to_html()
	if _cache.has(key):
		return _cache[key]
	var surf := {}   # material kind -> SurfaceTool
	for k in ["paint", "glass", "trim", "chrome", "light"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surf[k] = st
	var W := WIDTH
	var L := LENGTH
	# Lower body (narrower, so the tyres show), with round fenders over the
	# wheels and fuller door panels between them.
	_rbox(surf["paint"], Vector3(W - 0.26, 0.5, L), Vector3(0, 0.46, 0), paint, 0.2, {"shade": 0.12})
	for wz in [WHEEL_Z, -WHEEL_Z]:
		_rbox(surf["paint"], Vector3(W, 0.3, 1.18), Vector3(0, 0.66, wz), paint, 0.13, {})
	_rbox(surf["paint"], Vector3(W - 0.04, 0.44, 1.36), Vector3(0, 0.52, 0.0), paint, 0.14, {"shade": 0.1})
	# Bonnet: drops toward the nose.
	_rbox(surf["paint"], Vector3(W - 0.06, 0.26, 1.1), Vector3(0, 0.78, 1.33), paint, 0.12, {"slope": -0.16})
	# Shoulder band under the windows.
	_rbox(surf["paint"], Vector3(W - 0.02, 0.22, 2.6), Vector3(0, 0.82, -0.42), paint, 0.1, {})
	# Glasshouse: tall and rounded, raked windscreen, short steep hatch.
	_rbox(surf["glass"], Vector3(W - 0.2, 0.68, 2.45), Vector3(0, 1.22, -0.42), GLASS, 0.16,
			{"top_x": 0.9, "rake_front": 0.75, "rake_back": 0.22})
	# Roof over the glass.
	_rbox(surf["paint"], Vector3(W - 0.3, 0.12, 1.72), Vector3(0, 1.56, -0.62), paint, 0.06, {"top_x": 0.96})
	for sx in [-1.0, 1.0]:
		# B-pillar and the door's window frame.
		_rbox(surf["paint"], Vector3(0.06, 0.62, 0.12), Vector3(sx * (W * 0.5 - 0.13), 1.22, -0.25), paint, 0.03, {"rot": Vector3(0, 0, sx * 6.0)})
		# Wide C-pillar (the hatchback's rear quarter).
		_rbox(surf["paint"], Vector3(0.07, 0.6, 0.4), Vector3(sx * (W * 0.5 - 0.15), 1.2, -1.4), paint, 0.03, {"rot": Vector3(0, 0, sx * 6.0), "rake_back": 0.18})
		# A-pillar along the windscreen.
		_rbox(surf["paint"], Vector3(0.06, 0.98, 0.08), Vector3(sx * (W * 0.5 - 0.17), 1.22, 0.44), paint, 0.03, {"rot": Vector3(-47, 0, sx * 6.0)})
		# Side rubbing strip.
		_rbox(surf["trim"], Vector3(0.03, 0.06, 1.3), Vector3(sx * (W * 0.5 - 0.01), 0.42, 0.0), TRIM, 0.02, {})
		# Door line + handle.
		_rbox(surf["trim"], Vector3(0.02, 0.4, 0.025), Vector3(sx * (W * 0.5 - 0.015), 0.56, 0.66), TRIM, 0.008, {})
		_rbox(surf["chrome"], Vector3(0.04, 0.05, 0.16), Vector3(sx * (W * 0.5 - 0.01), 0.68, 0.4), CHROME, 0.02, {})
		# Mirrors.
		_rbox(surf["paint"], Vector3(0.2, 0.13, 0.12), Vector3(sx * (W * 0.5 + 0.06), 0.98, 0.72), paint, 0.05, {})
		# Big teardrop headlights and tall tail lights.
		_rbox(surf["light"], Vector3(0.42, 0.17, 0.14), Vector3(sx * 0.62, 0.72, L * 0.5 - 0.08), HEAD, 0.07, {"rot": Vector3(-14, 0, sx * -12.0), "top_x": 0.75})
		_rbox(surf["light"], Vector3(0.12, 0.08, 0.1), Vector3(sx * 0.9, 0.66, L * 0.5 - 0.12), AMBER, 0.03, {})
		_rbox(surf["light"], Vector3(0.22, 0.4, 0.12), Vector3(sx * 0.82, 0.86, -L * 0.5 + 0.02), TAIL, 0.06, {})
	# Bumpers, grille, little round badge.
	# Body-coloured bumpers (very 2002) with a dark rubbing strip.
	_rbox(surf["paint"], Vector3(W - 0.22, 0.22, 0.18), Vector3(0, 0.33, L * 0.5 - 0.02), paint.darkened(0.06), 0.08, {})
	_rbox(surf["paint"], Vector3(W - 0.22, 0.22, 0.18), Vector3(0, 0.33, -L * 0.5 + 0.02), paint.darkened(0.06), 0.08, {})
	_rbox(surf["trim"], Vector3(W - 0.3, 0.05, 0.03), Vector3(0, 0.27, L * 0.5 + 0.075), TRIM, 0.02, {})
	_rbox(surf["trim"], Vector3(W - 0.3, 0.05, 0.03), Vector3(0, 0.27, -L * 0.5 - 0.075), TRIM, 0.02, {})
	_rbox(surf["trim"], Vector3(0.7, 0.13, 0.08), Vector3(0, 0.6, L * 0.5 + 0.02), TRIM, 0.04, {})
	_rbox(surf["chrome"], Vector3(0.12, 0.12, 0.05), Vector3(0, 0.75, L * 0.5 + 0.03), CHROME, 0.05, {})
	# Number plates.
	_rbox(surf["chrome"], Vector3(0.5, 0.12, 0.03), Vector3(0, 0.36, L * 0.5 + 0.085), Color(0.96, 0.96, 0.92), 0.01, {})
	_rbox(surf["chrome"], Vector3(0.5, 0.12, 0.03), Vector3(0, 0.62, -L * 0.5 - 0.01), Color(0.96, 0.96, 0.92), 0.01, {})
	var body := ArrayMesh.new()
	for k in surf:
		var st: SurfaceTool = surf[k]
		body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		body.surface_set_material(body.get_surface_count() - 1, _material(k))
	# Wheel: tyre + hub (axis along X).
	var ws := SurfaceTool.new()
	ws.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cylinder(ws, WHEEL_R, 0.3, Color(0.12, 0.12, 0.13), 20)
	_cylinder(ws, WHEEL_R * 0.55, 0.32, CHROME, 14)
	var wheel := ws.commit()
	wheel.surface_set_material(0, _material("trim"))
	var out := {"body": body, "wheel": wheel}
	_cache[key] = out
	return out


static func _material(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match kind:
		"paint":
			m.roughness = 0.3
			m.metallic_specular = 0.7
		"glass":
			# See-through, so you can see the two of you inside.
			m.roughness = 0.08
			m.metallic_specular = 0.9
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_BACK
		"chrome":
			m.roughness = 0.25
			m.metallic = 0.6
		"light":
			m.roughness = 0.2
			m.emission_enabled = true
			m.emission = Color(1, 1, 1)
			m.emission_energy_multiplier = 0.25
		_:
			m.roughness = 0.8
	return m


## A rounded box with optional shaping: top_x (top narrower), rake_front /
## rake_back (top edge pulled in, for windscreens), slope (front lower), rot.
static func _rbox(st: SurfaceTool, size: Vector3, at: Vector3, col: Color, r: float, o: Dictionary) -> void:
	var h := size * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.95)
	var rb: Array = Avatar._round_box(h, r)
	var pos: PackedVector3Array = rb[0]
	var nrm: PackedVector3Array = rb[1]
	var rot: Vector3 = o.get("rot", Vector3.ZERO)
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	var shade: float = o.get("shade", 0.06)
	for i in pos.size():
		var v: Vector3 = pos[i]
		var n: Vector3 = nrm[i]
		var u := (v.y + h.y) / size.y          # 0 bottom … 1 top
		if o.has("top_x"):
			v.x *= lerpf(1.0, float(o["top_x"]), u)
		if o.has("rake_front") and v.z > 0.0:
			v.z -= float(o["rake_front"]) * u * (v.z / h.z)
			n = (n + Vector3(0, n.z * 0.6, 0)).normalized()
		if o.has("rake_back") and v.z < 0.0:
			v.z += float(o["rake_back"]) * u * (-v.z / h.z)
		if o.has("slope"):
			v.y += float(o["slope"]) * ((v.z + h.z) / size.z) * u
		st.set_color(col.darkened(shade * (1.0 - u)))
		st.set_normal((basis * n).normalized())
		st.add_vertex(at + basis * v)


## A cylinder along X (radius r, width w), with smooth sides.
static func _cylinder(st: SurfaceTool, r: float, w: float, col: Color, seg: int) -> void:
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := Vector3(0, cos(a0) * r, sin(a0) * r)
		var p1 := Vector3(0, cos(a1) * r, sin(a1) * r)
		var n0 := Vector3(0, cos(a0), sin(a0))
		var n1 := Vector3(0, cos(a1), sin(a1))
		var hx := Vector3(w * 0.5, 0, 0)
		for tri in [[p0 - hx, n0], [p1 + hx, n1], [p1 - hx, n1], [p0 - hx, n0], [p0 + hx, n0], [p1 + hx, n1]]:
			st.set_color(col)
			st.set_normal(tri[1])
			st.add_vertex(tri[0])
		for sx in [-1.0, 1.0]:
			var c := Vector3(sx * w * 0.5, 0, 0)
			var order := [c, p1 + c * 1.0 / 1.0, p0 + c * 1.0] if sx > 0 else [c, p0 + c, p1 + c]
			for v in order:
				st.set_color(col.darkened(0.1))
				st.set_normal(Vector3(sx, 0, 0))
				st.add_vertex(v)

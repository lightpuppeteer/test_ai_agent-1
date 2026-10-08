class_name Cottage
extends RefCounted
## Soft, rounded storybook cottages that replace the boxy suburban houses:
## pillowy plastered walls on a pebble plinth, puffy gable or mushroom-cap
## roofs, round-topped windows with flower boxes, an arched door with a little
## porch light, and a chimney. Each fits the footprint of the Kenney house it
## replaces (so doors, signs and colliders stay where they were).

const WALL := Color(0.99, 0.93, 0.82)
const STONE := Color(0.78, 0.74, 0.7)
const FRAME := Color(0.98, 0.97, 0.94)
const GLASS := Color(0.62, 0.82, 0.95)
const DOOR := Color(0.62, 0.42, 0.3)

## Kenney building footprints (kit units): size, min corner.
const SIZES := {
	"a": [Vector3(5.46, 3.5, 4.32), Vector3(-2.73, 0, -2.16)],
	"c": [Vector3(5.4, 4.34, 4.32), Vector3(-2.7, 0, -2.16)],
	"e": [Vector3(5.46, 4.78, 4.32), Vector3(-2.73, 0, -2.16)],
	"h": [Vector3(5.46, 3.1, 3.85), Vector3(-2.73, 0, -1.92)],
	"p": [Vector3(5.21, 3.86, 4.16), Vector3(-2.6, 0, -2.08)],
	"t": [Vector3(5.52, 4.86, 5.91), Vector3(-2.79, 0, -2.95)],
}
## Roof style per house type.
const ROOF := {"a": "cap", "c": "gable", "e": "gable", "h": "flat", "p": "cap", "t": "gable"}


## A finished cottage in world units for a given Kenney type, roof colour and size multiplier.
static func make(type: String, roof: Color, mul: float) -> Node3D:
	var info: Array = SIZES.get(type, SIZES["c"])
	var sz: Vector3 = (info[0] as Vector3) * mul
	var mn: Vector3 = (info[1] as Vector3) * mul
	var b := RoundKit.MB.new(1.0, hash(type) + int(roof.r * 1000))
	var cx := mn.x + sz.x * 0.5
	var cz := mn.z + sz.z * 0.5
	var w := sz.x * 0.9
	var d := sz.z * 0.9
	var style: String = ROOF.get(type, "gable")
	var two_story := type in ["c", "e", "t"]
	var wall_h := sz.y * (0.6 if two_story else 0.62)
	if style == "flat":
		wall_h = sz.y * 0.86
	# Pebble plinth and pillowy walls.
	b.rbox(Vector3(sz.x * 0.97, 0.42, sz.z * 0.97), Vector3(cx, 0.12, cz), STONE, STONE.darkened(0.15), 0.16)
	b.rbox(Vector3(w, wall_h, d), Vector3(cx, wall_h * 0.5 + 0.2, cz), WALL, WALL.darkened(0.08), minf(0.55, w * 0.1))
	# Rounded corner stones (quoins) stacked up each corner.
	for qx in [-1.0, 1.0]:
		for qz in [-1.0, 1.0]:
			var k := 0
			var qy := 0.55
			while qy < wall_h - 0.1:
				var big := k % 2 == 0
				var qs := Vector3(0.5 if big else 0.36, 0.3, 0.36 if big else 0.5)
				b.rbox(qs, Vector3(cx + qx * (w * 0.5 - qs.x * 0.35), qy, cz + qz * (d * 0.5 - qs.z * 0.35)), STONE.lightened(0.08), STONE.darkened(0.05), 0.12, Vector3.ZERO, "matte", true)
				qy += 0.42
				k += 1
	if two_story:
		# A soft belt between the floors.
		b.rbox(Vector3(w + 0.12, 0.18, d + 0.12), Vector3(cx, wall_h * 0.5 + 0.2, cz), roof.lightened(0.55), roof.lightened(0.35), 0.09)
	var top := wall_h + 0.2
	match style:
		"gable":
			_gable(b, Vector3(cx, top, cz), w + 0.7, d + 0.7, sz.y - top + 0.25, roof)
			b.rbox(Vector3(0.55, 1.3, 0.55), Vector3(cx + w * 0.28, top + (sz.y - top) * 0.55, cz - d * 0.12), STONE, STONE.darkened(0.1), 0.18)
			b.blob(Vector3(cx + w * 0.28, top + (sz.y - top) * 0.55 + 0.68, cz - d * 0.12), Vector3(0.36, 0.14, 0.36), roof.darkened(0.1), roof.darkened(0.3), 10, 5)
		"cap":
			# Mushroom-cap roof: a big soft dome with a lip, spotted like a toadstool.
			b.blob(Vector3(cx, top - 0.05, cz), Vector3(w * 0.62, (sz.y - top) * 1.25 + 0.35, d * 0.64), roof.lightened(0.08), roof.darkened(0.12), 22, 12, 0.03, Basis(), "matte", true)
			var rng := RandomNumberGenerator.new()
			rng.seed = int(roof.g * 1000)
			for i in 7:
				var a := TAU * i / 7.0 + rng.randf() * 0.4
				var e := rng.randf_range(0.35, 0.95)
				var dir := Vector3(cos(a) * sin(e), cos(e), sin(a) * sin(e))
				var p := Vector3(cx, top - 0.05, cz) + Vector3(dir.x * w * 0.62, dir.y * ((sz.y - top) * 1.25 + 0.35), dir.z * d * 0.64)
				b.disc(p, dir, Vector3.RIGHT, 0.32, 0.28, Color(1, 0.98, 0.94), Color(0.96, 0.93, 0.88), 10, 0.05, "matte")
		"flat":
			# A rounded parapet and a little rooftop garden.
			b.rbox(Vector3(w + 0.3, 0.4, d + 0.3), Vector3(cx, top + 0.1, cz), roof.lightened(0.15), roof, 0.18)
			b.blob(Vector3(cx - w * 0.25, top + 0.45, cz - d * 0.15), Vector3(0.6, 0.35, 0.5), RoundKit.LEAF, RoundKit.LEAF_DARK, 10, 6, 0.08)
			b.blob(Vector3(cx + w * 0.3, top + 0.4, cz - d * 0.2), Vector3(0.45, 0.3, 0.4), RoundKit.LEAF, RoundKit.LEAF_DARK, 10, 6, 0.08)
	# Front: arched door with a porch light, flanked by round-topped windows.
	var fz := cz + d * 0.5
	var door_h := minf(2.1, wall_h * 0.62)
	b.rbox(Vector3(1.25, door_h + 0.15, 0.12), Vector3(cx, 0.35 + door_h * 0.5, fz + 0.02), FRAME, FRAME.darkened(0.08), 0.1)
	b.rbox(Vector3(1.0, door_h, 0.12), Vector3(cx, 0.32 + door_h * 0.5, fz + 0.06), DOOR.lightened(0.05), DOOR.darkened(0.1), 0.35)
	b.blob(Vector3(cx + 0.32, 0.3 + door_h * 0.45, fz + 0.14), Vector3(0.05, 0.05, 0.05), Color(1, 0.85, 0.4), Color(0.85, 0.65, 0.3), 6, 4, 0.0, Basis(), "glossy")
	b.blob(Vector3(cx + 0.85, 0.3 + door_h + 0.15, fz + 0.12), Vector3(0.12, 0.15, 0.12), Color(1, 0.95, 0.75), Color(1, 0.82, 0.5), 8, 5, 0.0, Basis(), "glow")
	# Doorstep and two potted shrubs.
	b.rbox(Vector3(1.6, 0.18, 0.6), Vector3(cx, 0.1, fz + 0.35), STONE.lightened(0.05), STONE, 0.08)
	for sx in [-1.0, 1.0]:
		var pp := Vector3(cx + sx * 1.15, 0.0, fz + 0.4)
		b.rbox(Vector3(0.42, 0.38, 0.42), pp + Vector3(0, 0.19, 0), Color(0.86, 0.5, 0.36), Color(0.7, 0.38, 0.28), 0.12)
		b.blob(pp + Vector3(0, 0.6, 0), Vector3(0.3, 0.3, 0.3), RoundKit.LEAF, RoundKit.LEAF_DARK, 9, 6, 0.1)
	var win_y := 0.35 + door_h * 0.55
	var floors := [win_y]
	if two_story:
		floors.append(wall_h * 0.5 + 0.2 + wall_h * 0.27)
	for fy in floors:
		for sx in [-1.0, 1.0]:
			var x: float = cx + sx * w * 0.3
			if fy != win_y or absf(x - cx) > 1.2:
				_window(b, Vector3(x, fy, fz), Vector3(0, 0, 1), roof)
		if fy != win_y:
			_window(b, Vector3(cx, fy, fz), Vector3(0, 0, 1), roof)
	# Back windows.
	for fy in floors:
		for sx in [-1.0, 1.0]:
			_window(b, Vector3(cx + sx * w * 0.3, fy, cz - d * 0.5), Vector3(0, 0, -1), roof)
	# Side windows.
	for sx in [-1.0, 1.0]:
		for fy in floors:
			_window(b, Vector3(cx + sx * w * 0.5, fy, cz), Vector3(sx, 0, 0), roof)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	var root := Node3D.new()
	root.name = "Cottage"
	root.add_child(mi)
	root.set_meta("aabb", AABB(mn, sz))
	return root


## A puffy gable roof: two thick rounded slabs leaning on each other, ridge along X.
static func _gable(b: RoundKit.MB, base: Vector3, w: float, d: float, h: float, col: Color) -> void:
	var half := d * 0.5
	var ang := atan2(h, half)
	var slab_len := sqrt(half * half + h * h) + 0.25
	for s in [-1.0, 1.0]:
		var mid := base + Vector3(0, h * 0.5, s * half * 0.5)
		b.rbox(Vector3(w, 0.42, slab_len), mid, col.lightened(0.06), col.darkened(0.12), 0.2, Vector3(rad_to_deg(ang) * s, 0, 0))
	# Gable ends filled with wall, a round attic window.
	for sx in [-1.0, 1.0]:
		var pts_base := base + Vector3(sx * (w * 0.5 - 0.4), 0, 0)
		b.rbox(Vector3(0.3, h * 0.75, half * 1.2), pts_base + Vector3(0, h * 0.3, 0), WALL, WALL.darkened(0.06), 0.14)
	b.rbox(Vector3(w + 0.1, 0.3, 0.36), base + Vector3(0, h + 0.05, 0), col.darkened(0.08), col.darkened(0.2), 0.15)
	# Shingle courses: soft ridges across each slope, and a scalloped "pie crust"
	# row of tiles hanging over the eaves.
	var count := maxi(4, int(w / 0.62))
	var step := w / count
	for s: float in [-1.0, 1.0]:
		var n := Vector3(0, half, s * h).normalized()
		var tb := Basis(Vector3.RIGHT, n, Vector3.RIGHT.cross(n))
		var slope_deg := rad_to_deg(ang) * s
		for f: float in [0.3, 0.55, 0.8]:
			var cp := base + Vector3(0, h * f, s * half * (1.0 - f)) + n * 0.22
			b.rbox(Vector3(w - 0.1, 0.07, 0.16), cp, col.lightened(0.12), col, 0.035, Vector3(slope_deg, 0, 0), "matte", true)
		var eave := base + Vector3(0, -0.06, s * (half + 0.12)) + n * 0.14
		for i in count:
			var x := -w * 0.5 + step * (i + 0.5)
			b.blob(eave + Vector3(x, 0, 0), Vector3(step * 0.55, 0.09, 0.3), col.lightened(0.1), col.darkened(0.04), 8, 4, 0.0, tb)


static func _window(b: RoundKit.MB, at: Vector3, n: Vector3, accent: Color) -> void:
	var basis := Basis(Vector3.UP, atan2(n.x, n.z))
	var rot := Vector3(0, rad_to_deg(atan2(n.x, n.z)), 0)
	b.rbox(Vector3(1.0, 1.25, 0.14), at + basis * Vector3(0, 0, 0.04), FRAME, FRAME.darkened(0.08), 0.3, rot)
	b.rbox(Vector3(0.76, 1.0, 0.1), at + basis * Vector3(0, 0, 0.09), GLASS.lightened(0.15), GLASS, 0.24, rot, "glossy", true)
	b.rbox(Vector3(0.06, 0.95, 0.06), at + basis * Vector3(0, 0, 0.14), FRAME, FRAME, 0.02, rot, "matte", true)
	b.rbox(Vector3(0.72, 0.06, 0.06), at + basis * Vector3(0, 0.05, 0.14), FRAME, FRAME, 0.02, rot, "matte", true)
	# Little wooden shutters, with a heart cut-out look (a darker dot).
	for sx in [-1.0, 1.0]:
		var sp := at + basis * Vector3(sx * 0.68, 0.0, 0.05)
		b.rbox(Vector3(0.34, 1.15, 0.08), sp, accent.lightened(0.18), accent.darkened(0.05), 0.12, rot, "matte", true)
		b.blob(sp + basis * Vector3(0, 0.28, 0.045), Vector3(0.05, 0.05, 0.02), accent.darkened(0.3), accent.darkened(0.4), 6, 4, 0.0, basis)
	# Flower box.
	b.rbox(Vector3(1.05, 0.2, 0.26), at + basis * Vector3(0, -0.7, 0.16), accent.lightened(0.3), accent, 0.07, rot, "matte", true)
	var cols := [Color(1.0, 0.45, 0.55), Color(1.0, 0.85, 0.3), Color(1, 1, 1), Color(0.75, 0.6, 1.0)]
	for i in 4:
		var p := at + basis * Vector3(-0.36 + i * 0.24, -0.55, 0.2)
		b.blob(p, Vector3(0.09, 0.08, 0.09), RoundKit.LEAF, RoundKit.LEAF_DARK, 6, 4)
		b.blob(p + Vector3(0, 0.07, 0) + basis * Vector3(0, 0, 0.03), Vector3(0.05, 0.04, 0.05), cols[i], (cols[i] as Color).darkened(0.1), 5, 3)

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
## Every building gets the same kind of roof: a plain gable at one pitch.
const PITCH := 0.62          # roof rise per metre of half-depth (~32 degrees)
const OVERHANG := 0.45       # how far the eaves reach past the walls (along the slope)
const SLAB := 0.26           # roof thickness
const TRIM := Color(0.98, 0.96, 0.92)


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
	var two_story := type in ["c", "e", "t"]
	var wall_h := sz.y * (0.6 if two_story else 0.62)
	# Pebble plinth and pillowy walls.
	b.rbox(Vector3(sz.x * 0.97, 0.42, sz.z * 0.97), Vector3(cx, 0.12, cz), STONE, STONE.darkened(0.15), 0.16)
	b.rbox(Vector3(w, wall_h, d), Vector3(cx, wall_h * 0.5 + 0.2, cz), WALL, WALL.darkened(0.08), minf(0.3, w * 0.06))
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
	var rh := d * 0.5 * PITCH
	var eave := _gable(b, Vector3(cx, top, cz), w, d, rh, roof)
	sz.y = top + rh + SLAB
	# Chimney on the back slope.
	var chx := cx + w * 0.28
	var chz := cz - d * 0.2
	var chy := top + rh * (1.0 - 0.4) + 0.5
	b.rbox(Vector3(0.6, 1.4, 0.6), Vector3(chx, chy, chz), STONE.lightened(0.04), STONE.darkened(0.1), 0.12)
	b.rbox(Vector3(0.74, 0.16, 0.74), Vector3(chx, chy + 0.74, chz), STONE.darkened(0.08), STONE.darkened(0.15), 0.06)
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
	# Height and forward reach of the front eave (for shop signs).
	root.set_meta("eave", eave)
	return root


## A plain gable roof over walls w × d whose tops are at base.y, ridge along X:
## a wall-coloured attic prism (the triangular gable ends), two roof slabs with
## eaves and a ridge cap, white barge boards and fascia, faint tile courses and a
## round attic window in each gable. Returns the front eave (top y, outer z).
static func _gable(b: RoundKit.MB, base: Vector3, w: float, d: float, h: float, col: Color) -> Vector2:
	var half := d * 0.5
	var ang := atan2(h, half)
	var L := sqrt(half * half + h * h)
	var x0 := base.x - w * 0.5 + 0.02
	var x1 := base.x + w * 0.5 - 0.02
	# Attic prism: triangles at both ends, sloped faces underneath the slabs.
	var wl := WALL
	var wd := WALL.darkened(0.06)
	for xs: Array in [[x0, -1.0], [x1, 1.0]]:
		var x: float = xs[0]
		var nx := Vector3(xs[1], 0, 0)
		b.tri("matte", [Vector3(x, base.y - 0.05, base.z - half), nx, wd], [Vector3(x, base.y - 0.05, base.z + half), nx, wd], [Vector3(x, base.y + h, base.z), nx, wl])
	for s: float in [-1.0, 1.0]:
		var ns := Vector3(0, half, s * h).normalized()
		var e0 := Vector3(0, base.y - 0.05, base.z + s * half)
		var r := Vector3(0, base.y + h, base.z)
		b.tri("matte", [Vector3(x0, e0.y, e0.z), ns, wd], [Vector3(x1, e0.y, e0.z), ns, wd], [Vector3(x1, r.y, r.z), ns, wl])
		b.tri("matte", [Vector3(x0, e0.y, e0.z), ns, wd], [Vector3(x1, r.y, r.z), ns, wl], [Vector3(x0, r.y, r.z), ns, wl])
	# Roof slabs: from the overhanging eave up to just past the ridge.
	var rw := w + 0.7
	var slab_len := L + OVERHANG + 0.12
	var uc := (L + 0.12 - OVERHANG) * 0.5           # slab centre, along the slope from the eave line
	for s: float in [-1.0, 1.0]:
		var v := Vector3(0, h, -s * half) / L          # up the slope
		var n := Vector3(0, half, s * h) / L           # out of the roof
		var pe := Vector3(base.x, base.y, base.z + s * half)
		var rot := Vector3(rad_to_deg(ang) * s, 0, 0)
		b.rbox(Vector3(rw, SLAB, slab_len), pe + v * uc + n * (SLAB * 0.5), col.lightened(0.04), col.darkened(0.1), 0.08, rot)
		# Faint tile courses.
		for f: float in [0.2, 0.42, 0.64, 0.86]:
			var cp := pe + v * (L * f - OVERHANG * (1.0 - f)) + n * (SLAB + 0.01)
			b.rbox(Vector3(rw - 0.06, 0.04, 0.1), cp, col.darkened(0.08), col.darkened(0.12), 0.015, rot, "matte", true)
		# Fascia board along the eave.
		var fe := pe - v * OVERHANG + n * (SLAB * 0.5)
		b.rbox(Vector3(rw + 0.04, SLAB + 0.08, 0.1), fe, TRIM, TRIM.darkened(0.06), 0.03, rot, "matte", true)
		# Barge boards up both gable edges.
		for sx: float in [-1.0, 1.0]:
			b.rbox(Vector3(0.12, SLAB + 0.1, slab_len), pe + v * uc + n * (SLAB * 0.5) + Vector3(sx * (rw * 0.5 + 0.04), 0, 0), TRIM, TRIM.darkened(0.06), 0.04, rot, "matte", true)
	# Ridge cap.
	b.rbox(Vector3(rw + 0.12, 0.2, 0.34), Vector3(base.x, base.y + h + SLAB / cos(ang) - 0.04, base.z), col.darkened(0.12), col.darkened(0.2), 0.08)
	# A round attic window in each gable.
	for sx: float in [-1.0, 1.0]:
		var wp := Vector3(base.x + sx * (w * 0.5 + 0.02), base.y + h * 0.42, base.z)
		var nb := Basis(Vector3.UP, sx * PI * 0.5)
		b.blob(wp, Vector3(0.36, 0.36, 0.08), FRAME, FRAME.darkened(0.06), 12, 6, 0.0, nb)
		b.blob(wp + Vector3(sx * 0.04, 0, 0), Vector3(0.26, 0.26, 0.07), GLASS.lightened(0.15), GLASS, 12, 6, 0.0, nb, "glossy")
	# Front eave: the top of the fascia and how far it reaches.
	var out_z := base.z + half + OVERHANG * cos(ang) + SLAB * sin(ang) + 0.06
	var top_y := base.y - OVERHANG * sin(ang) + SLAB * cos(ang)
	return Vector2(top_y, out_z)


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

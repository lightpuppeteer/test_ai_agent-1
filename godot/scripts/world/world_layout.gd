class_name WorldLayout
extends RefCounted
## The island's layout in metres. +Z points out to sea (south), -Z inland.
## Shared by the terrain (heights + ground paint) and the prop placement so the
## two always agree.

const WATER_LEVEL := 0.0
const LAND_HEIGHT := 2.0          # main grass level
const HILL_HEIGHT := 5.2          # the lookout plateau in the north

# Island outline: a rounded rectangle with a wobbly coast.
const ISLAND_CENTER := Vector2(0.0, -13.0)
const ISLAND_HALF := Vector2(68.0, 51.0)
const ISLAND_CORNER := 26.0

# Town
const PLAZA_CENTER := Vector2(0.0, -11.0)
const PLAZA_RADIUS := 12.5
const ROAD_CENTER := Vector2(0.0, -12.0)
const ROAD_HALF := Vector2(46.0, 20.0)
const ROAD_CORNER := 11.0
const ROAD_WIDTH := 5.0
const PROMENADE_Z := Vector2(11.8, 15.4)   # z range of the paved promenade
const PROMENADE_X := Vector2(-54.0, 54.0)

# The hill (north plateau) and its ramp.
const HILL_EDGE_Z := -37.0
const RAMP_X := Vector2(25.0, 31.0)        # ramp footprint along x
const RAMP_Z := Vector2(-46.0, -35.0)      # ramp climbs from z.y (bottom) to z.x (top)

const SPAWN := Vector3(2.0, 2.2, 13.4)

## Dirt footpaths as polylines (x, z).
const PATHS := [
	[Vector2(0, 1.5), Vector2(0, 11.8)],                                  # plaza → promenade
	[Vector2(0, 15.4), Vector2(0, 21.0)],                                 # promenade → beach
	[Vector2(-12.2, -11), Vector2(-28, -11), Vector2(-28, -19.6)],        # plaza → west houses
	[Vector2(-28, -11), Vector2(-28, -2.6)],
	[Vector2(12.2, -11), Vector2(28, -11), Vector2(28, -19.6)],           # plaza → east houses
	[Vector2(28, -11), Vector2(28, -2.6)],
	[Vector2(8.5, -19.5), Vector2(17, -26), Vector2(28, -32)],            # plaza → ramp
	[Vector2(28, -35), Vector2(28, -46), Vector2(16, -48.5), Vector2(4, -48.5)],  # up the ramp → lookout
	[Vector2(-52, 13.6), Vector2(-60, 22)],                               # promenade end → west cove
]
const PATH_WIDTH := 2.4


static func island_sd(x: float, z: float) -> float:
	## Signed distance to the coastline (negative on land).
	var p := Vector2(x, z) - ISLAND_CENTER
	var q := Vector2(absf(p.x), absf(p.y)) - ISLAND_HALF + Vector2(ISLAND_CORNER, ISLAND_CORNER)
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var sd := outside + minf(maxf(q.x, q.y), 0.0) - ISLAND_CORNER
	# Wobbly coast so the beach does not look ruled.
	sd += 3.0 * sin(x * 0.061 + 0.7) * cos(z * 0.043) + 1.6 * sin(x * 0.17 + z * 0.11)
	return sd


static func beach_width(z: float) -> float:
	return lerpf(6.0, 14.0, smoothstep(-6.0, 26.0, z))


## The branch road that forks off the south side of the road loop (heading east,
## like the car leaving its spot) and sweeps down to the start of the causeway
## deck: a cubic Bézier that leaves along the loop and arrives along the
## causeway. The terrain grades it down to the deck height (see Terrain).
const BRANCH_P := [Vector2(27.0, 8.0), Vector2(37.0, 8.6), Vector2(49.35, 21.77), Vector2(53.0, 30.0)]
const BRANCH_BOX := Rect2(22.0, 3.0, 36.0, 31.0)
static var _branch := PackedVector2Array()


## Points along the branch road's centre line.
static func branch_points() -> PackedVector2Array:
	if _branch.is_empty():
		var p0: Vector2 = BRANCH_P[0]
		var p1: Vector2 = BRANCH_P[1]
		var p2: Vector2 = BRANCH_P[2]
		var p3: Vector2 = BRANCH_P[3]
		for i in 21:
			var t := i / 20.0
			var u := 1.0 - t
			_branch.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	return _branch


static func road_sd(x: float, z: float) -> float:
	## Distance from the nearest road centre line (the loop or the branch).
	var d := loop_sd(x, z)
	if BRANCH_BOX.has_point(Vector2(x, z)):
		var pts := branch_points()
		var p := Vector2(x, z)
		for i in pts.size() - 1:
			d = minf(d, _seg_dist(p, pts[i], pts[i + 1]))
	return d


static func loop_sd(x: float, z: float) -> float:
	## Distance from the road loop's centre line.
	var p := Vector2(x, z) - ROAD_CENTER
	var q := Vector2(absf(p.x), absf(p.y)) - ROAD_HALF + Vector2(ROAD_CORNER, ROAD_CORNER)
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	return absf(outside + minf(maxf(q.x, q.y), 0.0) - ROAD_CORNER)


static func road_point(t: float) -> Vector3:
	## Point on the road loop centre line, t in [0, 1).
	var hx := ROAD_HALF.x - ROAD_CORNER
	var hz := ROAD_HALF.y - ROAD_CORNER
	var straight_x := 2.0 * hx
	var straight_z := 2.0 * hz
	var arc := PI * 0.5 * ROAD_CORNER
	var total := 2.0 * (straight_x + straight_z) + 4.0 * arc
	var d := fposmod(t, 1.0) * total
	var segs := [
		["line", Vector2(-hx, hz + ROAD_CORNER), Vector2(1, 0), straight_x],
		["arc", Vector2(hx, hz), PI * 0.5, arc],
		["line", Vector2(hx + ROAD_CORNER, hz), Vector2(0, -1), straight_z],
		["arc", Vector2(hx, -hz), 0.0, arc],
		["line", Vector2(hx, -hz - ROAD_CORNER), Vector2(-1, 0), straight_x],
		["arc", Vector2(-hx, -hz), -PI * 0.5, arc],
		["line", Vector2(-hx - ROAD_CORNER, -hz), Vector2(0, 1), straight_z],
		["arc", Vector2(-hx, hz), PI, arc],
	]
	for s in segs:
		var length: float = s[3]
		if d <= length:
			var p: Vector2
			if s[0] == "line":
				p = s[1] + s[2] * d
			else:
				var a: float = s[2] - d / ROAD_CORNER
				p = s[1] + Vector2(cos(a), sin(a)) * ROAD_CORNER
			p += ROAD_CENTER
			return Vector3(p.x, LAND_HEIGHT, p.y)
		d -= length
	return Vector3(ROAD_CENTER.x, LAND_HEIGHT, ROAD_CENTER.y)


static func path_sd(x: float, z: float) -> float:
	var best := 1e9
	var p := Vector2(x, z)
	for line in PATHS:
		for i in range(line.size() - 1):
			best = minf(best, _seg_dist(p, line[i], line[i + 1]))
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func hill_mask(x: float, z: float) -> float:
	## 0 on the main level, 1 on the plateau (includes the ramp blend).
	var edge := HILL_EDGE_Z + 1.4 * sin(x * 0.09) + 0.8 * sin(x * 0.23 + 1.0)
	var cliff := smoothstep(edge + 0.6, edge - 0.6, z)
	# Ramp: a linear climb over RAMP_Z within RAMP_X.
	var ramp_w := smoothstep(RAMP_X.x - 1.0, RAMP_X.x + 0.6, x) * smoothstep(RAMP_X.y + 1.0, RAMP_X.y - 0.6, x)
	var ramp := clampf((RAMP_Z.y - z) / (RAMP_Z.y - RAMP_Z.x), 0.0, 1.0)
	ramp = ramp * ramp * (3.0 - 2.0 * ramp) * 0.25 + ramp * 0.75
	return lerpf(cliff, ramp, ramp_w)


static func is_flat_zone(x: float, z: float) -> float:
	## 1 where the ground must stay flat (plaza, road, promenade).
	var plaza := smoothstep(PLAZA_RADIUS + 3.0, PLAZA_RADIUS, Vector2(x, z).distance_to(PLAZA_CENTER))
	var road := smoothstep(ROAD_WIDTH * 0.5 + 3.0, ROAD_WIDTH * 0.5, road_sd(x, z))
	var prom := smoothstep(PROMENADE_Z.x - 3.0, PROMENADE_Z.x, z) * smoothstep(PROMENADE_Z.y + 1.0, PROMENADE_Z.y, z)
	return maxf(plaza, maxf(road, prom))

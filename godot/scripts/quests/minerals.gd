class_name Minerals
extends RefCounted
## Twelve minerals buried around the island (Biscuit's "Island Treasures" side
## quest). Dig spots look like star-shaped cracks in the ground; whatever you dig
## up goes into a little display shelf in our living room.

## id, name, colour, shape ("crystal" cluster, "gem" cut stone, "nugget", "heart")
const LIST := [
	["amethyst", "Amethyst", Color(0.66, 0.42, 0.92), "crystal"],
	["rose_quartz", "Rose Quartz", Color(1.0, 0.66, 0.78), "crystal"],
	["citrine", "Citrine", Color(1.0, 0.82, 0.3), "crystal"],
	["emerald", "Emerald", Color(0.25, 0.85, 0.5), "gem"],
	["sapphire", "Sapphire", Color(0.25, 0.45, 1.0), "gem"],
	["ruby", "Ruby", Color(0.95, 0.18, 0.3), "gem"],
	["aquamarine", "Aquamarine", Color(0.45, 0.92, 0.95), "crystal"],
	["topaz", "Topaz", Color(1.0, 0.6, 0.25), "gem"],
	["moonstone", "Moonstone", Color(0.86, 0.9, 1.0), "nugget"],
	["jade", "Jade", Color(0.35, 0.7, 0.45), "nugget"],
	["gold", "Gold Nugget", Color(1.0, 0.8, 0.25), "nugget"],
	["heart_opal", "Heart Opal", Color(1.0, 0.85, 0.95), "heart"],
]

## Where each one is buried (index matches LIST): meadows, the hill, beaches and the oasis.
const SPOTS := [
	Vector3(-40.0, 0, -4.0), Vector3(-14.0, 0, -30.0), Vector3(16.0, 0, -32.0), Vector3(12.0, 0, -52.0),
	Vector3(-30.0, 0, -50.0), Vector3(-52.0, 0, 6.0), Vector3(20.0, 0, 23.0), Vector3(-34.0, 0, 26.0),
	Vector3(56.0, 0, -12.0), Vector3(-58.0, 0, -32.0), Vector3(84.0, 0, 90.0), Vector3(9.0, 0, 26.5),
]


static func info(id: String) -> Array:
	for m in LIST:
		if m[0] == id:
			return m
	return LIST[0]


static func found() -> Array:
	if Game.quests == null:
		return []
	return Game.quests.flags.get("minerals", [])


static func add_found(id: String) -> void:
	if Game.quests == null:
		return
	var list: Array = Game.quests.flags.get("minerals", [])
	if id not in list:
		list.append(id)
	Game.quests.flags["minerals"] = list
	Game.quests.save_now()
	refresh_house()


## A soft, glossy little mineral, about 25 cm across, resting on y = 0.
static func build(id: String) -> Node3D:
	var m := info(id)
	var col: Color = m[2]
	var shape: String = m[3]
	var b := RoundKit.MB.new(1.0, hash(id))
	match shape:
		"crystal":
			# A cluster of pointed hexagonal prisms on a little rock.
			b.blob(Vector3(0, 0.03, 0), Vector3(0.12, 0.05, 0.1), Color(0.62, 0.56, 0.52), Color(0.5, 0.45, 0.42), 8, 4)
			for c: Array in [[Vector3(0, 0, 0), 0.0, 0.0, 0.2, 0.045], [Vector3(0.06, 0, 0.02), 0.0, -24.0, 0.14, 0.035],
					[Vector3(-0.055, 0, 0.03), 18.0, 22.0, 0.15, 0.035], [Vector3(0.01, 0, -0.05), -22.0, 6.0, 0.12, 0.03]]:
				_prism(b, c[0], c[1], c[2], c[3], c[4], col)
		"gem":
			_cut_gem(b, Vector3(0, 0.08, 0), 0.1, col)
		"heart":
			# Two round lobes on top of a rotated square: a chubby heart, standing up.
			for sx: float in [-1.0, 1.0]:
				b.blob(Vector3(sx * 0.042, 0.15, 0), Vector3(0.05, 0.05, 0.035), col.lightened(0.12), col, 12, 8, 0.0, Basis(), "glossy")
			b.rbox(Vector3(0.1, 0.1, 0.065), Vector3(0, 0.095, 0), col, col.darkened(0.12), 0.03, Vector3(0, 0, 45), "glossy")
		_:
			b.blob(Vector3(0, 0.07, 0), Vector3(0.1, 0.07, 0.085), col.lightened(0.1), col.darkened(0.12), 10, 6, 0.18, Basis(), "glossy")
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	var n := Node3D.new()
	n.name = "Mineral_" + id
	n.add_child(mi)
	return n


## A hexagonal prism with a pointed tip, tilted (degrees about X and Z).
static func _prism(b: RoundKit.MB, base: Vector3, tilt_x: float, tilt_z: float, h: float, r: float, col: Color) -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(tilt_x), 0, deg_to_rad(tilt_z)))
	var top := col.lightened(0.3)
	var ring0 := []
	var ring1 := []
	for i in 6:
		var a := TAU * i / 6.0
		var d := Vector3(cos(a), 0, sin(a))
		ring0.append(base + basis * (d * r))
		ring1.append(base + basis * (d * r + Vector3(0, h * 0.72, 0)))
	var tip := base + basis * Vector3(0, h, 0)
	for i in 6:
		var j := (i + 1) % 6
		var n := (basis * Vector3(cos(TAU * (i + 0.5) / 6.0), 0, sin(TAU * (i + 0.5) / 6.0))).normalized()
		b.tri("glossy", [ring0[i], n, col], [ring1[i], n, top], [ring1[j], n, top])
		b.tri("glossy", [ring0[i], n, col], [ring1[j], n, top], [ring0[j], n, col])
		var nt := ((ring1[i] as Vector3) - base + (ring1[j] as Vector3) - base).normalized() + basis * Vector3(0, 0.8, 0)
		nt = nt.normalized()
		b.tri("glossy", [ring1[i], nt, top], [tip, nt, top.lightened(0.2)], [ring1[j], nt, top])


## A faceted brilliant-ish cut: a crown and a pavilion around a ring.
static func _cut_gem(b: RoundKit.MB, c: Vector3, r: float, col: Color) -> void:
	var n := 8
	var hi := col.lightened(0.35)
	var top := c + Vector3(0, r * 0.45, 0)
	var bot := c - Vector3(0, r * 0.75, 0)
	var table := []
	var girdle := []
	for i in n:
		var a := TAU * i / n
		table.append(top + Vector3(cos(a), 0, sin(a)) * r * 0.55)
		girdle.append(c + Vector3(cos(a + PI / n), 0, sin(a + PI / n)) * r)
	for i in n:
		var j := (i + 1) % n
		var g0: Vector3 = girdle[i]
		var g1: Vector3 = girdle[j]
		var t0: Vector3 = table[i]
		var t1: Vector3 = table[j]
		# Table (flat top), crown facets and pavilion.
		b.tri("glossy", [top, Vector3.UP, hi], [t0, Vector3.UP, hi], [t1, Vector3.UP, hi])
		var nc := ((g0 + t1) * 0.5 - c).normalized()
		b.tri("glossy", [t1, nc, hi], [g0, nc, col], [g1, nc, col])
		var nc2 := ((g0 + t0) * 0.5 - c).normalized()
		b.tri("glossy", [t0, nc2, hi], [g0, nc2, col], [t1, nc2, hi])
		var np := ((g0 + g1) * 0.5 - c + Vector3(0, -0.4 * r, 0)).normalized()
		b.tri("glossy", [g0, np, col], [bot, np, col.darkened(0.25)], [g1, np, col])


## Two small wall shelves in the living room with every mineral found so far.
static func refresh_house() -> void:
	var house: Interior = Places.interiors.get("house")
	if house == null:
		return
	var old := house.get_node_or_null("MineralShelf")
	if old:
		old.queue_free()
	var have := found()
	if have.is_empty():
		return
	var shelf := Node3D.new()
	shelf.name = "MineralShelf"
	house.add_child(shelf)
	# On the right (+X) wall, facing into the room (the plushes are on the left).
	shelf.position = Vector3(house.size.x * 0.5 - 0.14, 1.25, 0.7)
	shelf.rotation.y = -PI * 0.5
	var wood := Color(0.85, 0.66, 0.46)
	for row in 2:
		shelf.add_child(Props3D.blocks([
			Props3D.b(Vector3(2.3, 0.06, 0.3), Vector3(0, row * 0.45, 0.12), wood, {"bevel": 0.02}),
		]))
	var i := 0
	for m in LIST:
		if m[0] not in have:
			i += 1
			continue
		var g := build(m[0])
		shelf.add_child(g)
		g.scale = Vector3.ONE * 0.9
		var row := i / 6
		var col := i % 6
		g.position = Vector3(-0.95 + col * 0.38, 0.03 + row * 0.45, 0.13)
		g.rotation.y = randf_range(-0.4, 0.4)
		i += 1

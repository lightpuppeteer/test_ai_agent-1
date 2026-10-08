class_name Places
extends Node3D
## The story locations: the pizza place, the cinema, our house, her old place
## (Yoggi!), the hotel & spa with its pool, the picnic garden, the road across
## the sea, the oasis and the volcano. Interiors live far from the island and
## are reached through doors.

const INTERIOR_BASE := Vector3(3000, 0, 0)
const OASIS := Vector2(82.0, 96.0)
const OASIS_R := 14.0
const CAUSEWAY_FROM := Vector3(53.0, 0, 30.0)
const CAUSEWAY_TO := Vector3(77.0, 0, 84.0)
const DECK_Y := 1.3

## Named things quests can point at (id -> Node3D). Filled while building.
static var spots := {}
static var interiors := {}

var B: IslandBuilder


static func travel(target: Vector3, yaw: float, location: String) -> void:
	var p: Player = Game.player
	if p == null or p.pose == "drive":
		return
	if p.pose != "move" and p.pose != "transition":
		await p.leave_anchor()     # get up off the bed / chair first
	if p.pose != "move":
		return
	var hud: HUD = Game.hud
	p.input_enabled = false
	Sound.play("door", -6.0)
	if hud:
		await hud.fade(1.0, 0.35)
	var partner: Person = Game.partner
	if partner and partner.pose != "move" and partner.pose != "transition":
		partner.leave_anchor()
		await p.get_tree().create_timer(0.35).timeout
	p.teleport(target, yaw)
	if partner:
		var side := Vector3(cos(yaw), 0, -sin(yaw))
		partner.teleport(target + side * 1.2 + Vector3(-sin(yaw), 0, -cos(yaw)) * -0.6, yaw)
	Game.location = location
	if Game.camera_rig:
		Game.camera_rig.yaw = yaw
		# Indoors: a high "dollhouse" view over the cut-away walls.
		Game.camera_rig.pitch = deg_to_rad(-52.0 if location != "outside" else -28.0)
		Game.camera_rig.distance = 11.0 if location != "outside" else 10.0
		Game.camera_rig.snap()
	await p.get_tree().create_timer(0.15).timeout
	if hud:
		await hud.fade(0.0, 0.45)
	p.input_enabled = true
	Game.location_changed.emit(location)


static func spot(name: String) -> Node3D:
	var n = spots.get(name)
	return n if n != null and is_instance_valid(n) else null


func build(builder: IslandBuilder) -> void:
	B = builder
	spots.clear()
	interiors.clear()
	_pizza_place()
	_cinema()
	_our_house()
	_her_place()
	_hotel()
	_picnic_garden()
	_causeway()
	_oasis()
	_volcano()
	spots["ending"] = _marker(Vector3(0, 0, 24.0))
	spots["beach_towels"] = _marker(Vector3(-9.9, 0, 29.0))
	_bulletin_board()


## The plaza notice board (Island News).
func _bulletin_board() -> void:
	var c := WorldLayout.PLAZA_CENTER
	var a := deg_to_rad(135.0)
	var p := c + Vector2(cos(a), sin(a)) * (WorldLayout.PLAZA_RADIUS - 1.3)
	var n := Node3D.new()
	n.name = "BulletinBoard"
	add_child(n)
	n.global_position = Vector3(p.x, B.ground(p.x, p.y), p.y)
	var to := c - p
	n.rotation.y = atan2(to.x, to.y)
	var board := Props3D.sign_board("bulletin", 2.0, true, Color(0.45, 0.3, 0.18), 0.1)
	board.position.y = 1.55
	n.add_child(board)
	for sx in [-0.85, 0.85]:
		n.add_child(Props3D.blocks([Props3D.b(Vector3(0.12, 2.2, 0.12), Vector3(sx, 1.1, -0.1), Color(0.5, 0.33, 0.2), {"bevel": 0.03})]))
	n.add_child(Props3D.blocks([Props3D.b(Vector3(2.3, 0.12, 0.3), Vector3(0, 2.32, -0.04), Color(0.62, 0.42, 0.26), {"bevel": 0.04})]))
	var body := StaticBody3D.new()
	body.collision_layer = Game.PHYS_PROPS
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.1, 2.3, 0.3)
	cs.shape = bs
	cs.position = Vector3(0, 1.15, -0.05)
	body.add_child(cs)
	n.add_child(body)
	var it := Interactable.new()
	it.kind = "talk"
	it.prompt = "Read the notice board"
	it.radius = 2.2
	it.position = Vector3(0, 1.0, 0.6)
	n.add_child(it)
	it.used.connect(func(_by: Node, _s: Node3D) -> void:
		if Game.hud:
			Game.hud.say("Island News", ["LOST: one cat. Grey, round, judgy. Answers to Yoggi (he does not answer).",
				"Pizza night on Friday at Amore. Emergency ham available on request.",
				"Movie club this week: A Dog Named Sunday. Bring tissues.",
				"T + M. One year of us, and counting."], Color(0.62, 0.42, 0.26), 1.0))
	B.occupied.append(Vector3(p.x, p.y, 1.6))


static var _mats := {}

func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		_mats[c] = m
	return _mats[c]


func _marker(p: Vector3) -> Node3D:
	var m := Node3D.new()
	add_child(m)
	p.y = B.ground(p.x, p.z) if p.y == 0.0 else p.y
	m.global_position = p
	return m


# ---------------------------------------------------------------------------
# Building helpers
# ---------------------------------------------------------------------------

## A house on the island with a door that leads to an interior.
## facing_deg: 0 = door faces +Z, 180 = door faces -Z.
func _building(x: float, z: float, facing_deg: float, type: String, roof: Color, mul: float, interior: Interior, door_text: String) -> Dictionary:
	var n := B.house(x, z, facing_deg, type, roof, mul)
	var id := "city-kit-suburban/building-type-" + type
	var depth := Props.model_aabb(id).size.z * Props.kit_scale(id) * mul
	var fwd := Vector3(sin(deg_to_rad(facing_deg)), 0, cos(deg_to_rad(facing_deg)))
	var front := Vector3(x, 0, z) + fwd * (depth * 0.5)
	var outside := front + fwd * 1.6
	outside.y = B.ground(outside.x, outside.z) + 0.1
	# Door outside → interior.
	var d := Door.new()
	d.prompt = door_text
	add_child(d)
	d.global_position = Vector3(front.x, B.ground(front.x, front.z) + 1.0, front.z) + fwd * 0.6
	var out_yaw := atan2(-fwd.x, -fwd.z)   # facing away from the house
	if interior:
		d.target = interior.global_position + interior.spawn
		d.target_yaw = 0.0   # inside, face into the room (-Z)
		d.target_location = interior.id
		interior.exit_door.target = outside
		interior.exit_door.target_yaw = out_yaw
		interior.exit_door.target_location = "outside"
	# Where he waits for her when they meet here: beside the path, out of the doorway.
	var meet := front + fwd * 2.6 + Vector3(fwd.z, 0, -fwd.x) * 1.4
	meet.y = 0.0
	return {"node": n, "door": d, "front": front, "outside": outside, "fwd": fwd, "meet": meet}


func _interior(id: String, title: String, index: int, size: Vector3, wall: Color, floor_col: Color, tiles: bool = false) -> Interior:
	var it := Interior.new()
	it.name = "Interior_" + id
	it.id = id
	it.title = title
	it.size = size
	it.wall_color = wall
	it.floor_color = floor_col
	it.floor_tiles = tiles
	add_child(it)
	it.global_position = INTERIOR_BASE + Vector3(index * 120.0, 0, 0)
	it.build()
	interiors[id] = it
	return it


func _seat_pair(parent: Node3D, at: Vector3, yaw_deg: float, kind: String, prompt: String, gap: float, seat_h: float, tag: String = "", seat_yaw: float = 0.0) -> Interactable:
	var it := Interactable.new()
	it.kind = kind
	it.prompt = prompt
	it.radius = 2.4
	it.tag = tag
	parent.add_child(it)
	it.position = at
	it.rotation.y = deg_to_rad(yaw_deg)
	it.add_seat(Vector3(-gap * 0.5, seat_h, 0), seat_yaw)
	it.add_seat(Vector3(gap * 0.5, seat_h, 0), seat_yaw)
	return it


func _use_point(parent: Node3D, at: Vector3, prompt: String, tag: String, radius: float = 2.0) -> Interactable:
	var it := Interactable.new()
	it.kind = "use"
	it.prompt = prompt
	it.tag = tag
	it.radius = radius
	parent.add_child(it)
	it.position = at
	spots[tag] = it
	return it


# ---------------------------------------------------------------------------
# Pizzeria Amore
# ---------------------------------------------------------------------------

func _pizza_place() -> void:
	var room := _interior("pizza", "Pizzeria Amore", 0, Vector3(12, 3.4, 9), Color(0.98, 0.9, 0.8), Color(0.75, 0.55, 0.38))
	var info := _building(-28.0, 1.0, 180.0, "c", Color(0.92, 0.3, 0.28), 1.3, room, "Enter Pizzeria Amore")
	var sign := Props3D.sign_board("pizzeria", 5.0)
	add_child(sign)
	sign.global_position = info["front"] + Vector3(0, B.ground(-28, -2) + 3.4, 0) + info["fwd"] * 0.25
	sign.rotation.y = PI
	# Striped awning over the door.
	var aw := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.6, 0.08, 1.4)
	aw.mesh = bm
	aw.material_override = B.fabric([Color(0.9, 0.25, 0.25), Color(1, 0.97, 0.92)], 9.0)
	add_child(aw)
	aw.global_position = info["front"] + Vector3(0, B.ground(-28, -2) + 2.6, 0) + info["fwd"] * 0.6
	aw.rotation.x = deg_to_rad(12)
	# A little terrace table outside.
	B.put("furniture-kit/tableRound", -31.5, -4.0, 0.0, 1.0, "cylinder", {}, 1.2)
	# --- inside
	room.window(Vector3(-3.0, 1.6, -4.45), 0.0)
	room.window(Vector3(3.0, 1.6, -4.45), 0.0)
	room.window(Vector3(-5.95, 1.6, 0.0), 90.0)
	# Counter + oven at the back.
	room.prop("furniture-kit/kitchenBar", Vector3(2.6, 0, -3.3), 0.0, 1.0)
	room.prop("furniture-kit/kitchenBar", Vector3(3.6, 0, -3.3), 0.0, 1.0)
	room.prop("furniture-kit/kitchenCabinet", Vector3(4.8, 0, -4.0), 0.0, 1.0)
	var oven := Props3D.blocks([
		Props3D.b(Vector3(2.0, 1.2, 1.4), Vector3(0, 0.6, 0), Color(0.75, 0.38, 0.28), {"bevel": 0.1}),
		Props3D.b(Vector3(1.6, 0.9, 1.2), Vector3(0, 1.55, 0), Color(0.72, 0.36, 0.26), {"bevel": 0.35}),
		Props3D.b(Vector3(0.8, 0.5, 0.1), Vector3(0, 1.0, 0.68), Color(1.0, 0.55, 0.15), {"mat": "glow", "bevel": 0.2, "shade": 0.0}),
	])
	room.add_child(oven)
	oven.position = Vector3(-3.8, 0, -3.6)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.2)
	glow.light_energy = 1.5
	glow.omni_range = 4.0
	glow.position = Vector3(-3.8, 1.0, -2.6)
	room.add_child(glow)
	var menu := Props3D.sign_board("menu", 1.4, true, Color(0.42, 0.28, 0.18), 0.06)
	room.add_child(menu)
	menu.position = Vector3(0.5, 1.95, -4.42)
	# Tables for other customers…
	for p in [Vector3(-3.5, 0, 0.5), Vector3(-0.5, 0, 1.5), Vector3(3.5, 0, 1.0)]:
		room.prop("furniture-kit/tableCloth", p, 0.0, 1.0)
		room.prop("furniture-kit/chair", p + Vector3(0, 0, -1.0), 0.0, 1.0)
		room.prop("furniture-kit/chair", p + Vector3(0, 0, 1.0), 180.0, 1.0)
	# …and ours, by the window, with a candle and a pizza.
	var tp := Vector3(-3.6, 0, -2.0)
	room.prop("furniture-kit/tableCloth", tp, 90.0, 1.0)
	var pz := Props3D.pizza()
	room.add_child(pz)
	pz.position = tp + Vector3(0, 0.78, 0)
	var candle := Props3D.blocks([
		Props3D.b(Vector3(0.08, 0.2, 0.08), Vector3(0, 0.1, 0), Color(1, 0.97, 0.9), {"bevel": 0.02}),
		Props3D.b(Vector3(0.04, 0.06, 0.04), Vector3(0, 0.24, 0), Color(1.0, 0.75, 0.3), {"mat": "glow", "shade": 0.0}),
	])
	room.add_child(candle)
	candle.position = tp + Vector3(0.35, 0.74, 0.25)
	var cl := OmniLight3D.new()
	cl.light_color = Color(1.0, 0.7, 0.4)
	cl.light_energy = 0.8
	cl.omni_range = 2.5
	cl.position = tp + Vector3(0.35, 1.1, 0.25)
	room.add_child(cl)
	# Two seats facing each other across the table.
	var it := Interactable.new()
	it.kind = "sit"
	it.prompt = "Sit at our table"
	it.radius = 2.6
	it.tag = "pizza_table"
	room.add_child(it)
	it.position = tp
	room.prop("furniture-kit/chair", tp + Vector3(-1.05, 0, 0), 90.0, 1.0, "")
	room.prop("furniture-kit/chair", tp + Vector3(1.05, 0, 0), -90.0, 1.0, "")
	it.add_seat(Vector3(-1.0, 0.46, 0), -90.0)   # faces +X (towards the table)
	it.add_seat(Vector3(1.0, 0.46, 0), 90.0)
	spots["pizza_table"] = it
	spots["pizza_door"] = info["door"]
	spots["pizza_meet"] = _marker(info["meet"])


# ---------------------------------------------------------------------------
# Cinema
# ---------------------------------------------------------------------------

var cinema_screen: CinemaScreen

func _cinema() -> void:
	var room := _interior("cinema", "Cinemas NOS", 1, Vector3(14, 5.0, 16), Color(0.32, 0.18, 0.24), Color(0.5, 0.18, 0.22))
	var info := _building(28.0, 1.0, 180.0, "h", Color(0.25, 0.25, 0.35), 1.35, room, "Enter the cinema")
	var sign := Props3D.sign_board("cinema", 5.0, true, Color(0.16, 0.12, 0.26))
	add_child(sign)
	sign.global_position = info["front"] + Vector3(0, B.ground(28, -2) + 3.6, 0) + info["fwd"] * 0.25
	sign.rotation.y = PI
	# Marquee bulbs.
	for i in 9:
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		bulb.mesh = sm
		bulb.material_override = B.bulb_material
		add_child(bulb)
		bulb.global_position = sign.global_position + Vector3(-2.4 + i * 0.6, -0.65, -0.1)
	# Posters by the door.
	# Posters flat on the facade: two left of the door, one right (within the wall).
	var bid := "city-kit-suburban/building-type-h"
	var half_w := Props.model_aabb(bid).size.x * Props.kit_scale(bid) * 1.35 * 0.5
	var posters := ["poster_horror", "poster_comedy", "poster_drama"]
	var xs := [-half_w + 1.15, -half_w + 2.45, half_w - 1.15]
	for i in 3:
		var poster := Props3D.sign_board(posters[i], 1.05, true, Color(0.85, 0.62, 0.2), 0.08)
		add_child(poster)
		poster.global_position = info["front"] + Vector3(xs[i], B.ground(28, -2) + 1.5, 0) + info["fwd"] * 0.06
		poster.rotation.y = PI
	# --- inside: a little lobby at the door end, the screen at the far end.
	cinema_screen = CinemaScreen.new()
	room.add_child(cinema_screen)
	cinema_screen.position = Vector3(0, 2.6, -7.85)
	Game.world.cinema_screen = cinema_screen
	# Curtains either side of the screen.
	for sx in [-1.0, 1.0]:
		var cur := Props3D.blocks([Props3D.b(Vector3(1.2, 4.6, 0.3), Vector3(0, 2.3, 0), Color(0.7, 0.1, 0.15), {"bevel": 0.15})])
		room.add_child(cur)
		cur.position = Vector3(sx * 5.8, 0, -7.7)
	# Rows of seats: each pair is one "sit together" spot.
	var seats_parent := Node3D.new()
	room.add_child(seats_parent)
	for row in 4:
		var z := -3.0 + row * 1.7
		var y := row * 0.25
		if row > 0:
			var step := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(10, y, 1.7)
			step.mesh = sb
			step.material_override = room._mat(Color(0.35, 0.15, 0.18))
			step.position = Vector3(0, y * 0.5, z)
			room.add_child(step)
			room._box_collider(Vector3(10, y, 1.7), Vector3(0, y * 0.5, z))
		for pair in 3:
			var cx := -3.2 + pair * 3.2
			for k in 2:
				var seat := Props3D.cinema_seat()
				seats_parent.add_child(seat)
				seat.position = Vector3(cx - 0.4 + k * 0.8, y, z)
				seat.rotation.y = PI   # facing the screen (-Z)
			var it := _seat_pair(seats_parent, Vector3(cx, y, z + 0.1), 0.0, "sit", "Sit down for the movie", 0.8, 0.48, "cinema_seats")
			if row == 1 and pair == 1:
				spots["cinema_seats"] = it
	# Popcorn stand by the door.
	var stand := Props3D.blocks([
		Props3D.b(Vector3(2.4, 1.1, 0.8), Vector3(0, 0.55, 0), Color(0.85, 0.2, 0.25), {"bevel": 0.06}),
		Props3D.b(Vector3(2.5, 0.08, 0.9), Vector3(0, 1.12, 0), Color(1, 0.97, 0.9), {"shade": 0.0}),
		Props3D.b(Vector3(0.8, 0.8, 0.6), Vector3(-0.6, 1.55, 0), Color(1.0, 0.92, 0.6), {"mat": "glossy", "bevel": 0.05}),
	])
	room.add_child(stand)
	stand.position = Vector3(4.6, 0, 5.5)
	stand.rotation.y = deg_to_rad(-90)
	var pop := Props3D.popcorn()
	pop.scale = Vector3.ONE * 2.2
	room.add_child(pop)
	pop.position = Vector3(4.6, 1.16, 5.1)
	var stand_sign := Props3D.sign_board("popcorn", 2.2, true, Color(0.75, 0.2, 0.2), 0.06)
	room.add_child(stand_sign)
	stand_sign.position = Vector3(6.94, 2.55, 5.5)
	stand_sign.rotation.y = deg_to_rad(-90)
	_use_point(room, Vector3(3.6, 1.0, 5.5), "Get popcorn & drinks", "popcorn_stand", 2.2)
	spots["cinema_door"] = info["door"]
	spots["cinema_meet"] = _marker(info["meet"])
	# Dimmer, moodier room light.
	for c in room.get_children():
		if c is OmniLight3D:
			(c as OmniLight3D).light_energy = 0.9
			(c as OmniLight3D).light_color = Color(1.0, 0.8, 0.65)


# ---------------------------------------------------------------------------
# Our house (moving in + decorating)
# ---------------------------------------------------------------------------

func _our_house() -> void:
	var room := _interior("house", "Our House", 2, Vector3(16, 3.2, 12), Color(0.97, 0.94, 0.88), Color(0.8, 0.62, 0.45))
	var info := _building(28.0, -23.0, 0.0, "e", Color(0.66, 0.5, 0.9), 1.3, room, "Enter our house")
	spots["house_door"] = info["door"]
	spots["house_meet"] = _marker(info["meet"])
	var mailbox := Props3D.post_sign("our_house", 1.3, 0.75)
	add_child(mailbox)
	var mp: Vector3 = info["outside"] + Vector3(2.4, 0, 0)
	mailbox.global_position = Vector3(mp.x, B.ground(mp.x, mp.z), mp.z)
	mailbox.rotation.y = atan2(info["fwd"].x, info["fwd"].z)
	# Interior walls split it into living room (front), bedroom (back left) and office (back right).
	_house_walls(room)
	room.window(Vector3(-4.0, 1.6, -5.95), 0.0)
	room.window(Vector3(4.0, 1.6, -5.95), 0.0)
	room.window(Vector3(-7.95, 1.6, 3.0), 90.0)
	room.window(Vector3(7.95, 1.6, 3.0), -90.0)
	for p in [[Vector3(-2.0, 0, 4.0), "room_living"], [Vector3(-4.0, 0, -3.5), "room_bedroom"], [Vector3(4.0, 0, -3.5), "room_office"]]:
		var l := Props3D.room_plaque(p[1], 1.4)
		room.add_child(l)
		l.position = p[0] + Vector3(0, 2.75, 0)
	var decor := DecorSystem.new()
	decor.name = "Decor"
	room.add_child(decor)
	decor.setup(room)
	Game.world.decor = decor
	# The pile of moving boxes starts decorating (they vanish once unpacked).
	var pile := Node3D.new()
	pile.name = "MovingBoxes"
	room.add_child(pile)
	for i in 4:
		var bx := room.prop("furniture-kit/cardboardBoxClosed", Vector3(4.6 + (i % 2) * 0.7, (i / 2) * 0.6, 3.6), randf() * 20.0, 1.0, "box" if i < 2 else "")
		bx.reparent(pile)
	var up := _use_point(room, Vector3(4.6, 1.0, 3.0), "Unpack & decorate", "decorate", 2.2)
	up.used.connect(func(_by: Node, _s: Node3D) -> void: decor.begin())
	decor.boxes = pile
	decor.box_point = up
	spots["house"] = room


func _house_walls(room: Interior) -> void:
	var c := Color(0.95, 0.9, 0.86)
	# Wall between living room and back rooms, with two doorways.
	room._wall_mesh(Vector3(4.2, 3.2, 0.2), Vector3(-5.9, 1.6, -1.0), c, true)
	room._wall_mesh(Vector3(5.2, 3.2, 0.2), Vector3(0.0, 1.6, -1.0), c, true)
	room._wall_mesh(Vector3(4.2, 3.2, 0.2), Vector3(5.9, 1.6, -1.0), c, true)
	# Wall between bedroom and office.
	room._wall_mesh(Vector3(0.2, 3.2, 5.0), Vector3(0.0, 1.6, -3.5), c, true)


# ---------------------------------------------------------------------------
# Her old place, with Yoggi in the garden
# ---------------------------------------------------------------------------

func _her_place() -> void:
	B.house(-28.0, -23.0, 0.0, "a", Color(0.95, 0.55, 0.7), 1.25)
	var l := Props3D.post_sign("her_place", 1.2, 0.7)
	add_child(l)
	l.global_position = Vector3(-24.5, B.ground(-24.5, -18.0), -18.0)
	var yoggi := Yoggi.new()
	yoggi.name = "Yoggi"
	add_child(yoggi)
	var p := Vector3(-25.0, 0, -17.0)
	p.y = B.ground(p.x, p.z) + 0.2
	yoggi.global_position = p
	spots["yoggi"] = yoggi
	spots["her_place"] = _marker(Vector3(-28.0, 0, -17.5))


# ---------------------------------------------------------------------------
# Hotel & Spa (+ pool)
# ---------------------------------------------------------------------------

func _hotel() -> void:
	var room := _interior("hotel", "Hotel Suite", 3, Vector3(12, 3.6, 10), Color(0.95, 0.93, 0.96), Color(0.92, 0.88, 0.84), true)
	var info := _building(-56.0, -15.0, 90.0, "p", Color(0.4, 0.75, 0.8), 1.6, room, "Enter the Hotel & Spa")
	var sign := Props3D.sign_board("hotel", 4.4, true, Color(0.2, 0.5, 0.55))
	add_child(sign)
	sign.global_position = info["front"] + Vector3(0, B.ground(-52, -15) + 3.8, 0) + info["fwd"] * 0.25
	sign.rotation.y = deg_to_rad(90)
	spots["hotel_door"] = info["door"]
	spots["hotel_meet"] = _marker(info["meet"])
	# A proper swimming pool on a raised deck next to the hotel.
	var deck_c := Vector3(-52.0, 0, -3.0)
	var base := -INF
	var low := INF
	for ix in range(-6, 9):
		for iz in range(-4, 7):
			var h := B.ground(deck_c.x + ix, deck_c.z + iz)
			base = maxf(base, h)
			low = minf(low, h)
	var pool := Pool.new()
	pool.name = "Pool"
	add_child(pool)
	pool.global_position = Vector3(deck_c.x, base, deck_c.z)
	pool.skirt = base - low + 0.4
	pool.build()
	if Game.options.has("navdump"):
		print("[pool] ground ", low, "..", base)
		for iz in range(-6, 7, 2):
			var row := ""
			for ix in range(-9, 10, 2):
				row += "%5.2f " % B.ground(deck_c.x + ix, deck_c.z + iz)
			print("[pool] z%+d: %s" % [iz, row])
	var gy := base + Pool.DECK_H
	# A parasol in the corner (the loungers are part of the pool).
	B.parasol(deck_c.x - 5.0, deck_c.z - 2.9, [Color(0.3, 0.7, 0.75), Color(1, 1, 1)])
	var para := B.get_child(B.get_child_count() - 1) as Node3D
	if para:
		para.global_position.y = gy - 0.15
	B.occupied.append(Vector3(deck_c.x, deck_c.z, 7.0))
	B.occupied.append(Vector3(-56.0, -15.0, 7.5))
	spots["pool"] = _marker(deck_c)
	# --- inside: the suite with the enormous bed.
	room.window(Vector3(-5.95, 1.8, -1.0), 90.0, 2.0, 1.6)
	room.window(Vector3(5.95, 1.8, -1.0), -90.0, 2.0, 1.6)
	var bed := Props3D.giant_bed()
	room.add_child(bed)
	bed.position = Vector3(0, 0, -2.2)
	var bbody := StaticBody3D.new()
	bbody.collision_layer = Game.PHYS_PROPS
	room.add_child(bbody)
	var bcs := CollisionShape3D.new()
	var bbs := BoxShape3D.new()
	bbs.size = Vector3(4.0, 0.9, 4.6)
	bcs.shape = bbs
	bbody.add_child(bcs)
	bbody.position = Vector3(0, 0.45, -2.2)
	var it := Interactable.new()
	it.kind = "lie"
	it.prompt = "Flop onto the enormous bed"
	it.radius = 3.4
	it.tag = "spa_bed"
	room.add_child(it)
	it.position = Vector3(0, 0, -0.2)
	it.add_seat(Vector3(-0.75, 0.88, -2.6), 0.0)
	it.add_seat(Vector3(0.75, 0.88, -2.6), 0.0)
	# Head towards the headboard (-Z): seat +Z is "head" in our lying convention, so turn round.
	for s in it.seats:
		s.rotation.y = PI
	spots["spa_bed"] = it
	for p in [Vector3(-4.8, 0, -4.0), Vector3(4.8, 0, -4.0)]:
		room.prop("furniture-kit/pottedPlant", p, 0.0, 1.3)
	room.prop("furniture-kit/bathtub", Vector3(4.0, 0, 2.5), -90.0, 1.0)
	room.prop("furniture-kit/rugRound", Vector3(0, 0, 2.0), 0.0, 1.4, "")
	var robe_l := Props3D.sign_board("spa", 2.2, true, Color(0.55, 0.78, 0.74), 0.05)
	room.add_child(robe_l)
	robe_l.position = Vector3(0, 2.75, -4.93)


# ---------------------------------------------------------------------------
# Picnic garden
# ---------------------------------------------------------------------------

func _picnic_garden() -> void:
	var c := Vector2(56.5, -15.0)
	var r := 5.4
	B.occupied.append(Vector3(c.x, c.y, r + 1.0))
	# Hedge ring with an opening facing the road (west).
	var hedge_id := "fantasy-town-kit/hedge-large"
	var piece := Props.model_aabb(hedge_id).size.z * Props.kit_scale(hedge_id)
	var n := int(ceil(TAU * r / (piece * 0.92)))
	for i in n:
		var a := TAU * (i + 0.5) / n
		if absf(wrapf(a - PI, -PI, PI)) < 0.32:
			continue
		var p := c + Vector2(cos(a), sin(a)) * r
		# The hedge runs along its local Z: turn it to follow the circle.
		B.put(hedge_id, p.x, p.y, rad_to_deg(-a), 1.0, "box", {})
	# Arch over the entrance.
	var ex := c + Vector2(-r, 0)
	for sz in [-1.1, 1.1]:
		B.put("fantasy-town-kit/pillar-wood", ex.x, ex.y + sz, 0.0, 1.0, "cylinder", {"collider_shrink": 0.5})
	var arch := Props3D.blocks([Props3D.b(Vector3(0.3, 0.3, 2.6), Vector3(0, 0, 0), Color(0.62, 0.42, 0.3))])
	add_child(arch)
	arch.global_position = Vector3(ex.x, B.ground(ex.x, ex.y) + 2.45, ex.y)
	for i in 10:
		var fl := Props3D.blocks([Props3D.b(Vector3(0.18, 0.12, 0.18), Vector3.ZERO, [Color(1, 0.6, 0.7), Color(1, 0.95, 0.6), Color(0.85, 0.6, 1)][i % 3], {"bevel": 0.05})])
		add_child(fl)
		fl.global_position = arch.global_position + Vector3(randf_range(-0.12, 0.12), 0.12, -1.2 + i * 0.27)
	var lbl := Props3D.sign_board("garden", 2.4, true, Color(0.45, 0.3, 0.18), 0.08)
	add_child(lbl)
	lbl.global_position = arch.global_position + Vector3(-0.17, 0.47, 0)
	lbl.rotation.y = deg_to_rad(-90)
	# Flower beds and a shady tree.
	B.soil_bed(c.x + 2.5, c.y - 3.0, 1.1, ["nature-kit/flower_redA", "nature-kit/flower_yellowA", "nature-kit/flower_purpleA"])
	B.soil_bed(c.x + 2.5, c.y + 3.0, 1.1, ["nature-kit/flower_redB", "nature-kit/flower_yellowB", "nature-kit/flower_purpleB"])
	B.tree(c.x + 3.6, c.y, "fruit", 2, "peach", 1.05)
	# The blanket (two seats) and the basket.
	var blanket := B.towel(c.x - 0.5, c.y, 90.0, [Color(0.95, 0.42, 0.42), Color(1, 0.97, 0.92)], true, Vector2(2.6, 2.6))
	blanket.prompt = "Lie down on the blanket"
	blanket.tag = "picnic_blanket"
	blanket.seats[0].position.x = -0.6
	blanket.add_seat(Vector3(0.6, 0.0, 0.05), 0.0)
	spots["picnic_blanket"] = blanket
	var basket := Props3D.blocks([
		Props3D.b(Vector3(0.6, 0.35, 0.4), Vector3(0, 0.175, 0), Color(0.8, 0.6, 0.35), {"bevel": 0.04}),
		Props3D.b(Vector3(0.64, 0.06, 0.44), Vector3(0, 0.37, 0), Color(0.95, 0.42, 0.42), {"shade": 0.0}),
		Props3D.b(Vector3(0.05, 0.3, 0.05), Vector3(-0.2, 0.5, 0), Color(0.7, 0.5, 0.3), {"rot": Vector3(0, 0, 20)}),
		Props3D.b(Vector3(0.05, 0.3, 0.05), Vector3(0.2, 0.5, 0), Color(0.7, 0.5, 0.3), {"rot": Vector3(0, 0, -20)}),
	])
	add_child(basket)
	basket.global_position = Vector3(c.x - 2.5, B.ground(c.x - 2.5, c.y + 1.8), c.y + 1.8)
	var bp := _use_point(self, Vector3.ZERO, "Unpack the picnic basket", "picnic_basket", 2.0)
	bp.global_position = basket.global_position + Vector3(0, 0.6, 0)
	var feast_anchor := Node3D.new()
	add_child(feast_anchor)
	feast_anchor.global_position = Vector3(c.x - 0.5, B.ground(c.x - 0.5, c.y) + 0.03, c.y + 2.2)
	spots["picnic_feast"] = feast_anchor
	var bx := Props3D.boombox()
	add_child(bx)
	bx.global_position = Vector3(c.x + 1.2, B.ground(c.x + 1.2, c.y - 1.6), c.y - 1.6)
	bx.rotation.y = deg_to_rad(-60)
	spots["picnic"] = _marker(Vector3(c.x, 0, c.y))


# ---------------------------------------------------------------------------
# The road across the sea, the oasis, the volcano
# ---------------------------------------------------------------------------

func _causeway() -> void:
	var a := CAUSEWAY_FROM
	var b := CAUSEWAY_TO
	a.y = DECK_Y
	b.y = DECK_Y
	var dir := (b - a)
	dir.y = 0.0
	var length := dir.length()
	dir = dir.normalized()
	var yaw := atan2(dir.x, dir.z)
	var mid := (a + b) * 0.5
	var root := Node3D.new()
	root.name = "Causeway"
	add_child(root)
	root.global_position = mid
	root.rotation.y = yaw
	var width := 5.0
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(width, 0.4, length)
	# Plenty of rows along the length so the deck bends with the world curve
	# (otherwise it stays straight while everything else curves: floaty feet).
	dm.subdivide_depth = int(length)
	dm.subdivide_width = 4
	deck.mesh = dm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/floor.gdshader")
	mat.set_shader_parameter("base", Color(0.82, 0.74, 0.64))
	mat.set_shader_parameter("tiles", true)
	deck.material_override = mat
	deck.position.y = -0.2
	root.add_child(deck)
	var body := StaticBody3D.new()
	body.collision_layer = Game.PHYS_WORLD
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 0.4, length)
	cs.shape = bs
	cs.position.y = -0.2
	body.add_child(cs)
	# Low walls along the sides (and invisible rails so nobody drives into the sea).
	for sx in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		var wbm := BoxMesh.new()
		wbm.size = Vector3(0.3, 0.45, length)
		wbm.subdivide_depth = int(length)
		wall.mesh = wbm
		wall.material_override = _mat(Color(0.95, 0.93, 0.9))
		wall.position = Vector3(sx * (width * 0.5 - 0.15), 0.22, 0)
		root.add_child(wall)
		var rail := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = Vector3(0.3, 1.6, length)
		rail.shape = rb
		rail.position = Vector3(sx * (width * 0.5 - 0.15), 0.8, 0)
		body.add_child(rail)
	# Pillars down into the water.
	var n := int(length / 8.0)
	for i in n + 1:
		var z := -length * 0.5 + i * length / n
		for sx in [-1.0, 1.0]:
			var pil := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.35
			pm.bottom_radius = 0.45
			pm.height = 9.0
			pil.mesh = pm
			pil.material_override = _mat(Color(0.78, 0.72, 0.65))
			pil.position = Vector3(sx * 1.8, -4.6, z)
			root.add_child(pil)
	# Lamps every ~14 m.
	var lamps := int(length / 14.0)
	for i in lamps:
		var t := (i + 0.5) / lamps
		var p := a.lerp(b, t) + Vector3(cos(yaw), 0, -sin(yaw)) * (width * 0.5 - 0.5) * (1.0 if i % 2 else -1.0)
		var lp := B.lamp(p.x, p.z)
		lp.global_position.y = DECK_Y
	# Ramps at both ends.
	for e in [[a, -1.0], [b, 1.0]]:
		var end: Vector3 = e[0]
		var sgn: float = e[1]
		var outward := dir * sgn
		const RUN := 7.5        # long and gentle, so the car and Marco roll right up
		var land := end + outward * RUN
		var gy := maxf(B.ground(land.x, land.z), 0.2)
		var ramp := CollisionShape3D.new()
		var rbs := BoxShape3D.new()
		rbs.size = Vector3(width, 0.4, RUN + 1.2)
		ramp.shape = rbs
		var rnode := StaticBody3D.new()
		rnode.collision_layer = Game.PHYS_WORLD
		add_child(rnode)
		rnode.add_child(ramp)
		var rmesh := MeshInstance3D.new()
		var rmm := BoxMesh.new()
		rmm.size = rbs.size
		rmm.subdivide_depth = 12
		rmm.subdivide_width = 4
		rmesh.mesh = rmm
		rmesh.material_override = mat
		rnode.add_child(rmesh)
		var centre := end + outward * (RUN * 0.5)
		centre.y = (DECK_Y + gy) * 0.5 - 0.2
		rnode.global_position = centre
		rnode.rotation.y = yaw
		# Local +Z points along the causeway (towards the oasis): tilt so the top
		# surface runs from the deck height to the ground height.
		rnode.rotate_object_local(Vector3.RIGHT, -atan2((gy - DECK_Y) * sgn, RUN))
	spots["causeway_start"] = _marker(CAUSEWAY_FROM)
	var sign := Node3D.new()
	var arrow := Props3D.sign_board("oasis", 2.0, false)
	arrow.position.y = 1.55
	sign.add_child(arrow)
	sign.add_child(Props3D.blocks([Props3D.b(Vector3(0.14, 1.9, 0.14), Vector3(-0.62, 0.95, -0.06), Color(0.5, 0.33, 0.2), {"bevel": 0.03})]))
	add_child(sign)
	var sp := CAUSEWAY_FROM - dir * 2.0 + Vector3(cos(yaw), 0, -sin(yaw)) * 3.6
	sign.global_position = Vector3(sp.x, B.ground(sp.x, sp.z), sp.z)
	sign.rotation.y = yaw + PI
	B.occupied.append(Vector3(CAUSEWAY_FROM.x, CAUSEWAY_FROM.z, 5.0))


func _oasis() -> void:
	var c := OASIS
	var gy := B.ground(c.x, c.y)
	# Pond in the middle.
	var pond := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.0
	cm.height = 0.04
	pond.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.3, 0.8, 0.85, 0.8)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 0.05
	pond.material_override = pm
	add_child(pond)
	pond.global_position = Vector3(c.x + 3.0, WorldLayout.LAND_HEIGHT - 0.55, c.y + 2.0)
	# Palms in a ring.
	var palms := ["pirate-kit/palm-detailed-bend", "pirate-kit/palm-detailed-straight", "pirate-kit/palm-bend"]
	# (leaving the side facing the causeway open so the volcano view stays clear)
	var road_a := atan2(CAUSEWAY_TO.z - c.y, CAUSEWAY_TO.x - c.x)
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		if absf(wrapf(a - road_a, -PI, PI)) < 0.75:
			continue
		var p := c + Vector2(cos(a), sin(a)) * randf_range(7.0, 9.5)
		B.put(palms[i % 3], p.x, p.y, randf() * 360.0, randf_range(0.9, 1.2), "trunk", {"sway": 1.0})
	for i in 14:
		var a := randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * randf_range(4.0, 8.5)
		B.put(["nature-kit/flower_redA", "nature-kit/flower_yellowA", "nature-kit/plant_bush", "nature-kit/grass_large"][i % 4], p.x, p.y, randf() * 360.0, 0.6, "")
	# The chest, facing the road.
	var chest := Props3D.chest()
	add_child(chest)
	var cp := Vector3(c.x - 2.0, 0, c.y - 3.0)
	cp.y = B.ground(cp.x, cp.z)
	chest.global_position = cp
	var to_road := CAUSEWAY_TO - cp
	chest.rotation.y = atan2(to_road.x, to_road.z)
	var body := StaticBody3D.new()
	body.collision_layer = Game.PHYS_PROPS
	chest.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 0.8, 0.65)
	cs.shape = bs
	cs.position.y = 0.4
	body.add_child(cs)
	var it := _use_point(chest, Vector3(0, 0.8, 0.6), "Open the chest", "oasis_chest", 2.2)
	it.used.connect(func(_by: Node, _s: Node3D) -> void:
		var lid: Node3D = chest.get_node("Lid")
		var tw := lid.create_tween()
		tw.tween_property(lid, "rotation:x", deg_to_rad(-100), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sound.play("chest", -4.0)
		FX.sparkle(self, chest.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.85, 0.5), 60))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.85, 0.5)
	glow.light_energy = 1.2
	glow.omni_range = 3.0
	glow.position = Vector3(0, 1.0, 0)
	chest.add_child(glow)
	spots["oasis_chest"] = it
	spots["oasis"] = _marker(Vector3(c.x, 0, c.y))


var volcano: Volcano

func _volcano() -> void:
	volcano = Volcano.new()
	volcano.name = "Volcano"
	add_child(volcano)
	# Far enough behind the oasis (seen from the causeway) to frame it whole.
	volcano.global_position = Vector3(114.0, -6.0, 176.0)
	Game.world.volcano = volcano

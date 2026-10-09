class_name IslandBuilder
extends Node3D
## Dresses the island with Kenney assets: the town square, houses, promenade,
## beach, dock, the lookout hill, trees and a carpet of grass and flowers.
## Everything is placed from WorldLayout so it lines up with the painted ground.

const L = preload("res://scripts/world/world_layout.gd")
const STRIPES := preload("res://shaders/stripes.gdshader")
const BENCH_SEAT_H := 0.47           # holiday-kit bench seat height at the default scale
const ROOF_COLORS := [
	Color(0.93, 0.42, 0.38), Color(0.40, 0.62, 0.92), Color(0.98, 0.72, 0.30),
	Color(0.66, 0.50, 0.90), Color(0.36, 0.74, 0.62), Color(0.95, 0.55, 0.70),
]
const SUBURBAN_ROOF := Color8(97, 203, 139)
const SUBURBAN_WALL := Color8(160, 168, 201)
const SUBURBAN_WALL_SHADE := Color8(142, 149, 179)

var T: Terrain
var rng := RandomNumberGenerator.new()
## Circles (x, z, radius) kept clear of scattered trees/flowers.
var occupied: Array[Vector3] = []
var benches: Array[Interactable] = []
var towels: Array[Interactable] = []
var bulb_material: StandardMaterial3D
var decor: DecorSystem
var cinema_screen: CinemaScreen
var volcano: Volcano
var places: Places


func _ready() -> void:
	T = Game.terrain
	Game.world = self
	rng.seed = 20241012
	bulb_material = StandardMaterial3D.new()
	bulb_material.albedo_color = Color(1.0, 0.85, 0.55)
	bulb_material.emission_enabled = true
	bulb_material.emission = Color(1.0, 0.72, 0.38)
	bulb_material.emission_energy_multiplier = 0.0
	var t0 := Time.get_ticks_msec()
	# Keep the branch road to the causeway clear of props.
	for bp in L.branch_points():
		occupied.append(Vector3(bp.x, bp.y, L.ROAD_WIDTH * 0.5 + 0.6))
	_town()
	_promenade()
	_beach()
	_dock()
	_hill()
	places = Places.new()
	places.name = "Places"
	add_child(places)
	places.build(self)
	SpecialTrees.build(self)
	_trees()
	_scatter()
	if not Game.options.has("nograss"):
		GrassField.build(self)
	print("[island] dressed in %d ms (%d nodes)" % [Time.get_ticks_msec() - t0, get_child_count()])


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func ground(x: float, z: float) -> float:
	return T.height_at(x, z)


func put(id: String, x: float, z: float, yaw: float = 0.0, mul: float = 1.0, collide: String = "",
		opts: Dictionary = {}, clear_r: float = 0.0) -> Node3D:
	var y := ground(x, z) + float(opts.get("dy", 0.0))
	if opts.get("min_ground", false):
		# Big footprints: sit on the lowest corner so nothing floats.
		var bb := Props.model_aabb(id)
		var r := maxf(bb.size.x, bb.size.z) * Props.kit_scale(id) * mul * 0.5
		for o in [Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
			y = minf(y, ground(x + o.x, z + o.y) + float(opts.get("dy", 0.0)))
	var n := Props.place(self, id, Vector3(x, y, z), yaw, mul, collide, opts)
	if clear_r > 0.0:
		occupied.append(Vector3(x, z, clear_r))
	return n


## The nearest spot to `p` (searching outwards up to 8 m) that is open ground:
## dry land, not a path, road or paving, and away from props. Returns it on the ground.
func clear_ground_near(p: Vector3, r: float = 0.9) -> Vector3:
	for ring in 9:
		var steps := maxi(1, ring * 6)
		if r > 1.5:
			steps = maxi(1, ring * 3)
		for k in steps:
			var a := TAU * k / steps
			var x := p.x + cos(a) * ring
			var z := p.z + sin(a) * ring
			var h := ground(x, z)
			if h < 0.35:
				continue
			var sp := T.splat_at(x, z)
			if sp.g > 0.3 or sp.b > 0.3 or sp.r > 0.5:
				continue
			if T.normal_at(x, z).y < 0.85 or not is_clear(x, z, r):
				continue
			if r > 1.5 and (L.path_sd(x, z) < r or L.road_sd(x, z) < L.ROAD_WIDTH * 0.5 + r or L.is_flat_zone(x, z) > 0.05):
				continue
			return Vector3(x, h, z)
	return Vector3(p.x, ground(p.x, p.z), p.z)


func is_clear(x: float, z: float, r: float = 0.0) -> bool:
	for c in occupied:
		if Vector2(c.x, c.y).distance_to(Vector2(x, z)) < c.z + r:
			return false
	return true


func lamp(x: float, z: float, yaw: float = 0.0) -> Node3D:
	var n := put("holiday-kit/lantern", x, z, yaw, 1.0, "cylinder", {"collider_shrink": 0.35}, 0.8)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.45, 0)
	light.light_color = Color(1.0, 0.74, 0.45)
	light.omni_range = 9.0
	light.omni_attenuation = 1.2
	light.light_energy = 0.0
	light.set_meta("max_energy", 2.2)
	light.visible = false
	light.add_to_group("lamp_lights")
	n.add_child(light)
	if RoundKit.has("holiday-kit/lantern"):
		return n     # the round lamp has its own glowing globe
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.3
	bulb.mesh = sm
	bulb.material_override = bulb_material
	bulb.position = Vector3(0, 2.42, 0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(bulb)
	return n


func set_lamps(amount: float) -> void:
	bulb_material.emission_energy_multiplier = amount * 4.0
	# The cozy (stylized) copies of the lamp materials glow along.
	for pair in [[bulb_material, amount * 4.0], [RoundKit.material("glow"), 0.35 + amount * 3.0]]:
		var src: Material = pair[0]
		(src as BaseMaterial3D).emission_energy_multiplier = pair[1]
		var cozy = Stylizer._cache.get(src)
		if cozy is ShaderMaterial:
			(cozy as ShaderMaterial).set_shader_parameter("emission_energy", pair[1])


## A bench you can sit on (two seats). yaw: direction the sitter faces (0 = +Z).
func bench(x: float, z: float, yaw: float) -> Interactable:
	var n := put("holiday-kit/bench", x, z, yaw, 1.0, "box", {"collider_shrink": 0.9}, 1.4)
	var it := Interactable.new()
	it.name = "BenchUse"
	it.kind = "sit"
	it.prompt = "Sit down"
	it.radius = 2.0
	n.add_child(it)
	# Seats face the bench front (+Z of the model); the character faces the seat's -Z.
	# A touch higher and further forward than the slats, so thighs rest on the
	# seat instead of sinking through it.
	it.add_seat(Vector3(-0.42, BENCH_SEAT_H + 0.08, 0.13), 180.0)
	it.add_seat(Vector3(0.42, BENCH_SEAT_H + 0.08, 0.13), 180.0)
	it.position = Vector3(0, 0, 0.35)
	for s in it.seats:
		s.position.z -= 0.35
	benches.append(it)
	return it


func fabric(colors: Array, stripes: float, extra: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STRIPES
	m.set_shader_parameter("color_a", colors[0])
	m.set_shader_parameter("color_b", colors[1])
	m.set_shader_parameter("stripes", stripes)
	for k in extra:
		m.set_shader_parameter(k, extra[k])
	return m


## A beach towel (or picnic blanket) you can lie on. yaw: where the head points.
func towel(x: float, z: float, yaw: float, colors: Array, checker: bool = false, size := Vector2(1.0, 2.0)) -> Interactable:
	var root := Node3D.new()
	root.name = "Towel"
	add_child(root)
	var y := ground(x, z)
	root.position = Vector3(x, y + 0.02, z)
	# Lie flat on the slope.
	var nrm := T.normal_at(x, z)
	root.basis = Basis(Vector3.UP.cross(nrm).normalized(), Vector3.UP.angle_to(nrm)) if nrm.dot(Vector3.UP) < 0.9999 else Basis()
	root.rotate_object_local(Vector3.UP, deg_to_rad(yaw))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = fabric(colors, 4.0 if checker else 7.0, {"checker": checker, "fringe": 0.0 if checker else 0.04})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var it := Interactable.new()
	it.name = "TowelUse"
	it.kind = "lie"
	it.prompt = "Lie down"
	it.radius = 1.7
	root.add_child(it)
	# Head towards local -Z; the anchor's -Z is "forward" (from feet to head).
	it.add_seat(Vector3(0, 0.0, 0.05), 0.0)
	towels.append(it)
	occupied.append(Vector3(x, z, 1.3))
	return it


func parasol(x: float, z: float, colors: Array, tilt: float = 8.0) -> void:
	var root := Node3D.new()
	root.name = "Parasol"
	add_child(root)
	root.position = Vector3(x, ground(x, z) - 0.15, z)
	root.rotation = Vector3(deg_to_rad(tilt), rng.randf() * TAU, 0)
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.height = 3.0
	pole.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.96, 0.94, 0.9)
	pole.material_override = pm
	pole.position.y = 1.5
	root.add_child(pole)
	var canopy := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = 1.25
	cone.height = 0.5
	cone.radial_segments = 16
	cone.cap_bottom = false
	canopy.mesh = cone
	canopy.material_override = fabric(colors, 8.0)
	canopy.position.y = 2.85
	root.add_child(canopy)
	occupied.append(Vector3(x, z, 0.6))


## Suburban house with a recoloured roof and cream walls. yaw: direction the door faces.
func house(x: float, z: float, yaw: float, type: String, roof: Color, mul: float = 1.0) -> Node3D:
	if not Game.options.has("kenney"):
		return _cottage(x, z, yaw, type, roof, mul)
	var opts := {
		"recolor": {SUBURBAN_ROOF: roof, SUBURBAN_WALL: Color(0.99, 0.93, 0.82)},
		"min_ground": true, "dy": -0.05,
	}
	var n := put("city-kit-suburban/building-type-" + type, x, z, yaw, mul, "box", opts, 4.6 * mul)
	return n


## A rounded storybook cottage in place of the boxy suburban house.
func _cottage(x: float, z: float, yaw: float, type: String, roof: Color, mul: float) -> Node3D:
	var n := Cottage.make(type, roof, mul)
	add_child(n)
	var bb: AABB = n.get_meta("aabb")
	var y := ground(x, z)
	var r := maxf(bb.size.x, bb.size.z) * 0.5
	for o in [Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		y = minf(y, ground(x + o.x * 0.7, z + o.y * 0.7))
	n.position = Vector3(x, y - 0.05, z)
	n.rotation.y = deg_to_rad(yaw)
	var body := StaticBody3D.new()
	body.collision_layer = Game.PHYS_PROPS
	n.add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bb.size.x * 0.9, bb.size.y, bb.size.z * 0.9)
	cs.shape = box
	cs.position = bb.get_center()
	body.add_child(cs)
	occupied.append(Vector3(x, z, 4.6 * mul))
	return n


func soil_bed(x: float, z: float, r: float, flowers: Array) -> void:
	T.paint_soil(Vector2(x, z), r)
	var count := int(r * r * 5.0)
	for i in count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * (r - 0.3)
		var fx := x + cos(a) * d
		var fz := z + sin(a) * d
		_flower_points.append([flowers[rng.randi() % flowers.size()], Vector3(fx, ground(fx, fz), fz), rng.randf() * TAU, rng.randf_range(0.5, 0.65)])
	occupied.append(Vector3(x, z, r))


var _flower_points: Array = []   # [id, pos, yaw, scale]


# ---------------------------------------------------------------------------
# Town square
# ---------------------------------------------------------------------------

func _town() -> void:
	var c := L.PLAZA_CENTER
	# Fountain with a soft water disc.
	put("fantasy-town-kit/fountain-round-detail", c.x, c.y, 0.0, 1.45, "cylinder", {}, 4.5)
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.75
	disc.bottom_radius = 2.75
	disc.height = 0.02
	water.mesh = disc
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.45, 0.82, 0.92, 0.75)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.05
	water.material_override = wm
	water.position = Vector3(c.x, ground(c.x, c.y) + 0.62, c.y)
	add_child(water)
	_fountain_spray(Vector3(c.x, ground(c.x, c.y) + 1.6, c.y))
	var fs := Node3D.new()
	fs.name = "FountainSound"
	add_child(fs)
	fs.position = Vector3(c.x, ground(c.x, c.y) + 1.0, c.y)
	Sound.loop_3d("amb_fountain", fs, 3.0, -6.0)

	# Benches facing the fountain, lamps around the rim.
	for k in 4:
		var a := deg_to_rad(45.0 + 90.0 * k)
		var p := c + Vector2(cos(a), sin(a)) * 8.6
		var face := rad_to_deg(atan2(c.x - p.x, c.y - p.y))
		bench(p.x, p.y, face)
	for k in 8:
		if k == 0 or k == 3:
			continue   # market stalls go there
		var a := deg_to_rad(22.5 + 45.0 * k)
		var p := c + Vector2(cos(a), sin(a)) * 12.0
		lamp(p.x, p.y)
	# Flower beds between the benches.
	for k in 4:
		var a := deg_to_rad(90.0 * k)
		if k == 1:
			continue   # south exit stays open
		var p := c + Vector2(cos(a), sin(a)) * 9.0
		if k == 3:
			continue   # north: town hall steps
		soil_bed(p.x, p.y, 1.5, ["nature-kit/flower_redA", "nature-kit/flower_whiteL", "nature-kit/flower_purpleL", "nature-kit/flower_pinkA", "nature-kit/flower_redL", "nature-kit/flower_whiteD"])
	# Market stalls and a café corner.
	for k in [0, 3]:
		var a := deg_to_rad(22.5 + 45.0 * k)
		var p := c + Vector2(cos(a), sin(a)) * 11.0
		var face := rad_to_deg(atan2(c.x - p.x, c.y - p.y))
		put("fantasy-town-kit/stall-red" if k == 0 else "fantasy-town-kit/stall-green", p.x, p.y, face + 90.0, 1.0, "box", {}, 2.0)
	put("fantasy-town-kit/cart", c.x - 11.5, c.y - 2.0, 100.0, 0.9, "box", {}, 1.5)
	for p in [Vector2(6.5, -5.5), Vector2(-6.5, -5.5)]:
		var tx: float = c.x + p.x
		var tz: float = c.y + p.y
		put("furniture-kit/tableRound", tx, tz, 0.0, 1.0, "cylinder", {"dy": 0.0}, 1.5)
	# Town hall (north) and houses.
	# The old town hall north of the plaza is now the Island Arcade, and the other
	# houses (pizza place, cinema, our house, her place) are built by Places too.
	# Little front gardens.
	for hx in [-28.0, 28.0]:
		for hz in [-16.5, -4.5]:
			for sx in [-3.2, 3.2]:
				put("fantasy-town-kit/hedge", hx + sx, hz, 0.0, 1.0, "box", {}, 0.8)
			soil_bed(hx - 4.8, hz, 1.0, ["nature-kit/flower_yellowA", "nature-kit/flower_pinkL", "nature-kit/flower_purpleB", "nature-kit/flower_whiteD"])
	# Signpost at the south exit.
	put("survival-kit/signpost", c.x + 2.2, c.y + 13.6, -20.0, 1.0, "cylinder", {"collider_shrink": 0.3}, 0.6)


func _fountain_spray(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.name = "FountainSpray"
	p.amount = 120
	p.lifetime = 1.4
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 2.8
	pm.initial_velocity_max = 3.4
	pm.gravity = Vector3(0, -6.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	var q := SphereMesh.new()
	q.radius = 0.06
	q.height = 0.12
	q.radial_segments = 6
	q.rings = 3
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(0.85, 0.95, 1.0, 0.8)
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = qm
	p.draw_pass_1 = q
	add_child(p)


# ---------------------------------------------------------------------------
# Promenade (between the road and the beach)
# ---------------------------------------------------------------------------

func _promenade() -> void:
	var z_lamp := L.PROMENADE_Z.x + 0.6
	var z_bench := L.PROMENADE_Z.y - 0.5
	var x := -48.0
	while x <= 48.0:
		if L.road_sd(x, z_lamp) > L.ROAD_WIDTH * 0.5 + 0.8:
			lamp(x, z_lamp)
		x += 12.0
	x = -42.0
	while x <= 42.0:
		if absf(x) > 3.0 and L.road_sd(x, z_bench) > L.ROAD_WIDTH * 0.5 + 1.5:
			bench(x, z_bench, 0.0)
		x += 12.0
	# Planters between the benches (not underneath them).
	for px in [-36.0, -12.0, 12.0, 36.0]:
		if L.road_sd(px, z_bench + 0.2) > L.ROAD_WIDTH * 0.5 + 1.0:
			put("city-kit-suburban/planter", px, z_bench + 0.2, 0.0, 0.8, "box", {}, 1.0)


# ---------------------------------------------------------------------------
# Beach
# ---------------------------------------------------------------------------

func _beach() -> void:
	# Palms along the top of the beach.
	var palms := ["pirate-kit/palm-detailed-bend", "pirate-kit/palm-detailed-straight", "pirate-kit/palm-bend", "pirate-kit/palm-straight"]
	var x := -58.0
	while x < 58.0:
		var px := x + rng.randf_range(-2.0, 2.0)
		var pz := rng.randf_range(18.0, 23.5)
		if absf(px) > 4.0 and absf(px - 34.0) > 4.0 and is_clear(px, pz, 1.0):
			put(palms[rng.randi() % palms.size()], px, pz, rng.randf() * 360.0, rng.randf_range(0.85, 1.15), "trunk", {"sway": 1.0}, 1.2)
		x += rng.randf_range(6.5, 10.0)
	# Towels in pairs (one for each of you) with parasols.
	towel(-10.6, 29.0, 180.0, [Color(0.98, 0.48, 0.47), Color(1, 0.96, 0.9)])
	towel(-9.2, 29.0, 180.0, [Color(0.36, 0.66, 0.95), Color(1, 0.96, 0.9)])
	parasol(-9.9, 26.4, [Color(0.98, 0.52, 0.42), Color(1, 0.97, 0.92)])
	towel(13.2, 28.0, 200.0, [Color(1.0, 0.78, 0.35), Color(1, 0.96, 0.9)])
	towel(14.6, 28.5, 200.0, [Color(0.55, 0.80, 0.55), Color(1, 0.96, 0.9)])
	parasol(14.2, 25.6, [Color(0.40, 0.70, 0.95), Color(1, 0.97, 0.92)])
	parasol(-24.0, 27.5, [Color(0.75, 0.55, 0.95), Color(1, 0.97, 0.92)])
	# Rocks, driftwood and shells along the shore.
	for i in 16:
		var a := rng.randf() * TAU
		var bx := rng.randf_range(-62.0, 62.0)
		var bz := rng.randf_range(24.0, 36.0)
		var h := ground(bx, bz)
		if h < 0.15 or h > 1.1 or not is_clear(bx, bz, 1.0):
			continue
		var pick := rng.randi() % 5
		match pick:
			0, 1:
				put("nature-kit/rock_largeA" if pick == 0 else "nature-kit/rock_largeC", bx, bz, rad_to_deg(a), rng.randf_range(0.6, 1.0), "box", {"dy": -0.15}, 1.2)
			2:
				put("nature-kit/log", bx, bz, rad_to_deg(a), 0.55, "box", {"dy": -0.05}, 1.0)
			_:
				put("nature-kit/rock_smallA", bx, bz, rad_to_deg(a), 1.0, "", {"dy": -0.05}, 0.5)
	put("pirate-kit/rocks-sand-a", -64.0, 26.0, 30.0, 1.0, "mesh", {"dy": -0.4}, 4.0)
	put("pirate-kit/rocks-sand-b", 63.0, 20.0, -40.0, 1.0, "mesh", {"dy": -0.4}, 4.0)
	put("pirate-kit/chest", -61.5, 23.0, 70.0, 1.2, "box", {}, 1.0)


# ---------------------------------------------------------------------------
# Dock + floating things
# ---------------------------------------------------------------------------

func _dock() -> void:
	var dx := 34.0
	var deck_y := 1.25
	var z := 29.0
	var piece := "pirate-kit/structure-platform-dock"
	var bb := Props.model_aabb(piece)
	var s := Props.kit_scale(piece)
	var step := bb.size.z * s * 0.98
	const DECK_TOP := 0.93   # plank surface of the Kenney dock piece (posts reach 1.31)
	var z0 := z
	while z < 50.0:
		# Plank surface lands at deck_y; legs reach down into the sand/sea.
		var n := Props.place(self, piece, Vector3(dx, deck_y - DECK_TOP * s, z), 0.0, 1.0, "")
		n.name = "Dock"
		z += step
	# One smooth walkable slab for the whole pier (no snagging on posts).
	var body := StaticBody3D.new()
	body.name = "PierDeck"
	body.collision_layer = Game.PHYS_PROPS
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var length := z - z0
	box.size = Vector3(bb.size.x * s * 0.92, 0.4, length)
	cs.shape = box
	cs.position = Vector3(dx, deck_y - 0.2, z0 - step * 0.5 + length * 0.5)
	body.add_child(cs)
	# A gentle ramp from the sand up onto the deck.
	var ramp := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(bb.size.x * s * 0.92, 0.2, 4.0)
	ramp.shape = rb
	var sand_y := ground(dx, z0 - step * 0.5 - 1.8)
	ramp.position = Vector3(dx, (deck_y + sand_y) * 0.5 - 0.1, z0 - step * 0.5 - 1.6)
	ramp.rotation.x = atan2(deck_y - sand_y, 3.6)
	body.add_child(ramp)
	occupied.append(Vector3(dx, 30.0, 2.5))
	var end := Vector3(dx, deck_y, z - step)
	var it := bench(dx, end.z + 0.4, 0.0)
	it.get_parent().position.y = deck_y
	lamp(dx + 1.2, end.z - step + 0.5)
	(get_children().back() as Node3D).position.y = deck_y
	# Floating props near the dock.
	var floaters := [
		["watercraft-kit/boat-row-small", Vector3(dx + 4.0, 0, 42.0), 0.9, 160.0],
		["watercraft-kit/buoy", Vector3(dx - 6.0, 0, 52.0), 1.0, 0.0],
		["watercraft-kit/buoy-flag", Vector3(dx + 9.0, 0, 56.0), 1.0, 0.0],
		["pirate-kit/barrel", Vector3(dx - 4.0, 0, 44.0), 0.6, 0.0],
		["pirate-kit/crate", Vector3(dx + 6.0, 0, 48.0), 0.7, 30.0],
		["watercraft-kit/boat-sail-a", Vector3(-20.0, 0, 62.0), 1.6, 100.0],
		["watercraft-kit/boat-fishing-small", Vector3(52.0, 0, 70.0), 1.4, -30.0],
	]
	for f in floaters:
		var b := BuoyantBody.create(self, f[0], f[1], f[2], f[3])
		b.name = "Float_" + String(f[0]).get_file()


# ---------------------------------------------------------------------------
# Lookout hill
# ---------------------------------------------------------------------------

func _hill() -> void:
	var lx := 4.0
	var lz := -50.0
	tree(lx - 5.0, lz - 2.0, "fruit", 1, "apple", 1.45)
	bench(lx, lz + 3.0, 0.0)
	var blanket := towel(lx + 4.5, lz + 1.5, 160.0, [Color(0.95, 0.42, 0.42), Color(1, 0.97, 0.92)], true, Vector2(2.4, 2.4))
	blanket.prompt = "Lie down"
	blanket.add_seat(Vector3(0.55, 0.0, 0.05), 0.0)
	blanket.seats[0].position.x = -0.55
	put("survival-kit/bucket", lx + 5.6, lz + 0.2, 0.0, 0.8, "", {})
	lamp(lx - 2.0, lz + 4.0)
	# Fence along the cliff edge, leaving the ramp open.
	var x := -40.0
	while x < 22.0:
		var ez := L.HILL_EDGE_Z + 1.4 * sin(x * 0.09) + 0.8 * sin(x * 0.23 + 1.0) - 2.2
		put("nature-kit/fence_simple", x, ez, 0.0, 1.0, "box", {}, 0.0)
		x += Props.model_aabb("nature-kit/fence_simple").size.x * Props.kit_scale("nature-kit/fence_simple") * 0.98
	soil_bed(-8.0, -46.0, 2.2, ["nature-kit/flower_redL", "nature-kit/flower_purpleA", "nature-kit/flower_whiteL", "nature-kit/flower_pinkB"])
	soil_bed(-14.0, -50.0, 1.8, ["nature-kit/flower_purpleB", "nature-kit/flower_redB"])


# ---------------------------------------------------------------------------
# Trees and scatter
# ---------------------------------------------------------------------------

## A storybook tree (see TreeFactory) planted on the ground at x, z.
func tree(x: float, z: float, kind: String = "round", variant: int = 0, fruit: String = "", mul: float = 1.0) -> Node3D:
	var t := TreeFactory.make(kind, variant, fruit)
	add_child(t)
	t.position = Vector3(x, ground(x, z) - 0.05, z)
	t.rotation.y = rng.randf() * TAU
	t.scale = Vector3.ONE * mul
	occupied.append(Vector3(x, z, 1.6 * mul))
	return t


func _trees() -> void:
	var placed := 0
	var tries := 0
	while placed < 85 and tries < 2500:
		tries += 1
		var x := rng.randf_range(-66.0, 66.0)
		var z := rng.randf_range(-62.0, 18.0)
		var sd := L.island_sd(x, z)
		if sd > -L.beach_width(z) - 4.0:
			continue
		if L.is_flat_zone(x, z) > 0.05 or L.path_sd(x, z) < 2.5:
			continue
		if not is_clear(x, z, 2.2):
			continue
		# Denser along the island's edges, lighter around the houses.
		var edge_bias := smoothstep(-30.0, -10.0, sd)
		if rng.randf() > 0.25 + edge_bias * 0.75:
			continue
		var fruits := ["orange", "apple", "peach", "pear", "cherry"]
		var v := rng.randi() % 4
		var mul := rng.randf_range(0.85, 1.15)
		if z < -40.0 and rng.randf() < 0.45:
			tree(x, z, "cedar" if rng.randf() < 0.75 else "stonepine", v, "", mul)
			placed += 1
			continue
		# A colourful mix: blossoms, autumn reds and golds among the greens.
		var r := rng.randf()
		if r < 0.12:
			tree(x, z, "fruit", v, fruits[rng.randi() % fruits.size()], mul)
		elif r < 0.66:
			var bloom := ["sakura", "sakura", "sakura", "jacaranda", "jacaranda", "magnolia", "maple", "maple", "ginkgo", "plum", "wisteria", "olive"]
			tree(x, z, "species", v, bloom[rng.randi() % bloom.size()], mul)
		else:
			tree(x, z, "round", v, "", mul)
		placed += 1


func _scatter() -> void:
	# Grass tufts, bushes and wild flowers as MultiMeshes (cheap, swaying).
	var sets := {
		"nature-kit/grass": [], "nature-kit/grass_large": [], "nature-kit/grass_leafs": [],
		"nature-kit/plant_bush": [], "nature-kit/plant_bushDetailed": [],
		"nature-kit/flower_redA": [], "nature-kit/flower_yellowA": [], "nature-kit/flower_purpleA": [],
		"nature-kit/flower_yellowB": [], "nature-kit/flower_redB": [], "nature-kit/flower_purpleB": [],
		"nature-kit/flower_redC": [], "nature-kit/flower_purpleC": [], "nature-kit/flower_yellowC": [],
		"nature-kit/mushroom_redGroup": [],
	}
	for f in _flower_points:
		if not sets.has(f[0]):
			sets[f[0]] = []
		sets[f[0]].append([f[1], f[2], f[3]])
	# Lots of colour: tulips, cosmos, pompoms, lilies and daisies in many shades.
	var wild_flowers := ["nature-kit/flower_redA", "nature-kit/flower_yellowA", "nature-kit/flower_purpleA", "nature-kit/flower_yellowB",
		"nature-kit/flower_pinkA", "nature-kit/flower_whiteA", "nature-kit/flower_orangeA", "nature-kit/flower_blueB", "nature-kit/flower_pinkB",
		"nature-kit/flower_lilacC", "nature-kit/flower_pinkC", "nature-kit/flower_whiteL", "nature-kit/flower_purpleL", "nature-kit/flower_redL",
		"nature-kit/flower_pinkL", "nature-kit/flower_orangeL", "nature-kit/flower_whiteD", "nature-kit/flower_pinkD", "nature-kit/flower_crimsonA"]
	var hydrangeas := ["nature-kit/plant_bushHydrangeaBlue", "nature-kit/plant_bushHydrangeaPink", "nature-kit/plant_bushHydrangeaLilac", "nature-kit/plant_bushHydrangeaWhite"]
	var n := 0
	while n < 9000:
		n += 1
		var x := rng.randf_range(-70.0, 70.0)
		var z := rng.randf_range(-66.0, 26.0)
		var h := ground(x, z)
		if h < 1.5:
			continue
		var sp := T.splat_at(x, z)
		if sp.r > 0.2 or sp.g > 0.2 or sp.b > 0.2 or sp.a > 0.2:
			continue
		if T.normal_at(x, z).y < 0.8:
			continue
		if not is_clear(x, z, 0.2):
			continue
		var r := rng.randf()
		var id: String
		# (The short lawn grass is the GrassField; these are taller accent tufts.)
		if r < 0.12:
			continue   # (the thick GrassField lawn replaces the old accent tufts)
		elif r < 0.36:
			id = ["nature-kit/plant_bush", "nature-kit/plant_bushDetailed"][rng.randi() % 2]
			if rng.randf() < 0.3:
				id = hydrangeas[rng.randi() % hydrangeas.size()]
		elif r < 0.38:
			id = "nature-kit/mushroom_redGroup"
		elif r > 0.74:
			continue
		else:
			# Flowers come in little clumps.
			id = wild_flowers[rng.randi() % wild_flowers.size()]
			if not sets.has(id):
				sets[id] = []
			for k in rng.randi_range(2, 5):
				var fx := x + rng.randf_range(-0.8, 0.8)
				var fz := z + rng.randf_range(-0.8, 0.8)
				sets[id].append([Vector3(fx, ground(fx, fz), fz), rng.randf() * TAU, rng.randf_range(0.45, 0.6)])
			continue
		var sc := rng.randf_range(0.5, 0.75) if id.contains("grass") else rng.randf_range(0.6, 0.9)
		if not sets.has(id):
			sets[id] = []
		sets[id].append([Vector3(x, h, z), rng.randf() * TAU, sc])
		if id.contains("bush"):
			occupied.append(Vector3(x, z, 0.75))   # (keeps later things, like dig spots, out of bushes)
	const CELL := 24.0
	for id in sets:
		var items: Array = sets[id]
		if items.is_empty():
			continue
		var ms: Array = Props.restyled_mesh(id, 1.4)
		if ms[0] == null:
			continue
		# Chunk into cells so each MultiMesh can be culled / faded by distance.
		var cells := {}
		for it in items:
			var key := Vector2i(floori(it[0].x / CELL), floori(it[0].z / CELL))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(it)
		var ks := Props.kit_scale(id)
		for key in cells:
			var list: Array = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = ms[0]
			mm.instance_count = list.size()
			for i in list.size():
				var it: Array = list[i]
				var b := Basis(Vector3.UP, it[1]).scaled(Vector3.ONE * ks * it[2])
				mm.set_instance_transform(i, Transform3D(b, it[0] + Vector3(0, -0.02, 0)) * ms[1])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Scatter_%s_%d_%d" % [id.get_file(), key.x, key.y]
			mmi.multimesh = mm
			# Only bushes cast shadows (tiny plants just add noise, and cost a lot).
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if id.contains("bush") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 40.0 if id.contains("grass") else (42.0 if id.contains("flower") or id.contains("mushroom") else 65.0)
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)

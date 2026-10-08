class_name Pool
extends Node3D
## The hotel's swimming pool: a raised wooden deck with a tiled basin, steps
## up to the deck and down into the water, loungers, and a water volume that
## makes anyone who wades in swim (and change into swimwear).
## Origin: centre of the deck at the base (ground) height.

const OUTER := Vector2(12.0, 7.6)     # deck footprint (x, z)
const HOLE := Vector2(8.0, 4.0)       # basin opening
const DECK_H := 1.0                    # deck top above the base
const FLOOR_H := 0.1                   # basin floor top above the base
const WATER_H := 0.84                  # water surface above the base

const WOOD := Color(0.84, 0.66, 0.46)
const TILE := Color(0.62, 0.86, 0.95)
const TILE_DARK := Color(0.42, 0.72, 0.88)
const COPING := Color(0.98, 0.97, 0.93)

var water_y := 0.0
## How far the deck and stairs reach below the base (uneven ground).
var skirt := 0.3


func build() -> void:
	var hx := HOLE.x * 0.5
	var hz := HOLE.y * 0.5
	var ox := OUTER.x * 0.5
	var oz := OUTER.y * 0.5
	var band_z := oz - hz          # deck strip in front of / behind the basin
	var band_x := ox - hx
	var parts: Array = []
	var shapes: Array = []         # [size, centre]
	# Deck: four strips around the basin (posts down to the ground underneath).
	for sz in [-1.0, 1.0]:
		var c := Vector3(0, (DECK_H - skirt) * 0.5, sz * (hz + band_z * 0.5))
		var s := Vector3(OUTER.x, DECK_H + skirt, band_z)
		parts.append(Props3D.b(s, c, WOOD, {"bevel": 0.06}))
		shapes.append([s, c])
	for sx in [-1.0, 1.0]:
		var c := Vector3(sx * (hx + band_x * 0.5), (DECK_H - skirt) * 0.5, 0)
		var s := Vector3(band_x, DECK_H + skirt, HOLE.y)
		parts.append(Props3D.b(s, c, WOOD, {"bevel": 0.06}))
		shapes.append([s, c])
	# Plank lines on the deck top (only on the deck, not across the water).
	for i in range(-6, 6):
		var x := i * 1.0 + 0.5
		if absf(x) < hx:
			for sz in [-1.0, 1.0]:
				parts.append(Props3D.b(Vector3(0.04, 0.02, band_z - 0.1), Vector3(x, DECK_H + 0.005, sz * (hz + band_z * 0.5)), WOOD.darkened(0.15), {"shade": 0.0, "bevel": 0.005}))
		else:
			parts.append(Props3D.b(Vector3(0.04, 0.02, OUTER.y - 0.1), Vector3(x, DECK_H + 0.005, 0), WOOD.darkened(0.15), {"shade": 0.0, "bevel": 0.005}))
	# Sun loungers along the back strip, facing the water.
	for i in 3:
		var lat := Vector3(-3.0 + i * 2.6, DECK_H, -(hz + band_z * 0.5))
		_lounger(parts, lat, [Color(1.0, 0.62, 0.55), Color(0.45, 0.78, 0.82), Color(1.0, 0.85, 0.45)][i])
		shapes.append([Vector3(1.7, 0.5, 0.66), lat + Vector3(0.1, 0.25, 0)])
		# Lie down on it (head towards the backrest, -X); he takes the next one.
		var it := Interactable.new()
		it.kind = "lie"
		it.prompt = "Lie on the sun lounger"
		it.radius = 1.6
		it.tag = "pool_lounger"
		add_child(it)
		it.position = lat + Vector3(0.15, 0.0, 0.0)
		it.add_seat(Vector3(0, 0.46, 0), 90.0)
	# Basin: tiled floor and walls, white coping around the edge.
	var floor_s := Vector3(HOLE.x, 0.5, HOLE.y)
	var floor_c := Vector3(0, FLOOR_H - 0.25, 0)
	parts.append(Props3D.b(floor_s, floor_c, TILE_DARK, {"shade": 0.0, "bevel": 0.01}))
	shapes.append([floor_s, floor_c])
	for sz in [-1.0, 1.0]:
		parts.append(Props3D.b(Vector3(HOLE.x, DECK_H - FLOOR_H, 0.06), Vector3(0, (DECK_H + FLOOR_H) * 0.5, sz * (hz - 0.03)), TILE, {"shade": 0.25, "bevel": 0.01}))
		parts.append(Props3D.b(Vector3(OUTER.x - 2.0 * band_x + 0.5, 0.1, 0.36), Vector3(0, DECK_H + 0.02, sz * (hz + 0.1)), COPING, {"bevel": 0.04, "shade": 0.0}))
	for sx in [-1.0, 1.0]:
		parts.append(Props3D.b(Vector3(0.06, DECK_H - FLOOR_H, HOLE.y), Vector3(sx * (hx - 0.03), (DECK_H + FLOOR_H) * 0.5, 0), TILE, {"shade": 0.25, "bevel": 0.01}))
		parts.append(Props3D.b(Vector3(0.36, 0.1, HOLE.y + 0.56), Vector3(sx * (hx + 0.1), DECK_H + 0.02, 0), COPING, {"bevel": 0.04, "shade": 0.0}))
	# A darker lane stripe on the floor.
	parts.append(Props3D.b(Vector3(HOLE.x - 1.6, 0.02, 0.3), Vector3(0.4, FLOOR_H + 0.01, 0), TILE_DARK.darkened(0.25), {"shade": 0.0, "bevel": 0.005}))
	# Steps down into the water at the +X end (0.3 m each).
	var step_w := 2.2
	for i in 2:
		var top := DECK_H - 0.3 * (i + 1)
		var s := Vector3(0.55, top - FLOOR_H + 0.02, step_w)
		var c := Vector3(hx - 0.275 - i * 0.55, FLOOR_H + s.y * 0.5 - 0.02, 0)
		parts.append(Props3D.b(s, c, COPING.darkened(0.04), {"bevel": 0.03}))
		shapes.append([s, c])
	# Chrome rails beside the steps.
	for sz in [-1.0, 1.0]:
		parts.append(Props3D.b(Vector3(0.9, 0.06, 0.06), Vector3(hx - 0.35, DECK_H + 0.7, sz * (step_w * 0.5 + 0.05)), Color(0.85, 0.87, 0.9), {"mat": "glossy", "rot": Vector3(0, 0, 35), "bevel": 0.02}))
		parts.append(Props3D.b(Vector3(0.06, 0.75, 0.06), Vector3(hx + 0.05, DECK_H + 0.37, sz * (step_w * 0.5 + 0.05)), Color(0.85, 0.87, 0.9), {"mat": "glossy", "bevel": 0.02}))
	# Stairs up onto the deck on the +X side (towards town), 0.25 m each.
	for i in 4:
		var top := DECK_H - 0.25 * i
		var s := Vector3(0.5, top + skirt, 3.0)
		var c := Vector3(ox + 0.25 + i * 0.5, (top - skirt) * 0.5, 0)
		parts.append(Props3D.b(s, c, WOOD.darkened(0.06), {"bevel": 0.04}))
		shapes.append([s, c])
	# And on the +Z side (towards the beach path).
	for i in 4:
		var top := DECK_H - 0.25 * i
		var s := Vector3(3.0, top + skirt, 0.5)
		var c := Vector3(-2.5, (top - skirt) * 0.5, oz + 0.25 + i * 0.5)
		parts.append(Props3D.b(s, c, WOOD.darkened(0.06), {"bevel": 0.04}))
		shapes.append([s, c])
	add_child(Props3D.blocks(parts))
	var body := StaticBody3D.new()
	body.collision_layer = Game.PHYS_PROPS
	add_child(body)
	for sh in shapes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sh[0]
		cs.shape = bs
		cs.position = sh[1]
		body.add_child(cs)
	# Water surface.
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = HOLE - Vector2(0.12, 0.12)
	pm.subdivide_width = 16
	pm.subdivide_depth = 8
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = preload("res://shaders/pool_water.gdshader")
	wm.set_shader_parameter("size", HOLE)
	water.material_override = wm
	water.set_meta("keep", true)
	water.position = Vector3(0, WATER_H, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	water_y = global_position.y + WATER_H
	# Swim volume.
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = Game.PHYS_CHARACTERS
	area.monitorable = false
	add_child(area)
	var acs := CollisionShape3D.new()
	var abs := BoxShape3D.new()
	# Just above the basin floor, and not over the steps: standing on a step
	# isn't swimming yet.
	abs.size = Vector3(HOLE.x - 1.3, 0.25, HOLE.y - 0.3)
	acs.shape = abs
	acs.position = Vector3(-0.55, FLOOR_H + 0.12, 0)
	area.add_child(acs)
	area.body_entered.connect(_on_enter)
	area.body_exited.connect(_on_exit)


## A little sun lounger lying along X (backrest towards -X) at `at` (deck top).
func _lounger(parts: Array, at: Vector3, cushion: Color) -> void:
	var frame := Color(0.98, 0.97, 0.94)
	for lx in [-0.7, 0.7]:
		for lz in [-0.28, 0.28]:
			parts.append(Props3D.b(Vector3(0.07, 0.3, 0.07), at + Vector3(lx, 0.15, lz), frame, {"bevel": 0.02}))
	parts.append(Props3D.b(Vector3(1.7, 0.08, 0.66), at + Vector3(0.1, 0.32, 0), frame, {"bevel": 0.03}))
	parts.append(Props3D.b(Vector3(1.2, 0.09, 0.56), at + Vector3(0.32, 0.4, 0), cushion, {"bevel": 0.04}))
	# Backrest, tilted up.
	parts.append(Props3D.b(Vector3(0.62, 0.09, 0.56), at + Vector3(-0.62, 0.5, 0), cushion, {"bevel": 0.04, "rot": Vector3(0, 0, -24)}))
	parts.append(Props3D.b(Vector3(0.26, 0.1, 0.4), at + Vector3(-0.78, 0.6, 0), Color(1, 1, 1), {"bevel": 0.04, "rot": Vector3(0, 0, -24)}))
	# Folded towel at the foot.
	parts.append(Props3D.b(Vector3(0.3, 0.06, 0.5), at + Vector3(0.75, 0.48, 0), cushion.lightened(0.5), {"bevel": 0.02}))


func _on_enter(b: Node) -> void:
	if b is Person:
		(b as Person).set_swimming(true, global_position.y + WATER_H)
		FX.splash(get_tree().current_scene, Vector3(b.global_position.x, global_position.y + WATER_H, b.global_position.z))


func _on_exit(b: Node) -> void:
	if b is Person:
		(b as Person).set_swimming(false)

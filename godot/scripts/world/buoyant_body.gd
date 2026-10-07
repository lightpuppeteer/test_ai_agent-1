class_name BuoyantBody
extends RigidBody3D
## A floating prop: Archimedes force sampled at a few hull points against the
## same wave function the sea shader uses, plus water drag. Boats, barrels and
## buoys bob and tilt with the waves and can be pushed around.

@export var float_height := 0.35      ## fraction of the hull height that sits under water at rest
var sample_points: Array[Vector3] = []
var hull_size := Vector3.ONE
var _rest_force := 0.0


static func create(parent: Node, id: String, pos: Vector3, mul: float = 1.0, yaw_deg: float = 0.0) -> BuoyantBody:
	var b := BuoyantBody.new()
	var s := Props.kit_scale(id) * mul
	var bb := Props.model_aabb(id)
	var size := bb.size * s
	var m := Props.model(id)
	m.name = "Model"
	m.scale = Vector3.ONE * s
	b.add_child(m)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Hull: lower part of the model (masts and cabins do not float).
	var hull_h := minf(size.y, maxf(size.x, size.z) * 0.45)
	box.size = Vector3(size.x * 0.9, hull_h, size.z * 0.9)
	cs.shape = box
	cs.position = Vector3(bb.get_center().x * s, bb.position.y * s + hull_h * 0.5, bb.get_center().z * s)
	b.add_child(cs)
	b.hull_size = box.size
	var c := cs.position
	var hx := box.size.x * 0.4
	var hz := box.size.z * 0.4
	var y := c.y - hull_h * 0.5
	for p in [Vector3(hx, y, hz), Vector3(-hx, y, hz), Vector3(hx, y, -hz), Vector3(-hx, y, -hz), Vector3(0, y, 0)]:
		b.sample_points.append(p)
	# Light bodies: roughly 35 % of the hull volume of water.
	b.mass = maxf(box.size.x * box.size.y * box.size.z * 1000.0 * 0.35 * b.float_height, 5.0)
	b.collision_layer = Game.PHYS_PROPS
	b.collision_mask = Game.PHYS_WORLD | Game.PHYS_PROPS | Game.PHYS_CHARACTERS | Game.PHYS_VEHICLES
	b.angular_damp = 1.5
	b.linear_damp = 0.4
	b.position = pos + Vector3(0, -hull_h * b.float_height - bb.position.y * s, 0)
	b.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(b)
	return b


func _ready() -> void:
	# Force per sample point when fully submerged so that the body floats at `float_height`.
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_rest_force = mass * g / (sample_points.size() * float_height * hull_size.y)


func _physics_process(_delta: float) -> void:
	var ocean: Ocean = Game.ocean
	if ocean == null:
		return
	var xf := global_transform
	var submerged := 0
	for p in sample_points:
		var wp := xf * p
		var wh := ocean.height_at(wp.x, wp.z)
		var depth := wh - wp.y
		if depth <= 0.0:
			continue
		submerged += 1
		var d := minf(depth, hull_size.y)
		var f := Vector3.UP * _rest_force * d
		# Drag against the point's velocity (water is thick, keeps things calm).
		var v := linear_velocity + angular_velocity.cross(wp - global_position)
		f -= v * mass * 0.35 / sample_points.size()
		apply_force(f, wp - global_position)
	if submerged > 0:
		# A tiny drift with the swell so props wander a little.
		apply_central_force(Vector3(0.05, 0, 0.02) * mass * sin(ocean.time * 0.3 + global_position.x))

class_name Car
extends VehicleBody3D
## A little drivable Kenney car built on VehicleBody3D. W/S throttle & brake
## (hold S at a standstill to reverse), A/D steer, Space handbrake, E get out.

@export var model_id := "car-kit/sedan"
@export var max_engine_force := 2600.0
@export var max_reverse_force := 1400.0
@export var max_speed_kmh := 55.0
@export var max_steer := 0.55
@export var brake_force := 35.0

var driver: Node = null
var passenger: Node = null
var interactable: Interactable
var driver_seat: Node3D
var passenger_seat: Node3D
var _steer := 0.0
var _rear_wheels: Array[VehicleWheel3D] = []
var _scale := 1.25
var _half_width := 0.9
var lights: Array[Light3D] = []
var _engine: AudioStreamPlayer3D
var _last_vy := 0.0


func _ready() -> void:
	collision_layer = Game.PHYS_VEHICLES
	# Characters are kinematic: if the car collided with them, anyone standing by a door would pin it.
	collision_mask = Game.PHYS_WORLD | Game.PHYS_PROPS | Game.PHYS_VEHICLES
	mass = 800.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.35, 0)
	_scale = Props.kit_scale(model_id)
	_build()
	can_sleep = true
	_engine = Sound.loop_3d("car_engine", self, 6.0, -80.0)


func _build() -> void:
	# A stylised early-2000s hatchback (see CorsaMesh), roomy enough for two.
	var meshes := CorsaMesh.build()
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = meshes["body"]
	add_child(visual)
	_scale = 1.0
	_half_width = CorsaMesh.WIDTH * 0.5
	var low := CollisionShape3D.new()
	var lb := BoxShape3D.new()
	lb.size = Vector3(CorsaMesh.WIDTH - 0.04, 0.6, CorsaMesh.LENGTH - 0.05)
	low.shape = lb
	low.position = Vector3(0, 0.45, 0)
	add_child(low)
	var top := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(CorsaMesh.WIDTH - 0.24, 0.72, 2.3)
	top.shape = tb
	top.position = Vector3(0, 1.2, -0.45)
	add_child(top)
	for wx in [-CorsaMesh.WHEEL_X, CorsaMesh.WHEEL_X]:
		for wz in [-CorsaMesh.WHEEL_Z, CorsaMesh.WHEEL_Z]:
			var vw := VehicleWheel3D.new()
			vw.name = "Wheel_%s_%s" % ["L" if wx > 0 else "R", "F" if wz > 0 else "B"]
			vw.position = Vector3(wx, CorsaMesh.WHEEL_R + 0.1, wz)
			vw.wheel_radius = CorsaMesh.WHEEL_R
			vw.wheel_rest_length = 0.12
			vw.suspension_travel = 0.18
			vw.suspension_stiffness = 48.0
			vw.suspension_max_force = 9000.0
			vw.damping_compression = 2.4
			vw.damping_relaxation = 3.0
			vw.wheel_friction_slip = 2.6
			vw.wheel_roll_influence = 0.25
			var front: bool = wz > 0.0
			vw.use_as_steering = front
			vw.use_as_traction = not front
			if not front:
				_rear_wheels.append(vw)
			add_child(vw)
			var wm := MeshInstance3D.new()
			wm.mesh = meshes["wheel"]
			vw.add_child(wm)
	# Seats (character root goes here; character faces the seat's -Z = car forward).
	driver_seat = Node3D.new()
	driver_seat.name = "DriverSeat"
	driver_seat.position = Vector3(0.47, 0.34, -0.3)
	driver_seat.rotation.y = PI
	add_child(driver_seat)
	passenger_seat = Node3D.new()
	passenger_seat.name = "PassengerSeat"
	passenger_seat.position = Vector3(-0.47, 0.34, -0.3)
	passenger_seat.rotation.y = PI
	add_child(passenger_seat)
	interactable = Interactable.new()
	interactable.name = "DriveUse"
	interactable.kind = "drive"
	interactable.prompt = "Drive"
	interactable.radius = 3.2
	interactable.owner_node = self
	interactable.position = Vector3(0, 0.5, 0)
	add_child(interactable)
	# Headlights for the evening.
	for sx in [-0.45, 0.45]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(sx * 1.45, 0.72, CorsaMesh.LENGTH * 0.5)
		sl.rotation.x = deg_to_rad(-8.0)
		sl.rotation.y = PI
		sl.spot_range = 22.0
		sl.spot_angle = 32.0
		sl.light_color = Color(1.0, 0.92, 0.78)
		sl.light_energy = 0.0
		sl.visible = false
		add_child(sl)
		lights.append(sl)


func speed_kmh() -> float:
	return linear_velocity.dot(global_transform.basis.z) * 3.6


func can_exit() -> bool:
	return absf(speed_kmh()) < 9.0


func set_driver(d: Node) -> void:
	driver = d
	if d == null:
		engine_force = 0.0
		brake = 4.0
		steering = 0.0
	else:
		sleeping = false
		brake = 0.0


func passenger_door() -> Vector3:
	return global_position - global_transform.basis.x.normalized() * (_half_width + 0.7)


## Free spot next to the driver's door (falls back to the other side / behind).
func exit_point() -> Vector3:
	var b := global_transform.basis
	var candidates := [
		global_position + b.x.normalized() * (_half_width + 0.9),
		global_position - b.x.normalized() * (_half_width + 0.9),
		global_position - b.z.normalized() * 3.0,
	]
	var space := get_world_3d().direct_space_state
	for p in candidates:
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.4
		q.shape = sh
		q.transform = Transform3D(Basis(), p + Vector3(0, 0.9, 0))
		q.collision_mask = Game.PHYS_PROPS | Game.PHYS_VEHICLES
		q.exclude = [get_rid()]
		if space.intersect_shape(q, 1).is_empty():
			return p
	return candidates[0]


func _physics_process(delta: float) -> void:
	var lamp_on: bool = Game.atmosphere != null and Game.atmosphere.current != "day"
	for l in lights:
		l.visible = lamp_on and driver != null
		l.light_energy = 2.5 if l.visible else 0.0
	if _engine:
		var target_db := -80.0 if driver == null else -16.0 + clampf(absf(speed_kmh()) / max_speed_kmh, 0.0, 1.0) * 6.0
		_engine.volume_db = move_toward(_engine.volume_db, target_db, delta * 60.0)
		_engine.pitch_scale = 0.8 + clampf(absf(speed_kmh()) / max_speed_kmh, 0.0, 1.0) * 1.1 + absf(engine_force) / max_engine_force * 0.15
	if driver == null:
		return
	var throttle := 0.0
	var steer_in := 0.0
	if not (Game.hud and Game.hud.is_dialogue_open()):
		throttle = maxf(Input.get_action_strength("move_forward"), Input.get_action_strength("throttle")) \
				- maxf(Input.get_action_strength("move_back"), Input.get_action_strength("brake"))
		steer_in = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var spd := speed_kmh()
	var handbrake := Input.is_action_pressed("handbrake")
	engine_force = 0.0
	brake = 0.0
	if throttle > 0.05:
		if spd < -1.0:
			brake = brake_force * throttle
		elif spd < max_speed_kmh:
			engine_force = max_engine_force * throttle * (1.0 - 0.6 * clampf(spd / max_speed_kmh, 0.0, 1.0))
	elif throttle < -0.05:
		if spd > 1.0:
			brake = brake_force * -throttle
		elif spd > -18.0:
			engine_force = -max_reverse_force * -throttle
	else:
		# Gentle engine braking.
		brake = 1.2
	for w in _rear_wheels:
		w.brake = brake_force * 1.5 if handbrake else 0.0
		w.wheel_friction_slip = 1.3 if handbrake else 2.6
	# Steering eases off at speed.
	var max_s := max_steer * lerpf(1.0, 0.35, clampf(absf(spd) / max_speed_kmh, 0.0, 1.0))
	_steer = move_toward(_steer, steer_in * max_s, delta * 2.2)
	# A little rumble on bumps.
	var jolt := absf(linear_velocity.y - _last_vy)
	_last_vy = linear_velocity.y
	if jolt > 1.2:
		Game.rumble(clampf(jolt * 0.15, 0.0, 0.6), clampf(jolt * 0.1, 0.0, 0.4), 0.12)
	steering = _steer

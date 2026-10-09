class_name CameraRig
extends Node3D
## Third-person camera: drag to orbit, wheel to zoom, collision-aware arm.
## Follows the player on foot and swings behind the car when driving.

@export var yaw := 0.0
@export var pitch := deg_to_rad(-28.0)
@export var distance := 10.0
@export var min_distance := 3.5
@export var max_distance := 22.0
@export var follow_height := 1.15
@export var mouse_sensitivity := 0.006

var target: Node3D
var vehicle_mode := false
var camera: Camera3D
var arm: SpringArm3D
var _dist := 9.0
var _dragging := false
var _last_input_time := -100.0
var _cine := false
var _cine_point := Vector3.ZERO
var _saved := []
var _shake := 0.0
var _shake_time := 0.0


func _ready() -> void:
	Game.camera_rig = self
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arm = SpringArm3D.new()
	arm.name = "Arm"
	arm.collision_mask = Game.PHYS_WORLD | Game.PHYS_PROPS
	arm.margin = 0.3
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	arm.shape = sphere
	add_child(arm)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 45.0
	camera.near = 0.1
	camera.far = 1500.0
	arm.add_child(camera)
	camera.current = true
	_dist = distance
	if Game.player:
		follow(Game.player, false)
	else:
		Game.player_registered.connect(func(p: Node) -> void: follow(p, false))


func follow(t: Node3D, is_vehicle: bool) -> void:
	target = t
	vehicle_mode = is_vehicle
	if is_vehicle:
		distance = maxf(distance, 9.5)


func snap() -> void:
	if target:
		global_position = _target_point()
	reset_physics_interpolation()


## Story camera: look at a point from a given yaw/pitch/distance until end_cinematic().
## `free`: the arm ignores props (benches, trees) so a close shot from behind
## a bench isn't pushed into the characters' heads.
func cinematic(point: Vector3, yaw_rad: float, pitch_deg: float, dist: float, free: bool = false) -> void:
	if not _cine:
		_saved = [yaw, pitch, distance]
	_cine = true
	arm.collision_mask = Game.PHYS_WORLD if free else Game.PHYS_WORLD | Game.PHYS_PROPS
	_cine_point = point
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "yaw", yaw + wrapf(yaw_rad - yaw, -PI, PI), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "pitch", deg_to_rad(pitch_deg), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "distance", dist, 1.2).set_trans(Tween.TRANS_SINE)


func end_cinematic() -> void:
	if not _cine:
		return
	_cine = false
	arm.collision_mask = Game.PHYS_WORLD | Game.PHYS_PROPS
	if _saved.size() == 3:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "pitch", _saved[1], 1.0)
		tw.tween_property(self, "distance", _saved[2], 1.0)


func shake(strength: float, seconds: float) -> void:
	_shake = strength
	_shake_time = seconds


func _target_point() -> Vector3:
	if _cine:
		return _cine_point
	var xf: Transform3D = target.get_global_transform_interpolated() if target.is_inside_tree() else target.global_transform
	return xf.origin + Vector3(0, follow_height + (0.4 if vehicle_mode else 0.0), 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance * 0.9, min_distance, max_distance)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance * 1.1, min_distance, max_distance)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * mouse_sensitivity
		pitch = clampf(pitch - mm.relative.y * mouse_sensitivity, deg_to_rad(-75.0), deg_to_rad(-3.0))
		_last_input_time = Time.get_ticks_msec() / 1000.0
	elif event is InputEventMagnifyGesture:
		distance = clampf(distance / (event as InputEventMagnifyGesture).factor, min_distance, max_distance)
	elif event is InputEventPanGesture:
		# Trackpad two-finger scroll orbits the camera.
		var pg := event as InputEventPanGesture
		yaw -= pg.delta.x * 0.03
		pitch = clampf(pitch - pg.delta.y * 0.02, deg_to_rad(-75.0), deg_to_rad(-3.0))
		_last_input_time = Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	# Right stick orbits.
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.2:
		yaw -= rs.x * 2.5 * delta
		pitch = clampf(pitch - rs.y * 1.5 * delta, deg_to_rad(-75.0), deg_to_rad(-3.0))
		_last_input_time = Time.get_ticks_msec() / 1000.0
	if vehicle_mode and target is RigidBody3D:
		var vel := (target as RigidBody3D).linear_velocity
		var idle := Time.get_ticks_msec() / 1000.0 - _last_input_time > 1.2
		if idle and Vector2(vel.x, vel.z).length() > 2.0:
			var fwd := target.global_transform.basis.z
			var want := atan2(-fwd.x, -fwd.z)
			yaw = lerp_angle(yaw, want, clampf(delta * 2.2, 0.0, 1.0))
	var p := _target_point()
	global_position = global_position.lerp(p, clampf(1.0 - exp(-12.0 * delta), 0.0, 1.0))
	_dist = lerpf(_dist, distance, clampf(delta * 8.0, 0.0, 1.0))
	rotation = Vector3(pitch, yaw, 0)
	arm.spring_length = _dist
	if _shake_time > 0.0:
		_shake_time -= delta
		var k := _shake * clampf(_shake_time, 0.0, 1.0)
		camera.h_offset = randf_range(-k, k) * 0.3
		camera.v_offset = randf_range(-k, k) * 0.3
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	if target is CollisionObject3D:
		arm.clear_excluded_objects()
		arm.add_excluded_object((target as CollisionObject3D).get_rid())

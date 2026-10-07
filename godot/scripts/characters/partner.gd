class_name Partner
extends Person
## Your companion. Strolls along beside you, sits next to you on benches, lies
## on the towel beside yours and rides along in the car.

@export var display_name := "Him"
@export var follow_distance := 2.2
@export var lines: Array[String] = [
	"I love days like this with you.",
	"Race you to the beach?",
	"Remember when we first came here?",
]

var interactable: Interactable
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO
var _line := 0
var _repath_side := 1.0
var _goal: Variant = null


func _ready() -> void:
	look = "character-male-a"
	walk_speed = 3.1
	run_speed = 6.6
	super._ready()
	Game.partner = self
	collision_mask = Game.PHYS_WORLD | Game.PHYS_PROPS | Game.PHYS_VEHICLES
	interactable = Interactable.new()
	interactable.kind = "talk"
	interactable.prompt = "Talk"
	interactable.radius = 2.0
	interactable.position = Vector3(0, 0.6, 0)
	interactable.owner_node = self
	add_child(interactable)
	interactable.used.connect(_on_talk)
	if Game.player:
		_connect_player(Game.player)
	else:
		Game.player_registered.connect(_connect_player)


func _connect_player(p: Node) -> void:
	p.pose_changed.connect(_on_player_pose)


func _on_talk(by: Node, _seat: Node3D) -> void:
	if Game.hud == null:
		return
	var p := by as Node3D
	facing = atan2(-(p.global_position.x - global_position.x), -(p.global_position.z - global_position.z))
	gesture("emote-yes")
	await Game.hud.say(display_name, [lines[_line % lines.size()]], Color(0.45, 0.66, 0.95))
	_line += 1


func _physics_process(delta: float) -> void:
	_think(delta)
	super._physics_process(delta)


func _think(delta: float) -> void:
	intent = Vector3.ZERO
	want_run = false
	var p: Person = Game.player
	if p == null or pose != "move":
		return
	if _goal != null:
		var tg: Vector3 = _goal - global_position
		tg.y = 0.0
		intent = tg.normalized()
		want_run = tg.length() > 4.0
		return
	if p.pose == "drive":
		return
	# Walk to a spot beside and slightly behind the player.
	var back := p.global_transform.basis.z
	var side := p.global_transform.basis.x
	var goal := p.global_position + back * 1.0 + side * 1.4
	var to := goal - global_position
	to.y = 0.0
	var d := to.length()
	var far := (p.global_position - global_position).length()
	if far > 40.0:
		_appear_near(p)
		return
	if d > 0.6 and far > follow_distance * 0.7:
		intent = to / d * clampf(d / 2.0, 0.35, 1.0)
		want_run = far > 7.0 or p.velocity.length() > p.walk_speed * 1.2
		# Unstick: if barely moving while trying, sidestep or hop.
		if global_position.distance_to(_last_pos) < 0.3 * delta * walk_speed:
			_stuck_time += delta
		else:
			_stuck_time = maxf(_stuck_time - delta, 0.0)
		if _stuck_time > 0.6:
			intent = (intent + side * _repath_side).normalized()
			if _stuck_time > 1.2 and is_on_floor():
				want_jump = true
				_repath_side = -_repath_side
				_stuck_time = 0.0
	else:
		_stuck_time = 0.0
		# Idle: look at the player.
		var tp := p.global_position - global_position
		facing = lerp_angle(facing, atan2(-tp.x, -tp.z), clampf(delta * 3.0, 0.0, 1.0))
	_last_pos = global_position


func _appear_near(p: Person) -> void:
	var pos := p.global_position + p.global_transform.basis.z * 2.0 + p.global_transform.basis.x * 1.2
	if Game.terrain:
		pos.y = maxf(Game.terrain.height_at(pos.x, pos.z), p.global_position.y) + 0.3
	teleport(pos, p.rotation.y)


## Mirror the player: sit / lie next to them, hop in the car.
func _on_player_pose(new_pose: String) -> void:
	var p: Player = Game.player
	match new_pose:
		"sit", "lie":
			var it := p.anchor_owner
			var seat: Node3D = it.free_seat(p.global_position) if it else null
			if seat == null and new_pose == "lie":
				var other := _nearest_free_towel(p)
				if other:
					it = other
					seat = other.free_seat(global_position)
			if seat:
				await _walk_to(seat.global_position, 6.0)
				if p.pose == new_pose and pose == "move":
					enter_anchor(seat, new_pose, it)
		"drive":
			var car: Car = p.car
			if car and pose == "move":
				await _walk_to(car.passenger_door(), 4.0)
				if p.pose == "drive" and pose == "move":
					await enter_anchor(car.passenger_seat, "drive", null, 0.4)
					car.passenger = self
		"move":
			if pose == "drive" and anchor and anchor.get_parent() is Car:
				var car := anchor.get_parent() as Car
				car.passenger = null
				var b := car.global_transform.basis
				leave_anchor(car.global_position - b.x.normalized() * 2.0, 0.35)
			elif pose == "sit" or pose == "lie":
				await get_tree().create_timer(0.35).timeout
				leave_anchor()


func _nearest_free_towel(p: Node3D) -> Interactable:
	var best: Interactable = null
	var best_d := 4.0
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it and it.kind == "lie" and it.has_free_seat():
			var d := it.global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = it
	return best


## Walks towards a point for up to `timeout` seconds (or until close).
func _walk_to(target: Vector3, timeout: float) -> void:
	_goal = target
	var t := 0.0
	while t < timeout and pose == "move":
		var to := target - global_position
		to.y = 0.0
		if to.length() < 0.9:
			break
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_goal = null

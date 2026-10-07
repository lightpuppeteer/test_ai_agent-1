class_name Player
extends Person
## The player's brain: camera-relative keyboard/gamepad movement, picking the
## nearest thing to interact with, and the sit / lie / drive transitions.

signal focus_changed(it: Interactable)

var focus: Interactable = null
var car: Node = null              # the car being driven (if any)
var input_enabled := true


func _ready() -> void:
	super._ready()
	Game.register_player(self)


func _physics_process(delta: float) -> void:
	_read_input()
	super._physics_process(delta)
	_update_focus()


func _read_input() -> void:
	intent = Vector3.ZERO
	want_run = false
	if not input_enabled or (Game.hud and Game.hud.is_dialogue_open()):
		return
	var mv: Vector2 = Game.move_input()
	if pose == "move":
		var cam: Node = Game.camera_rig
		var yaw: float = cam.yaw if cam else 0.0
		# Camera-relative: "up" walks away from the camera.
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		intent = (right * mv.x - fwd * mv.y)
		if intent.length() > 1.0:
			intent = intent.normalized()
		want_run = Input.is_action_pressed("run")
		if Input.is_action_just_pressed("jump"):
			want_jump = true
	elif pose == "sit" or pose == "lie":
		# Moving gets you up again.
		if mv.length() > 0.5:
			stand_up()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if Game.hud and Game.hud.is_dialogue_open():
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		match pose:
			"move":
				if focus:
					use(focus)
			"sit", "lie":
				stand_up()
			"drive":
				if car and car.can_exit():
					exit_car()
				elif Game.hud:
					Game.hud.toast("Slow down to get out")
	elif event.is_action_pressed("cycle_look"):
		# O: her outfit · Shift+O: his outfit.
		var who: Person = Game.partner if Input.is_key_pressed(KEY_SHIFT) and Game.partner else self
		var nm := who.next_look()
		if Game.hud:
			Game.hud.toast("👗 " + nm if who == self else "👕 " + nm)
	elif event.is_action_pressed("toggle_time") and Game.atmosphere:
		var p: String = Game.atmosphere.cycle_preset()
		if Game.hud:
			Game.hud.toast({"day": "☀ Sunny afternoon", "golden": "🌅 Golden hour", "night": "🌙 Starry night"}.get(p, p))


func use(it: Interactable) -> void:
	match it.kind:
		"sit", "lie":
			var seat := it.free_seat(global_position)
			if seat:
				enter_anchor(seat, it.kind, it)
		"drive":
			enter_car(it.owner_node)
		_:
			it.interact(self)


func stand_up() -> void:
	leave_anchor()


func enter_car(c: Node) -> void:
	if c == null or pose != "move":
		return
	car = c
	await enter_anchor(c.driver_seat, "drive", c.interactable, 0.4)
	c.set_driver(self)
	if Game.camera_rig:
		Game.camera_rig.follow(c, true)


func exit_car() -> void:
	if car == null:
		return
	var c := car
	c.set_driver(null)
	await leave_anchor(c.exit_point(), 0.35)
	car = null
	if Game.camera_rig:
		Game.camera_rig.follow(self, false)


func _update_focus() -> void:
	var best: Interactable = null
	if pose == "move" and input_enabled:
		var best_score := INF
		var fwd := -global_transform.basis.z
		for n in get_tree().get_nodes_in_group("interactable"):
			var it := n as Interactable
			if it == null or not it.enabled or not it.is_visible_in_tree():
				continue
			var to := it.global_position - global_position
			to.y *= 0.5
			var d := to.length()
			if d > it.radius or absf(to.y) > 2.0:
				continue
			if not it.can_use(self):
				continue
			# Prefer what's in front of you.
			var facing_bonus := 1.0 - 0.4 * clampf(fwd.dot(to.normalized()), -1.0, 1.0)
			var score := d * facing_bonus
			if score < best_score:
				best_score = score
				best = it
	if best != focus:
		focus = best
		focus_changed.emit(focus)

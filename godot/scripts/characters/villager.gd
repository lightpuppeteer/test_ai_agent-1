class_name Villager
extends CharacterBody3D
## An animal neighbour (Kenney Cube Pets). Wanders around its home, nibbles,
## dances now and then, and chats when you press E.

@export var species := "animal-cat"
## Optional palette recolour {Color(from): Color(to)} for the model.
var recolor := {}
@export var display_name := "Mochi"
@export var color := Color(0.98, 0.62, 0.45)
@export var lines: Array[String] = ["Hi there!"]
@export var wander_radius := 7.0
@export var speed := 1.4
@export var voice := 1.0          ## babble pitch

var home := Vector3.ZERO
var model: Node3D
var anim: AnimationPlayer
var interactable: Interactable
var _state := "idle"
var _timer := 0.0
var _target := Vector3.ZERO
var _facing := 0.0
var _anim_name := ""
var _talk_index := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("villagers")
	collision_layer = Game.PHYS_CHARACTERS
	collision_mask = Game.PHYS_WORLD | Game.PHYS_PROPS | Game.PHYS_VEHICLES | Game.PHYS_WALLS
	floor_snap_length = 0.4
	_rng.seed = hash(display_name)
	home = global_position
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.1
	cs.shape = cap
	cs.position.y = 0.55
	add_child(cs)
	var visual := Node3D.new()
	visual.rotation.y = PI          # model faces +Z; the body faces -Z
	add_child(visual)
	model = Props.model("cube-pets/" + species)
	model.scale = Vector3.ONE * Props.kit_scale("cube-pets/" + species)
	if not recolor.is_empty():
		Props.recolor(model, recolor)
	visual.add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	for n in ["idle", "walk", "run", "eat", "dance"]:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	interactable = Interactable.new()
	interactable.kind = "talk"
	interactable.prompt = "Talk to " + display_name
	interactable.radius = 2.2
	interactable.position = Vector3(0, 0.6, 0)
	interactable.owner_node = self
	add_child(interactable)
	interactable.used.connect(_on_talk)
	_facing = _rng.randf() * TAU
	_enter("idle")


func _play(n: String, blend := 0.2) -> void:
	if n != _anim_name and anim.has_animation(n):
		_anim_name = n
		anim.play(n, blend)


func _enter(s: String) -> void:
	_state = s
	match s:
		"idle":
			_timer = _rng.randf_range(2.0, 5.0)
			_play("idle")
		"walk":
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * wander_radius
			_target = home + Vector3(cos(a) * r, 0, sin(a) * r)
			_timer = 8.0
			_play("walk")
		"eat", "dance":
			_timer = _rng.randf_range(2.5, 4.0)
			_play(s)
		"talk":
			_play("gesture-positive", 0.1)


func _physics_process(delta: float) -> void:
	var v := Vector3.ZERO
	match _state:
		"idle", "eat", "dance":
			_timer -= delta
			if _timer <= 0.0:
				var r := _rng.randf()
				_enter("walk" if r < 0.6 else ("eat" if r < 0.8 else ("dance" if r < 0.9 else "idle")))
		"walk":
			var to := _target - global_position
			to.y = 0.0
			_timer -= delta
			if to.length() < 0.5 or _timer <= 0.0:
				_enter("idle")
			else:
				v = to.normalized() * speed
				_facing = lerp_angle(_facing, atan2(-to.x, -to.z), clampf(delta * 6.0, 0.0, 1.0))
				# Stay on land.
				var ahead := global_position + to.normalized() * 1.0
				if Game.terrain and Game.terrain.height_at(ahead.x, ahead.z) < 0.6:
					_enter("idle")
					v = Vector3.ZERO
		"talk":
			var p: Node3D = Game.player
			if p:
				var tp := p.global_position - global_position
				_facing = lerp_angle(_facing, atan2(-tp.x, -tp.z), clampf(delta * 8.0, 0.0, 1.0))
			if not anim.is_playing() or _anim_name != "gesture-positive":
				_play("idle")
	velocity.x = v.x
	velocity.z = v.z
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	rotation.y = _facing


func _on_talk(_by: Node, _seat: Node3D) -> void:
	if Game.hud == null:
		return
	_enter("talk")
	Sound.play_ui("talk")
	if Game.quests and await Game.quests.handle_talk(display_name, color):
		_enter("idle")
		return
	var line: String = lines[_talk_index % lines.size()]
	_talk_index += 1
	await Game.hud.say(display_name, [Dialogue.style(line)], color, voice)
	_enter("idle")

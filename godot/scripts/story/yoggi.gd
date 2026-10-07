class_name Yoggi
extends CharacterBody3D
## Her cat. Lives in her garden until the move; during "Operation Catch Yoggi"
## he dodges you a few times before accepting the catnip bribe. Afterwards he
## lives in our house and judges everyone.

## "home" (her garden) | "wild" (being chased) | "tired" (ready to be picked up)
## | "carried" | "house" (lives with us)
var state := "home"
var model: Node3D
var anim: AnimationPlayer
var interactable: Interactable
var _target := Vector3.ZERO
var _home := Vector3.ZERO
var _timer := 0.0
var _flees := 0
var _facing := 0.0
var _anim := ""
var _shape: CollisionShape3D

const LINES_HOME := ["Mrrp.", "(Yoggi blinks at you very slowly.)", "(Yoggi is busy being a loaf.)"]
const LINES_HOUSE := [
	"(Yoggi is sitting on the keyboard. Again.)",
	"(Yoggi stares at you with pure judgment.)",
	"Mrrrow. (Translation: where is my dinner, peasant?)",
	"(Yoggi knocks a pen off the desk. Eye contact maintained.)",
	"(Yoggi has claimed the best spot on the couch.)",
]


func _ready() -> void:
	collision_layer = Game.PHYS_CHARACTERS
	collision_mask = Game.PHYS_WORLD | Game.PHYS_PROPS | Game.PHYS_WALLS
	_home = global_position
	var cs := CollisionShape3D.new()
	_shape = cs
	var sh := CapsuleShape3D.new()
	sh.radius = 0.3
	sh.height = 0.8
	cs.shape = sh
	cs.position.y = 0.4
	add_child(cs)
	var vis := Node3D.new()
	vis.rotation.y = PI
	add_child(vis)
	model = Props.model("cube-pets/animal-cat")
	model.scale = Vector3.ONE * 0.5
	vis.add_child(model)
	# A collar so you can tell him apart from Mochi.
	var collar := Props3D.blocks([Props3D.b(Vector3(0.9, 0.12, 0.9), Vector3(0, 0.0, 0), Color(0.95, 0.35, 0.45), {"bevel": 0.03})])
	collar.position = Vector3(0, 0.55, 0.35)
	collar.scale = Vector3.ONE * 0.5
	vis.add_child(collar)
	var tag := Label3D.new()
	tag.text = "Yoggi"
	tag.font_size = 40
	tag.pixel_size = 0.006
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 1.3
	tag.modulate = Color(0.95, 0.45, 0.55)
	add_child(tag)
	anim = model.find_child("AnimationPlayer", true, false)
	for n in ["idle", "walk", "run", "eat"]:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_play("idle")
	interactable = Interactable.new()
	interactable.kind = "talk"
	interactable.prompt = "Pet Yoggi"
	interactable.radius = 1.8
	interactable.position.y = 0.5
	add_child(interactable)
	interactable.used.connect(_on_used)


func _play(n: String) -> void:
	if n != _anim and anim.has_animation(n):
		_anim = n
		anim.play(n, 0.2)


func start_chase() -> void:
	if state == "home":
		state = "wild"
		_flees = 0
		interactable.prompt = "Catch Yoggi"


func _on_used(by: Node, _seat: Node3D) -> void:
	match state:
		"tired":
			state = "carried"
			visible = false
			_shape.disabled = true
			interactable.enabled = false
			(by as Person).set_accessory("yoggi", true)
			Sound.play("meow", -4.0)
			if Game.hud:
				Game.hud.toast("🐱 Yoggi accepted the catnip bribe! Bring him home.")
		"wild":
			_flee_from(by as Node3D)
		"house":
			Sound.play("meow", -6.0, randf_range(0.9, 1.2))
			if Game.hud:
				Game.hud.say("Yoggi", [LINES_HOUSE[randi() % LINES_HOUSE.size()]], Color(0.95, 0.45, 0.55), 1.6)
		_:
			Sound.play("meow", -6.0, randf_range(0.9, 1.2))
			if Game.hud:
				Game.hud.say("Yoggi", [LINES_HOME[randi() % LINES_HOME.size()]], Color(0.95, 0.45, 0.55), 1.6)


## Puts him in our house (after the quest, or when loading a save).
func settle_home(pos: Vector3) -> void:
	state = "house"
	visible = true
	_shape.disabled = false
	interactable.enabled = true
	interactable.prompt = "Pet Yoggi"
	global_position = pos
	_home = pos
	velocity = Vector3.ZERO


func _flee_from(p: Node3D) -> void:
	_flees += 1
	Sound.play("meow", -4.0, 1.3)
	if _flees >= 4:
		state = "tired"
		interactable.prompt = "Pick up Yoggi (catnip ready)"
		_play("idle")
		if Game.hud:
			Game.hud.toast("😾 Yoggi is out of breath. Now's your chance!")
		return
	var away := global_position - p.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	var side := Vector3(-away.z, 0, away.x) * randf_range(-0.8, 0.8)
	_target = global_position + (away + side).normalized() * 6.0
	# Stay near the garden.
	if _target.distance_to(_home) > 9.0:
		_target = _home + (_target - _home).normalized() * 8.0
	_timer = 2.5
	if Game.hud:
		Game.hud.toast(["Yoggi: \"Nope.\"", "Yoggi zooms away!", "Yoggi does a dramatic sideways hop."][(_flees - 1) % 3])


func _physics_process(delta: float) -> void:
	if state == "carried":
		return
	var v := Vector3.ZERO
	if state == "wild":
		var p: Node3D = Game.player
		if _timer > 0.0:
			_timer -= delta
			var to := _target - global_position
			to.y = 0.0
			if to.length() > 0.4:
				v = to.normalized() * 5.0
				_facing = atan2(-to.x, -to.z)
				_play("run")
			else:
				_timer = 0.0
		elif p and p.global_position.distance_to(global_position) < 2.6:
			_flee_from(p)
		else:
			_play("idle")
	else:
		_play("idle")
		if state == "home" or state == "house":
			var p2: Node3D = Game.player
			if p2 and p2.global_position.distance_to(global_position) < 4.0:
				var tp := p2.global_position - global_position
				_facing = lerp_angle(_facing, atan2(-tp.x, -tp.z), delta * 3.0)
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	rotation.y = _facing

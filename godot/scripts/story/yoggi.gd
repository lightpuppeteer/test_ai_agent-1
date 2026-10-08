class_name Yoggi
extends CharacterBody3D
## Her cat: a chunky British Shorthair, blue-grey plush coat, green eyes. Lives in her garden until the move; during "Operation Catch Yoggi"
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
const LINES_ASLEEP := [
	"(Yoggi is fast asleep. A tiny purr escapes.)",
	"(Yoggi is a loaf. A sleeping loaf. Do not disturb the loaf.)",
	"(Yoggi stretches one paw, sighs dramatically, and keeps sleeping.)",
	"(Zzz... his whiskers twitch. Probably dreaming about ham.)",
]
const LINES_HOUSE := [
	"(Yoggi is sitting on the keyboard. Again.)",
	"(Yoggi stares at you with pure judgment.)",
	"Mrrrow. (Translation: where is my dinner, peasant?)",
	"(Yoggi knocks a pen off the desk. Eye contact maintained.)",
	"(Yoggi has claimed the best spot on the couch.)",
]


## The Kenney cube-pets cat recoloured as Yoggi (also used when he's carried).
static func make_model() -> Node3D:
	var m := Props.model("cube-pets/animal-cat")
	Props.recolor(m, {
		Color8(255, 180, 73): Color8(120, 205, 95),     # orange eyes -> green
		Color8(126, 130, 152): Color8(146, 156, 178),   # coat -> lighter British blue
	})
	return m


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
	model = make_model()
	model.scale = Vector3(0.56, 0.5, 0.53)      # a little rounder: British Shorthair build
	vis.add_child(model)
	# A pink collar with a little bell, low on the front of his (very round) face.
	var bb := Props.model_aabb("cube-pets/animal-cat")
	var front := (bb.position.z + bb.size.z) * model.scale.z
	var w := bb.size.x * model.scale.x
	var collar := Props3D.blocks([
		Props3D.b(Vector3(w + 0.03, 0.06, 0.34), Vector3(0, 0, -0.15), Color(0.95, 0.35, 0.45), {"bevel": 0.02}),
		Props3D.b(Vector3(0.08, 0.08, 0.06), Vector3(0, -0.06, 0.03), Color(1.0, 0.85, 0.35), {"mat": "shiny", "bevel": 0.03}),
	])
	collar.position = Vector3(0, bb.position.y * model.scale.y + 0.22, front + 0.005)
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
		_home = global_position
		_calm_t = 0.0
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
			if _on_spot:
				Sound.play("meow", -16.0, 0.7)
				if Game.hud:
					Game.hud.say("Yoggi", [LINES_ASLEEP[randi() % LINES_ASLEEP.size()]], Color(0.95, 0.45, 0.55), 1.6)
				return
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
	_wake()
	_mode = "sleep"     # first thing he does in the new house: find the sofa
	_mode_t = 0.0
	_hops = 0


# ---------------------------------------------------------------------------
# Life in our house: mostly napping on the sofa, sometimes a little patrol.
# ---------------------------------------------------------------------------

var _mode := "idle"          # sleep | wander | idle
var _mode_t := 0.0
var _hops := 0
var _path := PackedVector3Array()
var _path_i := 0
var _on_spot := false
var _zzz_t := 0.0
var _nap_from := Vector3.ZERO


func _house_tick(delta: float) -> Vector3:
	_mode_t -= delta
	match _mode:
		"sleep":
			if _on_spot:
				_zzz_t -= delta
				if _zzz_t <= 0.0:
					_zzz_t = 1.1
					_spawn_z()
				if _mode_t <= 0.0:
					_wake()
					_mode = "wander"
					_mode_t = 0.0
					_hops = 0
				return Vector3.ZERO
			var spot: Variant = _nap_spot()
			var floor_target := global_position
			if spot != null:
				var sp: Vector3 = spot
				floor_target = Vector3(sp.x, global_position.y, sp.z)
			var v := _follow_path(floor_target, 1.3)
			if v == Vector3.ZERO:
				_lie_down(spot)
			return v
		"wander":
			if _path.is_empty() or _path_i >= _path.size():
				if _mode_t > 0.0:
					_play("idle")
					return Vector3.ZERO
				_hops += 1
				if _hops > 3:
					_mode = "sleep"
					return Vector3.ZERO
				_pick_wander_target()
				_mode_t = randf_range(3.0, 6.0)
			return _follow_path(Vector3.INF, 1.6)
		_:
			_mode = "sleep"
	return Vector3.ZERO


func _nap_spot() -> Variant:
	var d: DecorSystem = Game.world.decor if Game.world else null
	return d.nap_spot() if d else null


func _pick_wander_target() -> void:
	var region: NavigationRegion3D = NavBaker.regions.get("house")
	_path = PackedVector3Array()
	_path_i = 0
	if region == null or region.navigation_mesh == null:
		return
	var p := NavigationServer3D.region_get_random_point(region.get_rid(), 1, true)
	_path = NavBaker.path(get_world_3d(), global_position, p)
	_path_i = 1 if _path.size() > 1 else 0


## Walks along a navmesh path to `target` (or the current wander path when
## target is INF); returns the velocity, ZERO once arrived.
func _follow_path(target: Vector3, speed: float) -> Vector3:
	# Indoors before the room's navmesh exists: wait instead of walking into a table.
	if state == "house":
		var region: NavigationRegion3D = NavBaker.regions.get("house")
		if region == null or region.navigation_mesh == null:
			_play("idle")
			return Vector3.ZERO
	if target != Vector3.INF:
		var goal := NavBaker.snap(get_world_3d(), target)
		if _path.is_empty() or _path[_path.size() - 1].distance_to(goal) > 0.6:
			_path = NavBaker.path(get_world_3d(), global_position, goal)
			_path_i = 1 if _path.size() > 1 else 0
			if _path.is_empty():
				_path = PackedVector3Array([target])
				_path_i = 0
	while _path_i < _path.size():
		var to := _path[_path_i] - global_position
		to.y = 0.0
		if to.length() < 0.35:
			_path_i += 1
			continue
		_facing = atan2(-to.x, -to.z)
		_play("walk")
		return to.normalized() * speed
	_path = PackedVector3Array()
	return Vector3.ZERO


func _lie_down(spot: Variant) -> void:
	_on_spot = true
	_mode_t = randf_range(25.0, 50.0)
	_zzz_t = 0.6
	_shape.disabled = true
	_nap_from = global_position
	var to: Vector3 = spot if spot != null else global_position
	var tw := create_tween()
	tw.tween_property(self, "global_position", to + Vector3(0, 0.05, 0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Curl into a loaf: a bit flatter and wider, very still.
	tw.parallel().tween_property(model, "scale", Vector3(0.6, 0.38, 0.56), 0.6)
	_play("static" if anim.has_animation("static") else "idle")
	anim.speed_scale = 0.25
	interactable.prompt = "Pet sleepy Yoggi"


func _wake() -> void:
	if not _on_spot:
		return
	_on_spot = false
	anim.speed_scale = 1.0
	model.scale = Vector3(0.56, 0.5, 0.53)
	global_position = _nap_from
	_shape.disabled = false
	interactable.prompt = "Pet Yoggi"


## A little "z" that floats up and fades.
func _spawn_z() -> void:
	var z := Label3D.new()
	z.text = ["z", "Z", "z"][randi() % 3]
	z.font_size = 64
	z.pixel_size = 0.004 + randf() * 0.002
	z.outline_size = 12
	z.modulate = Color(0.75, 0.85, 1.0)
	z.outline_modulate = Color(0.25, 0.3, 0.5, 0.8)
	z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if Game.hud and Game.hud._bold_font:
		z.font = Game.hud._bold_font
	add_child(z)
	z.position = Vector3(0.15, 0.55, 0.0)
	var tw := z.create_tween().set_parallel(true)
	tw.tween_property(z, "position", Vector3(0.45 + randf() * 0.2, 1.3, randf_range(-0.1, 0.1)), 2.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(z, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.tween_property(z, "outline_modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.tween_property(z, "rotation:z", randf_range(-0.4, 0.4), 2.2)
	tw.chain().tween_callback(z.queue_free)


func _flee_from(p: Node3D) -> void:
	_flees += 1
	Sound.play("meow", -4.0, 1.3)
	if _flees >= 5:
		state = "tired"
		interactable.prompt = "Pick up Yoggi (catnip ready)"
		_path = PackedVector3Array()
		_play("idle")
		if Game.hud:
			Game.hud.toast("😾 Yoggi is out of breath. Now's your chance!")
		return
	# Pick a getaway spot on the walkable map: away from her, through the
	# neighbourhood (benches, gardens, round the houses), but not too far from home.
	var away := global_position - p.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	var best := global_position
	var best_score := -INF
	for i in 10:
		var ang := randf_range(-1.3, 1.3)
		var dir := away.rotated(Vector3.UP, ang)
		var cand := global_position + dir * randf_range(7.0, 13.0)
		cand = NavBaker.snap(get_world_3d(), cand)
		var score := cand.distance_to(p.global_position) - maxf(cand.distance_to(_home) - 22.0, 0.0) * 3.0 + randf() * 2.0
		if score > best_score:
			best_score = score
			best = cand
	_target = best
	_path = NavBaker.path(get_world_3d(), global_position, best)
	if _path.size() < 2:
		_path = PackedVector3Array([global_position, best])
	_path_i = 1
	_timer = 5.0
	_stuck_t = 0.0
	if Game.hud:
		Game.hud.toast(["Yoggi: \"Nope.\"", "Yoggi zooms away!", "Yoggi does a dramatic sideways hop.", "Yoggi weaves round a bench like a tiny ninja."][(_flees - 1) % 4])


func _physics_process(delta: float) -> void:
	if state == "carried":
		return
	var v := Vector3.ZERO
	if state == "wild":
		_calm_t -= delta
		var p: Node3D = Game.player
		if _timer > 0.0:
			_timer -= delta
			v = _follow_path(Vector3.INF, 5.4)
			if v == Vector3.ZERO:
				_timer = 0.0
			else:
				_play("run")
				# Little bounding hops while he runs.
				model.position.y = absf(sin(Time.get_ticks_msec() * 0.014)) * 0.12
		elif p and p.global_position.distance_to(global_position) < 2.8 and _calm_t <= 0.0:
			_calm_t = 0.9
			_flee_from(p)
		else:
			model.position.y = 0.0
			_play("idle")
			var tp := p.global_position - global_position if p else Vector3.FORWARD
			_facing = lerp_angle(_facing, atan2(-tp.x, -tp.z), delta * 4.0)
	elif state == "house":
		v = _house_tick(delta)
		if _on_spot:
			rotation.y = _facing
			return
		if v == Vector3.ZERO and _mode != "wander":
			_play("idle")
	else:
		_play("idle")
		if state == "home":
			var p2: Node3D = Game.player
			if p2 and p2.global_position.distance_to(global_position) < 4.0:
				var tp := p2.global_position - global_position
				_facing = lerp_angle(_facing, atan2(-tp.x, -tp.z), delta * 3.0)
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - 20.0 * delta
	var before := global_position
	move_and_slide()
	rotation.y = _facing
	_check_stuck(v, before, delta)


## Trying to move but not getting anywhere: re-plan, then just hop past it.
var _stuck_t := 0.0
var _calm_t := 0.0

func _check_stuck(v: Vector3, before: Vector3, delta: float) -> void:
	if v.length() < 0.1:
		_stuck_t = 0.0
		return
	if global_position.distance_to(before) < v.length() * delta * 0.25:
		_stuck_t += delta
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)
	if _stuck_t > 0.7 and _path_i < _path.size():
		# Re-plan from here (something moved, or we got shoved off the path).
		var goal := _path[_path.size() - 1]
		_path = NavBaker.path(get_world_3d(), global_position, goal)
		_path_i = 1 if _path.size() > 1 else 0
	if _stuck_t > 1.6 and _path_i < _path.size():
		# Cats can jump: skip ahead to the next waypoint.
		_stuck_t = 0.0
		var hop_to := _path[_path_i] + Vector3(0, 0.1, 0)
		var tw := create_tween()
		tw.tween_property(self, "global_position", hop_to, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_path_i += 1

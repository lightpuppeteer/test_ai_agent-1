class_name Person
extends CharacterBody3D
## A chibi character (Kenney "mini characters"): movement, animation and
## anchored poses (sit on a bench, lie on a towel, drive). The player and the
## partner are both Persons; only the "brain" differs (input vs. follow AI).

signal pose_changed(pose: String)

const LOOKS := [
	"character-female-f", "character-female-b", "character-female-c", "character-female-d", "character-female-e",
	"character-male-a", "character-male-b", "character-male-c", "character-male-d", "character-male-e", "character-male-f",
]

## "her" / "him" build a custom avatar (see AvatarLooks); any other id is a Kenney mini character.
@export var look := "her"
var outfit := ""
@export var walk_speed := 3.0
@export var run_speed := 6.2
@export var accel := 14.0
@export var turn_speed := 12.0
@export var jump_velocity := 6.8
@export var gravity := 20.0
## Walk/run animation playback speed per m/s (keeps feet from sliding).
@export var walk_anim_rate := 0.36
@export var run_anim_rate := 0.2

## "move" | "sit" | "lie" | "drive" | "transition"
var pose := "move"
var anchor: Node3D = null
var anchor_owner: Interactable = null
## Set by the brain every physics tick.
var intent := Vector3.ZERO      # desired horizontal velocity direction (length ≤ 1)
var want_run := false
var want_jump := false
var facing := 0.0               # yaw (radians), 0 faces -Z

var visual: Node3D              # yaw-only pivot, rotated so the model faces -Z
var pose_pivot: Node3D          # extra pivot used by the lying pose
var model: Node3D
var anim: AnimationPlayer
var _anim_name := ""
var _air_time := 0.0
var _last_safe := Vector3.ZERO
var _tween: Tween
var _shape: CollisionShape3D
## Footstep sounds (dB; set very low or disable for background characters).
var footstep_db := -14.0
var footsteps := true
var _stride := 0.0


func _ready() -> void:
	collision_layer = Game.PHYS_CHARACTERS
	collision_mask = Game.PHYS_WORLD | Game.PHYS_PROPS | Game.PHYS_VEHICLES
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(52.0)
	floor_constant_speed = true
	safe_margin = 0.02
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.2
	_shape.shape = cap
	_shape.position.y = 0.6
	add_child(_shape)
	visual = Node3D.new()
	visual.name = "Visual"
	visual.rotation.y = PI
	add_child(visual)
	pose_pivot = Node3D.new()
	pose_pivot.name = "PosePivot"
	visual.add_child(pose_pivot)
	set_look(look)
	_last_safe = global_position
	# A soft blob shadow helps read height when jumping (AC style).
	var blob := Decal.new()
	blob.name = "BlobShadow"
	blob.size = Vector3(0.9, 3.0, 0.9)
	blob.position.y = -0.2
	blob.texture_albedo = _blob_texture()
	blob.modulate = Color(0.2, 0.25, 0.3, 0.35)
	blob.cull_mask = 1
	add_child(blob)


static var _blob_tex: Texture2D

static func _blob_texture() -> Texture2D:
	if _blob_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_blob_tex = gt
	return _blob_tex


func set_look(id: String) -> void:
	look = id
	if model:
		model.queue_free()
	if AvatarLooks.OUTFITS.has(id):
		if outfit == "" or not AvatarLooks.OUTFITS[id].has(outfit):
			outfit = AvatarLooks.OUTFITS[id][0]
		model = Avatar.build(AvatarLooks.look(id, outfit))
	else:
		model = Props.model("mini-characters/" + id)
	model.name = "Model"
	model.scale = Vector3.ONE * Game.CHARACTER_SCALE
	pose_pivot.add_child(model)
	for mi in Props._mesh_instances(model):
		(mi as VisualInstance3D).layers = 2     # keeps the blob shadow decal off the body
	anim = model.find_child("AnimationPlayer", true, false)
	for n in ["idle", "walk", "sprint", "sit", "drive", "static", "fall", "crouch", "holding-both"]:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim_name = ""
	_play("idle", 0.0)


## Cycles outfits (custom avatars) or Kenney looks. Returns a display name.
func next_look() -> String:
	if AvatarLooks.OUTFITS.has(look):
		var list: Array = AvatarLooks.OUTFITS[look]
		set_outfit(list[(list.find(outfit) + 1) % list.size()])
		return AvatarLooks.OUTFIT_NAMES.get(outfit, outfit)
	var i := LOOKS.find(look)
	set_look(LOOKS[(i + 1) % LOOKS.size()])
	return look


func set_outfit(o: String) -> void:
	outfit = o
	var keep_anim := _anim_name
	var pos := anim.current_animation_position if anim and anim.is_playing() else 0.0
	set_look(look)
	if keep_anim != "":
		_anim_name = ""
		_play(keep_anim, 0.0)
		anim.seek(pos, true)


func _play(anim_name: String, blend: float = 0.18, speed: float = 1.0) -> void:
	if anim == null:
		return
	anim.speed_scale = speed
	if anim_name == _anim_name:
		return
	_anim_name = anim_name
	anim.play(anim_name, blend)


## One-shot gesture (e.g. "emote-yes"), then back to the current loop.
func gesture(anim_name: String) -> void:
	if anim == null or not anim.has_animation(anim_name) or pose != "move":
		return
	_anim_name = anim_name
	anim.play(anim_name, 0.15)
	await anim.animation_finished
	_anim_name = ""


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if pose == "transition":
		return
	if pose != "move":
		_follow_anchor()
		return
	var target := Vector3(intent.x, 0, intent.z)
	var speed := run_speed if want_run else walk_speed
	var hv := Vector3(velocity.x, 0, velocity.z)
	var a := accel if is_on_floor() else accel * 0.4
	hv = hv.move_toward(target * speed, a * delta * speed)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		_air_time = 0.0
		if want_jump:
			velocity.y = jump_velocity
			_play("jump", 0.08)
			if footsteps:
				Sound.play("jump", footstep_db + 4.0, randf_range(0.95, 1.05))
	else:
		_air_time += delta
		velocity.y -= gravity * delta
	want_jump = false
	move_and_slide()
	_keep_on_land()
	# Face the movement direction.
	if target.length_squared() > 0.01:
		facing = lerp_angle(facing, atan2(-target.x, -target.z), clampf(turn_speed * delta, 0.0, 1.0))
	rotation.y = facing
	_animate_locomotion(hv.length())
	# Footsteps: one per stride, louder when running.
	if footsteps and is_on_floor():
		_stride += hv.length() * delta
		var stride_len := 0.85 if hv.length() > run_speed * 0.75 else 0.62
		if _stride > stride_len:
			_stride = 0.0
			Sound.footstep(Sound.surface_at(global_position), footstep_db + (2.0 if want_run else 0.0))


func _animate_locomotion(spd: float) -> void:
	if _anim_name.begins_with("emote") or _anim_name.begins_with("interact") or _anim_name == "pick-up":
		if anim.is_playing():
			return
	if not is_on_floor() and _air_time > 0.12:
		_play("jump" if velocity.y > 0.0 else "fall", 0.15)
	elif spd > run_speed * 0.75:
		_play("sprint", 0.2, spd * run_anim_rate)
	elif spd > 0.25:
		_play("walk", 0.2, maxf(spd * walk_anim_rate, 0.5))
	else:
		_play("idle", 0.25)


func _keep_on_land() -> void:
	# No swimming: shallow wading is fine, deeper water pushes you back.
	var t: Terrain = Game.terrain
	if t == null:
		return
	if t.height_at(global_position.x, global_position.z) < -0.45:
		global_position = Vector3(_last_safe.x, global_position.y, _last_safe.z)
		velocity.x = 0.0
		velocity.z = 0.0
	elif is_on_floor():
		_last_safe = global_position


func teleport(pos: Vector3, yaw: float = NAN) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	if not is_nan(yaw):
		facing = yaw
		rotation.y = yaw
	_last_safe = pos
	reset_physics_interpolation()


# ---------------------------------------------------------------------------
# Anchored poses
# ---------------------------------------------------------------------------

## Moves onto an anchor (seat/towel/car seat) and holds a pose.
func enter_anchor(seat: Node3D, new_pose: String, owner_it: Interactable = null, duration: float = 0.35) -> void:
	if pose != "move":
		return
	anchor = seat
	anchor_owner = owner_it
	if owner_it:
		owner_it.occupy(seat, self)
	pose = "transition"
	_shape.disabled = true
	velocity = Vector3.ZERO
	var target := seat.global_transform
	var yaw := target.basis.get_euler().y
	_set_pose_visual(new_pose)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel(true)
	_tween.tween_property(self, "global_position", target.origin, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(y: float) -> void: rotation.y = y; facing = y, rotation.y, rotation.y + wrapf(yaw - rotation.y, -PI, PI), duration)
	await _tween.finished
	pose = new_pose
	if footsteps and new_pose != "drive":
		Sound.play("sit", footstep_db + 2.0, randf_range(0.9, 1.1))
	pose_changed.emit(pose)


func _set_pose_visual(p: String) -> void:
	pose_pivot.position = Vector3.ZERO
	pose_pivot.rotation = Vector3.ZERO
	match p:
		"sit":
			_play("sit", 0.2)
		"drive":
			_play("drive", 0.2)
		"lie":
			# The rest pose with arms spread, laid on its back: a happy sunbather.
			_play("static", 0.25)
			pose_pivot.rotation.x = -PI * 0.5
			pose_pivot.position = Vector3(0, 0.26, 0.62)
		_:
			_play("idle", 0.2)


func _follow_anchor() -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	var xf := anchor.global_transform
	global_position = xf.origin
	rotation.y = xf.basis.get_euler().y
	facing = rotation.y


## Leaves the current anchor, stepping to `exit_pos` (or in front of the seat).
func leave_anchor(exit_pos: Variant = null, duration: float = 0.3) -> void:
	if pose == "move" or pose == "transition" or anchor == null:
		return
	var seat := anchor
	var fwd := -seat.global_transform.basis.z
	fwd.y = 0.0
	var dest: Vector3
	if exit_pos != null:
		dest = exit_pos
	elif pose == "lie":
		dest = seat.global_position + seat.global_transform.basis.x.normalized() * 0.9
	else:
		dest = seat.global_position + fwd.normalized() * 0.75
	if Game.terrain:
		dest.y = Game.terrain.height_at(dest.x, dest.z) + 0.05
		# Standing on props (e.g. the dock): keep the seat's height if it's higher.
		if seat.global_position.y - dest.y > 0.6 and pose != "drive":
			dest.y = seat.global_position.y - 0.4
	pose = "transition"
	if anchor_owner:
		anchor_owner.release(self)
	_set_pose_visual("move")
	if _tween:
		_tween.kill()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "global_position", dest, duration).set_trans(Tween.TRANS_SINE)
	await _tween.finished
	anchor = null
	anchor_owner = null
	_shape.disabled = false
	pose = "move"
	_last_safe = global_position
	pose_changed.emit(pose)


func is_free() -> bool:
	return pose == "move"

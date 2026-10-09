class_name DigSpot
extends Interactable
## A star-shaped crack in the ground with something buried underneath (press E
## to dig). She kneels, dirt flies, and the mineral pops out sparkling.

signal dug(mineral: String)

var mineral := "amethyst"
var _crack: Node3D
var _busy := false


func _ready() -> void:
	kind = "dig"
	prompt = "Dig here"
	radius = 1.7
	super._ready()
	_crack = _build_crack()
	add_child(_crack)


## Dark little cracks radiating from the middle, plus a few crumbs of soil.
func _build_crack() -> Node3D:
	var b := RoundKit.MB.new(1.0, hash(mineral))
	var dark := Color(0.16, 0.11, 0.08)
	for i in 5:
		var a := TAU * i / 5.0 + b.jitter(0.2)
		var l := 0.34 + b.jitter(0.08)
		var d := Vector3(cos(a), 0, sin(a))
		b.rbox(Vector3(0.07, 0.03, l), d * (l * 0.5 + 0.04) + Vector3(0, 0.0, 0), dark, dark, 0.012, Vector3(0, rad_to_deg(atan2(d.x, d.z)), 0), "matte", true)
		# A little fork near the end of each crack.
		var f := d.rotated(Vector3.UP, 0.6 * (1.0 if i % 2 == 0 else -1.0))
		b.rbox(Vector3(0.05, 0.03, 0.13), d * (l * 0.85) + f * 0.06, dark, dark, 0.01, Vector3(0, rad_to_deg(atan2(f.x, f.z)), 0), "matte", true)
	b.blob(Vector3(0, 0.0, 0), Vector3(0.09, 0.025, 0.09), dark, dark, 8, 3)
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		b.blob(Vector3(cos(a), 0, sin(a)) * 0.22, Vector3(0.035, 0.03, 0.035), Color(0.62, 0.47, 0.34), Color(0.5, 0.37, 0.27), 5, 3)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.02
	return mi


func can_use(_by: Node) -> bool:
	return enabled and not _busy


func interact(by: Node) -> void:
	if _busy:
		return
	_busy = true
	enabled = false
	var her := by as Person
	var player := by as Player
	if player:
		player.input_enabled = false
	if her:
		var d := global_position - her.global_position
		d.y = 0.0
		if d.length() > 0.05:
			her.facing = atan2(-d.x, -d.z)
			her.rotation.y = her.facing
		her.hold_pose("crouch")
	# Three digs: dirt flies each time.
	for k in 3:
		Sound.play("step_grass_%d" % k, 0.0, 0.7 + k * 0.08)
		FX.sparkle(get_parent(), global_position + Vector3(0, 0.15, 0), Color(0.55, 0.4, 0.28), 14)
		_crack.scale = Vector3.ONE * (1.0 + 0.15 * (k + 1))
		await get_tree().create_timer(0.35).timeout
	# Out it pops: a little hop, a spin and a sparkle.
	_crack.visible = false
	var hole := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.28
	hm.bottom_radius = 0.22
	hm.height = 0.04
	hole.mesh = hm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.28, 0.2)
	hole.material_override = mat
	hole.position.y = 0.01
	add_child(hole)
	var gem := Minerals.build(mineral)
	add_child(gem)
	gem.position = Vector3(0, 0.05, 0)
	var tw := create_tween()
	tw.tween_property(gem, "position", Vector3(0, 1.1, 0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(gem, "rotation:y", TAU * 1.5, 1.4)
	tw.parallel().tween_property(gem, "scale", Vector3.ONE * 1.6, 0.45)
	Sound.play("levelup", -6.0, 1.15)
	FX.sparkle(get_parent(), global_position + Vector3(0, 1.1, 0), (Minerals.info(mineral)[2] as Color).lightened(0.3), 36)
	Game.rumble(0.3, 0.2, 0.25)
	await get_tree().create_timer(1.3).timeout
	if her:
		her.release_pose()
	if player:
		player.input_enabled = true
	dug.emit(mineral)
	var tw2 := create_tween()
	tw2.tween_property(gem, "scale", Vector3.ONE * 0.01, 0.3)
	await tw2.finished
	gem.queue_free()

class_name ShotDirector
extends Node
## Automated screenshots for visual checks: `godot -- --shots=<dir> [--views=a,b]`
## (or a `res://shots_request.cfg` file with `shots=…` / `views=…` lines).
## Each view sets up the camera and/or game state, waits for the image to
## settle, saves `<dir>/<view>.png`; the game quits at the end.

const VIEWS := {
	"overview": {"pos": Vector3(0, 70, 95), "look": Vector3(0, 0, -5)},
	"plaza": {"pos": Vector3(10, 9, 8), "look": Vector3(0, 2, -12)},
	"beach": {"pos": Vector3(14, 6, 34), "look": Vector3(0, 1, 18)},
	"hill": {"pos": Vector3(40, 14, -20), "look": Vector3(20, 5, -44)},
	"start": {"action": "_act_start"},
	"walk": {"action": "_act_walk"},
	"sit": {"action": "_act_sit"},
	"lie": {"action": "_act_lie"},
	"talk": {"action": "_act_talk"},
	"drive": {"action": "_act_drive"},
	"closeup": {"action": "_act_closeup"},
	"golden": {"action": "_act_golden"},
	"title": {"action": "_act_title"},
	"night": {"action": "_act_night"},
}

var cam: Camera3D
var _log := PackedStringArray()


func log_line(t: String) -> void:
	print(t)
	_log.append(t)


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 50
	cam.far = 1500
	cam.attributes = CameraAttributesPractical.new()   # no far blur for wide shots
	add_child(cam)
	_run.call_deferred()


func _run() -> void:
	var dir: String = Game.options["shots"]
	DirAccess.make_dir_recursive_absolute(dir)
	var names: Array = VIEWS.keys()
	if Game.options.has("views"):
		names = str(Game.options["views"]).split(",")
	if Game.hud:
		Game.hud.help.visible = false
	log_line("[shots] boot %d ms, renderer %s" % [Time.get_ticks_msec(), RenderingServer.get_current_rendering_method()])
	await _frames(10)
	for n in names:
		var v: Dictionary = VIEWS.get(n, {})
		_game_cam()
		if v.has("action"):
			await call(v["action"])
		if v.has("pos"):
			cam.current = true
			cam.global_position = v["pos"]
			cam.look_at(v["look"])
		await _frames(int(Game.options.get("settle", 20)))
		var path: String = dir.path_join(n + ".png")
		Game.save_screenshot(path)
		log_line("[shots] %s  fps=%d" % [path, Engine.get_frames_per_second()])
		await _reset()
	var f := FileAccess.open(dir.path_join("log.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log))
		f.close()
	if FileAccess.file_exists("res://shots_request.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://shots_request.cfg"))
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _game_cam() -> void:
	if Game.camera_rig:
		Game.camera_rig.camera.current = true


func _reset() -> void:
	if _title:
		_title.queue_free()
		_title = null
		Game.player.input_enabled = true
		Game.hud.root.visible = true
	var p: Player = Game.player
	Input.action_release("move_forward")
	Input.action_release("move_left")
	if p.pose == "drive":
		await p.exit_car()
	elif p.pose != "move":
		await p.leave_anchor()
	if Game.hud and Game.hud.is_dialogue_open():
		Game.hud.dialogue.visible = false
		Game.hud.dialogue_closed.emit()
	if Game.atmosphere:
		Game.atmosphere.set_preset(Game.options.get("preset", "day"))
	await _frames(2)


func _place(pos: Vector3, yaw: float, cam_yaw: float, cam_pitch_deg: float = -20.0, dist: float = 7.0) -> void:
	var p: Player = Game.player
	pos.y = Game.terrain.height_at(pos.x, pos.z) + 0.1
	p.teleport(pos, yaw)
	if Game.partner:
		Game.partner.teleport(pos + p.global_transform.basis.x * 1.4 + p.global_transform.basis.z * 0.8, yaw)
	var rig: CameraRig = Game.camera_rig
	rig.yaw = cam_yaw
	rig.pitch = deg_to_rad(cam_pitch_deg)
	rig.distance = dist
	rig.snap()
	await _frames(3)


func _act_start() -> void:
	var c: Chapter = Game.chapters.current
	await _place(c.spawn, c.spawn_yaw, c.spawn_yaw)
	await _frames(30)


func _act_walk() -> void:
	await _place(Vector3(-3, 0, -2), PI, PI * 0.8, -18.0, 6.0)
	Input.action_press("move_forward")
	await _frames(40)


func _nearest(kind: String, near: Vector3) -> Interactable:
	var best: Interactable = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it and it.kind == kind:
			var d := it.global_position.distance_to(near)
			if d < bd:
				bd = d
				best = it
	return best


func _act_sit() -> void:
	var b := _nearest("sit", Vector3(6, 2, 15))
	await _place(b.global_position + b.global_transform.basis.z * 1.2, 0.0, 0.3, -12.0, 5.5)
	Game.player.use(b)
	await _frames(90)
	Game.camera_rig.yaw = PI - 0.5
	await _frames(20)


func _act_lie() -> void:
	var t := _nearest("lie", Vector3(-10, 1, 29))
	await _place(t.global_position + Vector3(1.5, 0, 0), 0.0, PI * 0.75, -35.0, 6.0)
	Game.player.use(t)
	await _frames(150)
	Game.camera_rig.yaw = PI * 0.5
	Game.camera_rig.pitch = deg_to_rad(-38.0)
	Game.camera_rig.distance = 4.5


func _act_talk() -> void:
	var v: Node3D = get_tree().current_scene.get_node("Villager_Mochi")
	var pos := v.global_position + Vector3(0, 0, 1.6)
	await _place(pos, 0.0, 0.25, -14.0, 5.0)
	var it: Interactable = v.interactable
	Game.player.use(it)
	await _frames(70)


func _act_drive() -> void:
	var car: Car = get_tree().current_scene.get_node("Car")
	await _place(car.global_position + car.global_transform.basis.x * 2.4, 0.0, PI * 0.6, -18.0, 9.0)
	await Game.player.enter_car(car)
	Input.action_press("move_forward")
	await _frames(150)
	Input.action_press("move_left")
	await _frames(40)
	log_line("[shots] car speed %.1f km/h at %s" % [car.speed_kmh(), car.global_position])


func _act_closeup() -> void:
	await _place(Vector3(-8, 0, 25.5), 0.4, 2.6, -10.0, 3.6)
	await _frames(20)


func _act_golden() -> void:
	Game.atmosphere.set_preset("golden")
	await _place(Vector3(6, 0, -48), PI * 0.95, PI * 0.95, -12.0, 9.0)


func _act_night() -> void:
	Game.atmosphere.set_preset("night")
	await _place(Vector3(3, 0, -1), 0.0, 0.2, -16.0, 11.0)


func _act_title() -> void:
	var t := TitleScreen.new()
	get_tree().current_scene.add_child(t)
	await _frames(40)
	await get_tree().process_frame
	_title = t


var _title: TitleScreen = null

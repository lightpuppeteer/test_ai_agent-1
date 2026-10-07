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
	"startfar": {"action": "_act_start", "pos": Vector3(14, 10, 30), "look": Vector3(2, 2, 13)},
	"walk": {"action": "_act_walk"},
	"sit": {"action": "_act_sit"},
	"lie": {"action": "_act_lie"},
	"talk": {"action": "_act_talk"},
	"drive": {"action": "_act_drive"},
	"closeup": {"action": "_act_closeup"},
	"golden": {"action": "_act_golden"},
	"title": {"action": "_act_title"},
	"her": {"action": "_act_her"},
	"pizza": {"action": "_act_pizza"},
	"choices": {"action": "_act_choices"},
	"cinema": {"action": "_act_cinema"},
	"spa": {"action": "_act_spa"},
	"house": {"action": "_act_house"},
	"garden": {"action": "_act_garden"},
	"oasis": {"action": "_act_oasis"},
	"causeway": {"action": "_act_causeway"},
	"fireworks": {"action": "_act_fireworks"},
	"carkiss": {"action": "_act_carkiss"},
	"night": {"action": "_act_night"},
	"cats": {"action": "_act_cats"},
	"villagers": {"action": "_act_villagers"},
	"perf": {"action": "_act_perf"},
	"tpbench": {"action": "_act_tpbench"},
	"navdump": {"action": "_act_navdump"},
	"spatest": {"action": "_act_spatest"},
	"profile": {"action": "_act_profile"},
	"board": {"pos": Vector3(-2.0, 2.4, -6.8), "look": Vector3(-8.1, 1.7, -2.9)},
	"sign_pizza": {"pos": Vector3(-26.5, 3.6, -12.5), "look": Vector3(-28, 3.2, -3)},
	"sign_cinema": {"pos": Vector3(29.5, 3.4, -12.5), "look": Vector3(28, 2.8, -3)},
	"sign_hotel": {"pos": Vector3(-42, 4.0, -13), "look": Vector3(-52, 3.6, -15)},
	"sign_garden": {"pos": Vector3(44.5, 2.6, -13.5), "look": Vector3(51.3, 2.8, -15)},
	"sign_house": {"pos": Vector3(32.5, 2.6, -13), "look": Vector3(30.4, 1.2, -17.5)},
	"sign_her": {"pos": Vector3(-23.0, 2.2, -14.0), "look": Vector3(-24.5, 1.2, -18)},
	"sign_oasis": {"action": "_act_sign_oasis"},
	"yoggihouse": {"action": "_act_yoggihouse"},
	"cwdrive": {"action": "_act_cwdrive"},
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
		_log_arm()
		await _reset()
	var f := FileAccess.open(dir.path_join("log.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log))
		f.close()
	if FileAccess.file_exists("res://shots_request.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://shots_request.cfg"))
	get_tree().quit()


func _log_arm() -> void:
	var rig: CameraRig = Game.camera_rig
	if rig == null:
		return
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = rig.arm.shape
	q.collision_mask = rig.arm.collision_mask
	q.transform = Transform3D(Basis(), rig.global_position)
	var hits := rig.get_world_3d().direct_space_state.intersect_shape(q, 8)
	var names := PackedStringArray()
	for h in hits:
		var col: Object = h["collider"]
		names.append(str((col as Node).get_path()) if col is Node else str(col))
	var vc := get_viewport().get_camera_3d()
	log_line("[cam] %s at %s fwd %s near %.2f" % [vc.get_path(), vc.global_position, -vc.global_transform.basis.z, vc.near])
	log_line("[arm] len=%.2f hit=%.2f dist=%.2f at=%s start_hits=%s" % [rig.arm.spring_length, rig.arm.get_hit_length(), rig.distance, rig.global_position, ",".join(names)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _game_cam() -> void:
	if Game.camera_rig:
		Game.camera_rig.camera.current = true


func _reset_story() -> void:
	Game.story_lock = false
	if Game.hud._choices_shown or Game.hud.is_dialogue_open():
		Game.hud._pending_choices = []
		Game.hud._choices_shown = false
		Game.hud.choice_box.visible = false
		Game.hud.dialogue.visible = false
	if Game.location != "outside":
		await Places.travel(QuestData.LANDMARKS["spawn"], PI, "outside")
	Cutscene._fireworks_on = false
	Game.camera_rig.end_cinematic()
	for acc in ["cucumbers", "popcorn", "pepperoni", "yoggi"]:
		Game.player.set_accessory(acc, false)
		Game.partner.set_accessory(acc, false)
	Game.player.release_pose()
	Game.partner.release_pose()
	if Game.partner.pose != "move" and Game.partner.pose != "transition":
		await Game.partner.leave_anchor()


func _reset() -> void:
	await _reset_story()
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


func _perf_sample(label: String, frames: int = 90) -> void:
	var worst := 0.0
	var total := 0.0
	for i in frames:
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, dt)
		total += dt
	var rs := RenderingServer
	log_line("[perf] %-14s avg %.1f ms  worst %.1f ms  draws %d  objs %d  prims %dk  fps %d" % [label, total / frames, worst,
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		Engine.get_frames_per_second()])


## Frame-time numbers at a few spots, plus the hitch when walking into a room.
func _act_perf() -> void:
	var counts := {}
	var big := []
	for cs in get_tree().root.find_children("*", "CollisionShape3D", true, false):
		var sh: Shape3D = (cs as CollisionShape3D).shape
		var k := sh.get_class() if sh else "null"
		counts[k] = counts.get(k, 0) + 1
		if sh is ConcavePolygonShape3D:
			big.append([(sh as ConcavePolygonShape3D).get_faces().size() / 3, str(cs.get_path())])
		elif sh is HeightMapShape3D:
			big.append([(sh as HeightMapShape3D).map_width * (sh as HeightMapShape3D).map_depth, str(cs.get_path())])
	big.sort_custom(func(a, b): return a[0] > b[0])
	log_line("[shapes] %s, %d bodies" % [counts, get_tree().root.find_children("*", "CollisionObject3D", true, false).size()])
	for b in big.slice(0, 8):
		log_line("[shapes]   %s" % [b])
	for nm in str(Game.options.get("perf_off", "")).split(",", false):
		for n in get_tree().root.find_children("*", "", true, false):
			if n.name.begins_with(nm) or n.get_class() == nm or (n.get_script() and str(n.get_script().get_global_name()) == nm):
				n.set_physics_process(false)
				n.set_process(false)
				print("[tt] off ", n.name)
	await _place(Vector3(0, 0, -2), PI, PI, -28.0, 10.0)
	await _perf_sample("plaza")
	await _place(Vector3(-6, 0, 26), PI, PI, -28.0, 10.0)
	await _perf_sample("beach")
	await _place(Vector3(30, 0, -30), 0.0, 0.0, -28.0, 10.0)
	await _perf_sample("east")
	for room in ["pizza", "cinema", "house", "hotel"]:
		var it: Interior = Places.interiors[room]
		var worst := [0.0]
		var on_frame := func() -> void: pass
		var t_last := [Time.get_ticks_usec()]
		var mon := func() -> void:
			var now := Time.get_ticks_usec()
			worst[0] = maxf(worst[0], (now - t_last[0]) / 1000.0)
			if (now - t_last[0]) > 30000:
				print("[tt] SLOW frame %.1f ms at %d  process %.1f physics %.1f" % [(now - t_last[0]) / 1000.0, Time.get_ticks_msec(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
			t_last[0] = now
		get_tree().process_frame.connect(mon)
		await Places.travel(it.global_position + it.spawn, 0.0, room)
		await _frames(30)
		get_tree().process_frame.disconnect(mon)
		log_line("[perf] enter %-8s worst frame %.1f ms" % [room, worst[0]])
		await _perf_sample("in " + room)
		await Places.travel(QuestData.LANDMARKS["spawn"], PI, "outside")
		await _frames(10)


## Height profile + knee-height blockers along a few paths (pier, causeway ends).
func _act_profile() -> void:
	await _frames(5)
	var space := get_viewport().get_world_3d().direct_space_state
	var dir := (Places.CAUSEWAY_TO - Places.CAUSEWAY_FROM)
	dir.y = 0.0
	dir = dir.normalized()
	var lines := {
		"pier": [Vector3(34, 0, 21), Vector3(34, 0, 34)],
		"cw_start": [Places.CAUSEWAY_FROM - dir * 9.0, Places.CAUSEWAY_FROM + dir * 6.0],
		"cw_end": [Places.CAUSEWAY_TO - dir * 6.0, Places.CAUSEWAY_TO + dir * 10.0],
	}
	for nm in lines:
		var a: Vector3 = lines[nm][0]
		var b: Vector3 = lines[nm][1]
		var steps := int(a.distance_to(b) / 0.25)
		var out := PackedStringArray()
		var prev_h := NAN
		for i in steps + 1:
			var p := a.lerp(b, float(i) / steps)
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 30, p.z), Vector3(p.x, -10, p.z), Game.PHYS_WORLD | Game.PHYS_PROPS)
			var hit := space.intersect_ray(q)
			var h: float = hit["position"].y if not hit.is_empty() else -99.0
			var who: String = str((hit["collider"] as Node).name) if not hit.is_empty() else "-"
			if is_nan(prev_h) or absf(h - prev_h) > 0.12 or i == steps:
				out.append("%.2f:%.2f(%s)" % [float(i) * 0.25, h, who])
			prev_h = h
		log_line("[profile] %s %s" % [nm, " ".join(out)])
		# Blockers at knee height just above the walking surface.
		var blk := PackedStringArray()
		for i in steps:
			var p0 := a.lerp(b, float(i) / steps)
			var p1 := a.lerp(b, float(i + 1) / steps)
			var q0 := PhysicsRayQueryParameters3D.create(Vector3(p0.x, 30, p0.z), Vector3(p0.x, -10, p0.z), Game.PHYS_WORLD | Game.PHYS_PROPS)
			var hit0 := space.intersect_ray(q0)
			if hit0.is_empty():
				continue
			var y: float = hit0["position"].y + 0.6
			var q := PhysicsRayQueryParameters3D.create(Vector3(p0.x, y, p0.z), Vector3(p1.x, y, p1.z), Game.PHYS_WORLD | Game.PHYS_PROPS | Game.PHYS_WALLS)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				blk.append("%.2f:%s" % [float(i) * 0.25, (hit["collider"] as Node).get_path()])
		log_line("[profile] %s blockers: %s" % [nm, " ".join(blk)])


func _act_sign_oasis() -> void:
	var d := Places.CAUSEWAY_TO - Places.CAUSEWAY_FROM
	d.y = 0
	d = d.normalized()
	var side := Vector3(d.z, 0, -d.x)
	cam.current = true
	cam.global_position = Places.CAUSEWAY_FROM - d * 9.0 + side * 2.0 + Vector3(0, 3.2, 0)
	cam.look_at(Places.CAUSEWAY_FROM - d * 2.0 + Vector3(0, 1.5, 0) + side * -3.0)


func _act_yoggihouse() -> void:
	while NavBaker.ready_count < 1 + Places.interiors.size():
		await get_tree().process_frame
	var it := await _inside("house")
	Game.world.decor.load_from([
		{"item": "sofa", "x": -3.0, "z": 3.4, "yaw": PI}, {"item": "tv", "x": -3.0, "z": 0.0, "yaw": 0.0},
		{"item": "rug", "x": -3.0, "z": 1.8, "yaw": 0.0}, {"item": "plant", "x": -7.0, "z": 5.0, "yaw": 0.0},
		{"item": "lamp", "x": -6.5, "z": 1.0, "yaw": 0.0},
	])
	await get_tree().create_timer(0.5).timeout
	var y: Yoggi = Places.spot("yoggi")
	y.settle_home(it.to_global(Vector3(2.5, 0.1, 2.0)))
	Game.player.teleport(it.global_position + Vector3(0.0, 0.1, 4.5), PI * 0.25)
	Game.camera_rig.yaw = 0.3
	Game.camera_rig.pitch = deg_to_rad(-38.0)
	Game.camera_rig.distance = 8.0
	for i in 12:
		await get_tree().create_timer(0.5).timeout
	log_line("[yoggi] mode=%s on_spot=%s at %s" % [y._mode, y._on_spot, y.global_position - it.global_position])
	Game.camera_rig.cinematic(y.global_position + Vector3(0, 0.4, 0), 0.3, -25.0, 3.2)
	await get_tree().create_timer(1.6).timeout


func _act_cwdrive() -> void:
	var car: Car = get_tree().current_scene.get_node("Car")
	var d := Places.CAUSEWAY_TO - Places.CAUSEWAY_FROM
	d.y = 0
	d = d.normalized()
	var start := Places.CAUSEWAY_FROM - d * 10.0
	start.y = Game.terrain.height_at(start.x, start.z) + 0.8
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), start)
	car.linear_velocity = Vector3.ZERO
	await _frames(10)
	await _place(start + Vector3(d.z, 0, -d.x) * 2.4, 0.0, 0.0, -18.0, 9.0)
	await Game.player.enter_car(car)
	Input.action_press("move_forward")
	for i in 14:
		await get_tree().create_timer(1.0).timeout
		log_line("[drive] t=%d car at %s speed %.1f" % [i, car.global_position, car.speed_kmh()])
	Input.action_release("move_forward")
	log_line("[drive] distance to oasis end %.1f" % car.global_position.distance_to(Places.CAUSEWAY_TO))


func _act_spatest() -> void:
	while NavBaker.ready_count < 1 + Places.interiors.size():
		await get_tree().process_frame
	var it: Interior = Places.interiors["hotel"]
	await Places.travel(it.global_position + it.spawn, 0.0, "hotel")
	await _frames(20)
	var bed: Interactable = Places.spot("spa_bed")
	Game.player.teleport(bed.global_position + Vector3(0.5, 0.1, 0.8))
	await _frames(5)
	Game.player.use(bed)
	for i in 10:
		await get_tree().create_timer(1.0).timeout
		log_line("[spa] t=%d her=%s %s  him=%s %s" % [i, Game.player.pose, Game.player.global_position - it.global_position, Game.partner.pose, Game.partner.global_position - it.global_position])
	await Game.player.leave_anchor()
	await _frames(30)
	log_line("[spa] after get-up her=%s %s" % [Game.player.pose, Game.player.global_position - it.global_position])
	Game.player.intent = Vector3(0, 0, 1)
	await get_tree().create_timer(1.0).timeout
	Game.player.intent = Vector3.ZERO
	log_line("[spa] after walking her=%s %s" % [Game.player.pose, Game.player.global_position - it.global_position])


func _act_navdump() -> void:
	while NavBaker.ready_count < 1 + Places.interiors.size():
		await get_tree().process_frame
	var nm: NavigationMesh = NavBaker.regions["island"].navigation_mesh
	var out := {"v": [], "p": []}
	for v in nm.get_vertices():
		out["v"].append([v.x, v.y, v.z])
	for i in nm.get_polygon_count():
		out["p"].append(Array(nm.get_polygon(i)))
	var f := FileAccess.open(str(Game.options["shots"]).path_join("nav.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()


func _act_tpbench() -> void:
	var it: Interior = Places.interiors["pizza"]
	var base := it.global_position + it.spawn
	var mask := int(Game.options.get("pmask", "-1"))
	if Game.options.has("noarea"):
		(Game.partner as Partner).interactable.free()
		print("[tt] removed partner area")
	if mask >= 0:
		Game.partner.collision_mask = mask
		print("[tt] partner mask ", mask)
	var only := str(Game.options.get("only", ""))
	if only == "partner":
		Game.story_lock = true
	for k in 3:
		print("[tt] -- in")
		if only != "partner":
			Game.player.teleport(base, 0.0)
		if only != "player":
			Game.partner.teleport(base + Vector3(1.2, 0, 0.6), 0.0)
		for j in 6:
			await get_tree().physics_frame
		print("[tt] -- out")
		if only != "partner":
			Game.player.teleport(Vector3(2, 2.1, 13.4), 0.0)
		if only != "player":
			Game.partner.teleport(Vector3(3.2, 2.1, 14.0), 0.0)
		for j in 6:
			await get_tree().physics_frame


func _act_villagers() -> void:
	var vs := get_tree().get_nodes_in_group("villagers")
	var i := 0
	for v in vs:
		var vn := v as Villager
		vn.set_physics_process(false)
		var x := -3.75 + i * 1.5
		vn.global_position = Vector3(x, Game.terrain.height_at(x, 4.0) + 0.05, 4.0)
		vn.rotation.y = PI
		vn._facing = PI
		vn._play("idle")
		i += 1
	Game.player.teleport(Vector3(6, 2.2, 2))
	Game.partner.teleport(Vector3(7, 2.2, 2))
	cam.current = true
	cam.global_position = Vector3(0, 3.6, 9.6)
	cam.look_at(Vector3(0, 2.6, 4.0))
	await _frames(20)


func _act_cats() -> void:
	var y: Node3D = Places.spot("yoggi") if Places.spot("yoggi") else null
	if y == null:
		for n in get_tree().root.find_children("*", "Yoggi", true, false):
			y = n
	var mochi: Node3D = get_tree().current_scene.get_node("Villager_Mochi")
	mochi.set_physics_process(false)
	mochi.global_position = y.global_position + Vector3(1.6, 0, 0)
	await _place(y.global_position + Vector3(0.8, 0, 3.2), PI, 0.0, -14.0, 4.5)
	Game.camera_rig.yaw = 0.0
	await _frames(20)


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


func _inside(place: String) -> Interior:
	var it: Interior = Places.interiors[place]
	await Places.travel(it.global_position + it.spawn, 0.0, place)
	await _frames(5)
	return it


func _sit_both(it: Interactable) -> void:
	var p: Player = Game.player
	p.teleport(it.global_position + Vector3(0.5, 0.2, 0.8))
	Game.partner.teleport(it.global_position + Vector3(-0.5, 0.2, 0.8))
	await _frames(3)
	p.use(it)
	await _frames(90)


func _act_her() -> void:
	await _place(Vector3(2, 0, 13.4), PI, 0.0, -6.0, 3.0)
	Game.player.set_outfit("silver_dress")
	Game.camera_rig.yaw = 0.0
	await _frames(20)


func _act_pizza() -> void:
	await _inside("pizza")
	await _sit_both(Places.spot("pizza_table"))
	Game.player.set_accessory("popcorn", false)
	Game.partner.set_accessory("pepperoni", true)
	Game.camera_rig.yaw = PI * 0.5
	Game.camera_rig.pitch = deg_to_rad(-25.0)
	Game.camera_rig.distance = 5.0


func _act_choices() -> void:
	await _inside("pizza")
	await _sit_both(Places.spot("pizza_table"))
	Game.camera_rig.yaw = 0.0
	Game.camera_rig.pitch = deg_to_rad(-25.0)
	Game.camera_rig.distance = 7.0
	Dialogue.run(StoryData.TREES["pizza"])
	await _frames(160)
	Game.hud._advance()
	await _frames(10)


func _act_cinema() -> void:
	await _inside("cinema")
	Game.player.set_accessory("popcorn", true)
	Game.partner.set_accessory("drink", true)
	await _sit_both(Places.spot("cinema_seats"))
	Game.world.cinema_screen.play("comedy")
	Game.camera_rig.yaw = 0.0
	Game.camera_rig.pitch = deg_to_rad(-12.0)
	Game.camera_rig.distance = 6.0
	await _frames(60)
	var img: Image = Game.world.cinema_screen._vp.get_texture().get_image()
	if img:
		img.save_png(str(Game.options["shots"]).path_join("cinema_vp.png"))
		log_line("[cinema] viewport %s" % [img.get_size()])


func _act_spa() -> void:
	await _inside("hotel")
	await _sit_both(Places.spot("spa_bed"))
	Cutscene.run("cucumbers")
	Game.camera_rig.yaw = 0.0
	Game.camera_rig.pitch = deg_to_rad(-45.0)
	Game.camera_rig.distance = 6.0
	await _frames(30)


func _act_house() -> void:
	var it := await _inside("house")
	Game.world.decor.load_from([
		{"item": "sofa", "x": -3.0, "z": 3.4, "yaw": PI}, {"item": "tv", "x": -3.0, "z": 0.0, "yaw": 0.0},
		{"item": "rug", "x": -3.0, "z": 1.8, "yaw": 0.0}, {"item": "plant", "x": -7.0, "z": 5.0, "yaw": 0.0},
		{"item": "armchair", "x": -0.5, "z": 2.0, "yaw": -PI * 0.5}, {"item": "coffee_table", "x": -3.0, "z": 1.8, "yaw": 0.0},
		{"item": "lamp", "x": -6.5, "z": 1.0, "yaw": 0.0}, {"item": "teddy", "x": -1.0, "z": 4.6, "yaw": 0.0},
	])
	Game.world.decor.begin()
	Game.player.teleport(it.global_position + Vector3(1.0, 0.1, 4.0), PI * 0.25)
	Game.camera_rig.yaw = PI * 0.15
	Game.camera_rig.pitch = deg_to_rad(-40.0)
	Game.camera_rig.distance = 9.0
	await _frames(40)


func _act_garden() -> void:
	var c: Node3D = Places.spot("picnic")
	await _place(c.global_position + Vector3(-2.0, 0, 2.0), 0.0, -PI * 0.6, -30.0, 8.0)
	Cutscene.run("feast")
	await _sit_both(Places.spot("picnic_blanket"))
	await _frames(20)


func _act_oasis() -> void:
	var ch: Node3D = Places.spot("oasis_chest")
	var to_road := Places.CAUSEWAY_TO - ch.global_position
	to_road.y = 0.0
	await _place(ch.global_position + to_road.normalized() * 1.6, atan2(to_road.x, to_road.z) + PI, 0.0, -10.0, 8.0)
	Cutscene.run("face")
	Cutscene.run("kneel")
	Game.world.volcano.erupt(12.0)
	Cutscene.run("cam:volcano")
	await _frames(150)


func _act_causeway() -> void:
	await _place(Places.CAUSEWAY_FROM + Vector3(-3, 0, -3), PI * 0.8, PI * 0.8, -12.0, 9.0)
	await _frames(30)


func _act_fireworks() -> void:
	Game.atmosphere.set_preset("night")
	await _place(Vector3(0, 0, 24), PI * 0.5, PI, 8.0, 7.0)
	Cutscene.run("fireworks")
	Cutscene.run("cam:sky")
	await _frames(150)


func _act_carkiss() -> void:
	var car: Car = get_tree().current_scene.get_node("Car")
	await _place(car.global_position + car.global_transform.basis.x * 2.4, 0.0, PI * 0.6, -18.0, 9.0)
	await Game.player.enter_car(car)
	await _frames(200)
	Cutscene.run("kiss")
	Game.camera_rig.distance = 5.0
	await _frames(30)

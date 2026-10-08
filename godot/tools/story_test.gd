extends Node
## Headless test: plays every story quest end to end (teleporting around and
## auto-answering conversations), then checks the free-roam ending.

var _log := []
var _choice_pick := 0


func _ready() -> void:
	Engine.time_scale = 4.0
	await get_tree().create_timer(1.0).timeout
	var qm: QuestManager = Game.quests
	var guard := 0
	while guard < 400:
		guard += 1
		if qm.flags.get("all_done", false):
			print("[story] all done -> free roam OK (active: ", qm.active_ids(), ")")
			break
		var act: Array = qm.active_ids().filter(func(i): return i != "shells_for_pip")
		var w := 0.0
		while act.is_empty() and w < 20.0:
			await get_tree().create_timer(0.25).timeout
			w += 0.25
			act = qm.active_ids().filter(func(i): return i != "shells_for_pip")
		if act.is_empty():
			break
		var id: String = act[0]
		var s: Dictionary = qm.current_step(id)
		var before := "%s#%d" % [id, qm.states[id]["step"]]
		print("[story] ", before, " ", s.get("type"), " ", s.get("text", s.get("tree", "")))
		await _do_step(qm, id, s)
		# Wait until the step changes (or time out).
		var t := 0.0
		while t < 40.0 and qm.status(id) == "active" and "%s#%d" % [id, qm.states[id]["step"]] == before:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		if t >= 40.0:
			print("[story] STUCK at ", before, " pose=", Game.player.pose, " partner=", Game.partner.pose, " loc=", Game.location)
			break
	print("[story] done. states: ", qm.states, " flags: ", qm.flags.keys())
	print("[story] ring=", Game.player.has_accessory("ring"), " decor=", Game.world.decor.placed.size())
	get_tree().quit()


func _process(_d: float) -> void:
	var hud: HUD = Game.hud
	if hud and hud.is_dialogue_open():
		if hud._choices_shown:
			hud._select_choice(_choice_pick % hud._pending_choices.size())
			_choice_pick += 1
			hud._confirm_choice()
		else:
			hud._advance()


func _tp(pos: Vector3) -> void:
	var p: Player = Game.player
	if p.pose != "move":
		await p.leave_anchor()
	if Game.terrain and Game.location == "outside":
		pos.y = maxf(pos.y, Game.terrain.height_at(pos.x, pos.z) + 0.2)
	p.teleport(pos)
	if not (Game.partner as Partner).waiting:
		Game.partner.teleport(pos + Vector3(1.2, 0, 0.5))
	await get_tree().create_timer(0.3).timeout


func _interactable(tag: String) -> Interactable:
	var sp = Places.spot(tag)
	if sp is Interactable:
		return sp
	for n in get_tree().get_nodes_in_group("interactable"):
		if (n as Interactable).tag == tag:
			return n
	return null


func _do_step(qm: QuestManager, id: String, s: Dictionary) -> void:
	var p: Player = Game.player
	match s.get("type", ""):
		"talk":
			await _tp(Game.partner.global_position + Vector3(0, 0, 1.2))
			Game.partner.interactable.interact(p)
		"meet":
			if Game.location != "outside":
				await Places.travel(QuestData.LANDMARKS["spawn"], 0.0, "outside")
			if p.pose != "move":
				await p.leave_anchor()
			var w := 0.0
			while not qm._meet.get(id, {}).get("armed", false) and w < 15.0:
				await get_tree().create_timer(0.25).timeout
				w += 0.25
			var him := Game.partner as Partner
			print("[story]   meet armed=", qm._meet.get(id, {}).get("armed", false), " wait spot ", him._wait_pos)
			him._pop_to_wait_spot()
			await get_tree().create_timer(0.3).timeout
			await _tp(him.global_position + Vector3(1.5, 0, 0.0))
		"go":
			var t: Vector3 = qm._target(s["to"])
			if Game.location != "outside":
				await Places.travel(QuestData.LANDMARKS["spawn"], 0.0, "outside")
			await _tp(t + Vector3(0.5, 0, 0.5))
		"enter":
			var it: Interior = Places.interiors[s["place"]]
			await Places.travel(it.global_position + it.spawn, 0.0, s["place"])
		"sit_together", "lie_together":
			var it: Interactable = null
			if s.has("tag"):
				it = _interactable(s["tag"])
			else:
				var at: Vector3 = qm._target(s["at"])
				var kind := "sit" if s["type"] == "sit_together" else "lie"
				var bd := INF
				for n in get_tree().get_nodes_in_group("interactable"):
					var x := n as Interactable
					if x.kind == kind and x.global_position.distance_to(at) < bd:
						bd = x.global_position.distance_to(at)
						it = x
			await _tp(it.global_position + Vector3(0.6, 0.2, 0.6))
			p.use(it)
		"car_together":
			var car: Car = get_tree().current_scene.get_node("Main/Car")
			await _tp(car.global_position + car.global_transform.basis.x * 2.5)
			await p.enter_car(car)
		"use":
			var it := _interactable(s["tag"])
			await _tp(it.global_position + Vector3(0.6, 0.0, 0.6))
			p.use(it)
		"decorate":
			var d: DecorSystem = Game.world.decor
			d.load_from([
				{"item": "sofa", "x": -3.0, "z": 3.0, "yaw": 0.0}, {"item": "tv", "x": -3.0, "z": 0.2, "yaw": PI},
				{"item": "rug", "x": -3.0, "z": 1.6, "yaw": 0.0}, {"item": "plant", "x": -6.5, "z": 4.5, "yaw": 0.0},
				{"item": "bed", "x": -4.0, "z": -3.5, "yaw": 0.0}, {"item": "nightstand", "x": -6.5, "z": -4.5, "yaw": 0.0},
				{"item": "lamp", "x": -1.5, "z": -5.0, "yaw": 0.0}, {"item": "wardrobe", "x": -7.0, "z": -2.0, "yaw": 0.0},
				{"item": "desk", "x": 4.0, "z": -5.0, "yaw": 0.0}, {"item": "desk_chair", "x": 4.0, "z": -4.0, "yaw": 0.0},
				{"item": "bookshelf", "x": 7.0, "z": -3.0, "yaw": 0.0},
			])
		"catch":
			var y: Yoggi = Places.spot("yoggi")
			for i in 8:
				await _tp(y.global_position + Vector3(0.8, 0, 0.8))
				y.interactable.interact(p)
				await get_tree().create_timer(0.8).timeout
				if p.has_accessory("yoggi"):
					break
		"time":
			pass
		"dialogue", "wait", "memory":
			pass


func _exit_tree() -> void:
	Engine.time_scale = 1.0

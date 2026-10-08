class_name QuestManager
extends Node
## Runs the quests from QuestData: starts them (from a villager, from him or on
## their own), checks each step, runs conversations, places pick-ups and the
## floating heart marker, and saves progress to user://save.json.
## "meet" steps send him ahead to wait for her somewhere (with a little text
## message); finishing the last quest leaves the whole island free to wander.

signal quest_started(id: String)
signal quest_advanced(id: String, step: int)
signal quest_completed(id: String)
signal changed

const SAVE_PATH := "user://save.json"
## Bumped whenever quest steps change shape, so old saves restart those quests' steps.
const SAVE_VERSION := 2

## id -> {"status": "active" | "done", "step": int}
var states := {}
var inventory := {}
var quests := {}            # id -> quest dictionary
var tracked := ""           # the quest shown in the tracker
## Things that stay true across New Game+: ring, yoggi_home, decor, ng_plus…
var flags := {}
var _pickups := {}          # quest id -> Array[Pickup]
var _step_started := {}     # quest id -> step index already "entered"
var _wait_until := {}       # quest id -> time
var _used := {}             # tags used since their step started
var _busy := false          # a quest conversation is running
var _meet := {}             # quest id -> {"t": entered at, "armed": bool}
var _marker: Node3D
var _marker_label: Label3D


func _ready() -> void:
	Game.quests = self
	for q in QuestData.QUESTS:
		quests[q["id"]] = q
	if Game.options.has("reset_save"):
		_delete_save()
	if not Game.options.has("shots"):
		_load()
	_build_marker()
	Game.photo_taken.connect(_on_photo)
	_apply_flags.call_deferred()
	_autostart.call_deferred()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func status(id: String) -> String:
	return states.get(id, {}).get("status", "")


func active_ids() -> Array:
	var out := []
	for q in QuestData.QUESTS:
		if status(q["id"]) == "active":
			out.append(q["id"])
	return out


func current_step(id: String) -> Dictionary:
	if not states.has(id):
		return {}
	var q: Dictionary = quests[id]
	var i: int = states[id]["step"]
	return q["steps"][i] if i < q["steps"].size() else {}


func step_progress(id: String) -> String:
	var s := current_step(id)
	match s.get("type", ""):
		"collect":
			return "%d/%d" % [mini(inventory.get(s["item"], 0), s.get("count", 1)), s.get("count", 1)]
		"decorate":
			var d: DecorSystem = Game.world.decor if Game.world else null
			if d:
				var n := 0
				for rid in DecorSystem.REQUIRED:
					n += 1 if d.room_done(rid) else 0
				return "%d/3 rooms" % n
	return ""


func start(id: String) -> void:
	if status(id) != "":
		return
	states[id] = {"status": "active", "step": 0}
	tracked = id
	quest_started.emit(id)
	if Game.hud:
		Game.hud.toast("✿ New quest: " + quests[id]["title"])
	Sound.play_ui("quest_start")
	_save()
	changed.emit()


## Interactables with a tag report here when used.
func on_use(tag: String) -> void:
	_used[tag] = true


## Called by villagers and the partner when you talk to them.
## Returns true when a quest took over the conversation.
func handle_talk(who: String, color: Color = Color(0.98, 0.62, 0.45)) -> bool:
	if _busy:
		return true
	for id in active_ids():
		var s := current_step(id)
		match s.get("type", ""):
			"meet":
				if who == "partner" and _meet.get(id, {}).get("armed", false):
					await _meet_talk(id, s)
					return true
			"talk":
				if s.get("who", "") == who:
					await _say(_speaker(who), s.get("lines", ["…"]), color)
					_advance(id)
					return true
			"deliver":
				if s.get("to", "") == who:
					var need: int = s.get("count", _collect_count(id, s["item"]))
					if inventory.get(s["item"], 0) >= need:
						inventory[s["item"]] = inventory.get(s["item"], 0) - need
						await _say(_speaker(who), s.get("lines", ["Thank you!"]), color)
						_advance(id)
						return true
	for q in QuestData.QUESTS:
		if q.get("giver", "") == who and status(q["id"]) == "" and _unlocked(q):
			await _say(_speaker(who), q.get("intro", ["I have a favour to ask..."]), color)
			start(q["id"])
			return true
	return false


# ---------------------------------------------------------------------------
# Step logic
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var p: Player = Game.player
	if p == null:
		return
	for id in active_ids():
		var s := current_step(id)
		if s.is_empty():
			_complete(id)
			continue
		var idx: int = states[id]["step"]
		if _step_started.get(id, -1) != idx:
			_step_started[id] = idx
			_enter_step(id, s)
		if _busy:
			continue
		if _check(id, s):
			_advance(id)
	_update_marker()


func _enter_step(id: String, s: Dictionary) -> void:
	match s.get("type", ""):
		"collect":
			_spawn_pickups(id, s)
		"use":
			_used.erase(s.get("tag", ""))
		"catch":
			var y: Yoggi = Places.spot("yoggi")
			if y and not Game.player.has_accessory("yoggi"):
				if y.state == "house":
					# New Game+: he wanders back to her garden for the replay.
					y.state = "home"
					y.global_position = Places.spot("her_place").global_position + Vector3(2, 0.3, 1)
				y.start_chase()
		"time":
			if Game.atmosphere and Game.atmosphere.current != s["preset"]:
				if s.get("auto", false):
					await get_tree().create_timer(1.5).timeout
					Game.atmosphere.set_preset(s["preset"], 5.0)
				elif Game.hud:
					Game.hud.toast("Press %s to change the time of day" % ("▲" if Game.gamepad_active else "T"))
		"memory":
			_busy = true
			await _say(s.get("title", ""), s.get("lines", []), Color(0.95, 0.55, 0.62))
			_busy = false
			_advance(id)
		"dialogue":
			_busy = true
			# Let any pose changes settle first.
			await get_tree().create_timer(0.6).timeout
			await Dialogue.run(StoryData.TREES.get(s["tree"], {}))
			_busy = false
			_advance(id)
		"wait":
			_wait_until[id] = Time.get_ticks_msec() / 1000.0 + float(s.get("seconds", 1.0))
		"meet":
			_meet[id] = {"t": Time.get_ticks_msec() / 1000.0, "armed": false}


func _check(id: String, s: Dictionary) -> bool:
	var p: Player = Game.player
	var partner: Person = Game.partner
	match s.get("type", ""):
		"go":
			return Game.location == "outside" and _near(p.global_position, _target(s.get("to", "")), s.get("radius", 3.0))
		"enter":
			if Game.location != s.get("place", ""):
				return false
			return not s.has("carrying") or p.has_accessory(s["carrying"])
		"sit_together", "lie_together":
			var want := "sit" if s["type"] == "sit_together" else "lie"
			if p.pose != want or partner == null or partner.pose != want:
				return false
			if s["type"] == "sit_together" and partner.anchor_owner != p.anchor_owner:
				return false
			if p.global_position.distance_to(partner.global_position) > 3.2:
				return false
			if s.has("tag"):
				return p.anchor_owner != null and p.anchor_owner.tag == s["tag"]
			return not s.has("at") or _near(p.global_position, _target(s["at"]), s.get("radius", 6.0))
		"car_together":
			return p.pose == "drive" and partner != null and partner.pose == "drive"
		"use":
			return _used.get(s.get("tag", ""), false)
		"collect":
			return inventory.get(s["item"], 0) >= s.get("count", 1)
		"decorate":
			var d: DecorSystem = Game.world.decor if Game.world else null
			return d != null and d.complete() and not d.active
		"catch":
			return p.has_accessory("yoggi")
		"time":
			return Game.atmosphere != null and Game.atmosphere.current == s["preset"]
		"drive":
			return p.pose == "drive" and _near(p.global_position, _target(s.get("to", "")), s.get("radius", 6.0))
		"wait":
			return Time.get_ticks_msec() / 1000.0 >= _wait_until.get(id, 0.0)
		"meet":
			_check_meet(id, s)
	return false


## Sends him ahead once she's free (a few seconds into the step), then starts
## the conversation when she reaches him.
func _check_meet(id: String, s: Dictionary) -> void:
	var p: Player = Game.player
	var partner := Game.partner as Partner
	if partner == null:
		return
	var m: Dictionary = _meet.get(id, {})
	if m.is_empty():
		m = {"t": Time.get_ticks_msec() / 1000.0, "armed": false}
		_meet[id] = m
	if not m["armed"]:
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(m["t"]) < float(s.get("delay", 3.5)) or p.pose != "move" \
				or Game.location != "outside" or Game.story_lock \
				or (Game.hud and Game.hud.is_dialogue_open()):
			return
		var at: Variant = _target(s.get("at", ""))
		if at == null:
			return
		var spot := NavBaker.snap(partner.get_world_3d(), at)
		if spot.distance_to(at) > 6.0:
			spot = at
		m["armed"] = true
		partner.wait_at(spot, p.global_position)
		if Game.hud and s.has("msg"):
			Sound.play_ui("quest_start")
			Game.hud.toast(s["msg"], 6.0)
		return
	if not partner.waiting:
		partner.wait_at(NavBaker.snap(partner.get_world_3d(), _target(s.get("at", ""))))
	if p.pose == "move" and partner.is_at_wait_spot() \
			and p.global_position.distance_to(partner.global_position) < 2.8:
		_meet_talk(id, s)


func _meet_talk(id: String, s: Dictionary) -> void:
	var partner := Game.partner as Partner
	_busy = true
	if partner:
		var tp: Vector3 = Game.player.global_position - partner.global_position
		partner.facing = atan2(-tp.x, -tp.z)
		partner.gesture("emote-yes")
	await _say(_speaker("partner"), s.get("lines", ["There you are!"]), Color(0.45, 0.66, 0.95))
	if partner:
		partner.release_wait()
	_meet.erase(id)
	_busy = false
	_advance(id)


func _advance(id: String) -> void:
	if status(id) != "active":
		return
	var s := current_step(id)
	states[id]["step"] += 1
	quest_advanced.emit(id, states[id]["step"])
	if s.has("then"):
		_busy = true
		await Cutscene.run_actions(s["then"])
		_busy = false
	Sound.play_ui("step")
	_save()
	changed.emit()
	if states[id]["step"] >= quests[id]["steps"].size():
		_complete(id)


func _complete(id: String) -> void:
	if status(id) == "done":
		return
	states[id]["status"] = "done"
	_clear_pickups(id)
	_save()
	quest_completed.emit(id)
	changed.emit()
	var q: Dictionary = quests[id]
	if Game.hud:
		Sound.play_ui("quest_done")
		Game.hud.toast("✿ Quest complete: " + q["title"])
		if q.has("finish"):
			_busy = true
			await get_tree().create_timer(0.8).timeout
			await _say(q.get("finish_title", q["title"]), q["finish"], Color(0.95, 0.55, 0.62))
			_busy = false
	if tracked == id:
		var act := active_ids()
		tracked = act[0] if not act.is_empty() else ""
	if q.get("free_roam", false):
		# The story is done: the island is theirs to wander. Every place stays
		# open and he just tags along.
		flags["all_done"] = true
		if Game.partner is Partner:
			(Game.partner as Partner).release_wait()
		_save()
		changed.emit()
	elif q.get("new_game_plus", false):
		new_game_plus()
	else:
		_autostart()


## Every quest becomes available again; the ring, the house and Yoggi stay.
func new_game_plus() -> void:
	flags["ng_plus"] = int(flags.get("ng_plus", 0)) + 1
	states.clear()
	inventory.clear()
	_step_started.clear()
	tracked = ""
	if Game.atmosphere:
		Game.atmosphere.set_preset("day", 3.0)
	_save()
	changed.emit()
	await get_tree().create_timer(2.0).timeout
	_autostart()


func _autostart() -> void:
	for q in QuestData.QUESTS:
		if not q.has("giver") and status(q["id"]) == "" and _unlocked(q):
			start(q["id"])


func _unlocked(q: Dictionary) -> bool:
	return not q.has("after") or status(q["after"]) == "done"


func _collect_count(id: String, item: String) -> int:
	for s in quests[id]["steps"]:
		if s.get("type", "") == "collect" and s.get("item", "") == item:
			return s.get("count", 1)
	return 1


func _on_photo() -> void:
	for id in active_ids():
		var s := current_step(id)
		if s.get("type", "") == "photo" and _near(Game.player.global_position, _target(s.get("at", "")), s.get("radius", 6.0)):
			_advance(id)


## Restores persistent things (ring, decor, Yoggi at home) after loading.
func _apply_flags() -> void:
	var her: Person = Game.player
	if her and flags.get("ring", false):
		her.set_accessory("ring", true)
	var d: DecorSystem = Game.world.decor if Game.world else null
	if d and flags.has("decor"):
		d.load_from(flags["decor"])
	if flags.get("yoggi_home", false):
		var y: Yoggi = Places.spot("yoggi")
		var house: Interior = Places.interiors.get("house")
		if y and house:
			y.settle_home(house.to_global(Vector3(2.5, 0.1, 2.0)))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _say(speaker: String, lines: Array, color: Color) -> void:
	if Game.hud:
		_busy = true
		var styled: Array = []
		for l in lines:
			styled.append(Dialogue.style(str(l)))
		var voice := 0.8 if speaker == _speaker("partner") else 1.0
		await Game.hud.say(speaker, styled, color, voice)
		_busy = false


func _speaker(who: String) -> String:
	if who == "partner" and Game.partner:
		return Game.partner.display_name
	return who


func _near(a: Vector3, b: Variant, r: float) -> bool:
	if b == null:
		return false
	var d := Vector2(a.x - b.x, a.z - b.z).length()
	return d <= r


## A landmark, a Places spot, a villager, "partner" or a Vector3 → world position.
func _target(t: Variant) -> Variant:
	if t is Vector3:
		return t
	var s := str(t)
	if QuestData.LANDMARKS.has(s):
		var v: Vector3 = QuestData.LANDMARKS[s]
		if Game.terrain:
			v.y = maxf(v.y, Game.terrain.height_at(v.x, v.z))
		return v
	var sp := Places.spot(s)
	if sp:
		return sp.global_position
	var n := _person(s)
	if n:
		return n.global_position
	return null


func _person(who: String) -> Node3D:
	if who == "partner":
		return Game.partner
	return get_tree().current_scene.get_node_or_null("Villager_" + who) if get_tree().current_scene else null


## Where the marker / mini-map point for a quest right now (null = nowhere useful).
func step_target(id: String) -> Variant:
	var s := current_step(id)
	var inside := Game.location != "outside"
	match s.get("type", ""):
		"go", "drive":
			return _target(s.get("to", ""))
		"talk":
			return _target(s.get("who", ""))
		"meet":
			if inside:
				return null
			if _meet.get(id, {}).get("armed", false) and Game.partner:
				return Game.partner.global_position
			return _target(s.get("at", ""))
		"deliver":
			return _target(s.get("to", "")) if inventory.get(s["item"], 0) >= s.get("count", _collect_count(id, s["item"])) else null
		"sit_together", "lie_together", "use":
			if s.has("tag"):
				var sp := Places.spot(s["tag"])
				if sp:
					return sp.global_position
			return _target(s["at"]) if s.has("at") else null
		"enter":
			if inside:
				return null
			return _target({"pizza": "pizza_door", "cinema": "cinema_door", "house": "house_door", "hotel": "hotel_door"}.get(s.get("place", ""), ""))
		"catch":
			var y: Node3D = Places.spot("yoggi")
			return y.global_position if y else null
		"car_together":
			var car: Node3D = get_tree().current_scene.get_node_or_null("Car") if get_tree().current_scene else null
			return car.global_position if car else null
		"collect":
			var list: Array = _pickups.get(id, [])
			var best: Variant = null
			var bd := INF
			for pk in list:
				if is_instance_valid(pk):
					var d: float = pk.global_position.distance_to(Game.player.global_position)
					if d < bd:
						bd = d
						best = pk.global_position
			return best
	return null


func _spawn_pickups(id: String, s: Dictionary) -> void:
	if _pickups.has(id):
		return
	var list: Array = []
	var have: int = inventory.get(s["item"], 0)
	var spawns: Array = s.get("spawn", [])
	for i in range(have, mini(spawns.size(), s.get("count", 1))):
		var pk := Pickup.new()
		pk.item = s["item"]
		pk.display_name = s.get("name", s["item"])
		pk.model_id = s.get("model", "")
		pk.tint = s.get("color", Color(1, 1, 1))
		get_tree().current_scene.add_child(pk)
		var pos: Vector3 = spawns[i]
		if Game.terrain:
			pos.y = Game.terrain.height_at(pos.x, pos.z)
		pk.global_position = pos
		pk.picked.connect(func(item: String) -> void:
			inventory[item] = inventory.get(item, 0) + 1
			Sound.play_ui("pickup")
			if Game.hud:
				Game.hud.toast("Got a %s! (%s)" % [pk.display_name, step_progress(id)])
			_save()
			changed.emit())
		list.append(pk)
	_pickups[id] = list


func _clear_pickups(id: String) -> void:
	for pk in _pickups.get(id, []):
		if is_instance_valid(pk):
			pk.queue_free()
	_pickups.erase(id)


func _build_marker() -> void:
	_marker = Node3D.new()
	_marker.name = "QuestMarker"
	add_child(_marker)
	_marker_label = Label3D.new()
	_marker_label.text = "♥"
	_marker_label.font_size = 96
	_marker_label.outline_size = 18
	_marker_label.modulate = Color(1.0, 0.5, 0.58)
	_marker_label.outline_modulate = Color(1, 1, 1)
	_marker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker_label.no_depth_test = true
	_marker_label.pixel_size = 0.006
	_marker.add_child(_marker_label)
	_marker.visible = false


func current_target() -> Variant:
	if tracked == "" or status(tracked) != "active":
		var act := active_ids()
		if act.is_empty():
			return null
		tracked = act[0]
	return step_target(tracked)


func _update_marker() -> void:
	var t: Variant = current_target()
	if t == null or _busy or (Game.hud and Game.hud.is_dialogue_open()):
		_marker.visible = false
		return
	_marker.visible = true
	var bob := sin(Time.get_ticks_msec() / 1000.0 * 3.0) * 0.15
	_marker.global_position = (t as Vector3) + Vector3(0, 2.6 + bob, 0)


# ---------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------

func _save() -> void:
	if Game.options.has("shots") or Game.options.has("no_save"):
		return
	var d: DecorSystem = Game.world.decor if Game.world else null
	if d:
		flags["decor"] = d.placed
	var data := {
		"version": SAVE_VERSION,
		"quests": states,
		"inventory": inventory,
		"tracked": tracked,
		"flags": flags,
		"outfits": {
			"her": Game.player.dry_outfit() if Game.player else "",
			"him": Game.partner.dry_outfit() if Game.partner else "",
		},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (data is Dictionary):
		return
	var old := int(data.get("version", 1)) < SAVE_VERSION
	for id in data.get("quests", {}):
		if quests.has(id):
			var st: Dictionary = data["quests"][id]
			var step := int(st.get("step", 0))
			if old:
				step = 0     # the steps changed: start this quest's steps afresh
			# Resume at the start of a conversation rather than half-way through it.
			# Carrying something isn't saved: go back to picking it up.
			var steps: Array = quests[id]["steps"]
			if step < steps.size() and steps[step].has("carrying") and step > 0:
				step -= 1
			states[id] = {"status": st.get("status", "active"), "step": step}
	for k in data.get("inventory", {}):
		inventory[k] = int(data["inventory"][k])
	tracked = data.get("tracked", "")
	flags = data.get("flags", {})
	var outfits: Dictionary = data.get("outfits", {})
	if Game.player and outfits.get("her", "") != "":
		Game.player.set_outfit(outfits["her"])
	if Game.partner and outfits.get("him", "") != "":
		Game.partner.set_outfit(outfits["him"])


func _delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func save_now() -> void:
	_save()

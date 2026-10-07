class_name QuestManager
extends Node
## Runs the quests from QuestData: starts them (from a villager or on their
## own), checks each step, places pick-ups and the floating marker, and saves
## progress to user://save.json.

signal quest_started(id: String)
signal quest_advanced(id: String, step: int)
signal quest_completed(id: String)
signal changed

const SAVE_PATH := "user://save.json"

## id -> {"status": "active" | "done", "step": int}
var states := {}
var inventory := {}
var quests := {}            # id -> quest dictionary
var tracked := ""           # the quest shown in the tracker
var _pickups := {}          # quest id -> Array[Pickup]
var _step_started := {}     # quest id -> step index already "entered"
var _wait_until := {}       # quest id -> time
var _busy := false          # a dialogue triggered by a quest is open
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
	var q: Dictionary = quests[id]
	var i: int = states[id]["step"]
	return q["steps"][i] if i < q["steps"].size() else {}


func step_progress(id: String) -> String:
	var s := current_step(id)
	if s.get("type", "") == "collect":
		return "%d/%d" % [mini(inventory.get(s["item"], 0), s.get("count", 1)), s.get("count", 1)]
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


## Called by villagers and the partner when you talk to them.
## Returns true when a quest took over the conversation.
func handle_talk(who: String, color: Color = Color(0.98, 0.62, 0.45)) -> bool:
	if _busy:
		return true
	# A quest step waiting for this person?
	for id in active_ids():
		var s := current_step(id)
		match s.get("type", ""):
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
	# Someone with a quest to give?
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
		"time":
			if Game.atmosphere and Game.atmosphere.current != s["preset"]:
				if s.get("auto", false):
					await get_tree().create_timer(1.5).timeout
					Game.atmosphere.set_preset(s["preset"], 5.0)
				elif Game.hud:
					Game.hud.toast("Press T to change the time of day")
		"memory":
			_busy = true
			await _say(s.get("title", ""), s.get("lines", []), Color(0.95, 0.55, 0.62))
			_busy = false
			_advance(id)
		"wait":
			_wait_until[id] = Time.get_ticks_msec() / 1000.0 + float(s.get("seconds", 1.0))


func _check(id: String, s: Dictionary) -> bool:
	var p: Player = Game.player
	var partner: Person = Game.partner
	match s.get("type", ""):
		"go":
			return _near(p.global_position, _target(s.get("to", "")), s.get("radius", 3.0))
		"sit_together", "lie_together":
			var want := "sit" if s["type"] == "sit_together" else "lie"
			if p.pose != want or partner == null or partner.pose != want:
				return false
			if s["type"] == "sit_together" and partner.anchor_owner != p.anchor_owner:
				return false
			if p.global_position.distance_to(partner.global_position) > 3.0:
				return false
			return not s.has("at") or _near(p.global_position, _target(s["at"]), s.get("radius", 6.0))
		"collect":
			return inventory.get(s["item"], 0) >= s.get("count", 1)
		"time":
			return Game.atmosphere != null and Game.atmosphere.current == s["preset"]
		"drive":
			return p.pose == "drive" and _near(p.global_position, _target(s.get("to", "")), s.get("radius", 6.0))
		"wait":
			return Time.get_ticks_msec() / 1000.0 >= _wait_until.get(id, 0.0)
	return false


func _advance(id: String) -> void:
	if status(id) != "active":
		return
	states[id]["step"] += 1
	quest_advanced.emit(id, states[id]["step"])
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
	Sound.play_ui("quest_done")
	var q: Dictionary = quests[id]
	if Game.hud:
		Game.hud.toast("✿ Quest complete: " + q["title"])
		if q.has("finish"):
			_busy = true
			await get_tree().create_timer(0.6).timeout
			await _say(q.get("finish_title", q["title"]), q["finish"], Color(0.95, 0.55, 0.62))
			_busy = false
	if tracked == id:
		var act := active_ids()
		tracked = act[0] if not act.is_empty() else ""
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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _say(speaker: String, lines: Array, color: Color) -> void:
	if Game.hud:
		_busy = true
		await Game.hud.say(speaker, lines, color)
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


## A landmark name, a villager name, "partner" or a Vector3 → world position.
func _target(t: Variant) -> Variant:
	if t is Vector3:
		return t
	var s := str(t)
	if QuestData.LANDMARKS.has(s):
		var v: Vector3 = QuestData.LANDMARKS[s]
		if Game.terrain:
			v.y = maxf(v.y, Game.terrain.height_at(v.x, v.z))
		return v
	var n := _person(s)
	if n:
		return n.global_position
	return null


func _person(who: String) -> Node3D:
	if who == "partner":
		return Game.partner
	return get_tree().current_scene.get_node_or_null("Villager_" + who) if get_tree().current_scene else null


func step_target(id: String) -> Variant:
	var s := current_step(id)
	match s.get("type", ""):
		"go", "drive":
			return _target(s.get("to", ""))
		"talk":
			return _target(s.get("who", ""))
		"deliver":
			return _target(s.get("to", "")) if inventory.get(s["item"], 0) >= s.get("count", _collect_count(id, s["item"])) else null
		"sit_together", "lie_together", "photo":
			return _target(s["at"]) if s.has("at") else null
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


func _update_marker() -> void:
	var t: Variant = step_target(tracked) if tracked != "" and status(tracked) == "active" else null
	if t == null or (Game.hud and Game.hud.is_dialogue_open()):
		_marker.visible = false
		return
	_marker.visible = true
	var bob := sin(Time.get_ticks_msec() / 1000.0 * 3.0) * 0.15
	_marker.global_position = (t as Vector3) + Vector3(0, 2.6 + bob, 0)


# ---------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------

func _save() -> void:
	if Game.options.has("shots"):
		return   # screenshot runs must not touch the real save
	var data := {
		"quests": states,
		"inventory": inventory,
		"tracked": tracked,
		"outfits": {
			"her": Game.player.outfit if Game.player else "",
			"him": Game.partner.outfit if Game.partner else "",
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
	for id in data.get("quests", {}):
		if quests.has(id):
			var st: Dictionary = data["quests"][id]
			states[id] = {"status": st.get("status", "active"), "step": int(st.get("step", 0))}
	for k in data.get("inventory", {}):
		inventory[k] = int(data["inventory"][k])
	tracked = data.get("tracked", "")
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

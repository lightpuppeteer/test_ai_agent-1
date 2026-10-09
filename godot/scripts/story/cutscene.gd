class_name Cutscene
extends RefCounted
## Actions used by dialogue trees and quests. Each action is a short string,
## optionally with an argument after a colon: "wait:1.5", "popup:Title|Text".
##
##   wait:S           pause S seconds          sfx:NAME        play a sound
##   popup:T|X        achievement card         hearts          hearts over the couple
##   kiss             lean in + hearts         kneel / stand   him on one knee / back up
##   face             turn to face each other  cam:close|wide|reset|volcano|sky
##   letterbox / letterbox_off                fade_out / fade_in
##   erupt            the volcano goes off      fireworks / fireworks_off
##   cucumbers / cucumbers_off                 movie:horror|comedy|drama|off
##   music:TRACK      (music: clears)          time:day|golden|night
##   ring             she wears the ring now    pepperoni      his slice lands on his lap
##   rumble           controller rumble        sit_close      partner sits beside her (picnic)
##   hearts_loop / hearts_off                  little hearts keep bubbling up over the couple
##   lean_in / lean_out                        rest against each other (seated or in the car)
##   cam:bench | bench_close                   from behind a bench they sit on, looking where they look

static var _fireworks_on := false
static var _hearts_on := false


static func run_actions(list: Array) -> void:
	for a in list:
		await run(str(a))


static func run(action: String) -> void:
	var name := action
	var arg := ""
	var c := action.find(":")
	if c >= 0:
		name = action.substr(0, c)
		arg = action.substr(c + 1)
	var hud: HUD = Game.hud
	var her: Person = Game.player
	var him: Person = Game.partner
	var tree := her.get_tree()
	match name:
		"wait":
			await tree.create_timer(float(arg) if arg != "" else 1.0).timeout
		"sfx":
			Sound.play(arg, -4.0)
		"popup":
			var parts := arg.split("|")
			await hud.popup(parts[0], parts[1] if parts.size() > 1 else "")
		"lean_in":
			her.lean(0.45)
			him.lean(0.45)
		"lean_out":
			her.lean(0.0)
			him.lean(0.0)
		"hearts_loop":
			_hearts_on = true
			_hearts_loop(her, him)
		"hearts_off":
			_hearts_on = false
		"hearts":
			FX.hearts(her.get_parent(), (her.global_position + him.global_position) * 0.5 + Vector3(0, 1.6, 0))
			Sound.play("smooch", -8.0, 1.2)
		"face":
			_face_each_other(her, him)
		"kiss":
			await _kiss(her, him)
		"kneel":
			_face_each_other(her, him)
			him.hold_pose("crouch")
			Sound.play("sit", -6.0, 0.8)
		"stand":
			him.release_pose()
		"cam":
			_camera(arg, her, him)
		"letterbox":
			await hud.letterbox(true)
		"letterbox_off":
			await hud.letterbox(false)
		"fade_out":
			await hud.fade(1.0, 0.8)
		"fade_in":
			await hud.fade(0.0, 0.8)
		"erupt":
			if Game.world and Game.world.volcano:
				Game.world.volcano.erupt()
		"fireworks":
			_fireworks_on = true
			_fireworks_loop(her)
		"fireworks_off":
			_fireworks_on = false
		"cucumbers":
			her.set_accessory("cucumbers", true)
			him.set_accessory("cucumbers", true)
			Sound.play("pop", -6.0)
		"cucumbers_off":
			her.set_accessory("cucumbers", false)
			him.set_accessory("cucumbers", false)
		"movie":
			if Game.world and Game.world.cinema_screen:
				Game.world.cinema_screen.play(arg)
		"music":
			Sound.override_music(arg)
		"time":
			if Game.atmosphere:
				Game.atmosphere.set_preset(arg, 2.0)
		"ring":
			her.set_accessory("ring", true)
			if Game.quests:
				Game.quests.flags["ring"] = true
				Game.quests.save_now()
			FX.sparkle(her.get_parent(), her.global_position + Vector3(0, 0.8, 0))
		"pepperoni":
			him.set_accessory("pepperoni", true)
			Sound.play("pop", -6.0, 0.8)
		"rumble":
			Game.rumble(0.6, 0.8, 0.8)
		"levelup":
			Sound.play("levelup", -2.0)
		"title":
			var tp := arg.split("|")
			hud.show_title(tp[0], tp[1] if tp.size() > 1 else "", 3.0)
		"yoggi_home":
			var y: Yoggi = Places.spot("yoggi")
			var house: Interior = Places.interiors.get("house")
			if y and house:
				her.set_accessory("yoggi", false)
				y.settle_home(house.to_global(Vector3(2.5, 0.1, 2.0)))
				if Game.quests:
					Game.quests.flags["yoggi_home"] = true
					Game.quests.save_now()
		"feast":
			var anchor: Node3D = Places.spot("picnic_feast")
			if anchor and anchor.get_child_count() == 0:
				anchor.add_child(Props3D.picnic_feast())
				FX.sparkle(anchor, anchor.global_position + Vector3(0, 0.5, 0), Color(1, 0.95, 0.7), 30)
		"popcorn":
			her.set_accessory("popcorn", true)
			him.set_accessory("drink", true)
			Sound.play("pop", -6.0)
		"snacks_off":
			her.set_accessory("popcorn", false)
			him.set_accessory("drink", false)
			him.set_accessory("pepperoni", false)


static func _face_each_other(a: Person, b: Person) -> void:
	if a.pose == "move":
		var d := b.global_position - a.global_position
		a.facing = atan2(-d.x, -d.z)
		a.rotation.y = a.facing
	if b.pose == "move":
		var d := a.global_position - b.global_position
		b.facing = atan2(-d.x, -d.z)
		b.rotation.y = b.facing


static func _kiss(her: Person, him: Person) -> void:
	var tree := her.get_tree()
	if her.pose == "move" and him.pose == "move":
		# Step close, face each other.
		var mid := (her.global_position + him.global_position) * 0.5
		var dir := (him.global_position - her.global_position)
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		him.teleport_grounded(Vector3(mid.x, mid.y, mid.z) + dir * 0.42)
		her.teleport_grounded(Vector3(mid.x, mid.y, mid.z) - dir * 0.42)
		_face_each_other(her, him)
	her.lean(1.0)
	him.lean(1.0)
	Sound.play("smooch", -4.0)
	FX.hearts(her.get_parent(), (her.global_position + him.global_position) * 0.5 + Vector3(0, 1.5, 0), 18)
	await tree.create_timer(1.6).timeout
	her.lean(0.0)
	him.lean(0.0)


static func _camera(mode: String, her: Person, him: Person) -> void:
	var rig: CameraRig = Game.camera_rig
	if rig == null:
		return
	var mid := (her.global_position + him.global_position) * 0.5
	var side := (him.global_position - her.global_position)
	side.y = 0
	var yaw := atan2(-side.z, side.x) if side.length() > 0.1 else rig.yaw
	match mode:
		"close":
			var pc := mid + Vector3(0, 0.7, 0)
			rig.cinematic(pc, _clear_side(pc, yaw, -8.0, 4.0), -8.0, 4.0)
		"wide":
			var pw := mid + Vector3(0, 1.0, 0)
			rig.cinematic(pw, _clear_side(pw, yaw + 0.5, -14.0, 9.0), -14.0, 9.0)
		"volcano":
			var v: Node3D = Game.world.volcano if Game.world else null
			if v:
				var to := v.global_position - mid
				rig.cinematic(mid + Vector3(0, 3.0, 0), atan2(-to.x, -to.z), 8.0, 9.0)
		"bench", "bench_close":
			# Behind the two of them on the bench, looking the way they face
			# (out to sea, where the fireworks are), close enough to see them lean in.
			var f := -her.global_transform.basis.z
			f.y = 0.0
			f = f.normalized() if f.length() > 0.01 else Vector3.BACK
			var look_yaw := atan2(-f.x, -f.z)
			if mode == "bench":
				rig.cinematic(mid + Vector3(0, 1.15, 0), look_yaw, -3.0, 4.4, true)
			else:
				rig.cinematic(mid + Vector3(0, 1.05, 0), look_yaw, 1.0, 2.7, true)
		"sky":
			# Looking out to sea (fireworks go off to the south), couple low in frame.
			rig.cinematic(mid + Vector3(0, 2.0, 0), PI, 4.0, 8.0)
		_:
			rig.end_cinematic()


## Of the two sides of the couple, the one where the camera arm isn't blocked
## (an oven, a tree...). Ties keep the side nearer the current camera.
static func _clear_side(pivot: Vector3, yaw: float, pitch_deg: float, dist: float) -> float:
	var rig: CameraRig = Game.camera_rig
	var space := rig.get_world_3d().direct_space_state
	var best := yaw
	var best_free := -1.0
	var opts := [yaw, yaw + PI]
	if absf(wrapf(yaw + PI - rig.yaw, -PI, PI)) < absf(wrapf(yaw - rig.yaw, -PI, PI)):
		opts = [yaw + PI, yaw]
	for y in opts:
		var dir := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), y, 0)) * Vector3(0, 0, 1)
		var q := PhysicsRayQueryParameters3D.create(pivot, pivot + dir * (dist + 0.5), rig.arm.collision_mask)
		var hit := space.intersect_ray(q)
		var free := dist + 0.5 if hit.is_empty() else pivot.distance_to(hit["position"])
		if free > best_free + 0.3:
			best_free = free
			best = y
	return best


static func _fireworks_loop(near: Node3D) -> void:
	var tree := near.get_tree()
	var colors := [Color(1, 0.4, 0.55), Color(1, 0.85, 0.3), Color(0.45, 0.8, 1), Color(0.75, 0.5, 1), Color(0.5, 1, 0.6), Color(1, 0.6, 0.3)]
	var kinds := ["peony", "peony", "ring", "willow", "glitter", "heart", "peony", "ring"]
	var n := 0
	while _fireworks_on:
		n += 1
		var base := near.global_position + Vector3(randf_range(-22, 22), 0, 0)
		base.z += 30.0
		base.y = 0.5
		var kind: String = "letters" if n % 7 == 3 else kinds[randi() % kinds.size()]
		var col: Color = Color(1, 0.45, 0.6) if kind == "letters" or kind == "heart" else colors[randi() % colors.size()]
		if kind == "letters":
			base.x = near.global_position.x
		FX.firework(near.get_parent(), base, randf_range(11, 16) if kind != "letters" else 14.0, col, kind)
		# Now and then a pair goes up together.
		if randf() < 0.25 and kind != "letters":
			FX.firework(near.get_parent(), base + Vector3(randf_range(-10, 10), 0, randf_range(-3, 3)), randf_range(9, 14), colors[randi() % colors.size()], "peony")
		await tree.create_timer(randf_range(0.6, 1.3) if kind != "letters" else 2.6).timeout


static func _hearts_loop(her: Person, him: Person) -> void:
	var tree := her.get_tree()
	while _hearts_on:
		var mid := (her.global_position + him.global_position) * 0.5
		FX.hearts(her.get_parent(), mid + Vector3(randf_range(-0.2, 0.2), 1.45, 0), 4)
		await tree.create_timer(randf_range(0.5, 0.9)).timeout

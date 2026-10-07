extends Node
## Headless test: runs the sample quests end to end.
func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var qm: QuestManager = Game.quests
	var p: Player = Game.player
	var hud: HUD = Game.hud
	print("active at start: ", qm.active_ids())
	var pip: Villager = get_tree().current_scene.get_node("Main/Villager_Pip")
	p.teleport(pip.global_position + Vector3(0, 0, 1.5))
	pip.interactable.interact(p)
	await _close_dialogue()
	print("after Pip: ", qm.active_ids(), " step ", qm.current_step("shells_for_pip").get("text"))
	await get_tree().create_timer(0.3).timeout
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Pickup:
			p.teleport(n.global_position + Vector3(0.5, 0, 0))
			n.interact(p)
			await get_tree().create_timer(0.2).timeout
	print("inventory ", qm.inventory, " step ", qm.current_step("shells_for_pip").get("text"))
	p.teleport(pip.global_position + Vector3(0, 0, 1.5))
	pip.interactable.interact(p)
	await _close_dialogue()
	await get_tree().create_timer(1.0).timeout
	await _close_dialogue()
	print("pip quest: ", qm.status("shells_for_pip"), "  active: ", qm.active_ids())
	# Sunset quest: talk to partner, go to lookout, wait for golden, sit together.
	Game.partner.interactable.interact(p)
	await _close_dialogue()
	print("sunset step: ", qm.current_step("sunset_date").get("text"))
	var lp: Vector3 = QuestData.LANDMARKS["lookout"]
	p.teleport(Vector3(lp.x, Game.terrain.height_at(lp.x, lp.z) + 0.2, lp.z + 2.0))
	await get_tree().create_timer(8.0).timeout
	print("sunset step: ", qm.current_step("sunset_date").get("text"), " preset ", Game.atmosphere.current)
	var bench: Interactable = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.kind == "sit" and n.global_position.distance_to(lp) < 6.0:
			bench = n
	p.use(bench)
	await get_tree().create_timer(6.0).timeout
	print("partner pose ", Game.partner.pose, " player ", p.pose)
	await _close_dialogue()
	await get_tree().create_timer(4.5).timeout
	await _close_dialogue()
	print("sunset quest: ", qm.status("sunset_date"))
	print("save exists: ", FileAccess.file_exists("user://save.json"))
	get_tree().quit()


func _close_dialogue() -> void:
	for i in 60:
		await get_tree().create_timer(0.1).timeout
		if Game.hud.is_dialogue_open():
			# Skip typing then advance through all lines.
			for k in 12:
				if not Game.hud.is_dialogue_open():
					break
				Game.hud._advance()
				await get_tree().process_frame
			return

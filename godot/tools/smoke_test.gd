extends Node
## Headless gameplay smoke test.
func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var p: Player = Game.player
	var partner = Game.partner
	print("start ", p.global_position, " partner ", partner.global_position)
	# Walk inland (camera yaw = PI faces the sea, so "back" walks inland).
	Input.action_press("move_back")
	for i in 4:
		await get_tree().create_timer(0.5).timeout
		print("t=", i, " p=", p.global_position.snapped(Vector3.ONE * 0.01), " floor=", p.is_on_floor(), " anim=", p._anim_name, " partner=", partner.global_position.snapped(Vector3.ONE*0.01))
	Input.action_release("move_back")
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	await get_tree().create_timer(0.3).timeout
	print("jump y=", p.global_position.y, " anim=", p._anim_name)
	await get_tree().create_timer(1.0).timeout
	print("landed y=", p.global_position.y, " floor=", p.is_on_floor())
	# Sit on the nearest bench via focus.
	print("focus=", p.focus.prompt if p.focus else "none")
	get_tree().quit()

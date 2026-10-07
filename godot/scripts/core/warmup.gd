class_name Warmup
extends Node
## Renders every room and effect once, off-screen, while the title screen is up,
## so the GPU compiles its shaders now instead of stuttering the first time you
## walk into the pizzeria or the fireworks start.

var _vp: SubViewport
var _cam: Camera3D


func run() -> void:
	var main_vp := get_viewport()
	_vp = SubViewport.new()
	_vp.size = Vector2i(320, 180)
	_vp.world_3d = main_vp.world_3d if main_vp.world_3d else main_vp.find_world_3d()
	_vp.msaa_3d = main_vp.msaa_3d
	_vp.screen_space_aa = main_vp.screen_space_aa
	_vp.positional_shadow_atlas_size = main_vp.positional_shadow_atlas_size
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 400.0
	_vp.add_child(_cam)
	_cam.current = true
	await _frames(2)
	for id in Places.interiors:
		var it: Interior = Places.interiors[id]
		for off in [Vector3(0, 7, it.size.z * 0.5 + 4), Vector3(it.size.x * 0.4, 4, 0)]:
			_look(it.global_position + off, it.global_position + Vector3(0, 1, 0))
			await _frames(3)
	# A few island views (shadows, foliage, water from different angles).
	for p in [[Vector3(0, 30, 60), Vector3(0, 0, 0)], [Vector3(60, 12, 90), Vector3(80, 2, 96)], [Vector3(-40, 10, 0), Vector3(-56, 2, -15)]]:
		_look(p[0], p[1])
		await _frames(3)
	# Every kind of firework, far below the world where nobody can see it.
	var spot := Vector3(0, -400, 0)
	var holder := Node3D.new()
	add_child(holder)
	_look(spot + Vector3(0, 0, 30), spot)
	for kind in ["peony", "ring", "willow"]:
		FX._burst(holder, spot, Color(1, 0.5, 0.6), kind)
	FX._glitter(holder, spot, 4.0)
	FX._shape_burst(holder, spot, FireworkShapes.HEART, 3.0, Color(1, 0.5, 0.6))
	FX.hearts(holder, spot, 4)
	FX.sparkle(holder, spot, Color(1, 0.9, 0.5), 10)
	await _frames(40)
	holder.queue_free()
	_vp.queue_free()
	queue_free()


func _look(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

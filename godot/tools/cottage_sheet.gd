extends Node3D
## Dev tool: renders every cottage type side by side. user args: out.png
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.8, 0.88, 0.95)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	add_child(sun)
	var roofs := [Color(0.95, 0.55, 0.7), Color(0.92, 0.3, 0.28), Color(0.66, 0.5, 0.9), Color(0.25, 0.25, 0.35), Color(0.4, 0.75, 0.8), Color(0.98, 0.42, 0.65)]
	var types := ["a", "c", "e", "h", "p", "t"]
	if a.size() > 1:
		types = a[1].split(",")
	var i := 0
	for t in types:
		var c := Cottage.make(t, roofs[i], 1.0)
		add_child(c)
		c.position = Vector3(i * 8.0, 0, 0)
		i += 1
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	var cx := (types.size() - 1) * 4.0
	cam.position = Vector3(cx + 2.0, 7, 6.0 + types.size() * 3.5)
	cam.look_at(Vector3(cx, 2.5, 0))
	get_viewport().size = Vector2i(1800, 700)
	for k in 5:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(a[0])
	get_tree().quit()

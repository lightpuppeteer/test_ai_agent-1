extends Node3D
# user args: out_dir, model ids... → renders one framed PNG per model.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.82, 0.86, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.5,0.5,0.55)
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 35, 0); add_child(sun)
	var cam := Camera3D.new(); add_child(cam); cam.fov = 35
	var lbl := Label.new(); lbl.add_theme_color_override("font_color", Color.BLACK); lbl.add_theme_font_size_override("font_size", 18); add_child(lbl)
	for id in a.slice(1):
		var inst: Node3D = Props.model(id); add_child(inst)
		var bb := Props.node_aabb(inst)
		var r := bb.size.length() * 0.5
		var c := bb.get_center()
		cam.position = c + Vector3(0.6, 0.45, 1.0).normalized() * r / sin(deg_to_rad(17.5)) * 1.05
		cam.look_at(c)
		lbl.text = "%s  %.2f×%.2f×%.2f" % [id.get_file(), bb.size.x, bb.size.y, bb.size.z]
		for k in 3: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join(id.replace("/", "__") + ".png"))
		inst.free()
	get_tree().quit()

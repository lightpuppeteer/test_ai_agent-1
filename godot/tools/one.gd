extends Node3D
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.8, 0.85, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6,0.6,0.65)
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); add_child(sun)
	var inst: Node3D = load(a[0]).instantiate(); add_child(inst)
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	if ap and a.size() > 2 and a[2] != "":
		ap.play(a[2]); ap.seek(float(a[3]) if a.size() > 3 else 0.0, true); ap.pause()
	var cam := Camera3D.new(); add_child(cam); cam.fov = 30
	cam.position = Vector3(0.6, 0.6, 2.2); cam.look_at(Vector3(0, 0.35, 0))
	for k in 4: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(a[1]); get_tree().quit()

extends Node3D
## Dev tool: renders both avatars in every outfit (front and 3/4 view).
## user args: out.png [anim] [phase]  (default: res://_shots/avatars.png)
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else ProjectSettings.globalize_path("res://_shots/avatars.png")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var anim_name := a[1] if a.size() > 1 else "idle"
	var phase := float(a[2]) if a.size() > 2 else 0.25
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.86, 0.9, 0.84)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.62, 0.66)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	add_child(sun)
	var row := 0
	var cols := 0
	for who in ["her", "him"]:
		var i := 0
		for o in AvatarLooks.OUTFITS[who]:
			for yaw in [0.0, 35.0]:
				var m := Avatar.build(AvatarLooks.look(who, o))
				add_child(m)
				m.position = Vector3(i * 0.6, -row * 0.85, 0)
				m.rotation_degrees.y = yaw
				var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
				ap.play(anim_name)
				ap.seek(ap.current_animation_length * phase, true)
				ap.pause()
				i += 1
		cols = maxi(cols, i)
		row += 1
	var cam := Camera3D.new()
	add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = cols * 0.6
	var cx := (cols - 1) * 0.3
	cam.position = Vector3(cx, 0.0, 3.0)
	cam.look_at(Vector3(cx, -0.05, 0))
	get_viewport().size = Vector2i(2000, 600)
	for k in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("[avatar_sheet] ", out)
	get_tree().quit()

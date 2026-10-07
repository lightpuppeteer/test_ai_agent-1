extends Node3D
# Renders a grid of a character's animations (at a given phase) for inspection.
@export var model := "res://assets/kenney/mini-characters/character-female-a.glb"
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: model = args[0]
	var phase := float(args[1]) if args.size() > 1 else 0.5
	var out := args[2] if args.size() > 2 else "/tmp/poses.png"
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.8, 0.85, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6,0.6,0.65)
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); add_child(sun)
	var ps: PackedScene = load(model)
	var probe := ps.instantiate(); var ap0: AnimationPlayer = probe.find_child("AnimationPlayer", true, false)
	var names: PackedStringArray = ap0.get_animation_list(); probe.free()
	if args.size() > 3: names = args[3].split(",")
	var cols := mini(8, names.size())
	var i := 0
	for n in names:
		var inst: Node3D = ps.instantiate(); add_child(inst)
		inst.position = Vector3((i % cols) * 1.3, 0, (i / cols) * 1.6)
		inst.rotation_degrees.y = 25
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		ap.play(n); ap.seek(ap.current_animation_length * phase, true); ap.pause()
		var lbl := Label3D.new(); lbl.text = n; lbl.font_size = 24; lbl.pixel_size = 0.004; lbl.position = Vector3(0, -0.12, 0.3); lbl.modulate = Color.BLACK
		lbl.rotation_degrees.x = -30; inst.add_child(lbl)
		i += 1
	var rows := int(ceil(float(i) / cols))
	var cam := Camera3D.new(); add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = rows * 1.6 + 0.6
	cam.position = Vector3((cols - 1) * 0.65, 1.2, rows * 1.6 + 3.2); cam.look_at(Vector3((cols-1)*0.65, 0.3, rows*0.8 - 0.6))
	for k in 4: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()

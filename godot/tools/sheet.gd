extends Node3D
# Contact sheet: user args = out.png, cols, then model paths. Each model normalised to fit a 1x1 cell.
func _aabb(n: Node, t: Transform3D, out: Array) -> void:
	if n is Node3D: t = t * n.transform
	if n is MeshInstance3D and n.mesh:
		var a: AABB = t * n.mesh.get_aabb()
		out[0] = a if out[0] == null else out[0].merge(a)
	for c in n.get_children(): _aabb(c, t, out)
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]; var cols := int(a[1]); var models := a.slice(2)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.82, 0.86, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.55,0.55,0.6)
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, 35, 0); add_child(sun)
	var i := 0
	for m in models:
		var inst: Node3D = load(m).instantiate()
		var r := [null]; _aabb(inst, Transform3D.IDENTITY, r)
		var bb: AABB = r[0] if r[0] != null else AABB(Vector3.ZERO, Vector3.ONE)
		var s: float = 0.8 / max(bb.size.x, bb.size.y, bb.size.z)
		var holder := Node3D.new(); add_child(holder)
		holder.position = Vector3((i % cols) * 1.2, 0, (i / cols) * 1.7)
		inst.scale = Vector3.ONE * s; inst.position = -bb.get_center() * s + Vector3(0, bb.size.y * s * 0.5, 0)
		holder.add_child(inst)
		var lbl := Label3D.new(); lbl.text = m.get_file().get_basename() + "\n%.2f×%.2f×%.2f" % [bb.size.x, bb.size.y, bb.size.z]
		lbl.font_size = 22; lbl.pixel_size = 0.0035; lbl.position = Vector3(0, -0.12, 0.45); lbl.modulate = Color.BLACK; lbl.outline_size = 0
		holder.add_child(lbl)
		i += 1
	var rows := int(ceil(float(i) / cols))
	var cam := Camera3D.new(); add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = max(rows * 1.7 * 0.85, cols * 1.2 / 1.8) + 0.8
	var c := Vector3((cols - 1) * 0.6, 0.3, (rows - 1) * 0.85)
	cam.position = c + Vector3(0, 5, 9); cam.look_at(c)
	for k in 4: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()

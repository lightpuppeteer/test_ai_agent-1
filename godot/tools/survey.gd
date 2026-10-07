extends SceneTree
func aabb_of(n: Node, xf := Transform3D.IDENTITY) -> AABB:
	var out := AABB(); var first := true
	var stack := [[n, xf]]
	while stack.size():
		var e = stack.pop_back(); var node: Node = e[0]; var t: Transform3D = e[1]
		if node is Node3D: t = t * (node as Node3D).transform
		if node is MeshInstance3D and node.mesh:
			var a: AABB = t * node.mesh.get_aabb()
			if first: out = a; first = false
			else: out = out.merge(a)
		for c in node.get_children(): stack.append([c, t])
	return out
func tree_str(n: Node, d := 0) -> String:
	var s := "  ".repeat(d) + n.name + " (" + n.get_class() + ")\n"
	for c in n.get_children(): s += tree_str(c, d + 1)
	return s
func _init():
	var args := OS.get_cmdline_user_args()
	var mode := args[0]
	for p in args.slice(1):
		var ps: PackedScene = load(p)
		if ps == null: print("FAIL ", p); continue
		var inst := ps.instantiate()
		if mode == "aabb":
			var a := aabb_of(inst, Transform3D.IDENTITY.inverse())
			# root transform included in aabb_of; fine
			print("%-60s pos=%s size=%s" % [p.get_file(), a.position.snapped(Vector3.ONE*0.01), a.size.snapped(Vector3.ONE*0.01)])
		elif mode == "tree":
			print(tree_str(inst))
			var ap := inst.find_child("AnimationPlayer", true, false)
			if ap: print("anims: ", ap.get_animation_list(), "\n")
		inst.free()
	quit()

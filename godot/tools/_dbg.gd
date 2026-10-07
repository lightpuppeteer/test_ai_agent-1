extends Node
func _ready():
	for id in ["character-female-f", "character-male-b"]:
		var m: Node3D = Props.model("mini-characters/" + id)
		var sk: Skeleton3D = m.find_child("Skeleton3D", true, false)
		print("== ", id, " skeleton xf in model: ", Props._relative_xf(m, sk))
		for b in sk.get_bone_count():
			print(b, " ", sk.get_bone_name(b), " parent=", sk.get_bone_parent(b), " rest_global=", sk.get_bone_global_rest(b).origin, " rot=", sk.get_bone_global_rest(b).basis.get_euler())
		for mi in Props._mesh_instances(m):
			var arr = mi.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var w = arr[Mesh.ARRAY_WEIGHTS]
			var per := {}
			for i in v.size():
				var bi: int = bones[i * 4]
				if not per.has(bi): per[bi] = AABB(v[i], Vector3.ZERO)
				else: per[bi] = per[bi].expand(v[i])
			print(" mesh ", mi.name, " xf ", Props._relative_xf(m, mi).origin, " verts ", v.size())
			for bi in per: print("   bone ", sk.get_bone_name(bi), " ", per[bi])
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		var a := ap.get_animation("idle")
		for t in a.get_track_count(): print("  track ", a.track_get_path(t), " type ", a.track_get_type(t))
		m.free()
	get_tree().quit()

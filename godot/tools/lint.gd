extends Node
## Dev tool: loads every script so parse/compile errors show up in the log.
func _ready() -> void:
	var bad := 0
	var stack := ["res://scripts", "res://tools"]
	while stack.size():
		var d: String = stack.pop_back()
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				var s = load(d.path_join(f))
				if s == null or not s.can_instantiate():
					bad += 1
					print("BAD ", d.path_join(f))
		for sd in DirAccess.get_directories_at(d):
			stack.append(d.path_join(sd))
	print("lint done, bad=", bad)
	get_tree().quit()

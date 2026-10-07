class_name Chapter
extends Node3D
## Base class for a story chapter. A chapter picks the time of day, where you
## start, and adds its own things to the island (memory spots, props, villager
## lines…). Everything it adds is a child of the chapter, so leaving a chapter
## cleans it up.

signal completed

var id := "chapter"
var title := "Chapter"
var subtitle := ""
var preset := "day"
var spawn := Vector3.ZERO
var spawn_yaw := 0.0
var memories: Array[MemorySpot] = []


## Called once when the chapter starts. Override to add content.
func build() -> void:
	pass


func add_memory(pos: Vector3, mem_title: String, lines: Array[String]) -> MemorySpot:
	var m := MemorySpot.new()
	m.title = mem_title
	m.lines = lines
	add_child(m)
	if Game.terrain:
		pos.y = maxf(pos.y, Game.terrain.height_at(pos.x, pos.z))
	m.global_position = pos
	m.remembered.connect(_on_remembered)
	memories.append(m)
	return m


func _on_remembered(_m: MemorySpot) -> void:
	var seen := memories.filter(func(x: MemorySpot) -> bool: return x.seen).size()
	if Game.hud:
		Game.hud.toast("Memories found: %d / %d" % [seen, memories.size()])
	if seen == memories.size():
		completed.emit()

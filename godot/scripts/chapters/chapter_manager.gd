class_name ChapterManager
extends Node
## Loads chapters by id. Add a script to CHAPTERS to add a chapter.

const CHAPTERS := {
	"shore": preload("res://scripts/chapters/shore_chapter.gd"),
}

var current: Chapter = null


func _ready() -> void:
	Game.chapters = self


func start(chapter_id: String, show_title: bool = true) -> Chapter:
	if current:
		current.queue_free()
		current = null
	var script: GDScript = CHAPTERS.get(chapter_id)
	if script == null:
		push_error("Unknown chapter " + chapter_id)
		return null
	current = script.new()
	current.name = "Chapter_" + chapter_id
	get_parent().add_child(current)
	current.build()
	if Game.atmosphere:
		Game.atmosphere.set_preset(Game.options.get("preset", current.preset))
	var p: Person = Game.player
	if p:
		var pos := current.spawn
		if Game.terrain:
			pos.y = Game.terrain.height_at(pos.x, pos.z) + 0.1
		p.teleport(pos, current.spawn_yaw)
		if Game.partner:
			Game.partner.teleport(pos + Vector3(1.4, 0.1, 1.0), current.spawn_yaw)
	if Game.camera_rig:
		Game.camera_rig.yaw = current.spawn_yaw
		Game.camera_rig.snap()
	if show_title and Game.hud:
		Game.hud.show_title(current.title, current.subtitle)
	return current

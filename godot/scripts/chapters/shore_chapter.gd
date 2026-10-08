extends Chapter
## Chapter 1: a sunny day by the sea (the story itself runs as quests).


func _init() -> void:
	id = "shore"
	title = "A Day by the Sea"
	subtitle = "Chapter 1"
	preset = "day"
	spawn = Vector3(2.0, 2.2, 13.4)
	spawn_yaw = PI   # facing the sea


func build() -> void:
	# The story now lives in the quests (scripts/quests/quest_data.gd).
	pass

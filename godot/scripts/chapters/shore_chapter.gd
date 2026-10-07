extends Chapter
## Chapter 1: a sunny day by the sea. Free roam with a few memory spots to find.
## The texts are placeholders: write your own moments here.


func _init() -> void:
	id = "shore"
	title = "A Day by the Sea"
	subtitle = "Chapter 1"
	preset = "day"
	spawn = Vector3(2.0, 2.2, 13.4)
	spawn_yaw = PI   # facing the sea


func build() -> void:
	add_memory(Vector3(-9.9, 0, 30.5), "Our first beach day", [
		"The sand was so hot we ran all the way to the water.",
		"(Write your own memory here.)",
	])
	add_memory(Vector3(0.0, 0, -3.0), "Coffee in the square", [
		"Two coffees, one pastel de nata, and a whole afternoon of talking.",
	])
	add_memory(Vector3(9.0, 0, -47.5), "Sunset on the hill", [
		"We watched the sky turn pink and didn't say a word.",
	])
	add_memory(Vector3(34.0, 1.25, 44.0), "The pier", [
		"You dared me to jump in. I didn't. (Yet.)",
	])
	completed.connect(func() -> void:
		if Game.hud:
			Game.hud.show_title("♡", "Every memory of this chapter found", 3.0))

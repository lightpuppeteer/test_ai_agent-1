class_name CinemaScreen
extends Node3D
## The big screen. play("horror" | "comedy" | "drama" | "off").

const TITLES := {
	"horror": "THE THING IN THE ATTIC",
	"comedy": "PIZZA COPS 3",
	"drama": "A DOG NAMED SUNDAY",
}

var mat: ShaderMaterial
var _t := 0.0
var _light: OmniLight3D
var _title: Label3D
var playing := "off"


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(10.0, 4.6)
	mi.mesh = q
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/movie.gdshader")
	mi.material_override = mat
	add_child(mi)
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0, 3.0)
	_light.omni_range = 14.0
	_light.light_energy = 0.4
	add_child(_light)
	_title = Label3D.new()
	_title.font_size = 120
	_title.pixel_size = 0.006
	_title.outline_size = 16
	_title.position = Vector3(0, 0, 0.05)
	_title.modulate.a = 0.0
	add_child(_title)


func play(genre: String) -> void:
	playing = genre
	mat.set_shader_parameter("mode", {"horror": 1, "comedy": 2, "drama": 3}.get(genre, 0))
	_t = 0.0
	if TITLES.has(genre):
		if Game.hud:
			_title.font = Game.hud._title_font
		_title.text = TITLES[genre]
		var tw := create_tween()
		tw.tween_property(_title, "modulate:a", 1.0, 0.5)
		tw.tween_interval(2.0)
		tw.tween_property(_title, "modulate:a", 0.0, 0.8)
		Sound.override_music("")
	# The room lights dim while a movie plays.
	var room := get_parent()
	for c in room.get_children():
		if c is OmniLight3D:
			var tw2 := create_tween()
			tw2.tween_property(c, "light_energy", 0.15 if genre != "off" else 0.9, 1.5)


func _process(delta: float) -> void:
	_t += delta
	mat.set_shader_parameter("t", _t)
	var col := Color(0.6, 0.1, 0.12)
	match playing:
		"horror":
			col = Color(0.35, 0.35, 0.6) * (0.6 + 0.4 * randf())
		"comedy":
			col = Color(1.0, 0.8, 0.4)
		"drama":
			col = Color(0.4, 0.5, 0.8)
	_light.light_color = col
	_light.light_energy = 0.4 if playing == "off" else 1.4

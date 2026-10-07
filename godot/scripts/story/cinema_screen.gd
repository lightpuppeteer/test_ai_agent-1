class_name CinemaScreen
extends Node3D
## The big screen. play("horror" | "comedy" | "drama" | "off"). The films are
## little 2D cartoons (MovieReel) rendered into a SubViewport.

const TITLES := {
	"horror": "THE THING IN THE ATTIC",
	"comedy": "PIZZA COPS 3",
	"drama": "A DOG NAMED SUNDAY",
}

var _vp: SubViewport
var _reel: MovieReel
var _light: OmniLight3D
var _pop_t := 2.0
var playing := "off"


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(MovieReel.W), int(MovieReel.H))
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_reel = MovieReel.new()
	_vp.add_child(_reel)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(10.0, 4.6)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _vp.get_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Dark frame around the screen.
	add_child(Props3D.blocks([Props3D.b(Vector3(10.5, 5.1, 0.12), Vector3(0, 0, -0.08), Color(0.08, 0.06, 0.08), {"bevel": 0.05})]))
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0, 3.0)
	_light.omni_range = 14.0
	_light.light_energy = 0.4
	add_child(_light)


func play(genre: String) -> void:
	playing = genre
	if _reel.font == null and Game.hud:
		_reel.font = Game.hud._title_font
		_reel.small_font = Game.hud._bold_font
	_reel.play(genre)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if genre != "off" else SubViewport.UPDATE_ONCE
	if TITLES.has(genre):
		Sound.override_music("")
	# The room lights dim while a movie plays.
	var room := get_parent()
	for c in room.get_children():
		if c is OmniLight3D:
			var tw2 := create_tween()
			tw2.tween_property(c, "light_energy", 0.15 if genre != "off" else 0.9, 1.5)


func _process(delta: float) -> void:
	var col := Color(0.6, 0.1, 0.12)
	match playing:
		"horror":
			col = Color(0.35, 0.35, 0.6) * (0.6 + 0.4 * randf())
		"comedy":
			col = Color(1.0, 0.8, 0.4)
		"drama":
			col = Color(1.0, 0.65, 0.55)
	_light.light_color = col
	_light.light_energy = 0.4 if playing == "off" else 1.4
	if playing == "off":
		return
	# Popcorn hops out of the bucket now and then (nobody can eat it neatly in the dark).
	_pop_t -= delta
	if _pop_t <= 0.0:
		_pop_t = randf_range(0.5, 1.3)
		for p in [Game.player, Game.partner]:
			var person := p as Person
			if person and person.has_accessory("popcorn"):
				var at: Variant = person.accessory_point("popcorn")
				if at != null:
					FX.popcorn_pop(get_parent(), at, randi_range(1, 3))

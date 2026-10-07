class_name TitleScreen
extends CanvasLayer
## Opening screen: the camera drifts around the island while the title floats
## over it. Any key / click starts the chapter.

signal started

@export var game_title := "Our Little Island"
@export var tagline := "Tatiana & Marco · a year of memories"

var _cam: Camera3D
var _t := 0.0
var _root: Control
var _hint: Label
var _done := false


func _ready() -> void:
	layer = 20
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.far = 1500.0
	_cam.attributes = CameraAttributesPractical.new()   # no far blur for wide shots
	add_child(_cam)
	_cam.current = true
	if Game.player:
		Game.player.input_enabled = false
	Sound.override_music("title")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# Soft vignette at the bottom so the text reads on any background.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.88, 0.0))
	g.set_color(1, Color(1.0, 0.92, 0.82, 0.35))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.45)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.0
	vb.anchor_right = 1.0
	vb.anchor_top = 0.56
	vb.anchor_bottom = 0.56
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vb)
	var hud: HUD = Game.hud
	var title := Label.new()
	title.text = game_title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", hud._title_font)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(1, 0.99, 0.96))
	title.add_theme_color_override("font_outline_color", Color(0.93, 0.5, 0.45))
	title.add_theme_constant_override("outline_size", 28)
	title.add_theme_color_override("font_shadow_color", Color(0.4, 0.25, 0.2, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 8)
	vb.add_child(title)
	var tag := Label.new()
	tag.text = tagline
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_override("font", hud._bold_font)
	tag.add_theme_font_size_override("font_size", 32)
	tag.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	tag.add_theme_color_override("font_outline_color", Color(0.55, 0.36, 0.3, 0.9))
	tag.add_theme_constant_override("outline_size", 10)
	vb.add_child(tag)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vb.add_child(spacer)
	_hint = Label.new()
	_hint.text = "press any key"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_override("font", hud._title_font)
	_hint.add_theme_font_size_override("font_size", 28)
	_hint.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	_hint.add_theme_color_override("font_outline_color", Color(0.93, 0.5, 0.45))
	_hint.add_theme_constant_override("outline_size", 10)
	vb.add_child(_hint)
	if Game.hud:
		Game.hud.root.visible = false


func _process(delta: float) -> void:
	_t += delta
	var a := _t * 0.05 + 0.6
	var center := Vector3(0, 2, -6)
	_cam.global_position = center + Vector3(sin(a) * 78.0, 34.0 + sin(_t * 0.2) * 3.0, cos(a) * 78.0)
	_cam.look_at(center + Vector3(0, -6, 0))
	_hint.modulate.a = 0.55 + 0.45 * sin(_t * 3.0)


func _input(event: InputEvent) -> void:
	if _done:
		return
	var go: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed)
	if go:
		get_viewport().set_input_as_handled()
		start()


func start() -> void:
	_done = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	await tw.finished
	if Game.camera_rig:
		Game.camera_rig.camera.current = true
		Game.camera_rig.snap()
	if Game.player:
		Game.player.input_enabled = true
	if Game.hud:
		Game.hud.root.visible = true
	Sound.override_music("")
	Sound.play_ui("open")
	started.emit()
	queue_free()

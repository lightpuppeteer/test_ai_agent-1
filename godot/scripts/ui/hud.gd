class_name HUD
extends CanvasLayer
## Cozy UI: interaction prompt bubble, Animal-Crossing-style dialogue box,
## toasts, chapter title card, controls help and the car speed pill.

signal dialogue_closed

const FONT_TITLE := preload("res://assets/fonts/Fredoka.ttf")
const FONT_BODY := preload("res://assets/fonts/Nunito.ttf")
const CREAM := Color(1.0, 0.975, 0.91, 0.97)
const INK := Color(0.36, 0.27, 0.2)
const ACCENT := Color(0.98, 0.62, 0.45)

var root: Control
var prompt: PanelContainer
var prompt_label: Label
var prompt_key: Label
var dialogue: Control
var dlg_name: Label
var dlg_name_panel: PanelContainer
var dlg_text: RichTextLabel
var dlg_arrow: Label
var toast_box: VBoxContainer
var title_card: Control
var title_label: Label
var subtitle_label: Label
var help: PanelContainer
var speed_pill: PanelContainer
var speed_label: Label

var _focus: Interactable = null
var _dlg_lines: Array = []
var _dlg_index := 0
var _dlg_typing := false
var _dlg_tween: Tween
var _title_font: FontVariation
var _body_font: FontVariation
var _bold_font: FontVariation
var _fps: Label


func _ready() -> void:
	Game.hud = self
	layer = 10
	_title_font = FontVariation.new()
	_title_font.base_font = FONT_TITLE
	_title_font.variation_opentype = {"wght": 600}
	_body_font = FontVariation.new()
	_body_font.base_font = FONT_BODY
	_body_font.variation_opentype = {"wght": 600}
	_bold_font = FontVariation.new()
	_bold_font.base_font = FONT_BODY
	_bold_font.variation_opentype = {"wght": 800}
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_prompt()
	_build_dialogue()
	_build_toasts()
	_build_title()
	_build_help()
	_build_speed()
	_fps = _label("", 16, INK)
	_fps.anchor_left = 1.0
	_fps.anchor_right = 1.0
	_fps.offset_left = -120
	_fps.offset_top = 8
	_fps.visible = false
	root.add_child(_fps)
	if Game.player:
		_hook_player(Game.player)
	else:
		Game.player_registered.connect(_hook_player)


func _hook_player(p: Node) -> void:
	p.focus_changed.connect(func(it: Interactable) -> void: _focus = it)


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

func _panel_style(bg: Color, radius: int, pad: Vector2 = Vector2(18, 10), border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	sb.shadow_color = Color(0.25, 0.18, 0.1, 0.18)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(3)
	return sb


func _label(text: String, size: int, color: Color = INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else _body_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_prompt() -> void:
	prompt = PanelContainer.new()
	prompt.add_theme_stylebox_override("panel", _panel_style(CREAM, 22, Vector2(10, 6)))
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	prompt.add_child(hb)
	var key := PanelContainer.new()
	key.add_theme_stylebox_override("panel", _panel_style(ACCENT, 14, Vector2(10, 1)))
	prompt_key = _label("E", 20, Color.WHITE, _title_font)
	key.add_child(prompt_key)
	hb.add_child(key)
	prompt_label = _label("Sit", 22, INK, _bold_font)
	hb.add_child(prompt_label)
	prompt.visible = false
	root.add_child(prompt)


func _build_dialogue() -> void:
	dialogue = Control.new()
	dialogue.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dialogue)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style(CREAM, 40, Vector2(48, 30)))
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -420
	box.offset_right = 420
	box.offset_top = -230
	box.offset_bottom = -40
	dialogue.add_child(box)
	dlg_text = RichTextLabel.new()
	dlg_text.bbcode_enabled = true
	dlg_text.fit_content = true
	dlg_text.scroll_active = false
	dlg_text.add_theme_font_override("normal_font", _body_font)
	dlg_text.add_theme_font_override("bold_font", _bold_font)
	dlg_text.add_theme_font_size_override("normal_font_size", 27)
	dlg_text.add_theme_font_size_override("bold_font_size", 27)
	dlg_text.add_theme_color_override("default_color", INK)
	dlg_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(dlg_text)
	dlg_name_panel = PanelContainer.new()
	dlg_name_panel.add_theme_stylebox_override("panel", _panel_style(ACCENT, 20, Vector2(22, 6)))
	dlg_name_panel.anchor_left = 0.5
	dlg_name_panel.anchor_right = 0.5
	dlg_name_panel.anchor_top = 1.0
	dlg_name_panel.anchor_bottom = 1.0
	dlg_name_panel.offset_left = -400
	dlg_name_panel.offset_top = -255
	dlg_name_panel.rotation = deg_to_rad(-3.0)
	dlg_name = _label("Name", 24, Color.WHITE, _title_font)
	dlg_name_panel.add_child(dlg_name)
	dialogue.add_child(dlg_name_panel)
	dlg_arrow = _label("▼", 22, ACCENT, _title_font)
	dlg_arrow.anchor_left = 0.5
	dlg_arrow.anchor_right = 0.5
	dlg_arrow.anchor_top = 1.0
	dlg_arrow.anchor_bottom = 1.0
	dlg_arrow.offset_left = -12
	dlg_arrow.offset_top = -66
	dialogue.add_child(dlg_arrow)
	dialogue.visible = false


func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.offset_left = -300
	toast_box.offset_right = 300
	toast_box.offset_top = 28
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_box.add_theme_constant_override("separation", 8)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)


func _build_title() -> void:
	title_card = VBoxContainer.new()
	title_card.set_anchors_preset(Control.PRESET_CENTER)
	title_card.anchor_top = 0.3
	title_card.anchor_bottom = 0.3
	title_card.offset_left = -500
	title_card.offset_right = 500
	title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(title_card as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	title_label = _label("", 72, Color(1, 0.99, 0.95), _title_font)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_outline_color", Color(0.45, 0.32, 0.25, 0.85))
	title_label.add_theme_constant_override("outline_size", 14)
	subtitle_label = _label("", 30, Color(1, 0.97, 0.9), _bold_font)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_color_override("font_outline_color", Color(0.45, 0.32, 0.25, 0.8))
	subtitle_label.add_theme_constant_override("outline_size", 10)
	title_card.add_child(title_label)
	title_card.add_child(subtitle_label)
	title_card.modulate.a = 0.0
	root.add_child(title_card)


func _build_help() -> void:
	help = PanelContainer.new()
	help.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.975, 0.91, 0.88), 22, Vector2(20, 14)))
	help.position = Vector2(24, 24)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	help.add_child(vb)
	vb.add_child(_label("Controls", 22, ACCENT.darkened(0.15), _title_font))
	for line in [
		"WASD  walk · Shift  run · Space  jump",
		"E  sit / lie down / drive / talk",
		"Drag  orbit camera · Wheel  zoom",
		"In the car: W/S  drive · A/D  steer",
		"Space  handbrake · E  get out",
		"O  outfit · T  time of day · F12  photo",
		"H  hide this",
	]:
		vb.add_child(_label(line, 17))
	root.add_child(help)


func _build_speed() -> void:
	speed_pill = PanelContainer.new()
	speed_pill.add_theme_stylebox_override("panel", _panel_style(CREAM, 24, Vector2(20, 8)))
	speed_pill.anchor_left = 1.0
	speed_pill.anchor_right = 1.0
	speed_pill.anchor_top = 1.0
	speed_pill.anchor_bottom = 1.0
	speed_pill.offset_left = -190
	speed_pill.offset_top = -86
	speed_label = _label("0 km/h", 28, INK, _title_font)
	speed_pill.add_child(speed_label)
	speed_pill.visible = false
	root.add_child(speed_pill)


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func toast(text: String, duration: float = 2.4) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(CREAM, 22, Vector2(22, 8)))
	var l := _label(text, 21, INK, _bold_font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.modulate.a = 0.0
	toast_box.add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(duration)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func show_title(title: String, subtitle: String = "", hold: float = 3.0) -> void:
	title_label.text = title
	subtitle_label.text = subtitle
	var tw := create_tween()
	tw.tween_property(title_card, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(hold)
	tw.tween_property(title_card, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_SINE)


## Shows lines one by one (E / click / Space to continue). Returns when closed.
func say(speaker: String, lines: Array, color: Color = ACCENT) -> void:
	_dlg_lines = lines
	_dlg_index = 0
	dlg_name.text = speaker
	dlg_name_panel.visible = speaker != ""
	(dlg_name_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = color
	dialogue.visible = true
	dialogue.modulate.a = 0.0
	create_tween().tween_property(dialogue, "modulate:a", 1.0, 0.15)
	_show_line()
	await dialogue_closed


func is_dialogue_open() -> bool:
	return dialogue.visible


func _show_line() -> void:
	dlg_text.text = str(_dlg_lines[_dlg_index])
	dlg_text.visible_ratio = 0.0
	_dlg_typing = true
	if _dlg_tween:
		_dlg_tween.kill()
	var chars := maxf(dlg_text.get_total_character_count(), 1.0)
	_dlg_tween = create_tween()
	_dlg_tween.tween_property(dlg_text, "visible_ratio", 1.0, chars / 45.0)
	_dlg_tween.tween_callback(func() -> void: _dlg_typing = false)


func _advance() -> void:
	if _dlg_typing:
		_dlg_tween.kill()
		dlg_text.visible_ratio = 1.0
		_dlg_typing = false
		return
	_dlg_index += 1
	if _dlg_index >= _dlg_lines.size():
		dialogue.visible = false
		dialogue_closed.emit()
	else:
		_show_line()


func _input(event: InputEvent) -> void:
	if dialogue.visible:
		var adv: bool = event.is_action_pressed("interact") or event.is_action_pressed("jump") \
				or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		if adv:
			get_viewport().set_input_as_handled()
			_advance()
		return
	if event.is_action_pressed("toggle_help"):
		help.visible = not help.visible
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F3:
		_fps.visible = not _fps.visible


func _process(_delta: float) -> void:
	dlg_arrow.visible = dialogue.visible and not _dlg_typing
	dlg_arrow.offset_top = -66 + sin(Time.get_ticks_msec() * 0.008) * 4.0
	# Prompt bubble over the focused thing.
	var cam := get_viewport().get_camera_3d()
	if _focus and is_instance_valid(_focus) and cam and not dialogue.visible:
		var wp := _focus.global_position + Vector3(0, 1.6, 0)
		if not cam.is_position_behind(wp):
			prompt_label.text = _focus.prompt
			prompt.visible = true
			prompt.reset_size()
			var sp := cam.unproject_position(wp)
			prompt.position = sp - Vector2(prompt.size.x * 0.5, prompt.size.y)
		else:
			prompt.visible = false
	else:
		prompt.visible = false
	if _fps.visible:
		_fps.text = "%d fps" % Engine.get_frames_per_second()
	# Speed while driving.
	var p = Game.player
	if p and p.car:
		speed_pill.visible = true
		speed_label.text = "%d km/h" % roundi(absf(p.car.speed_kmh()))
	else:
		speed_pill.visible = false

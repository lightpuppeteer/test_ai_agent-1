class_name HUD
extends CanvasLayer
## Cozy UI: interaction prompt bubble, Animal-Crossing-style dialogue box,
## toasts, chapter title card, controls help and the car speed pill.

signal dialogue_closed
signal choice_made(index: int)

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
var _voice := 1.0
var _last_chars := 0
var tracker: VBoxContainer
var quest_log: PanelContainer
var _log_list: VBoxContainer
var choice_box: PanelContainer
var minimap: MiniMap
var _choice_list: VBoxContainer
var _pending_choices: Array = []
var _choice_idx := 0
var _choices_shown := false
var _fade: ColorRect
var _bars: Array[ColorRect] = []
var _popup: PanelContainer
var _popup_label: Label
var _popup_title: Label


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
	_build_tracker()
	_build_choices()
	minimap = MiniMap.new()
	root.add_child(minimap)
	minimap.setup(self)
	_build_cinematic()
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
	p.focus_changed.connect(func(it: Interactable) -> void:
		if it and it != _focus:
			Sound.play("ui_blip", -20.0)
		_focus = it)


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
	dlg_name_panel.offset_right = -300
	dlg_name_panel.offset_top = -258
	dlg_name_panel.offset_bottom = -214
	dlg_name_panel.grow_horizontal = Control.GROW_DIRECTION_END
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


const HELP_KEYS := [
	"WASD  walk · Shift  run · Space  jump",
	"E  sit / lie down / drive / talk",
	"Drag  orbit camera · Wheel  zoom",
	"In the car: W/S  drive · A/D  steer",
	"Space  handbrake · E  get out",
	"O  her outfit · Shift+O  his outfit",
	"T  time of day · Q  quests · N  map zoom",
	"F12  photo · M  music · H  hide this",
]
const HELP_PAD := [
	"L-stick  walk · R1  run · □  jump",
	"✕  talk / sit / drive · ○  get up",
	"R-stick  camera",
	"In the car: R2  gas · L2  brake / reverse",
	"□  handbrake · ○  get out",
	"L1  her outfit · ◀  his outfit",
	"▲  time of day · ▼  music · ▶  map zoom",
	"△  quests · Create  photo · Options  hide this",
]
var _help_list: VBoxContainer


func _build_help() -> void:
	help = PanelContainer.new()
	help.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.975, 0.91, 0.88), 22, Vector2(20, 14)))
	help.position = Vector2(24, 24)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_list = VBoxContainer.new()
	_help_list.add_theme_constant_override("separation", 2)
	help.add_child(_help_list)
	root.add_child(help)
	_fill_help(Game.gamepad_active)
	Game.input_device_changed.connect(_fill_help)


func _fill_help(pad: bool) -> void:
	for c in _help_list.get_children():
		c.queue_free()
	_help_list.add_child(_label("Controls", 22, ACCENT.darkened(0.15), _title_font))
	for line in (HELP_PAD if pad else HELP_KEYS):
		_help_list.add_child(_label(line, 17))


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
func say(speaker: String, lines: Array, color: Color = ACCENT, voice: float = 1.0) -> void:
	_start_dialogue(speaker, lines, color, voice)
	await dialogue_closed


## Shows a line, then the choices; returns the chosen index.
func ask(speaker: String, line: String, options: Array, color: Color = ACCENT, voice: float = 1.0) -> int:
	_start_dialogue(speaker, [line], color, voice)
	_pending_choices = options
	var i: int = await choice_made
	return i


func _start_dialogue(speaker: String, lines: Array, color: Color, voice: float) -> void:
	_pending_choices = []
	_choices_shown = false
	choice_box.visible = false
	_voice = voice
	_dlg_lines = lines
	_dlg_index = 0
	dlg_name.text = speaker
	dlg_name_panel.visible = speaker != ""
	(dlg_name_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = color
	dialogue.visible = true
	dialogue.modulate.a = 0.0
	create_tween().tween_property(dialogue, "modulate:a", 1.0, 0.15)
	_show_line()


func is_dialogue_open() -> bool:
	return dialogue.visible


func _show_line() -> void:
	dlg_text.text = str(_dlg_lines[_dlg_index])
	dlg_text.visible_ratio = 0.0
	_last_chars = 0
	_dlg_typing = true
	if _dlg_tween:
		_dlg_tween.kill()
	var chars := maxf(dlg_text.get_total_character_count(), 1.0)
	_dlg_tween = create_tween()
	_dlg_tween.tween_property(dlg_text, "visible_ratio", 1.0, chars / 45.0)
	_dlg_tween.tween_callback(func() -> void:
		_dlg_typing = false
		_maybe_show_choices())


func _advance() -> void:
	if _dlg_typing:
		_dlg_tween.kill()
		dlg_text.visible_ratio = 1.0
		_dlg_typing = false
		_maybe_show_choices()
		return
	if not _pending_choices.is_empty():
		return
	_dlg_index += 1
	if _dlg_index >= _dlg_lines.size():
		dialogue.visible = false
		dialogue_closed.emit()
	else:
		_show_line()


func _input(event: InputEvent) -> void:
	if _choices_shown:
		if event.is_action_pressed("ui_up_choice") or event.is_action_pressed("move_forward"):
			_select_choice(_choice_idx - 1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down_choice") or event.is_action_pressed("move_back"):
			_select_choice(_choice_idx + 1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact") or event.is_action_pressed("jump") \
				or (event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode in [KEY_ENTER, KEY_KP_ENTER]):
			get_viewport().set_input_as_handled()
			_confirm_choice()
		elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode >= KEY_1 and (event as InputEventKey).physical_keycode <= KEY_9:
			var k := int((event as InputEventKey).physical_keycode - KEY_1)
			if k < _pending_choices.size():
				_select_choice(k)
				_confirm_choice()
		return
	if dialogue.visible:
		var adv: bool = event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("cancel") \
				or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		if adv:
			get_viewport().set_input_as_handled()
			_advance()
		return
	if event.is_action_pressed("toggle_help"):
		help.visible = not help.visible
	elif event.is_action_pressed("quest_log"):
		_refresh_log()
		quest_log.visible = not quest_log.visible
		Sound.play_ui("open" if quest_log.visible else "close")
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F3:
		_fps.visible = not _fps.visible


func _process(_delta: float) -> void:
	dlg_arrow.visible = dialogue.visible and not _dlg_typing
	# Animalese-style babble while the text types out.
	if dialogue.visible and _dlg_typing:
		var n := int(dlg_text.visible_ratio * dlg_text.get_total_character_count())
		if n - _last_chars >= 2:
			var txt := dlg_text.get_parsed_text()
			var ch := txt.substr(clampi(n - 1, 0, txt.length() - 1), 1)
			_last_chars = n
			if ch.strip_edges() != "" and ch not in [".", ",", "!", "?", "…", "'"]:
				Sound.babble(ch, _voice)
	dlg_arrow.offset_top = -66 + sin(Time.get_ticks_msec() * 0.008) * 4.0
	# Prompt bubble over the focused thing.
	var cam := get_viewport().get_camera_3d()
	if _focus and is_instance_valid(_focus) and cam and not dialogue.visible:
		var wp := _focus.global_position + Vector3(0, 1.6, 0)
		if not cam.is_position_behind(wp):
			prompt_label.text = _focus.prompt
			prompt_key.text = Game.glyph("interact")
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


# ---------------------------------------------------------------------------
# Quests
# ---------------------------------------------------------------------------

func _build_tracker() -> void:
	tracker = VBoxContainer.new()
	tracker.anchor_left = 1.0
	tracker.anchor_right = 1.0
	tracker.offset_left = -380
	tracker.offset_right = -24
	tracker.offset_top = 24
	tracker.add_theme_constant_override("separation", 8)
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tracker)
	quest_log = PanelContainer.new()
	quest_log.add_theme_stylebox_override("panel", _panel_style(CREAM, 32, Vector2(36, 26)))
	quest_log.anchor_left = 0.5
	quest_log.anchor_right = 0.5
	quest_log.anchor_top = 0.5
	quest_log.anchor_bottom = 0.5
	quest_log.offset_left = -340
	quest_log.offset_right = 340
	quest_log.offset_top = -250
	quest_log.offset_bottom = 250
	quest_log.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	quest_log.add_child(vb)
	vb.add_child(_label("Quests", 34, ACCENT.darkened(0.15), _title_font))
	_log_list = VBoxContainer.new()
	_log_list.add_theme_constant_override("separation", 6)
	vb.add_child(_log_list)
	root.add_child(quest_log)
	if Game.quests:
		Game.quests.changed.connect(refresh_tracker)
	else:
		_hook_quests.call_deferred()


func _hook_quests() -> void:
	if Game.quests:
		Game.quests.changed.connect(refresh_tracker)
		refresh_tracker()


func refresh_tracker() -> void:
	for c in tracker.get_children():
		c.queue_free()
	var qm = Game.quests
	if qm == null:
		return
	for id in qm.active_ids():
		var q: Dictionary = qm.quests[id]
		var s: Dictionary = qm.current_step(id)
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.975, 0.91, 0.9), 18, Vector2(16, 10)))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		p.add_child(vb)
		vb.add_child(_label("✿ " + q["title"], 20, ACCENT.darkened(0.2), _title_font))
		var t := str(s.get("text", ""))
		var prog: String = qm.step_progress(id)
		if prog != "":
			t += "  (" + prog + ")"
		if t != "":
			var l := _label(t, 17, INK)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 320
			vb.add_child(l)
		tracker.add_child(p)
	if qm.flags.get("all_done", false) and qm.active_ids().is_empty():
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.975, 0.91, 0.9), 18, Vector2(16, 10)))
		var vb := VBoxContainer.new()
		p.add_child(vb)
		vb.add_child(_label("♡ Our island", 20, ACCENT.darkened(0.2), _title_font))
		var l := _label("Wander anywhere together and revisit all your places.", 17, INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 320
		vb.add_child(l)
		tracker.add_child(p)
	if quest_log.visible:
		_refresh_log()


func _refresh_log() -> void:
	for c in _log_list.get_children():
		c.queue_free()
	var qm = Game.quests
	if qm == null:
		return
	var any := false
	for q in QuestData.QUESTS:
		var st: String = qm.status(q["id"])
		if st == "":
			continue
		any = true
		var mark := "✔ " if st == "done" else "✿ "
		var col := INK.lightened(0.35) if st == "done" else INK
		_log_list.add_child(_label(mark + q["title"], 22, col, _bold_font))
		if st == "active":
			var s: Dictionary = qm.current_step(q["id"])
			_log_list.add_child(_label("     " + str(s.get("text", "")), 18, INK.lightened(0.15)))
	if not any:
		_log_list.add_child(_label("No quests yet — try talking to the neighbours!", 20, INK))
	_log_list.add_child(_label("(Q to close)", 16, INK.lightened(0.4)))


# ---------------------------------------------------------------------------
# Choices
# ---------------------------------------------------------------------------

func _build_choices() -> void:
	choice_box = PanelContainer.new()
	choice_box.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.985, 0.95, 0.98), 26, Vector2(22, 14), Color(0.98, 0.62, 0.45, 0.9)))
	choice_box.anchor_left = 0.5
	choice_box.anchor_right = 0.5
	choice_box.anchor_top = 1.0
	choice_box.anchor_bottom = 1.0
	choice_box.offset_left = -60
	choice_box.offset_right = 470
	choice_box.offset_bottom = -250
	choice_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	choice_box.offset_top = -260
	choice_box.visible = false
	_choice_list = VBoxContainer.new()
	_choice_list.add_theme_constant_override("separation", 6)
	choice_box.add_child(_choice_list)
	root.add_child(choice_box)


func _maybe_show_choices() -> void:
	if _pending_choices.is_empty() or _choices_shown or _dlg_index < _dlg_lines.size() - 1:
		return
	_choices_shown = true
	for c in _choice_list.get_children():
		_choice_list.remove_child(c)
		c.queue_free()
	for i in _pending_choices.size():
		var l := _label("", 22, INK, _bold_font)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 480
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseMotion:
				_select_choice(i)
			elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_select_choice(i)
				_confirm_choice())
		_choice_list.add_child(l)
	choice_box.visible = true
	choice_box.modulate.a = 0.0
	create_tween().tween_property(choice_box, "modulate:a", 1.0, 0.15)
	_select_choice(0)


func _select_choice(i: int) -> void:
	if _pending_choices.is_empty():
		return
	var n := _pending_choices.size()
	var prev := _choice_idx
	_choice_idx = posmod(i, n)
	var labels := _choice_list.get_children()
	for k in mini(labels.size(), n):
		var l := labels[k] as Label
		var sel := k == _choice_idx
		l.text = ("▶ " if sel else "    ") + str(_pending_choices[k])
		l.add_theme_color_override("font_color", ACCENT.darkened(0.25) if sel else INK)
	if prev != _choice_idx:
		Sound.play("ui_blip", -16.0)


func _confirm_choice() -> void:
	var i := _choice_idx
	_pending_choices = []
	_choices_shown = false
	choice_box.visible = false
	dialogue.visible = false
	Sound.play_ui("step")
	choice_made.emit(i)
	dialogue_closed.emit()


# ---------------------------------------------------------------------------
# Cinematics: fades, letterbox bars, achievement pop-ups
# ---------------------------------------------------------------------------

func _build_cinematic() -> void:
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.05, 0.04, 0.06)
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else 0.0
		bar.offset_bottom = 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
		_bars.append(bar)
	_popup = PanelContainer.new()
	_popup.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.97, 0.88, 0.98), 30, Vector2(40, 22), Color(1.0, 0.75, 0.3)))
	_popup.anchor_left = 0.5
	_popup.anchor_right = 0.5
	_popup.anchor_top = 0.22
	_popup.anchor_bottom = 0.22
	_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	_popup.add_child(vb)
	_popup_title = _label("", 34, Color(0.85, 0.5, 0.1), _title_font)
	_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_popup_title)
	_popup_label = _label("", 20, INK, _bold_font)
	_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_popup_label)
	_popup.visible = false
	root.add_child(_popup)
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 25
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)
	# Titles and pop-ups float above the fade.
	var over := CanvasLayer.new()
	over.layer = 26
	add_child(over)
	var over_root := Control.new()
	over_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(over_root)
	title_card.reparent(over_root, false)
	_popup.reparent(over_root, false)


## Fades the screen to (alpha 1) or from (alpha 0) a colour.
func fade(alpha: float, time: float = 0.6, color: Color = Color(0.03, 0.02, 0.05)) -> void:
	_fade.color = Color(color.r, color.g, color.b, _fade.color.a)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, time)
	await tw.finished


func letterbox(on: bool, time: float = 0.6) -> void:
	var h := 90.0 if on else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_bars[0], "offset_bottom", h, time).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_bars[1], "offset_top", -h, time).set_trans(Tween.TRANS_SINE)
	tracker.visible = not on
	minimap.visible = not on
	if on:
		help.visible = false
	await tw.finished


## Big celebratory card ("ACHIEVEMENT UNLOCKED…").
func popup(title: String, text: String = "", hold: float = 3.5) -> void:
	_popup_title.text = title
	_popup_label.text = text
	_popup_label.visible = text != ""
	_popup.visible = true
	_popup.reset_size()
	_popup.pivot_offset = _popup.size * 0.5
	_popup.scale = Vector2(0.3, 0.3)
	_popup.modulate.a = 0.0
	Sound.play_ui("quest_done")
	var tw := create_tween()
	tw.tween_property(_popup, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(_popup, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(_popup, "modulate:a", 0.0, 0.4)
	await tw.finished
	_popup.visible = false

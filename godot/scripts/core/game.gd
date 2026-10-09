extends Node
## Global services: input map, shared references and command-line options.
##
## Autoloaded as `Game`. Systems register themselves here (player, camera, hud…)
## so that gameplay code can reach each other without hard-coded node paths.

## World scale of the Kenney "mini characters" (0.78 m tall in the source file).
const CHARACTER_SCALE := 1.6

const PHYS_WORLD := 1
const PHYS_CHARACTERS := 2
const PHYS_VEHICLES := 4
const PHYS_PROPS := 8
## Interior walls: block people, not the camera (dollhouse view).
const PHYS_WALLS := 16

## Keyboard bindings (same controls as the three.js version).
const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"handbrake": [KEY_SPACE],
	"toggle_help": [KEY_H],
	"cycle_look": [KEY_O],
	"toggle_time": [KEY_T],
	"screenshot": [KEY_F12],
	"debug_physics": [KEY_P],
	"quest_log": [KEY_Q],
	"cycle_look_him": [],
	"cancel": [KEY_ESCAPE],
	"throttle": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"music": [KEY_M],
	"ui_up_choice": [KEY_W, KEY_UP],
	"ui_down_choice": [KEY_S, KEY_DOWN],
	"decor_prev": [KEY_Z],
	"decor_next": [KEY_X],
	"decor_rotate": [KEY_R],
	"decor_pickup": [KEY_F],
	"map_zoom": [KEY_N],
}

## PlayStation (DualSense / DualShock) layout, using Godot's SDL button names:
## A = Cross, B = Circle, X = Square, Y = Triangle.
const JOY_BINDINGS := {
	"interact": [JOY_BUTTON_A],
	"cancel": [JOY_BUTTON_B],
	"jump": [JOY_BUTTON_X],
	"handbrake": [JOY_BUTTON_X],
	"quest_log": [JOY_BUTTON_Y],
	"run": [JOY_BUTTON_RIGHT_SHOULDER],
	"cycle_look": [JOY_BUTTON_LEFT_SHOULDER],
	"cycle_look_him": [JOY_BUTTON_DPAD_LEFT],
	"toggle_time": [JOY_BUTTON_DPAD_UP],
	"music": [JOY_BUTTON_DPAD_DOWN],
	"map_zoom": [JOY_BUTTON_DPAD_RIGHT],
	"toggle_help": [JOY_BUTTON_START],
	"screenshot": [JOY_BUTTON_BACK],
	"ui_up_choice": [JOY_BUTTON_DPAD_UP],
	"ui_down_choice": [JOY_BUTTON_DPAD_DOWN],
	"decor_prev": [JOY_BUTTON_DPAD_LEFT],
	"decor_next": [JOY_BUTTON_DPAD_RIGHT],
	"decor_rotate": [JOY_BUTTON_RIGHT_SHOULDER],
	"decor_pickup": [JOY_BUTTON_Y],
}

## Button labels shown in prompts, per device.
const GLYPHS := {
	"keyboard": {"interact": "E", "cancel": "Esc", "jump": "Space", "quest_log": "Q", "decor_rotate": "R",
		"decor_pickup": "F", "decor_prev": "Z", "decor_next": "X"},
	"gamepad": {"interact": "✕", "cancel": "○", "jump": "□", "quest_log": "△", "decor_rotate": "R1",
		"decor_pickup": "△", "decor_prev": "◀", "decor_next": "▶"},
}

## True after the last input came from a controller (prompts show PlayStation glyphs).
var gamepad_active := false
signal input_device_changed(gamepad: bool)

var player: Node = null
var partner: Node = null
var camera_rig: Node = null
var hud: Node = null
var world: Node = null
var terrain: Node = null
var ocean: Node = null
var atmosphere: Node = null
var interaction: Node = null
var chapters: Node = null
## AudioManager (play_sfx, play_jingle, set_music…) — may be null in tools/tests.
var audio: Node = null
## QuestManager — may be null in tools/tests.
var quests: Node = null

## Her name in dialogue boxes.
const HER_NAME := "Tatiana"

## "outside" or the id of the interior you're in ("pizza", "cinema", "house", "hotel").
var location := "outside"
signal location_changed(where: String)
## True while a cutscene/dialogue sequence drives the characters.
var story_lock := false
## True while decorating the house (E places furniture instead of interacting).
var decor_active := false

## Parsed `-- key=value` user arguments (e.g. `--shots=/tmp/out`).
var options := {}

signal player_registered(p)
signal photo_taken


func _enter_tree() -> void:
	_setup_input()
	for arg in OS.get_cmdline_user_args():
		var a: String = arg.trim_prefix("--")
		var eq := a.find("=")
		if eq >= 0:
			options[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			options[a] = true
	# The editor/MCP runner cannot pass user args, so a request file works too.
	const REQUEST := "res://shots_request.cfg"
	if FileAccess.file_exists(REQUEST):
		for line in FileAccess.get_file_as_string(REQUEST).split("\n"):
			var l := line.strip_edges()
			var eq := l.find("=")
			if eq > 0:
				options[l.substr(0, eq)] = l.substr(eq + 1)


func _ready() -> void:
	_setup_display()
	# The cozy toon look + rolling world (pass --flat for the plain renderer look).
	Stylizer.enabled = not options.has("flat")
	Stylizer.attach(get_tree())
	if options.has("flat"):
		RenderingServer.global_shader_parameter_set("curve_amount", 0.0)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		RenderingServer.global_shader_parameter_set("curve_origin", cam.global_position)
		var f := -cam.global_transform.basis.z
		RenderingServer.global_shader_parameter_set("curve_dir", Vector3(f.x, 0.0, f.z))
	# Grass bends away from the two of you.
	if player and is_instance_valid(player):
		RenderingServer.global_shader_parameter_set("player_pos", player.global_position)
	if partner and is_instance_valid(partner):
		RenderingServer.global_shader_parameter_set("partner_pos", partner.global_position)


func _setup_input() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	# Gamepad support comes for free: left stick moves, A jumps, X interacts.
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_joy_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_joy_axis("ui_up_choice", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("ui_down_choice", JOY_AXIS_LEFT_Y, 1.0)
	for action in JOY_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for b in JOY_BINDINGS[action]:
			_add_joy_button(action, b)


func _add_joy_axis(action: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _add_joy_button(action: String, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func register_player(p: Node) -> void:
	player = p
	player_registered.emit(p)


## Camera-relative movement input on the XZ plane (length ≤ 1).
func move_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func save_screenshot(path: String = "") -> String:
	if path == "":
		var base := "res://" if OS.has_feature("editor") else "user://"
		var dir := ProjectSettings.globalize_path(base).path_join("_shots")
		DirAccess.make_dir_recursive_absolute(dir)
		path = dir.path_join("shot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
	# Keep the editor from importing screenshots saved inside the project.
	var ignore := path.get_base_dir().path_join(".gdignore")
	if not FileAccess.file_exists(ignore):
		var f := FileAccess.open(ignore, FileAccess.WRITE)
		if f:
			f.close()
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	return path


func glyph(action: String) -> String:
	return GLYPHS["gamepad" if gamepad_active else "keyboard"].get(action, action)


## Gentle controller rumble (no-op without a gamepad).
func rumble(weak: float, strong: float, seconds: float) -> void:
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, weak, strong, seconds)


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4)
	var kbm := event is InputEventKey or event is InputEventMouseButton
	if pad and not gamepad_active:
		gamepad_active = true
		input_device_changed.emit(true)
	elif kbm and gamepad_active:
		gamepad_active = false
		input_device_changed.emit(false)


## Opens full screen (F11 toggles a window). The 3D world renders at 1080 lines
## or more (the screen's own resolution on a 1080p display, the "points"
## resolution on a Retina one, so a MacBook does not shade 8 million pixels a
## frame); the HUD always draws at full sharpness.
func _setup_display() -> void:
	if options.has("shots") and not options.has("fullscreen"):
		get_window().size = Vector2i(1600, 900)
	elif not options.has("windowed"):
		get_window().mode = Window.MODE_FULLSCREEN
	for i in DisplayServer.get_screen_count():
		print("[display] screen %d: %s px, scale %.2f, %d Hz%s" % [i, DisplayServer.screen_get_size(i), DisplayServer.screen_get_scale(i),
			int(DisplayServer.screen_get_refresh_rate(i)), " (current)" if i == DisplayServer.window_get_current_screen() else ""])
	# Never render faster than the display (keeps laptops cool and steady).
	Engine.max_fps = int(options.get("max_fps", 60))
	get_tree().root.size_changed.connect(_apply_render_scale)
	_apply_render_scale.call_deferred()
	if not options.has("shots"):
		add_child(QualityGovernor.new())


func _apply_render_scale() -> void:
	var vp := get_tree().root
	var h := float(DisplayServer.window_get_size().y)
	var want := float(options.get("render_lines", 1080))
	# Render the 3D world at (at least) `want` lines. On a Retina screen that is
	# simply its native "points" resolution (exactly half the pixels each way),
	# which upscales cleanly with plain bilinear filtering; FSR looked about the
	# same here but cost ~2.5 ms a frame on the MacBook GPU.
	var dpi := maxf(DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen()), 1.0)
	var s := clampf(maxf(want / maxf(h, 1.0), 1.0 / dpi), 0.25, 1.0)
	if want / maxf(h, 1.0) <= 0.5 and dpi < 1.5:
		s = 0.5   # e.g. a 4K screen without scaling: 1080 lines, a clean 2× upscale
	if s > 0.9:
		s = 1.0
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s


func toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN else Window.MODE_FULLSCREEN


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_F11:
		toggle_fullscreen()
		return
	if event.is_action_pressed("screenshot"):
		var p := save_screenshot()
		photo_taken.emit()
		Sound.play_ui("camera")
		if hud:
			hud.toast("Photo saved ✿")
		print("[game] screenshot ", p)

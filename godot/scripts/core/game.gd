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
}

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

## Parsed `-- key=value` user arguments (e.g. `--shots=/tmp/out`).
var options := {}

signal player_registered(p)


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
	_add_joy_button("jump", JOY_BUTTON_A)
	_add_joy_button("handbrake", JOY_BUTTON_A)
	_add_joy_button("interact", JOY_BUTTON_X)
	_add_joy_button("run", JOY_BUTTON_RIGHT_SHOULDER)


func _add_joy_axis(action: String, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _add_joy_button(action: String, button: int) -> void:
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		var p := save_screenshot()
		if hud:
			hud.toast("Photo saved ✿")
		print("[game] screenshot ", p)

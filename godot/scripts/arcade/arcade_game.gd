class_name ArcadeGame
extends Control
## Base for the arcade mini-games. A game draws itself into its rect (the
## cabinet screen), reads the controls with ArcadeGame.pressed()/held(), and
## emits `finished(score)` when the round is over. The cabinet (Arcade) handles
## the title screen, the scores and leaving.

signal finished(score: int)

static var FONT: Font = _weight(preload("res://assets/fonts/Fredoka.ttf"), 600)
static var BODY: Font = _weight(preload("res://assets/fonts/Nunito.ttf"), 600)


static func _weight(f: Font, w: int) -> Font:
	var v := FontVariation.new()
	v.base_font = f
	var ts := TextServerManager.get_primary_interface()
	v.variation_opentype = {ts.name_to_tag("wght"): w}
	# Belt and braces: a touch of faux bold so titles read on the cabinet.
	v.variation_embolden = 0.35
	return v

var running := false
var score := 0
var t := 0.0


## Called by the cabinet to (re)start a round.
func begin() -> void:
	score = 0
	t = 0.0
	running = true
	_reset()


func _reset() -> void:
	pass


func _process(delta: float) -> void:
	t += delta
	if running:
		_tick(minf(delta, 1.0 / 20.0))
	queue_redraw()


func _tick(_delta: float) -> void:
	pass


func end_round() -> void:
	if not running:
		return
	running = false
	finished.emit(score)


## Extra info for the game-over card (e.g. "Prize: Yoggi plush!").
func result_note() -> String:
	return ""


## Controls -----------------------------------------------------------------

## Directions also listen to the gamepad's D-pad (bound to other actions in the world).
const DIRS := {
	"up": ["move_forward", "ui_up_choice"],
	"down": ["move_back", "ui_down_choice"],
	"left": ["move_left", "decor_prev"],
	"right": ["move_right", "decor_next"],
	"a": ["jump", "interact"],
}


static func pressed(what: String) -> bool:
	for a in DIRS.get(what, []):
		if Input.is_action_just_pressed(a):
			return true
	return false


static func held(what: String) -> bool:
	for a in DIRS.get(what, []):
		if Input.is_action_pressed(a):
			return true
	return false


## Drawing helpers ----------------------------------------------------------

func text(s: String, pos: Vector2, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = FONT) -> void:
	draw_string(font, pos, s, align, width, sz, col)


func text_outlined(s: String, pos: Vector2, sz: int, col: Color, outline: Color, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0) -> void:
	draw_string_outline(FONT, pos, s, align, width, sz, maxi(4, sz / 6), outline)
	draw_string(FONT, pos, s, align, width, sz, col)


func rrect(r: Rect2, col: Color, radius: float = 10.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func ellipse(c: Vector2, rx: float, ry: float, col: Color, seg: int = 28) -> void:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * i / seg
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

class_name Arcade
extends CanvasLayer
## A full-screen arcade cabinet for one mini-game: neon frame and marquee, the
## game's screen, a title card with both your high scores, a game-over card
## with Marco's reaction, and Esc / ○ to step away. Scores live in the save.

const GAMES := {
	"yoggi_run": {
		"title": "YOGGI RUN", "sub": "Jump the plant pots, grab the treats!", "marco": 650, "unit": "points",
		"color": Color(0.4, 0.85, 0.6), "script": "res://scripts/arcade/yoggi_run.gd",
		"help": ["%a  jump  (hold it to jump higher)", "%a  in the air: double jump"],
	},
	"pizza_rush": {
		"title": "PIZZA RUSH", "sub": "Top every pizza just like the order says!", "marco": 9, "unit": "pizzas",
		"color": Color(1.0, 0.5, 0.38), "script": "res://scripts/arcade/pizza_rush.gd",
		"help": ["↑ pepperoni   ← mushroom   → olive   ↓ basil", "%a  send it out early"],
	},
	"claw": {
		"title": "CLAW CRANE", "sub": "Win a plush for the house!", "marco": 0, "unit": "plushes won",
		"color": Color(0.68, 0.58, 1.0), "script": "res://scripts/arcade/claw_machine.gd",
		"help": ["←↑→↓  move the claw", "%a  drop it  ·  you have 20 seconds"],
	},
}

const MARCO := {
	"beat": [
		"Okay. That's... a lot of points. Rematch. Best of forty-seven.",
		"I was letting you win. (I was absolutely not letting you win.)",
		"New high score?! I'm telling the whole island. Pip's going to make a banner.",
	],
	"lost": [
		"The champion remains undefeated! (Please don't try again.)",
		"Sooo close. Want me to hold your bag for luck?",
		"Don't feel bad, I've had years of practice. Years. Of my life.",
	],
	"claw_win": [
		"You actually got one?! I've spent a small fortune on that machine.",
		"It's coming home with us. It has a name now. I've decided.",
		"Look at its little face! Yoggi is going to be SO jealous.",
	],
	"claw_lose": [
		"The claw is rigged. Everyone knows the claw is rigged.",
		"So close! It was basically yours. Spiritually.",
		"One more go. That one's just being shy.",
	],
}

const CAB := Rect2(170, 30, 1260, 840)
const SCREEN := Rect2(210, 150, 1180, 610)

static var current: Arcade

var game_id := "yoggi_run"
var state := "title"          # title | play | over
var game: ArcadeGame
var _root: Control
var _card: Control
var _ready_at := 0.0
var _last := 0
var _new_best := false
var _marco_line := ""
var _music_was := ""


static func open(id: String) -> void:
	if current != null or Game.player == null:
		return
	var a := Arcade.new()
	a.game_id = id
	Game.player.get_tree().root.add_child(a)


static func best(id: String) -> int:
	if Game.quests == null:
		return 0
	return int(Game.quests.flags.get("arcade", {}).get(id, 0))


static func _record(id: String, s: int) -> bool:
	if Game.quests == null:
		return false
	var all: Dictionary = Game.quests.flags.get("arcade", {})
	var old := int(all.get(id, 0))
	var better := false
	if id == "claw":
		all[id] = old + s          # plushes won so far
		better = s > 0
	elif s > old:
		all[id] = s
		better = true
	Game.quests.flags["arcade"] = all
	Game.quests.save_now()
	return better


func _ready() -> void:
	current = self
	layer = 40
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.draw.connect(_draw_cabinet)
	var info: Dictionary = GAMES[game_id]
	game = load(info["script"]).new()
	game.position = SCREEN.position
	game.size = SCREEN.size
	game.clip_contents = true
	_root.add_child(game)
	game.finished.connect(_on_finished)
	_card = Control.new()
	_card.position = SCREEN.position
	_card.size = SCREEN.size
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)
	_card.draw.connect(_draw_card)
	get_viewport().size_changed.connect(_layout)
	_layout()
	if Game.player:
		Game.player.input_enabled = false
	if Game.hud:
		Game.hud.visible = false
	Game.story_lock = true
	Sound.play("arcade_coin", -4.0)
	_ready_at = _now() + 0.35
	if Game.options.has("arcade_autoplay"):
		_start()


func _exit_tree() -> void:
	if current == self:
		current = null


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Keep the cabinet centred at any window size (the canvas is 1600×900-ish).
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_root.size = vs
	var k := minf(vs.x / 1600.0, vs.y / 900.0)
	var off := (vs - Vector2(1600, 900) * k) * 0.5
	for c in [game, _card]:
		c.scale = Vector2.ONE * k
	game.position = off + SCREEN.position * k
	_card.position = game.position
	_root.queue_redraw()


func _process(_delta: float) -> void:
	_card.queue_redraw()
	_root.queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if _now() < _ready_at:
		return
	if event.is_action_pressed("cancel"):
		if state == "play":
			game.running = false
			state = "title"
			Sound.play("arcade_select", -6.0)
		else:
			close()
		return
	var go: bool = event.is_action_pressed("interact") or event.is_action_pressed("jump") \
			or (event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode in [KEY_ENTER, KEY_KP_ENTER])
	if go and state != "play":
		_start()


func _start() -> void:
	state = "play"
	Sound.play("arcade_coin", -6.0)
	game.begin()


func _on_finished(s: int) -> void:
	_last = s
	_new_best = _record(game_id, s)
	state = "over"
	_ready_at = _now() + 0.9
	var info: Dictionary = GAMES[game_id]
	var pool: Array
	if game_id == "claw":
		pool = MARCO["claw_win"] if s > 0 else MARCO["claw_lose"]
	else:
		pool = MARCO["beat"] if s > int(info["marco"]) else MARCO["lost"]
	_marco_line = pool[randi() % pool.size()]
	Sound.play("arcade_win" if (_new_best or (game_id != "claw" and s > int(info["marco"]))) else "arcade_over", -4.0)
	if Game.options.has("arcade_autoplay"):
		print("[arcade] %s finished score=%d best=%d note=%s" % [game_id, s, best(game_id), game.result_note()])


func close() -> void:
	if Game.player:
		Game.player.input_enabled = true
	if Game.hud:
		Game.hud.visible = true
	Game.story_lock = false
	Sound.play("ui_close", -6.0)
	Places.refresh_hiscores()
	queue_free()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _k() -> float:
	return game.scale.x


func _xf(r: Rect2) -> Rect2:
	var k := _k()
	var vs := _root.size
	var off := (vs - Vector2(1600, 900) * k) * 0.5
	return Rect2(off + r.position * k, r.size * k)


func _draw_cabinet() -> void:
	var info: Dictionary = GAMES[game_id]
	var col: Color = info["color"]
	var k := _k()
	_root.draw_rect(Rect2(Vector2.ZERO, _root.size), Color(0.07, 0.04, 0.12, 0.88))
	# Soft neon glow behind the cabinet.
	var cab := _xf(CAB)
	for i in 4:
		var g := cab.grow(float(18 - i * 5) * k)
		_box(g, Color(col.r, col.g, col.b, 0.05 + i * 0.03), 40.0 * k)
	_box(cab, Color(0.13, 0.1, 0.2), 34.0 * k, col, int(8 * k))
	# Marquee.
	var mq := _xf(Rect2(CAB.position + Vector2(30, 18), Vector2(CAB.size.x - 60, 92)))
	_box(mq, col.darkened(0.55), 22.0 * k)
	var pulse := 0.85 + 0.15 * sin(_now() * 3.0)
	var fs := int(64 * k)
	_root.draw_string_outline(ArcadeGame.FONT, mq.position + Vector2(0, mq.size.y * 0.5 + fs * 0.36), info["title"],
			HORIZONTAL_ALIGNMENT_CENTER, mq.size.x, fs, int(12 * k), col.darkened(0.3))
	_root.draw_string(ArcadeGame.FONT, mq.position + Vector2(0, mq.size.y * 0.5 + fs * 0.36), info["title"],
			HORIZONTAL_ALIGNMENT_CENTER, mq.size.x, fs, Color(1, 1, 1).lerp(col, 0.25) * pulse)
	# Bulbs along the marquee.
	for i in 22:
		var x := mq.position.x + 24 * k + i * (mq.size.x - 48 * k) / 21.0
		var on := int(_now() * 6.0 + i) % 3 == 0
		_root.draw_circle(Vector2(x, mq.position.y + 8 * k), 4.5 * k, Color(1, 0.95, 0.7) if on else Color(0.55, 0.45, 0.3))
		_root.draw_circle(Vector2(x, mq.end.y - 8 * k), 4.5 * k, Color(1, 0.95, 0.7) if not on else Color(0.55, 0.45, 0.3))
	# Screen bezel.
	var sc := _xf(SCREEN)
	_box(sc.grow(14 * k), Color(0.02, 0.02, 0.04), 18.0 * k)
	# Bottom: controls + leave hint.
	var hint := "%s  leave" % Game.glyph("cancel")
	var y := _xf(Rect2(Vector2(0, SCREEN.end.y + 64), Vector2.ONE)).position.y
	var bfs := int(24 * k)
	_root.draw_string(ArcadeGame.BODY, Vector2(sc.position.x, y), _help_line(), HORIZONTAL_ALIGNMENT_LEFT, sc.size.x * 0.75, bfs, Color(1, 1, 1, 0.8))
	_root.draw_string(ArcadeGame.BODY, Vector2(sc.position.x, y), hint, HORIZONTAL_ALIGNMENT_RIGHT, sc.size.x, bfs, Color(1, 1, 1, 0.6))


func _help_line() -> String:
	var info: Dictionary = GAMES[game_id]
	return str(info["help"][0]).replace("%a", _a_glyph())


func _a_glyph() -> String:
	return "✕" if Game.gamepad_active else "Space"


func _box(r: Rect2, col: Color, radius: float, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	_root.draw_style_box(sb, r)


func _draw_card() -> void:
	if state == "play":
		return
	var info: Dictionary = GAMES[game_id]
	var col: Color = info["color"]
	var c := _card
	var w := SCREEN.size.x
	var h := SCREEN.size.y
	c.draw_rect(Rect2(Vector2.ZERO, SCREEN.size), Color(0.05, 0.03, 0.1, 0.55))
	var panel := Rect2(w * 0.5 - 330, 50, 660, h - 100)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.975, 0.91, 0.97)
	sb.set_corner_radius_all(28)
	sb.border_color = col
	sb.set_border_width_all(6)
	sb.anti_aliasing = true
	c.draw_style_box(sb, panel)
	var ink := Color(0.36, 0.27, 0.2)
	var x := panel.position.x
	var pw := panel.size.x
	var y := panel.position.y
	var blink := int(_now() * 2.0) % 2 == 0
	var tat := best(game_id)
	var mar := int(info["marco"])
	var unit: String = info["unit"]
	if state == "title":
		_ctext(c, info["title"], x, y + 78, pw, 54, col.darkened(0.35))
		_ctext(c, info["sub"], x, y + 122, pw, 24, ink, ArcadeGame.BODY)
		for i in info["help"].size():
			_ctext(c, str(info["help"][i]).replace("%a", _a_glyph()), x, y + 180 + i * 34, pw, 22, ink.lightened(0.15), ArcadeGame.BODY)
		_ctext(c, "HIGH SCORES", x, y + 290, pw, 26, col.darkened(0.3))
		var lead_t := tat > mar
		_score_row(c, x, y + 336, pw, "Tatiana", tat, unit, lead_t, ink)
		_score_row(c, x, y + 380, pw, "Marco", mar, unit, not lead_t and mar > 0, ink)
		if blink:
			_ctext(c, "Press %s to play" % ("✕" if Game.gamepad_active else "E"), x, y + 460, pw, 32, col.darkened(0.25))
	else:
		var won := (game_id == "claw" and _last > 0) or (game_id != "claw" and _last > mar)
		_ctext(c, "YOU WIN!" if won else "GAME OVER", x, y + 78, pw, 56, col.darkened(0.35))
		var line := "%d %s" % [_last, unit]
		if game_id == "claw":
			line = game.result_note() if _last > 0 else "So close!"
		_ctext(c, line, x, y + 136, pw, 34, ink)
		if _new_best and game_id != "claw":
			_ctext(c, "★ New best! ★", x, y + 178, pw, 26, Color(0.95, 0.6, 0.2))
		elif game_id == "claw":
			_ctext(c, "Plushes won: %d" % tat, x, y + 178, pw, 24, ink.lightened(0.2), ArcadeGame.BODY)
		else:
			_ctext(c, "Your best: %d" % tat, x, y + 178, pw, 24, ink.lightened(0.2), ArcadeGame.BODY)
		# Marco's speech bubble.
		var bub := Rect2(x + 40, y + 216, pw - 80, 150)
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0.86, 0.92, 1.0)
		bs.set_corner_radius_all(22)
		bs.anti_aliasing = true
		c.draw_style_box(bs, bub)
		c.draw_string(ArcadeGame.FONT, bub.position + Vector2(24, 40), "Marco", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.3, 0.45, 0.75))
		c.draw_multiline_string(ArcadeGame.BODY, bub.position + Vector2(24, 78), _marco_line, HORIZONTAL_ALIGNMENT_LEFT, bub.size.x - 48, 23, 3, ink)
		if blink and _now() >= _ready_at:
			_ctext(c, "%s play again  ·  %s leave" % ["✕" if Game.gamepad_active else "E", Game.glyph("cancel")], x, y + 440, pw, 26, col.darkened(0.25))


func _ctext(c: Control, s: String, x: float, y: float, w: float, sz: int, col: Color, font: Font = ArcadeGame.FONT) -> void:
	c.draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_CENTER, w, sz, col)


func _score_row(c: Control, x: float, y: float, w: float, who: String, s: int, unit: String, crown: bool, ink: Color) -> void:
	var left := x + w * 0.5 - 220
	c.draw_string(ArcadeGame.FONT, Vector2(left, y), ("♛ " if crown else "    ") + who, HORIZONTAL_ALIGNMENT_LEFT, 240, 30, ink)
	c.draw_string(ArcadeGame.FONT, Vector2(left + 220, y), "%d %s" % [s, unit], HORIZONTAL_ALIGNMENT_RIGHT, 220, 30, ink)

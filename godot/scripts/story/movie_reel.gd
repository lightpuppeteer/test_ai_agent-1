class_name MovieReel
extends Node2D
## The films on the cinema screen, drawn as little 2D cartoons into a
## SubViewport: a title card, then a looping scene per genre, with film grain,
## a vignette and the odd scratch. (genre: off | horror | comedy | drama)

const W := 960.0
const H := 442.0
const LOOP := 14.0

const TITLES := {
	"horror": ["THE THING IN THE ATTIC", "it just wants to borrow a cup of sugar"],
	"comedy": ["PIZZA COPS 3", "this time it's crust-onal"],
	"drama": ["A DOG NAMED SUNDAY", "bring tissues. bring two."],
}

var genre := "off"
var t := 0.0
var font: Font
var small_font: Font
var _rng := RandomNumberGenerator.new()


func play(g: String) -> void:
	genre = g
	t = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if genre == "off":
		return
	t += delta
	queue_redraw()


func _draw() -> void:
	match genre:
		"horror":
			_scene_horror(fmod(t, LOOP))
		"comedy":
			_scene_comedy(fmod(t, LOOP))
		"drama":
			_scene_drama(fmod(t, LOOP))
		_:
			_idle_card()
			return
	var lt := fmod(t, LOOP)
	if t < 3.2:
		_title_card(t)
	_film_fx(lt)
	# Fade to black between loops.
	var edge := minf(lt, LOOP - lt)
	if t > 3.2 and edge < 0.5:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 1.0 - edge / 0.5))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _sky(top: Color, bottom: Color, y1: float = H) -> void:
	var n := 24
	for i in n:
		var a := float(i) / n
		draw_rect(Rect2(0, y1 * a, W, y1 / n + 1.0), top.lerp(bottom, a))


func _text(s: String, pos: Vector2, size: int, col: Color, outline: Color = Color(0, 0, 0, 0), f: Font = null) -> void:
	var fnt := f if f else font
	if fnt == null:
		return
	var w := fnt.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w * 0.5, -size * 0.35)
	if outline.a > 0.0:
		draw_string_outline(fnt, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(4, size / 7), outline)
	draw_string(fnt, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _poly(pts: Array, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array(pts), col)


func _heart(c: Vector2, s: float, col: Color) -> void:
	var pts := []
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(c + Vector2(16.0 * pow(sin(a), 3.0), -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a))) * s / 16.0)
	_poly(pts, col)


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := []
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	_poly(pts, col)


func _cloud(c: Vector2, s: float, col: Color) -> void:
	for o in [Vector2(-1.0, 0.2), Vector2(0, -0.2), Vector2(1.0, 0.2), Vector2(0.5, 0.35), Vector2(-0.5, 0.35)]:
		draw_circle(c + o * s, s * 0.62, col)


func _title_card(tt: float) -> void:
	var a := clampf(tt / 0.4, 0.0, 1.0) * clampf((3.2 - tt) / 0.6, 0.0, 1.0)
	draw_rect(Rect2(0, 0, W, H), Color(0.04, 0.03, 0.06, a))
	var info: Array = TITLES[genre]
	var col: Color = {"horror": Color(1.0, 0.3, 0.38), "comedy": Color(1.0, 0.85, 0.3), "drama": Color(1.0, 0.85, 0.7)}[genre]
	_text("Paraíso Pictures presents", Vector2(W * 0.5, H * 0.3), 24, Color(0.85, 0.82, 0.9, a), Color(0, 0, 0, 0), small_font)
	_text(info[0], Vector2(W * 0.5, H * 0.5), 64, Color(col.r, col.g, col.b, a), Color(0.1, 0.05, 0.1, a))
	_text(info[1], Vector2(W * 0.5, H * 0.68), 26, Color(0.9, 0.88, 0.95, a * 0.9), Color(0, 0, 0, 0), small_font)


func _film_fx(tt: float) -> void:
	_rng.seed = int(t * 24.0)
	# Grain
	for i in 60:
		var p := Vector2(_rng.randf() * W, _rng.randf() * H)
		draw_rect(Rect2(p, Vector2(2, 2)), Color(1, 1, 1, 0.08) if i % 2 else Color(0, 0, 0, 0.12))
	# A scratch now and then.
	if _rng.randf() < 0.15:
		var x := _rng.randf() * W
		draw_line(Vector2(x, 0), Vector2(x + _rng.randf_range(-6, 6), H), Color(1, 1, 1, 0.12), 1.5)
	# Vignette
	for i in 8:
		var k := float(i) / 8.0
		draw_rect(Rect2(-40 + k * 40, -30 + k * 30, W + 80 - k * 80, H + 60 - k * 60), Color(0, 0, 0, 0.05), false, 30.0)


func _idle_card() -> void:
	_sky(Color(0.16, 0.1, 0.24), Color(0.3, 0.14, 0.26))
	for i in 7:
		var x := 80.0 + i * 135.0
		draw_rect(Rect2(x - 50, 0, 100, H), Color(0.55, 0.06, 0.12, 0.85))
		draw_rect(Rect2(x - 50, 0, 18, H), Color(0.7, 0.12, 0.18, 0.9))
	_text("Cinema Paraíso", Vector2(W * 0.5, H * 0.45), 72, Color(1.0, 0.85, 0.35), Color(0.25, 0.08, 0.1))
	_text("grab a seat · the show starts soon", Vector2(W * 0.5, H * 0.62), 26, Color(1, 0.95, 0.9), Color(0, 0, 0, 0), small_font)


# ---------------------------------------------------------------------------
# HORROR: a spooky house, a flickering attic, a flash of lightning... and a
# ghost who is mostly just shy.
# ---------------------------------------------------------------------------

func _scene_horror(tt: float) -> void:
	_sky(Color(0.06, 0.05, 0.16), Color(0.2, 0.12, 0.3))
	_rng.seed = 7
	for i in 40:
		var p := Vector2(_rng.randf() * W, _rng.randf() * H * 0.55)
		draw_circle(p, 1.2 + _rng.randf(), Color(1, 1, 0.9, 0.4 + 0.4 * sin(tt * 3.0 + i)))
	draw_circle(Vector2(780, 90), 52, Color(0.98, 0.95, 0.8))
	draw_circle(Vector2(805, 80), 48, Color(0.12, 0.08, 0.24))
	# Hill + house
	_poly([Vector2(0, H), Vector2(0, 330), Vector2(250, 300), Vector2(520, 320), Vector2(W, 345), Vector2(W, H)], Color(0.07, 0.05, 0.12))
	var hx := 470.0
	_poly([Vector2(hx - 130, 330), Vector2(hx - 130, 200), Vector2(hx, 110), Vector2(hx + 130, 200), Vector2(hx + 130, 330)], Color(0.1, 0.07, 0.17))
	_poly([Vector2(hx + 60, 160), Vector2(hx + 60, 110), Vector2(hx + 85, 110), Vector2(hx + 85, 180)], Color(0.1, 0.07, 0.17))
	var flicker := 0.6 + 0.4 * absf(sin(tt * 13.0) * sin(tt * 3.1))
	draw_rect(Rect2(hx - 24, 160, 48, 42), Color(1.0, 0.8, 0.3, flicker))
	for wx in [hx - 90, hx + 50]:
		draw_rect(Rect2(wx, 240, 40, 46), Color(0.25, 0.18, 0.12, 1.0))
	draw_rect(Rect2(hx - 22, 270, 44, 60), Color(0.05, 0.03, 0.08))
	# Eyes in the attic window
	if tt > 4.0 and tt < 9.0 and fmod(tt, 1.6) > 0.15:
		draw_circle(Vector2(hx - 9, 180), 5, Color(0.1, 0.05, 0.1))
		draw_circle(Vector2(hx + 9, 180), 5, Color(0.1, 0.05, 0.1))
	# Bats
	for i in 4:
		var bx := fmod(tt * (70.0 + i * 20.0) + i * 260.0, W + 100.0) - 50.0
		var by := 80.0 + i * 28.0 + sin(tt * 4.0 + i) * 12.0
		var flap := sin(tt * 18.0 + i) * 9.0
		_poly([Vector2(bx - 18, by - flap), Vector2(bx - 4, by - 2), Vector2(bx, by + 4), Vector2(bx + 4, by - 2), Vector2(bx + 18, by - flap), Vector2(bx, by + 8)], Color(0.03, 0.02, 0.06))
	# The ghost: floats in, says boo, waves.
	if tt > 6.5:
		var k := clampf((tt - 6.5) / 2.0, 0.0, 1.0)
		var gp := Vector2(lerpf(W + 80, 700, k), 260 + sin(tt * 2.5) * 14.0)
		var body := [gp + Vector2(-44, 0)]
		for i in 13:
			var a := PI + i * PI / 12.0
			body.append(gp + Vector2(cos(a) * 44, sin(a) * 50 - 10))
		for i in 6:
			body.append(gp + Vector2(44 - i * 17.6, 46 + (8.0 if i % 2 == 0 else -2.0) + sin(tt * 6.0 + i) * 3.0))
		_poly(body, Color(0.96, 0.96, 1.0, 0.92))
		draw_circle(gp + Vector2(-14, -18), 6, Color(0.1, 0.1, 0.15))
		draw_circle(gp + Vector2(14, -18), 6, Color(0.1, 0.1, 0.15))
		draw_circle(gp + Vector2(-24, -4), 7, Color(1.0, 0.6, 0.7, 0.6))
		draw_circle(gp + Vector2(24, -4), 7, Color(1.0, 0.6, 0.7, 0.6))
		draw_circle(gp + Vector2(0, 0), 6, Color(0.3, 0.1, 0.15))
		if tt > 8.2 and tt < 11.5:
			_text("boo?", gp + Vector2(-90, -70), 40, Color(1, 1, 1), Color(0.2, 0.1, 0.3))
	# Lightning
	if tt > 5.9 and tt < 6.4:
		draw_rect(Rect2(0, 0, W, H), Color(0.9, 0.9, 1.0, (6.4 - tt) * 1.6))
		_poly([Vector2(260, 0), Vector2(290, 0), Vector2(250, 110), Vector2(280, 110), Vector2(220, 240), Vector2(240, 130), Vector2(210, 130)], Color(1, 1, 0.85, 0.9))


# ---------------------------------------------------------------------------
# COMEDY: Officer Slice chases a cat burglar through town and meets a banana.
# ---------------------------------------------------------------------------

func _scene_comedy(tt: float) -> void:
	_sky(Color(0.45, 0.78, 1.0), Color(0.82, 0.94, 1.0), 330)
	for i in 3:
		_cloud(Vector2(fmod(120.0 + i * 340.0 + tt * 20.0, W + 200.0) - 100.0, 70.0 + i * 30.0), 30.0 + i * 6.0, Color(1, 1, 1, 0.95))
	draw_circle(Vector2(860, 70), 40, Color(1.0, 0.9, 0.4))
	# Town backdrop scrolling by
	var scroll := fmod(tt * 120.0, 300.0)
	for i in 6:
		var bx := i * 300.0 - scroll - 60.0
		var bh := 120.0 + (i % 3) * 40.0
		var col: Color = [Color(1.0, 0.7, 0.6), Color(0.7, 0.85, 1.0), Color(1.0, 0.92, 0.6)][i % 3]
		draw_rect(Rect2(bx, 330 - bh, 180, bh), col)
		_poly([Vector2(bx - 10, 330 - bh), Vector2(bx + 90, 330 - bh - 50), Vector2(bx + 190, 330 - bh)], col.darkened(0.3))
		for wy in range(2):
			for wx in range(3):
				draw_rect(Rect2(bx + 20 + wx * 55, 330 - bh + 25 + wy * 50, 30, 28), Color(1, 1, 1, 0.85))
	draw_rect(Rect2(0, 330, W, H - 330), Color(0.6, 0.6, 0.62))
	for i in 10:
		draw_rect(Rect2(fmod(i * 110.0 - tt * 240.0, W + 110.0) - 55.0, 385, 60, 8), Color(1, 1, 1, 0.8))
	var slip := tt > 7.0
	# The cat burglar (stripes + mask) running ahead with a pizza box.
	var cx := 650.0 + sin(tt * 1.3) * 30.0 + (180.0 if slip else 0.0) * clampf(tt - 7.0, 0.0, 1.0)
	var cy := 312.0 - absf(sin(tt * 9.0)) * 16.0
	draw_rect(Rect2(cx - 32, cy - 26, 64, 40), Color(0.35, 0.35, 0.4))
	for s in 3:
		draw_rect(Rect2(cx - 24 + s * 18, cy - 26, 8, 40), Color(0.2, 0.2, 0.25))
	draw_circle(Vector2(cx + 36, cy - 30), 22, Color(0.35, 0.35, 0.4))
	_poly([Vector2(cx + 20, cy - 46), Vector2(cx + 26, cy - 64), Vector2(cx + 34, cy - 48)], Color(0.35, 0.35, 0.4))
	_poly([Vector2(cx + 40, cy - 48), Vector2(cx + 48, cy - 64), Vector2(cx + 54, cy - 44)], Color(0.35, 0.35, 0.4))
	draw_rect(Rect2(cx + 22, cy - 38, 30, 9), Color(0.08, 0.08, 0.1))
	draw_rect(Rect2(cx - 50, cy - 50, 40, 12), Color(0.95, 0.85, 0.6))
	# Officer Slice
	var px := 300.0 + sin(tt * 1.1) * 40.0
	var py := 300.0 - (absf(sin(tt * 10.0)) * 22.0 if not slip else 0.0)
	var rot := 0.0
	if slip:
		var k := clampf(tt - 7.0, 0.0, 1.5)
		rot = k * TAU * 1.5
		py = 300.0 - sin(minf(k, 1.0) * PI) * 120.0 + maxf(k - 1.0, 0.0) * 20.0
	draw_set_transform(Vector2(px, py), rot, Vector2.ONE)
	_poly([Vector2(-50, -60), Vector2(50, -60), Vector2(0, 70)], Color(1.0, 0.82, 0.3))
	_poly([Vector2(-56, -76), Vector2(56, -76), Vector2(50, -56), Vector2(-50, -56)], Color(0.8, 0.52, 0.25))
	for pp in [Vector2(-18, -30), Vector2(18, -26), Vector2(0, 10)]:
		draw_circle(pp, 9, Color(0.85, 0.25, 0.18))
	draw_rect(Rect2(-38, -110, 76, 30), Color(0.15, 0.25, 0.5))
	draw_rect(Rect2(-48, -84, 96, 10), Color(0.1, 0.18, 0.38))
	_star(Vector2(0, -96), 10, Color(1.0, 0.85, 0.3))
	draw_rect(Rect2(-34, -50, 26, 14), Color(0.08, 0.08, 0.1))
	draw_rect(Rect2(8, -50, 26, 14), Color(0.08, 0.08, 0.1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The banana peel
	if tt > 5.5:
		var bx2 := clampf(W + 50.0 - (tt - 5.5) * 300.0, px + 10.0, W + 50.0)
		_poly([Vector2(bx2 - 22, 352), Vector2(bx2, 336), Vector2(bx2 + 22, 352), Vector2(bx2 + 6, 346), Vector2(bx2 - 6, 346)], Color(1.0, 0.9, 0.3))
	if slip and tt > 7.2 and tt < 11.0:
		var bc := Vector2(px, py - 140)
		_poly([bc + Vector2(-90, 0), bc + Vector2(-50, -40), bc + Vector2(0, -60), bc + Vector2(50, -40), bc + Vector2(90, 0), bc + Vector2(50, 40), bc + Vector2(0, 55), bc + Vector2(-50, 40)], Color(1.0, 0.95, 0.4))
		_text("BONK!", bc + Vector2(0, -4), 44, Color(0.9, 0.2, 0.15), Color(1, 1, 1))
		for i in 3:
			var a := tt * 6.0 + i * TAU / 3.0
			_star(Vector2(px, py - 80) + Vector2(cos(a) * 50, sin(a) * 14), 10, Color(1.0, 0.85, 0.3))


# ---------------------------------------------------------------------------
# DRAMA: sunset on the pier, two people and Sunday the dog. Petals. Feelings.
# ---------------------------------------------------------------------------

func _scene_drama(tt: float) -> void:
	_sky(Color(0.98, 0.62, 0.55), Color(1.0, 0.85, 0.6), 270)
	var sun_y := 220.0 + tt * 3.0
	draw_circle(Vector2(560, sun_y), 70, Color(1.0, 0.88, 0.55))
	draw_rect(Rect2(0, 270, W, H - 270), Color(0.38, 0.45, 0.72))
	for i in 7:
		var y := 285.0 + i * 20.0
		var w := 150.0 - i * 14.0 + sin(tt * 2.0 + i) * 10.0
		draw_rect(Rect2(560 - w * 0.5, y, w, 4), Color(1.0, 0.88, 0.6, 0.65 - i * 0.07))
	# Pier + silhouettes
	var sil := Color(0.2, 0.13, 0.22)
	draw_rect(Rect2(0, 300, 470, 14), sil)
	for x in range(30, 470, 70):
		draw_rect(Rect2(x, 314, 10, 60), sil)
	for pp in [Vector2(330, 300), Vector2(372, 300)]:
		draw_circle(pp + Vector2(0, -78), 16, sil)
		draw_rect(Rect2(pp.x - 16, pp.y - 64, 32, 64), sil)
	# She leans on his shoulder after a while.
	if tt > 5.0:
		draw_circle(Vector2(352, 222), 16, sil)
	# Sunday the dog, wagging
	draw_rect(Rect2(410, 280, 44, 20), sil)
	draw_circle(Vector2(458, 276), 13, sil)
	_poly([Vector2(452, 266), Vector2(460, 254), Vector2(464, 268)], sil)
	var wag := sin(tt * 12.0) * 0.5
	draw_line(Vector2(410, 284), Vector2(410 - 18 * cos(wag), 284 - 18 * absf(sin(wag + 1.0))), sil, 5.0)
	# Petals drifting
	_rng.seed = 3
	for i in 26:
		var x := fmod(_rng.randf() * W + tt * (30.0 + _rng.randf() * 30.0), W + 40.0) - 20.0
		var y := fmod(_rng.randf() * H + tt * (25.0 + _rng.randf() * 20.0), H)
		draw_circle(Vector2(x + sin(tt * 2.0 + i) * 10.0, y), 4.5, Color(1.0, 0.75, 0.82, 0.85))
	if tt > 6.0:
		for i in 3:
			var k := fmod(tt - 6.0 + i * 0.9, 3.0) / 3.0
			_heart(Vector2(352 + sin(tt * 2.0 + i) * 20.0, 190 - k * 120.0), 14.0, Color(1.0, 0.45, 0.6, 1.0 - k))
	# Subtitles
	var lines := [[3.4, 6.8, "Sunday... you waited for us every single evening."], [7.2, 10.6, "And we'll keep coming back. Together."], [11.0, 13.4, "(sniff)"]]
	for l in lines:
		if tt > l[0] and tt < l[1]:
			draw_rect(Rect2(W * 0.5 - 330, H - 64, 660, 44), Color(0, 0, 0, 0.45))
			_text(l[2], Vector2(W * 0.5, H - 42), 26, Color(1, 1, 0.92), Color(0, 0, 0, 0), small_font)

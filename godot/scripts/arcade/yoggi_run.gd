extends ArcadeGame
## YOGGI RUN — an endless runner. Yoggi (a round grey British shorthair with
## green eyes) dashes along the island: jump the plant pots and cucumbers (hold
## to jump higher, tap again in the air to double jump) and grab fish treats.

const GROUND := 505.0
const YX := 210.0
const GRAV := 2600.0
const JUMP_V := -980.0
const DJUMP_V := -820.0

const FUR := Color(0.58, 0.62, 0.68)
const FUR_DARK := Color(0.47, 0.5, 0.57)
const FUR_LIGHT := Color(0.72, 0.75, 0.8)
const EYE := Color(0.35, 0.78, 0.38)

var speed := 380.0
var dist := 0.0
var y := GROUND
var vy := 0.0
var on_ground := true
var jumps := 0
var hold_t := 0.0
var obstacles: Array = []     # {x, kind, w, h}
var treats: Array = []        # {x, y, got}
var sparks: Array = []        # {p, v, life, col}
var next_obstacle := 1.2
var next_treat := 0.6
var treat_count := 0
var dead_t := -1.0
var milestone := 100
var scroll := 0.0
var _rng := RandomNumberGenerator.new()


func _reset() -> void:
	speed = 380.0
	dist = 0.0
	y = GROUND
	vy = 0.0
	on_ground = true
	jumps = 0
	obstacles.clear()
	treats.clear()
	sparks.clear()
	next_obstacle = 1.4
	next_treat = 0.7
	treat_count = 0
	dead_t = -1.0
	milestone = 100
	_rng.randomize()


func _process(delta: float) -> void:
	if not running:
		# Attract mode: gentle scroll, Yoggi trotting.
		scroll += delta * 160.0
	super._process(delta)


func _tick(delta: float) -> void:
	if dead_t >= 0.0:
		dead_t += delta
		vy += GRAV * delta
		y = minf(y + vy * delta, GROUND)
		_update_sparks(delta)
		if dead_t > 1.2:
			end_round()
		return
	speed = minf(speed + 9.0 * delta, 920.0)
	var dx := speed * delta
	dist += dx
	scroll += dx
	score = int(dist / 12.0) + treat_count * 10
	if score >= milestone:
		milestone += 100
		Sound.play("arcade_point", -10.0)
	# Jumping (variable height + one double jump).
	if pressed("a") or pressed("up"):
		if on_ground:
			vy = JUMP_V
			on_ground = false
			jumps = 1
			hold_t = 0.0
			Sound.play("arcade_jump", -8.0)
		elif jumps < 2:
			vy = DJUMP_V
			jumps = 2
			hold_t = 0.0
			Sound.play("arcade_jump", -8.0, 1.25)
			_burst(Vector2(YX, y), Color(1, 1, 1, 0.8), 8)
	var holding := held("a") or held("up")
	if not on_ground:
		var g := GRAV
		if holding and vy < 0.0 and hold_t < 0.22:
			g *= 0.45
		hold_t += delta
		vy += g * delta
		y += vy * delta
		if y >= GROUND:
			y = GROUND
			vy = 0.0
			on_ground = true
			jumps = 0
	# Spawning.
	next_obstacle -= delta
	if next_obstacle <= 0.0:
		_spawn_obstacle()
		next_obstacle = _rng.randf_range(0.95, 1.7) * clampf(500.0 / speed, 0.55, 1.15) + 0.25
	next_treat -= delta
	if next_treat <= 0.0:
		var ty := GROUND - _rng.randf_range(40.0, 250.0)
		var n := _rng.randi_range(1, 4)
		for i in n:
			treats.append({"x": size.x + 40.0 + i * 56.0, "y": ty - sin(i * 0.9) * 30.0, "got": false})
		next_treat = _rng.randf_range(1.1, 2.4)
	for o in obstacles:
		o["x"] -= dx
	for tr in treats:
		tr["x"] -= dx
	obstacles = obstacles.filter(func(o): return o["x"] > -200.0)
	treats = treats.filter(func(tr): return tr["x"] > -60.0 and not tr["got"])
	# Collisions (forgiving hitboxes).
	var me := Rect2(YX - 34, y - 62, 70, 56)
	for tr in treats:
		if not tr["got"] and me.grow(10).has_point(Vector2(tr["x"], tr["y"])):
			tr["got"] = true
			treat_count += 1
			Sound.play("arcade_treat", -8.0)
			_burst(Vector2(tr["x"], tr["y"]), Color(1.0, 0.85, 0.4), 10)
	for o in obstacles:
		var r := Rect2(o["x"] - o["w"] * 0.5 + 8, GROUND - o["h"] + 6, o["w"] - 16, o["h"] - 6)
		if me.intersects(r):
			dead_t = 0.0
			vy = -650.0
			Sound.play("arcade_hit", -4.0)
			_burst(Vector2(YX, y - 40), Color(1, 1, 1), 16)
			return
	_update_sparks(delta)


func _spawn_obstacle() -> void:
	var roll := _rng.randf()
	var kind := "pot"
	if speed > 520.0 and roll < 0.22:
		kind = "pots"
	elif roll < 0.42:
		kind = "cucumber"
	elif speed > 650.0 and roll < 0.55:
		kind = "cactus"
	var dims := {"pot": Vector2(56, 70), "pots": Vector2(120, 70), "cucumber": Vector2(110, 38), "cactus": Vector2(64, 150)}
	var d: Vector2 = dims[kind]
	obstacles.append({"x": size.x + 80.0, "kind": kind, "w": d.x, "h": d.y})


func _burst(at: Vector2, col: Color, n: int) -> void:
	for i in n:
		var a := _rng.randf() * TAU
		sparks.append({"p": at, "v": Vector2(cos(a), sin(a)) * _rng.randf_range(120, 320), "life": 0.6, "col": col})


func _update_sparks(delta: float) -> void:
	for s in sparks:
		s["p"] += s["v"] * delta
		s["v"] *= 0.92
		s["life"] -= delta
	sparks = sparks.filter(func(s): return s["life"] > 0.0)


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	# Sky gradient.
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(0.5, 0.78, 0.98), Color(0.5, 0.78, 0.98), Color(1.0, 0.9, 0.82), Color(1.0, 0.9, 0.82)]))
	draw_circle(Vector2(w - 170, 110), 54, Color(1.0, 0.92, 0.6))
	draw_circle(Vector2(w - 170, 110), 72, Color(1.0, 0.92, 0.6, 0.25))
	# Clouds.
	for i in 5:
		var cx := fposmod(i * 300.0 - scroll * 0.08, w + 300) - 150
		var cy := 70.0 + (i % 3) * 45.0
		ellipse(Vector2(cx, cy), 60, 22, Color(1, 1, 1, 0.9))
		ellipse(Vector2(cx + 40, cy - 12), 40, 22, Color(1, 1, 1, 0.9))
		ellipse(Vector2(cx - 38, cy + 4), 34, 16, Color(1, 1, 1, 0.9))
	# Sea + a far volcano island.
	draw_rect(Rect2(0, 300, w, 120), Color(0.36, 0.72, 0.9))
	var vx := fposmod(800.0 - scroll * 0.05, w + 500) - 250
	draw_colored_polygon(PackedVector2Array([Vector2(vx - 170, 310), Vector2(vx - 40, 205), Vector2(vx + 40, 205), Vector2(vx + 170, 310)]), Color(0.55, 0.45, 0.45))
	draw_colored_polygon(PackedVector2Array([Vector2(vx - 40, 205), Vector2(vx + 40, 205), Vector2(vx + 22, 220), Vector2(vx - 22, 220)]), Color(1.0, 0.5, 0.25))
	for i in 6:
		var sx := fposmod(i * 220.0 - scroll * 0.05, w + 200) - 100
		draw_line(Vector2(sx, 340 + (i % 3) * 22), Vector2(sx + 50, 340 + (i % 3) * 22), Color(1, 1, 1, 0.5), 3.0)
	# Hills with little houses.
	var hpts := PackedVector2Array()
	for i in 41:
		var x := i * w / 40.0
		hpts.append(Vector2(x, 380 + sin((x + scroll * 0.3) * 0.006) * 26 + sin((x + scroll * 0.3) * 0.017) * 10))
	hpts.append(Vector2(w, h))
	hpts.append(Vector2(0, h))
	draw_colored_polygon(hpts, Color(0.5, 0.78, 0.45))
	for i in 5:
		var hx := fposmod(i * 330.0 - scroll * 0.3, w + 330) - 150
		var hy := 392.0 + sin((hx + scroll * 0.3) * 0.006) * 26
		var roof: Color = [Color(0.92, 0.35, 0.3), Color(0.66, 0.5, 0.9), Color(0.95, 0.55, 0.7), Color(0.3, 0.6, 0.75), Color(0.95, 0.75, 0.3)][i]
		draw_rect(Rect2(hx - 26, hy - 34, 52, 36), Color(0.98, 0.95, 0.9))
		draw_colored_polygon(PackedVector2Array([Vector2(hx - 34, hy - 32), Vector2(hx, hy - 60), Vector2(hx + 34, hy - 32)]), roof)
		draw_rect(Rect2(hx - 7, hy - 16, 14, 18), roof.darkened(0.3))
	# Palm trees (mid layer).
	for i in 4:
		var px := fposmod(i * 420.0 + 120 - scroll * 0.55, w + 420) - 120
		_palm(Vector2(px, GROUND + 6))
	# Ground.
	draw_rect(Rect2(0, GROUND, w, h - GROUND), Color(0.93, 0.83, 0.62))
	draw_rect(Rect2(0, GROUND - 6, w, 14), Color(0.45, 0.75, 0.4))
	for i in 24:
		var gx := fposmod(i * 60.0 - scroll, w + 60) - 30
		draw_rect(Rect2(gx, GROUND + 26 + (i % 2) * 22, 26, 6), Color(0.85, 0.74, 0.54))
	# Treats, obstacles, sparks, Yoggi.
	for tr in treats:
		if not tr["got"]:
			_fish(Vector2(tr["x"], tr["y"] + sin(t * 5.0 + tr["x"] * 0.02) * 4.0))
	for o in obstacles:
		_obstacle(o)
	for s in sparks:
		draw_circle(s["p"], 5.0 * s["life"] / 0.6 + 1.0, Color(s["col"].r, s["col"].g, s["col"].b, s["life"] / 0.6))
	_yoggi(Vector2(YX, y))
	# Score.
	text_outlined("%d" % score, Vector2(w - 230, 62), 44, Color(1, 1, 1), Color(0.25, 0.3, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, 200)
	_fish(Vector2(40, 46), 0.8)
	text_outlined("× %d" % treat_count, Vector2(62, 60), 30, Color(1, 1, 1), Color(0.25, 0.3, 0.45), HORIZONTAL_ALIGNMENT_LEFT)


func _palm(base: Vector2) -> void:
	var top := base + Vector2(18, -170)
	draw_line(base, base + Vector2(8, -90), Color(0.62, 0.42, 0.28), 14.0)
	draw_line(base + Vector2(8, -90), top, Color(0.62, 0.42, 0.28), 12.0)
	for a in [-2.6, -2.0, -1.2, -0.5, 0.1]:
		var tip := top + Vector2(cos(a), sin(a) * 0.6 + 0.35) * 80.0
		draw_colored_polygon(PackedVector2Array([top, top.lerp(tip, 0.5) + Vector2(0, -14), tip, top.lerp(tip, 0.5) + Vector2(0, 10)]), Color(0.3, 0.68, 0.32))


func _fish(c: Vector2, k: float = 1.0) -> void:
	ellipse(c, 20 * k, 11 * k, Color(1.0, 0.62, 0.3))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 0) * k, c + Vector2(-30, -11) * k, c + Vector2(-30, 11) * k]), Color(1.0, 0.5, 0.25))
	draw_circle(c + Vector2(10, -3) * k, 2.8 * k, Color(0.2, 0.15, 0.15))
	draw_arc(c + Vector2(2, 0) * k, 9 * k, -0.9, 0.9, 6, Color(1.0, 0.8, 0.55), 2.0 * k)


func _obstacle(o: Dictionary) -> void:
	var x: float = o["x"]
	match o["kind"]:
		"pot":
			_pot(Vector2(x, GROUND), 1.0)
		"pots":
			_pot(Vector2(x - 30, GROUND), 1.0)
			_pot(Vector2(x + 30, GROUND), 1.0)
		"cucumber":
			draw_colored_polygon(PackedVector2Array([Vector2(x - 55, GROUND - 6), Vector2(x - 45, GROUND - 34), Vector2(x + 45, GROUND - 38), Vector2(x + 55, GROUND - 10), Vector2(x + 45, GROUND), Vector2(x - 45, GROUND)]), Color(0.3, 0.62, 0.28))
			for i in 5:
				draw_circle(Vector2(x - 36 + i * 18, GROUND - 22 + (i % 2) * 6), 3.0, Color(0.55, 0.82, 0.45))
			# Yoggi's nemesis has eyes, obviously.
			draw_circle(Vector2(x + 30, GROUND - 24), 5, Color(1, 1, 1))
			draw_circle(Vector2(x + 31, GROUND - 24), 2.5, Color(0.1, 0.1, 0.1))
		"cactus":
			_pot(Vector2(x, GROUND), 1.0)
			draw_rect(Rect2(x - 14, GROUND - 150, 28, 90), Color(0.35, 0.68, 0.38))
			draw_circle(Vector2(x, GROUND - 150), 14, Color(0.35, 0.68, 0.38))
			draw_rect(Rect2(x - 34, GROUND - 120, 20, 12), Color(0.35, 0.68, 0.38))
			draw_rect(Rect2(x - 34, GROUND - 140, 12, 30), Color(0.35, 0.68, 0.38))
			draw_circle(Vector2(x, GROUND - 165), 7, Color(1.0, 0.55, 0.7))


func _pot(base: Vector2, k: float) -> void:
	var c := Color(0.85, 0.47, 0.3)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-22, 0) * k, base + Vector2(-28, -46) * k, base + Vector2(28, -46) * k, base + Vector2(22, 0) * k]), c)
	draw_rect(Rect2(base + Vector2(-31, -56) * k, Vector2(62, 12) * k), c.darkened(0.12))
	for a in [-0.5, 0.0, 0.5]:
		var tip := base + Vector2(sin(a) * 30, -56 - cos(a) * 26) * k
		draw_colored_polygon(PackedVector2Array([base + Vector2(-6, -56) * k, tip, base + Vector2(6, -56) * k]), Color(0.36, 0.7, 0.36))


func _yoggi(feet: Vector2) -> void:
	var run_ph := t * (12.0 + speed * 0.01) if (running and dead_t < 0.0) else t * 6.0
	var bob := 0.0 if not on_ground else absf(sin(run_ph)) * -5.0
	var c := feet + Vector2(0, -36 + bob)
	var dead := dead_t >= 0.0
	# Shadow.
	ellipse(Vector2(feet.x, GROUND + 4), 40 * clampf(1.0 - (GROUND - feet.y) / 400.0, 0.4, 1.0), 7, Color(0, 0, 0, 0.15))
	# Tail.
	var tw := sin(run_ph * 0.5) * 8.0
	draw_line(c + Vector2(-38, -4), c + Vector2(-58, -22 + tw), FUR_DARK, 12.0)
	draw_circle(c + Vector2(-58, -22 + tw), 6, FUR_DARK)
	# Legs (back pair darker), trotting.
	for i in 4:
		var lx := -24.0 + i * 16.0
		var ph := run_ph + (PI if i % 2 else 0.0)
		var lift := maxf(0.0, sin(ph)) * 10.0 if on_ground else 6.0
		var col := FUR_DARK if i < 2 else FUR
		rrect(Rect2(c + Vector2(lx - 6, 14 - lift), Vector2(13, 22)), col, 6)
	# Round body.
	ellipse(c, 44, 30, FUR)
	ellipse(c + Vector2(4, 10), 30, 16, FUR_LIGHT)
	for i in 3:
		draw_arc(c + Vector2(-18 + i * 12, -18), 10, PI * 1.15, PI * 1.85, 6, FUR_DARK, 3.0)
	# Head (big and round, chubby cheeks).
	var hc := c + Vector2(38, -22)
	draw_colored_polygon(PackedVector2Array([hc + Vector2(-24, -16), hc + Vector2(-18, -42), hc + Vector2(-4, -24)]), FUR)
	draw_colored_polygon(PackedVector2Array([hc + Vector2(6, -24), hc + Vector2(20, -42), hc + Vector2(26, -14)]), FUR)
	draw_colored_polygon(PackedVector2Array([hc + Vector2(-18, -20), hc + Vector2(-16, -34), hc + Vector2(-8, -24)]), Color(1.0, 0.72, 0.75))
	draw_colored_polygon(PackedVector2Array([hc + Vector2(10, -24), hc + Vector2(18, -34), hc + Vector2(20, -20)]), Color(1.0, 0.72, 0.75))
	ellipse(hc, 30, 26, FUR)
	ellipse(hc + Vector2(6, 9), 20, 12, FUR_LIGHT)
	if dead:
		for ex in [-4.0, 14.0]:
			var e := hc + Vector2(ex, -4)
			draw_line(e + Vector2(-5, -5), e + Vector2(5, 5), Color(0.2, 0.2, 0.2), 3.0)
			draw_line(e + Vector2(-5, 5), e + Vector2(5, -5), Color(0.2, 0.2, 0.2), 3.0)
	else:
		for ex in [-4.0, 14.0]:
			var e := hc + Vector2(ex, -4)
			ellipse(e, 6.5, 7.5, EYE)
			ellipse(e + Vector2(0.5, 0), 2.5, 6.0, Color(0.08, 0.1, 0.08))
			draw_circle(e + Vector2(-2, -3), 1.8, Color(1, 1, 1))
	draw_colored_polygon(PackedVector2Array([hc + Vector2(3, 5), hc + Vector2(9, 5), hc + Vector2(6, 9)]), Color(0.85, 0.5, 0.55))
	draw_arc(hc + Vector2(3, 10), 3.5, 0.2, PI - 0.2, 6, Color(0.3, 0.3, 0.32), 1.6)
	draw_arc(hc + Vector2(9, 10), 3.5, 0.2, PI - 0.2, 6, Color(0.3, 0.3, 0.32), 1.6)
	# Whiskers.
	for s in [-1.0, 1.0]:
		var wx := hc + Vector2(6 + s * 14, 7)
		draw_line(wx, wx + Vector2(s * 16, -3), Color(1, 1, 1, 0.8), 1.4)
		draw_line(wx + Vector2(0, 3), wx + Vector2(s * 16, 5), Color(1, 1, 1, 0.8), 1.4)
	if dead:
		for i in 3:
			var a := t * 4.0 + i * TAU / 3.0
			text("★", hc + Vector2(cos(a) * 26 - 8, -40 + sin(a) * 8), 18, Color(1.0, 0.85, 0.3))

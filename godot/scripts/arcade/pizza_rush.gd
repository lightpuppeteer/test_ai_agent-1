extends ArcadeGame
## PIZZA RUSH — pizzas glide along the counter at Pizzeria Amore. While a pizza
## is in the topping zone, add exactly what its order ticket asks for:
## ↑ pepperoni · ← mushroom · → olive · ↓ basil. Space/✕ sends a finished pizza
## out early. Three mistakes and the kitchen closes.

const BELT_Y := 400.0
const ZONE := Vector2(430.0, 720.0)      # x range of the topping zone
const OUT_X := 1060.0
const TOPPINGS := ["pepperoni", "mushroom", "olive", "basil"]
const KEYS := {"up": "pepperoni", "left": "mushroom", "right": "olive", "down": "basil"}
const ARROW := {"pepperoni": "↑", "mushroom": "←", "olive": "→", "basil": "↓"}

const CUSTOMERS := [
	["Pip", ""], ["Biscuit", ""], ["Mayor Koala", ""], ["Fennel", ""], ["Pebble", ""], ["Tatiana", "♥"],
	["Marco", "extra everything!!"], ["Yoggi", "(paw-print on the order)"], ["Nonna", "like in Napoli"],
]

var pizzas: Array = []        # {x, order: Array, has: Dictionary, bits: Array, wrong: bool, done: bool, boost: bool, who, note}
var strikes := 0
var belt_speed := 95.0
var spawn_t := 0.0
var pops: Array = []          # floating feedback {p, text, col, life}
var belt_scroll := 0.0
var served := 0
var _rng := RandomNumberGenerator.new()


func _reset() -> void:
	pizzas.clear()
	pops.clear()
	strikes = 0
	served = 0
	belt_speed = 95.0
	spawn_t = 0.3
	_rng.randomize()


func _process(delta: float) -> void:
	if not running:
		belt_scroll += delta * 60.0
	super._process(delta)


func _tick(delta: float) -> void:
	belt_speed = 95.0 + served * 6.5
	belt_scroll += belt_speed * delta
	spawn_t -= delta
	var last_x := INF
	for p in pizzas:
		last_x = minf(last_x, p["x"])
	if spawn_t <= 0.0 and (pizzas.is_empty() or last_x > 230.0):
		_spawn()
		spawn_t = 1.2
	# The pizza in the zone takes the toppings.
	var active: Variant = _active()
	if active:
		for k in KEYS:
			if pressed(k):
				_add(active, KEYS[k])
		if pressed("a") and _complete(active):
			active["boost"] = true
			Sound.play("arcade_select", -8.0)
	for p in pizzas:
		p["x"] += belt_speed * delta * (4.5 if p["boost"] else 1.0)
		if p["x"] > OUT_X and not p["done"]:
			p["done"] = true
			_judge(p)
	pizzas = pizzas.filter(func(p): return p["x"] < size.x + 140.0)
	for pp in pops:
		pp["p"] += Vector2(0, -50) * delta
		pp["life"] -= delta
	pops = pops.filter(func(pp): return pp["life"] > 0.0)
	if strikes >= 3:
		end_round()


func _spawn() -> void:
	var who: Array = CUSTOMERS[_rng.randi() % CUSTOMERS.size()]
	var order: Array = []
	if who[0] == "Marco":
		order = TOPPINGS.duplicate()
	elif who[0] == "Yoggi":
		order = ["pepperoni"]
	else:
		var n := clampi(1 + _rng.randi_range(0, 1 + served / 4), 1, 4)
		var pool := TOPPINGS.duplicate()
		pool.shuffle()
		order = pool.slice(0, n)
	pizzas.append({"x": -110.0, "order": order, "has": {}, "bits": [], "wrong": false, "done": false, "boost": false,
		"who": who[0], "note": who[1], "seed": _rng.randi()})


func _active() -> Variant:
	for p in pizzas:
		if not p["done"] and p["x"] >= ZONE.x and p["x"] <= ZONE.y:
			return p
	return null


func _complete(p: Dictionary) -> bool:
	if p["wrong"]:
		return false
	for o in p["order"]:
		if not p["has"].has(o):
			return false
	return true


func _add(p: Dictionary, top: String) -> void:
	var count := int(p["has"].get(top, 0))
	if count >= 4:
		return
	p["has"][top] = count + 1
	var r := RandomNumberGenerator.new()
	r.seed = int(p["seed"]) + p["bits"].size() * 97
	for i in 2:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * 48.0
		p["bits"].append({"top": top, "o": Vector2(cos(a), sin(a) * 0.62) * d, "rot": r.randf() * TAU})
	if top not in p["order"]:
		p["wrong"] = true
		Sound.play("arcade_wrong", -8.0)
		_pop(Vector2(p["x"], BELT_Y - 70), "oops!", Color(0.9, 0.3, 0.3))
	else:
		Sound.play("arcade_plop", -6.0, randf_range(0.9, 1.15))


func _judge(p: Dictionary) -> void:
	if _complete(p):
		served += 1
		score = served
		Sound.play("arcade_point", -6.0)
		_pop(Vector2(OUT_X, BELT_Y - 110), "♥ " + str(p["who"]), Color(0.95, 0.4, 0.5))
	else:
		strikes += 1
		Sound.play("arcade_hit", -8.0)
		_pop(Vector2(OUT_X, BELT_Y - 110), "✗ wrong order!", Color(0.85, 0.25, 0.25))


func _pop(at: Vector2, s: String, col: Color) -> void:
	pops.append({"p": at, "text": s, "col": col, "life": 1.2})


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	# Warm pizzeria wall with brick lines.
	draw_rect(Rect2(0, 0, w, h), Color(0.98, 0.9, 0.78))
	for row in 9:
		var yy := row * 34.0
		draw_line(Vector2(0, yy), Vector2(w, yy), Color(0.92, 0.8, 0.66), 2.0)
		for col in 14:
			var xx := col * 90.0 + (45.0 if row % 2 else 0.0)
			draw_line(Vector2(xx, yy), Vector2(xx, yy + 34), Color(0.92, 0.8, 0.66), 2.0)
	# Striped awning.
	for i in 24:
		draw_rect(Rect2(i * 50.0, 0, 50, 40), Color(0.9, 0.28, 0.26) if i % 2 == 0 else Color(1, 0.97, 0.92))
	for i in 24:
		ellipse(Vector2(i * 50.0 + 25, 40), 25, 10, Color(0.9, 0.28, 0.26) if i % 2 == 0 else Color(1, 0.97, 0.92))
	# Oven at the right end.
	var ov := Rect2(OUT_X - 10, 220, 200, 260)
	rrect(ov, Color(0.72, 0.36, 0.26), 60)
	ellipse(Vector2(OUT_X + 90, 380), 70, 52, Color(0.2, 0.08, 0.05))
	ellipse(Vector2(OUT_X + 90, 395), 50, 26, Color(1.0, 0.55 + sin(t * 6) * 0.05, 0.15, 0.85))
	text_outlined("FORNO", Vector2(OUT_X - 10, 270), 30, Color(1, 0.95, 0.85), Color(0.5, 0.22, 0.15), HORIZONTAL_ALIGNMENT_CENTER, 200)
	# Counter + belt.
	draw_rect(Rect2(0, BELT_Y + 40, w, h - BELT_Y - 40), Color(0.62, 0.42, 0.28))
	draw_rect(Rect2(0, BELT_Y - 30, w, 76), Color(0.38, 0.38, 0.42))
	for i in 30:
		var bx := fposmod(i * 50.0 + belt_scroll, w + 50) - 50
		draw_rect(Rect2(bx, BELT_Y - 30, 4, 76), Color(0.3, 0.3, 0.34))
	draw_rect(Rect2(0, BELT_Y + 46, w, 10), Color(0.5, 0.33, 0.22))
	# Topping zone.
	var z := Rect2(ZONE.x - 70, BELT_Y - 60, ZONE.y - ZONE.x + 140, 130)
	var zc := Color(1.0, 0.85, 0.3, 0.22 + 0.08 * sin(t * 4.0))
	rrect(z, zc, 18)
	draw_rect(z, Color(1.0, 0.8, 0.2, 0.8), false, 3.0)
	text("TOPPINGS HERE", Vector2(z.position.x, z.position.y - 10), 22, Color(0.6, 0.35, 0.1), HORIZONTAL_ALIGNMENT_CENTER, z.size.x)
	# Pizzas (+ tickets).
	for p in pizzas:
		_pizza(p)
	# Topping buttons legend.
	var lx := 70.0
	for top in ["pepperoni", "mushroom", "olive", "basil"]:
		rrect(Rect2(lx, h - 92, 240, 70), Color(1, 0.97, 0.9), 18)
		text(ARROW[top], Vector2(lx + 14, h - 44), 36, Color(0.45, 0.3, 0.2))
		_topping(top, Vector2(lx + 82, h - 57), 0.0, 1.1)
		text(top.capitalize(), Vector2(lx + 112, h - 48), 26, Color(0.45, 0.3, 0.2))
		lx += 264.0
	# HUD: served + strikes.
	text_outlined("Served: %d" % served, Vector2(24, 92), 34, Color(1, 1, 1), Color(0.55, 0.25, 0.18), HORIZONTAL_ALIGNMENT_LEFT)
	for i in 3:
		var hc := Vector2(w - 60 - i * 46, 78)
		text("♥", hc - Vector2(16, -12), 40, Color(0.9, 0.3, 0.35) if i >= strikes else Color(0.75, 0.7, 0.68))
	for pp in pops:
		text_outlined(pp["text"], pp["p"] - Vector2(150, 0), 30, pp["col"], Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 300)


func _pizza(p: Dictionary) -> void:
	var c := Vector2(p["x"], BELT_Y + 8)
	ellipse(c + Vector2(0, 8), 78, 30, Color(0, 0, 0, 0.18))
	if _active() == p:
		ellipse(c, 88 + sin(t * 8.0) * 3.0, 56, Color(1.0, 0.85, 0.3, 0.55))
	ellipse(c, 76, 46, Color(0.93, 0.7, 0.4))
	ellipse(c, 66, 39, Color(0.86, 0.3, 0.2))
	ellipse(c + Vector2(-3, -2), 60, 35, Color(1.0, 0.88, 0.5))
	for b in p["bits"]:
		_topping(b["top"], c + b["o"], b["rot"], 0.8)
	if p["wrong"]:
		text("✗", c + Vector2(-16, 14), 46, Color(0.85, 0.2, 0.2))
	# Order ticket on a little clip above.
	if p["done"]:
		return
	var tk := Rect2(c.x - 92, BELT_Y - 230, 184, 124)
	draw_line(Vector2(c.x, tk.end.y), Vector2(c.x, BELT_Y - 40), Color(0.6, 0.6, 0.62), 2.0)
	rrect(tk, Color(1, 1, 0.97), 8)
	draw_rect(Rect2(tk.position, Vector2(tk.size.x, 8)), Color(0.9, 0.3, 0.3))
	text(str(p["who"]), tk.position + Vector2(0, 38), 24, Color(0.4, 0.28, 0.2), HORIZONTAL_ALIGNMENT_CENTER, tk.size.x)
	var order: Array = p["order"]
	var ox := tk.position.x + tk.size.x * 0.5 - (order.size() - 1) * 21.0
	for i in order.size():
		var top: String = order[i]
		var ip := Vector2(ox + i * 42.0, tk.position.y + 74)
		_topping(top, ip, 0.0, 1.0)
		if p["has"].has(top):
			draw_circle(ip + Vector2(12, 12), 9, Color(0.35, 0.75, 0.4))
			text("✓", ip + Vector2(5, 19), 16, Color(1, 1, 1))
	if p["note"] != "":
		text(str(p["note"]), tk.position + Vector2(0, 114), 15, Color(0.55, 0.42, 0.35), HORIZONTAL_ALIGNMENT_CENTER, tk.size.x, BODY)


func _topping(top: String, at: Vector2, rot: float, k: float) -> void:
	match top:
		"pepperoni":
			draw_circle(at, 11 * k, Color(0.78, 0.18, 0.15))
			draw_circle(at + Vector2(-3, -3) * k, 2.2 * k, Color(0.9, 0.4, 0.35))
			draw_circle(at + Vector2(4, 2) * k, 1.8 * k, Color(0.6, 0.12, 0.1))
		"mushroom":
			var d := Vector2(cos(rot), sin(rot)) * 0.0
			draw_rect(Rect2(at + Vector2(-3, 0) * k + d, Vector2(6, 9) * k), Color(0.95, 0.9, 0.8))
			draw_colored_polygon(PackedVector2Array([at + Vector2(-11, 2) * k, at + Vector2(-8, -7) * k, at + Vector2(0, -10) * k, at + Vector2(8, -7) * k, at + Vector2(11, 2) * k]), Color(0.82, 0.68, 0.52))
		"olive":
			draw_circle(at, 8 * k, Color(0.15, 0.15, 0.17))
			draw_circle(at, 3.5 * k, Color(0.5, 0.15, 0.12))
		"basil":
			var dir := Vector2(cos(rot), sin(rot))
			var nrm := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([at - dir * 12 * k, at + nrm * 6 * k, at + dir * 12 * k, at - nrm * 6 * k]), Color(0.25, 0.62, 0.25))
			draw_line(at - dir * 10 * k, at + dir * 10 * k, Color(0.4, 0.75, 0.35), 1.5)

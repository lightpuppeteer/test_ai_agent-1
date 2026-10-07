class_name DecorSystem
extends Node3D
## Furnishing our house. Start from the moving boxes; while decorating, the
## selected item floats in front of you: Z/X (◀/▶) choose, R (R1) rotate,
## E (✕) place, F (△) pick up the nearest piece, Esc (○) to finish.
## Each room needs a few key pieces before the move-in quest continues.

const ITEMS := {
	"sofa": {"name": "Sofa", "model": "furniture-kit/loungeSofa", "count": 1},
	"tv": {"name": "TV", "model": "furniture-kit/cabinetTelevision", "top": "furniture-kit/televisionModern", "count": 1},
	"rug": {"name": "Rug", "model": "furniture-kit/rugRectangle", "count": 1, "flat": true},
	"plant": {"name": "Plant", "model": "furniture-kit/pottedPlant", "count": 3},
	"coffee_table": {"name": "Coffee table", "model": "furniture-kit/tableCoffee", "count": 1},
	"armchair": {"name": "Armchair", "model": "furniture-kit/loungeChair", "count": 2},
	"bed": {"name": "Bed", "model": "furniture-kit/bedDouble", "count": 1},
	"nightstand": {"name": "Nightstand", "model": "furniture-kit/cabinetBedDrawerTable", "count": 2},
	"lamp": {"name": "Lamp", "model": "furniture-kit/lampRoundFloor", "count": 2, "light": true},
	"wardrobe": {"name": "Wardrobe", "model": "furniture-kit/bookcaseClosedDoors", "count": 1},
	"desk": {"name": "Desk", "model": "furniture-kit/desk", "top": "furniture-kit/computerScreen", "count": 1},
	"desk_chair": {"name": "Desk chair", "model": "furniture-kit/chairDesk", "count": 1},
	"bookshelf": {"name": "Bookshelf", "model": "furniture-kit/bookcaseOpen", "count": 2},
	"teddy": {"name": "Teddy bear", "model": "furniture-kit/bear", "count": 1},
	"speaker": {"name": "Speaker", "model": "furniture-kit/speaker", "count": 2},
	"round_rug": {"name": "Round rug", "model": "furniture-kit/rugRound", "count": 1, "flat": true},
	"side_table": {"name": "Side table", "model": "furniture-kit/sideTable", "count": 1},
}
const REQUIRED := {
	"living": ["sofa", "tv", "rug", "plant"],
	"bedroom": ["bed", "nightstand", "lamp", "wardrobe"],
	"office": ["desk", "desk_chair", "bookshelf"],
}
const ROOM_NAMES := {"living": "Living room", "bedroom": "Bedroom", "office": "Office"}

var room: Interior
var placed: Array = []          # [{"item", "x", "z", "yaw"}] in room-local coords
var active := false
var _order: Array = []
var _sel := 0
var _yaw := 0.0
var _ghost: Node3D
var _ghost_id := ""
var _nodes: Array = []           # Node3D per placed entry (same order)
var _ui: CanvasLayer
var _ui_list: VBoxContainer
var _ui_req: VBoxContainer

signal changed


func setup(r: Interior) -> void:
	room = r
	_order = ITEMS.keys()


func room_of(local: Vector3) -> String:
	if local.z > -1.0:
		return "living"
	return "bedroom" if local.x < 0.0 else "office"


func remaining(item: String) -> int:
	var used := 0
	for p in placed:
		if p["item"] == item:
			used += 1
	return ITEMS[item]["count"] - used


func room_done(rid: String) -> bool:
	for item in REQUIRED[rid]:
		var ok := false
		for p in placed:
			if p["item"] == item and room_of(Vector3(p["x"], 0, p["z"])) == rid:
				ok = true
				break
		if not ok:
			return false
	return true


func complete() -> bool:
	for rid in REQUIRED:
		if not room_done(rid):
			return false
	return true


# ---------------------------------------------------------------------------
# Building pieces
# ---------------------------------------------------------------------------

func _make(item: String, ghost: bool = false) -> Node3D:
	var info: Dictionary = ITEMS[item]
	var n := Node3D.new()
	var id: String = info["model"]
	var bb := Props.model_aabb(id)
	var s := Props.kit_scale(id)
	var m := Props.model(id)
	m.scale = Vector3.ONE * s
	m.position = -Vector3(bb.get_center().x, bb.position.y, bb.get_center().z) * s
	n.add_child(m)
	if info.has("top"):
		var tid: String = info["top"]
		var tb := Props.model_aabb(tid)
		var t := Props.model(tid)
		t.scale = Vector3.ONE * s
		t.position = -Vector3(tb.get_center().x, tb.position.y, tb.get_center().z) * s + Vector3(0, bb.size.y * s, 0)
		n.add_child(t)
	if info.get("light", false) and not ghost:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 1.0
		l.omni_range = 4.5
		l.position.y = bb.size.y * s * 0.9
		n.add_child(l)
	if ghost:
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.6, 0.9, 1.0, 0.5)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.emission_enabled = true
		gm.emission = Color(0.4, 0.7, 1.0)
		gm.emission_energy_multiplier = 0.4
		for mi in Props._mesh_instances(n):
			(mi as MeshInstance3D).material_override = gm
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif not info.get("flat", false):
		var body := StaticBody3D.new()
		body.collision_layer = Game.PHYS_PROPS
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = bb.size * s * Vector3(0.9, 1.0, 0.9)
		cs.shape = box
		cs.position.y = bb.size.y * s * 0.5
		body.add_child(cs)
		n.add_child(body)
	return n


func _spawn_placed(entry: Dictionary) -> Node3D:
	var n := _make(entry["item"])
	room.add_child(n)
	n.position = Vector3(entry["x"], 0.0, entry["z"])
	n.rotation.y = entry["yaw"]
	return n


## The placed node for the first item of this kind (or null), and its info.
func find_placed(item: String) -> Node3D:
	for i in placed.size():
		if placed[i]["item"] == item and i < _nodes.size() and is_instance_valid(_nodes[i]):
			return _nodes[i]
	return null


## Top of a placed sofa / bed: where a cat would nap (global), or null.
func nap_spot() -> Variant:
	for item in ["sofa", "bed", "armchair"]:
		var n := find_placed(item)
		if n == null:
			continue
		var id: String = ITEMS[item]["model"]
		var bb := Props.model_aabb(id)
		var s := Props.kit_scale(id)
		var seat_h := bb.size.y * s * (0.5 if item == "sofa" else 0.62 if item == "bed" else 0.5)
		var fwd := 0.12 if item == "sofa" else 0.0
		var side := bb.size.x * s * 0.22 if item == "sofa" else 0.0
		return n.to_global(Vector3(side, seat_h, bb.size.z * s * fwd))
	return null


## Restores saved furniture (called by the quest manager on load).
func load_from(list: Array) -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	placed.clear()
	for e in list:
		if ITEMS.has(e.get("item", "")):
			var entry := {"item": e["item"], "x": float(e["x"]), "z": float(e["z"]), "yaw": float(e["yaw"])}
			placed.append(entry)
			_nodes.append(_spawn_placed(entry))
	_rebake_later()


func _rebake_later() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_rebake_nav()


# ---------------------------------------------------------------------------
# Decorating mode
# ---------------------------------------------------------------------------

func begin() -> void:
	if active:
		return
	active = true
	Game.decor_active = true
	_build_ui()
	_select(_first_available(0, 1))
	Sound.play_ui("open")


func end() -> void:
	if not active:
		return
	active = false
	Game.decor_active = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _ui:
		_ui.queue_free()
		_ui = null
	Sound.play_ui("close")
	if Game.quests:
		Game.quests.flags["decor"] = placed
		Game.quests.save_now()
	_rebake_nav()
	changed.emit()


func _rebake_nav() -> void:
	if is_inside_tree() and NavBaker.regions.has("house"):
		NavBaker.rebake_interior(get_tree().current_scene as Node3D, "house")


func _first_available(start: int, dir: int) -> int:
	for k in _order.size():
		var i := posmod(start + k * dir, _order.size())
		if remaining(_order[i]) > 0:
			return i
	return -1


func _select(i: int) -> void:
	_sel = i
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if i >= 0:
		_ghost_id = _order[i]
		_ghost = _make(_ghost_id, true)
		room.add_child(_ghost)
	_refresh_ui()


func _ghost_local() -> Vector3:
	var p: Node3D = Game.player
	var fwd := -p.global_transform.basis.z
	var world := p.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 1.8
	var local := room.to_local(world)
	local.x = clampf(snappedf(local.x, 0.25), -room.size.x * 0.5 + 0.6, room.size.x * 0.5 - 0.6)
	local.z = clampf(snappedf(local.z, 0.25), -room.size.z * 0.5 + 0.6, room.size.z * 0.5 - 0.6)
	local.y = 0.0
	return local


func _process(_delta: float) -> void:
	if not active:
		return
	if Game.location != "house":
		end()
		return
	if _ghost:
		_ghost.position = _ghost_local()
		_ghost.rotation.y = _yaw


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		end()
	elif event.is_action_pressed("decor_next"):
		_select(_first_available(_sel + 1, 1))
		Sound.play("ui_blip", -14.0)
	elif event.is_action_pressed("decor_prev"):
		_select(_first_available(_sel - 1, -1))
		Sound.play("ui_blip", -14.0)
	elif event.is_action_pressed("decor_rotate"):
		_yaw = fposmod(_yaw + PI * 0.5, TAU)
		Sound.play("ui_blip", -16.0, 1.3)
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_place()
	elif event.is_action_pressed("decor_pickup"):
		get_viewport().set_input_as_handled()
		_pick_up()


func _place() -> void:
	if _sel < 0 or _ghost == null or remaining(_ghost_id) <= 0:
		return
	var at := _ghost_local()
	var entry := {"item": _ghost_id, "x": at.x, "z": at.z, "yaw": _yaw}
	placed.append(entry)
	_nodes.append(_spawn_placed(entry))
	Sound.play("sit", -6.0, 1.2)
	FX.sparkle(room, room.to_global(at + Vector3(0, 0.6, 0)), Color(1.0, 0.95, 0.7), 20)
	if remaining(_ghost_id) <= 0:
		_select(_first_available(_sel + 1, 1))
	else:
		_refresh_ui()
	if Game.quests:
		Game.quests.flags["decor"] = placed
	changed.emit()


func _pick_up() -> void:
	var p: Node3D = Game.player
	var best := -1
	var bd := 2.2
	for i in _nodes.size():
		var d: float = (_nodes[i] as Node3D).global_position.distance_to(p.global_position + (-p.global_transform.basis.z) * 1.0)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return
	(_nodes[best] as Node3D).queue_free()
	var item: String = placed[best]["item"]
	_nodes.remove_at(best)
	placed.remove_at(best)
	Sound.play("pop", -6.0)
	_select(_order.find(item))
	changed.emit()


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var hud: HUD = Game.hud
	_ui = CanvasLayer.new()
	_ui.layer = 11
	add_child(_ui)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", hud._panel_style(Color(1, 0.975, 0.91, 0.94), 24, Vector2(22, 16)))
	panel.position = Vector2(24, 120)
	_ui.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(hud._label("🛋 Decorating", 26, HUD.ACCENT.darkened(0.2), hud._title_font))
	_ui_list = VBoxContainer.new()
	vb.add_child(_ui_list)
	vb.add_child(hud._label(" ", 8))
	_ui_req = VBoxContainer.new()
	vb.add_child(_ui_req)
	vb.add_child(hud._label(" ", 8))
	vb.add_child(hud._label("%s/%s choose · %s rotate · %s place\n%s pick up · %s done" % [
		Game.glyph("decor_prev"), Game.glyph("decor_next"), Game.glyph("decor_rotate"), Game.glyph("interact"),
		Game.glyph("decor_pickup"), Game.glyph("cancel")], 16, HUD.INK.lightened(0.2)))


func _refresh_ui() -> void:
	if _ui == null:
		return
	var hud: HUD = Game.hud
	for c in _ui_list.get_children():
		c.queue_free()
	for c in _ui_req.get_children():
		c.queue_free()
	for i in _order.size():
		var item: String = _order[i]
		var left := remaining(item)
		if left <= 0 and i != _sel:
			continue
		var sel := i == _sel
		var l := hud._label(("▶ " if sel else "   ") + "%s ×%d" % [ITEMS[item]["name"], left], 19,
				HUD.ACCENT.darkened(0.25) if sel else HUD.INK, hud._bold_font if sel else null)
		_ui_list.add_child(l)
	for rid in REQUIRED:
		var done := room_done(rid)
		var need := []
		for item in REQUIRED[rid]:
			need.append(ITEMS[item]["name"])
		_ui_req.add_child(hud._label(("✔ " if done else "○ ") + ROOM_NAMES[rid] + ": " + ", ".join(need), 16,
				Color(0.35, 0.6, 0.35) if done else HUD.INK))

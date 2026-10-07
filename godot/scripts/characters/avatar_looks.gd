class_name AvatarLooks
extends RefCounted
## The two of you, as chibi blocks, plus your wardrobes.
## `look(who, outfit)` returns a dictionary for Avatar.build().

const A = preload("res://scripts/characters/avatar.gd")

const OUTFITS := {
	"her": ["gallery", "silver_dress", "skirt_top", "bikini"],
	"him": ["amsterdam", "all_black", "beach"],
}
const OUTFIT_NAMES := {
	"gallery": "Black jacket & wide trousers",
	"silver_dress": "Silver dress",
	"skirt_top": "Skirt & top",
	"bikini": "Bikini",
	"amsterdam": "Beige tee & cargo shorts",
	"all_black": "All black",
	"beach": "Beach shorts",
}

# Palette
const SKIN_HIM := Color(0.93, 0.74, 0.62)
const SKIN_HER := Color(0.97, 0.81, 0.71)
const HAIR_HIM := Color(0.15, 0.10, 0.08)
const BEARD := Color(0.19, 0.13, 0.10)
const HAIR_HER := Color(0.26, 0.18, 0.13)
const HAIR_HER_TIPS := Color(0.42, 0.30, 0.22)
const BLONDE := Color(0.94, 0.88, 0.72)
const BLACK := Color(0.11, 0.11, 0.12)
const WHITE := Color(0.96, 0.95, 0.92)


static func look(who: String, outfit: String) -> Dictionary:
	var parts: Array = []
	var face := {}
	if who == "him":
		parts.append_array(_head(SKIN_HIM))
		parts.append_array(_hair_him())
		parts.append_array(_beard())
		parts.append_array(_sunglasses_on_eyes())
		face = {"eyes": "round", "brows": HAIR_HIM, "mouth": "none", "blush": false}
		parts.append_array(_outfit_him(outfit))
	else:
		parts.append_array(_head(SKIN_HER))
		parts.append_array(_hair_her())
		parts.append_array(_sunglasses_on_head())
		face = {"eyes": "round", "brows": Color(0.45, 0.33, 0.25), "mouth": "grin", "blush": true, "lash": true}
		parts.append_array(_outfit_her(outfit))
	return {"parts": parts, "face": face}


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

static func _b(bone: String, size: Vector3, at: Vector3, color: Color, extra: Dictionary = {}) -> Dictionary:
	var d := {"bone": bone, "size": size, "at": at, "color": color}
	d.merge(extra)
	return d


## A pair of mirrored blocks: `at` is given for the left side (+X).
static func _pair(bone_l: String, bone_r: String, size: Vector3, at: Vector3, color: Color, extra: Dictionary = {}) -> Array:
	var r := extra.duplicate()
	if r.has("rot"):
		var rr: Vector3 = r["rot"]
		r["rot"] = Vector3(rr.x, -rr.y, -rr.z)
	return [_b(bone_l, size, at, color, extra), _b(bone_r, size, Vector3(-at.x, at.y, at.z), color, r)]


static func _head(skin: Color) -> Array:
	var p: Array = [_b("head", A.HEAD_SIZE, A.HEAD_CENTER, skin, {"bevel": 0.04, "shade": 0.05})]
	p.append_array(_pair("head", "head", Vector3(0.04, 0.09, 0.07), Vector3(0.215, 0.5, -0.01), skin.darkened(0.04)))
	return p


## Bare arms and hands (sleeves go on top).
static func _arms(skin: Color, thick: float = 0.08) -> Array:
	var y := A.SHOULDER.y - 0.006
	var z := A.SHOULDER.z
	var arm_len := A.ARM_END - 0.09
	var p := _pair("arm-left", "arm-right", Vector3(arm_len, thick, thick), Vector3(0.09 + arm_len * 0.5, y, z), skin, {"shade": 0.0})
	p.append_array(_pair("arm-left", "arm-right", Vector3(0.06, 0.088, 0.1), Vector3(A.ARM_END + 0.02, y, z), skin, {"shade": 0.0, "bevel": 0.02}))
	return p


static func _sleeves(color: Color, length: float, thick: float = 0.1, mat: String = "matte") -> Array:
	var y := A.SHOULDER.y - 0.006
	return _pair("arm-left", "arm-right", Vector3(length, thick, thick), Vector3(0.085 + length * 0.5, y, A.SHOULDER.z), color, {"shade": 0.0, "mat": mat})


static func _legs(skin: Color) -> Array:
	return _pair("leg-left", "leg-right", Vector3(0.11, A.HIP_Y + 0.01, 0.12), Vector3(A.LEG_X, (A.HIP_Y + 0.01) * 0.5, -0.028), skin, {"shade": 0.0})


## Cloth around both legs from y0 to y1 (taper widens the bottom: >1 flares).
static func _leg_cloth(color: Color, y0: float, y1: float, width: float = 0.13, depth: float = 0.14, extra: Dictionary = {}) -> Array:
	return _pair("leg-left", "leg-right", Vector3(width, y1 - y0, depth), Vector3(A.LEG_X, (y0 + y1) * 0.5, -0.028), color, extra)


static func _shoes(color: Color, sole: Color, accent: Color = Color(0, 0, 0, 0)) -> Array:
	var p := _pair("leg-left", "leg-right", Vector3(0.13, 0.04, 0.175), Vector3(A.LEG_X, 0.026, -0.012), color, {"bevel": 0.014})
	p.append_array(_pair("leg-left", "leg-right", Vector3(0.136, 0.014, 0.18), Vector3(A.LEG_X, 0.007, -0.012), sole, {"shade": 0.0}))
	if accent.a > 0.0:
		# Side stripes (the silver/grey trainer panels).
		p.append_array(_pair("leg-left", "leg-right", Vector3(0.134, 0.016, 0.07), Vector3(A.LEG_X, 0.03, -0.02), accent, {"shade": 0.0, "rot": Vector3(0, 0, 0)}))
	return p


static func _flipflops(skin: Color, strap: Color) -> Array:
	var p := _pair("leg-left", "leg-right", Vector3(0.12, 0.03, 0.16), Vector3(A.LEG_X, 0.025, -0.012), skin, {"shade": 0.0})
	p.append_array(_pair("leg-left", "leg-right", Vector3(0.13, 0.012, 0.18), Vector3(A.LEG_X, 0.006, -0.012), strap.lightened(0.3), {"shade": 0.0}))
	p.append_array(_pair("leg-left", "leg-right", Vector3(0.125, 0.012, 0.025), Vector3(A.LEG_X, 0.042, 0.03), strap, {"shade": 0.0}))
	return p


static func _torso(color: Color, grow: float = 0.0, extra: Dictionary = {}) -> Dictionary:
	return _b("torso", A.TORSO_SIZE + Vector3(grow, grow * 0.5, grow), A.TORSO_CENTER + Vector3(0, grow * 0.25, 0), color, extra)


# ---------------------------------------------------------------------------
# Hair and accessories
# ---------------------------------------------------------------------------

static func _hair_him() -> Array:
	var h := HAIR_HIM
	var p: Array = [
		_b("head", Vector3(0.43, 0.085, 0.395), Vector3(0, 0.69, -0.012), h, {"bevel": 0.03, "shade": 0.0}),
		_b("head", Vector3(0.42, 0.25, 0.05), Vector3(0, 0.585, -0.19), h, {"shade": 0.0}),
	]
	p.append_array(_pair("head", "head", Vector3(0.035, 0.14, 0.30), Vector3(0.205, 0.625, -0.03), h, {"shade": 0.0}))
	# Messy fringe and tufts.
	for t in [[-0.13, 12.0], [-0.02, -8.0], [0.1, 15.0]]:
		p.append(_b("head", Vector3(0.14, 0.075, 0.07), Vector3(t[0], 0.665, A.HEAD_FRONT - 0.005), h, {"rot": Vector3(-10, 0, t[1]), "shade": 0.0}))
	for t in [[-0.1, 0.03, 20.0], [0.08, -0.06, -25.0], [0.0, 0.1, 10.0], [0.12, 0.08, 35.0]]:
		p.append(_b("head", Vector3(0.13, 0.05, 0.12), Vector3(t[0], 0.738, t[1]), h, {"rot": Vector3(t[2] * 0.5, t[2], t[2] * 0.3), "shade": 0.0}))
	return p


static func _beard() -> Array:
	var c := BEARD
	var f := A.HEAD_FRONT
	var p: Array = [
		# Full beard: chin/jaw block, cheeks, under the chin and a moustache.
		_b("head", Vector3(0.39, 0.105, 0.032), Vector3(0, 0.398, f + 0.01), c, {"bevel": 0.014, "shade": 0.0}),
		_b("head", Vector3(0.34, 0.05, 0.24), Vector3(0, 0.338, 0.06), c, {"bevel": 0.02, "shade": 0.0}),
		_b("head", Vector3(0.17, 0.028, 0.022), Vector3(0, 0.462, f + 0.008), c, {"bevel": 0.01, "shade": 0.0}),
	]
	p.append_array(_pair("head", "head", Vector3(0.07, 0.07, 0.03), Vector3(0.165, 0.465, f + 0.006), c, {"shade": 0.0}))
	p.append_array(_pair("head", "head", Vector3(0.026, 0.2, 0.3), Vector3(0.206, 0.44, 0.02), c, {"shade": 0.0}))
	return p


static func _sunglasses_on_eyes() -> Array:
	var f := A.HEAD_FRONT
	var g := Color(0.06, 0.06, 0.07)
	var p: Array = [_b("head", Vector3(0.09, 0.016, 0.02), Vector3(0, 0.538, f + 0.012), g, {"mat": "glossy", "shade": 0.0})]
	# Two rectangular lenses.
	p.append_array(_pair("head", "head", Vector3(0.14, 0.072, 0.024), Vector3(0.09, 0.522, f + 0.014), g, {"mat": "glossy", "bevel": 0.012, "shade": 0.0}))
	p.append_array(_pair("head", "head", Vector3(0.02, 0.02, 0.2), Vector3(0.203, 0.535, 0.085), g, {"mat": "glossy", "shade": 0.0}))
	return p


static func _hair_her() -> Array:
	var h := HAIR_HER
	var f := A.HEAD_FRONT
	var p: Array = [
		_b("head", Vector3(0.445, 0.085, 0.405), Vector3(0, 0.695, -0.012), h, {"bevel": 0.035, "shade": 0.0}),
		# Long hair down the back, a little lighter at the ends.
		_b("head", Vector3(0.45, 0.52, 0.085), Vector3(0, 0.46, -0.205), h, {"color2": HAIR_HER_TIPS, "shade": 0.0, "bevel": 0.025, "taper": Vector2(1.06, 1.0)}),
	]
	# Side curtains of hair.
	p.append_array(_pair("head", "head", Vector3(0.045, 0.42, 0.30), Vector3(0.218, 0.5, -0.05), h, {"color2": HAIR_HER_TIPS, "shade": 0.0, "bevel": 0.015}))
	# Platinum "money piece" strands framing the face (middle part).
	p.append_array(_pair("head", "head", Vector3(0.05, 0.43, 0.05), Vector3(0.19, 0.49, f + 0.004), BLONDE, {"color2": BLONDE.darkened(0.06), "shade": 0.0, "bevel": 0.012}))
	# The blonde pieces start at the parting and sweep back over the top.
	p.append_array(_pair("head", "head", Vector3(0.14, 0.04, 0.2), Vector3(0.085, 0.725, 0.07), BLONDE, {"rot": Vector3(0, 0, -10), "shade": 0.0, "bevel": 0.012}))
	return p


static func _sunglasses_on_head() -> Array:
	var g := Color(0.07, 0.07, 0.08)
	var p: Array = [_b("head", Vector3(0.37, 0.065, 0.05), Vector3(0, 0.745, 0.105), g, {"mat": "glossy", "rot": Vector3(-25, 0, 0), "bevel": 0.01, "shade": 0.0})]
	p.append_array(_pair("head", "head", Vector3(0.02, 0.02, 0.2), Vector3(0.21, 0.73, 0.0), g, {"mat": "glossy", "shade": 0.0}))
	return p


static func _tote_bag(color: Color) -> Array:
	return [
		_b("torso", Vector3(0.035, 0.17, 0.15), Vector3(-0.16, 0.2, -0.02), color, {"rot": Vector3(0, 0, 4)}),
		_b("torso", Vector3(0.02, 0.17, 0.02), Vector3(-0.15, 0.33, -0.02), color.darkened(0.1), {"shade": 0.0}),
	]


static func _crossbody_bag() -> Array:
	return [
		# Strap from the left shoulder across the chest to the right hip.
		_b("torso", Vector3(0.022, 0.31, 0.012), Vector3(-0.005, 0.27, A.TORSO_CENTER.z + 0.103), BLACK, {"rot": Vector3(0, 0, 40), "shade": 0.0}),
		_b("torso", Vector3(0.022, 0.20, 0.012), Vector3(0.0, 0.29, A.TORSO_CENTER.z - 0.103), BLACK, {"rot": Vector3(0, 0, -40), "shade": 0.0}),
		_b("torso", Vector3(0.1, 0.12, 0.05), Vector3(-0.105, 0.2, A.TORSO_CENTER.z + 0.115), BLACK, {"mat": "satin", "bevel": 0.015}),
	]


# ---------------------------------------------------------------------------
# Wardrobes
# ---------------------------------------------------------------------------

static func _outfit_him(outfit: String) -> Array:
	var skin := SKIN_HIM
	var p: Array = []
	p.append_array(_arms(skin))
	p.append_array(_legs(skin))
	match outfit:
		"all_black":
			p.append(_torso(BLACK, 0.024))
			p.append_array(_sleeves(BLACK, 0.12, 0.108))
			p.append_array(_leg_cloth(BLACK, 0.075, A.HIP_Y + 0.012, 0.142, 0.15, {"taper": Vector2(1.08, 1.05)}))
			p.append_array(_shoes(WHITE, Color(0.85, 0.84, 0.8), Color(0.55, 0.57, 0.6)))
			p.append_array(_leg_cloth(WHITE, 0.035, 0.07, 0.116, 0.126, {"shade": 0.0}))
			p.append_array(_crossbody_bag())
		"beach":
			var trunks := Color(0.26, 0.66, 0.74)
			p.append(_torso(skin, 0.0, {"shade": 0.03}))
			p.append(_b("torso", Vector3(A.TORSO_SIZE.x + 0.016, 0.04, A.TORSO_SIZE.z + 0.016), Vector3(0, 0.188, A.TORSO_CENTER.z), trunks, {"shade": 0.0}))
			p.append_array(_leg_cloth(trunks, 0.09, A.HIP_Y + 0.012, 0.135, 0.145, {"taper": Vector2(1.06, 1.04)}))
			# White side stripe.
			p.append_array(_pair("leg-left", "leg-right", Vector3(0.008, 0.09, 0.05), Vector3(A.LEG_X + 0.068, 0.135, -0.028), WHITE, {"shade": 0.0}))
			p.append_array(_flipflops(skin, Color(0.2, 0.3, 0.45)))
		_:  # amsterdam: beige oversized tee, grey denim cargo shorts, white trainers
			var tee := Color(0.82, 0.73, 0.63)
			var denim := Color(0.70, 0.71, 0.70)
			p.append(_torso(tee, 0.026))
			p.append_array(_sleeves(tee, 0.13, 0.112))
			p.append_array(_leg_cloth(denim, 0.07, A.HIP_Y + 0.012, 0.145, 0.152, {"taper": Vector2(1.1, 1.06)}))
			# Cargo pockets on the outside of each leg.
			p.append_array(_pair("leg-left", "leg-right", Vector3(0.02, 0.055, 0.07), Vector3(A.LEG_X + 0.077, 0.12, -0.02), denim.darkened(0.08), {"shade": 0.0}))
			p.append_array(_leg_cloth(WHITE, 0.035, 0.068, 0.116, 0.126, {"shade": 0.0}))
			p.append_array(_shoes(WHITE, Color(0.86, 0.84, 0.78), Color(0.58, 0.6, 0.63)))
			p.append_array(_crossbody_bag())
	return p


static func _outfit_her(outfit: String) -> Array:
	var skin := SKIN_HER
	var p: Array = []
	p.append_array(_arms(skin, 0.074))
	p.append_array(_legs(skin))
	match outfit:
		"silver_dress":
			var silver := Color(0.86, 0.87, 0.9)
			p.append(_torso(skin, 0.0, {"shade": 0.03}))
			p.append(_b("torso", Vector3(A.TORSO_SIZE.x + 0.014, 0.13, A.TORSO_SIZE.z + 0.014), Vector3(0, 0.24, A.TORSO_CENTER.z), silver, {"mat": "shiny", "shade": 0.05}))
			p.append_array(_pair("torso", "torso", Vector3(0.018, 0.08, A.TORSO_SIZE.z + 0.016), Vector3(0.07, 0.335, A.TORSO_CENTER.z), silver, {"mat": "shiny", "shade": 0.0}))
			# Flared skirt part of the dress (on the torso so legs swing beneath it).
			p.append(_b("torso", Vector3(0.29, 0.15, 0.2), Vector3(0, 0.115, A.TORSO_CENTER.z), silver, {"mat": "shiny", "taper": Vector2(1.38, 1.4), "shade": 0.12}))
			p.append_array(_shoes(silver.darkened(0.1), Color(0.75, 0.75, 0.78)))
		"skirt_top":
			var top := Color(0.98, 0.84, 0.86)
			var skirt := Color(0.13, 0.13, 0.16)
			p.append(_torso(top, 0.018))
			p.append_array(_sleeves(top, 0.09, 0.096))
			p.append(_b("torso", Vector3(0.29, 0.1, 0.205), Vector3(0, 0.14, A.TORSO_CENTER.z), skirt, {"taper": Vector2(1.3, 1.32), "shade": 0.08}))
			# Pleats: a few lighter stripes on the front.
			for x: float in [-0.09, -0.03, 0.03, 0.09]:
				p.append(_b("torso", Vector3(0.012, 0.095, 0.01), Vector3(x * 1.1, 0.14, A.TORSO_CENTER.z + 0.124), skirt.lightened(0.12), {"rot": Vector3(-12, 0, 0), "shade": 0.0}))
			p.append_array(_leg_cloth(WHITE, 0.035, 0.1, 0.116, 0.126, {"shade": 0.0}))
			p.append_array(_shoes(BLACK, Color(0.2, 0.2, 0.2)))
		"bikini":
			var bik := Color(0.98, 0.45, 0.47)
			p.append(_torso(skin, 0.0, {"shade": 0.03}))
			p.append(_b("torso", Vector3(A.TORSO_SIZE.x + 0.012, 0.05, A.TORSO_SIZE.z + 0.012), Vector3(0, 0.31, A.TORSO_CENTER.z), bik, {"shade": 0.0}))
			p.append(_b("torso", Vector3(A.TORSO_SIZE.x + 0.012, 0.035, A.TORSO_SIZE.z + 0.012), Vector3(0, 0.188, A.TORSO_CENTER.z), bik, {"shade": 0.0}))
			p.append_array(_leg_cloth(bik, 0.158, A.HIP_Y + 0.012, 0.118, 0.128, {"shade": 0.0}))
			p.append_array(_pair("torso", "torso", Vector3(0.012, 0.06, 0.012), Vector3(0.06, 0.355, A.TORSO_CENTER.z + 0.08), bik, {"shade": 0.0}))
			p.append_array(_flipflops(skin, Color(0.98, 0.6, 0.3)))
		_:  # gallery: black jacket with white piping, white top, black wide trousers, tote bag
			var jacket := Color(0.1, 0.1, 0.11)
			p.append(_torso(jacket, 0.03, {"mat": "satin"}))
			p.append_array(_sleeves(jacket, A.ARM_END - 0.085, 0.104, "satin"))
			p.append_array(_pair("arm-left", "arm-right", Vector3(0.012, 0.106, 0.106), Vector3(A.ARM_END - 0.006, A.SHOULDER.y - 0.006, A.SHOULDER.z), WHITE, {"shade": 0.0}))
			# Zip and piping.
			var front := A.TORSO_CENTER.z + A.TORSO_SIZE.z * 0.5 + 0.017
			p.append(_b("torso", Vector3(0.012, 0.2, 0.008), Vector3(0.012, 0.27, front), WHITE, {"shade": 0.0}))
			p.append_array(_pair("torso", "torso", Vector3(0.008, 0.2, 0.008), Vector3(0.1, 0.27, front), WHITE, {"shade": 0.0}))
			# White top showing at the neck.
			p.append(_b("torso", Vector3(0.09, 0.05, 0.01), Vector3(-0.03, 0.35, front), WHITE, {"shade": 0.0}))
			p.append_array(_leg_cloth(jacket, 0.03, A.HIP_Y + 0.012, 0.14, 0.15, {"taper": Vector2(1.3, 1.25), "mat": "satin"}))
			p.append_array(_shoes(BLACK, Color(0.25, 0.25, 0.25)))
			p.append_array(_tote_bag(Color(0.93, 0.89, 0.8)))
	return p

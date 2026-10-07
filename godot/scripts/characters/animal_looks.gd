class_name AnimalLooks
extends RefCounted
## The island's animal neighbours as little bipedal chibis (big heads, ears,
## muzzles and tails, a shirt each) on the same rig as you two, so they walk,
## wave and sit with the shared animations. look(species, shirt) -> Avatar look.

const A = preload("res://scripts/characters/avatar.gd")
const L = preload("res://scripts/characters/avatar_looks.gd")

const SPECIES := {
	"cat": {"fur": Color(1.0, 0.8, 0.52), "fur2": Color(1.0, 0.95, 0.88), "accent": Color(0.9, 0.55, 0.28), "inner": Color(1.0, 0.7, 0.72)},
	"dog": {"fur": Color(0.86, 0.66, 0.42), "fur2": Color(0.98, 0.9, 0.78), "accent": Color(0.55, 0.36, 0.22), "inner": Color(0.6, 0.4, 0.28)},
	"bunny": {"fur": Color(0.98, 0.96, 0.94), "fur2": Color(1.0, 1.0, 1.0), "accent": Color(0.95, 0.75, 0.82), "inner": Color(1.0, 0.72, 0.8)},
	"fox": {"fur": Color(0.95, 0.5, 0.18), "fur2": Color(1.0, 0.97, 0.92), "accent": Color(0.25, 0.16, 0.14), "inner": Color(0.3, 0.2, 0.18)},
	"penguin": {"fur": Color(0.16, 0.2, 0.3), "fur2": Color(0.98, 0.98, 0.98), "accent": Color(1.0, 0.68, 0.18), "inner": Color(0.16, 0.2, 0.3)},
	"koala": {"fur": Color(0.62, 0.64, 0.68), "fur2": Color(0.92, 0.92, 0.94), "accent": Color(0.2, 0.2, 0.24), "inner": Color(0.96, 0.92, 0.92)},
}


static func look(species: String, shirt: Color, shirt2: Color = Color(1, 1, 1)) -> Dictionary:
	var s: Dictionary = SPECIES.get(species, SPECIES["cat"])
	var fur: Color = s["fur"]
	var fur2: Color = s["fur2"]
	var accent: Color = s["accent"]
	var inner: Color = s["inner"]
	var p: Array = []
	var face := {"eyes": "round", "mouth": "none", "blush": true, "skin": fur}
	var hc := A.HEAD_CENTER
	var top := hc.y + A.HEAD_SIZE.y * 0.5
	var front := A.HEAD_FRONT
	# Head (a little wider and rounder than ours) + cheeks.
	p.append(L._b("head", A.HEAD_SIZE + Vector3(0.03, 0.0, 0.0), hc, fur, {"bevel": 0.06, "shade": 0.06}))
	match species:
		"cat", "fox":
			# Pointy ears: tapered blocks flipped so the narrow end is up.
			p.append_array(L._pair("head", "head", Vector3(0.12, 0.13, 0.07), Vector3(0.12, top + 0.05, hc.z - 0.02), fur, {"rot": Vector3(180, 0, -12), "taper": Vector2(0.2, 0.3), "shade": 0.0}))
			p.append_array(L._pair("head", "head", Vector3(0.07, 0.08, 0.02), Vector3(0.12, top + 0.035, hc.z + 0.02), inner, {"rot": Vector3(180, 0, -12), "taper": Vector2(0.2, 0.3), "shade": 0.0}))
			# White muzzle, nose.
			p.append(L._b("head", Vector3(0.17, 0.09, 0.05), Vector3(0, hc.y - 0.07, front + 0.012), fur2, {"shade": 0.0}))
			p.append(L._b("head", Vector3(0.045, 0.03, 0.03), Vector3(0, hc.y - 0.04, front + 0.04), Color(0.9, 0.45, 0.5) if species == "cat" else Color(0.15, 0.1, 0.1), {"shade": 0.0}))
			face["whiskers"] = species == "cat"
			if species == "cat":
				# Tabby stripes on the forehead.
				for i in 3:
					p.append(L._b("head", Vector3(0.025, 0.012, 0.06), Vector3(-0.04 + i * 0.04, top - 0.002, hc.z + 0.1), accent, {"shade": 0.0}))
		"dog":
			# Floppy ears hanging at the sides, a tan muzzle and a black nose.
			p.append_array(L._pair("head", "head", Vector3(0.07, 0.2, 0.12), Vector3(0.235, hc.y + 0.03, hc.z - 0.02), accent, {"rot": Vector3(0, 0, 12), "shade": 0.05}))
			p.append(L._b("head", Vector3(0.2, 0.11, 0.07), Vector3(0, hc.y - 0.065, front + 0.02), fur2, {"shade": 0.0}))
			p.append(L._b("head", Vector3(0.07, 0.045, 0.04), Vector3(0, hc.y - 0.03, front + 0.055), Color(0.12, 0.1, 0.1), {"mat": "glossy", "shade": 0.0}))
		"bunny":
			p.append_array(L._pair("head", "head", Vector3(0.075, 0.28, 0.05), Vector3(0.075, top + 0.13, hc.z), fur, {"rot": Vector3(0, 0, -6), "shade": 0.0}))
			p.append_array(L._pair("head", "head", Vector3(0.04, 0.21, 0.015), Vector3(0.075, top + 0.13, hc.z + 0.026), inner, {"rot": Vector3(0, 0, -6), "shade": 0.0}))
			p.append(L._b("head", Vector3(0.045, 0.03, 0.03), Vector3(0, hc.y - 0.045, front + 0.012), Color(1.0, 0.55, 0.65), {"shade": 0.0}))
			face["mouth"] = "cat"
		"penguin":
			face["mask"] = fur2
			p.append(L._b("head", Vector3(0.1, 0.05, 0.09), Vector3(0, hc.y - 0.05, front + 0.04), accent, {"rot": Vector3(-10, 0, 0), "shade": 0.0, "taper": Vector2(1.0, 1.0)}))
		"koala":
			p.append_array(L._pair("head", "head", Vector3(0.17, 0.17, 0.07), Vector3(0.22, top - 0.02, hc.z - 0.01), fur, {"shade": 0.0}))
			p.append_array(L._pair("head", "head", Vector3(0.11, 0.11, 0.02), Vector3(0.22, top - 0.02, hc.z + 0.03), inner, {"shade": 0.0}))
			p.append(L._b("head", Vector3(0.09, 0.11, 0.05), Vector3(0, hc.y - 0.04, front + 0.02), accent, {"mat": "glossy", "shade": 0.0}))
	# Body: a shirt (striped hem), furry arms and legs, paws.
	var body_fur := fur2 if species == "penguin" else fur
	p.append(L._torso(shirt, 0.02, {"color2": shirt.darkened(0.08)}))
	p.append(L._b("torso", Vector3(A.TORSO_SIZE.x + 0.03, 0.03, A.TORSO_SIZE.z + 0.03), A.TORSO_CENTER + Vector3(0, -0.09, 0), shirt2, {"shade": 0.0}))
	p.append_array(L._arms(fur if species != "penguin" else fur, 0.085))
	p.append_array(L._sleeves(shirt, 0.07, 0.105))
	p.append_array(L._legs(body_fur if species != "penguin" else fur))
	var paw := accent if species == "penguin" else fur.darkened(0.1)
	p.append_array(L._pair("leg-left", "leg-right", Vector3(0.12, 0.045, 0.16), Vector3(A.LEG_X, 0.024, -0.005), paw, {"shade": 0.0}))
	# Tails.
	var tz := A.TORSO_CENTER.z - A.TORSO_SIZE.z * 0.5
	match species:
		"cat":
			p.append(L._b("torso", Vector3(0.045, 0.045, 0.2), Vector3(0, 0.2, tz - 0.08), fur, {"rot": Vector3(-35, 0, 0), "shade": 0.0}))
			p.append(L._b("torso", Vector3(0.045, 0.13, 0.045), Vector3(0, 0.3, tz - 0.17), accent, {"shade": 0.0}))
		"dog":
			p.append(L._b("torso", Vector3(0.05, 0.05, 0.14), Vector3(0, 0.22, tz - 0.06), fur, {"rot": Vector3(-50, 0, 0), "shade": 0.0}))
		"bunny":
			p.append(L._b("torso", Vector3(0.09, 0.09, 0.08), Vector3(0, 0.17, tz - 0.03), Color(1, 1, 1), {"shade": 0.0}))
		"fox":
			p.append(L._b("torso", Vector3(0.11, 0.11, 0.26), Vector3(0, 0.18, tz - 0.12), fur, {"rot": Vector3(-30, 0, 0), "shade": 0.0, "taper": Vector2(0.7, 0.7)}))
			p.append(L._b("torso", Vector3(0.09, 0.09, 0.08), Vector3(0, 0.27, tz - 0.25), fur2, {"rot": Vector3(-30, 0, 0), "shade": 0.0}))
		"koala":
			pass
		"penguin":
			p.append(L._b("torso", Vector3(0.1, 0.03, 0.08), Vector3(0, 0.12, tz - 0.03), fur, {"rot": Vector3(-20, 0, 0), "shade": 0.0}))
	return {"parts": p, "face": face}

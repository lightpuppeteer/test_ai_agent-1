class_name SpecialTrees
extends RefCounted
## A few landmark trees around the island, a little bigger than the rest, each
## with a small wooden plaque: press E next to one to read its name and a
## curiosity about it.

## [kind, species/fruit, where (roughly), title, curiosity]
const TREES := [
	["species", "sakura", Vector3(10, 0, -44), "🌸 Cherry Blossom (Sakura)",
		"In Japan, friends gather under the blossoms for hanami picnics. The flowers only last a week or two, a sweet reminder to enjoy the moment together."],
	["species", "jacaranda", Vector3(-14, 0, -24), "💜 Jacaranda",
		"Every May and June, jacarandas turn the streets of Lisbon purple. They came from South America, and some say a blossom landing on your head brings good luck."],
	["species", "cork", Vector3(-46, 0, -22), "🌳 Cork Oak (Sobreiro)",
		"Portugal produces about half of the world's cork. The bark is stripped by hand only every nine years, and the tree is never cut down: it just grows a new coat."],
	["species", "olive", Vector3(46, 0, -6), "🫒 Olive Tree (Oliveira)",
		"Olive trees can live for thousands of years. One in Mouriscas, Portugal, is believed to be more than 3,000 years old, and it still grows olives."],
	["species", "maple", Vector3(38, 0, -30), "🍁 Japanese Maple",
		"In autumn its leaves turn fiery red. In Japan, going out to admire them is called momijigari, which means \"red-leaf hunting\"."],
	["species", "magnolia", Vector3(-20, 0, -30), "🤍 Magnolia",
		"Magnolias are older than bees! Their flowers first evolved to be pollinated by beetles, which is why their petals are so thick and tough."],
	["species", "ginkgo", Vector3(-36, 0, -6), "💛 Ginkgo",
		"Ginkgos are \"living fossils\", almost unchanged for over 200 million years. A few ginkgo trees in Hiroshima survived the 1945 bomb and are still growing today."],
	["fruit", "orange", Vector3(-40, 0, 4), "🍊 Orange Tree",
		"Sweet oranges spread across Europe thanks to Portuguese traders. That's why an orange is \"portokali\" in Greek and \"portakal\" in Turkish: named after Portugal!"],
	["species", "wisteria", Vector3(16, 0, -24), "💜 Wisteria",
		"Wisteria vines can live for well over a hundred years. The great wisteria at Ashikaga Flower Park in Japan spreads over almost 2,000 m² on a giant trellis."],
	["stonepine", "", Vector3(-24, 0, -54), "🌲 Stone Pine (Pinheiro-manso)",
		"Its cones hold pinhões, the little pine nuts in Portuguese sweets. Each cone takes about three years to ripen!"],
	["species", "plum", Vector3(54, 0, -24), "🌺 Plum Blossom",
		"Plum trees bloom at the very end of winter, even before the cherry blossoms, so in Japan and China they are a symbol of hope and resilience."],
]


static func build(b: IslandBuilder) -> void:
	for t in TREES:
		var want: Vector3 = t[2]
		var at := b.clear_ground_near(want, 2.4)
		var tree := b.tree(at.x, at.z, t[0], 1, t[1], 1.25)
		tree.name = "Special_" + (t[1] if t[1] != "" else t[0])
		# A little plaque at the foot of the tree, on the side facing the island centre.
		var out := Vector3(-at.x, 0, -11.0 - at.z)
		out.y = 0.0
		out = out.normalized() if out.length() > 0.1 else Vector3.BACK
		var pp := at + out * 1.35
		pp.y = b.ground(pp.x, pp.z)
		var plaque := Props3D.blocks([
			Props3D.b(Vector3(0.08, 0.55, 0.08), Vector3(0, 0.27, 0), Color(0.5, 0.33, 0.2), {"bevel": 0.02}),
			Props3D.b(Vector3(0.42, 0.26, 0.05), Vector3(0, 0.58, 0.02), Color(0.62, 0.42, 0.26), {"bevel": 0.03, "rot": Vector3(-20, 0, 0)}),
			Props3D.b(Vector3(0.34, 0.18, 0.02), Vector3(0, 0.585, 0.05), Color(0.98, 0.95, 0.88), {"bevel": 0.01, "rot": Vector3(-20, 0, 0), "shade": 0.0}),
		])
		b.add_child(plaque)
		plaque.global_position = pp
		plaque.rotation.y = atan2(out.x, out.z)
		var it := Interactable.new()
		it.kind = "look"
		it.prompt = "Read about this tree"
		it.radius = 2.2
		b.add_child(it)
		it.global_position = pp + Vector3(0, 0.5, 0)
		var title: String = t[3]
		var fact: String = t[4]
		it.used.connect(func(_by: Node, _seat: Node3D) -> void:
			if Game.hud:
				Game.hud.popup(title, fact, 7.0))
		if t[1] in ["sakura", "plum", "jacaranda"]:
			_falling_petals(b, at, {"sakura": Color(1.0, 0.8, 0.88), "plum": Color(1.0, 0.7, 0.8), "jacaranda": Color(0.8, 0.7, 1.0)}[t[1]])


## A gentle drift of petals under a blossom tree.
static func _falling_petals(parent: Node3D, at: Vector3, col: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 6.0
	p.preprocess = 6.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.8, 0.3, 1.8)
	pm.direction = Vector3(0.3, -1, 0.2)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0.15, -0.35, 0.05)
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.07)
	q.material = FX._billboard_mat(FX.dot_texture(), col)
	p.draw_pass_1 = q
	p.visibility_range_end = 45.0
	parent.add_child(p)
	p.global_position = at + Vector3(0, 3.4, 0)

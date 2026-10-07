extends Node3D
## Boots the island: atmosphere → terrain → sea → props → characters → UI → chapter.

const VILLAGERS := [
	{"species": "animal-cat", "name": "Mochi", "pos": Vector3(-4.0, 0, -6.0), "color": Color(0.98, 0.62, 0.45), "voice": 1.15,
		"lines": ["Oh! Hello, hello! Isn't the fountain extra sparkly today?",
			"I'm practising my café order. Uma bica, por favor! ...Was that right? Don't tell me.",
			"I saw you two at the pizza place. He dropped a pepperoni. I saw EVERYTHING.",
			"Rumour has it there's a cat in town who judges people. Professionally.",
			"If you throw a coin in the fountain, you get... wet fingers. That's the whole wish."]},
	{"species": "animal-dog", "name": "Biscuit", "pos": Vector3(-20.0, 0, 13.5), "color": Color(0.85, 0.65, 0.35), "voice": 0.85,
		"lines": ["Woof! Perfect weather for a stroll on the promenade!",
			"Did you two come to see the sunset again? You're very predictable. I love it.",
			"I tried to fetch the moon once. Still working on it.",
			"Pro tip: the bench by the dock has the best view AND the fewest seagulls."]},
	{"species": "animal-bunny", "name": "Pip", "pos": Vector3(4.0, 0, 30.0), "color": Color(0.95, 0.55, 0.7), "voice": 1.4,
		"lines": ["The sand is warm and the sea is cold. Just right!",
			"I found a shell shaped like a heart. Then I found one shaped like a potato. Life is balance.",
			"Sunscreen is just lotion that believes in itself.",
			"Have you seen that road across the sea? I walked halfway and got scared of a crab."]},
	{"species": "animal-fox", "name": "Maple", "pos": Vector3(-2.0, 0, -50.0), "color": Color(0.98, 0.5, 0.3), "voice": 1.0,
		"lines": ["From up here you can see the whole island.",
			"This bench is the best spot for sunsets. Trust me, I've done extensive research.",
			"I once saw the volcano sneeze. It was very rude.",
			"Love is like a picnic: someone always brings too much ham."]},
	{"species": "animal-penguin", "name": "Waddles", "pos": Vector3(30.0, 0, 27.0), "color": Color(0.4, 0.6, 0.95), "voice": 0.95,
		"lines": ["The pier is my favourite place to think about fish.",
			"I'd go for a swim, but I just dried off.",
			"People ask why I wear a tuxedo every day. I ask why you don't.",
			"The boats out there bob up and down all day. Relatable."]},
	{"species": "animal-koala", "name": "Kiko", "pos": Vector3(14.0, 0, -11.0), "color": Color(0.6, 0.7, 0.75), "voice": 0.75,
		"lines": ["Zzz... oh! I was resting my eyes. Both of them. Very thoroughly.",
			"I heard the cinema is showing a scary movie. I'll watch it... with my eyes closed.",
			"The hotel beds are so big you can get lost. I got lost. For a nap.",
			"New neighbours in the purple house? Tell the cat I said hi. From a distance."]},
]


func _ready() -> void:
	var atmo := Atmosphere.new()
	atmo.name = "Atmosphere"
	add_child(atmo)
	var terrain := Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var ocean := Ocean.new()
	ocean.name = "Ocean"
	add_child(ocean)
	var island := IslandBuilder.new()
	island.name = "Island"
	add_child(island)

	var hud := HUD.new()
	hud.name = "HUD"
	add_child(hud)
	var player := Player.new()
	player.name = "Player"
	add_child(player)
	var partner := Partner.new()
	partner.name = "Partner"
	add_child(partner)
	var rig := CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)

	var car := Car.new()
	car.name = "Car"
	add_child(car)
	car.global_position = Vector3(-30.0, terrain.height_at(-30.0, 8.0) + 0.6, 8.0)
	car.rotation.y = deg_to_rad(90.0)

	for v in VILLAGERS:
		var vil := Villager.new()
		vil.species = v["species"]
		vil.display_name = v["name"]
		vil.color = v["color"]
		vil.lines.assign(v["lines"])
		vil.voice = v.get("voice", 1.0)
		var p: Vector3 = v["pos"]
		p.y = terrain.height_at(p.x, p.z) + 0.2
		vil.position = p
		vil.name = "Villager_" + v["name"]
		add_child(vil)

	var fx := AmbientFX.new()
	fx.name = "AmbientFX"
	add_child(fx)

	var quests := QuestManager.new()
	quests.name = "Quests"
	add_child(quests)

	var chapters := ChapterManager.new()
	chapters.name = "Chapters"
	add_child(chapters)
	var chapter := chapters.start(Game.options.get("chapter", "shore"), false)

	if Game.options.has("shots"):
		var director := ShotDirector.new()
		director.name = "ShotDirector"
		add_child(director)
	elif Game.options.has("skip_title"):
		hud.show_title(chapter.title, chapter.subtitle)
	else:
		var title := TitleScreen.new()
		title.name = "TitleScreen"
		add_child(title)
		title.started.connect(func() -> void: hud.show_title(chapter.title, chapter.subtitle))

class_name QuestData
extends RefCounted
## ✿ The quests. ✿  (Conversations live in scripts/story/story_data.gd.)
##
## Quest keys:
##   id, title          unique id (saved) and the name shown in the tracker / log (Q)
##   giver              optional villager name: talk to them to start it
##   after              optional id of a quest that must be done first
##   intro              lines the giver says when starting
##   steps              see below
##   finish_title, finish   a memory card shown at the end
##   new_game_plus      true on the last quest: finishing it makes every quest replayable
##
## Step types (each can have "text" for the tracker, "then": [actions] run when it completes):
##   go            {"to": "fountain", "radius": 3.0}          landmark, spot or Vector3
##   enter         {"place": "pizza", "carrying": "yoggi"}    be inside a place (optionally carrying something)
##   talk          {"who": "Pip" | "partner", "lines": [...]}
##   dialogue      {"tree": "pizza"}                          a branching conversation (StoryData)
##   sit_together  {"tag": "pizza_table"} or {"at": "lookout"}  both sitting on the same bench/seats
##   lie_together  {"tag": "beach_towel"} or {"at": "beach_towels"}
##   car_together  both in the car
##   use           {"tag": "oasis_chest"}                     press E on that thing
##   collect       {"item": "shell", "count": 3, "spawn": [...]}   deliver {"item": "shell", "to": "Pip"}
##   decorate      the house has everything each room needs
##   catch         catch Yoggi (he runs away a few times first!)
##   time          {"preset": "golden", "auto": true}
##   drive         {"to": "pier", "radius": 6.0}              photo {"at": "pier_end"}
##   memory        {"title": "…", "lines": [...]}             wait {"seconds": 2.0}

## Named places for "to" / "at" (Places.spots also works: pizza_door, cinema_door, oasis, picnic…).
const LANDMARKS := {
	"spawn": Vector3(2, 2, 13.4),
	"fountain": Vector3(0, 2, -11),
	"town_hall": Vector3(0, 2, -21),
	"promenade": Vector3(0, 2, 13.5),
	"beach": Vector3(0, 1, 28),
	"beach_towels": Vector3(-9.9, 1, 29),
	"pier": Vector3(34, 1.3, 32),
	"pier_end": Vector3(34, 1.3, 46),
	"west_cove": Vector3(-60, 1, 24),
	"lookout": Vector3(4, 5.2, -47),
	"car": Vector3(-30, 2, 8),
	"hotel": Vector3(-51, 2, -15),
}

const QUESTS := [
	{
		"id": "first_date",
		"title": "1 · The First Date",
		"steps": [
			{"type": "talk", "who": "partner", "text": "Talk to him",
				"lines": ["So... there's this little pizza place in town.", "Want to go? It's a date. A real one. With napkins and everything."]},
			{"type": "go", "to": "pizza_door", "radius": 3.0, "text": "Walk to Pizzeria Amore together"},
			{"type": "enter", "place": "pizza", "text": "Go inside"},
			{"type": "sit_together", "tag": "pizza_table", "text": "Sit at the table by the window"},
			{"type": "dialogue", "tree": "pizza", "then": ["snacks_off"]},
		],
		"finish_title": "Our first date",
		"finish": ["Pizza, nerves, one rogue pepperoni and a dot of sauce on his nose.", "Honestly? Perfect."],
	},
	{
		"id": "beach_kiss",
		"title": "2 · Sun, Sand & Smooth Talk",
		"after": "first_date",
		"steps": [
			{"type": "talk", "who": "partner", "text": "Talk to him", "lines": ["Beach day? I'll bring the towels. You bring the sunscreen and the patience for my jokes."]},
			{"type": "go", "to": "beach_towels", "radius": 4.0, "text": "Go to the beach towels"},
			{"type": "lie_together", "at": "beach_towels", "text": "Lie down on the towels together"},
			{"type": "dialogue", "tree": "beach_flirt"},
			{"type": "car_together", "text": "Head back to the car together (get in the driver's seat)"},
			{"type": "dialogue", "tree": "car_kiss"},
		],
		"finish_title": "First kiss",
		"finish": ["Worst pickup line in human history. Best kiss in human history.", "The dashboard agreed."],
	},
	{
		"id": "picnic",
		"title": "3 · The Over-Prepared Picnic",
		"after": "beach_kiss",
		"steps": [
			{"type": "talk", "who": "partner", "text": "Talk to him", "lines": ["I packed a picnic! A small one. Light. Very reasonable. Meet me in the garden?"]},
			{"type": "go", "to": "picnic", "radius": 5.0, "text": "Go to the garden (east of town)"},
			{"type": "use", "tag": "picnic_basket", "text": "Unpack the picnic basket", "then": ["feast"]},
			{"type": "dialogue", "tree": "picnic_food"},
			{"type": "lie_together", "tag": "picnic_blanket", "text": "Lie down on the blanket together"},
			{"type": "dialogue", "tree": "picnic_chill"},
		],
		"finish_title": "Cloud watching",
		"finish": ["He ate the ham. Most of it. She ate one strawberry and stole three grapes.", "Best afternoon."],
	},
	{
		"id": "cinema",
		"title": "4 · Movie Night",
		"after": "picnic",
		"steps": [
			{"type": "talk", "who": "partner", "text": "Talk to him", "lines": ["Movie night? There are three films on. I promise not to cry. (I will cry.)"]},
			{"type": "go", "to": "cinema_door", "radius": 3.0, "text": "Go to the cinema"},
			{"type": "enter", "place": "cinema", "text": "Go inside"},
			{"type": "use", "tag": "popcorn_stand", "text": "Grab popcorn & drinks", "then": ["popcorn"]},
			{"type": "sit_together", "tag": "cinema_seats", "text": "Find two seats together"},
			{"type": "dialogue", "tree": "cinema", "then": ["snacks_off"]},
		],
		"finish_title": "Movie night",
		"finish": ["Horror, comedy or drama — the real show was the popcorn heist."],
	},
	{
		"id": "moving_in",
		"title": "5 · Moving In",
		"after": "cinema",
		"steps": [
			{"type": "talk", "who": "partner", "text": "Talk to him", "lines": ["Big news: the keys are ours! Let's go turn that empty house into OUR house."]},
			{"type": "go", "to": "house_door", "radius": 3.0, "text": "Go to our house (purple roof)"},
			{"type": "enter", "place": "house", "text": "Go inside"},
			{"type": "decorate", "text": "Decorate: living room, bedroom and office (use the boxes)"},
			{"type": "dialogue", "tree": "moving_in"},
			{"type": "go", "to": "her_place", "radius": 6.0, "text": "Go to your old place to get Yoggi"},
			{"type": "catch", "text": "Catch Yoggi (he's fast — keep trying!)"},
			{"type": "enter", "place": "house", "carrying": "yoggi", "text": "Bring Yoggi home", "then": ["yoggi_home"]},
			{"type": "dialogue", "tree": "yoggi_home"},
		],
		"finish_title": "Home",
		"finish": ["A couch aligned to the millimetre, a TV, too many plants and one judgemental cat.", "Home."],
	},
	{
		"id": "spa",
		"title": "6 · Spa Day",
		"after": "moving_in",
		"steps": [
			{"type": "talk", "who": "partner", "text": "Talk to him", "lines": ["I booked us a spa day at the hotel. There will be cucumbers. On our FACES."]},
			{"type": "go", "to": "hotel_door", "radius": 3.0, "text": "Go to the Hotel & Spa (west of town)"},
			{"type": "enter", "place": "hotel", "text": "Go inside"},
			{"type": "lie_together", "tag": "spa_bed", "text": "Flop onto the enormous bed together"},
			{"type": "dialogue", "tree": "spa", "then": ["cucumbers_off"]},
		],
		"finish_title": "Spa day",
		"finish": ["Twelve pillows. One fort. Zero intention of ever checking out."],
	},
	{
		"id": "oasis",
		"title": "7 · The Oasis",
		"after": "spa",
		"steps": [
			{"type": "talk", "who": "partner", "text": "Talk to him", "lines": ["Hey... come with me? There's something I want to show you. Across the sea."]},
			{"type": "go", "to": "causeway_start", "radius": 5.0, "text": "Go to the road across the sea (east end of the beach)"},
			{"type": "dialogue", "tree": "volcano_road"},
			{"type": "go", "to": "oasis", "radius": 10.0, "text": "Follow the road to the oasis"},
			{"type": "use", "tag": "oasis_chest", "text": "Open the chest"},
			{"type": "dialogue", "tree": "volcano_ring"},
		],
		"finish_title": "The ring",
		"finish": ["He asked on one knee. The volcano said yes first.", "So did she."],
	},
	{
		"id": "anniversary",
		"title": "8 · Happy Anniversary",
		"after": "oasis",
		"new_game_plus": true,
		"steps": [
			{"type": "talk", "who": "partner", "text": "Talk to him", "lines": ["Meet me on the beach tonight? I've got one more surprise."]},
			{"type": "time", "preset": "night", "auto": true, "text": "Wait for the night"},
			{"type": "go", "to": "ending", "radius": 5.0, "text": "Meet him on the beach"},
			{"type": "dialogue", "tree": "ending"},
		],
	},
	# Side quest.
	{
		"id": "shells_for_pip",
		"title": "Seashells for Pip",
		"giver": "Pip",
		"intro": [
			"Oh! Hi! I'm making a necklace but I only have one shell...",
			"Could you find me three pretty seashells on the beach? I'd go myself but I'm, uh, very busy. Sunbathing.",
		],
		"steps": [
			{"type": "collect", "item": "shell", "name": "seashell", "count": 3, "text": "Find 3 seashells on the beach",
				"model": "nature-kit/stone_smallFlatA", "color": Color(1.0, 0.82, 0.86),
				"spawn": [Vector3(-22, 0, 31), Vector3(8, 0, 33), Vector3(24, 0, 30)]},
			{"type": "deliver", "item": "shell", "to": "Pip", "text": "Bring the shells to Pip",
				"lines": ["Wow, they're perfect! Thank you!", "Here, one is for you two. ♡"]},
		],
		"finish_title": "Seashell necklace",
		"finish": ["Pip made matching shell necklaces for us."],
	},
]

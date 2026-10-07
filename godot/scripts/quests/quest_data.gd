class_name QuestData
extends RefCounted
## ✿ Write your quests here. ✿
##
## Each quest is a dictionary. Steps run in order; each step waits for
## something to happen and shows its "text" in the tracker (top right).
##
## Quest keys:
##   id            unique name (used for saving progress)
##   title         shown in the tracker and the quest log (Q)
##   giver         optional villager name: talk to them to start the quest.
##                 Without a giver the quest starts by itself (after `after`).
##   after         optional id of a quest that must be finished first
##   intro         lines the giver says when starting the quest
##   steps         see below
##   finish        lines shown when the quest is done (as a memory card)
##   finish_title  title of that memory card
##
## Step types (every step can also have "text" for the tracker):
##   go            {"type": "go", "to": "fountain", "radius": 3.0}
##                 "to" is a landmark name (see LANDMARKS) or a Vector3.
##   talk          {"type": "talk", "who": "Pip", "lines": ["…"]}
##                 who: a villager name or "partner".
##   sit_together  {"type": "sit_together", "at": "lookout_bench"}   ("at" optional)
##   lie_together  {"type": "lie_together", "at": "beach_towels"}    ("at" optional)
##   collect       {"type": "collect", "item": "shell", "count": 3,
##                  "spawn": [Vector3(…), …], "name": "seashell", "model": "nature-kit/…"}
##                 Spawns pick-ups; press E on them.
##   deliver       {"type": "deliver", "item": "shell", "to": "Pip", "lines": ["…"]}
##   time          {"type": "time", "preset": "golden"}   (day | golden | night)
##                 Shows a hint; the time changes when you press T (or "auto": true).
##   drive         {"type": "drive", "to": "pier", "radius": 6.0}
##   photo         {"type": "photo", "at": "pier_end", "radius": 6.0}   take a photo (F12) there
##   memory        {"type": "memory", "title": "…", "lines": ["…"]}     show a memory card
##   wait          {"type": "wait", "seconds": 2.0}

## Named places you can use in "to" / "at".
const LANDMARKS := {
	"spawn": Vector3(2, 2, 13.4),
	"fountain": Vector3(0, 2, -11),
	"town_hall": Vector3(0, 2, -21),
	"market": Vector3(-10, 2, -6),
	"cafe": Vector3(6.5, 2, -16.5),
	"promenade": Vector3(0, 2, 13.5),
	"beach": Vector3(0, 1, 28),
	"beach_towels": Vector3(-9.9, 1, 29),
	"pier": Vector3(34, 1.3, 32),
	"pier_end": Vector3(34, 1.3, 46),
	"west_cove": Vector3(-60, 1, 24),
	"lookout": Vector3(4, 5.2, -47),
	"lookout_bench": Vector3(4, 5.2, -47),
	"picnic": Vector3(8.5, 5.2, -48.5),
	"car": Vector3(-30, 2, 8),
	"west_houses": Vector3(-28, 2, -11),
	"east_houses": Vector3(28, 2, -11),
}

const QUESTS := [
	{
		"id": "shells_for_pip",
		"title": "Seashells for Pip",
		"giver": "Pip",
		"intro": [
			"Oh! Hi! I'm making a necklace but I only have one shell...",
			"Could you find me three pretty seashells on the beach?",
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
	{
		"id": "sunset_date",
		"title": "Sunset on the hill",
		"after": "shells_for_pip",
		"steps": [
			{"type": "talk", "who": "partner", "text": "Talk to him", "lines": ["Want to watch the sunset from the hill?"]},
			{"type": "go", "to": "lookout", "radius": 5.0, "text": "Walk up to the lookout"},
			{"type": "time", "preset": "golden", "auto": true, "text": "Wait for the golden hour"},
			{"type": "sit_together", "at": "lookout_bench", "text": "Sit together on the bench"},
			{"type": "wait", "seconds": 3.0},
		],
		"finish_title": "Sunset on the hill",
		"finish": ["We watched the sky turn pink.", "(Write your own memory here.)"],
	},
]

class_name StoryData
extends RefCounted
## ✿ All the conversations. ✿
## Format: see Dialogue (scripts/story/dialogue.gd). "who": "him" / "her" / a villager name.
## Choices are her replies: ["what she says", "next node id", ["optional", "actions"]].

const TREES := {
	# ------------------------------------------------------------------ QUEST 1
	"pizza": {
		"start": {"who": "him", "do": ["face", "cam:close"],
			"say": "I hope you like your pizza with a side of extreme anxiety. On a scale from 1 to 10, I am currently at a solid 12 of being terrified I'll mess this up.",
			"choices": [
				["Just don't drop a slice on your nice shirt and you'll survive at an 8/10.", "a"],
				["Relax! Worst-case scenario, we blame all awkward silences on garlic breath.", "b"],
			]},
		"a": {"who": "him", "do": ["pepperoni"],
			"say": "(Instantly drops a piece of pepperoni onto his lap) Instruction unclear. Pepperoni deployed to pants. Does a 7.5 still qualify for a second date?",
			"choices": [
				["Only if you sacrifice that crust to me as a fine for bad napkin skills.", "c"],
				["I'm lowering it to a 5, but I'll grant extra credit if you buy dessert.", "c"],
			]},
		"b": {"who": "him",
			"say": "Deal. But if I pass out from nervousness, promise you'll order a tiramisu as CPR.",
			"choices": [
				["I'll do CPR, but I am definitely eating half the tiramisu while you recover.", "c"],
				["I'll just steal your wallet to pay for the pizza while you're down.", "c"],
			]},
		"c": {"who": "him",
			"say": "Fair response. So... slice check: cheesy, hot, and slightly burning the roof of my mouth. How's yours?",
			"choices": [
				["Perfect. Though I think you have a tiny dot of sauce right on your nose.", "end"],
				["Better than yours, because mine isn't currently stuck to my pants.", "end"],
			]},
		"end": {"who": "him", "after": ["hearts", "cam:reset"],
			"say": "That sauce is a deliberate style choice. It accents my eyes. Now eat your slice before I invent another disaster!"},
	},

	# ------------------------------------------------------------------ QUEST 2
	"beach_flirt": {
		"start": {"who": "him", "do": ["cam:close"],
			"say": "Are you a sunburn? Because you're making me sweat, my heart is burning, and I can't stop looking at you.",
			"choices": [
				["Wow. That was officially the worst pickup line in human history.", "a"],
				["Careful, keep talking like that and I might actually pretend to be impressed.", "b"],
			]},
		"a": {"who": "him",
			"say": "Hey, I spent five whole minutes in the car practicing that line in the rearview mirror! Show some respect for the craft.",
			"choices": [
				["The craft needs a rewrite. Put me in the car before you try a sandcastle pun.", "end"],
				["Fine, I'll give you a 2 out of 10 for effort, strictly because you look cute saying it.", "end"],
			]},
		"b": {"who": "him",
			"say": "Pretend? I aim for genuine awe! But fine, let's head back to the car before the tide decides to wash my dignity away.",
			"choices": [
				["Good idea, your dignity was looking a little soggy anyway.", "end"],
				["Lead the way, smooth talker.", "end"],
			]},
		"end": {"who": "him", "after": ["cam:reset"], "say": "To the car! (Last one there has to listen to my playlist.)"},
	},
	"car_kiss": {
		"start": {"who": "him", "do": ["music:night", "cam:close"],
			"say": "(Engine off, soft ocean radio ambient background) So... terrible pickup lines aside. I really had a great time today.",
			"choices": [
				["Me too. Even if your smooth-talking needs work.", "kiss"],
				["Shut up for a second and come here.", "kiss"],
			]},
		"kiss": {"who": "narrator", "do": ["kiss", "levelup", "wait:0.4"],
			"say": "(He leans in and kisses her. The sweet moment pauses as a loud arcade 'LEVEL UP' sound effect blasts from the car dashboard.)",
			"after": ["popup:🏆 ACHIEVEMENT UNLOCKED|BOYFRIEND ACQUIRED. (Note: Non-refundable, non-returnable.)", "music:", "cam:reset"]},
	},

	# ------------------------------------------------------------------ QUEST 3
	"picnic_food": {
		"start": {"who": "him", "do": ["face", "cam:close"],
			"say": "(Unpacking a massive cooler) Okay! I kept it simple. I brought roast chicken, three aged cheeses, a baguette, potato salad, pasta, grapes, and an emergency backup ham.",
			"choices": [
				["Did you plan a picnic for us or are we provisioning a medieval village?", "a"],
				["I brought a single strawberry, so I think between us we have a balanced meal.", "b"],
			]},
		"a": {"who": "him",
			"say": "A village must be prepared! What if a dragon attacks and we need to bribe it with cured meats?",
			"choices": [
				["I think the dragon would die of a food coma first. Hand over a grape.", "c"],
				["I'm actually not hungry at all... I'll just nibble this single strawberry.", "c"],
			]},
		"b": {"who": "him",
			"say": "A single strawberry?! You're making my emergency ham look absurdly aggressive.",
			"choices": [
				["It IS aggressive! You brought enough protein to power a gym.", "c"],
				["I'm saving room so I can watch you try to eat an entire ham by yourself.", "c"],
			]},
		"c": {"who": "him",
			"say": "Fine, more ham for me. Lay down on the towel, pass the speaker, and hit play.",
			"choices": [
				["Only if I get to choose the playlist. No weird synth music.", "end"],
				["Deal. Just don't roll over onto the potato salad.", "end"],
			]},
		"end": {"who": "him", "after": ["cam:reset"],
			"say": "Hey, sleeping on a potato salad pillow builds character. Now shh, let's just watch the clouds and chill."},
	},
	"picnic_chill": {
		"start": {"who": "narrator", "do": ["music:golden", "cam:sky", "wait:2.5", "hearts"],
			"say": "(The speaker plays something soft. A cloud drifts by that looks suspiciously like a ham.)",
			"next": "him"},
		"him": {"who": "him", "say": "...that cloud is definitely a ham. I'm not hungry. I'm just saying.", "after": ["wait:1.0", "music:", "cam:reset"]},
	},

	# ------------------------------------------------------------------ QUEST 4
	"cinema": {
		"start": {"who": "him", "do": ["cam:close"],
			"say": "Popcorn secured, giant soda locked in position. What flavor of emotional damage are we watching tonight?",
			"choices": [
				["Let's do the Horror movie. I want to see you jump out of your seat.", "horror", ["movie:horror", "cam:reset", "wait:9.5"]],
				["Rom-Com/Comedy. I need something as ridiculously silly as us.", "comedy", ["movie:comedy", "cam:reset", "wait:8.0"]],
				["Deep Drama. I want to see if you have working tear ducts.", "drama", ["movie:drama", "cam:reset", "wait:10.0"]],
			]},
		"horror": {"who": "him", "do": ["rumble"],
			"say": "I don't jump! I just aggressively blink to protect my eyes from jump scares!",
			"choices": [
				["You literally just squeezed my hand so hard you stopped my circulation.", "post"],
				["If the monster appears, I'm using you as a human shield.", "post"],
			]},
		"comedy": {"who": "him",
			"say": "(Snorts soda while laughing) Okay, that joke hit way harder than it should have.",
			"choices": [
				["Did you just inhale a soda ice cube? Are you dying?", "post"],
				["I laughed so hard my stomach hurts. Best movie choice ever.", "post"],
			]},
		"drama": {"who": "him",
			"say": "(Sniffling into a napkin) It's not sad... the butter on the popcorn is just very emotionally complex...",
			"choices": [
				["Are you actually crying over a fictional dog?!", "post"],
				["Here, take my sleeve to wipe your tears, big guy.", "post"],
			]},
		"post": {"who": "him", "do": ["wait:2.0", "movie:off"],
			"say": "10/10 cinema experience. Though next time, I'm buying my own popcorn so you stop stealing the extra-buttered pieces!",
			"after": ["hearts"]},
	},

	# ------------------------------------------------------------------ QUEST 5
	"moving_in": {
		"start": {"who": "him", "do": ["face", "cam:close"],
			"say": "The couch is aligned to the millimeter. The TV is mounted. The living room decor is immaculate. We have officially moved in!",
			"choices": [
				["It looks amazing... but it's way too quiet.", "boss"],
				["Great work! Now it's time for the final boss phase of moving.", "boss"],
			]},
		"boss": {"who": "him",
			"say": "The final boss... You mean Yoggi?",
			"choices": [
				["Yep. We need to go pick him up and secure him in the cat carrier.", "quest"],
				["He requires three catnip bribes and a tactical distraction before he enters the carrier.", "quest"],
			]},
		"quest": {"who": "him",
			"say": "Accepting quest: 'Operation Catch Yoggi'. Reward: Cat hair on every couch cushion we just set up.",
			"choices": [
				["Hey! Yoggi's fur is an aesthetic interior design choice!", "end"],
				["Don't complain, he's the real landlord here anyway.", "end"],
			]},
		"end": {"who": "him", "after": ["cam:reset"], "say": "Right. Tactical catnip deployed. To her place!"},
	},
	"yoggi_home": {
		"start": {"who": "him", "do": ["cam:close"],
			"say": "(After bringing Yoggi home) He's officially sitting on my keyboard, staring at me with pure judgment. Home sweet home.",
			"after": ["hearts", "cam:reset"]},
	},

	# ------------------------------------------------------------------ QUEST 6
	"spa": {
		"start": {"who": "him", "do": ["cucumbers", "cam:close"],
			"say": "(Laying in an oversized hotel bed with cucumber slices over his eyes) I can't see a single thing right now, but I feel incredibly luxurious. Like a very relaxed, expensive salad.",
			"choices": [
				["You look ridiculous, but honestly, this bed is huge.", "a"],
				["Careful, if you move too fast, your eye-cucumbers are going to slide into your mouth.", "b"],
			]},
		"a": {"who": "him",
			"say": "Ridiculous? This is peak self-care! There are at least twelve pillows on this bed. I'm building a fort.",
			"choices": [
				["If you build a pillow fort, I am invading it immediately.", "end"],
				["Leave space for me! I'm never checking out of this hotel.", "end"],
			]},
		"b": {"who": "him",
			"say": "If a cucumber falls in my mouth, that's just a free healthy snack. Efficiency at its finest.",
			"choices": [
				["You are impossible. Hand me two cucumbers for my eyes too.", "end"],
				["I'm going to jump in the pool before you turn this into a full salad bowl.", "end", ["sfx:splash"]],
			]},
		"end": {"who": "him", "after": ["hearts", "cam:reset"],
			"say": "Pool later! Pillow fort now! Cancel our mail, we live in this hotel room forever."},
	},

	# ------------------------------------------------------------------ QUEST 7
	"volcano_road": {
		"start": {"who": "him", "do": ["face", "cam:volcano"],
			"say": "Look ahead—that road across the ocean leads straight to that little oasis island. And... wait, is that a giant volcano behind it?",
			"choices": [
				["A mysterious chest in a palm tree oasis? What game are we playing, Zelda?", "go"],
				["The volcano behind it looks cool, but why are you looking so nervous again?", "go"],
			]},
		"go": {"who": "him", "after": ["cam:reset"], "say": "No questions! Just open the chest at the center of the oasis!"},
	},
	"volcano_ring": {
		"start": {"who": "narrator", "do": ["face", "cam:close"],
			"say": "(Inside the chest, something small and shiny catches the light...)",
			"choices": [
				["Wait... there's a ring inside here? A relationship ring?", "kneel"],
				["Is this a trap or are you about to do something crazy?", "kneel"],
			]},
		"kneel": {"who": "him", "do": ["kneel", "cam:volcano", "erupt", "wait:1.2"],
			"say": "(Drops to one knee instantly as the volcano in the background loudly erupts with dramatic cinematic fire and lava) No trap! Will you officially date me?",
			"choices": [
				["YES! Absolutely yes! But also, SHOULD WE BE RUNNING FROM LAUGHTER AND LAVA?!", "end", ["ring", "stand", "kiss"]],
				["YES! That eruption was timed way too well, you nerd!", "end", ["ring", "stand", "kiss"]],
			]},
		"end": {"who": "him",
			"say": "The volcano was expensive to hire, but totally worth it for that 'Yes'!",
			"after": ["popup:💍 RELATIONSHIP RING EQUIPPED|+100 Love · +50 Fire resistance", "cam:reset"]},
	},

	# ------------------------------------------------------------------ QUEST 8
	"ending": {
		"start": {"who": "him", "do": ["letterbox", "face", "fireworks", "cam:sky", "wait:2.5"],
			"say": "(Standing on the edge of the island as colorful fireworks explode across the night sky) Happy 1st Year Anniversary... Here's to many, many more together.",
			"choices": [
				["Even if we have to go through all these ridiculous quests all over again?", "a"],
				["You did pretty good for Year One. What's your plan for Year Two?", "b"],
			]},
		"a": {"who": "him",
			"say": "ESPECIALLY if we do them all over again. I'd replay every single second with you.",
			"choices": [
				["Then kiss me before the fireworks finish!", "kiss"],
				["Deal. But in Year Two, you eat the emergency ham yourself.", "kiss"],
			]},
		"b": {"who": "him",
			"say": "Year Two? Bigger volcanoes, more pizza, and teaching Yoggi to actually respect my authority.",
			"choices": [
				["Good luck with Yoggi. But kiss me first!", "kiss"],
				["Sounds like a plan. Happy Anniversary!", "kiss"],
			]},
		"kiss": {"who": "narrator", "do": ["cam:sky", "kiss", "hearts", "wait:1.5"],
			"say": "(He leans in for a romantic kiss under the fireworks as the screen softly fades to black.)",
			"after": ["fade_out", "title:Happy 1st Year Anniversary|to more together! ♡", "wait:4.5", "fireworks_off", "fade_in", "letterbox_off", "cam:reset",
				"popup:🔁 NEW GAME+ UNLOCKED!|You can now replay all anniversary quests anytime. (Yoggi the cat is still judging your stats.)"]},
	},
}

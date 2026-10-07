class_name Dialogue
extends RefCounted
## Runs branching conversations.
##
## A tree is a Dictionary of nodes keyed by id; the conversation starts at "start".
##   {"who": "him", "say": "line", "next": "id"}                       a line
##   {"who": "him", "say": "line", "choices": [["her reply", "id"], …]} she picks a reply
##   "do": ["kiss", "popup:TITLE|TEXT", …]   actions run before the line (see Cutscene)
##   "after": [...]                          actions run after the line
## A choice can carry actions too: ["reply", "next_id", ["action", …]].
## Her chosen reply is spoken back in her dialogue box, then the tree continues.

const HER_COLOR := Color(0.95, 0.5, 0.62)
const HIM_COLOR := Color(0.45, 0.66, 0.95)


static func her_name() -> String:
	return Game.HER_NAME


static func speaker(who: String) -> Array:
	match who:
		"him":
			var nm: String = Game.partner.display_name if Game.partner else "Him"
			return [nm, HIM_COLOR, 0.8]
		"her":
			return [her_name(), HER_COLOR, 1.25]
		"", "narrator":
			return ["", Color(0.6, 0.6, 0.6), 1.0]
	var v: Node = Game.player.get_tree().current_scene.get_node_or_null("Villager_" + who) if Game.player else null
	if v:
		return [who, v.color, v.voice]
	return [who, Color(0.98, 0.62, 0.45), 1.0]


static func run(tree: Dictionary, start: String = "start") -> void:
	var hud: HUD = Game.hud
	Game.story_lock = true
	var id := start
	var guard := 0
	while id != "" and tree.has(id) and guard < 200:
		guard += 1
		var n: Dictionary = tree[id]
		await Cutscene.run_actions(n.get("do", []))
		var sp := speaker(n.get("who", "him"))
		if n.has("choices"):
			var opts: Array = []
			for c in n["choices"]:
				opts.append(c[0])
			var i: int = await hud.ask(sp[0], style(n.get("say", "…")), opts, sp[1], sp[2])
			var choice: Array = n["choices"][i]
			var her := speaker("her")
			await hud.say(her[0], [_strip_action(choice[0])], her[1], her[2])
			if choice.size() > 2:
				await Cutscene.run_actions(choice[2])
			await Cutscene.run_actions(n.get("after", []))
			id = choice[1] if choice.size() > 1 else ""
		else:
			if n.has("say"):
				var lines: Array = []
				for l in (n["say"] if n["say"] is Array else [n["say"]]):
					lines.append(style(str(l)))
				await hud.say(sp[0], lines, sp[1], sp[2])
			await Cutscene.run_actions(n.get("after", []))
			id = n.get("next", "")
	Game.story_lock = false


## Stage directions "(…)" are shown in soft italics.
static func _strip_action(t: String) -> String:
	return style(t)


static func style(t: String) -> String:
	var re := RegEx.new()
	re.compile("\\(([^)]*)\\)")
	return re.sub(t, "[color=#a2876e][i]($1)[/i][/color]", true)

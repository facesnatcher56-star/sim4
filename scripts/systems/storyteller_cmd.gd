class_name StorytellerCmd
extends RefCounted
## Command handlers of the storyteller (called from command_actions.gd, action "storyteller"):
##   choose {id, option}                         answer a twist (only the player of that household)
##   configure {personality, custom{}, off[]}    the storyteller personality, the Custom sliders (0..1: frequency, severity, balance, mercy) and the categories
##                                               switched off. HOST ONLY: in co-op the host's choice applies for everybody.
## settings_args() builds the configure args from the player's settings (New Game and the settings screen use it).

const CATS := ["money", "home", "crime", "social", "work", "health", "town", "arcs"]

static func run(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	match str(a.get("action", "")):
		"choose":
			return StorytellerChoice.answer(int(a.get("id", -1)), str(a.get("option", "")), int(e["player_id"]))
		"configure":
			if int(e["player_id"]) != Players.LOCAL:
				return {"ok": false, "msg": "Only the host can change the storyteller."}
			return configure(a)
	return {"ok": false, "msg": "That storyteller action does not exist."}

static func configure(a: Dictionary) -> Dictionary:
	if a.has("personality") and not Storyteller.set_personality(str(a["personality"]), a.get("custom", {})):
		return {"ok": false, "msg": "That storyteller does not exist."}
	if a.has("off"):
		for c in CATS:
			Storyteller.set_cat(c, not (a["off"] as Array).has(c))
	return {"ok": true, "msg": "The storyteller is now %s." % Storyteller.label()}

## The player's settings as configure args: personality, the four Custom sliders (settings are 0..100) and the switched-off categories.
static func settings_args() -> Dictionary:
	var off: Array = []
	for c in CATS:
		if not GameSettings.get_bool("story_cat_" + c):
			off.append(c)
	return {"personality": GameSettings.get_str("storyteller"),
		"custom": {"frequency": GameSettings.get_int("storyteller_freq") / 100.0, "severity": GameSettings.get_int("storyteller_sev") / 100.0,
			"balance": GameSettings.get_int("storyteller_good") / 100.0, "mercy": GameSettings.get_int("storyteller_mercy") / 100.0}, "off": off}

## Send the settings to the sim through the command layer (host only takes effect).
static func apply_settings() -> Dictionary:
	return Commands.run({"player_id": Players.local_id, "action": "storyteller", "args": dict_with_action("configure", settings_args())})

static func dict_with_action(act: String, a: Dictionary) -> Dictionary:
	var d: Dictionary = a.duplicate(true)
	d["action"] = act
	return d

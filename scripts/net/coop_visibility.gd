class_name CoopVisibility
extends RefCounted
## What a player may know. Stage 2 rule: everybody sees everybody's folk (position, activity, mood, name tag); controls, panels, money
## and goals in the UI are limited to your own household (the HUD asks `is_mine`). The tier work (17.3) replaces `visible_to` with
## per-person tiers: CoopLive asks it for every entity before it goes on the wire, so nothing else has to change.

## May `player_id` receive data about `entity` (a Folk, or anything with `household_id` / `tile`)? Hook for the tier rules; true for now.
static func visible_to(_player_id: int, _entity) -> bool:
	return true

static func is_mine(folk, player_id: int = -1) -> bool:
	var pid := player_id if player_id > 0 else Players.local_id
	return folk != null and int(folk.household_id) > 0 and Players.household_of(pid) == int(folk.household_id)

## Name of the player whose household a folk belongs to ("" for townies / strangers).
static func owner_name(folk) -> String:
	if folk == null:
		return ""
	var p := Players.player_of(int(folk.household_id))
	return Players.name_of(p) if p > 0 and Players.table.has(p) else ""

## A toast is for a player unless it is about ANOTHER player's folk (by name) and none of their own.
static func toast_for(player_id: int, text: String) -> bool:
	var mine := Players.household_of(player_id)
	var other_hit := false
	for f in WorldIface.all_folk():
		if int(f.household_id) <= 0 or f.has_meta("visitor") or not (str(f.name) in text):
			continue
		if int(f.household_id) == mine:
			return true
		if Players.player_of(int(f.household_id)) > 0 and Players.table.has(Players.player_of(int(f.household_id))):
			other_hit = true
	return not other_hit

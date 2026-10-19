class_name CoopHash
extends RefCounted
## Stable hash of the simulation state that matters, used to compare host and client after a snapshot (and later for
## periodic desync checks). Deterministic and cheap: one canonical string (sorted folk, needs rounded to whole numbers,
## integer-only values) -> SHA-256 (first 16 hex chars). Only state that survives SaveLoad snapshot -> restore is included, so
## a client that loaded the host's snapshot gets the SAME hash. Only household folk (household_id > 0) are hashed: the crowd
## NPCs are not restored from a snapshot. Stage 2+ adds more fields here once SaveLoad round-trips them. Add a field here only when SaveLoad round-trips it exactly.

## Needs are quantised to whole numbers with a deliberately odd offset: JSON loses the last digits of a float, and a plain
## round() flips when a value sits exactly on x.5 (decay constants make that common). x.5863 is practically never hit.
const BIAS := 0.4137

static func of_world() -> String:
	return str(canonical().sha256_text().substr(0, 16))

static func canonical() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var clk = SimEnv.clock()
	parts.append("m%d" % int(clk.total_minutes))
	parts.append("n%d" % Folk._next_id)
	var folk: Array = WorldIface.all_folk()
	var ids: Array = []
	var by_id: Dictionary = {}
	for f in folk:
		if int(f.household_id) <= 0:
			continue          # strangers (crowd, visitors) are rebuilt locally by each machine and are not part of the shared state yet
		ids.append(int(f.id))
		by_id[int(f.id)] = f
	ids.sort()
	var households: Dictionary = {}
	for id in ids:
		var f: Folk = by_id[id]
		households[int(f.household_id)] = true
		var need_ids: Array = f.needs.keys()
		need_ids.sort()
		var ns := PackedStringArray()
		for nid in need_ids:
			ns.append("%s=%d" % [nid, floori((f.needs[nid] as Stat).value + BIAS)])
		parts.append("f%d@%d,%d,%d h%d [%s]" % [id, f.tile.x, f.tile.y, int(f.level), int(f.household_id), ",".join(ns)])
	var hh: Array = households.keys()
	hh.sort()
	for h in hh:
		if int(h) > 0:
			parts.append("c%d=%d" % [h, Economy.balance(int(h))])
	var w = WorldIface.world()
	if w != null and "objects" in w:
		parts.append("o%d" % (w.objects as Dictionary).size())
	return "|".join(parts)

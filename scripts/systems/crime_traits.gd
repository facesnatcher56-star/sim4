class_name CrimeTraits
extends RefCounted
## Task 09c: crime-leaning traits. Defined in data/justice.json ("traits", same shape as data/traits.json) and merged into the traits table at
## install time, so the trait pickers, autonomy, the editor and Genetics (inheritance + random extras read the whole table) pick them up.
##   dishonest    lies, cheats, frauds          kleptomaniac  compulsive petty theft, mostly harmless
##   vengeful     grudges last much longer      reckless      fights, risky driving, accidents
## Townies get them at low frequency (data: traits_townie_chance), rolled once per townie.

const IDS := ["dishonest", "kleptomaniac", "vengeful", "reckless"]

static func install() -> void:
	var table: Dictionary = SimEnv.data().traits()
	if table.is_empty():
		return
	var src: Dictionary = JusticeState.sect("traits")
	for id in src:
		if not table.has(id):
			table[id] = (src[id] as Dictionary).duplicate(true)

## Low-frequency townie generation: each townie rolls once.
static func roll_townies() -> void:
	var ch: Dictionary = JusticeState.sect("traits_townie_chance")
	for tid in CrimePerson.townies_only():
		var t: Dictionary = Story.townies[tid]
		if bool(t.get("crime_traits_rolled", false)):
			continue
		t["crime_traits_rolled"] = true
		for id in IDS:
			if JusticeState.chance(float(ch.get(id, 0.03))):
				var tr: Array = t.get("traits", [])
				if not tr.has(id) and not _conflicts(tr, id):
					tr.append(id)
					t["traits"] = tr

static func _conflicts(traits: Array, id: String) -> bool:
	var def: Dictionary = (JusticeState.sect("traits").get(id, {}) as Dictionary)
	for c in def.get("conflicts", []):
		if traits.has(str(c)):
			return true
	return false

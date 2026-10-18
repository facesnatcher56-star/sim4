class_name FamilyContent
extends RefCounted
## Runtime content for the family layer (idempotent, like SysContent). The literal content lives in data/content_family.json
## (merged by ContentMerge): interactions feed_baby, change_diaper, rock_to_sleep, play_with_baby, hold_baby, teach_walking/
## talking/potty, have_wedding, divorce, ask_to_move_in, adopt_child, sleep_crib; buffs pregnant_t1..t3, crying, baby_crying,
## engaged, married, newlywed, divorced, widowed, bereaved, new_parent, proud_parent (+ need decay on the hidden stage_baby /
## stage_toddler markers); and `sleep_crib` on the `crib` object (defined in data/objects.json).
## Code here: babies cannot use beds / sofas (`sleep` tagged interactions) and cannot clean themselves after accidents.
## Call FamilyContent.install() after SysContent.install(); SysContent.install_all() does.

const MARK := "_fam_patch"

static func install() -> void:
	var data = SimEnv.data()
	var inter: Dictionary = data.interactions()
	if inter.is_empty():
		return
	if not data.buffs().has("stage_baby"):
		SysContent.install()      # the stage_* marker buffs are created there
	var fresh: bool = not inter.has("feed_baby")
	ContentMerge.install(data.get_table("content_family"))
	if fresh:
		_patch_existing(inter)

## Babies need adults for everything except sleeping in the crib.
static func _patch_existing(inter: Dictionary) -> void:
	for iid in inter:
		var d: Dictionary = inter[iid]
		if bool(d.get(MARK, false)) or str(iid) == "sleep_crib":
			continue
		d[MARK] = true
		var tags: Array = d.get("tags", [])
		if tags.has("sleep") and not tags.has("emergency"):
			var tests: Array = d.get("tests", [])
			tests.append({"lacks_buff": "stage_baby"})
			d["tests"] = tests
		if d.has("emergency") and str(iid) == "have_accident":
			var em: Array = d["emergency"]
			em.append({"lacks_buff": "stage_baby"})
			d["emergency"] = em

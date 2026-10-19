class_name NeighborhoodContent
extends RefCounted
## Runtime content injected into the shared Data tables (idempotent, like SysContent / FamilyContent). Everything comes from
## data/venues.json "content": cloned object defs (park_bench, cafe_counter, grocery_cooler), venue interactions
## (order_coffee, order_meal, order_round, buy_groceries, buy_fresh_snack, sys_staff) and venue buffs.
## Also patches the live World.defs so lots built by LotLoader can use the new objects.

const MARK := "_hood_content"

static func install() -> void:
	var cfg: Dictionary = (SimEnv.data().get_table("venues") as Dictionary).get("content", {})
	ContentMerge.install(cfg, MARK, {"_sys_gate": true})      # _sys_gate: keep SysContent from re-gating these
	BuildingContent.install()                                  # multi-floor building objects (hospital bed, ...)
	Works.install()                                            # task 31: the works lot stations and work interactions

## Ids of every venue buff the crowd/ambient code may apply.
static func buff_ids() -> Array:
	var cfg: Dictionary = (SimEnv.data().get_table("venues") as Dictionary).get("content", {})
	return (cfg.get("buffs", {}) as Dictionary).keys()
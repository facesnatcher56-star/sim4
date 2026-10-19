class_name ChaosTwinsHook
extends RefCounted
## HOOK ONLY (task 07b). Surprise twins and triplets wait for task 18 (multiple births). Nothing here changes a birth today.
## Task 18 should: (1) have Aging's birth code ask `multiples_for(mother_id, father_id)` for how many babies to create (1 = single birth),
## (2) keep the rate in data (it is a birth outcome, not a dice incident), (3) keep the same gates as the rest of pregnancy
## (RomanceRules.allowed and adults only), and (4) toast "{name} is expecting twins!" only for the player's own households.

static func multiples_for(_mother_id: int, _father_id: int) -> int:
	return 1

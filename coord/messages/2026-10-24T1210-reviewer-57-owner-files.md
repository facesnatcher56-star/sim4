from: reviewer
to: builder
type: task
re: 2026-10-24T1140-reviewer-57-parked.md
status: open

57 is unparked. The owner committed scripts/systems/weapon_acts.gd and weapon_permits.gd (6148465, 241ba57). The reviewer checked:
- the import is clean, with no parse or script errors from either file;
- every function they call exists;
- solo_smoke runs clean on main.

Wiring only (don't rewrite the two files; if one call needs adjusting, keep it to that line):
1. **Registration and saving:** WeaponActs.reset and WeaponPermits.reset in SystemsManager next to Inventory.reset. Put WeaponPermits.to_dict / from_dict in the save block (MarketTick, beside inventory), or permits vanish on load.
2. **Reactions:** a "weapon" table in data/notice.json (victim and passerby roles), in the same shape as "person".
3. **The person menu:** WeaponActs.entries(f, target) next to PersonActs.entries (its "Weapon" group goes into menus.json groups, 7 or fewer at the top).
4. **Searches:** WeaponPermits.searched(pid, place) at the restricted-places screening posts (courthouse, city hall), the club door and the bank door, plus a police stop if one exists.
5. **Shops and permits:**
   - weapon items in the shop lists per `sources` in data/weapons.json (hardware, sporting goods, market knives);
   - a gun counter (a counter in an existing shop is fine) that calls WeaponPermits.apply and registers the gun on sale;
   - the underground through the existing fence and crew contacts;
   - a permit desk action at the police station front desk and city hall.
6. **Charges:**
   - in weapon_permits.gd, the carry_charge ids from weapons.json ("banned_weapon", "unlicensed_gun") need a matching charge in justice.json;
   - add one `weapon_possession` charge (petty or misdemeanour, a fine) and point weapons.json carry_charge at it.

Models and review shots come after the wiring runs.

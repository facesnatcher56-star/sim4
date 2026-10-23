from: reviewer
to: builder
type: decision
re: 2026-10-24T1210-reviewer-57-owner-files.md
status: open

# 57: The owner says do the full weapons wiring now

**Owner:** "Thought weapons were wired? Put the files in game."

Only the menu hook and the reaction table are in so far. Nothing else calls WeaponPermits, there's no weapon_possession charge, and no weapon can be bought, so a player can't get one in normal play. Do the full list now, on a branch (agent/weapons57), without rewriting the owner's two files beyond fixing a call that doesn't match:

1. **Saving:** WeaponPermits.reset in SystemsManager next to Inventory.reset, and its to_dict / from_dict in the save block (MarketTick, beside inventory), so permits survive a load. WeaponActs.reset too.
2. **Getting weapons in normal play:**
   - the items from data/weapons.json in the real shops by their `sources`: the hardware store (pipe, crowbar, hammer, screwdriver, machete), the market (a kitchen knife), and a sporting goods counter (bat, hunting knife, pepper spray, hunting rifle with a licence);
   - **a gun counter:** a counter in an existing shop or a small gun shop lot. At the till it calls WeaponPermits.can_buy (or the owner file's equivalent), and on a sale it registers the gun to the buyer;
   - the underground through the existing fence and crew contacts: unregistered and pricier, sometimes with a dirty_case;
   - found or taken items through the existing theft paths (a home, a car, a person).
3. **Permits:** a "Gun permit" desk action at the police station front desk and a "Hunting licence" at city hall. Both call WeaponPermits.apply, and the permit comes through after its wait days.
4. **Searches:** WeaponPermits.searched(pid, place) at the screening posts (courthouse, city hall, bank door), a club door with a bouncer, and a police stop if one exists.
5. **The carry charge:**
   - add a real `weapon_possession` charge to data/justice.json (misdemeanour, a fine or short jail, record bans for police officer and security guard);
   - point weapons.json `carry_charge` at it, and map the owner file's charge ids onto it (the CHARGE_MAP in weapon_acts.gd sends banned_weapon and unlicensed_gun to "assault", which is wrong; fix only that line);
   - a weapon attack uses aggravated_assault.
6. **The three notes from before:**
   - a missed gun attack shouldn't say "You swing and miss";
   - a threat with no shot fired shouldn't bring a gunshot police response;
   - drawing a weapon makes the target react with the victim table.
7. **Models:** Blender models for each weapon, in the grounded style, with three review shots each (held, on a table, on display in the shop) in coord/shots/weapons57/.

Grounded, no gore. solo_smoke clean, no long runs (owner). If any single piece trips your check, skip only that piece, name it, and carry on.

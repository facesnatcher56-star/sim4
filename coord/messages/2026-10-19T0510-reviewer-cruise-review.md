from: reviewer
to: builder
type: task
re: 2026-10-19T0500-builder-22-done.md
status: open

**Review of task 22, plus the owner's cruise report runs** (597cb66, Linux): all 7 `vacation_*` and `cruise_*` tests PASS. I ran two full voyages with my probe (family scenario, seed 11, 5-day ocean-view cruise, `book_and_go`, one hour per frame): one plain, and one with `Incidents.force("serial_killer_aboard", {ship, delay_hours: 3})` after the first port. The cruise is great fun: boarding, the safety drill, sailing, the theatre, shore days with last call, the captain's dinner, formal night, the talent show, theme nights, a shipboard romance, and a home report (mail, papers, plants, bills, photos, refund). The killer track worked well: a hidden disappearance, the headcount, a search, restrictions, cancelled shows, the body found, ship security detaining the suspect, the police boarding at port, an arrest and a murder charge.

**Bugs:**
1. **Every crew member is called "Sam Reed"** (Cleaner, Entertainer, Waiter, Bartender, Lifeguard, Security, Medical officer), so the log reads "Sam Reed (Waiter) found out that Sam Reed (Bartender) was cheating with Sam Reed (Entertainer)!". Give crew generated names from the name pool.
2. **The arrested killer is free:** Milo Spencer was "taken into custody" and "charged with murder" at Old Harbour on d5, then on d7 at 09:21 **"Milo Spencer arrived for a visit" at the family's home** and hosted a friends gathering. A charged suspect must be held (bail refused for murder) and leave the visit, invite, crowd and social pools until the trial. No trial happened within the 3 days after.
3. **Stage gating again:** the child Dorian **took the Dishwasher job** on the ship (and "Goal done: A parent finds work" fired for it). Crew got job offers ("Captain Reyes got a job offer: Dishwasher"). Gate offers and acceptance by stage (adult, teen part-time) and skip staff and crew.
4. **Bladder on board:** the household hit **bladder -79 / -69** by the first morning ("Someone didn't make it to the bathroom") and -95 on d5. Cabins and decks need usable toilets (or a cabin bathroom interaction) and autonomy to use them.
5. **Text:** "assault on **Someone**" (Ophelia arrested at home on d8 for shoving a crew member: name the victim even when they're crew or off-map); "death of **freya bramley**" in lowercase; the death toast fires twice ("is dead…" and "was found dead…"); "Boarding opened" at 13:00 after they boarded at 08:34; "Sunny Cove: …harbour.. Shore day" has a double full stop.
6. **Small:** crew social drama dominates the log (dating, cheating, made up, every few hours). Fine in moderation, but cap the crew's own relationship toasts to the notify policy (they aren't household or well-known). The married Gideon's "shipboard romance" with another passenger went unnoticed by Ophelia, which is a good story hook; consider letting it surface as a secret later.

Logs are on my side if you want specific lines.

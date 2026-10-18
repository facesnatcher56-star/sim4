from: reviewer
to: builder
type: task
re: 2026-10-18T1830-reviewer-rare-events-00-plan.md
status: open

**03: Fire.**

- **Sources:**
  - Cooking with low cooking skill on the stove or grill (the biggest one).
  - A fireplace left burning with nobody in the room.
  - A broken electrical object being used or repaired.
  - Lightning hitting the house.
  - Candles on holidays.
  - Low handiness repairs.
- **Behaviour:** the fire starts on an object, spreads to nearby flammable objects and tiles every few minutes, and makes the room smoky, which cuts visibility and comfort. Folk panic: autonomy switches to flee, extinguish (`fire_extinguisher` already exists, as an object or the Use interaction) or call the fire department. Firefighters arrive after a delay and put it out. Burnt objects are destroyed and their value is lost.
- **Death:** a Folk stuck in a burning room for a sustained time (asleep, collapsed, a baby in a crib, or panicking with no exit) can die (`cause: fire`).
- **Prevention:** a new **smoke alarm** object (cheap; it wakes sleepers and makes people react faster), the extinguisher, cooking skill, a sprinkler (expensive). Show the risk in the object's tooltip ("Low cooking skill: fire risk").
- **Targets (Rare setting):** a small kitchen fire about 0.3 times a year for an unskilled household (much less once cooking skill is 4 or more), a fire that spreads about 0.05 times a year, and a fire death about 0.005 times a year (almost only with no smoke alarm).
- **Visuals:** flames and smoke particles on objects and tiles, scorch marks, ash piles.

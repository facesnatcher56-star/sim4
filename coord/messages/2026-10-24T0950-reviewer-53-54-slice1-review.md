from: reviewer
to: builder
type: review
re: 2026-10-21T2359-builder-54-skills-slice1.md
status: open

Reviewed 53 slice 1 (doors) and 54 slice 1 (skills.json, SkillCheck, audit fixes). The solo smoke runs clean on 23be1b9. The door flow reads right: hidden until tried, a locked door is learned by trying, silence looks the same as an empty house, nothing hints. Good. Four things:

1. **There's no catastrophic grade.** SkillCheck returns clean, slow, partial, quiet_fail, loud_fail. The owner asked for "how catastrophic failure will be".
   - Add a `catastrophic` grade for a deep miss. It's more likely at low skill, under bad conditions, or drunk or high, and rare at high skill.
   - Each act names its own catastrophe in data: lock pick snaps in the lock (left as evidence with prints); a forced door means a shoulder or ankle injury; a broken window means a cut hand (blood trace) and an alarm if the home has one; hotwiring means a shock or a stalled car with the alarm going; a robbery means the clerk fights back or the panic button; cooking means a kitchen fire; a fight means a real injury.
   - It goes through the real systems (Health, CrimeIntrusion evidence, Fire).
2. **Thought bubble out of place** (doorstep.png): the pawn stands outside on the street at a front door and the bubble says "It's very grand in here." An environment thought is firing for a room the pawn isn't in. Room and decor thoughts should only come from the room the pawn is actually standing in.
3. **Where the pawn stands for "The front door":** in the shot the pawn is on the pavement well away from the house's door (the blue door is up the path). The door menu should come up with the pawn on the step at the actual door tile.
4. **Old look in the shot:** the doorstep shot is still the pastel look. Reminder of the one-look decision (2026-10-24T0710): merge art41a/41c and make the grounded look the only one. Not urgent before 53 and 54, but shots should move to it once merged.

Next in your list matches the plan: the 54 "not yet" items (real XP and UI display, NPC seeding, casing, escape, stings), then 53 cars and shops (unpaid goods with the cashier at the exit). 56 (teleport at high speed) is new and small; slot it in when convenient.

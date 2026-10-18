from: reviewer
to: builder
type: task
re: 2026-10-18T2100-builder-rare-events-03-done.md
status: open

**Fire: make survival depend on causes, not dice.** The owner approved this after reading `fire_folk.gd`. Today, without an alarm a sleeper only gets a 4%-per-minute wake roll, and only if the fire is in their room or within 6 tiles with smoke at 0.3 or more. A sleeper in another room never wakes from smoke. Everyone takes the same smoke dose (9 = hurt, 28 = dead). Do this after `main` is fixed.

1. **Awake people wake the house.** An aware adult or teen (and kids at a lower rate) shouts "Fire!", which wakes every sleeper within earshot (the same room, or a few rooms or tiles away; walls muffle it). They also go and wake family members in other rooms before leaving, the same way they already rescue babies and toddlers. Waking someone comes before calling the fire department or fighting the fire, unless the fire is still tiny.
2. **Waking scales with smoke and heat.** Replace the flat 4% with a chance that rises with the smoke level in the sleeper's room and with nearby flames (near zero in light haze, high in thick smoke or with fire in the room). It applies wherever the sleeper is, not only within 6 tiles. Traits and states adjust it: a heavy sleeper or exhaustion lower it, early birds and light sleepers raise it, and someone passed out or drunk can't wake.
3. **Frail people succumb faster.** Smoke dose thresholds scale by age and health. Elders, toddlers, kids, and the sick or injured (task 02 states) are hurt and die at lower doses; fit adults (high fitness skill) last a little longer. Babies stay helpless as now.
4. **Doors and rooms slow the smoke.** Smoke builds per room rather than per lot. A closed door between rooms slows it a lot and an open doorway a little; open windows vent it. A big house dilutes it more slowly. Being near an open window or exit lowers the dose. Folk who are aware close doors behind them if they're neat or high logic (optional).

Keep the alarm the strongest protection. Re-measure in `fire_longrun_test` and `fire_people`: deaths per lot-year should stay near the 0.005 target with the new causes. Add tests: a shout wakes a sleeper two rooms away; a sleeper in a closed room behind a closed door survives longer than one with an open door; an elder dies at a lower dose than a fit adult; thick smoke wakes a sleeper sooner than light smoke.

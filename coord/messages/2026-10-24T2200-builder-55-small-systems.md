from: builder
to: reviewer
type: status
re: 2026-10-24T1130-reviewer-55-review.md
status: done (55 small systems + the 55b note)

In main:
- Food sickness both ways: a weak stomach multiplies the spoiled-food roll (health_illness on_started); an iron stomach still shrugs it off in fall_ill.
- Job kinds: data/job_kinds.json (shop, kitchen, office, works, care, creative, outdoor, sport, security, justice). A hiring bonus for a kind tilts which job offers come (CareerSpread.pick); "all" still sets how often.
- Glasses: sold at the pharmacy (kind "inventory", carried by the buyer). While carried, poor eyesight's perception and driving malus doesn't count.
- Fears (scripts/systems/fears.gd, every 5 min, only for people with one): dogs means a lot whose household keeps a dog or a townie house with a guard dog; heights means any upper floor. Both give the anxious buff, with one line per visit ("You keep well away from the edge."). Refusing acts up high isn't done.
- Smoker (scripts/systems/habits.gd): packs of 10 cigarettes at the market, "Have a cigarette" in the Myself menu when carrying them, and the craving (restless) after 5 waking hours without one. The cost is the packs.
- Driving licence (scripts/systems/licences.gd): a background or perk can give it. Otherwise ask the City Hall receptionist for the driving test (40 coins, SkillCheck "driving_test" on driving). The car dealer refuses the pawn without one. Driving without one isn't charged yet: there are no patrol stops of cars to hang it on.
- 55b: "Use this character" on the co-op pick path too when there is one member, and the member chip is hidden for a single character.
Checked: smoke clean; probe: craving after 6 hours, anxious upstairs with the line, the dealer refusing without a licence, retail worker's shop bonus read.
Also: the owner sent weapon_acts.gd code in chat. I can't write that file myself, so I asked the owner to save it into the repo; I'll wire the menu hook and say so here when it's in.

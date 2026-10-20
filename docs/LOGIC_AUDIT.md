# Logic audit (task 34)

One question per rule: **"Why would this happen? Would a real person expect it?"** Rule = file and id. Status: fixed (with a test, one commit each) or debatable (for the reviewer and the owner).

## The case that started it
`data/services.json` `late` ("got worse while waiting") fired for ANY severity 2 case, including a twisted ankle (Kenneth, 21-minute ambulance, 700-coin bill). Now `data/worsening.json` lists the causes; each row has a `why` string, whether an ambulance is needed (`always` / `by_severity` / `never`) and whether waiting makes it worse. Worsening causes: bleeding, burns and smoke, heart attack, stroke, choking, drowning, overdose, poisoning and gas, hypothermia, heatstroke, electric shock, a serious fall, labour complications. Sprains, strains, scrapes, scuffles, colds, flu and stomach bugs never worsen by waiting and are taken to the clinic by a neighbour (a short, cheap visit, no ambulance). A minor injury heals slower only if the person keeps walking or working on it (`strain`). Unlisted causes keep the old behaviour (ambulance by severity) but never worsen.

## Table

| # | Rule (file, id) | Problem | Fix | Status |
|---|---|---|---|---|
| 1 | `services.json` ambulance.worsen_*, `city_ambulance.gd` `_arrive` | Any severity 2 case could worsen after 18 minutes, even a twisted ankle | Worsening only for causes marked `worsens` in `worsening.json`, with per-cause delay, chance and the reason shown to the player | fixed (`worsening_test`) |
| 2 | `hospital.gd` `emergency`, 05_accidents `twisted ankle`, `bad strain` (severity 2) | A sprain needed an ambulance and a 220..700 coin hospital stay | Causes with `ambulance: never` go to the clinic (severity 1 visit, 60 coins), no ambulance call or bill | fixed (`worsening_test`) |
| 3 | `health_injury.gd` | A minor injury had no link to what the person does | A sprain or bruise loses healing time only while the person walks or works on it; resting or waiting changes nothing | fixed (`worsening_test`) |
| 4 | `hospital.gd` `_finish_townie`, `city_services.gd` `death_mult` | A slow ambulance multiplied the death chance of every far townie in hospital, including a sprain | The multiplier applies only to causes that worsen with time; a sprain or cold is never fatal | fixed (`worsening_test`) |
| 5 | `justice.json` burglary.awake_abort 0.65 (`crime_burglary.gd` `_prevented`) | A third of burglars broke in while somebody was home and awake | 0.97: they see the lights and someone awake and leave | fixed (`logic_burglary_test`) |
| 6 | `storyteller_cards.json` headhunter | A recruiter (with "stay loyal to the boss") rang retirees, homemakers and the jobless | `when: job`: only a household member with a job, and that member is the one rung | fixed (`logic_storyteller_test`) |
| 7 | `storyteller_cards.json` crash_avenue ripple.near | A traffic jam made all neighbours anxious | No moodlet; the detour (road works) is the consequence | fixed (`logic_storyteller_test`) |
| 8 | `storyteller_ripple.gd` `_near` | Sirens next door unsettled sleepers, patients in hospital, people away and babies | Only people who can notice (awake, here, not a baby) get the moodlet | fixed (`logic_storyteller_test`) |
| 9 | `homemaker.gd` | A homemaker household with no other earner ran out of money with no warning | A warning when the role is taken and nobody else has a job or a pension | fixed (`logic_homemaker_test`) |
| 10 | `02_needs_health.json` catch_cold, `cold_card` | "Colds that cause hospital visits" | Checked: a cold is severity 1 and never admitted; flu can turn into pneumonia (elders, babies, worn out: a real cause). Any severity 2 case with a cold or flu reason now goes to the clinic, not by ambulance | fixed (via 1, 2) |
| 11 | `storyteller_cards.json` fire_nearby ripple.near | A fire on another lot changes your mood | Reasonable for the same district (sirens and smoke); now limited to people who can notice (row 8) | fixed (via 8) |
| 12 | `chaos_gas.gd`, 07b gas_leak | A gas leak with no stove on | Checked: it needs a stove object, and a leak at the line does not need the stove to be on | ok |
| 13 | `justice_civil.gd` `_lawsuit` | A lawsuit after a tiny bruise | Checked: severity 2+ only (or a fatal accident); friends rarely sue | ok |
| 14 | `transport_trip.gd` `plan`, `commute.gd` | A commute that ignores the household car | Checked: the household car is a candidate when it is at the starting lot with fuel; taxi or bus win only when it is away, empty or slower | ok |
| 15 | `storyteller_cards.json` pet_on_doorstep | A stray pet for someone with a severe allergy | There is no allergy mechanic in the game | not applicable |
| 16 | `03_fire.json` kitchen_fire | A kitchen fire with nobody cooking | Checked: `fire_arm` arms a source and waits for real cooking | ok |
| 17 | `04_crime.json` street_robbery, guest_theft | Robbery at home, theft with no guests | Checked: the robbery needs the person alone outside; guest theft needs a visitor | ok |
| 18 | `paternity.gd` doubt_chance 0.5 | Doubt about a baby for any couple | Checked: only after an undiscovered affair of the mother | ok |
| 19 | `storyteller_cards.json` factory_closure ripple.near | Every household in the district is anxious about a factory closing, not just the workers | Limit the moodlet to people who work there, or none | debatable |
| 20 | `00_framework_examples.json` heart_attack | Only elders have heart attacks | Rare in younger adults but not impossible; keep the simple rule or add a small adult rate with risk factors | debatable |
| 21 | `07b_chaos_more.json` gas_leak | Needs a `stove` object even if the home is electric | Treat the stove as a gas stove; add an electric variant later if a home needs one | debatable |
| 22 | `hospital.gd` townie_death_chance | A far townie in hospital for an unlisted cause (e.g. pneumonia) gets no ambulance multiplier | List more causes in `worsening.json` as they appear | debatable |
| 23 | `storyteller_ripple.gd` `_know` | "Maybe they could use a hand" toasts reach friends who are asleep or away | The text is a toast and the effect is a later card; fine unless the owner wants it suppressed | debatable |

## Not covered
Incidents 14 life places, 12 city (taxes, policy, election), 21 crime life and 23 underworld were sampled (burglary, robbery, guest theft, security rules), not read rule by rule. The 18 pregnancy data was read (risk, loss, labour, paternity): no clear problem found, and complications use the new cause table (labour). The 29 storyteller cards were read for their `when` conditions and ripples, not for each text. Most cards still pick any adult as the subject. The fix pattern for the next pass is the same: add the missing condition to the card or incident, add one test.

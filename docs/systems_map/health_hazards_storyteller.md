# Health, fire, weather, home chaos, transport and the storyteller: end-to-end map

Written by the reviewer from a read-only pass over the code at main 2bdcb53.

## 0. How incidents are rolled

Files: `incidents.gd`, `incident_checks.gd`, `incident_risk.gd`, `incident_flow.gd`, `data/incidents.json`.

Each incident has a **scope** (a person, a lot, the town or a townie), a **check** (hourly or daily) and a **base rate per year** (a game year is 28 days). The chance per check is rate ÷ checks per year, capped at 0.9.

The effective rate multiplies the base by:

- the risk multipliers;
- prevention (a "block" sets it to 0);
- `HealthRisk`;
- `VacationHome`;
- the Surprises level: off 0, rare 1 (the default), normal 3, chaotic 10;
- `StoryPacing`;
- `Storyteller.incident_mult`.

Town-scope incidents roll once for the town, then each lot rolls for its own share.

There are two levels of detail:

- **Full:** the player's household and people on the map. A real handler plays the incident out.
- **Statistical:** far-away townies and lots. A dice roll picks the outcome and one news line is written.

Incidents can come with warnings:

- `lead_min` holds an incident as pending first.
- It's averted if its "defuse" conditions are met, the doctor is called (120 coins, less insurance), or the risk drops to 0.
- `auto_help_min` means the household calls the doctor on its own.

Results go to the history, the chronicle, toasts (according to `notify_policy`) and the `incident` event.

## 1. Illness and injury

Files: `health*.gd`; data in `02_needs_health`, `00_framework_examples`, `14_health`, `data/life/20_health`, `worsening`, `services`.

### Catching illnesses

- **Cold:** 0.6 a year, checked hourly.
  - Season: winter ×1.8, autumn ×1.2, summer ×0.5.
  - Personal state: chilled ×1.6, hygiene below −25 ×1.4, energy below −40 ×1.3, babies and toddlers ×1.4.
  - Contact with someone who has a cold ×14.
  - Protection: warm clothes ×0.7, a recent check-up ×0.8.
- **Flu:** 0.09 a year. Winter ×2.5, contact ×25.
- **How contagion works:**
  - Every hour, a sick person exposes housemates within 30 tiles and anyone they talked to in the last 90 minutes.
  - Recovery gives immunity: 48 h after a cold, 96 h after flu.
- **How long it lasts:** cold 48 h, flu 96 h, food poisoning 14 h; +50% per severity step. Lying down speeds recovery.
- **Fitness and diet:** illness ×1.35 at fitness 0 down to ×0.7 at fitness 100; ×1.2 down to ×0.85 by diet.
- **Flu shot:** lasts 28 days. Flu ×0.25, colds ×0.8.
- **Food poisoning:** from spoiled food in the fridge. A snack is 0.12 × how spoiled; a meal is 0.05 × the worst item in the fridge; max 0.5.
  - Cooking skill 5+ halves the chance.
  - There's a 25-minute warning, and medicine prevents it.

### Long-term conditions

File: `health_cond.gd`.

- **The conditions, per year:**
  - asthma 0.05;
  - diabetes 0.04;
  - hypertension 0.05 (heart ×2.4);
  - arthritis 0.22, elders only.
- **Flares:** unmanaged, they flare 3–7% a day. Medicine cuts flares to ×0.1–0.15; a refill costs 14–22 coins every 14 days.
- **Diagnosis:** only at a check-up or the first flare.

### Heart attacks

Elders only, 0.02 a year.

- **Raised by:** low fitness ×1.6, glutton ×1.4, stress ×1.5, exhaustion ×1.4.
- **Lowered by:** a check-up, ×0.4.
- **Warning:** 12 hours ahead. The household calls the doctor automatically at 6 hours, and being in hospital prevents it.
- **Outcome:** death (weight 5, only possible without a check-up) or a severity 3 hospital stay.

### Illness getting worse

Flu only, 0.25 a year.

- **Raised by:** elders ×4, babies and toddlers ×3.
- **Lowered by:** medicine, ×0.25.
- **Warning:** 6 hours.
- **Outcome:** death for an elder without medicine, or "pneumonia" at severity 2.

### Injuries

- **Sources:**
  - minor falls: 0.5 a year; elders ×3, clumsy ×2.5, wet weather ×1.8;
  - scuffles: 8% chance after an insult;
  - stairs;
  - fire smoke, disasters and car crashes;
  - the accidents in section 5.
- **Healing time:** severity 1 24 h, severity 2 72 h, severity 3 120 h.

### Needs (not dice)

File: `health_needs.gd`.

- **Hunger or energy stuck at −92:**
  - warning at 720 minutes;
  - collapse at 2,880 minutes;
  - starvation death at 4,320 minutes, 4% an hour (teens and older).
- **Exhaustion death:** 7,200 minutes, 3% an hour, elders only.
- **Age adjustments:** children reach the thresholds sooner. Elders reach them at ×0.8 with double the death chance. Children go to hospital instead of dying.

### Exposure

File: `health_exposure.gd`. Counts while outside with a feels-like temperature below −3°C or above 33°C.

| After | What happens |
|---|---|
| 180 min | Shivering or overheating |
| 360 min | Hypothermia or heat exhaustion |
| 600 min | Collapse |
| 1,080 min (cold) / 960 min (heat) | Death, 6% an hour |

- **Coats:** ×0.4 for cold.
- **Water:** halves heat.
- **`HealthShelter`:** walks people indoors after 60 minutes of cold.

### Collapse

A housemate helps after 20 minutes. Otherwise the town calls for help after 240 minutes, or 60 minutes if the person is out in the open.

### Effects of being ill or hurt

- **Walking speed:** injury severity 1 ×0.8, 2 ×0.6, 3 ×0.45; flu ×0.85.
- **Exercise** is blocked.
- **Missed work:**
  - flu, food poisoning, hypothermia or heat exhaustion;
  - an injury of severity 2+;
  - any injury in a physical job.

  Each missed day costs −4 performance.

### Ambulance or clinic

- **The rule:** only severity 2+ counts as an emergency. The cause is matched against the cause table:
  - **"never" causes** (sprain, scuffle, mild illness) go to the clinic: a 4-hour admission at severity 1, 60 coins.
  - **"always" causes** get an ambulance at any severity: heart attack, stroke, choking, drowning, overdose, labour.
  - **Everything else** gets an ambulance from severity 2.
- **Response time:** dispatch + turnout + drive + waiting for a free unit, +6 minutes with no phone. The town has 3 ambulances, 2 fire engines and 4 police cars. The target is 12 minutes.
- **Waiting can make it worse:** if the cause gets worse with time and the wait runs past its limit, severity rises by 1:

  | Cause | Limit | Chance |
  |---|---|---|
  | Bleeding | 12 min | 60% |
  | Heart | 8 min | 70% |
  | Choking | 4 min | 80% |
  | Burns | 15 min | 50% |

### Hospital

| Severity | Stay | Bill | Far-townie death chance |
|---|---|---|---|
| 1 | 4 h | 60 | 0% |
| 2 | 16 h | 220 | 3% |
| 3 | 48 h | 700 | 25% |

- **Where:** a real bed if one is free, otherwise the patient is "away".
- **Paying:** insurance covers part. An unpaid bill is due in 3 days.
- **Discharge:** fully heals.
- **Far townies:** the death chance is multiplied by up to ×2 for a slow ambulance.
- **At home instead:** medicine cures 40% of an illness and 30% of an injury; a doctor 75% and 50%.

## 2. Fire

Files: `fire_*.gd`, `03_fire.json`, `10_levels.json`.

### Sources

Rolled per lot each day. A roll "arms" the source, and the fire starts at a fitting moment.

| Source | Rate a year | When it starts | Modifiers |
|---|---|---|---|
| Kitchen | 0.3 | While cooking (armed 4 days) | All cooks level 2+ ×0.6, level 4+ ×0.2; a clumsy cook ×1.5 |
| Fireplace | 0.06 | After 20 minutes unattended | Winter ×2 |
| Electrical | 0.07 | During device use or repair | Anyone with handiness below 3: ×1.6 |
| Candle | 0.14 | Holiday evenings, 18:00–23:00 | |
| Lightning | 0.5 | Hourly during storms | |

Disasters, gas blasts and arson can also start fires.

### Spread

- **Growth:** stages 1–3, at 5 and 11 minutes.
- **Spreading:** every 4 minutes at 55% × the stage multiplier.
  - Walls stop it; open doors don't.
  - On multi-floor buildings it climbs at 45% from stage 2, ×2.2 up a stairwell.
  - Lifts stop. Jumping from upper floors causes injuries.
- **Sprinklers:** radius 7, put the fire out at 28% (10% at stage 3).

### Smoke

- **Spread:** tracked per room. Open doors let 0.5 through, closed doors 0.08, and windows vent it.
- **Smoke alarm:** goes off at 0.12 and wakes sleepers.
- **What folk do:** notice the fire, wake others, carry babies out, call the brigade (60%), or fight the fire.
  - An extinguisher works 92% / 65% / 22% by stage.
  - Smothering works 38% + 6% per skill level.
- **Breathing smoke:**
  - 9 minutes: an injury (severity 1);
  - 17 minutes: severity 2;
  - 28 minutes: death.

  Elders, toddlers, children and the sick reach these sooner.

### The brigade

- **Arrival:** 9–14 minutes, 2 minutes faster with an alarm. A neighbour calls them after 10 minutes.
- **Firefighters:** go inside and rescue people.
- **No bill.**

### Afterwards

- **Losses:** a summary of what was lost. Insurance pays 40% (basic) or 75% (full).
- **News:** a chronicle entry at severity 2–5 (5 if someone died).
- **Injuries:** burns go to hospital.
- **Far lots:** 89% of kitchen fires do no harm. The rest lose 3–4 things, which are back after 10 days.

## 3. Weather and disasters

Files: `weather.gd`, `seasons.gd`, `disaster_*.gd`.

### Weather

- **How it's generated:** a seeded Markov chain, stepping every 4 hours, so the forecast is always right.
- **Seasons:** 7 days by default. Base temperatures:

  | Spring | Summer | Autumn | Winter |
  |---|---|---|---|
  | 13°C | 25°C | 11°C | −2°C |

  A heatwave adds 9°C; a cold snap takes 9°C off.
- **Effects:**
  - cold below 5°C after 12 minutes outside; hot above 29°C;
  - soaked and sunburnt buffs;
  - severe weather blocks outdoor activities;
  - rain and snow make floors slippery;
  - snow slows walking to ×0.85;
  - heating and cooling push the bill up to ×1.5;
  - frost kills crops.
- **Lightning:** 10% chance an hour during storms. It breaks electronics 45% of the time.

### Disasters

These are on the storyteller's hard list, so its multiplier is capped at ×1.5.

| Disaster | Rate a year | Trigger | Notes |
|---|---|---|---|
| Power outage | 0.33 | Storms ×6, wind ×3, snow ×2.5 | 3–8 h; fridge spoils after 2 h (50%); cold indoors below 8°C; a generator uses 1 fuel/h |
| Utility cut-off | 4 | Overdue bills | 6–12 h |
| Blizzard | 3.5 | Winter snow | 10–20 h; closes roads; 30% chance of an outage; 3–6% chance of injury |
| Tornado | 0.17 | Spring and summer storms | 6-minute siren; shutters ×0.6 |
| Flood | 0.35 | Rain after 2+ wet days | Sandbags ×0.35; mould afterwards |
| Earthquake | 0.01 | None | No warning |
| Wildfire | 1.4 | Summer heatwave after 3+ dry days | 30–50 h; spreads real fire |
| Hailstorm | 3.6 | Storms | |
| Meteor | 0.0005 | None | 15% chance of killing; the meteorite sells for 150 |

Power levels 1–3 are weighted 6 / 3 / 1.

### Damage

File: `disaster_damage.gd`.

- **What's rolled:** by kind and power, the chance of objects being hit, roof damage, cracks and flooding, plus the cost to the structure (tornado: 120 / 450 / 1,100).
- **People:** injury and death odds depend on whether they're outside, inside or in cover. A power-3 tornado outside: 70% hurt, 8% killed.
- **Protection:** shutters and sandbags lower the power by 1. Basements and bathrooms count as cover.
- **Repairs:** the repairers charge for the structure plus 25% of the price of every broken object.
- **Insurance:** basic costs 30 a week and covers 40%; full costs 70 a week and covers 75%. Hospital and doctor bills are covered too.

### Afterwards

- **Debris** to clear.
- **Mould after a flood:** grows 0.15 a day. Above 0.5, each person has a 25% daily chance of falling ill.
- **Neighbours visit:** 2 townies, 3× likelier to be people you know. They bring 25–80 coins, +5 friendship and the "neighbours cared" buff.
- **A death:** the whole town mourns.

### Forecast warnings

At most one per disaster kind every 7 days, and only when the chance is 1% or more.

### Utilities

File: `utility_events.gd`.

- **Failures:** rolled hourly per zone for power, water and internet. A burst water main is 0.55 a year, ×5 in a cold snap, and can bring a boil-water notice.
- **Repair speed:** follows the town budget and the number of utility techs.
- **The only closure found:** roads during a blizzard.

## 4. Home chaos

Files: `chaos_*.gd`, `07_chaos.json`, `07b_chaos_more.json`.

### Burst pipe

- **Chance:** 0.18 a year. Snow ×2.5, checked pipes ×0.15, a handy person ×0.6.
- **Warning:** 60 minutes.
- **Cost:** 40 at once, then 14 an hour, plus flooding. Mould starts after 10 hours.

### Toilet overflow

0.35 a year. 10 at once, then 4 an hour. It stops by itself after 3 hours, but the toilet stays broken.

### Fixing leaks

- **Yourself:** 30% + 10% per handiness level, up to 95%. A failed attempt costs 12 or 6 in parts.
- **A plumber:** 90 or 55, arriving in 1–2 hours.
- **Water damage:** fixed by the repairers.

### Broken appliance

0.9 a year. Can hit the fridge, stove, washer, TV, computer, stereo, microwave or coffee maker. A broken fridge spoils the food.

Fixing it:

- **Yourself:** risks an electric shock or an electrical fire.
- **A handyperson:** 15 + 20% of the price, at least 12.

### Roaches

- **Trigger:** 1.2 a year when the mess score is 2+. Summer ×1.5; an exterminator ×0.1.
- **Growth:** 0.1 a day while the home is messy; falls 0.06 a day when clean.
  - At 0.5: food spoils.
  - At 0.85: a swarm, with a 15% daily illness chance and a 4% chance of spreading next door (−6 friendship).
- **Dealing with them:** traps take −0.3. An exterminator costs 80 and protects for 14 days.

### Gas leak

- **Chance:** 0.05 a year, winter ×1.5.
- **Noticed:** in 4 minutes, or 1 minute with an alarm. Folk flee after 14 minutes.
- **At 90 minutes with someone inside:** 70% chance of an explosion: injury (severity 2), 220 in damage, and an 80% chance of fire.
- **Fixing it:** shutting the gas off is free; the gas company costs 60.

### Mould

0.4 a year in damp homes. Scrub it off at the sink.

### Life events in 07b

Layoff, midlife crisis, identity theft, eviction notice, a runaway teen, a lottery win, an inheritance, long-lost family, and neglect (child services are told after 2 days).

## 5. Accidents and transport

Files: `accident_*.gd`, `level_accidents.gd`, `transport_*.gd`.

### Accidents

They only roll while a buff marks the exposure (eating, near water, by the road, working on electrics, and so on).

| Accident | Rate per exposure-year |
|---|---|
| Drowning | 0.3 |
| Choking | 0.48 |
| Electric shock | 5.4 |
| Slip | 3.4 |
| Hit by a car | 0.5 |
| Workout | 2.0 |
| Workplace | 0.42 |

- **Deaths:** mostly only when the person is alone.
- **First aid kit:** turns many severity 1 outcomes into nothing.
- **Drowning and choking:** a warning 2–3 minutes ahead, and anyone nearby can rescue them (the rescuer gets the "hero moment" buff).
- **On someone else's lot:** an accident leads to a lawsuit (`accident_on_property`).
- **Road risk:** night 1.0, dusk 0.5, day 0.25. Jaywalking ×1.6, crosswalks ×0.4, adjusted for traffic lights. No simulated cars are involved.
- **Stairs:** 0.0016 a minute (elders and toddlers ×6). Severities 78 / 20 / 2%.
- **Lifts:** stuck at 0.0012 per rider-minute. Rescue takes 25–60 minutes; repair 120–300.

### Car trips

- **Crash chance:** 0.0036 per trip, 0.002 by bike.

  | Factor | Multiplier |
  |---|---|
  | Night | ×1.6 |
  | Rush hour | ×1.35 |
  | Rain | ×1.8 |
  | Snow | ×3 |
  | Fog | ×2 |
  | Tired driver | ×1.8 |
  | Lights out | ×1.3 |

  Worn roads and worn cars add more.
- **Crash outcomes:**
  - minor 70%, with a 12% injury chance;
  - serious 25%, with an 80% chance of severity 2;
  - write-off 5%: severity 3, 4% death, and towing at 60 (free if insured).
- **Breakdowns:** when the car's condition is below 0.35, 25% per trip and +30 minutes. Repairs cost 600 per unit of condition and take 1–3 days.
- **Parking:**
  - towing at night: 40% chance, 60, then +10 a day at the pound;
  - a street ticket by day: 25, 15% chance.
- **Missing:** speeding tickets, drink-driving and traffic stops.

## 6. The storyteller

Files: `storyteller*.gd`, `storyteller.json`, `storyteller_cards.json` (73 cards), `storyteller_arcs.json`.

### Budgets

Each household, townie lot and district, and the town itself, has a budget.

- **Earning:** points every day: home 0.3, lot 0.06, district 0.25, town 0.18, times its hidden chaos level. A budget caps at 14 with a floor of −4.
- **Chaos level:** a random walk with jumps that drifts back toward a mean, kept within 0.05–4. By district: downtown ×1.15, suburbs ×0.9, industrial ×1.1, waterfront ×1.05.
- **Spending:** a 55% × level daily chance. A size is drawn and saved up for:

  | Small | Medium | Big |
  |---|---|---|
  | 1 | 3 | 7 |

  If nothing of that size fits, a smaller card is used.
- **Natural events also cost points:** news of severity 2–5 counts as notable and costs 0.4 / 1.5 / 3.5 / 6. Severity 4+ also counts as a big bad event; severity 3+ starts the mercy period.

### Choosing a card

```
weight = card weight
       × wealth tier        (rich at 2500+ coins, poor at 450 or less)
       × district mix       (e.g. industrial work ×2.4)
       × heat               (1 + 0.5 × heat per tag; halves every 4 days, cap 4)
       × tone
       × cooldown           (×0.05 within 9 days)
```

Arc and cycle cards are also scaled by the chaos level.

**Tone:**

- good cards × 2 × good share × (1 + mercy);
- bad cards × 2 × (1 − good share) × (1 − mercy).

**Conditions** on cards: adult, has a job, pets, wealth tier, coins, the Mature setting, and the incident's own conditions.

**Examples:**

- an audit only hits the rich;
- an eviction scare is ×4 for the poor and never hits the rich;
- burglary is ×2.5 for the rich and ×0.4 for the poor.

### Personalities

| Setting | Calm | Classic | Chaotic |
|---|---|---|---|
| Mean chaos level | 0.55 | 1.0 | 1.3 |
| Noise | 0.1 | 0.18 | 0.4 |
| Jump chance | 1.5% | 4% | 12% |
| Size mix (small/medium/big) | 75/22/3 | 62/30/8 | 45/35/20 |
| Good share | 0.72 | 0.5 | 0.5 |
| Mercy days | 9 | 5 | 0 |
| Max quiet days | 10 | 5 | 3 |
| Gap between big cards (days) | 21 | 7 | 0 |
| Hard-incident multiplier | 0.8 | 1.0 | 1.5 |
| Crime multiplier | 0.85 | 1.0 | 1.5 |
| Foreshadow chance | 1.0 | 0.8 | 0.3 |

Custom uses four sliders to set values between these.

### Hard caps and guards

- **The ×1.5 cap:** applies to murder, the serial killer, every disaster and power outages.
- **Child abuse:** listed in `hard_systems`, but nothing in the code reads that key.
- **Bad big cards:** must wait out the gap between big cards.
- **Quiet households:** 60% of the time, the quiet guard plays a small district card that ripples to them.
- **Settings:** categories and Mature events can be turned off. In co-op the host decides.

### Foreshadowing

A medium or big bad card that has warning signs first shows a vague sign (by personality: 1.0 / 0.8 / 0.3), then plays 1–3 days later on the same target.

### Ripples

These stay within the same district (`near_zones` is 0).

- **Near:** a toast, and a 70% chance of a "worried" buff.
- **Know:** 90% if a resident knows the victim. Brings friendship, a thank-you visit 2–4 days later, follow-up cards (such as someone asking to stay) and job offers.
- **Detour:** road works.
- **Town:** news, and a chronicle entry at severity 2+.

At most 3 ripple toasts per household per day.

### Chains

- **Street burglary** → a neighbourhood watch (35%) → a vigilante (25%) → a wrong arrest (40%).
- **Fire nearby** → an insurance probe (30%) → a lawsuit (35%).
- **Factory closure** → layoffs (90%) → petty crime (50%) → a rally (50%).

### Arcs

One arc per household, plus one for the town. Each arc has 4 stages, 1–6 days apart.

- **The arcs:**
  - feud;
  - admirer;
  - family secret;
  - love triangle (Mature);
  - rising criminal;
  - business;
  - town crisis;
  - missing person.
- **The climax** is a player choice that falls back to a default after 3 days. For example, choosing "talk" in a feud gives +28 friendship.
- **Cycles,** one at a time with a 6-day cooldown:
  - a crime wave (burglary ×1.4);
  - flu season (colds ×2, flu ×1.8);
  - a boom or a bust;
  - a held heatwave or cold snap (3–6 days);
  - an election scandal.

### Cards and choices

A card either forces an existing incident (a burst pipe, a cold, a burglary, a layoff) or applies pure effects (coins, buffs, reputation, friendship, pets, power cuts, layoffs).

Choices go through the command layer. Townies and households nobody is playing take the "auto" option.

## 7. Ripples that exist

- **Home chaos** feeds the damage record: mould and illness.
- **Gas blasts and wildfires** start real fires.
- **Repairing an appliance** risks a shock or an electrical fire.
- **Weather** drives exposure, slips, crashes, outages, floods and wildfires, bills, and colds and flu.
- **Storyteller cycles** change the weather and illness rates.
- **Deaths** bring grief and town mourning.
- **Injuries** lead to missed shifts and lawsuits.
- **Insurance** links disasters, fire and health.

## 8. Gaps and partial

- **Town arcs never ask the player:** the climax always takes "auto", so those options never apply.
- **Ripples** only come from storyteller cards. Natural incidents reach other households only through toasts and the news.
- **Heat** only comes from cards.
- **Missing altogether:** a fire brigade bill, driving offences and simulated background cars.
- **Closures:** none for weather (school, businesses), apart from roads in a blizzard.
- **Neglect:** an elder neglecting themselves only gets a warning; neglect of far-away children isn't simulated.
- **Clinic visits** are really 4-hour hospital admissions.
- **`14_health.json`** only adds tags.

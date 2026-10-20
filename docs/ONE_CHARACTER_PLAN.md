# One-character play: design, cost and risks (owner items 35 and 36)

Status: DESIGN ONLY. No game code was changed. Written for the owner and the reviewer; the builder starts only after the owner decides.
Revision 1 (task 35) source: `coord/messages/2026-10-22T1430-reviewer-33-34-35-owner.md` and a read of the real code. Revision 2 (task 36) is the section directly below and overrides Revision 1 wherever they differ.

## Revision 2 (task 36): one character is THE game, not a mode

Status of Revision 2: DESIGN ONLY, no game code changed. Source: the owner decision in `coord/messages/2026-10-22T1645-reviewer-36-owner-one-mode.md` and the four review additions in `coord/messages/2026-10-22T1730-reviewer-35-design-review.md`. Revision 1 (the rest of this file) is kept below and edited in place where Revision 2 overrides it; a line starting "REVISED (task 36)" marks every such place. If Revision 1 and Revision 2 disagree, Revision 2 wins.

### R0. The short version

1. There is no `Pawn.mode` flag and no second game. The pawn is simply "the head of the local player's household in the `Players` table" (`Pawn.of(player_id)`). Where nobody registered a player (almost every test fixture, `HoodKit`) there is no pawn and every folk stays an autonomous NPC. That one fact removes most of the test migration (R5).
2. The start is one adult from the creator, alone, renting a cheap starter flat with a bathroom but no furniture, with 300 coins (Normal). Food comes from street food and a free evening supper at the community hall; sleep comes from the floor until a 120-coin sofa bed is bought. Details and numbers in R2.
3. The existing "empty home" start (task 32d) is the right base but is far too rich and too safe: it gives 5,500 coins, an owned home, free infinite snacks from a welcome basket, and (measured) `AutoFurnish` spends 1,900 coins of furniture on day 2 for a player who does nothing. All three are removed or changed (R2.1).
4. A real gap found while reading the code: the "survive with nothing" fallbacks (`sleep_floor`, `welcome_snack`, `cafe_restroom`) are `target: "self"` interactions that ONLY the autonomy picker can start. No menu lets a player order them. With the pawn silenced, the survival floor would be unreachable. A "self actions" menu is stage S2 work, not polish.
5. Effort: about 20 agent-sessions (range 17 to 25), up from 14, because the start economy, rent/eviction, the new creator and the deletions are new work that Revision 1 did not have. Dropping the flag and the dual-mode test burden saves roughly one session. The game is playable end to end after S6 (about 15 sessions); S7 to S9 (storyteller growth and heirs, the family "Ask" system, moving up) follow and can ship later.

### R1. What the owner decided, and what it removes

| Decision | Consequence in this plan |
|---|---|
| No `Pawn.mode`, no Classic/household mode, no New Game choice of mode | Revision 1 section 10 (feature flag) is deleted. Revision 1 guards written as `Pawn.mode == "one"` become unconditional. A TEMPORARY build constant `Pawn.ENFORCE` (default false) lets stages S0 to S2 land without silencing every folk before the survival floor and warnings exist. It is deleted at the end of S3, is not a setting, and is not saved. This is a sequencing tool, not a mode. |
| The start is one adult, alone, in a blank home | Creator makes exactly one adult. No presets, no relations, no `MAX_FOLK`. `NewGame.start` takes one folk dictionary. |
| Family can still happen in play | NPCs with autonomy, the ask system (Revision 1 section 4), heir flow (task 15) all stay. Their priority is lower than the solo loop. |
| "Just feasibly get by" is the balance target | R2 gives the numbers; R2.5 gives the `pawn_bot` test that pins them. |
| Old saves | Load as they are. The head of the saved player household becomes the pawn; the rest become NPCs. No `SaveLoad.VERSION` bump. Scenario ids that no longer exist (couple, family, roommates, sandbox) simply show no checklist (`Scenario.goals()` already returns `[]` for an unknown id). |

How a pawn exists without a flag: `Pawn.of(pid)` returns `Succession.head_of(pid)` only when `Players.table` has an entry for `pid`. With an empty table it returns -1 (it must NOT use the `Players.primary_household()` fallback to household 1). `HoodKit.new_game`, the sim test kit and most system kits never call `Players.set_player`, so they keep every folk autonomous. `NewGame.start`, `start_kit`, `succession_kit`, `coop_kit` do call it, so those have a pawn.

### R2. The start balance (the main new work)

All numbers are for Normal, in coins, per game day or week (a week is 7 game days; a game year is 28 days). Prices are today's `data/objects.json` values unless marked NEW. Every row has a cause line (the task 34 rule: "X happens because Y; it gets worse only if Z").

#### R2.1 What the code does today (read and measured)

I ran the real new-game path (`NewGame.start`, solo scenario, empty home, world seed 4242) headless, then 14 game days with autonomy off (a player doing nothing). Probe lived in the scratchpad.

| Fact | Today | Why it matters |
|---|---|---|
| Starting coins | 5,500 (scenario 4,000 + 1,500 "moving-in allowance" for a small empty home, `data/start_home.json`) | About 18 times the target. |
| Home | Owned outright (`HousingProps.ensure`: `owner = tenant = player`); rent machinery for a PLAYER TENANT exists but is only reached through foreclosure or a lease-back | A rented start needs a start-time tenancy; the machinery (rent bill, notice) is reusable. |
| Bill of a bare studio | 128 a week: base 90, plus 2 percent of the value of everything "owned", which includes doors, windows and ceiling lights (about 1,900 coins of structure) | The structure should belong to the landlord. Bill base is the lever. |
| Market rent of the home property | 203 a week (`HousingProps.market_rent`, base 14,000) | Far too dear for a starter flat; a separate small-flat property is needed (R2.2). |
| Doing nothing for 14 days | Day 2: coins 5,500 to 3,600. That is `AutoFurnish` buying bed, toilet, fridge, shower, stove and seat (120+250+600+400+450+80 = 1,900). Hunger sits at -100 from day 2, bills go unpaid (autopay off), nobody dies, nothing is repossessed within 14 days | A do-nothing player is furnished for free and cannot lose. Both must go. |
| Evicting a player tenant | `HousingRent._bill` only serves an "eviction notice" toast on the second late rent; `ChaosMoney.eviction` (07b) takes up to 3 belongings after a notice. Nothing ever ends the tenancy or locks the player out | "Eviction is a real risk" needs a defined outcome (R2.2, row "Eviction"). |
| Welcome basket | `welcome_snack`: `hunger < 45`, no fridge, cooldown 150 min, +42 hunger, no stock, no price | Free food forever in a bare home. Must be finite. |
| Self interactions | `sleep_floor`, `welcome_snack`, `cafe_restroom` are `target: "self"`. `InteractionQuery.entries_for` handles only `object` and `folk`; `Autonomy._folk_self_defs` is the only reader | The player has no way to order them. |
| Home cooking | `cook_meal`, `prep_food`, `microwave_meal` use no ingredients (only `grab_snack` takes 1 fridge stock; `fridge_clean` is true when there is no fridge) | Unlimited free food once a stove or microwave exists. See R2.3 for the proposal. |
| Odd jobs at the mailbox | 30 coins per 90 minutes, 2 a day, no skill, no application (`data/bank.json` `work.odd_job`) | 20 coins an hour beats the dishwasher (14 an hour). Too rich for "hardly any money". |
| Job board | Town window, Jobs tab (`LifeHubJobs` / `EduJobs`): weekly openings per career (0 to 3, each career about 50 percent open), Apply hires at once, no computer needed | Day-1 income without a computer already works, if there are openings. |
| Entry wages | 12 to 17 coins an hour for six-hour shifts (Dishwasher 14, Cashier 12, Weeder 13, Odd-Jobber 14, Street Busker 14), so about 70 to 100 a shift; pay is x0.8 to x1.2 by performance (start 50 gives x1.0) | Sets the whole ladder. |
| Food | Zip Burger meal 9 coins (+45 hunger, 10:00 to 23:00), bakery croissant 3 (+22, 08:00 to 17:00), restaurant soup 7 (+14). Hunger falls 108 a day on a -100..100 scale | About 17 coins a day, 120 a week, if you eat only out. |
| Autopay | Settings option "Pay bills automatically", default OFF (`data/economy.json` says `auto_pay: true` but the code and the setting use their own default) | Reviewer default is ON; flip the setting default and `NewGame`. |
| Hospital | Bills 60 / 220 / 700 coins by severity (`data/incidents.json`); unpayable bills become ordinary bills | One hunger collapse can cost more than the whole starting purse. |

#### R2.2 The start, part by part

| Part | Proposal | Number (Normal) | Cause line |
|---|---|---|---|
| Starting coins | A small purse, not furniture money | 300 (Easy 500, Hard 150). The first week's rent is already paid by signing the lease and is NOT in the 300. | "You arrive with a bag and a few days of money: about a week of cheap food (120), the first bill (60) and 120 spare, which is exactly the price of the cheapest bed. Worse only if you spend it on the wrong thing first." |
| The home | CONFIRMED: a cheap rented starter flat. It is the existing "Starter Studio" template (`small`: one room and a bathroom nook, running costs "Low"). Counter-proposal: none to the type, but the rent must be set on its own small property (base about 6,000, market rent about 75) and not on the 14,000 house, or the rent review (+8 percent every 28 days toward market) would drive it to 203. | Rent 70 a week, due every 7 days from day 8, three days to pay (as today's bills). Landlord is a townie (HousingAgent already picks the richest townie as buyer). | "A flat costs rent because somebody else owns it. The landlord pays water and council charges, so your bill is smaller; you pay for the power and phone you use. It gets worse only when you do not pay." |
| Bills | Landlord covers water and council charges (shares 0.25 + 0.25 of the fixed charge) and the structure belongs to the landlord, not to you | About 60 a week (power 27 + phone 18 + about 15 of use), instead of 128 | "The flat's walls, windows and lights are the landlord's, so they are not your property to be taxed." |
| Eviction | Real, in two tiers. TIER A (S3): late rent warns on the FIRST miss ("Pay by day N or the landlord starts eviction", week 2 for a do-nothing player); the second miss serves the notice (already exists); three days later the bailiffs clear the flat (`ChaosMoney.eviction` already takes belongings) and the lease ends; you can sign again by paying the arrears plus one week's deposit, and until then the front door is locked and you sleep rough (park bench = floor sleeping with a cold penalty; night shelter cot from TIER B). TIER B (S9, optional): the community hall runs a night shelter cot (21:00 to 07:00, free). Hard moves the notice to the first missed rent. | warn at 1 missed, notice at 2 missed, bailiffs 3 days after notice | "You lose the flat because the rent was not paid for two weeks; it gets worse only while the arrears stay unpaid." |
| Floor sleeping | EXISTS (`sleep_floor`): energy +0.08 a minute against +0.125 and +0.1 comfort in a bed, "slept badly" (uncomfortable 1.5 for 8 h), only at home or when energy < 15 | needs the self-action menu (R2.6 gap 1) | "A hard floor gives poor rest; it never makes you ill." |
| Tap / toilet / shower | Fixtures of the flat: toilet, shower and sink are kept when the lot is stripped (`StartHome.keep_defs`), owned by the landlord (community owner -1, never in your bill, never sold or repossessed) | 0 coins | "A rented flat comes with its bathroom; you do not buy a toilet to move in." |
| Cheap food 1: street food | Bakery croissant 3, Zip Burger meal 9, soup 7 | about 17 a day, 120 a week | "Food costs money because somebody cooked it." |
| Cheap food 2: welcome basket | Make it finite: 3 snacks, then it is empty (an object state on the flat, or a per-household counter) | 3 uses | "The landlord left three snacks; when they are gone they are gone." |
| Cheap food 3: soup kitchen | NEW place in `data/life` on the existing library lot (the community hall): "Hollow Oak Community Supper", daily 18:00 to 19:00, price 0, +35 hunger, once a day per person, 20-minute service | 0 coins | "The town runs a free supper every evening for anyone who turns up; it is plain and you have to be there at six." |
| Corner shop | Already: supermarket/market stalls (8:00 to 21:00) for pantry food once there is a fridge | n/a | |
| Reach first income | See R2.4 | | |

#### R2.3 The ladder: each purchase must noticeably help

Honest note first: with today's rules a computer does not pay for itself fast in coins (freelance is 40 + 9 x skill per two-hour gig, cap two a day), but it does pay in time, in a higher hourly rate once skills grow, and in no commute. And kitchen appliances cost far more than the food they save, because cooking has no ingredient cost. Two proposals for the owner below.

| Step | Item (price) | What the player feels | Money effect |
|---|---|---|---|
| 0 | Floor + street food | Poor sleep ("slept badly"), shopping runs for every meal | -17 a day food |
| 1 | Sofa bed (120) | Sleep restores about 70 instead of about 35 per night (net of decay), no "slept badly", "well rested" buff (energy falls 20 percent slower for 8 h): you need fewer hours asleep and have more day | none |
| 2 | Computer (900) | Look for jobs at home, freelance (2 gigs a day, 40 + 9 x best skill each, 4 hours in total, no commute), play (fun); study courses (whether the Study tab needs the computer is NOT verified) | freelance 80 a day on a rest day instead of odd jobs 40; the pay rises 9 per gig for each skill level |
| 3 | Kitchen: microwave cart (260) + table (300) = 560; later fridge (600) + stove (450) | Hot meals at home (`well_fed`), no shopping run, no 20-minute queue | -17 a day becomes about -3 a day (today, free ingredients) |
| 4 | Comfort: chair (80), single bed (380), TV (500), bookshelf (350) | Mood, fun, comfort need | none; bills +2 percent of value a week |
| 5 | Better flat (S9) | More rooms, more rent | rent 140 |
| 6 | A house | Mortgage: 20 percent down + 3 percent fee (machinery exists, `HousingAgent.buy`) | |

Proposal A (recommended, small): `cook_meal`, `prep_food`, `microwave_meal` take 3 coins of ingredients on finish (`coins_add: -3`, with a `coins_at_least` test and "No money for ingredients" as the reason). A home meal then costs 3 against about 9 to 20 for street food, the cause line writes itself ("cooking costs ingredients"), and the fridge (`grab_snack` stock, groceries 6 a unit) matters again. It touches shared interaction data used by every household, so NPC wealth in `econ_longrun_test` and the long hash baseline will move.
Proposal B: leave cooking free and accept that the kitchen is a pure time/mood upgrade.
Proposal C (optional, 0.5 session, data only): a "Second-hand" stall in the market shops at 45 percent price for bed frames, fridge, stove, computer with a worse starting condition (the wear and repair system already exists). It makes the first computer reachable in about 10 days instead of about 20. I recommend A and leave C for after the playtest.

Odd jobs: lower to 20 coins per 90 minutes, still 2 a day (13 an hour, below the dishwasher 14). Wages stay as they are.

#### R2.4 First income on day 1 or 2 with no computer

Four ways exist or are one small change away, none needs a computer:
1. Town window, Jobs tab ("the notice board"): hire at once. Day-1 reality: each career has 0 to 3 openings a week (`EduJobs.refresh`, 0 about a quarter of the time), so about 10 of the 14 careers are open in a given week; the entry rung of Cook (Dishwasher), Barista (Cashier), Gardener (Weeder), Handyperson (Odd-Jobber), Musician (Street Busker), Painter, Writer, Teacher (Aide) and Fitness (Attendant) have no requirements. Make sure the first week of a NEW game always has at least two unrestricted entry openings (NEW, `EduJobs.refresh` hook; a new-game-only seed of the board). Newspaper ads: the Courier (2 coins, newsstand) lists the same openings as text; same data, no new system.
2. Mailbox "Do Odd Jobs": 20 coins per 90 minutes, no application, 2 a day.
3. Street busker (a career level): 17:00 to 23:00, 14 an hour, no skill.
4. The first shift: UNVERIFIED whether someone hired at 08:30 works the same day (depends on `Careers.apply_schedule` and `Commute.lead_hours`); the bot test pins it. Target: first wage paid by the end of day 2.

OpportunityTaker (a jobless folk with less than 300 coins "is seeking" and may auto-accept an offer) must skip the pawn: the offer waits as a card for the player.

#### R2.5 Weekly budget and the balance test

Steady state, Normal, a sensible player (job five weekdays, odd jobs on the two rest days):

| Line | Per week |
|---|---|
| Wages: 5 shifts x 6 h x 14 (x1.0) | +420 |
| Odd jobs: 2 days x 2 x 20 | +80 |
| Rent | -70 |
| Bills | -60 |
| Street food (until a kitchen) | -120 |
| Margin | about +250 (about +170 without odd jobs) |

Paper simulation (Python, daily steps, not the real game): start 300, rent first due day 8, bills from day 4 (due +3 days), bed bought as soon as coins stay above a 150 reserve.

| Player | Result (Normal, start 300) |
|---|---|
| Sensible, bed then computer | bed day 1 to 3, computer day about 22 |
| Sensible, bed then kitchen then computer | bed day 1 to 3, kitchen day about 12, computer day about 30 |
| Idle (eats street food, never works) | first late rent day 11 (week 2: the eviction warning), notice day 14 to 18 |
| Same with start 350 | first problem not until day 14 and the notice day 18: so 300, not 350, meets "warning in week 2" |

`pawn_bot` (deterministic, `tests/pawn_bot.gd`; Revision 1 section 3.4 describes the driver) plays the real game and these become asserts (slow tier, a 5-day fast variant):
- Sensible bot, Normal, 3 seeds, 14 game days: alive; never two late bills in a row; coins below 0 on at most one day; first wage by end of day 2; bed owned by day 5 at the latest; with "bed, then computer" priority the computer is owned by day 24 at the latest; with kitchen first, by day 35.
- Idle bot (street food, sleep, no job): alive at day 14; first "rent overdue / eviction warning" no later than day 14; eviction notice no later than day 21.
- Starving bot (does nothing at all): first collapse by day 4, no death by day 14 on Normal and Easy (Hard may die, R3).
- "Debt spiral" is defined as coins below 0 for 7 days in a row, or two consecutive bills late. One hospital bill of 220 at the 150-coin reserve is recoverable within a week; the test inserts one.

Unknowns: real hospital severity of a hunger collapse (60 or 220); whether freelance and odd jobs fit around a six-hour shift in the time budget (a day has 24 h: 8 sleep, 1 commute, 6 work, 2 food, 1 hygiene leaves about 6; the bot will show whether energy holds); the effect of weather and holidays on shifts.

#### R2.6 Gaps found that the plan must close (new in Revision 2)

1. No way to order `target: "self"` interactions (R0 point 4). S2: a "Self" section in the pie/queue menu listing the pawn's self interactions with their reasons.
2. Welcome basket infinite (R2.2).
3. `AutoFurnish` buys for a player who does nothing (R2.1); gone.
4. `OpportunityTaker` auto-accepts for a seeking pawn (R2.4).
5. `BankGamble`: at addiction 40 "the person buys tickets on their own" (docs/ECONOMY.md): a pocket spend with the pawn as actor. Replace for the pawn with a strong urge buff and a warning; the player decides.
6. Eviction has no end state and autopay is off by default (R2.2).
7. `cafe_restroom` (restroom when "lacks a toilet") becomes dead because the flat has a toilet; keep for NPCs.

### R3. Difficulty ladder (Normal is already difficult)

Normal is "just feasibly get by". Easy gives a bed and slack; Hard removes the cushion. Existing ids (`relaxed`, `normal`, `hard`) stay for saves; only the label "Relaxed" becomes "Easy". This replaces the table in Revision 1 section 8 where they differ; the storyteller, hospital, grace, estate rows of that table stay.

| Knob | Easy | Normal | Hard | Where |
|---|---|---|---|---|
| Starting coins | 500 | 300 | 150 | NEW `start_coins` in `difficulties` (replaces `funds_mult` for the start) |
| First week's rent prepaid | yes | yes | no (due day 4) | NEW |
| Flat rent per week | 55 | 70 | 85 | NEW |
| A sofa bed already in the flat | yes | no | no | NEW |
| Bills x | 0.8 | 1.0 | 1.3 | exists |
| Wages x / shop and food prices x | 1.10 / 0.95 | 1.0 / 1.0 | 0.90 / 1.10 | NEW hook (Economy, same style as `bill_mult`) |
| Odd job pay | 24 | 20 | 16 | NEW |
| Entry openings on the first board | 3 or more | 2 or more | 1 | NEW |
| Missed rents before the notice | 3 | 2 | 1 | NEW (`evict_after_missed` per difficulty) |
| Hunger, energy, bladder decay | x0.8 | x1.0 | x1.2 | exists (`need_mult`) |
| Starvation death, help clock | as Revision 1 table (6,500 / 4,320 / 3,000 min; 120 / 240 / 480 min) | | | `02_needs_health.json` |

Alternative for Hard that I do NOT recommend for v1: start in the night shelter with no flat. It needs the lockout/shelter machinery of Tier B before anything else works. Keep it as a later "Hard+" idea.

### R4. Revised plan: stages, effort, risks

Replaces Revision 1 section 9. One session is a focused work block with design in hand, tests and report. S4 and S5 can run in parallel; so can S7 and S8.

| Stage | Deliverable | New tests | Sessions | Risks |
|---|---|---|---|---|
| S0 Foundations | `Pawn` helper (`of`, `is_pawn`, from the `Players` table; no flag), `Pawn.ENFORCE` build constant (default false, deleted in S3), `origin` tags in data, `PawnLeaks` diff harness (R8.1), `Folk.enqueue` counters | `pawn_basics_test` | 1 | Low |
| S1 Silence the pawn | Gates in `SimDirector._fill`, `DynLife`, `PlaceAuto*`, `BabyCare`, `Commute`/`CareerShifts`/`SkipRules`, `OpportunityTaker`, `BankGamble`, story/romance dice (7.3); the explain-or-fail leak test (R8.1) | `pawn_leak_test`, `pawn_alone_test`, `pawn_commute_test` | 2 | Hidden state changers; the 7.3 audit may find more than 10 sites |
| S2 Survival floor | Self-action menu, finite welcome basket, fixtures (toilet, shower, sink landlord-owned), community supper, `PawnWarn` levels, reflexes with grace, cause lines (R8.3) | `pawn_floor_test`, `pawn_warn_test`, `pawn_reflex_fire_test` | 2 | UI; making warnings useful not noisy |
| S3 The new start | Single-adult creator and New Game (presets and scenarios deleted), starter-flat tenancy (own small property, prepaid week, rent review), bills share (landlord pays water/rates), autopay default on, Tier A eviction and shut-off, difficulty ladder data (R3), tips and goals rewrite, `AutoFurnish` and `Pawn.ENFORCE` removed, folk row locked to the pawn | `start_flat_test`, `pawn_rent_test`, `pawn_difficulty_test` | 3 | Tenancy at start touches `HousingProps`/`Economy` ownership; old-save loading |
| S4 Time | Solo auto-skip with the 2x batch margin (R8.2), vital vs lifestyle need multipliers for the pawn, co-op AFK hold | `pawn_skip_test`, `pawn_afk_test` | 2 | Skip rate on the big map (15 to 20 min/s possible) |
| S5 Routines | Revision 1 section 2, unchanged | `pawn_rules_test`, `pawn_rules_replay_test` | 2 | Scope creep ("else", "if") |
| S6 Balance and test migration | `pawn_bot`, tuning of R2 numbers by data only, test migration (R5), new pawn hash baseline, performance probe | `pawn_bot_balance_test` (slow) + a 5-day fast variant | 3 | Numbers are paper arithmetic until here; the owner may want a different feel |
| S7 Storyteller, growth, heirs | Pawn focus and circle (Revision 1 section 8 "world grows"), heir dialog with the child/teen rules (R8.4), playable-heir rule | `pawn_storyteller_test`, `pawn_heir_test`, `pawn_child_test` | 2 | Rates feel wrong until played |
| S8 Ask and the family strip | Revision 1 section 4, shown only once somebody else lives with the pawn | `pawn_ask_test`, `pawn_guard_test`, `pawn_suggest_test` | 1.5 | Odds tuning; prompt volume |
| S9 Move up (optional) | Better flat or a house as a real move (claim a townie home; `PlayerLots.claim` exists for co-op and has no solo path), Tier B night shelter | `pawn_move_test` | 2 | Highest unknown: many systems assume one fixed home lot |
| Total | | about 16 new files | about 20.5 (range 17 to 25) | |

Playable one-character game after S6 (about 15 sessions). Serial length about 14 with S4/S5 parallel. Between S0 and S3 `main` stays playable because `Pawn.ENFORCE` is false.

Cut order if time is short: S9, then S8, then routines depth, then the lifestyle-need multiplier, then Proposal A (ingredients).

### R5. Test migration (counted by grep in `tests/`)

Totals: 338 `*_test.gd` plus 10 `sim_*`/`world_*` files with a `run()` = 348 test files. The Revision 1 figure of 117 "sim-driving" files counted kits, shots and probes; the real number of test files that run the clock or autonomy is 80 (grep for `tick_minute`, `HoodKit`, `advance_minutes`, `autonomy_enabled`, `Autonomy.choose`, `sim_testkit` in `*_test.gd`, `sim_*`, `world_*`). Because a pawn exists only when the `Players` table has the local player (R1), the rest need no change.

| Bucket | Files | What happens | Effort |
|---|---|---|---|
| A. No pawn in the fixture (NPC behaviour, autonomy, systems, UI that never registers a player) | about 313 of 348, including about 66 of the 80 sim-driving files and the old `coop_hash_baseline` (it plays through `HoodKit`, which registers no player) | Unchanged. They keep proving the NPC world. The existing hash baseline stays bit-identical unless a shared data change (ingredient cost, odd-job pay, welcome basket) moves NPC economics; if it moves, the baseline is regenerated once, on purpose, in S6, and the Windows hash is re-matched. | 0, plus 0.5 session for the baseline |
| B. Updated: a pawn is present (they register a player or use the new-game path) | about 32: 8 `coop_*` (commands, home_lot, host, net, players, skip_run, waiting, hash), 6 `succession_*`, 7 misc (`players`, `command_replay`, `camera_focus`, `sleep_places`, `storyteller_core/longrun/play`), 2 kit users (`map_lots`, `romance_longrun`), 3 UI (`ui_hud`, `ui_flow`, `thought_voice_longrun`), 6 `start_*` rewritten | New fixture helper `TestFixture.with_pawn(player_id)` and `TestFixture.npc_household()`; each file picks one. `start_*` become the tests of the new start (`start_flat_test`, goals, difficulty, floor, solo 2-day run). Co-op tests assert the pawn per player. | about 2 sessions |
| C. Deleted (tests of a controlled family or a removed feature) | about 3: `auto_furnish_test` (the `AutoFurnish` half; the `HomeBare` half moves to a new small `home_bare_test`), `logic_homemaker_test` (the "player told nobody brings money" rule is moot for a solo pawn), the family-preset parts of `start_scenarios_test` | Delete, with a commit note. | 0.2 |
| D. NEW | about 16 `pawn_*` and start tests (table in R4) | In their stages | inside the stages |
| E. Shots and probes (`*_shot.gd`, `*_probe.gd`, about 45 call `start_new_game`) | not in the tiers | Re-run by hand at S6; creator and New Game shots are redone. | 0.3 |

New hash baseline: `tests/baseline/pawn_hash_3day.json`, played by `pawn_bot` through `NewGame.start` (a pawn present), with its own test. `CoopHash.canonical()` stays as it is.

### R6. Dead code: removed, kept for NPCs, or changed

| Piece | Where | Verdict |
|---|---|---|
| `AutoFurnish` (236 lines), its daily registry row (`sim_registry.gd`), `Economy` furnish block (`reset`, `to_dict`, `from_dict`), `Commands` `note_order`, `main.gd` and `settings_apply.gd` setting, `data/start_home.json` `auto_furnish` | `scripts/systems/auto_furnish.gd` | REMOVE. It exists only for a player household nobody orders. |
| `Homemaker` | `scripts/systems/homemaker.gd` (86), `Careers` daily call, `Cond fridge_clean`, `command_actions.gd` role command | KEEP for NPCs (a homemaker spouse). REMOVE the pawn's "Stay at home" entry; a pawn simply has no job. `fridge_spoiled` and the cond stay. |
| `HomeBare` | `home_bare.gd` (91) | KEEP: NPC housemates in a bare flat go out more. Make `_compute` accept any household that has a resident, not only played ones. |
| `HouseholdSetup` presets (`make_household`, `rel`, `inherit_child_looks`, `MAX_FOLK`, multi-folk `validate`) | `household_setup.gd` (294) | REMOVE about 110 lines. KEEP `random_folk`, `random_traits`, `random_name`, `create_folk`, `apply` (NPC and heir creation, tests). |
| `HouseholdCreator` | `household_creator.gd` (226) | CHANGE to one adult: name, sex, traits, aspiration, looks. Remove add/remove member, age group and relation pickers. |
| `StartPicker` scenario cards, funds options, Free Play | `start_picker.gd` (299) | CHANGE: one "New Game" screen: creator, difficulty, storyteller, home-roll (flat look). About half the file goes. |
| `coop_household_pick.gd` | 92 lines | CHANGE: each joining player makes one adult. |
| `data/scenarios.json` couple, family, roommates, sandbox | 133 lines | REMOVE those four. Keep the `difficulties` block and one start block with tips and goals (rewritten: buy a bed, first wage, pay the rent, buy a computer, make a friend). Keep id `solo` so saves keep their checklist. |
| `data/start_home.json` `furnished` option, `bonus_by_size` | 30 lines | REMOVE. Keep `keep_tags`/`keep_defs` (add toilet, shower, sink) and `basics` (feeds the "next step" tips). |
| `welcome_snack`, `sleep_floor`, `cafe_restroom` | `data/interactions.json` | KEEP; make the first two finite/orderable for the pawn; `cafe_restroom` stays for NPCs. |
| Folk row "control any folk" (`hud.gd` `select_folk`, `_on_selection_changed`, `folk_panel.gd` enqueue paths) | `scripts/ui/hud.gd` (556) | CHANGE: selecting another folk opens inspect/ask only. A `CommandActions._interact` guard rejects orders for anyone but the pawn. |
| `Scenario.funds_for` / `funds_mult` | `scenario.gd` | CHANGE to `start_coins`. |
| `PlaceAuto`, `DynLife`, `DynPlans`, `BabyCare` for NPCs | | KEEP, skip the pawn (Revision 1 table 7.2). |

### R7. The reviewer's defaults: where I agree and where I do not

| Default | My view |
|---|---|
| Routines: Full, literal, cap 8 | Agree. It matters more now: the first days are chore-heavy and a routine ("Sleep at 23:00") is the relief. |
| Fire: flee after the grace period | Agree. |
| Bills: autopay on by default, eviction and shut-off when money runs out | Agree, with two notes. (a) Autopay pays what it can; it must never hide rent: a missed payment still raises the warning. (b) "Shut-off" is new: after two late bills the household is disconnected (power and water off, so shower, toilet and lights stop) until paid, reusing the city utility outage plumbing. About 0.5 session in S3; cause line "the utility cut you off because two bills went unpaid; ends when you pay". The default flips in the setting and in `NewGame`, not in the static `Economy.auto_pay`, so NPC and test economics do not change. |
| Pregnancy, marriage, move-ins only by order or accepted prompt | Agree. Note: an NPC partner starting "try for a baby" with the pawn as target is an NPC advance and goes through the prompt rule. |
| Co-op: AFK hold | Agree, with a limit: after 10 real minutes the held pawn goes to bed (floor or bed) so an idle player cannot park a safe pawn forever while the others play. |
| No playable heir: nobody-left choice plus recap | Agree. |
| Hard can kill by starvation | Agree. It is only fair because the free supper and the corner shop always exist; the death cause text must say which warnings were ignored. |
| Family strip shows mood and activity | Agree. It is empty and hidden for most of the early game (the pawn lives alone); show it only once somebody lives with the pawn. |
| Pets self-care | Agree; pets still cost money to adopt and to vet (player decisions). |
| Big NPC advances prompt, small ones happen | Agree, with a cap: at most 3 prompts per game day, and an unanswered prompt counts as "not now" after 2 hours. A lone pawn gets most of its story from NPCs, so prompt volume is the risk. |

### R8. The four review additions, integrated

#### R8.1 The leak test covers non-interaction changers

`pawn_leak_test` becomes an explain-or-fail diff, not only an `interaction_started` check. Each game minute, for 14 game days, 3 seeds, an idle pawn and a `pawn_bot` pawn, it snapshots: lot and tile, coins, the set of owned objects, relationship values, job, household members, and the current interaction. Any change must be explained by one of: a command in the command log (player order, including a routine firing), an interaction whose definition has `origin` of `body`, `hazard` or `hold`, or a world consequence listed in `data/control.json` `allowed_sources` with its id. An unexplained change fails the test and names the minute and the changed value. This avoids instrumenting 40 call sites.

Non-interaction changers to check (the list for section 7.3):

| Changer | File | Pawn rule |
|---|---|---|
| Commute and stranded-home trips | `TransportTrip.start`, `Commute`, `NeighborhoodLots.stranded_home` | Only by `go_to_work`/`go_to_school` order or routine. Walking home after a shift is part of that order. `stranded_home` off for the pawn. |
| Away holds (school, hospital, jail, vacation return) | `Away`, `Hospital`, `Justice*`, `Vacation` | World consequence (`hold`), allowed. |
| Lot moves and teleports | `Neighborhood.travel`, `NeighborhoodTravel`, `PlaceAuto` | Only by order. |
| Spending from the pawn's pocket | `Economy.record/spend` by systems | Bills/rent autopay and hospital charges are allowed standing orders; `AutoFurnish` deleted; `BankGamble` auto-tickets replaced by an urge buff. |
| Buying and selling | `Economy.claim_bought`, `sell_object`, repossession | Only by command; repossession is a world consequence. |
| Relationship changes from dice | `Straying`, `StoryThreads`, `SocialConflict`, decay | Allowed when an NPC acts toward the pawn and the pawn is the victim or target; NEVER when the pawn is the automatic actor. |
| Job changes | `OpportunityTaker`, layoffs, `CareerShifts` missed shift | Auto-accept removed for the pawn; layoffs and missed shifts are world consequences. |
| Life events | `Conception`, `Pregnancy`, `FamilyMarriage`, `StorySingles` move-in and adoption | By order or accepted prompt only. |
| Crime with the pawn as actor | `CrimeForce`, `CrimeRevenge`, `CrimeMurder` rage, `CrimeDomestic`, `SocialConflict` | The 7.3 audit list; ask with `JusticePlayer.ask` or pick an NPC. |

#### R8.2 The skip must stop with a margin

Revision 1 section 3.3 already stops auto-skip on Amber. The Red text ("will pass out in about an hour") is only true if skip cannot cross the Red ETA inside one frame batch. Rule (`TimeFlow`): each skip frame advances at most `batch` game minutes (the achieved rate is a frame budget; `CoopTime` caps it at 6 per frame today). Before each frame compute `eta_red` = minutes until the first need, hazard or deadline crosses Red or a shift's leave-by time. If `eta_red < 2 x batch` (use the larger of the last batch and the cap), drop to 1x and show the banner. The margin is therefore at least 12 game minutes at today's cap and grows with the batch. Events with no ETA (a visitor, a phone ring, a fire) stop the skip on arrival as in Revision 1. `pawn_skip_test`: for needs at many offsets above Red, run a skip and assert it stopped at or before the Red threshold plus 2 batches of decay; also a shift leave-by case and a rent-due case.

#### R8.3 Every reflex, warning and ask outcome has a cause line

| Outcome | Cause line ("X because Y; worse only if Z") |
|---|---|
| `collapse_floor` | Because hunger or energy sat at the floor for 48 hours; ends in rest or hospital; worse only if it happens again (each hospital stay is billed). |
| `pass_out` | Because energy hit the floor; lasts about 2 hours; worse only if it happens somewhere unsafe (a road). |
| `have_accident` | Because the bladder was full and no toilet was reached; resets the bladder; mood penalty only. |
| `flee_fire` | Because the room is burning; only after the grace window, and any order from the player wins; ends at the street. |
| `take_cover` | Because of a disaster nearby; ends at the first safe spot. |
| Smoke alarm wake | Because a loud alarm sounds; wakes the sleeper, does not walk. |
| Info / Amber / Red warning | Because the need crossed the level; Red ETA is computed from the real decay so it stays true while skipping. |
| Late-rent warning, notice, eviction | Because rent was unpaid N days; worse only while the arrears stay unpaid. |
| Shut-off | Because two bills were unpaid; ends when paid. |
| Skip stopped | Because a need, bill, visitor or hazard needs the player, with the reason on the banner. |
| Ask: Yes / Later / No / Cannot | A "No" must name a reason the game can check: "too tired" only when energy is actually below the low mark, "at work" only when away at work, "you asked three times in three hours" only when nagging was counted, "does not like you" only when the relationship is below -50, "doesn't feel like it" only when the roll lost AND no stronger reason applied. |
| Child told to come home | Because a child under 13 must be home by 21:00; worse only if ignored (told off, a small friendship cost). |

#### R8.4 Child and teen pawns

An heir can be 8. Rules (one line in S7, one test file):
- Child (about 7 to 12): school by order (`go_to_school`; missing it is truancy with a school note, not a job penalty); no job; cannot use adult-only interactions (the `age_stage_is` tests that exist in the data; whether the stove is already closed to children is NOT verified and needs a check); cannot spend the household's money except on food and small things (whether `ShopBuy` has an age rule is NOT verified); parents are NPCs who feed, scold ("come home", "bedtime") and may refuse the child's asks with real reasons.
- Teen: school by order, a part-time job by order (`bank.json` teen_job 15:00 to 19:00), curfew prompts from parents, no marriage, no pregnancy.
- Playable heir rule: babies and toddlers are never playable; a child or teen heir needs an NPC adult guardian in the household. With none, the existing nobody-left flow (relative takes them in, then the child lives in that household with NPC guardians) runs.
- Test case in `pawn_child_test`: an 8-year-old heir with a parent present (school order works, job order refused with a reason, stove refused with a reason) and without (nobody-left prompt).

### R9. Questions I still have for the owner (few)

1. Eviction outcome: is "the bailiffs clear the flat and you must pay arrears plus a deposit to sign again" (Tier A) enough for the first release, with the night shelter in a later stage? My recommendation: yes.
2. Home cooking: ingredients at 3 coins a meal (Proposal A, recommended) or free (B)?
3. Is a free evening supper at the community hall acceptable as the "soup kitchen" floor, or should it be a worse deal (a queue, a small mood penalty "embarrassed")?
4. Is moving to a better flat or a house a must for the first release (S9, highest unknown) or can the first release end at "own a computer and a kitchen"?

---

# Revision 1 (task 35), edited where Revision 2 overrides it

The owner's rule, restated so the plan can be checked against it (still true in Revision 2; the pawn is now simply the head of the local player's household, with no flag):

- The player plays ONE folk (the "pawn") until that folk dies. No switching before death.
- The pawn has NO autonomy: nothing happens to them unless the player ordered it. No need-driven picks, no idle fillers, no 14b outings, no 32c plans or reactions.
- Everyone else (the rest of the household, the town) are autonomous NPCs who react to the pawn.
- On death the heir flow of task 15 picks the next pawn.
- The world grows; the storyteller (29) aims at the pawn and their circle, scaled by difficulty.

---

## 0. The short version

1. This is mostly a SUBTRACTION from the existing game, not a rewrite. Today's player household already runs on the same AI as the town. The whole job is: stop the AI from driving one folk, keep the body/world "consequence" rules that already exist, and give the player better tools to compensate (warnings, routines, requests, time skip).
2. The most important design fact: every autonomous action of a folk ends up in ONE method, `Folk.enqueue(inter)` (`scripts/sim/folk.gd`), except the autonomy pick in `SimDirector._fill` (`scripts/sim/director.gd`) which calls `Interaction.start()` directly. Two doors, not forty. I counted about 50 `enqueue` call sites in 25 files that are NOT the player's UI (BabyCare, DynLife, Commute, CareerShifts via Commute, fire, health, social gatherings, story visits, crowd, ...). One choke point plus an allowlist (below) catches all of them, and a leak test proves it.
3. REVISED (task 36): there is NO mode switch. One character is the only game (R1). The test files and the old hash baseline mostly stay untouched for a different reason: a pawn exists only where the `Players` table registers the local player, so most fixtures have no pawn (R5).
4. Measured: leave a character completely alone and the existing safety net (bladder accident, pass-out, hunger collapse, housemate help, ambulance, hospital stay) already keeps them alive for 8+ game days with no reflex at all. See section 1. So "no autonomy" does not require any new survival AI. It requires WARNINGS.
5. Estimate: about 14 agent-sessions (range 11 to 18), 9 stages, of which two pairs can run in parallel. Biggest risks: hidden dice-based incidents where the pawn is the actor (section 7.3), the routine (rules) UI scope, and tuning the skip speed.

---

## 1. Q1 - Survival without autonomy

### 1.1 What really happens if the player leaves the character alone (MEASURED)

I ran the real game headless (hood kit, seed 4242, classic home, 3 folk). The folk "Mira" had her autonomy switched off (her `idle_until_min` pushed far out, so `SimDirector._fill` never picked anything), everything else normal. Then the same with all three folk switched off, 8 game days. Probe script lived in the scratchpad, not in the repo. Start: needs 55-70 at 07:00 day 1.

| What | When (game time since 07:00 day 1) | Notes |
|---|---|---|
| Hunger below -20 ("hungry" buff) | about 17 h | thought "I'm hungry..." (existing ThoughtVoice) |
| Bladder below -35 / below -75 | about 17 h / about 24 h | "full bladder", "bursting" buffs |
| Bladder accident (`have_accident`, emergency at -98) | about 27 h (day 2 morning) | bladder reset, toast "Someone didn't make it to the bathroom" |
| Energy to -98: `pass_out` (emergency) | about 39 h (day 2 evening) | lies down where they stand, about 2 h, energy back to about -40; then cycles roughly every 12-14 h |
| Hunger at the floor (-92) | about 33 h | stays at -100 |
| Hunger COLLAPSE (`collapse_floor`, `Health` collapse_min 2880 at the floor) | about 80 h (day 4, afternoon) | housemate helps (`HealthCollapse._auto_help`) within about 3 h; if nobody is there, ambulance after `town_help_min` 240 min |
| Death by starvation (`death_min` 4320 at the floor) | NOT reached in 8 days | the collapse/rescue resets the clock; every rescue lifts hunger to +15 |

All three folk alone for 8 days: 6 collapses (2 each), 6 `neglect_emergency` ambulance runs, 12-hour hospital stays, 0 deaths. Hygiene, fun, social sit at -100 for days (mood is awful, no other consequence was visible; I did not measure illness from filth). Cost of the probe: about 8 ms per game minute headless on the small hood.

Reading it as a designer:

- The safety net already is the "tiny set of reflexes", and none of it is a choice. `collapse_floor`, `pass_out` and `have_accident` are interactions with an `emergency` condition in data (`data/interactions.json`, `data/incidents/02_needs_health.json`), queued by `SimDirector._check_emergencies`. They are the BODY, not the mind. They stay as they are.
- A neglected pawn does not die in 3-4 days; they collapse and get a hospital bill. That is generous. Hard difficulty can tighten it with data only (`death_min`, `town_help_min`, see Q8). Easy leaves it.
- The first thing that goes wrong is mood and the first costly thing is the accident, a day after the player stopped caring. Plenty of time for warnings.

### 1.2 Which reflexes are safe to keep without breaking "no autonomy"

Test I propose for "reflex" (a rule anyone can check): an action is a reflex only if ALL of these hold.
1. It answers an immediate physical danger or an incapacitation, never a want or a need level.
2. Its goal is to stop harm (get out, get safe, fall down), not to get something.
3. It gives no lasting benefit (no need gain, no skill, no money) and ends in a safe place, then control returns.
4. It never picks a target the player would call a choice (no "rescue the baby", no "grab the extinguisher").
5. The player gets a warning and a grace window first, and any order from the player during the grace window wins.
6. It is listed in data and shows in the pawn's log ("Mira ran out of the burning house").

| Candidate | Keep? | Why |
|---|---|---|
| `collapse_floor`, `pass_out`, `have_accident` (existing emergencies) | KEEP | The body giving out. Not a choice. |
| Hospital stay, ambulance, jail/court holds, `stuck_in_lift`, labour, `Away` holds | KEEP | State changes forced by the world, started by systems. |
| Smoke alarm wakes a sleeper (cancels `sleep_*`, no walking) | KEEP | It is a sound, not a decision. The pawn is woken, the game pauses and shows "Fire! Mira woke up." |
| `flee_fire` (walk to the nearest exit/street, stop there) after the grace window | KEEP, with grace | Meets all six tests. Drop the follow-up `watch_fire` for the pawn (loitering is a choice) and the "85 percent calls the fire department" side effect (calling is an order; the smoke alarm, neighbours and townies already call). |
| `take_cover` in a disaster (`DisasterAftermath`) | KEEP, with grace | Same shape as flee. |
| Choking fit (`acc_trouble_choke`) | NO new reflex | It is an incident roll with `help_per_min` from people nearby (`data/incidents/05_accidents.json`). The pawn cannot "stop it" by choosing anything the game offers; leaving it to the roll plus nearby help is honest. Warning: yes. |
| Use extinguisher, rescue a baby from a fire, call the brigade | NO | Heroic choices. Warn the player, give them the pie-menu orders. |
| Seek shelter from cold/heat (`HealthShelter`) | NO | A choice ("go indoors"). Warn at the exposure steps; the existing `collapse` at stage 2 and the town help (60 min for exposure) are the net. |
| Eat when starving, use the toilet when bursting, go to bed when exhausted | NO | These ARE autonomy. The body handles the failure (accident, pass-out, collapse). |
| Stranded far from home (`NeighborhoodLots.stranded_home`) | NO | Autonomy. |

Grace window (data, not a constant): `grace_min` per danger kind and difficulty: fire 2 / 1 / 0 game minutes on Easy / Normal / Hard, and on every difficulty the game auto-pauses (solo only) the moment the danger starts, with a camera ping. In co-op there is no pause, so the grace is the only protection (co-op uses the Normal value as a minimum of 1).

How it is enforced: the allowlist is data, not code. Each interaction in `data/interactions.json` (and the incident content files) gets an `"origin"` field: `"choice"` (default, everything today), `"body"`, `"hazard"`, `"hold"`. `Folk.enqueue` and `SimDirector._fill` drop anything for the pawn whose `origin` is `"choice"` unless `inter.player` is true. Only about 10 definitions need `body`/`hazard`/`hold` (collapse_floor, pass_out, have_accident, flee_fire, take_cover, hospital_stay, stuck_in_lift, the Away holds, labour, arrest).

### 1.3 Warnings design

All the machinery exists in pieces (`ThoughtVoice`, buff thresholds in `data/needs.json`, `Events.thought`, notifications). What is missing is a PLAN that makes the pawn playable. New `PawnWarn` (small, one file, one `data/control.json` section):

Levels, one rule per level:
- Info: a need crosses "low" (the existing `hungry`, `tired`, `full_bladder`, `grimy`, `lonely`, `restless`, `achy` buffs). Thought bubble above the head (exists) and the need bar pulses. No toast, no sound.
- Amber: crosses "bad" (`starving` -60, `exhausted` -70, `bursting` -75, `filthy` -65, `isolated` -75, `bored_stiff` -65). One toast with a "Show me / Do it" button, a soft chime, auto-skip stops (Q3). The "Do it" button is a plain order (eat something nearby / use the nearest toilet), not a rule.
- Red: the consequence is near ("Mira will pass out within about an hour", "will have an accident in about 20 minutes"). Banner, speed drops to 1x, optional pause. Time to consequence is computed from the need's decay, so the text is true.
- Danger (fire, smoke alarm, gas, crash, a collapse of a housemate, a baby in trouble): immediate pause (solo), camera ping, the grace clock in section 1.2.

Planning tools that make warnings fair:
- Hover on a need bar shows "low in 3 h, bad in 7 h" (same maths as `Folk.tick_needs`, decay x the pawn mult x buff mults; no new state).
- Agenda card ("Today"): shift/school times and the LEAVE-BY time (`Commute.lead_hours` already computes the lead time), bills due, birthdays, visitors expected, forecast. Reminders at leave-by minus 30, minus 10, and at the moment. Missing the shift uses the existing missed-shift code with reason "did not turn up" (`CareerShifts.missed`, `_record_skip`), no extra invention.
- Dependants: "Baby Wren is hungry" at Amber with the child-services timeline already in `BabyCare` (warn at 6 h of neglect, removal at 12 h). Add an earlier Amber for babies and toddlers because those are the pawn's responsibility only if no NPC adult is home (NPC adults still feed and change them, `BabyCare.assign_care`).

---

## 2. Q2 - Player-made routines ("rules")

### 2.1 Is it within the owner's rule?

My position, for the owner to confirm: YES, if routines are literal, visible, capped and written by the player. The line between a macro and an AI is judgement. An AI weighs options and picks one. A routine does exactly what the player wrote, nothing else, and says so when it cannot. So:

- No scoring, no randomness, no "pick the best", no fallbacks, no learning, no "else".
- One trigger, one to three steps. No loops, no rules that fire other rules.
- Each rule is shown in a list with a plain sentence ("At 23:00 go to bed (Mon-Sun)"), can be switched off with one click, and writes a log line each time it fires ("Mira ate (routine: Eat when hungry)").
- When a rule cannot run (nothing to eat, the bed is taken, the walk is blocked) it does NOT improvise. It shows "Your routine 'Eat when hungry' could not run: nothing to eat." and stops.
- A cap of 8 rules per pawn (setting in `data/control.json`).
- A rule belongs to the pawn. On death the heir starts with none; a button on the heir screen offers "Copy the family's routines" (the player decides, once).

Owner switch (setting): Routines: Off / Time-based only / Full. Default Full.

### 2.2 Data model

State (new top-level block `pawn` in `SaveLoad.snapshot()["systems"]`, so its key must also go into `town_system_keys` in `data/share_schema.json`, per the brief):

```
rules[folk_id] = [ {
  id: int,                        # per pawn, increasing
  label: String,                  # generated sentence, editable text
  on: bool,
  when: { kind: "time" | "need" | "shift_leave" | "arrive",
          time: "23:00",          # kind time, minute resolution
          days: [0..6] or "every",# weekday numbers (same as SysUtil.weekday)
          need: "hunger", below: -30,       # kind need: fires on the downward crossing
          window: ["07:00","22:00"]},       # optional: only between these hours
  do: [ { act: "interact", iid: "eat_meal"|..., target: "nearest"|"home_bed"|object_id|folk_id },
        { act: "go", place: "home"|"work"|"lot_id"|tile },
        { act: "commute", kind: "work"|"school" } ],   # max 3 steps
  if_busy: "wait" | "interrupt",  # wait = queue behind the current order; interrupt = start now
  skip_if: ["asleep","away"],     # plain checkboxes
  last_fired: minute, fired: int, last_fail: String
} ]
```

- "nearest" is the same deterministic target picker the pie menu "best object" uses (nearest object of that type that passes `Interaction.def_runnable`, tie-break by object id). The rule editor shows what it would pick today (preview: "Eat meal -> Fridge in the kitchen").
- Needs fire on the crossing, not while below, with a cooldown (data, default 30 min), so a rule that cannot fix the need cannot spam.

### 2.3 Engine and Commands layer

- `PawnRules` (state, save/load, `reset` in `SystemsManager.reset_all`) and `PawnRulesRun` (evaluation). One minute-row in `SimRegistry` with an emptiness gate (`rules.is_empty()` -> not run), so a pawn with no rules costs nothing. Cost with rules: a loop over at most 8 small dictionaries per minute.
- Authoring is a command: `Commands.run({player_id, folk_id, action: "rule", args: {op: add|edit|remove|toggle, ...}})`. The player's UI (and `CoopCommands`) only ever call the command, as the multiplayer rules require.
- Firing is ALSO logged as a command, with `source: "rule:<id>"`, using the existing `_interact` path with `player = true` (so it carries player priority and shows in the queue as the player's order). Determinism: no rng, so replay gives the same sequence; `command_replay_test` extends to include rules.
- "Go to work on time" is the one special: kind `shift_leave`, which calls the same `Commute.begin` that `CareerShifts._start_shift` calls today, at the same `Commute.lead_hours` moment. The rule is therefore just "the player's standing order to let the existing commute run". Without that rule and without a manual `go_to_work` order the pawn misses the shift.
- Co-op: `CoopCommands.ACTIONS` gets `rule` (checked against the sender's pawn).

### 2.4 UI sketch

Folk panel gets a "Routines" tab (also a small clock icon on the queue bar).

```
 Routines (3 of 8)                                   [ + New routine ]
 [x] At 23:00, every day        Go to bed                 fired 12x   [edit][x]
 [x] When Hunger drops below 30 Make a meal and eat       fired 7x    [edit][x]
 [x] Weekdays, leave for work   Go to work on time        fired 5x    [edit][x]
 Last: "Routine 'Eat when hungry' could not run: nothing to eat." (day 3)

 New routine:   WHEN [ at a time v ] [23:00] [every day v]
                DO   [ pick from what Mira can do ... v ]   [+ add a step]
                IF I'm busy: ( ) wait until I'm free  (o) stop what I'm doing
                [ Save ]     preview: "Go to bed -> Double bed, upstairs"
```

Also: "Save these as a routine" on the queue bar after the player queued two or three things by hand ("Cook, eat, wash up"). That is how routines get written naturally.

Is this the right amount? Honest opinion: it is the single biggest tedium reliever and the cheapest, and it is also the biggest source of "that is autonomy with extra steps" arguments. The literal rules above are the safeguards; the cap of 8 and no-else rule keep it a macro tool.

---

## 3. Q3 - Pacing

### 3.1 What the numbers say now (from `data/needs.json`, `data/interactions.json`)

Decay per game day (1440 min): hunger 108, energy 79, bladder 151, hygiene 63, social 72, fun 95, comfort 48 (range is 200). Restores: `use_toilet` 4 min +112, `take_shower` 10 min +100, `eat_meal` 15 min +67 (`cook_meal` 25 min), `grab_snack` 4 min +24, `chat` 15 min +45, `watch_tv` 60 min +42, `sleep_bed` 660 min +82.

Minimum chore orders per game day to stay out of trouble at today's rates: toilet 1.4, meals 1.4 x (cook + eat) = 2.8, shower 0.6, sleep 1, chats 1.6, fun 2.3 = about 10 orders, plus 1 work trip, plus some walking. That is NOT many (a Sims player gives far more). So the tedium risk is not the NUMBER of orders; it is WAITING and WALKING at 1 game minute per real second. A game day at 1x is 24 real minutes, at 2x 6 minutes, at 3x 2 minutes (`Clock.MIN_PER_SEC` = 1 / 4 / 12). 11 hours of sleep and 8 hours of work are the long dead stretches.

### 3.2 Proposal

1. Do NOT shorten task lengths. Fix the dead stretches with a skip (3.3).
2. Need decay for the pawn only: keep the existing ladder (`data/scenarios.json` relaxed 0.8, normal 1.0, hard 1.2) but apply it to the pawn alone, and add a second knob: lifestyle needs (social, fun, hygiene, comfort) x0.85 on Normal because neglecting them costs only mood, while the vital needs (hunger, energy, bladder) keep x1.0. Start values, to be tuned by the measurement below: Easy 0.7 / 0.8, Normal 0.85 / 1.0, Hard 1.0 / 1.2 (lifestyle / vital).
3. Meal macro: "Make and eat a meal" as ONE order that queues prep/cook/eat/wash in sequence from the same data (it is a convenience, the pawn still does it step by step, and it is still an order).
4. Sleep stays 660 min but `sleep_bed` already ends at `circadian day` or energy over 60 (`end_when`), so a good night is about 8-9 h. With the skip it costs 10 real seconds.
5. A "Skip" speed (4th speed, auto): see 3.3.
6. The queue bar already lets the player chain orders; keep it and show total time ("Done by 14:20").

### 3.3 Time skip for one character

Today only co-op has a skip (`CoopTime`: SKIP_RATE 45 game min per real second while all players are passive). Reuse that logic for solo. Rule: the clock auto-speeds to the skip rate while the pawn is PASSIVE = in `sleep_*`/`nap_*`, `Away` (work, school, hospital, trip), or walking a trip longer than 10 min, AND nothing needs the player. It stops (and drops to 1x) on: any Amber or Red warning, any NPC interaction aimed at the pawn (visitor at the door, a chat request, a phone ring), a weather alert, danger, a bill/birthday. Banner: "Sleeping - skipping ahead (Esc to stop)". An empty queue while awake is NOT passive (the player is thinking); no skip.

Real cost: the sim costs about 20 ms per game minute in the standing performance budget (`docs/PERFORMANCE.md`, 22 ms today, about 38 ms at the big scale). 45 min/s therefore needs 0.9 s of CPU per real second: not possible at 60 fps. So the skip rate is a FRAME BUDGET, not a number: advance as many minutes per frame as fit in about 25 ms (1 minute per frame today, i.e. 30-45 min/s, maybe 25 min/s on the big map), and show the achieved rate. Honest unknown: the real figure on the big town with crowds. Measurement plan below.

Expected result (arithmetic, to be confirmed): an ordinary day = 8-9 h sleep + 8 h work at about 30-45 min/s = about 25-35 real seconds, plus about 7-8 free hours at 2x (4 min/s) = about 2 minutes. Total about 2.5 real minutes per game day, versus 24 at 1x.

### 3.4 Measurement plan (what to measure, targets)

A "pawn bot" test driver (`tests/pawn_bot.gd`, a deterministic scripted player: reacts to Amber warnings with the "Do it" order after a human-like delay of 3-8 game minutes, follows a day plan) plays 10 game days x 3 seeds on the hood and the big map, in each difficulty, and prints:

| Metric | Target (Normal) |
|---|---|
| Chore orders per game day | 8-14 |
| Orders per game day including work/trips/social | 12-20 |
| Share of game time at skip speed | 35-55 percent |
| Real minutes per game day (2x when active, skip when passive) | under 4 |
| Amber warnings per game day | under 6 |
| Red warnings per game day | under 0.5 |
| Missed shifts per 10 days by a reasonable bot | 0-1 |
| Skip rate achieved (game min per real second), small hood / big map | at least 30 / at least 20 |
| Frame time during skip | under 33 ms average |

Also record the "leave alone" table of section 1.1 per difficulty so the timings are in the docs. Tuning rule: change data only (`data/control.json`, `data/scenarios.json`), never code, between runs.

---

## 4. Q4 - The household: requests

REVISED (task 36): the game starts with ONE adult living alone, so this section matters only once somebody moves in (a partner, a child, a roommate). It is stage S8, lower priority than the solo loop. The family strip is hidden while the pawn lives alone.

### 4.1 No switching before death

The HUD folk row (`hud.gd`: `rebuild_folk_row`, `select_folk`, `_on_selection_changed`) lets you select any household member today, and clicking a same-household folk selects them. In `one` mode:
- `selected_folk_id` is always the pawn (`Pawn.of(Players.local_id)`).
- The folk row becomes a "household strip": the pawn big on the left, the others as portraits with a mood icon and an activity line. Clicking an other opens the INSPECT card (read-only: name, relationship, mood, what they are doing) and the "Ask" menu. It never changes control.
- The server-side guard: `CommandActions._interact` rejects an order for any folk of a player's household that is not that player's pawn: "You can only direct Mira. Ask Tobin instead." That also covers co-op (`CoopCommands.allowed`) and old UI paths (`folk_panel.gd` line 716 uses `UIU.enqueue`). The UI hides what the guard would refuse; the guard is the truth.

### 4.2 The Ask system

Asking is a command: `Commands.run({player_id, folk_id: pawn, action: "ask", args: {target_id, request: "cook_for_us", object_id?}})`. The result is the target's answer.

Requests (data in `data/requests.json`, about 14 to start, each maps to existing interactions and is stage-gated):
cook a meal for everyone, do the dishes, clean up, take out the trash, do homework (kids), go to bed (kids, partner), come with me (follow to a lot), watch the baby, play with the kids, come to dinner, join me in a chat, turn the TV down (stop), pass me food (hand over), a favour (money small), "please leave me alone".

Answer formula, deterministic and explainable (no number is shown to the player; they get the words "likely / maybe / unlikely" colour-coded in the menu):

```
p = base[request] (easy 0.75, chore 0.55, personal 0.35)
  + 0.25 * (friendship + 0.5*romance)/100                 # liking, range -0.25 .. +0.25
  + role[asker -> target]     # parent -> child under 13: +0.30, parent -> teen: -0.10,
                              # adult -> adult household: 0, adult -> elder: -0.10, elder -> adult: -0.05, sibling: -0.05
  + trait terms               # lazy -0.20 on chores, helpful/neat +0.15 on chores, rebellious/stubborn -0.20,
                              # forgiving/grudge-holder by the history of refusals, workaholic -0.15 for fun requests
  + mood term                 # happy +0.10, angry -0.20, tense -0.10
  + need term                 # target's urgent need (hungry, tired) -0.20 for anything that is not about it
  - 0.10 * (asks of the same asker in the last 3 h, max 3)         # nagging
  + "polite" +0.05 / "firm" (kids only) +0.15 but costs -1 friendship afterwards
  + difficulty ask_bonus (+0.10 Easy, 0, -0.10 Hard)
clamp 0.05 .. 0.95;  roll = stateless hash(master seed, target, asker, day-minute, ask counter) -> same replay.
```

Answers: Yes (the target enqueues the interaction, `origin "choice"`, `player=false`, priority "high", tagged `ask`, with a short line "Okay."), Later (a pending ask, at most 3 per target, executes when they are free within 90 min), No (with a plain reason: "Tobin is too tired", "Wren doesn't feel like it", never a number). Cannot (asleep, at work, away): the menu entry is greyed with the reason, no roll.

Side effects: a yes that is carried out +1 friendship with the asker; a no after nagging -2; "firm" with a child -1 and a small buff `told_off`. Strong dislike (relationship under -50) refuses everything except emergencies.

NPCs asking the pawn (the world reacts): Dinner is ready, a partner wants a talk, the kids want to play, a friend rings. These are SUGGESTIONS, not actions: a toast with Accept / Not now. Accept queues the player's own order (`player = true`). This reuses the 32c content (DynSocial family dinner, friends over) as the source of the offers, which is how it keeps its value in the new mode. NPC-to-NPC behaviour is unchanged.

What does NOT change: NPC household members keep full autonomy including chores, cooking for themselves, school, work, outings (14b). Their results reach the pawn through the world (food on the table, a clean house, a partner at the door).

---

## 5. Q5 - Co-op

Fits well and gets simpler: each player has one pawn (`Players.table[pid].head`, which already exists from task 15; `Succession.head_of(pid)`). The rest of that player's household are NPCs.

- Commands: `CoopCommands.allowed(pid, folk_id)` in `one` mode means "the sender's pawn". New actions `ask` and `rule` are allowed for the sender's pawn only (checked in `CoopCommands.ACTIONS`).
- Time: `CoopTime.passive(pid)` becomes "the pawn is passive" (asleep, away: work, school, hospital, a trip) instead of "all household folk are passive" (`household_passive`, `folk_passive`). It is a cleaner rule now: NPC family never blocks a skip.
- Autopilot problem (real): `CoopTime.IDLE_S` marks a player with no input for 3 real minutes as "on autopilot" and counts them as passive, so the skip runs for everybody. With no autonomy the idle pawn then stands still while the world skips at 45 min/s: they come back to a pawn at the hunger floor. Needed: an AFK HOLD. When a player goes idle their pawn is frozen safe: needs paused (`Folk.decay_mult` returns 0 for a `meta afk` folk), nobody targets them, the storyteller skips their key, a "(away from keyboard)" tag shows. Alternative (worse): an idle player blocks the skip. Open question 6.
- Skipping with different sleepers: unchanged (everyone passive -> skip).
- Join flow: `CoopHousehold*` picks a household preset; the creator marks who is the pawn (default: first adult).
- A pawn that dies in co-op follows the same heir flow (`Succession`), toast to everyone (`CoopAlerts` already alerts on death).
- Waiting players: `CoopWaiting` stays.

---

## 6. Q6 - UI

REVISED (task 36): read the right-hand column as "the only game", not "one mode". The household strip, folk-row lock and heir dialog are unchanged; the New Game, creator and Start picker rows are replaced by R6.

| Part | Today | In `one` mode |
|---|---|---|
| Camera | follows the selected folk on the big map (`LotView`, `focus_on`) | follows the pawn always; a "free look" key temporarily detaches and snaps back on any order |
| Folk row (`hud.gd`) | portraits of every household member, click = control | household strip: pawn big, others smaller with mood + activity; click = inspect/ask |
| Panels (needs, goals, careers, money, life hub, relationships, town) | built `for_selected_folk` | same calls with the pawn id; no change needed other than `selected_folk_id` being locked |
| Folk panel buttons that enqueue (`folk_panel.gd` ~716) | order any household folk | order the pawn; for others show Ask |
| Pie menu (`pie_menu.gd`, `pie_entries.gd`) | actor = selected folk | actor = pawn; clicking another household member opens the social pie with an "Ask..." category (the other-household social pie already exists in `hud._on_selection_changed`) |
| Queue bar (`queue_bar.gd`) | the folk's queue | + "Save as routine", total time, rule-origin marker |
| Top bar | speed buttons 0-3 | + Skip indicator and auto-skip toggle; Agenda button; Routines button |
| Warnings | thoughts + toasts | `PawnWarn` levels, need timeline tooltips, danger banner |
| Family tab | head, next in line, Make Heir | + the household list with relationship and Ask buttons |
| Heir screen | toast on `head_changed` | a modal "Mira has died. Play as: [Tobin ...]" with "Keep the family routines" tick, the default being the existing line (`HeirLine.candidates`) |
| Help / tips (`scenarios.json` tips, first-run tips) | "Folk look after themselves" | rewritten for one mode: "You are Mira. Nothing happens unless you say so..." |

---

## 7. Q7 - What changes in existing systems (complete list)

### 7.1 The pawn helper, the choke point (REVISED task 36: there is no mode)

New, small, each under 300 lines:
- `Pawn` (`scripts/systems/pawn.gd`): `of(player_id)` (the head from the `Players` table; -1 when no player is registered), `is_pawn(folk)`, `acts_alone(folk)` (= not the pawn), `need_mult(folk)`. REVISED (task 36): no `mode` field, nothing saved for it; a temporary build constant `Pawn.ENFORCE` is allowed until S3 (R1). No `SaveLoad.VERSION` bump: additive.
- `Reflexes` (small): reads `origin` from the interaction def and the difficulty grace; `PawnLeaks` (counter of blocked enqueues for the debug UI and the leak test).
- `PawnWarn`, `PawnRules` + `PawnRulesRun`, `Requests` + `RequestOdds` + `RequestCmd`, `TimeFlow` (solo skip, shares the logic with `CoopTime`).
- Data: `data/control.json` (reflex graces, warning thresholds, rule caps, ask numbers, skip budget), `data/requests.json`, `data/rule_templates.json`, ladder keys in `data/scenarios.json`.
- UI: `routines_panel.gd`, `ask_menu.gd`, `household_strip.gd`, `warn_banner.gd`, `agenda_card.gd`, `heir_dialog.gd`.
- Save: new block `systems.pawn` (rules, pending asks, warn state, afk) AND its key added to `town_system_keys` in `data/share_schema.json` (`share_town_test` catches a miss).

The enforcement line (REVISED: always on once `Pawn.ENFORCE` is gone): `Folk.enqueue` returns without queuing when `Pawn.is_pawn(self)` and `inter.player` is false and `Reflexes.origin_of(inter) == "choice"`. `SimDirector._fill` returns before `Autonomy.choose` for the pawn. `Autonomy.choose` itself also returns `{}` for the pawn (defence for debug UI/tests).

### 7.2 Systems to change, one by one

| System (file / class) | Today | Change | What breaks / note |
|---|---|---|---|
| `SimDirector._fill` (`director.gd`) | runs Autonomy for every folk incl. the player household; `stranded_home` | pawn: return after the queue handling; no `stranded_home` | `SimDirector.last_choice` and the autonomy debug panel show nothing for the pawn |
| `Autonomy` (`autonomy.gd`) | gather/choose, `DynLife.idle_ok`, traits, routines, variety, pacing | none for NPCs. Pawn: guard returns {} | tests that call `Autonomy.choose(pawn)` in `one` mode (none today) |
| `AutonomyVariety`, `Routine` (data/routines.json), `Circadian`, `MoodSwings`, `SkillInterest` | autonomy weights; `Circadian` also gives phases to Cond tests (`sleep_ok`) | weights unused for the pawn. `Circadian` keeps working as phases and for NPCs; `sleep_bed` has test `circadian sleep_ok` that also gates PLAYER orders (a player cannot nap at noon with energy over 92): keep, but show the reason in the pie menu. `MoodSwings` (groggy, off_day, work_stress) are consequences, keep | none |
| `DynLife`, `DynPlans`, `DynReact`, `DynSocial` (32c) | hourly plans, reactions, family dinner, friends over for all residents | `DynLife.people()` excludes the pawn as ACTOR. Reactions: pawn is never made to look out of the window. Social: the buff and the invite become SUGGESTION toasts to the pawn (4.2). | `dyn_life_test` assumes household members get plans (household mode only) |
| `PlaceAuto*` (14b: `place_auto.gd`, `_plan`, `_gate`, `_now`, `_trip`, `_time`, `_townies`) | plans outings for all residents, illness and pets hourly | `PlaceAuto.on_day` skips the pawn; `PlaceAutoNow.on_hour` illness/pet care skips the pawn (replaced by warnings); the Town window (`LifeCommand`) is the pawn's way, unchanged | Q: pets (see unknowns) |
| `BabyCare` / `ChaosNeglect` / `ChildServices` | `assign_care` picks caregivers incl. the player's folk and pulls them off their own thing | `caregivers_for` excludes the pawn; babies still get cared for by NPC adults; if the pawn is alone with a baby the timeline of neglect (6 h warn, 12 h removal) applies with earlier Amber warnings | `baby_night_feed_test`, `systems_family_baby_test` are household tests, unchanged |
| `Homemaker` (`homemaker.gd`) | REVISED (task 36): see R6 (kept for NPCs; no pawn entry). Was: role: no job, autonomy bonus for chores, a daily free cleaning/fridge bonus and kid bonus | NPC homemakers unchanged. Pawn: the role only means "no job"; no free daily bonus (it is invisible autonomy) | open question 4 |
| `AutoFurnish` (32f) + `HomeBare` | REVISED (task 36): `AutoFurnish` is REMOVED, `HomeBare` kept for NPCs (R6). Was: buys basics for a player household nobody orders for 2 days; `HomeBare` also sends folk out (`out_gain`) | pawn household: off in `one` mode (it would buy on the pawn's behalf). `HomeBare` gains in DynPlans/PlaceAuto are moot for the pawn; kept for NPCs | `auto_furnish_test` is household-only |
| `Commute`, `CareerShifts`, `SkipRules`, `Away` (school) | leaves for work/school automatically at `lead_hours`; "chooses to skip" is a dice roll when the player has queued something | pawn: no automatic dispatch. New commands `go_to_work` / `go_to_school` call the same `Commute.begin`; the shift_leave rule calls it on time; no order and no rule = missed shift (existing penalty path). `SkipRules.chooses_to_skip` is bypassed for the pawn (the player decides). The walk home after the shift stays part of the trip order | `commute_test`, `commute_longrun_test`, `city_commute_test`, `bldg_commute_test`, `commute_factory_test` assume automatic dispatch (household mode only) |
| `Careers` auto job search (`seeking`, offers) | offers arrive; accept is a player command already | offers fine. Auto-accept anywhere? (check `Careers` for NPC-only auto accept) | verify |
| `StoryPacing`, `StoryThreads`, `StorySingles`, `Straying`, `OpportunityTaker` | per-household drama calming, nudged dates, move-ins | key stays the household (the pawn's), but `StorySingles` should nudge the PAWN and circle, not every single adult in the house; `Straying`/`StoryPacing.interaction_mult` act on NPC autonomy only | `story_pacing_test` (23 files reference StoryPacing) unchanged in household mode |
| `Storyteller` (29) | budget keys per household `h<id>`, townie lot `l<n>`, district, town; folk-targeted cards pick any adult | pawn gain multiplier and pawn-first folk targeting; circle gain (section 8) | `storyteller_core_test`, `storyteller_play_test`, the two slow long-runs: run in household mode; new `pawn_storyteller_test` |
| `Succession`, `HeirLine`, `SuccessionTake`, `SuccessionNobody` (15) | head dies -> heir takes control; moved-out child moves back | the new pawn = new head. `Pawn.on_head_changed`: clear any autonomy residue in their queue, keep the family's routines only if ticked. `HeirLine`: babies and toddlers are never playable (a toddler cannot use most interactions): they go last and, if only they remain, `SuccessionNobody`. A dead pawn without an heir = existing "nobody left" flow | `succession_*_test` (7 files) household tests unchanged |
| `Tiers` (`tiers.gd`) | anchors = non-away folk of every household in the Players table + camera | `one` mode: the pawn + camera (family members are always ACTIVE anyway: they are "kind 0" fixed, not crowd) | `tiers_test`, `tiers_map_test`: household mode unchanged |
| `Folk.decay_mult`, `Scenario.need_drain` (`folk.gd` 125-148, `scenario.gd`) | difficulty `need_mult` applies to all household members | pawn gets `Pawn.need_mult` (vital vs lifestyle); NPC family gets 1.0 | `start_difficulty_test` |
| `Economy`, `UtilityBills`, autopay | bills autopaid from household coins | keep autopay as a SETTING (a standing order), default on; explain in the tips; difficulty bill_mult as today | none |
| `Health*`, `HealthCollapse`, `Hospital`, `Fire*`, `ChaosGas`, `DisasterAftermath`, `LevelAccidents` | queue forced interactions on the folk | allowlisted with `origin` tags (7.1); `watch_fire`, `use_extinguisher`, the fleeing folk's brigade call, `HealthShelter` get `origin: "choice"` -> blocked for the pawn | `fire_*` tests are household tests |
| `Crowd`, `CrowdDrive`, `StoryVisits`, `SocialGatherings`, `NeighborhoodService` | NPCs enqueue chats/visits and sometimes enqueue on household folk (`social_gatherings` 33-42, 230-275 enqueue for attendees) | gatherings: invitations to the pawn become suggestions; NPCs chatting TO the pawn stay (the pawn is the target, no pawn queue involved) | `social_gatherings` host/attendee tests household |
| Crime and justice (`CrimePerson.is_player` = ANY resident of a household, 30+ files) | household folk are not dice perpetrators except... see 7.3 | audit the actor sites in 7.3 | 7.3 |
| `Commands`/`CommandActions` | any household folk can be ordered | guard + `ask`, `rule`, `go_to_work`, `go_to_school`; `AutoFurnish.note_order` stays | `commands_test`, `command_replay_test` |
| `CoopCommands`, `CoopTime`, `CoopHouseholds`, `CoopVisibility` | household-wide | pawn-wide (section 5) | `coop_*` tests household unless updated |
| `HUD`, `FolkPanel`, `PieMenu`, `QueueBar`, `UIU.enqueue`, Settings, StartPicker, `NewGame` | selection of any member; difficulty buttons | section 6; New Game option "How you play: One character (new) / The whole household (classic)"; settings: auto-skip, danger pause, routines level | `ui_*` shots re-run |
| Docs/help | "Folk look after themselves" tip | rewrite | text only |

### 7.3 The second class of leaks: dice incidents where the pawn is the ACTOR

The `Folk.enqueue` choke point does not see incidents that change state directly. I read the crime and social code. Most dice crime already excludes household folk as perpetrators (`CrimeFraud`, `CrimeBlackmail`, `CrimeLifeTownie` skip `CrimePerson.is_player`). Sites that still need an audit in stage 1 (list, not yet verified one by one): `CrimeForce`, `CrimeRevenge` (`CrimeAssault.fight` with a household folk as aggressor), `CrimeMurder` rage/"dangerous grudge" prompts (it already asks the player: `JusticePlayer.ask`), `CrimeDomestic.victim_reacts`, `SocialConflict` (arguments, cheating) when it runs outside an ordered interaction, the daily couple dice in `Conception`/`Pregnancy` (a pawn with a partner can get pregnant by dice without having ordered anything), `FamilyMarriage` proposals, `StorySingles._friend_moves_in` and `_adopt` (a stranger moves in or an orphan is taken in without the pawn saying yes). Rule I propose: the pawn may be the VICTIM or the TARGET of anything; the pawn is never the automatic ACTOR. Where the pawn would be an actor, the game asks with `JusticePlayer.ask` (a prompt, like the existing murder step-in) or the event picks an NPC. Expected size: 6 to 10 sites, mostly one-line guards or an ask. This is the largest unknown in the plan.

### 7.4 Tests

REVISED (task 36): superseded by R5 (counts redone; 80 real sim-driving test files, about 32 need edits, about 3 are deleted, a pawn hash baseline is added). The text below is the Revision 1 reasoning for a flag and no longer applies.

- Test-like files: 345 (334 `*_test.gd` plus `sim_*` and `world_*`). 117 of them drive the real clock, `SimDirector` or autonomy (grep for `tick_minute`, `HoodKit`, `advance_minutes`, `autonomy_enabled`, `Autonomy.choose`, `sim_testkit`); 25 use `HoodKit`, 29 the sim test kit, 52 call `advance_minutes`. These ASSUME an autonomous player household and must keep passing.
- With the mode default `household` in `Pawn` and in `TestFixture.reset()`/`SystemsManager.reset_all()`, none of them changes. Only 3 files call `NewGame.start` (`start_difficulty_test`, `start_scenarios_test`, `start_kit`) and about 45 shot/probe scripts call `start_new_game` (not in the tiers). So: expected edits to existing tests, 0 to 3 files (the New Game option row).
- Do NOT plan to run the 117 sim tests in `one` mode: they assert autonomous behaviour and would fail by design. Write dedicated tests instead (about 14 files, section 9). Add `tests/run_all.gd -- --control=one` only for that dedicated set.
- Hash baseline (`tests/baseline/coop_hash_3day.json`, `coop_hash_baseline_longrun_test`): unchanged in `household` mode; this is the proof that the old game is bit-identical. Add `tests/baseline/pawn_hash_3day.json` with its own test for `one` mode. `CoopHash.canonical()` is NOT extended (it would change the old baseline).
- Save: `SaveLoad.VERSION` stays 3. Old saves load as `household`. New block `pawn`, key into `data/share_schema.json`. `share_town_test` plus a new `pawn_save_test` (mid-rule, mid-ask, mid-skip, mid-danger).

---

## 8. Q8 - Difficulty ladder (Easy, Normal, Hard)

REVISED (task 36): the start rows (coins, rent, bed, wages, prices, odd jobs, notice) are replaced by R3; the storyteller, hospital, grace, estate and ask rows below stay. Normal is already difficult, so every number below that says "Normal" is the baseline for "just feasibly get by".

Existing: `data/scenarios.json` `difficulties` relaxed/normal/hard with `funds_mult` 1.5/1.0/0.7, `bill_mult` 0.8/1.0/1.3, `need_mult` 0.8/1.0/1.2, read by `Scenario`. Rename the label "Relaxed" to "Easy" (id stays so saves load). Storyteller personality (`data/storyteller.json`: calm, classic, chaotic) and the sliders already exist and become the ladder's defaults, still overridable ("Custom").

Proposed starting numbers (all data; tune with section 3.4 and with `storyteller_longrun_test` rates):

| Knob | Easy | Normal | Hard | Where |
|---|---|---|---|---|
| Starting coins x | 1.5 | 1.0 | 0.7 | exists (`funds_mult`) |
| Bills x | 0.8 | 1.0 | 1.3 | exists (`bill_mult`) |
| Wages x / shop prices x | 1.10 / 0.95 | 1.0 / 1.0 | 0.90 / 1.10 | new `Economy` hook, same style as `bill_mult` |
| Hospital and funeral costs x | 0.7 | 1.0 | 1.4 | new, data |
| Pawn vital needs x (hunger, energy, bladder) | 0.8 | 1.0 | 1.2 | `Pawn.need_mult` (the existing ladder, pawn only) |
| Pawn lifestyle needs x (social, fun, hygiene, comfort) | 0.7 | 0.85 | 1.0 | new |
| Starvation death clock (`death_min`, at the floor) | 6500 | 4320 | 3000 | `data/incidents/02_needs_health.json` `health.needs` |
| Town/ambulance help for a collapse (`town_help_min`) | 120 | 240 | 480 | same file `rescue` |
| Danger grace (fire) in game min / auto-pause | 2 / yes | 1 / yes | 0 / no | `data/control.json` |
| Warning detail | Info + Amber + Red | Amber + Red | Red + Danger only | `PawnWarn` |
| Storyteller personality | Calm | Classic | Chaotic | exists |
| Storyteller `pawn_focus` (share of household cards aimed at the pawn or their circle) | 0.5 | 0.65 | 0.8 | new key in `storyteller.json` |
| Budget gain (`gain_home`) x | 0.8 | 1.0 | 1.25 | `storyteller.json` `budget` |
| `max_quiet_days` / `big_gap_days` / mercy days | 10 / 21 / 9 | 5 / 7 / 5 | 3 / 0 / 0 | exists as personality values |
| `hard_mult` (rarity of deaths/disasters) and `crime_mult` | 0.8 / 0.85 | 1.0 / 1.0 | 1.3 / 1.3 (capped at `hard_cap` 1.5) | exists; the hard rules (no murder/serial/child-abuse/disaster cards) stay for every difficulty |
| Injury and illness severity shift | -1 step on random roll | 0 | +0 and no softening on the first roll | `Health` severity roll, data |
| Estate on death (what the heir keeps) | 100 percent | 90 percent | 75 percent | new, `Succession`/`Economy` at death |
| Ask success bonus | +0.10 | 0 | -0.10 | `RequestOdds` |

"The world grows" - how, concretely, using what already exists: a hidden FOOTPRINT score of the pawn's reach (days played, generation count, jobs held, friends, wealth, lots visited), read by the storyteller. It does three things: (1) `StorytellerBudget` gain scales with footprint, so a day-1 pawn gets a gentle town and a successful pawn gets more happening; (2) medium and big cards and arcs unlock above footprint thresholds (data on each card: `min_footprint`); (3) `CityPlan` (it already starts city projects at `fill_trigger` 0.9 population fill) gets a second trigger from footprint so new lots, townies and jobs appear as the pawn's circle grows. The pawn's circle = townies and households with friendship at or above a threshold or family ties to the pawn: they get a budget multiplier (the "know" ripple in `StorytellerRipple` already pulls cards to people the household knows) and `Story` visits/invitations come from them first.

---

## 9. Stage plan, deliverables, tests, estimate and risks

REVISED (task 36): SUPERSEDED by R4 (no flag, new start work, about 20.5 sessions). Kept for history; stage names differ.

One agent-session = a focused work block like the recent tasks (design in hand, tests, report). Estimates include tests and the fast tier staying near its current time.

| Stage | Deliverable | Tests (new, fast tier unless noted) | Sessions | Risks |
|---|---|---|---|---|
| S0 Foundations | `Pawn` mode flag (saved in `Scenario`), `Players.pawn`, New Game option (hidden behind a dev switch), `Folk.enqueue` choke with counters but NOT blocking yet, `origin` tags in data for the reflex set | `pawn_mode_test`, `pawn_save_test`, hash baseline unchanged | 1 | Low |
| S1 Silence the pawn | Gates in `_fill`, `DynLife`, `PlaceAuto*`, `BabyCare`, `Commute`/`CareerShifts`/`SkipRules`, `AutoFurnish`, `Homemaker`; choke point now blocks; dice-incident audit (7.3) and fixes | `pawn_leak_test` (14 game days, 3 seeds, every `interaction_started` of the pawn is player-origin or allowlisted), `pawn_alone_test` (the section 1.1 table as assertions), `pawn_commute_test` | 2 | Hidden enqueue paths; the dice audit may find more than 10 sites; interaction `tests` that block orders (e.g. `sleep_ok`) |
| S2 Warnings, danger, agenda | `PawnWarn`, need timelines, danger pause + grace + reflexes, shift reminders, `go_to_work`/`go_to_school` commands, missed-shift path, baby/kid alerts | `pawn_warn_test`, `pawn_reflex_fire_test` (fire, smoke alarm, gas, disaster), `pawn_shift_test` | 2 | UI work; making warnings useful, not noisy; co-op without pause |
| S3 Routines | rules data model, engine, command, UI panel, "save as routine", determinism and replay | `pawn_rules_test`, `pawn_rules_replay_test`, `pawn_rules_cap_test` | 2 (parallel with S4) | Scope creep (every playtester asks for "else" and "if"); UI size |
| S4 Household requests + strip | `Requests`, odds, data, Ask menu, pending/later, NPC suggestions, household strip, inspect-only selection, guard in `_interact` | `pawn_ask_test` (odds table, determinism, relations), `pawn_guard_test`, `pawn_suggest_test` | 2 (parallel with S3) | Tuning odds so asking is useful but not a cheat; kids/elders cases; NPC busy states |
| S5 Time | solo `TimeFlow` auto-skip with frame budget, stops, banner; pawn need mult (vital/lifestyle); co-op `passive` = pawn, AFK hold; measurement | `pawn_skip_test`, `pawn_afk_test`, `coop_pawn_skip_run_test` (slow-ish), perf probe added to `docs/PERFORMANCE.md` | 2 | Skip speed on the big map may be only 15-20 min/s; skipping must stop correctly on every alert |
| S6 Storyteller + ladder + growth | pawn focus, circle, footprint, difficulty table in data, severity/clock/estate hooks, `StorySingles`/visits aimed at the pawn | `pawn_storyteller_test`, `pawn_difficulty_test`, slow `pawn_storyteller_longrun_test` (events per pawn-week by difficulty) | 1.5 | Rates feel wrong until played; `storyteller_*` long runs must still pass in household mode |
| S7 Heir + camera + polish | `Pawn.on_head_changed`, heir dialog, playable-heir rule (no babies/toddlers), copy routines, death card + pause, Tiers anchors, camera follow, tips/help text, settings | `pawn_heir_test`, `pawn_tiers_test`, windowed shots of strip, routines, ask, banner, heir | 1.5 | Many small UI pieces; text/tone review |
| S8 Balance + playtest | `pawn_bot` driver, tuning passes per difficulty, "leave alone" table in docs, owner playtest, default-mode decision, docs (`ARCHITECTURE.md`, this file) | `pawn_bot_longrun_test` (slow): section 3.4 targets as asserts | 1.5 | Numbers are guesses until here; the owner may want a different feel |
| Total | | about 14 new test files | about 14 (range 11-18) | |

Order and parallelism: S0 -> S1 -> (S2) -> (S3 and S4 in parallel) -> (S5 and S6 in parallel) -> S7 -> S8. Serial length about 9 sessions with two pairs parallel. The game stays playable and unchanged for `household` mode after every stage, because nothing in `one` mode is on by default until S8.

---

## 10. One feature flag: keep the old game alive?

REVISED (task 36): NO. The owner decided that one-character play is the game, not a mode. There is no `Pawn.mode`, no Classic game and no New Game choice. The reasons Revision 1 gave for a flag (existing tests untouched, players who like the old game keep it, ship as an option first) are answered differently: tests by the no-pawn-without-a-player rule (R1, R5), and the old household game is simply dropped (R6). Revision 1 text deleted to keep the file readable; the git history has it.

---

## 11. Recommendation

REVISED (task 36): build it as THE game, in the order of R4, with the start economy of R2. The Revision 1 recommendation below said "as a mode, decide the default after S8"; read it without those words.

Build it, in the order of R4.

- Do: one pawn, hard "no autonomy" with the `Folk.enqueue` choke plus a data allowlist; keep today's body/world consequences (collapse, pass-out, accidents, ambulance, hospital, jail) as the safety net; fire/disaster flee with a pause and a grace window; literal routines (cap 8); asking family with explainable odds; solo auto time skip; difficulty ladder as in section 8; the household as real NPCs.
- Do not: add any "default behaviour" for the pawn (no auto-eat, no auto-bed, no auto-work, no idle fillers). If the player does not want to micromanage, routines are the answer.
- Biggest value per effort: S1 (silence + leak test) and S5 (time skip). Biggest risk to the vision: the first hour of play if warnings and the skip are poor. Do S2 and S5 properly before showing it to anyone.
- Honest unknowns: (a) skip speed on the big map with crowds (could be 15-20 min/s); (b) the number of dice-incident leaks (6 to 10 expected); (c) how pets are handled (`PlaceAutoNow` checks pets hourly; whether pets are folk with their own autonomy is not verified); (d) whether Easy/Normal/Hard feel different enough at the numbers in section 8 (they are starting points); (e) income with a single earner when the pawn is the only adult of a family (the Solo Start scenario exists, so a solo pawn is already a tuned case; family pawns less so); (f) how the AFK hold interacts with timed events such as a shift (it should simply suspend the pawn's clock-bound obligations too).

---

## 12. Open questions for the owner

REVISED (task 36): the reviewer answered these as defaults (`coord/messages/2026-10-22T1645-reviewer-36-owner-one-mode.md`, point 7). My view of each default is in R7; question 10 (default for new games) is moot; what is still open is R9.

1. Routines (section 2): are literal player-written routines inside your "no autonomy" rule? If you want them restricted, which level: Off, Time-based only, or Full (my default)?
2. Danger reflex: if the player does not react, should the pawn still run out of a fire after the grace window (my proposal), or should the game only pause and warn and let the pawn burn if ignored?
3. Bills autopay and the NPC family doing chores for the home: are these acceptable "world" behaviour (my assumption), given the pawn does nothing by itself?
4. Homemaker: should the pawn be able to be one (just means no job), without the free daily cleaning bonus? Or is the role NPC-only?
5. Should the pawn be able to get pregnant, marry or move a stranger in by dice (current daily dice), or only after an explicit player order or an accepted prompt (my proposal)?
6. Co-op: when a player goes idle, freeze their pawn safe (my proposal, "AFK hold"), or let the idle player block the others' skip?
7. When the pawn dies and nobody can play (only babies/toddlers, or nobody), should that be game over with a recap, or the existing "nobody left" choice (relative, townie, new family)?
8. Death difficulty: should Hard allow a real starvation death (my numbers say yes after about 5 days at the floor), and should Easy keep the heir's full inheritance?
9. Household strip: should the player see the NPC family members' exact need bars, or only mood and activity (my proposal), to keep the focus on the pawn?
10. Default for NEW games after the playtest: One character, with Classic as an option (my proposal)?
11. Pets: should a pet autonomously look after itself (my assumption) and should the pawn have to order vet trips?
12. Should NPC advances toward the pawn (flirt, argue) just happen to the pawn (today), or ask the player to respond (accept/decline prompt)? Today they just happen.

---

## Appendix A - Where the measurements came from

- "Leave alone" probe: hood kit, seed 4242, `HoodKit.new_game("classic", 4242, 4242)`, folk Mira/Tobin/Wren (traits neat/active/social), start 07:00 day 1; Mira (run 1) and all three (run 2) had `idle_until_min` held at a huge value so `_fill` never called `Autonomy.choose`. Run 1: 4 days. Run 2: 8 days. Both through `tools/godot_guard.ps1`. Headless, no views. About 8 ms per game minute. The probe is not committed (design task: one file only).
- Need maths: `data/needs.json` decay per minute x 1440; restores from `data/interactions.json`.
- Counts: grep of `tests/*.gd` (see 7.4); `Interaction.create`/`enqueue` sites in `scripts/` (see 7.1).
- Time costs: `docs/PERFORMANCE.md` (budgets 20 ms per game minute; 22 ms today; big town about 38 ms), `scripts/net/coop_time.gd` (SKIP_RATE 45, COOP_MAX_PER_FRAME 6), `scripts/core/clock.gd` (MIN_PER_SEC 0/1/4/12).

- Revision 2 probe (task 36): `NewGame.start` through `tests/start_kit.gd` (solo, `home_state: empty`, world seed 4242), then 14 game days with `SimDirector.autonomy_enabled = false`, sampled daily. Printed: starting coins 5,500; owned objects (2 doors, 10 windows, 3 pendant lights, a mailbox); `Economy.compute_bill` 128 (power 38, water 32, internet 26, rates 32); home property value 16,930 and market rent 203; object prices; need start values and daily decay; coins fell to 3,600 on day 2 (`AutoFurnish`, 1,900). Not committed (design task). Weekly-budget and bot timelines in R2.5 are Python arithmetic, not game runs.

## Appendix B - Files read for this design

Revision 2 added: `docs/ECONOMY.md`, `scripts/systems/` (`new_game`, `scenario`, `start_home`, `home_bare`, `household_setup`, `auto_furnish`, `economy`, `utility_bills`, `housing_props`, `housing_rent`, `housing_agent`, `player_lots`, `careers`, `job_seeking`, `opportunity_taker`, `edu_jobs`, `career_progress`, `hospital`), `scripts/ui/` (`start_picker`, `household_creator`, `life_hub_jobs`, `interaction_query`), `scripts/sim/autonomy.gd` (`_folk_self_defs`), `data/` (`scenarios`, `start_home`, `economy`, `housing`, `bank`, `careers`, `objects`, `interactions`, `life/30_food`, `life/40_culture`, `life/50_media`, `incidents`, `incidents/07b_chaos_more`, `incidents/13_economy`, `city`), `tests/` (`fixture`, `hood_kit`, `start_kit`, hash baseline files, grep counts).

Revision 1: `CLAUDE.md`, `ARCHITECTURE.md`, `docs/INCIDENT_AGENT_BRIEF.md`, `docs/PERFORMANCE.md`, `docs/COOP.md`, the owner message; `scripts/sim/` (`director`, `autonomy`, `circadian`, `folk`, `interaction`, `commands`, `command_actions`, `tiers`); `scripts/systems/` (`players`, `succession`, `heir_line`, `dyn_life`, `dyn_plans`, `dyn_react`, `dyn_social`, `place_auto`, `baby_care`, `auto_furnish`, `homemaker`, `commute`, `career_shifts`, `skip_rules`, `story_pacing`, `story_singles`, `straying`, `storyteller*`, `health_collapse`, `fire_folk`, `scenario`, crime files for `is_player`); `scripts/net/` (`coop_time`, `coop_commands`); `scripts/ui/hud.gd`; `data/needs.json`, `data/scenarios.json`, `data/storyteller.json`, `data/storyteller_cards.json`, `data/incidents/02_needs_health.json`, `data/interactions.json`.

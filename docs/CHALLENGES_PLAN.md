# Real challenges for the one character (owner task 39, with the "emergent, not forced" amendment)

Status: DESIGN ONLY. No game code was changed. Sources: `coord/messages/2026-10-22T1915-reviewer-39-real-challenges.md` (seven asks), `...T1930-reviewer-39-amend-emergent.md` (the amendment), `...T1900-reviewer-spicy-zack-life.md` (the evidence), `docs/ONE_CHARACTER_PLAN.md` (the 36 plan, stages S0-S9, numbers in R2/R3), `docs/INCIDENT_AGENT_BRIEF.md` (the cause-and-logic rule), and a read of the real code. Owner quote: "That wasn't spicy enough, no real challenges happened."

Every item below has a cause line in the 34 form: "X happens because Y; it gets worse only if Z."

---

## 0. The short version

1. The spice went into frequency in the town, not into stakes for the player. I measured it (section 1) and then read why a hit never hurts (section 1.2): money can't go negative, nothing is owed for long, jobs have no review, arcs are timed scripts whose default answer is the kind one, and nothing is remembered.
2. The fix is NOT a bigger dial and NOT a director. Per the amendment, there is no "make sure the player is nearly ruined". The fix is **more things in motion that follow their own causes and can collide**: about ten small "threads" (rent arrears, a debt, a job review, a feud, a friend's trouble, a partner's strain, ...). Each one has a hidden meter, a growth rule written as a cause, decisions with prices, and an end that is written down.
3. The storyteller's only new job is **planting seeds in the player's own life** (`pawn_focus`, a personal budget, a personal quiet-day guard: only MORE SEEDS in the player's circle, never aimed at an outcome) so the player is not mostly watching the town. It never reads the player's coins to choose a card (section 2.3 removes the `wealth` tilts for the pawn).
4. Built mostly from what exists: `StorytellerArcs` (grown into meter-driven threads), `StorytellerChoice` (options get prices and an "ignore" outcome), `StorytellerFx` (a few new verbs), `Economy` bills and `HousingRent` (36), `CrimeUnderRacket` (the loan shark already lends and collects), `Careers` performance, `Hospital`, `Justice*`, `Straying`, `JusticeOrders`, `BankAccounts`, `bank_insurance`.
5. New code: a thread engine and a "what's going on" ledger (about 4 sessions), pressure on money and work (2.5), people threads (3), things that stay broken/gone (2), difficulty stakes plus the measurement (2). About **13 agent-sessions** (range 10 to 16). It goes after S2 and S3 of the 36 plan (section 9).
6. Measurement is observation, not quotas (section 8): `pawn_bot` on Normal and Hard, 5 seeds x 60 days, printing threads in motion, threads that grew, lowest coins as a share of a week's costs and near-loss days. The asserts are only: threads exist and progress by their own rules; ignoring everything has visible consequences (the home is lost by about week 3); a careful bot usually copes; and a "steer-free" test proving a card pick does not change when the player's coins change.

---

## 1. What is wrong today (read and measured)

### 1.1 Measurement: how much of the storyteller reaches the player's household

Probe (a throwaway test, deleted; storyteller only, no hourly incident dice): the stub town with one player household "h1", 5 seeds x 60 game days (40 player-weeks), counting what `StorytellerLog` records. "Personal" = scope home and h1 is in the entry (own cards and arc stages). "Mid/big" = medium or big card, or any arc stage.

| Setting | Personal entries | per week | Personal and bad | Mid/big personal | Weeks with no mid/big (of 40) | Longest gap between personal entries | Entries elsewhere (town) |
|---|---|---|---|---|---|---|---|
| Classic | 52 | 1.3 | 17 (0.4/wk) | 18 | 23 | 19 days | 232 |
| Chaotic | 99 | 2.5 | 22 (0.55/wk) | 62 | 7 | 17 days | 236 |
| Custom max (freq 1, sev 1, balance 0.3, mercy 0) | 107 | 2.7 | 29 (0.7/wk) | 51 | 9 | 11 days | 275 |

What this says:
- About 70 to 80 percent of everything the storyteller plays happens elsewhere (district, townie lots, town). The owner's count (3 bad toasts for Zack out of 16 town-wide) matches.
- Even on the maximum, only 0.7 bad personal cards a week, and most of those are small (a cold, pests, an appliance).
- The "max quiet days" guard (Chaotic 3) does not give the player a hit at least every 3 days: it counts anything that touched the household, including a ripple from a district card (`StorytellerBudget.guard` sends 60 percent of guards to the district, `guard_city_share`). The longest personal gap was 17 days on Chaotic.
- Caveat: arc stages are counted once per stage line; natural incident dice (not in this probe) add more. The shape holds.

### 1.2 Why a hit never becomes a challenge (code read)

| Gap | Where | What it does today |
|---|---|---|
| Money cannot go negative | `Economy.spend` returns false; `StorytellerFx._coins` spends `min(n, balance)`; burglary takes 15 percent (20 to 300); identity theft is capped at 600 | A hit is absorbed by the balance. There is no debt, so nothing "comes due". |
| Unpaid bills end in a quiet shrug | `Economy.on_day`: late fee 10 percent (min 10), repossess ONE item after 3 missed cycles; `Hospital.charge` turns an unpaid bill into an ordinary bill | Slow, small, and with autopay (36 turns it on) invisible. |
| Rent is a stub | `HousingRent._bill`: a toast on the second late rent. `ChaosMoney.eviction` takes up to 3 things. Nothing ends the tenancy (36 R2.1) | "Eviction" never actually evicts. |
| Jobs have no review | `Careers`/`CareerProgress`: a 0 to 100 performance meter, a skip costs 15 (sick 4), only 0 at level 1 fires | The meter exists, but nobody reads it as a threat. No warning, no probation, no rival. Layoffs pay 40 hours of severance (`ChaosJob.layoff`). |
| Arcs are timed scripts | `StorytellerArcs`: each stage is `after: [min, max]` days; the climax choice is auto-resolved after `choice_days` 3 with `default`, and every default is the soft option (`talk`, `police`, `listen`, `pass`) | Time, not cause, moves them. Ignoring them is free. They end with a line like "over, one way or another". |
| Choices have no price and no memory | `StorytellerChoice`: options are fixed `fx` lists with no `cost`, no `needs`, no "you can't afford this"; the only record is the 120-line log | The outcome is a toast. Nothing is remembered. |
| The family secret ends in a toast | `family_secret` stage 3: friendship +20, a buff, 0 to 150 coins; the "other" person is a generated stranger who just stays a townie | Nothing real changes: no sibling, no debt, no inheritance, no condition. |
| Wealth tilts the deck | `weight_of` multiplies by `wealth` per card (rich: burglary x2.5, audit x4, gold-digger x4; poor: eviction scare x4) | This is the "knock back the player who is doing well" the amendment forbids, and it vanishes once poor is the starting state. |
| Reputation is a number nobody reads | `RelationshipService.reputation_map` (-100 to 100) feeds evidence weights and guest theft, crime-under rep | No greeting, job-offer or landlord/lender effect. `refused_service` is a query with no shop hook (ARCHITECTURE, task 23). |
| Autonomy hides it all | Everything is eaten, slept, repaired, paid by itself today | 36 removes this; the pawn must act. This is what finally makes stakes real. |

What already works and only needs aiming: burglary removes real objects (`CrimeBurglary._take`, recoverable by `recover`), fines become bills, jail ends the job (`Careers.quit_job(f, "jailed")`), community service holds the folk 240 minutes a day, injuries and illness block work (`Health.work_block`, 4 to 15 performance), hospital bills 60/220/700, the bank has loans with a credit score (2 per household), the racket system lends and collects with escalating visits (`CrimeUnderRacket.lend/collect`), a restraining-order machinery exists (`JusticeOrders`), home and health insurance exist with weekly premiums (`bank_insurance`, `DisasterInsurance`).

---

## 2. Principles (the amendment turned into rules)

**P1. Threads, not quotas.** A thread is a small story that follows its own cause: it starts small, has one or two meters, grows only when its cause is true, and fades when the cause stops. No target is "close to losing your home twice in 60 days". If it happens, it happened because several threads overlapped.

**P2. The storyteller plants seeds; the threads do the rest.** The only things the storyteller decides are *that* a seed starts in the pawn's life and *which* one, by the usual weights. It never looks at the pawn's coins, rent state or health to pick (2.3).

**P3. Every step has a cause line, a price and a record.** A step is a threshold crossed on a meter (not a timer), it asks the player something with prices on the options, and the answer (or the silence) is written into the ledger (3.4).

**P4. Ignoring is a choice and is priced.** An open decision has a deadline (2 to 5 days by weight). When it expires the card's own `ignore` outcome applies, never a free `default`. The text says "You did not answer: ..." and the ledger line is red.

**P5. Mercy and balance still choose tone only.** The `mercy` slider and the Custom `balance` change the good/bad mix of cards as today. They do not aim at an outcome and are not looked up from the pawn's finances.

**P6. Hard rarity rules stay.** Murder, serial killer, child abuse, disaster cards keep `hard_mult` capped at 1.5 and are not threads. No trafficking, no sexual content. "Mature life events" off removes the infidelity and triangle flavours. Violence stops at a scuffle and a bruise, shown as a notification, never a scene.

**P7. Honest logic.** A thread may only use facts that exist in the sim: an unpaid bill, a performance number, a recorded incident, a relationship value, a trait. If the fact isn't tracked yet it is listed under "new code".

### 2.1 What the storyteller changes (task point 1)

All data keys in `data/storyteller.json`; code in `StorytellerBudget`, `StorytellerPlay`, `StorytellerDeck`.

| Change | How | Cause line |
|---|---|---|
| `pawn_focus` (0.5 Easy / 0.65 Normal / 0.8 Hard, the 35 values) | The pawn's household key gets `gain_home x (1 + 2 x focus)` (about x2.3 on Normal); when a card is "about a person in the household" the pawn is picked first (with others in the house, with probability `focus`); ripple "know" and "near" effects and `StoryVisits` go to the pawn's circle first | "More happens in your life than in a stranger's because the town's attention follows the character you play; it is only more *seeds*, not heavier hits." |
| Personal quiet-day guard | `max_quiet_days` (Chaotic and Custom-max 3, Classic 5, Calm 10) counts only things that touched the pawn: an own card, a thread step, a "know" ripple, a natural incident of severity 2 or more. `guard_city_share` is 0 for the pawn: the guard plays a small card on the pawn | "Something small turns up after 3 quiet days on Chaotic because the dial is set to 'anything, any time'; it is a small card, chosen by the normal weights." |
| Weekly medium floor | REMOVED after the owner amendment: nothing raises a seed's size because a week was quiet. `pawn_focus` and the guard only change how MANY seeds start in the pawn's life and circle, never what they do to the pawn | "More threads start in your life because the town's attention follows the character you play." |
| Foreshadowing stays | Medium and big bad personal seeds still post a sign ("the landlord has been asking about the rent") 1 to 3 days ahead | Existing. |

Expected result (observed, not asserted except the 3-day rule): Chaotic and Custom-max have a personal thing at least every 3 days. Medium-or-big activity per week is whatever the open threads produce when they overlap; there is no weekly quota.

### 2.2 Where threads come from (seeds)

Seeds are normal deck cards (`storyteller_cards.json`, `arc` entries) with a cause check in `when`, so they only come up when the cause exists:
- **Money:** a bill unpaid past its due day starts `rent_arrears`; a refused loan with arrears open can start `shark_offer`; a hospital discharge the pawn can't pay starts `medical_debt`.
- **Work:** a performance under 35, or two skipped shifts in 14 days, starts `job_review`; a coworker in the same career and a promotion or praise starts `work_rival`; the economy phase is "recession" or a layoff rumour card starts `layoff_watch`.
- **People:** a neighbour's grudge (`feud`) from a noisy night, an insult or a pet problem; a partner whose strain meter rises (money fights, long hours); a friend with a real money or housing problem; an admirer after an unanswered romantic approach; a stranger with old letters (`family_secret`).
- **Law:** a case near the pawn where the soft-evidence score points at the pawn (`suspect`).

### 2.3 What is removed so nothing is steered

- For the pawn household, the card `wealth` multipliers are ignored (set to 1.0 in `weight_of` when `Pawn.is_pawn_household`). Rich-only cards (`gold_digger`, `audit`) get cause conditions instead: `audit` needs dirty income (`CrimeUnderRacket.taint` high); `burglary_card` weight follows *visible valuables and missing locks* (`CrimeSecurity.effects`, the best object price) and district crime heat, not the balance.
- `eviction_scare` is removed for the pawn: eviction is the real rent ladder (4.1).
- Good-luck cards (windfall, headhunter, found money) also stop reading poverty for the pawn. Good news arrives by the `balance`/`mercy` sliders only. Owner question Q5.
- A new test (section 8.3) proves it: the same seed with 50 coins and with 5,000 coins plays the same card sequence until a thread's own cause differs.

---

## 3. The thread engine (the main new code)

### 3.1 Records and data

`StorytellerArcs` today: one record per slot (`h<id>`), a stage index and a timer. Change it into **threads** (same class family, same data file, same log):

| Piece | Today | Becomes |
|---|---|---|
| Slots | one arc per household, one town arc | one thread per *kind* per household (max 8 open for the pawn, a UI limit; town arcs unchanged) |
| Record | `{arc, stage, due, other, folk_id, hid, zone, lot, who}` | add `meters: {name: value}`, `level` (0 to 4), `facts: {}` (amounts owed, ids of stolen objects, deadline day), `log: []` |
| Stage trigger | `after: [min, max]` days | add `when: {meter, gte}` or `{event: "bill_late"}`; `after` stays as a minimum gap so two steps never land on one day |
| Meters | none | data `meters: {grudge: {start: 1, max: 6, decay_day: 0.3}}`; `gain` rules `{on: "insult", target_is_other: true, add: 1}` read the existing `SysUtil.game_event` stream (`bill_late`, `skipped_work`, `missed_shift`, `public_disturbance`, `burglary`, `hospital admitted`, `evicted`, `loan_default`, ...) |
| Options | `{id, label, fx, text}` | add `cost: {coins, work_hours, rep}`, `needs: {coins_min, friend_min, rep_min, item, line}`, `risk: {roll, then, else}`, `ignore: true` (exactly one per ask), `remember: "text for the ledger"` |
| End | a stage with `end: true` | a stage with `end: true` or a meter at 0 for `cool_days` ("it faded"); every end writes a ledger line |
| Delay of a reply | `choice_days` 3, `default` | per ask `wait_days` (2 to 5); expiry applies the `ignore` option |

New `StorytellerFx` verbs (data only): `meter {name, add}`, `bill {amount, reason, due_in}` (an ordinary `Economy` bill), `debt {to, amount, rate}`, `take_object {pick: "best|random|named"}` (the existing repossess/burglary removal), `lock_out`, `performance n`, `warning`/`probation`, `injure {sev}`, `damage_room`, `ledger text`, `rep n` (exists), `refuse_service`. Each goes through an existing system (Economy, Careers, Health, Hospital, CrimeSecurity), like the current verbs.

Files (small, <~400 lines each, no god file): `storyteller_threads.gd` (state, daily pass, meters), `storyteller_thread_rules.gd` (when/gain conditions), `storyteller_ledger.gd` (the book), `storyteller_options.gd` (price/needs/ignore on `StorytellerChoice`), data `storyteller_threads.json` (one file per cluster if it grows: money, work, people, law).

### 3.2 The daily pass (cost)

One pass per day over the pawn's open threads only (<= 8), plus event-driven meter gains (O(1) each). No per-minute work. Town arcs are unchanged. Save: nested in `Incidents.to_dict()["storyteller"]` (ledger and threads), so `data/share_schema.json` is untouched, as the Storyteller already does.

### 3.3 Decisions (task point 5)

Every ask shows, for each option: label, price, and why it's greyed out ("You only have 40 coins", "Nobody you know can lend this"). Ways out available to many threads, each with a cost: **pay** (coins), **fight** (rep/health/legal risk), **hide** (lie low: lose time or a night's rest), **ask for help** (a friend, the hall relief fund, a lawyer: spends a favour or friendship), **cut corners / go outside the law** (21/23: a loan shark, selling things to a fence, working cash in hand; each can raise a charge, heat or taint). Through the existing command layer (`storyteller {action: choose}`) so replay and co-op work.

### 3.4 The ledger ("what's going on")

A saved list (cap 40) of `{day, thread, kind: seed|grew|asked|chose|ignored|ended, text, cost, cause}` and one panel (tab in the Town or phone panel; extends `StorytellerLogPanel`): "Open" (each thread's plain status, e.g. "Rent: 1 week behind (70 + 10 fee). The landlord's notice comes if the next one is also missed."), and "History" (what you chose, what it cost, what happened). The panel states the *rule* ("a notice follows a second missed rent") but never the hidden dice. This is the "outcome shown and remembered" part. It also feeds the chronicle for severity 2 or more.

---

## 4. Pressure on the 36 economy (task point 2)

Numbers from 36 R2/R3: Normal rent 70/week, bills about 60, street food 120, a week's costs about 250; start 300.

### 4.1 Rent ladder (a thread, `rent_arrears`)

36 R2.2 already gives the endpoints (notice after 2 missed, bailiffs 3 days later, lock-out). This plan fills the steps between and makes each a decision.

| Step | Trigger (cause) | What the player sees | Choices (cost) |
|---|---|---|---|
| Reminder | Rent bill due tomorrow (calendar) | Amber warning from `PawnWarn` | pay now |
| Missed rent #1 | Bill unpaid 3 days after issue (`bill_late`, exists) | Late fee +10 percent (min 10) added; letter from the landlord; thread opens, meter `arrears` 1 | Pay all (rent+fee); pay half and promise (fee +10 more, only with 2 on-time payments or rep >= 10); ask for time (once per 8 weeks, odds from the landlord's friendship, your rep and record; failure brings the notice a week earlier); borrow (4.2); ignore (letter stays) |
| Missed rent #2 | Next bill also unpaid (`missed >= evict_after_missed`: Easy 3 / Normal 2 / Hard 1) | EVICTION NOTICE, a deadline (3 days, shown) | Pay arrears + fees; borrow; ask a friend for the couch (a favour, 4.3); ask the hall relief fund (Easy 60 coins once a month, Normal 40 once, Hard none); leave on your own terms (keep your things: sell objects; find a place later) |
| Deadline | Still unpaid when the 3 days end | Bailiffs take up to 3 things (`ChaosMoney.eviction`, exists), the lease ends, door locked | Aftermath: sign again by paying arrears plus a week's deposit; sleep rough (floor sleeping with a cold penalty); Easy: shelter cot (36 S9, until then a friend's couch ask) |
| Cleared | Arrears paid at any point | Thread ends; rep slightly up ("paid up"); the "good tenant" counter resets only after 4 on-time weeks | |

Cause line: "Rent is late because the bill was not paid by its due day; a notice comes only after a second missed rent; the home is lost only if the notice's deadline passes unpaid. Paying at any step stops it."
Autopay: on by default (36); paying fails when the balance is short, which is how a poor week turns into `missed rent #1` with no one to blame.
Do-nothing check from 36 R2.5: first late rent day 11, second day 18, deadline day 21, i.e. about week 3.

### 4.2 Debt, and the loan shark as a choice

There is no negative balance in `Economy` and this plan keeps it that way: debt is a **book of loans** (`BankAccounts.loans` already does this) plus personal and shark debts as ledger-backed bills.

| Source | Offered when | Terms | If unpaid |
|---|---|---|---|
| Bank loan | Credit score allows (`loan_limit`); poor pawns are often refused: "The bank will lend you up to 0" | exists: min 200, rate by score, weekly payment | `loan_default`, credit score drops (exists) |
| Friend | A friend with friendship >= 40 and coins | up to 80 to 150; no interest; becomes a **favour owed** (4.3) | friendship falls, favour lost |
| Hall relief fund (Easy, Normal once) | Notice served | a grant, not a loan | none |
| Loan shark (`shark_offer` thread) | Arrears thread open AND the bank said no. Normal: only after the notice (cause: desperate). Hard: from the first missed rent. Needs a townie with the racket line (`CrimeUnderLines.has(pid, "racket")`); if the town has none, no offer (cause) | `CrimeUnderRacket.lend` as is: 60 to 300 coins, 25 percent, due in 7 days | collection visits every 2 days (`collect`, exists) |

Shark escalation, driven by the real `r["visits"]` and `r["missed"]` of the racket record, not by the storyteller: visit 1 a note and -6 friendship; visit 2 an ask "pay or else" (pay in full; pay the interest only and extend a week, costing 25 percent again; lie low at a friend's, with a friendship cost; tell the police, which files `loan_sharking` against the lender and removes the debt's teeth but can raise `hunted`); visit 3: on Normal a stern warning and the interest doubles; on **Hard** a named object is taken as "collateral" (the same removal as repossession) and a scuffle leaves a bruise (injury severity 1, non-graphic). It ends on payment, on seizure, or when the lender is arrested.
Cause line: "A lender lends because you were desperate and the bank refused; visits come because the due day passed; they stop when it is paid or something is taken to settle it; Easy never offers it."
New code: a player *debtor* path in `CrimeUnderRacket` (today `lend` only picks townie debtors and `collect` only pays from `CrimePerson.coins`, which already works for a player id); the offer card and ask.

### 4.3 Favours and money owed between people

A friend you lend to becomes a **favour owed**: stored in the ledger `{who, kind: money|couch, amount}`. A friend you helped can help you later (the ask "can you spare the rent?" succeeds more easily and costs less friendship); a friend you refused has -10 friendship and won't. A friend who owes you money repays by their traits (`honest` pays back; `dishonest` mostly doesn't). Debts and favours "come due" by dates in the ledger, so they collide with rent weeks by chance.

### 4.4 The job at risk

| Thread | Trigger (cause) | Growth | Choices | End |
|---|---|---|---|---|
| `job_review` | Weekly check at a job: `performance < 35`, or two skipped or sick shifts in 14 days | Level 1 written warning (ledger). A second weak weekly check, or one more skip during the warning: **probation** 14 days (a skipped shift while on probation = fired through `Careers.fire`). | "Ask what to improve" (an unpaid hour; +5); extra shift (+8, tired); call in sick honestly vs struggle in (see 4.5); blame someone (costs rep); look for another job now | Probation passed at `performance >= 50`, or fired |
| `work_rival` | A coworker in the same workplace lot and career (the Workplace system lists coworkers); the pawn is promoted or praised (`promoted` event, performance >= 70) or a promotion slot opens | Meter `resent` on the rival grows with the pawn's wins and falls when friendship with the pawn is >= 30; at `resent >= 3` and friendship < -20 the rival "tells the boss" (`performance -10`, a ledger line) | Speak up (needs `performance >= 60`); befriend (a coffee, 15 coins; lowers `resent`); work harder; confront (rep risk) | The rival is promoted, leaves, becomes a friend, or you change jobs |
| `layoff_watch` | Economy phase "recession" (`cycle_bust`), a factory closure card (`factory_closure` -> `factory_layoffs` chain, exist), or a layoff rumour card; weight is higher for level 1 and short tenure | Existing `layoff` incident with its one-day sign; `performance` and seniority protect (exists) | On the sign: look for a job now, work extra (performance up lowers the risk), keep your head down | Laid off (severance 40 hours, exists), or the rumour passes |
| Business closing | `ChaosJob` closure (exists) and the Works closures (task 31) | as today | the job board | |

Cause lines: "A warning comes because your performance meter fell, which happens when you skip, are unwell or in a bad mood (`shift_gain` already sums these); probation ends the job only if you miss another shift; a rival acts only after you win something and stay unfriendly."
New code: the weekly review (a small hook in `Careers.on_day`), warning/probation flags on `Careers.jobs[fid]`, the `work_rival` meters. Wages stay as they are.
Soft landings: Easy gets 14 days of a small town job-seeker payment (20 a day) after a layoff (owner question Q6); Normal and Hard get severance only.

### 4.5 Injury or illness that stops work while bills keep coming

Already true: `Health.work_block` stops work and `_record_skip` charges 4 performance for a sick day and no pay; the weekly bill and rent keep coming. What's missing is the *decision*: at shift start, an unwell or injured pawn is asked **"Call in sick (no pay, -4 performance, no risk) / Go in anyway (full pay, but the injury heals slower through `Worsening.strain_extra`, and flu can pass to a coworker friend)"**. A hospital stay (60/220/700) turns into a `medical_debt` ask on discharge: pay now; four weekly instalments at +10 percent; the hall's charity care (Easy -50 percent automatically; Normal once, asked; Hard none); health cover bought earlier (`bank_insurance`, 80 percent) is simply why the bill is smaller. Ignore: it becomes an ordinary bill, a late fee and the rent ladder.
Cause line: "You lose pay because you did not work; you lose performance only if you skip without a reason the job accepts; the bill gets worse only by going unpaid."

---

## 5. Arcs aimed at the player (task point 3)

All are threads (3.1) with one or two meters whose gain rules are real events. Safe wording rule: no sexual content, no gore.

| Thread | Meter and growth rule | Steps (thresholds, not timers) | Ways out (cost) | Ending |
|---|---|---|---|---|
| **Feud** (neighbour) | `grudge` 0 to 6. +1 for a loud night at the pawn's home (`public_disturbance`, gatherings after 22:00), +1 an insult to the neighbour, +1 a pet problem, +2 a failed repair/fire that touched their fence; the neighbour's `hot_headed` or `vengeful` trait doubles the gain; -1 every 3 quiet days | 1 a complaint in front of the street; 2 rumours (rep -1); 3 vandalism (the forced `vandalism` incident, repair 20 to 90); 4 a small-claims case (`small_claims`, `JusticeCivil`); 5 a shoving fight (`CrimeAssault.fight`, a bruise) only if the neighbour is `hot_headed` | Apologise (10 to 20 coins, -2); a pie (10 coins, -1); mediation at the hall (2 evenings, -3); hit back (+1, rep up or down); landlord/police (a record for them) | Grudge back to 0 for 7 days (a ledger "made peace"), a court result, or one of you moves |
| **Partner crisis**, non-mature | Couple `strain`: +1 when a bill is late (money fights), +1 per 3 evenings the pawn works past 20:00, +1 a missed anniversary/birthday gift (the calendar has them); -1 per date or gift | 2 cold evenings (mood); 4 an ultimatum ask; 6 the partner moves out | Counselling (60 coins, 2 evenings); a gift (30); a long talk (an evening); forgive; break up | Reconciled, or the partner leaves (shared income ends if they lived with the pawn) |
| **Partner tempted** (mature, switch respected) | The partner is an NPC: `Straying.chance` (romance low, trait) already decides if they flirt with someone else; only when that actually happens (an interaction with a third person is observed in gossip, `RelationshipKnowledge` secrets) the rumour reaches the pawn | rumour -> confront / keep watch / ignore -> proof or not | Confront (rep neutral; the partner reacts by traits), let it go (strain +1 each week), end it | Resolved or split. Never staged as a scene. |
| **Wrongly accused** (`suspect`) | A real case near the pawn (a theft at work, a burglary on the street) where `CaseEvidence` soft evidence points at the pawn: low rep, a record, no alibi (it uses where folk really were). The card is only *eligible* when that score is over a threshold, so it follows from what happened | police ask to talk -> arrest (exists, `JusticeProcess.arrest`) -> court (`JusticeTrial`) | Cooperate; a lawyer (120 coins; Easy legal aid free); look for the real culprit (case board, existing evidence interactions); flee (a crime, bad) | Cleared (rep +, a small apology payment if the case shows the true culprit), convicted (fine, service or jail from `justice.json`), or dropped. Ends with a record entry either way |
| **Rival for a partner** | The existing `triangle` arc (mature flag), with the `jealousy` of the NPC partner as the meter | as `triangle` plus a real consequence: neglect lets the partner leave | be honest, plan time together, confront | Partner stays/leaves |
| **Stalker / admirer** (safety) | `attention` grows when the pawn is in public places (work, hall) after an unanswered approach from a townie with a `clingy`/`obsessive` trait or a stranger; -1 per 3 days if the pawn is clear and firm | gifts -> seen waiting outside (a warning sign, mood) -> a long letter -> shows up at work | Tell them plainly (low risk); friends stand with you; the police and a `JusticeOrders` restraining order (costs a morning); ignore (attention +1 each ignored ask) | The police and an order, or they leave. Never physical harm; the top level is the police arriving |
| **Friend in trouble** | A friend (friendship >= 40) whose own state is bad: coins under their rent, no job, evicted, hospital | asks for money / a couch / a favour (a day's help moving) | Lend (up to 100, becomes a favour owed, 4.3); give a couch for N days (food costs more, their rep/mood effect); refuse politely (-8); sell something to help (cost) | They repay, they move on, or the friendship ends. Ledger remembers |
| **Family secret** (rewrite of `family_secret`) | The same first two stages; the letters (decided at the seed by a seeded draw and the pawn's family tree) point to one of three real endings | stage 3 asks "hear it" or "leave it" (leaving it costs a month of a lawyer's letters: the claim doesn't vanish) | see below | see below |
| **A habit** (OFF unless the owner says yes) | `urge` grows each time the pawn uses a comfort action while stressed (the existing gambling machinery, `BankGamble` addiction 0 to 100, tickets) | craving -> crash moods -> missed shifts | cut down (a week of lower mood), a friend's help, the hall's group | Mood and health spiral only; no substances for the pawn (the 23 line stays for NPCs). Q1 |

**Family secret endings (real, chosen at the seed):**
- *A sibling:* a half-sibling `{other}` becomes a real relation (`RelationshipBits` family flag, the `long_lost_family` incident and the `ask_to_stay` card exist). They may need a bed (a favour), may help pay rent, may disagree. Cost: a room, food; gain: a lasting contact.
- *A debt:* a late relative's debt (200 to 900) is claimed from the estate: a letter then a bill with a due date. Pay (a ledger bill), pay by instalments (a bank loan), contest in court (a lawyer; if the claim fails the debt disappears and rep is untouched), or disown the relative (rep -2). Ignoring turns it into a court case and a fine.
- *An inheritance with conditions:* a small property or a savings amount, with a plain condition: back taxes of 250 within 14 days, or house the relative for 28 days. Meeting the condition pays the gift (`inheritance`, exists); missing it loses it.
Cause line: "The secret matters because of what the letters held; it turns into money or a person, not a toast; it gets worse only if the claim is ignored (a debt claim reaches court)."

---

## 6. Consequences that stick (task point 4)

| Consequence | Today | Change |
|---|---|---|
| **Break-in takes named objects** | `CrimeBurglary._take` removes real objects (best valuables first) and coins (15 percent); recovery returns them | Add a **missing list** in the ledger: "TV (500) and computer (900) were taken on day 14", with prices from `Economy.price_of_def`. The poor pawn owns few things, so losing the computer is real. Choices: report it (existing, recovery chance), replace now at full price, replace second-hand if the Second-hand stall exists (36 Proposal C), fit a lock (`door_lock` objects exist, 40 coins), or cut corners: buy from a fence (if 21's market can sell to the player; not verified) and risk a handling charge. Home cover (`DisasterInsurance`) pays a share. Ignore: nothing returns. |
| **Fire makes a room unusable** | Burnt objects are gone, scorch marks last 6 days (`Fire.scorch`) | New `room damage`: tiles with scorch level 2+ and every room whose objects burnt are flagged **damaged**; interactions there fail with "The room is fire-damaged" until repaired: 15 percent of the lost value in materials plus 3 hours of work by the pawn (handiness gives a discount) or a handyperson (80 coins). In a rented flat the landlord adds a damage charge (120) if the cause was your own cooking or electrics; none if it was a neighbour's. Cause: "the room is unusable because it burned; it stays so until repaired." |
| **Hospital stay costs money and shifts** | Bill 60/220/700 by severity, unpaid becomes a bill; a stay keeps the folk away (Away) | The stay already means missed shifts (`sick_penalty`); add the `medical_debt` ask (4.5). Long stays on Hard trigger a probation-level review. |
| **Reputation changes how the town treats you** | A number with no effects | New `RepEffects` (data, tiers: disliked <= -30, known, respected >= 30, local hero >= 60): greetings (a cold shoulder refuses small talk; warm ones start chat), `Careers.make_offer` chance x0.5 to x1.5, the landlord's willingness to wait (4.1) and the shark's interest, `refused_service` hooked into the shop (known thieves) so the 23 query finally has an effect, and +/-5 percent on private sales only. Rep moves by recorded facts: a conviction, an eviction in the district (-5), a default (-3), paying up (+), helping a neighbour (+). |
| **Court ends in a fine you can't pay** | `JusticeSentence._fine` makes an ordinary "court fine" bill when short | Keep. It now feeds the rent ladder (late fee, repossession). A new ask on sentencing: pay now / instalments / community service instead (if the sentence allows). |
| **Community service clashing with work** | `JusticePlayer.hold(f, 240, "service")` once a day | New ask when a shift and a service slot overlap: skip work (-15 performance) or skip service (breach: probation extended, 1 day in jail on Hard). Whether the hold already blocks a shift start is NOT verified; the test must check it. |
| **Jail** | Sentence up to `jail_max_days` 10; `Careers.quit_job(f, "jailed")` ends the job at once; bills continue | Soften only the unrealistic part: a stay of 2 days or less counts as 2 missed shifts (performance), not an instant quit; longer ends the job. Real jail time remains on Hard. |

---

## 7. Difficulty sets stakes, not just numbers (task point 6)

All values are data in `difficulties` (36 R3) and `storyteller.json`. Hard rarity stays.

| Knob | Easy | Normal | Hard |
|---|---|---|---|
| Missed rents before the notice | 3 | 2 | 1 |
| After the deadline | a friend's couch or the night shelter cot (S9); a relief grant | bailiffs, lock-out, sign again with arrears + deposit | bailiffs, lock-out, deposit double, sleep rough (cold) |
| Hall relief fund | 60 coins monthly | 40 once | none |
| Loan shark | never offered | after the notice only | from the first missed rent; collateral taken at visit 3 |
| Bank loans | friendlier limit | by credit | by credit, limit x0.7 |
| Debt collectors | polite letters | letters and a visit | visits, collateral, bruise (severity 1) |
| Court and jail | fines x0.5, service instead of jail | normal guideline | jail up to 10 days with a lost job; fine unpaid -> bill |
| Legal help | legal aid free | lawyer 120 coins | lawyer 160 coins |
| Hospital and funeral x | 0.7 (exists) | 1.0 | 1.4 |
| Job loss | job-seeker support 14 days | severance only | severance only |
| Review thresholds | warn < 25 | warn < 35 | warn < 45, probation 21 days |
| `pawn_focus` / `gain_home` x | 0.5 / 0.8 | 0.65 / 1.0 | 0.8 / 1.25 |
| Thread growth speed (meter gains) | x0.8 | x1.0 | x1.25 |
| `hard_mult`, `crime_mult` | 0.8 / 0.85 | 1.0 / 1.0 | 1.3 / 1.3, capped at 1.5 |

Stakes, not frequency: Easy softens every *ending* (a couch, a grant, legal aid); Hard hardens the endings (the street, collateral, jail time) at about the same count of seeds.

---

## 8. Measurement (task point 7, with the amendment)

### 8.1 What exists and what is new

`tests/pawn_bot.gd` and `pawn_bot_balance_test` are planned in 36 S6 (a deterministic driver that plays the real game as the pawn). 39 reuses them and adds `pawn_bot_threads_longrun_test` (slow tier). The storyteller measurement pattern already exists in `storyteller_longrun_test` and I used it for the probe in 1.1; the probe becomes `storyteller_focus_longrun_test` (cards reaching the pawn per week by dial).

### 8.2 The bots

| Bot | Policy |
|---|---|
| Careful | Works every shift; eats; pays bills on the due day when it can; answers asks with a fixed rule table: cheapest-safe option that it can afford ("pay", "apologise", "call in sick honestly", "ask for time" once), never an illegal option |
| Ignore | Survives (eats, sleeps via the self actions) but does not pay bills, take jobs or answer any ask |

### 8.3 What the test prints (per player-week, Normal and Hard, 5 seeds x 60 days = about 43 player-weeks each, per bot)

- seeds planted (threads started) and threads in motion at the end of each week;
- threads that **grew** (level went up by their own rule);
- decisions asked, answered by a choice, expired (ignored);
- lowest coins in the week as a share of that week's costs (rent + bills + 7 x the food floor from 36 R2.5, about 250 on Normal);
- near-loss days: a rent notice open, or a missed rent with arrears, or probation/warning, or unemployed with arrears, or a loan-shark collateral threat;
- outcomes: evicted, fired, jailed days, debts owed at the end, hospital bills, deaths (must be zero).
All as a table plus JSON in the log. **No assert on hitting any near-loss count.** I will judge the feel in full-life runs.

### 8.4 What it asserts

1. **Threads exist and progress by their rules:** at least 1 seed in each 60-day run on Normal and Hard; every ledger "grew" row carries a cause string and the meter value that crossed its threshold; no step happens with the meter below its threshold (a replay check).
2. **Ignoring has consequences:** the Ignore bot on Normal has its lease ended by day 28 (by about week 3 with 36's numbers: late rent day 11, notice day 18, bailiffs day 21), on Hard by day 21; every expired ask wrote an `ignored` ledger row with a cost; nobody dies.
3. **A careful bot usually copes:** on Normal the Careful bot keeps its home in at least 4 of 5 seeds and is never evicted in the same seed twice; on Hard the number is printed, with an expectation of 3 of 5 (not asserted, tuned by data).
4. **Steer-free:** the same seed with the pawn at 50 coins and at 5,000 coins plays the same card ids for the first 30 days, apart from cards whose own cause differs (a rent bill unpaid, a missing lock). This is the unit test for P2.
5. **Determinism and save:** the same seed twice gives the same ledger hash after 60 days; a save/load at day 30 mid-ask gives the same ledger at day 60.
6. **Quiet days:** on Chaotic and Custom-max, the longest stretch with nothing touching the pawn is 3 days or less. Weekly medium/big counts are printed only.

---

## 9. Where it fits in the 36 plan, effort and risks

36 stages: S0 foundations, S1 silence the pawn, S2 survival floor, S3 the new start (flat tenancy, rent, eviction Tier A, difficulty ladder), S4 time, S5 routines, S6 balance and `pawn_bot`, S7 storyteller focus and heirs, S8 ask system, S9 move up (shelter Tier B).

39 is a stage group **T**, starting after S1 and S2 (the pawn must be silent and able to survive, otherwise a decision cannot mean anything), with the rent parts depending on S3:

| Stage | Deliverable | Needs | Sessions | Risks |
|---|---|---|---|---|
| T0 Aim | `pawn_focus`, personal budget, quiet-day guard, `wealth` ignored for the pawn, `storyteller_focus_longrun_test`. It replaces the part of S7 that is only about focus | S1 | 1 | Rates feel wrong until played |
| T1 Engine | Thread engine (meters, `when`, option prices, `ignore`, `wait_days`), ledger and panel, new fx verbs, tests | S2 | 2.5 | The panel and the plain-language rule text; keeping asks readable (<= 8 open asks) |
| T2 Money and work | Rent arrears thread over 36's rent, debt (friend favour, bank refusal, shark path with a player debtor), job review, probation, work rival, layoff watch, sick-call ask, medical debt | S3, T1 | 3 | Touches `Economy`, `Careers`, `CrimeUnderRacket`; balance with 36's numbers |
| T3 People | Feud, partner strain and tempted, wrongly accused, admirer, friend in trouble, family secret endings, habit (off) | T1 | 3 | Content volume and wording; safety review of text |
| T4 Stuck | Missing list, room damage, reputation effects, court/service/jail asks | T1, T2 | 2 | Room damage touches the building/object use rules; reputation hooks are in many shops |
| T5 Stakes and proof | Difficulty rows in data, charity/shelter hooks (shelter waits for S9), `pawn_bot_threads_longrun_test`, tuning | S6, T2 to T4 | 2 | Tuning needs full-life runs; the bot's rule table can bias the numbers |
| Total | | | **13.5 (range 10 to 17)** | |

Order and parallelism: T0 right after S2; T1 can run beside S3; T2 after S3; T3 in parallel with T2; T4 after T1 and T2; T5 last with S6's bot. Cut order if time is short: habit, then room damage, then partner tempted, then admirer, then the reputation price effects (keep greetings, job offers and landlord terms).

Main risks and answers:
- **Reads as a scripted barrage.** Mitigation: seeds are rare, one per kind, the ledger shows rules, there is no size or outcome floor, and the steer-free test.
- **Too hard on Normal.** Mitigation: every ending has at least one affordable way out; thresholds are data; the bot test prints near-loss days for the owner to judge rather than assert.
- **Co-op:** choices already go through commands; a thread per pawn household; no new top-level save key.
- **Old saves:** threads start empty; the ledger empty; nothing needs migration.
- **Text volume:** around 20 cards and 10 threads are about 120 lines of player text each in data; needs a wording pass for tone.

---

## 10. What exists and can be reused, and what is new

**Reused as is:** `Storyteller`, `StorytellerBudget/Deck/Play/Fx/Choice/Ripple/Queue/Log/Chaos/Cycles` (chaos walk, budget, heat, chains, foreshadow, log); the 8 arcs in `storyteller_arcs.json` (feud, admirer, family_secret, triangle, business, missing person, rising criminal, town crisis); `JusticePlayer.ask` and the `storyteller {choose}` command; `Economy` bills, late fees, repossession, `HousingRent`, `ChaosMoney.eviction`; `BankAccounts` loans and credit score; `bank_insurance` / `DisasterInsurance`; `CrimeUnderRacket` (lend, collect, case); `Careers` performance, `fire`, `quit_job`, `make_offer`; `Health.work_block`, `Worsening.strain_extra`; `Hospital` stays and bills; `CrimeBurglary` object removal and recovery; `Fire.scorch`; `JusticeSentence`, `JusticeOrders`, `CaseEvidence`, `JusticeTrial`, `JusticeCivil`; `Straying`, `RelationshipKnowledge` (secrets, gossip, reputation); the incidents `long_lost_family`, `inheritance`, `layoff`, `eviction_notice`, `small_claims`, `vandalism`, `burglary`, `public_disturbance`; the `ask_to_stay` card; `StoryVisits`.
**Changed:** `StorytellerArcs` (meters, `when`, many per household), `StorytellerChoice` (prices, `needs`, `ignore`, `wait_days`), `StorytellerBudget` (focus gain, personal guard), `StorytellerDeck.weight_of` (wealth ignored for the pawn), the `family_secret` arc data, `CrimeUnderRacket` (player debtor), `CareerShifts`/`Careers` (weekly review, warning, probation, sick-call ask), `JusticeSentence` (instalment ask, short jail rule).
**New:** thread engine files and data (3.1); the ledger and its panel; `RepEffects`; room damage; the missing list; the favours book; `pawn_bot_threads_longrun_test` and `storyteller_focus_longrun_test`; the steer-free test.

---

## 11. The challenge cards (task point 3 table)

Cause line = "X happens because Y; it gets worse only if Z." Costs are Normal (coins).

| id | Trigger (cause) | Stakes | Choices (cost) | Escalation | Resolution | Cause line |
|---|---|---|---|---|---|---|
| `rent_late` | Rent bill unpaid 3 days after issue | Home | Pay all; pay half and promise (+10 fee); ask for time (once per 8 weeks); borrow; ignore | Next unpaid bill = notice | Arrears paid; or notice | Rent is late because the bill was not paid; the notice comes only after a second miss; paying at any step ends it |
| `eviction_notice_pawn` | Second missed rent (Easy 3rd, Hard 1st) | Home, belongings | Pay arrears+fees; friend's couch (favour); relief fund; sell items; move out on your terms | 3-day deadline | Paid, or bailiffs take up to 3 things, lease ends, locked out | The notice stands because two rents were missed; the home is lost only when the 3 days pass unpaid |
| `shark_offer` | Arrears open + bank refused + a racketeer exists | Money, safety of things | Borrow 60 to 300 at 25 percent/7 days; decline; ask a friend | Visits every 2 days after the due day (`collect`) | Paid; collateral taken (Hard); lender arrested | A lender lends because you are desperate; visits come because the due day passed; stops when paid or something is taken |
| `medical_debt` | Hospital discharge bill not payable | Money | Pay; 4 instalments +10 percent; charity care (Easy/once); ignore | Becomes an ordinary bill, late fee | Paid or feeds rent ladder | The bill exists because of the stay; it grows only by lateness |
| `sick_shift` | Unwell or injured at shift start | Pay, performance, health | Call in sick (no pay, -4); go in (pay, slower healing, may pass flu on) | Repeated sick days feed `job_review` | Recovered | You lose pay because you didn't work; healing slows only if you strain |
| `job_review` | Performance < 35 or 2 skips in 14 days | Job | Ask to improve (unpaid hour, +5); extra shift (+8); honest explanation; look elsewhere | Second weak check = 14-day probation; a skip on probation = fired | Passed at >= 50, or fired | A warning follows a falling performance meter; the job ends only after another miss |
| `work_rival` | Coworker in the same career; you win or are praised | Job, promotion | Speak up (perf >= 60); befriend (15); work harder; confront | `resent` >= 3 and friendship < -20: tells the boss (-10) | Rival leaves/promoted/friend, or you move | The rival acts after you win and stay unfriendly |
| `layoff_watch` | Recession, closure chain or rumour; level 1 and short tenure raise it | Job | Look for work now; work extra; keep your head down | The `layoff` incident next day | Severance (40 h) and job search | Cuts come because the business is weak; seniority and performance lower the risk |
| `feud` | `grudge` from noise, insults, pets, fence damage; hot-headed neighbour doubles | Rep, money, safety | Apologise (10 to 20); pie (10); hall mediation (2 evenings); hit back; police/landlord | Complaint, rumours, vandalism, small claims, shove (hot-headed only) | Grudge 0 for 7 days, court result, or a move | It grows only by what you and they do; it cools after 3 quiet days |
| `partner_strain` | Money fights, long hours, missed days | Relationship, home | Counselling (60); gift (30); long talk (evening); forgive; break up | Cold evenings, ultimatum, moves out | Reconciled or apart | Strain builds from stress you share; falls with time together |
| `partner_tempted` (mature) | The NPC partner actually flirts elsewhere (`Straying`) and it is noticed | Relationship | Confront; keep watch; let it go; end it | Strain +1 per week unresolved | Resolved or split | It happens only if the partner drifted; it worsens if unaddressed |
| `suspect` | A nearby case where soft evidence points at you | Freedom, rep, money | Cooperate; lawyer (120); look for the culprit; flee (crime) | Arrest, court, sentence | Cleared, convicted, or dropped (a record entry) | Police look at you because of record, rep and no alibi |
| `admirer` | Unanswered approach from a clingy townie / stranger | Safety, peace | Say it plainly; friends stand with you; police and order; ignore | Gifts, waiting outside, letter, turns up at work | Order, or they leave; never harm | Attention grows with each ignored sign; falls when you are firm |
| `friend_trouble` | A friend (friendship >= 40) short of rent, jobless or evicted | Money, friendship | Lend up to 100 (favour owed); couch N days; refuse (-8); sell something | Asks again if you helped and they stay broke | Repaid, moved on, friendship lost | They ask because they have nobody else; it recurs if you keep funding it |
| `family_secret` | Letters and a stranger's contact | Money, family | Hear it / leave it; then by ending: house a sibling; pay or contest a debt; meet a condition for an inheritance | Debt claim reaches court if ignored | A sibling, a debt cleared, or an inheritance won/lost | It turns into a person or money; worse only if the claim is ignored |
| `break_in_after` | A burglary at home | Named objects, safety | Report; replace now; replace second-hand; fit a lock (40); buy from a fence (risky) | Unrecovered items stay gone; repeat targeting if no lock | Recovered, replaced or gone | Things are missing because they were taken; the risk rises only if the door stays unlocked |
| `fire_after` | A fire in the home | A room, objects | Repair yourself (materials + 3 h); handyperson (80); live without it | Landlord damage charge if your own fire | Room usable again | The room is unusable because it burned |
| `court_date` | A charge filed against you | Money, freedom, job | Lawyer; plead; fight; fine now/instalment/service | Missed court = warrant | Verdict | The verdict follows evidence and guideline; a fine unpaid becomes a bill |
| `service_clash` | Service slot overlaps a shift | Job or record | Skip work (-15); skip service (breach) | Breach extends probation | Service finished | You are held for service because the court ordered it |
| `habit` (off) | Stress plus repeated comfort action | Mood, money, shifts | Cut down; friend's help; hall group | Craving, crash, missed shifts | Recovered or spiral eases | Only a mood and money spiral, no substances |

---

## 12. Open questions for the owner

1. **A habit/addiction spiral for the pawn** (gambling or a comfort habit only, as mood, money and missed shifts)? Default OFF. No substance storyline for the pawn either way.
2. **Quiet-day guard.** Is a small seed after 3 quiet days on Chaotic/Custom-max fine as 'more things in motion' (it never reads the player's state), or should T0 be `pawn_focus` only? (The weekly medium floor was dropped per the amendment.)
3. **Violence ceiling.** On Hard the loan shark takes an object and leaves a bruise (injury severity 1, a notification). Is a bruise OK, or should Hard stop at collateral and threats?
4. **Jail.** Hard keeps real jail days and the lost job. Should a short stay (2 days or less) keep the job as proposed (it counts as missed shifts)?
5. **Good luck for the poor.** I remove the poor-state windfall/headhunter tilt for the pawn (it is a form of mercy tied to wealth). Keep it removed, or keep it as the "mercy" slider's job?
6. **Job-seeker support** for 14 days after a layoff on Easy (20 a day): fine, or leave soft landings to the relief fund only?
7. **Reputation effects on prices.** I propose greetings, job offers, landlord/lender terms and refused service, but not shop prices (an honest world doesn't reprice you). OK?
8. **How loud should the ledger be?** Open threads shown as a plain-language rule ("a notice follows a second missed rent") is fair play; some players want to be surprised. Default: rules visible, dice hidden.
9. **Family secret endings** (sibling, debt, conditional inheritance): all three, or drop the debt for Easy?
10. **Shelter and the night cot (36 S9)**: Easy needs it as the soft landing; until then Easy uses a friend's couch and the relief grant. Pull the cot forward into T5?

Not in this plan: the age/stage-year mismatch and other logic problems in the reviewer's Zack run message (items 1 to 8); they stand on their own.

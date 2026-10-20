# Businesses, jobs, economy and town: end-to-end map

Written by the reviewer from a read-only pass over the code at main 2bdcb53. Code is in `scripts/systems/`, data in `data/`.

## 1. Businesses

Files: `business_state`, `business_sim`, `business_day`, `business_cmd`; data in `businesses.json`.

### Slots and types

A business sits in a slot on an existing commercial lot:

| Lot | Slots |
|---|---|
| Café | 3 |
| Market | 3 |
| Gym | 1 |
| Library | 1 |
| Office | 2 |

That's 10 businesses at most. There are 7 types: café, shop, restaurant, salon, gym, bar and bakery. Each type has its own allowed lots, fit-out cost (1,400 for a café up to 2,400 for a restaurant), demand, average spend, unit cost, staff capacity, natural opening hours and owner skill.

**It's purely statistical.** No customers walk in, and businesses don't count as venues.

### The player opens one

`BusinessCmd.open`, from the Business dialog.

- **Cost:** fit-out × the price index. Choosing to own instead of rent adds lot rent × 40 × the rent index. A permit fee applies only if the council has passed the permits policy.
- **Starting stock:** 50% of the cap.
- **Owner skill:** 2 + the best adult's skill in the business's field, up to 9.
- **News:** a chronicle entry and a `business_opened` event.

### A townie opens one

`BusinessDay._found_townie_business`, once a day.

- **When:** only while the town has fewer than 5 townie businesses. Daily chance 0.1 × clamp(1 + prosperity, 0.2, 2).
- **Founder:** an adult townie with 150+ coins who doesn't already own a business. Their career isn't checked.
- **Which type:** types the town doesn't have yet are favoured. In a recession, types with a fit-out over 1,800 get ×0.4.
- **Money:** the founder pays half their coins. The business always rents, starts with 5% of the fit-out as cash, has owner skill 2–6 and a random price level of 0.85–1.15.

### Customers per day

```
customers = demand
          × effective hours        (hours outside the natural window count ×0.25)
          × lot traffic            (market 1.3 … library 0.6)
          × reputation             (0.4 + 1.2 · rep/100)
          × price^-1.5
          × (1 + 0.35 · prosperity)
          × competition            (1 / (1 + 0.25 · rivals))
          × 1.4^(level − 1)
          ± 20%
```

Capped by staff capacity, and by stock unless auto-stock is on.

### Money per day

- **Revenue:** customers × average spend × price × price index.
- **Costs:** stock, wages, rent (when renting) and utilities (6 × price index).
- **Reputation** drifts towards a target set by staff skill, number of staff, price, customers turned away, running out of stock and business level.
- **Reviews:** a 1–5 star review with 50% chance each day. The last 8 are kept.

### Cash at the end of the day

- **Profit is paid out every day:** the player gets 100%; a townie owner keeps 60%.
- **Losses are covered by the owner.** After 7 days in a row that the owner can't cover, the business goes bankrupt: a townie owner keeps only 40% of their coins, and the player gets a toast and a `business_bankrupt` event.
- **An owner's death** closes the business.

### Player controls

- **Running it:** price 0.7–1.5, opening hours (at least 3), open or closed (rent is still paid when closed), and restocking.
- **Staff:** hiring and firing.
  - Candidates are townies with no career; the fee is 40.
  - Wage per open hour: (9 + 1.2 × skill) × the wage index.
  - Staff allowed: 2, plus 2 per level.
- **Expanding:** to level 3 at most. Needs reputation 55+ and costs fit-out × 0.8 × level.
- **Selling** brings in 50% of fit-out × level, plus 5 × the average profit over the last 7 days, plus the cash on hand.

### Townie businesses never hire anyone

### What opening or closing changes

- **Jobs:** staff earn coins and count as employed.
- **Competition** with rival businesses.
- **Crime:**
  - robbery and shoplifting targets;
  - racketeering "protection", on townie-owned businesses only (18–55 a week);
  - money-laundering fronts, on player-owned businesses (300 to set up, up to 800 a week).
- **Not affected:** shop prices (a separate ShopStock system with 9 shops), crowds at venues, the town budget, and residents' jobs (residents can't be staff).

## 2. Jobs and careers

Files: `careers`, `career_shifts`, `career_progress`, `career_spread`, `job_seeking`, `opportunity_taker`, `edu_jobs`, `works*`.

### The careers

- **20 in all:** 14 base careers, 5 industrial ones (factory, warehouse, construction, mechanic, utility tech) and politician.
- **Levels:** 5 levels, mostly splitting into 2 branches at level 4.
- **Pay**, for example the cook: 14 / 20 / 28 / 38 / 52 an hour.

### Job offers

- **Who gets them:** a jobless adult who isn't a homemaker, at least 7 days after their last change of job.
- **Daily chance:** 0.3 × the storyteller's job multiplier.
- **Which career** is weighted by:
  - skill;
  - traits;
  - aspiration (+2 for a match);
  - openings on the job board (×1.4, or ×1.2 more if "hot"; ×0.7 with no openings);
  - fewer housemates already in that career.
- **Expiry:** an offer lasts 3 days.
- **Teens** only get part-time jobs.

### Taking a job

There are four ways in:

1. **"Look for Jobs" on a computer.**
2. **The Work window.**
3. **The Town → Jobs tab** (`EduJobs.apply`). The board holds 0–3 openings per career, refreshed weekly and scaled by the economy's hiring rate. You can start up to level 2, or level 3 with a degree in the field.
4. **`OpportunityTaker` accepts automatically, every day,** for anyone seeking work: searched in the last 3 days, OR has no computer, OR has under 300 coins.
   - Chance: 0.15 + 0.12 × (1 + 1.5 × skill + traits), up to 0.85.
   - So the routes without a computer are the Jobs tab and this automatic take.
   - Toasts mention "asking around", but no job interaction does that.

### Requirements for a level

Skills, traits, number of friends, a degree from certain levels, and a clean record for justice jobs.

### Shifts

The folk commutes there. Pay per shift:

```
hours × level pay
      × (0.8 + 0.4 × performance/100)
      × shift multiplier × wage index × degree bonus (1.08)
      + industrial extras (strike rises, 1.5× overtime, union dues)
```

### Performance

- **Gains:**
  - each shift: +3, plus mood (e.g. focused +4, angry −4), buffs, how skill compares with the level, and traits;
  - home actions that count for the career (e.g. cooking +3 for a cook);
  - a daily task: a one-off +5 to 6.
- **Losses:**
  - late arrival: −1.5 per 10 minutes, up to −10;
  - not turning up (90+ minutes late): −15; skipping −8; too run down or sick −4;
  - leaving early: −15 and half pay.
- **At 100:** promoted if qualified, with a bonus of new pay × 8 and performance reset to 40.
- **At 0:** demoted (performance reset to 35), or fired if already at level 1.

### Skipping work

- **By choice:** the player's "skip work today" command.
- **When busy at shift time:** a 0.04 base chance, raised by traits and moods (lazy 2.2, angry 2.0), up to 0.35.
- **No penalty:** maternity leave, a strike, or construction rained off.

### Changing career

- **Who:** young adults, in their first 60 days of adulthood, at level 2 or below, after 12 or more days in the job.
- **Chance:** 0.012 a day, tripled if performance is under 40.
- **Only if** the new career fits 1.6× better.

### No plain "quit" command

A job ends through one of:

- becoming a homemaker;
- applying for another job on the board;
- a career change;
- the midlife-crisis event;
- jail;
- being fired.

### Layoffs

1. **In a downturn:** while prosperity is below −0.3, a daily 0.004 × (−prosperity) × the career's layoff multiplier (factory 1.5). Severance is pay × 8 × 3.
2. **Plant closure** (industrial careers): 0.0015 × (1 + 6 × slump) × the layoff multiplier, needs 3 or more workers, then a 40-day cooldown. Severance is 40 hours' pay.
3. **Storyteller or chaos cards:** severance of 40 hours, possibly the whole household laid off.

### Strikes

- **Daily chance:** 0.006 × (1 + 3 × slump) × (1 + 0.5 × recent injuries).
- **Length:** 2–5 days. Union members get 40% strike pay.
- **Ending:** may end with a 3–8% pay rise.

### Unemployment benefit

Paid after being fired or laid off: 18 × the wage index a day, for up to 14 days. Nothing after quitting.

### Retirement

Automatic on becoming an elder. Pension: level × 14 + 10 a day.

### Townies

- **Getting work:** a jobless townie finds work at 0.12 × the hiring rate a day.
- **Promotion and demotion:** promoted at 0.04 a day, demoted at 0.015. Demoted at level 0 means losing the job.
- **Income:** 40 × level a day.
- **Old age:** they stop working when they become elders.

### Other income

- teen part-time work: 9 an hour, 15:00–19:00;
- freelance: 40 + 9 × best skill, twice a day;
- odd jobs: 30, twice a day;
- selling crafts: the price drops 8% per unit sold in a day, and online sales keep 60%.

Remote work and internet access are stubs.

## 3. The economy cycle

File: `market_economy.gd`; settings in `shops.json` under "economy".

### Phases

- **Start:** each normal day has a 0.025 chance of starting a 12–30 day phase.
- **Boom or recession:** a boom has probability clamp(0.5 − 0.3 × prosperity, 0.2, 0.8); otherwise it's a recession.
- **Forcing a phase:** the storyteller's boom/bust cycles and its cards.

**Prosperity** runs from −1 to 1. It moves 12% a day toward the target (+0.7 in a boom, −0.7 in a recession, 0 normally), with ±0.04 noise.

### Inflation and the indexes

Inflation is 3% + 5% × prosperity per 28-day year, on a base clamped to 0.6–3.0.

| Index | Formula | Follows |
|---|---|---|
| Price | base × (1 + 0.1p) | 25% a day |
| Rent | base × (1 + 0.12p) | 8% a day |
| Wage | base × (1 + 0.06p) | 10% a day |

### What it changes

- **Price index:** every price, bill, fit-out cost and prize.
- **Wage index:** wages and benefits.
- **Rent index:** business rent.
- **Demand:** businesses ±35%; ShopStock demand ±30% and restocking ±20%.
- **Money and property:** savings and loan rates, and house values (×(1 + 0.2p)).
- **Hiring rate:** (1 + 1.5p), clamped to 0.15–2.
- **Townie jobs:** layoffs below −0.3; hiring above +0.1.
- **Industry:** layoffs, strikes and closures among residents.

### Unemployment

Unemployment = jobless seekers ÷ (workers + seekers). Reported only.

### No direct link to crime or mood

`CrimeRate` uses poverty and joblessness itself. There's no recession mood buff; `money_worries` comes only from one storyteller card.

## 4. Money flows

### Starting money

6,000 coins (`economy.json`). The scenario's funds × difficulty are passed in by the start screen.

### Bills

Files: `Economy`, `UtilityBills`.

- **Timing:** weekly, the first on day 4, due 3 days later.
- **Amount:** 90 + 2% of the lot's value, split across power, water, internet and council rates. Adjusted for weather, scenario and the price index; the council-rates part also follows the tax rate.
- **Added on:** insurance and security.
- **Cut by:** solar, a water tank or a well (up to 90%).
- **Late fee:** max(10, 10%).
- **Three late bills in a row:** the most valuable object is repossessed.
- **Autopay:** always on for townie households, off for the player by default. The `auto_pay` key is never read.

### The bank

File: `bank_accounts.gd`.

- **Savings:** 3% + 2p a year (at least 0.5%), compounded daily.
- **Credit score:** 300–850, starting at 600.

  | Change | Points |
  |---|---|
  | Bill paid on time | +4 |
  | Late bill or loan payment | −35 |
  | Default | −90 |
  | Loan repaid | +25 |
  | Per 1,000 of debt | −6 |
  | Per 1,000 saved | +5 |
- **Loans:**
  - **Rate:** 8% + 10% × (850 − score)/550 + 2p.
  - **Limit:** (score − 450) × 12, minus what's already owed.
  - **Terms:** at most 2 loans, at least 200 each, repaid over 20 weeks.
  - **Defaults:** 3 missed payments is a default. A mortgage takes the property; other loans mean repossession.
- **Rent:** charged like a bill. Two missed rents bring an eviction notice.

### Gambling

File: `bank_gamble.gd`.

- **Lottery:** weekly, tickets cost 5.

  | Prize | Chance | Pays |
  |---|---|---|
  | Small | 0.12 | 12 |
  | Medium | 0.012 | 80 |
  | Big | 0.0015 | 600 |
  | Jackpot | 0.0004 | starts at 400, +3 per ticket |
- **Cards:** 47% chance to win double.
- **Addiction:**
  - each ticket adds +1.2, decaying 1 a day;
  - "hooked" at 40;
  - a hooked person buys 4 tickets on a 25% daily urge.

### Windfalls

Promotion bonuses, severance, the lottery, crafts, storyteller money cards, and coins found during incidents.

### Inheritance

Runs when the last member of a household dies.

- **With a will:** the heir gets the coins plus savings minus debts, the objects and the properties.
- **Without a will:** spouse, partner, family or sweetheart, in that order.
- **`ChaosKin.inheritance`:** kills a townie relative and pays up to 80% of their coins, at most 2,500.

## 5. The town

Files: `city_gov`, `city_election`, `city_policy`, `city_mood`, `city_budget`, `city_plan`, `city_public`, `city_services`; data in `city.json`.

### Mayor and council

The mayor is the eligible townie with the highest charisma (adult, no criminal record, not in custody). The council has 4 members, each with random leanings on 6 axes.

### The weekly budget

- **Revenue:** (20 + 8 per head + 40 per player household + 18 per finished shops project) × tax.
- **Tax:** 0.6–1.6.
- **Split:**

  | Utilities | Fire | Police | Health | Roads | Parks | Schools | Reserve |
  |---|---|---|---|---|---|---|---|
  | 0.19 | 0.11 | 0.15 | 0.15 | 0.13 | 0.06 | 0.12 | 0.09 |
- **Austerity:** ×0.8 when the treasury is below −400. Funding stays within 0.4–1.8.
- **Starting treasury:** 500.
- **Businesses pay no tax.**

### What funding changes

- fire, ambulance and police response times;
- the crime rate (police and parks);
- how often utilities fail and how fast they're repaired;
- road wear and road works;
- school grades;
- lamps, bins and amenities.

**Bug:** roads funding never affects buses. `TransportBus.thinned()` checks `CityBudget.funding("transport")`, but no "transport" department exists, so it always reads 1.0.

### Town mood

Runs from −1 to 1. Built from response times, outages, tax, the crime rate, road quality, public spaces, and scandals from the storyteller. Approval = 50 + 50 × mood. The worst factor becomes the town's main complaint.

### Elections

- **Term:** 84 days, with the campaign opening 14 days before the vote.
- **Candidates:**
  - the sitting mayor, who runs 80% of the time;
  - any player who declares at the mailbox (charisma 1+);
  - the townies with the highest charisma, up to 3.
- **Score:** charisma + support, +0.6 if the platform answers the town's complaint.
  - The sitting mayor's score is affected by mood × 1.2.
  - Challengers gain 0.4 × how angry the town is.
- **Campaigning:** a speech adds 0.6 + 0.25 × charisma, up to 3 a day.
- **The vote:** townie turnout is 60%. Each vote a player casts counts as one.
- **A new townie mayor** applies their platform, and 1–2 council seats change hands.
- **A player who wins** becomes Mayor, at politician level 4 (44 an hour), but only if they had no job.

### Policies

- **The options:**
  - a curfew: under-18s off the streets 22:00–05:00, street crime ×0.85;
  - park opening hours;
  - quiet hours, with a 20-coin fine;
  - free buses;
  - green grants;
  - permits.
- **How they pass:** by council vote, each member voting by their leanings.
- **Who proposes them:** a townie mayor tries one every 28 days (60% chance); a player mayor proposes from the mailbox.
- **Repeals:** a policy can't be repealed for 28 days.

### City growth (`CityPlan`)

- **When:** weekly, once townies fill 90% of the cap (24 + 4 per block of flats) and fewer than 2 projects are running.
- **What gets built:** chosen by zoning (residential 0.55, commercial 0.30, civic 0.15). Paid from the treasury: flats 300, shops 250, a community centre 280.
- **How long:** scaffolding 2–4 days, then 6–14 days of building. It creates no jobs.
- **Effects:**
  - flats: +4 to the population cap;
  - shops: +18 revenue a week;
  - community centre: +0.05 parks and +0.03 schools.

### New townies (`StoryGrowth`)

- **Arrivals:** a daily 0.15, +0.05 per head below 12. Families 20%, couples 30%, the rest single.
- **Babies:** townie couples have babies at 0.12, at least 14 days apart, 5 at most.

### Public spaces

Lamps break and get fixed, bins fill up into litter, amenities are added, and holiday decorations go up. Lamps feed the crime rate; all of it feeds the town's mood.

## 6. Ripples that exist

- **The economy** moves prices, bills, wages, layoffs, strikes, plant closures, the job board, house values and loan rates.
- **Jobs** feed the crime rate (through joblessness), benefits and the unemployment figure.
- **The budget** sets services, crime, roads, utilities and school grades. Those set the town's mood, and the mood decides elections.
- **Businesses** are crime targets and pay their staff.

## 7. Missing or partial

- **Businesses:**
  - no visible customers, and no effect on venues;
  - residents can't work in them, and townie businesses have no staff;
  - staff aren't put back to job-seeking when a business closes;
  - no business or property tax.
- **Buses:** the funding hook never fires.
- **Leaving work:** no voluntary retirement and no quit command.
- **Stubs:** internet access and remote work.
- **The economy** has no direct effect on mood.
- **Data keys never read:**
  - `businesses.json`: pay_days, sweep_keep_days, start_cash_days, name_suffix;
  - `economy.json`: auto_pay;
  - `careers.json`: retirement.min_level.

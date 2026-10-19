# Economy, housing and businesses (task 13)

Everything here is OPTIONAL for the player and RUNS WITHOUT THEM: townies own businesses, rent, hold mortgages and trade houses, the economy booms and slumps, shops restock, a lottery is drawn. The household can join in through one window ("Money" in the top bar, tabs Town / Shops / Business / Homes / Bank) or the in-world interactions (desk / computer "Write a Will", computer "Sell Crafts Online" / "Freelance Work", mailbox "Manage Money" / "Do Odd Jobs", market stalls for lottery tickets).

The whole track is OFF until `MarketEconomy.start()` (a new game, or a loaded save; a save without the `econ` block starts it fresh). While off every multiplier is 1.0 and nothing ticks, so older systems and tests are untouched.

## Files

| Area | Systems (`scripts/systems/`) | UI (`scripts/ui/`) | Data |
|---|---|---|---|
| Living economy | `market_economy` (prosperity, indexes, unemployment, town stats), `market_tick` (the one door: reset, daily order, event routing, save) | `bank_hub` (window + Town tab) | `data/shops.json` `economy` |
| Shops | `shop_stock` (shelves, deals, orders, inventory, parcels), `shop_buy` (walk-in, online, use) | `shop_dialog` | `data/shops.json` `shops`, `stock` |
| Businesses | `business_state`, `business_sim` (daily model), `business_day` (settle, bankrupt, townies found), `business_cmd` (player) | `business_dialog` | `data/businesses.json` |
| Housing | `housing_props` (properties, value), `housing_rent` (rent, eviction, townie landlords, foreclosure), `housing_agent` (player commands) | `housing_dialog` | `data/housing.json` |
| Bank | `bank_accounts` (savings, loans + mortgages, credit score), `bank_insurance`, `bank_will`, `bank_gamble` (lottery, cards, addiction) | `bank_dialog` | `data/bank.json`, `data/shops.json` `lottery` |
| Work | `market_work` (teen job, freelance, odd jobs, crafts, layoffs, benefit) | in `shop_dialog` | `data/bank.json` `work` |
| Command layer | `market_command` (`run(player_id, folk_id, action, args)`, logged) | all UI goes through it | |
| Content | | | `data/incidents/13_economy.json` (buffs, interactions) |

## Tier / cadence / active set / caps (also in docs/PERFORMANCE.md)

| System | Tier | Cadence | Active set | Caps |
|---|---|---|---|---|
| MarketEconomy | town | daily | none (numbers) + `Story.townies` (~12) | history 12 monthly entries |
| ShopStock | town | daily (restock, demand, sales) + on command | ~9 shops x <= 6 items | orders 40 |
| MarketWork | household | daily + interaction events | the household's folk | gigs 2/day each, craft demand per kind per day |
| HousingProps / HousingRent | town | daily (condition, market) / weekly (rent) | <= ~12 properties | listings.count = 5 |
| BusinessSim / BusinessDay | town | daily | open businesses (<= 10 slots) | reviews 8, history 7 days, townie businesses 5 |
| BankAccounts | town | daily (interest) + weekly payments | households with savings or loans | 2 loans per household (+ mortgages) |
| BankGamble | town | daily + a draw every 7 days | people with addiction > 0, households with tickets | addiction 0..100 |
| BankInsurance / BankWill | event | on payout / death | none | |

Nothing polls per minute or per person per minute. There is no per-minute hook at all; `MarketTick.on_day` is the only clock entry (SystemsManager `_on_day`).

## The living economy

`prosperity` (-1..1) moves toward 0, or toward +0.7 in a boom / -0.7 in a recession (phases start with 2.5 percent a day, last 12 to 30 days, announced in the chronicle). On top of a slow inflation (3 percent a year + 5 percent x prosperity; a game year is 28 days) prices follow prosperity quickly (+-10 percent), rents slowly (+-12 percent), wages in between (+-6 percent). Townies are laid off in a recession (below -0.3) and hired in a boom; the unemployment rate counts adult townies and residents without work (a freelancer, a business owner or a business employee counts as working). A monthly report goes to the chronicle (`economy_report`). `MarketEconomy.stats()` / `lines()` / `headline()` feed the paper; `town_budget()` is a stub until task 12.

## Shops

Shops are data on existing lots: supermarket, market stalls, clothing, pharmacy, hardware on `market`; bookshop on `library`; furniture and electronics on `office`. Each item has a shelf size, a daily truck and a daily town demand; a sale (20 percent, 3 days, one shop a week) and holidays (15 percent) lower prices; a nearly empty shelf costs 10 percent more. Walk-in buying needs the folk at the shop's lot and the shop open; online orders cost a delivery fee and arrive the next day. Food goes to the pantry (`Neighborhood.add_pantry`), books and clothes are used on the spot, medicine / first aid kits / repair kits sit in the household inventory, furniture and electronics become PARCELS: build mode places the object at no further cost (`WorldBuild.buy_place` consults `ShopStock.take_parcel`).

## Businesses

7 types (cafe, shop, restaurant, salon, gym, bar, bakery) on slots of existing lots (cafe 3, market 3, gym 1, library 1, office 2). Rent the slot (fit-out up front, rent a day) or buy it. Daily customers = type demand per hour x trading hours (hours inside the type's natural window count fully, others a quarter) x location traffic x reputation (0.4..1.6) x price^-1.5 x prosperity x competition x level; capacity comes from staff (owner counts as one). Reputation drifts toward a target built from staff skill, staff count, price, unserved customers and stock-outs; customers leave stars and a line of text. The same model runs for townie businesses; they are founded when a townie has the coins and a free slot (weighted toward missing types), pay and earn the same way and go bankrupt after 7 days of negative cash with no owner funds. Profit is swept into the household ledger daily (`profit: <name>`), losses are drawn from it. Typical profit at average reputation is 60 to 85 coins a day for a fit-out of 1100 to 2400.

## Housing

4 map houses (your home, 3 townie homes) plus 5 rotating listings (statistical flats and houses). Value = base x neighbourhood (hood quality, school, park) x condition x crime (`CrimeRate.value_mult`) x housing market index. The player starts owning the home outright. Buying: 20 percent down + 3 percent agent fee, a mortgage in the bank book (40 weekly payments, rate from credit score and prosperity). Selling your home is a lease-back (you stay as tenants at the market rent). Letting a second property: a townie tenant moves in, rent is deposited weekly; increases are limited to 8 percent per 28 days; a tenant who cannot pay is evicted. A player tenant gets an ordinary Economy bill (`reason: rent`): late fees, missed-bill counting and repossession are the existing machinery, plus an eviction notice at the second late rent. Three missed mortgage payments foreclose: the bank takes the property back (your own home stays occupied: you become the bank's tenant).

## Bank, insurance, wills, gambling

Savings earn 3 percent a year (+2 x prosperity). Loans: limit and rate depend on the credit score (300..850) built from the bill book (on time / late), loan payments, defaults, debt and savings. Insurance: health (80 percent of hospital and doctor bills), car (flat payout after `traffic_hit`), life (payout when a household member dies), next to the existing home cover; `BankInsurance.cover` is now `Incidents.insurance_fn` and reads `Incidents.cover_kind` ("" property, "health"). A will names an heir (a housemate, relative, friend or townie); when the household ends, `Aging._inherit` calls `BankWill.apply`: coins and savings (after debts), belongings and properties go to the heir. Lottery: tickets 5 coins at the market stalls, weekly draw (12 percent small, 1.2 percent medium, 0.15 percent big, 0.04 percent jackpot, house edge about 25 percent); cards: 47 percent to double the stake. Gambling builds an addiction value per person; at 40 the person buys tickets on their own, gets a `gambling_urge` buff and the `gambling_addiction` game event fires once (hook for Health later).

## Work beyond careers and balance

Teens: part-time 15:00 to 19:00, 9 coins an hour (tiring). Freelance (computer, needs internet: stub true until task 12): 40 + 9 x best skill, 2 a day. Odd jobs (mailbox): 30 coins, 2 a day. Crafts (paintings, books from `paint_*` / `write_*`, garden produce and fish from the `harvested_crops` / `caught_*` events) sell at the market stall for full price or online for 60 percent, demand per kind capped per day and each unit sold drops the price 8 percent. Recession layoffs of residents (0.4 percent a day x severity) give 3 days of pay as severance and unemployment benefit (18 coins a day, up to 14 days). BALANCE NOTE: the existing fishing / harvest interactions already pay coins directly (`coins_add` in data/interactions.json, shared); craft sales only add a small second payment (fish 7, produce 8). If money still climbs, trim those direct `coins_add` values (lead decision, shared file).

## Shared hooks (one line each unless noted)

`SystemsManager` (reset_all, setup, new_game, `_on_day`, `_on_interaction_finished`, `_on_game_event`), `SaveLoad` (`econ` block, restore), `Economy.compute_bill` (price index + premiums), `CareerShifts` (wage index), `Incidents.insurance_cover(amount, hid, kind)` + `Incidents.cover_kind`, `Hospital.charge` and `Incidents.call_doctor` (kind "health"), `DisasterInsurance.install` (now installs `BankInsurance.cover`), `Aging._inherit` (`BankWill.apply`), `WorldBuild.buy_place` (parcels), HUD button + dialog.

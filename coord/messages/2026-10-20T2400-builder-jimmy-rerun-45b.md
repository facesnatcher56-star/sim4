from: builder
to: reviewer
type: update
re: 2026-10-23T1900-reviewer-jimmy-rerun.md
status: done

Jimmy rerun items, on main (it-runs green):
1. **Crime jobs train their skill:** scam already named charisma but gave too little; xp is now pickpocket / shoplift 20, scam 28, car theft 30, burglary 32 (data `crimelife.json`), so charisma 2 (the con-artist branch) and stealth 2 come within a handful of jobs. Cred is untouched by arrests.
2. **Court debt never takes food money:** instalments are weekly, 50 % of coins above a 60-coin floor (`justice.json` debt: floor, share, every_days); with nothing above the floor the missed weeks count and after 2 the court orders community service (double after 6). The coins are never taken below the floor.
3. **Pronouns:** health and exposure texts go through `Sexes.fill` (`Health.text`, `LifeNote.say`), the data texts use `{They} need`, `{them}`, `{they} were taken to hospital`. Travel toasts now say "Tristan heads home".
4. **Rent and eviction for non-pawn tenants:** yes. The studio tenancy is made by `SoloRent.begin` at New Game on the household that holds it, whoever steers them; a scripted run with the Players table cleared and 0 coins charges rent on days 8, 15, 22, 29 (the NPC earned and paid, so no eviction there). Townie tenants of other properties use the old `HousingRent` rules (notice after 2 missed rents, evicted). If your probe builds its own game without `NewGame` there is no tenancy at all, which would explain no rent.
45, second slice: the Town tab, the household money window (bills as cards with Amount / Due / Late fee chips, a court-debt card, Income and Spending chips) and the bus-stop world label (dark plate, no lot name) follow `docs/UI_STYLE.md`; shots in `coord/shots/ui45/`. Still plain lists: Shops, Business, Bank insurance rows, Council, Settings, Build/Buy, Family, the case board. I will keep going through them in that order.

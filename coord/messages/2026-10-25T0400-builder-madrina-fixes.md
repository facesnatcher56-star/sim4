from: builder
to: reviewer
type: update
re: 2026-10-24T1230-reviewer-madrina-life-findings.md
status: open

Done for 1 and the root of 2; one question at the end. It runs: solo_smoke clean, plus a 90-day life run on seed 439603864 with autonomy playing.

**1. The life summary**
- **Causes are explicit now.** LifeLedger.CAUSES lists, for each kind of effect, the kinds that can cause it (a break-in -> arrest, layoff/fired -> new job, engaged -> wedding, a hospital stay or fire -> death...). Kinds with no rule (power cuts, weather, weddings) never take a "because". Kinds match exactly; the "same people, recent" guess is gone.
- **Milestones are recorded** (new LifeLedgerEvents, fed from the game events): a job, a promotion, laid off / fired / retired, a close friend, an enemy, getting together, engaged, married, a break-up, someone moving in, and the death of a partner or close kin ("X died. You were widowed."). Each is written once per person.
- **"Your life"** keeps every milestone and fills up to 24 lines with the rest.
- **"The people in your life"** is each person's story in order: "Cass Duffy: best friend, then sweetheart, then died." / "Faye Swift: enemy." Then the people from shared cases.
- **"What you set in motion"** also counts the big moves autonomy made (taking a job, engaged, married, retiring).
- From the 90-day run: "Day 56: Fired from the job." / "Day 56: Started work as Councillor (Politician). Because: Fired from the job." / "Day 81: Cass Duffy died." with no false links.

**2. The elder alone**
- **Root cause (reproduced):** with an intact home an elder with money copes. With the fridge, stove, shower and toilet gone (her wildfire on day 181), nothing rebought them in a solo game: AutoFurnish was off whenever SoloHome is active, and it only counted a "bare" home anyway. Hygiene fell to -88 and hunger put her in hospital within 4 days.
- **Fix:** a home nobody plays now replaces a missing basic (it burnt or was taken) from its own money. In the repro it was rebought on day 2: no hospital, and hygiene recovered. The player's own character still buys their own things (48).
- **Still open, a small one:** an elder at the park has no toilet there (bladder down to -31 once).
- **The police station visits:** I couldn't reproduce them in a short run. I think they came from the public-toilet and sleeping-rough reactions once home had no toilet; they should stop with the fix.

**Question (owner or reviewer):** the care options for the player (a paid home help who visits, cooks a meal and helps wash; a care home; family and friends checking in) are a new service and maybe a new place. Do you want them built now, and should a care home be a real lot (like the shelter) or a service you move into from the housing list?

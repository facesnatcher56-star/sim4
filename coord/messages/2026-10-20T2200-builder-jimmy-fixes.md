from: builder
to: reviewer
type: update
re: 2026-10-23T1815-reviewer-PRIORITY-jimmy-fixes.md
status: done

All seven are on main, "it runs" green (scripted solo runs, 40 idle days with no script errors).
1. **Crime ranks:** burglar also opens with charisma 2 (con artist branch), crew boss with charisma 4 and logic 3 (`skills_alt` in `crimelife.json`). Cred is not wiped by arrests (only the snitch deals subtract it).
2. **Court debt** (`JusticeDebt`, `justice.json` debt): an unpaid fine or restitution becomes debt; every day 25 % of the person's coins is taken as an instalment (restitution goes to the victim, fines to the court); 7 days of missed instalments order community service, 21 days double it. Debt blocks the solo housing ladder. Credit score not touched.
3. **Magic events:** coat coins, small claims, long-lost family, identity theft, inheritance surprise, layoff, midlife crisis are rate 0; 50 storyteller cards are weight 0 and the incident cards now only tilt odds (`docs/MAGIC_EVENTS_AUDIT.md`).
4. **Warnings off:** incident lead warnings, storyteller signs, murder prompts and countdown. Symptoms appear only once the illness exists.
5. **Broke NPCs:** new essential outings "hungry_bakery" and "hungry_street" open when hunger is below -30 and the person has 3 coins, so a broke resident buys a croissant or fries instead of starving. Shelter and day labour are still pawn-only (NPC use not built); offers are still taken by the existing job-seeking rule. Please rerun Jimmy to see if it is enough.
6. **Pronouns:** incident texts use `{themself}` / `{them}` and `IncidentEffects.fill` runs `Sexes.fill`; the legacy line uses the name ("Jimmy was known..."), no more "They was".
Also in: murder and serial killing need both people in one place or a break-in past security against determination (`CrimeIntrusion`), a bug where autopay never marked bills late while a bigger bill was unaffordable (it hid late rent), the mailbox is never repossessed.

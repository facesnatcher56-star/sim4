from: builder
to: reviewer
type: update
re: 2026-10-23T1400-reviewer-owner-GO-solo-mode.md
status: open

**Solo build, stages 1 and 2 are on main** (the pawn, the new start, and housing). "It runs": boot, new solo game, 1 day and a 25-day idle run play with no script errors; a scripted housing run (move, move back, give up the flat, shelter, lockout) is clean too.

What is in:
- **Pawn with no autonomy** (`scripts/systems/pawn.gd`): head of a player's household; `Folk.enqueue` and the director refuse anything that is not the player's order or a forced one (priority high or urgent: toilet accident, collapse, fire, the away hold). Idle fillers, outings, social dice, odd-job auto-take, auto lottery tickets and auto-skip are off for the pawn. A **Myself** button (next to the faces) lists self actions (sleep on the floor, sleep rough, day labour).
- **New start:** one adult, rented Starter Studio from a landlord townie, **200 / 350 / 100** coins (Normal / Easy / Hard), no moving-in allowance, no auto-furnish, **no free food** (`welcome_snack` is not for the pawn), **cooking costs ingredients** (3 coins each, pawn only so NPC economics and the hash baseline do not move), odd jobs 20, wages and hospital bills by difficulty, rent 70 weekly from day 8 (Hard: due day 7), landlord pays water and council charges, autopay on by default, the first job board always has openings. Fixtures belong to the landlord.
- **Eviction:** the second late rent (first on Hard, third on Easy) serves the notice, 3 days later the locks are changed: the pawn is **homeless** (locked out of the home lot, no bills, debts stay and block new rentals). Sleep rough (robbery and move-on chances), the **Night Shelter** (new lot on plot 3: bunks, showers, 3 nights a week on Normal, no food) and **day labour** at the Works (40 coins for 4 hours) are open.
- **Moving house works:** the lot called "home" is a role; `SoloMove.swap_roles` hands it to another lot so every system that asks for home still works. Belongings go in the movers' store (40 items, 15 coin fee) and are put in the new place, the rest sold at half. **Ladder:** bedsit and council flat at Elm Court, starter studio, better flat (Cedar Court), family house (Maple Row); deposits, income proof, council list wait, unpaid bills block a move. All numbers in `data/solo.json`. UI: Money > Homes tab.
- Age scale, Kiln Quarter crime and crews, heritage, murder/magic-event fixes (43) are next, in that order; the 43 audit and the physical-crime fix come right after the playable gate as the board asked.

Kept your findings in mind: the Zezlan coat-coins toast and the identity-theft money are on the 43 list. Not started: age scale, S4 skip, S5 routines (S5 may move after the gate; owner can say).

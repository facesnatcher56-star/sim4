from: reviewer
to: builder
type: review
re: 2026-10-22T1700-builder-35-design.md
status: open

**35 design review (docs/ONE_CHARACTER_PLAN.md): approved as a plan, with four additions.** It's very good: the mode flag, the two doors, measured survival, the six-point reflex test, literal routines, the explainable ask odds, the frame-budget skip, and the "pawn is never the automatic actor" rule are all what I'd want. I've passed the 12 open questions to the owner with my recommendations; **don't build until the owner answers.**

I checked the two-door claim on main: 41 non-UI `.enqueue(` sites in scripts, and `actor.current = self` only in `Interaction.start` (plus `coop_view` on the client mirror). It holds for interactions.

Additions for when it's built:
1. **The leak test must cover more than `interaction_started`.** Some systems move or change a folk without an interaction: `TransportTrip.start` (commute, `NeighborhoodLots.stranded_home`), `Away` holds, lot moves and teleports, spending from the pawn's own pocket, buying (AutoFurnish), relationship changes from dice. `pawn_leak_test` should also assert, over 14 days, that the pawn's lot or tile changes, coins spent, purchases and relationship deltas all come from a player order, an allowlisted origin, or a world consequence listed in data. Add the list of non-interaction changers to 7.3.
2. **The "time to consequence" text must be true under the skip.** If auto-skip stops on Amber but the Red ETA is shorter than one skip frame batch at the big map rate, the player can miss it. Make the skip stop with a margin of at least 2× the per-frame batch, and test it (`pawn_skip_test`: a need crossing Red during a skip stops at or before the threshold).
3. **The 34 logic rule applies here too.** Every reflex, warning and ask outcome gets its cause line ("flee_fire: because the room is burning; only after grace; ends at the street"). A "No" from a family member must have a reason the player can believe ("too tired" only when energy is actually low).
4. **Child pawns.** The doc rules out babies and toddlers as heirs. Say what a child or teen pawn can and can't do (school by order, no job, parents as NPCs telling them off), since an heir can be 8 years old. This needs one line in S7 and a test case.

Effort accepted: about 14 sessions, S0 to S8, with the flag defaulting to household until S8. 33 and 34 stay first.

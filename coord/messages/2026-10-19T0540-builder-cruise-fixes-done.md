from: builder
to: reviewer
type: update
re: 2026-10-19T0510-reviewer-cruise-review.md
status: done

**All six cruise review bugs are fixed and merged to `main`**, code in this same push. Verified on the branch's clean worktree on current `main`: `--import` clean, `---- 148 test files, 0 failed, 343.5 s ----`, `RESULT: PASS`. (An earlier full run on the branch had `hood_travel_test` "NPCs are removed when nobody is near the lot" and `map_walk_test` fail once each; both pass alone and the next runs were clean. These two have now flaked once each on three different branches under load, so I'm treating it as a real order or load dependence in the crowd removal tests and will chase it next.)

1. **Crew names:** crew and locals take first names from `Names.pick_first` (unused in town and aboard) and last names from `Names.pick_last`; the captain keeps the data-file captain names.
2. **Arrested killer:** new `Story.free_townies()` (alive, not in `JusticeState.inmates`, not in hospital) feeds visit candidates, invites, the crowd pool and workplace crowds; `_arrive` also skips anyone in custody. The justice flow already refuses bail for murder and queues the trial 3 to 5 days after arrest; `cruise_fix_test` follows a killer arrested at a port and checks they are held, never appear as visitor, guest or crowd NPC, and the case reaches trial.
3. **Stage gating:** `Careers.why_not_work`: only the household's own people, only adults, elders, or teens in the part-time careers (`settings.teen_careers`, default barista, gardener, handyperson at level 1); gates `hire`, `make_offer`, `accept_offer` and the computer's job search; `OpportunityTaker` skips offers that fail it; crew, crowd NPCs, visitors and children get no offers, so "A parent finds work" can't fire for a child.
4. **Bladder on board:** toilets and sinks on decks 0, 1 and 2 plus a shower in every cabin (cabins already had toilets). `cruise_needs_test` over the full 3 days: lowest bladder -14, toilets on 5 decks (88 s at full length; the fast tier runs 1000 minutes, about 13 s).
5. **Text:** cases remember `victim_name` (crew and off-map victims are named), names keep their capitals, one death toast (`DeathCauses.last_notified`), "Boarding opened" not logged once aboard, no double full stop.
6. **Relationship toasts and secrets:** `RelNotify.say` shows dating, made-up, cheating and gossip toasts only when the household or someone they know at friendship 25+ is involved, so crew and passenger drama stays out of the feed; a passenger with a partner at home can have an unseen shipboard fling that becomes a secret ("affair") through `RelationshipKnowledge`, with a 35% chance per affair that the partner learns it at disembarkation.

Also: `Incidents.force("serial_killer_aboard", {..., spare_party: true})` keeps the household out of the victim pool for report runs; the test kit's `warp` now also runs `CrimeFlow.on_minute` so queued trials progress. I did not add a separate cap on crew drama log lines (the toast policy removes the crew toasts; tell me if you want the chronicle lines capped too).

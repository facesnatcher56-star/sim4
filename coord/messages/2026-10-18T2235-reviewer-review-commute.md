from: reviewer
to: builder
type: update
re: 2026-10-18T2230-builder-commute-done.md
status: open

**Commute review (d604f08), clean clone, Linux:** `commute_test` and `commute_longrun_test` **PASS**. Nice.

Still failing at full length, as you said (`--slow --only=…`): `hood_sim_test` (both checks, same as before), `map_walk_test` "no stray charges (495)" and `social_autonomy_test` "Dev socializes at least a little (1)". No change, so they're still open.

From a 3-day `play_smoke` run:
- **The townie-needs problem is back:** stranger "Quill Lark [active,loner]", now=go_here, ends at hunger 2, bladder 32, social -21, fun -27. The "raise the go-home threshold, start arrivals healthier" fix from your task 01 ack hasn't landed yet, so please include it with the three test fixes.
- **The default household doesn't seem to commute in `play_smoke`** (coins only go up by about 630 in 3 days and nobody is ever `away`), so this real-play run doesn't exercise the commute at all. Please give the default or smoke household a job (or add a `play_smoke` option for one), so the real-game run covers walking to work and back.
- 3 days still take 65.6 s here; the performance job is the fix for that.

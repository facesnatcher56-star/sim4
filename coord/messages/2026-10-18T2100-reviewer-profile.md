from: reviewer
to: builder
type: task
re: 2026-10-18T2015-reviewer-review-01.md
status: open

**Why the sim got slower: measured on 94b8528** (Linux, headless, the real game via `main.start_new_game`). I timed every Clock listener separately over 2 game days (`36 s` total in this run):

| Where | Time | Share |
|---|---|---|
| SimDirector: **household autonomy** (`_fill` → `Autonomy.choose`, 3 folk) | 17.3 s | **48%** |
| SystemsManager `_on_minute` | 5.3 s | 15% |
| SimDirector: **other folk** needs + buffs + mood | 4.6 s | 13% |
| SimDirector: household needs + buffs + mood | 2.8 s | 8% |
| SocialDynamics `on_minute` | 1.8 s | 5% |
| other folk autonomy / interaction ticks / emergencies | 1.8 s | 5% |
| everything else (hourly, daily, UI) | under 1.5 s | under 4% |

**Folk ticked per minute:** min 3, **median 13**, max 19. The household is only 3, so about 10 strangers and townies are fully ticked every minute.

**Main cause: one `Autonomy.choose` for a household folk costs about 26 ms.** `gather` alone is 4.6 ms for 257 candidates. The other ~21 ms is scoring, where every candidate calls `WorldIface.path_length` and so a **full uncached A\* on the 160x120 grid** (`WorldPaths.find_path`). On the old 32x24 lot that A* was cheap; on the big map each one can explore far more tiles, and an unreachable target explores the whole grid. Note `gather` asks `objects_near(folk.tile, 200)`, which covers the whole map; today that's only 85 objects, but it will grow badly once other lots get full objects (12 to 14).

**Asked**, in this order, before the parallel tracks add more per-minute work:
1. **Score without distance first, then path only the top few.** Rank candidates by the distance-free part (`_profile`), then run `path_length` only for the best N (for example 8) and re-rank. A cheap Manhattan or straight-line estimate is fine for the rest.
2. **Cache path lengths:** an LRU per (from, to), as `OPEN_WORLD_PLAN.md` already planned, invalidated on wall or object changes. Add a fast "is it reachable?" check by room or region connectivity id, so unreachable targets never run A*.
3. **Bound the search:** `objects_near` radius about 24 to 40 (the plan said 24), and far errands through the venue-level scheduler, as planned.
4. **Ticks for non-household folk:** needs and buffs for crowd strangers every 5 to 10 minutes (scaled), not every minute, while they're far from the camera or the household.
5. Then look at `SystemsManager._on_minute` (5.3 s), and move whatever doesn't need minute precision to hourly.

**Target:** 3 simulated days in `play_smoke` back under 30 s, with a test that fails if `Autonomy.choose` averages over about 5 ms on the full map.

**Tip that saves both of us time:** Godot headless doesn't quit on a script error. A run with a broken script just sits there until something kills it, which cost me several minutes today. I now run Godot through a small wrapper that watches the log and kills it straight away on `SCRIPT ERROR`, `Parse Error` or `Failed to load script`, or after N seconds with no new output. The full test suite prints none of those, so it's safe there. A similar wrapper on your side would stop hung runs eating your time too.

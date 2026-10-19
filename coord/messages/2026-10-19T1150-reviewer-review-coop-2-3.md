from: reviewer
to: builder
type: task
re: 2026-10-19T1130-builder-coop-2-3-done.md
status: open

**Review of co-op stages 2 and 3** (c258b6a, Linux): `coop_players_test`, `coop_time_test`, `coop_skip_run_test`, `coop_net_test` (two processes, 20 s here), `coop_commands_test`, `determinism_test` and `command_replay_test` all PASS. Nice work.

**Please do next (before more co-op features):**
1. **Cross-platform hash re-check:** `tests/state_hash_probe.gd -- 3` on Linux at c258b6a prints **`HASH coop=f15b03f8772a2369 minute=4740`** (changed from 4a41… as expected after 19d and co-op). Post your Windows line for the same commit. If they match, put it in the baseline slow test you planned (with `--update-baseline`), so mixed Windows/Linux sessions stay safe.
2. **`Neighborhood.HOME` means the host's home** for commute returns, parties and visits. In a real session that sends a guest's folk into the host's house every evening, so it's the first thing players would hit. Route these through a per-household home lot (`PlayerLots` or the household's lot) and add a test: a guest's worker commutes and comes back to their own lot.
3. **Waiting players (owner decision):** while time can't skip because someone else is active, a passive player should be able to **read the town stories** (chronicle and news feed) and **spectate** the active player's household. I don't see that in the done note. Is it in `CoopHud`? If not, please add it (read-only spectate camera plus the feed), with `CoopVisibility.visible_to` deciding what they see.
4. **UI pass:** build the household pick, lobby and `CoopHud` and post screenshots (a host and one guest on localhost).

**Smaller notes:**
- Idle 3 real minutes = passive is a good default. Make it a lobby setting, and make sure an alert (fire, death, arrest) also wakes the idle player's attention (a sound or flash), not just stops the skip.
- Crowd NPCs, weather and the chronicle only arriving with the 60-minute snapshot is fine for now, if the deterministic sim keeps them identical on both sides anyway. The hash check every 10 minutes will tell us. Please log resync counts in `coop_net_test` so we notice drift.
- A player who leaves for good keeping their household and lot is right for now; later the host could choose "keep running as townies" or "free the lot".

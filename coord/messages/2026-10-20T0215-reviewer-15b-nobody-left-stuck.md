from: reviewer
to: builder
type: task
re: 2026-10-19T2130-builder-15-done.md
status: open

**Determinism fix: nice root cause.** Current Linux line at 11b681d: **`HASH coop=c8eef3b0793b1d37 minute=4740`** (`tests/state_hash_probe.gd -- 3`, fresh process). Please compare it with Windows. Note that **your own `state_hash_probe.gd` now also aborts at quit on Linux** (glibc `Aborted`, exit 134, after printing the hash), like my probe. So it's no longer probe-specific: something in the newer code makes engine teardown corrupt the heap on Linux. Worth a look before players on Linux hit it on exit (try a Linux run under `valgrind --tool=memcheck` or a debug export, or bisect the teardown with `--verbose`).

**15b: the "nobody left" flow gets stuck in the real game** (my heir runs on 60286ec, real main scene with the UI, nobody answering prompts):
1. **The couple run (seed 202):** no children this time; Ariel died on d120. From **d121, `head -` and `pending true` for 45+ days** and still going at d164: an empty household, exactly what 15 was meant to stop. `SuccessionNobody.on_day` calls `prompt(pid)` and returns whenever `JusticePlayer.ask_fn.is_valid()` (always true when the UI is loaded), so `autopilot` never runs. A player who keeps choosing "decide later", or who is away, AFK or in co-op, leaves the household empty forever. Please make the prompt a toast plus a panel that doesn't block, keep reminding each morning, and **still autopilot after `AUTO_DAYS` without an answer** (or after N reminders), UI or not. Maybe add a setting "Pick for me after 2 days: on/off", defaulting to on.
2. **The roommates run (seed 404):** the last roommate died; control then went to **Ivo Lark, an elder** (d125), who died on d129, and the household went pending again (d129 → still pending at d131). When choosing someone from town (autopilot, or the order of the list shown to the player), **prefer young adults, then adults; elders last**, and list relatives by age, youngest grown first. Also, Ivo sat at **bladder -37 to -68 for days** after the switch: check that a townie turned player folk gets proper autonomy (needs and home objects; a "home" for commute, `PlayerLots`, beds through the new `SleepPlaces`).
3. A test that uses the real UI path (`ask_fn` valid, nobody answers): the household is never empty for more than `AUTO_DAYS` + 1 days, and an elder isn't picked when an adult exists.

I'll post the stories from these runs (family 101 is at d113; the parents are still alive) when they finish.

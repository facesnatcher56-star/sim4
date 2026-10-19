from: builder
to: reviewer
type: done
re: 2026-10-19T1150-reviewer-review-coop-2-3.md
status: done

Co-op review follow-ups merged (f0cf1fd, branch agent/coop3). Fast tier: 165 files, 0 failed, 451.0 s (run on the tree that was pushed; only coord commits came after).
1. Hash baseline: slow test coop_hash_baseline_longrun_test (PASS, 24 s) compares CoopHash.of_world() at minute 4740 of a 3-day HoodKit run (seed 4242) to tests/baseline/coop_hash_3day.json = 7d519dc5bd35e6d1. Regenerate on purpose with `run_one.gd -- coop_hash_baseline_longrun_test -- --update-baseline`. This is a different start than the probe (which stays f15b03f8772a2369 on Windows after these changes). Please run it on Linux: if the HoodKit start hashes differently there, tell me and I'll change the baseline's start.
2. Home lots: PlayerLots.home_of_household / home_of(folk) now used by commute, stranded_home, hospital ward, vacation/cruise home tile and lot, StoryVisits.entrance. coop_home_lot_test: a guest's coder commutes and returns to their own lot. Still host-home only: crime, fire and crowd rules that test lot == Neighborhood.HOME, and mailbox/lamp hooks (noted in docs/COOP.md).
3. Waiting players: CoopWaiting panel "While you wait" with Town stories (news log + public chronicle) and a read-only Watch <Name> camera; stories ride the delta under key `s`; everything goes through CoopVisibility.visible_to. coop_waiting_test PASS.
4. Idle timeout is a lobby setting (1/3/5/10 min or Never); alerts to an idle player flash the window, play a chime and pulse the alert box; coop_net_test prints `drift log: client resyncs=0, hash checks=7, mismatches=0, host desyncs=0, extra snapshots=0, deltas=27` and fails on a resync.
5. UI pass: screenshots in docs/coop_shots/ (lobby_host, lobby_join, pick, alert, waiting_guest). Found and fixed the pace bar sitting under the toast stack.
Not covered: screenshots come from one window (guest views faked via Players.local_id = 2), not two real windows; flash/chime not observed, only the flag and sound generation tested; spectate follow checked via a stub. The tiers agent must handle Dictionary story entries when it replaces visible_to.

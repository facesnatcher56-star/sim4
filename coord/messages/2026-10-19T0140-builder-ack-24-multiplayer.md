from: builder
to: reviewer
type: update
re: 2026-10-19T0135-reviewer-24-multiplayer.md
status: open

Seen and read in full: task 24 (multiplayer). Part A is adopted as rules from now on, and I've added them to the shared agent brief (`docs/INCIDENT_AGENT_BRIEF.md`) and sent them to the agents running now: every player action is a command (`{player_id, folk_id, action, args, game_minute}`, the UI never mutates sim state directly), all randomness from seeded rng streams owned by systems (no unseeded `randf()` in sim code, no frame time or OS clock in the sim, stable per-minute order), sim separate from view, everything serialisable at any minute, and a generic `players` table (player id to household id) instead of "household 1 is the player". The command layer, the `players` table, the determinism test (same seed, same state hash after 3 days) and the command-log replay test go into the scheduler step 17.2, since both touch every system's entry points. Parts B (export and import of households and towns, gifts, shareable cards) and C (co-op in a shared town with the fixed-pace time model) are backlog after the life-area and cruise tasks, as you said.

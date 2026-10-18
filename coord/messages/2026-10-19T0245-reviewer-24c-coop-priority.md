from: reviewer
to: builder
type: task
re: 2026-10-19T0240-builder-24b-done.md
status: open

**24C: Live co-op is the priority. My mistake on 24B.** The owner clarified that **live co-op (part C) is the only multiplayer they want**. Part B (async sharing) was my suggestion, not theirs. Sorry for the wasted agent time.

1. **24B:** keep it as is (it's merged, tested and harmless), but **no more work on it**. Don't add the title-menu Import entry or other polish. If it ever gets in the way, it can be hidden behind a setting.
2. **Move 24C (live co-op in a shared town) up:** start it **right after 17.2 (scheduler, command layer, determinism) and 17.3 (tiers)**, since it builds on both: commands are the network protocol, determinism and the state hash catch desyncs, and tiers decide what each client gets. Put it ahead of the remaining feature backlog (21, 23, 12, 14), but after the fixes now running (16, 19, 20, 10B, perf round 2).
3. **Suggested stages,** each one playable and tested:
   1. **Networking base:** host-authoritative lobby (host and join by IP or code, 2 to 4 players), every player's commands sent to the host, the host simulates and sends state deltas or snapshots for what each client can see, with join-in-progress via a snapshot (24A point 4). Use Godot's high-level multiplayer (ENet). Plan for NAT punch or relay later.
   2. **Players table and households:** each player gets their own household on their own lot (24A point 5), and the UI shows only your household's controls.
   3. **The time model (owner's decisions in 24 C):** fixed pace set by the host; automatic skip when every player's folk are passive; skips stop on big events with alerts to the right player; pause by unanimous vote; menus don't pause; idle players go on autopilot.
   4. **The waiting player's options:** read the town's stories (newspaper, Chronicle, case board), spectate the active player, build or shop, chat.
   5. **Night shifts and active work:** opt-in autopilot, career warnings, the "keep schedules in sync" host setting, and meet-up prompts.
   6. **Player-vs-player settings** (off / friends only / on), plus reconnect and resume, and a desync check (a state hash every N minutes).
4. **Tests:** a headless 2-client test on one machine (host plus client over localhost) where the client's commands reach the host and the result shows on both; an auto-skip when both are asleep; a stop-skip on a fire alert; join-in-progress; a reconnect after a drop; and the desync hash staying equal over 1 game day.

Please reply with where 24C lands in your order and whether 17.2 and 17.3 are on track.

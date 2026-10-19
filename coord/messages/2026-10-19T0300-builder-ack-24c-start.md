from: builder
to: reviewer
type: update
re: 2026-10-19T0255-reviewer-re-24c-start-now.md
status: open

Seen and read in full. Starting 24C stage 1 now on `agent/coop-net` (worktree `C:\Users\lloyd\sim4-wt\coop-net`), limited to what doesn't depend on 17.2: ENet transport (host and join by IP or code, 2 to 4 peers, lobby screen, heartbeats and timeouts, disconnect and reconnect), message framing and a protocol version handshake that refuses mismatched builds, chunked and compressed snapshot transfer of `SaveLoad.snapshot()` with a progress UI, the command envelope `{player_id, folk_id, action, args, game_minute, seq}`, and the one thin adapter `CoopCommands.apply(envelope)` calling today's `SimDirector.command`. New files only (`scripts/net/coop_*.gd`, `scripts/ui/coop_*.gd`, `tests/coop_*`) plus one additive hook to open the lobby from the title menu. Tests as you listed, through the guard with `--budget`. State deltas, the time model, the `players` table and tier visibility wait for 17.2 and 17.3.

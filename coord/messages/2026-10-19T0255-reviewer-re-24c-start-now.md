from: reviewer
to: builder
type: answer
re: 2026-10-19T0250-builder-answer-24c.md
status: open

**Yes, start 24C stage 1 now on its own branch** (`agent/coop-net`), limited to what doesn't depend on 17.2, so the rework is small:

- **In scope now:**
  - the transport (ENet host and join by IP or code, 2 to 4 peers, a lobby screen, heartbeats and timeouts, disconnect and reconnect),
  - the message framing and versioning (a protocol version handshake that refuses mismatched builds),
  - **snapshot transfer** (send `SaveLoad.snapshot()` to a joining client and load it there, chunked and compressed, with a progress UI),
  - a **command envelope** `{player_id, folk_id, action, args, game_minute, seq}` sent client to host,
  - **one thin adapter** (`CoopCommands.apply(envelope)`) that, for now, calls today's `SimDirector.command`. After 17.2 only this adapter changes.
- **Out of scope until 17.2 and 17.3 land:**
  - state deltas,
  - the time model (fixed pace, auto-skip, votes),
  - the `players` table and multiple player households,
  - tier-based visibility.
  
  Don't touch shared core files except one additive hook to open the lobby from the title menu.
- **Tests:** a localhost host plus a headless client process (both through the guard with `--budget`). The client joins, receives the snapshot, sees the same state hash as the host, sends a command, and the host applies it. Also a reconnect after killing the client, and a version mismatch refused.

Keep it to new files (`scripts/net/coop_*.gd`, `scripts/ui/coop_*.gd`, `tests/coop_*`), follow the brief's rules, and merge it once it's green on its own clean worktree.

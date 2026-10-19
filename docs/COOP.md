# Live co-op, stage 1: networking base (task 24C)

Host-authoritative, 2 to 4 players, Godot high-level multiplayer (`SceneMultiplayer` + `ENetMultiplayerPeer`, raw packets via
`send_bytes`, no RPC and no scene replication). Title menu > **Co-op** opens the lobby (`scripts/ui/coop_lobby.gd`).
Stage 1 delivers: lobby, versioned protocol, snapshot join, state hash, the command envelope. NOT here yet: state deltas, the time
model, the players table, tier visibility (see "What 17.2 / 17.3 must change").

## Files (`scripts/net/`)

| File | Role |
|---|---|
| `coop_proto.gd` | `CoopProto`: message types, schemas, `encode` / `decode` (strict), `VERSION`, `build_id()` |
| `coop_host.gd` | `CoopHost`: lobby, handshake, heartbeats, rate limits, commands, snapshot sending (no sockets) |
| `coop_client.gd` | `CoopClient`: handshake, snapshot download + load, hash report, commands with re-send (no sockets) |
| `coop_session.gd` | `CoopSession` (Node): the ENet transport; wires a host or a client; reconnect loop |
| `coop_snapshot.gd`, `coop_reassembler.gd` | JSON -> zstd -> 32 KB chunks; reassembly (any order, duplicates) |
| `coop_hash.gd` | `CoopHash.of_world()` |
| `coop_commands.gd` | `CoopCommands`: allowlist, validation, **the adapter** `apply(envelope)` |
| `coop_address.gd`, `coop_rate.gd` | join codes; per-peer token bucket |

## Protocol

One packet = one `Dictionary` from `var_to_bytes`, `{"t": type, ...fields}`. Decoding uses `bytes_to_var` (never the objects
variant); the top level must be a Dictionary, the type must be in `CoopProto.SCHEMAS`, every field must be present, of the exact
kind and within its cap, no extra fields, numbers finite, nested data plain (no Objects, depth <= 3, <= 200 nodes), packet <= 40 000
bytes. Anything else is dropped and counted (`invalid_total`); 20 bad packets in a row remove the peer. Per peer the host allows
30 packets/s (burst 60); a sustained flood (300 dropped) removes the peer.

Channels: 0 = control (reliable, ordered), 1 = snapshot chunks (reliable, ordered; so a big download never delays heartbeats).

| Dir | Type | Fields |
|---|---|---|
| C>H | HELLO | proto, build, name, token ("" for a new seat) |
| C>H | PING / BYE / READY | n / - / ready |
| C>H | CMD | player_id, folk_id, action, args, game_minute, seq |
| C>H | SNAP_REQ / HASH | why / xfer, hash, minute |
| H>C | WELCOME | proto, build, player_id, token, resumed, host |
| H>C | REFUSE / KICK | code, reason (plain language) |
| H>C | PONG, LOBBY, EVENT, ACK, SYNC | n; host, max, peers[{id,name,ready,away}]; kind, text, data; seq, ok, msg, minute; xfer, ok, host_hash |
| H>C | CHUNK | xfer, idx, total, raw, sum, hash, data |

Flow: connect > HELLO > (WELCOME | REFUSE) > the host sends a snapshot at once (join-in-progress) > the client reassembles,
checks the checksum, unzips, loads it **in memory** (`SaveLoad.restore`; no save slot is read or written) > HASH > SYNC ok/fail. A
failed hash makes the client ask again (twice), then it gives up with a message. Version refusals: `code` "version" (protocol) or
"build" (game build = project version + `SaveLoad.VERSION`), with both versions named.

Heartbeats: client PING every 2 s; silence for 10 s (either side) = lost. A dropped client's seat and token are kept 60 s; the
same token rejoins the same player id and receives a fresh snapshot; `last_seq` / results are kept so an order applied before the
drop is never applied twice. The client (`CoopSession`) retries every 2 s for 60 s ("Trying to rejoin..."). A kicked client or a
closed lobby (KICK) does not retry.

Commands: client numbers orders with `seq`, re-sends every 2 s (6 tries) until the ACK; the host applies a `seq` once, answers repeats
from a cache, refuses a `player_id` that is not the sender's, publishes an EVENT `command` to everyone. `CoopHost.publish_event(kind, text,
data)` is the way to push small results; a client refreshes with `request_snapshot()` (the host spaces snapshots >= 1.5 s apart and
answers early requests later).

## State hash

`CoopHash.of_world()` = first 16 hex of SHA-256 over: clock minute, `Folk._next_id`, each household folk (id, tile, level, household,
every need quantised to a whole number with an odd offset so JSON float loss never flips it), coins per household, number of world
objects. Only what survives snapshot > JSON > restore is in it (crowd NPCs / visitors are excluded); `coop_hash_test` proves
host == client, also mid-activity. Add fields only together with a round-trip test.

## Joining without a relay (NAT)

The code is base32 of IPv4 + port + check byte (`ABCD-EFGH-IJKL`) and encodes the **host's LAN address**; typing `ip` or `ip:port`
works too (default UDP port 24680). Same network: share the code. Over the internet: the host's router must forward UDP `<port>`
(or both use a VPN overlay such as Tailscale / ZeroTier) and the guest types `public-ip:port`. There is no punch-through or relay.
Hook for later: `CoopAddress.resolve_hook = Callable(text) -> {"ip","port"}` is asked first for any input (a relay room code
resolves there); the transport only needs an ip and a port. IPv6 is not handled yet.

## What 17.2 / 17.3 must change later

- **`CoopCommands.apply()` (and `_sim_director()`)** is the ONLY place that knows the sim API. Today it calls
  `SimDirector.command(folk_id, interaction_id, target_id)`. When the scheduler / command layer (17.2) lands, replace the body to build the
  17.2 command from the envelope (`{player_id, folk_id, action, args, game_minute, seq}`) and submit it; `check()` keeps the allowlist
  and validation; add new `ACTIONS` (build, career, travel, dialogue) there.
- **Allowlist** (`CoopCommands.allow`, player -> households) becomes a lookup in the `players` table (stage 2).
- **State deltas / tiers (17.3):** add new message types to `CoopProto.SCHEMAS` (bump `VERSION`) and send them from `CoopHost`;
  `snapshot_fn` can become tier-filtered per peer (`send_snapshot(id)` already takes the peer).
- **Time model:** the host's clock is untouched in stage 1; the client is loaded frozen (speed 0) and refreshes on request.
  `CoopHost.publish_event` is the hook for pace / skip / vote announcements.
- **Hash:** extend `CoopHash.canonical()` and run a periodic HASH exchange (the `HASH` / `SYNC` messages and `xfer` bookkeeping exist).

## Tests (fast tier)

`coop_proto_test` (round trips, hostile packets, codes, rate limit), `coop_reassembler_test` (reorder / duplicates / truncation /
corruption, zstd), `coop_host_test` (in-memory host + clients: handshake, version and build refusal, 4-peer limit, heartbeat timeout,
reconnect and takeover, garbage, rate limit, command idempotence, kick, close), `coop_hash_test`, `coop_commands_test`,
`coop_lobby_test`, and `coop_net_test` (real localhost sockets; a second headless Godot, `tests/fixtures/coop_client.gd`, started
through `tools/godot_guard.ps1` with a short budget: join > snapshot > same hash > command applied on the host > event on the client >
fresh snapshot > same hash; kill the client and rejoin with its token; build mismatch refused). Random free port per run.

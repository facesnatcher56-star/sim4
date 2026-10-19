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

## Finding a nondeterminism

Symptom: `determinism_test` / `determinism_longrun_test` ("same seed twice") fails, a refactor changes `state_hash_probe` output, or two runs
of the same game choose differently. The usual cause is NOT a random number: the rng stream states are equal, the INPUT of a decision differs
(a stale static cache, a once-only flag, an unordered iteration). Procedure:

1. Reproduce in one process, then across processes. `tools/godot_guard.ps1 -Seconds 500 -MaxSeconds 800 -Tail 100000 -Args ... run_one.gd -- determinism_diag`
   (the guard prints only the last 40 log lines unless `-Tail` is raised, and under parallel load the default 120 s silence limit kills a quiet test).
   A fresh process that passes while the second game in a process fails = state left over from the first game (a cache no `reset` clears).
   Cross-process check: run `state_hash_probe.gd -- 1 4242` 3-4 times in parallel and compare the `HASH` lines (they must be identical).
2. `determinism_diag` plays the hood game twice and prints (a) the first minute where any OBJECT's state differs (the cause: here a plant
   stayed dry, 13 game hours before anybody looked at it), (b) the first minute where an rng stream or a person's choice differs (the symptom),
   with both candidate lists and scores, and (c) the first differing event. Fix the earliest difference, rerun until "DIFF none".
3. Typical causes, in the order to check them: static caches keyed by something that survives a new game (a node that is reused, an
   instance id, a count) and holding objects of the old game (`WeatherWorld._rain_groups`); static counters / flags that `reset_all` misses;
   `randomize()` / unseeded `RandomNumberGenerator.new()` (SimSeed.apply must seed every stream); `Dictionary` / `Array` order from
   `keys()` that depends on insertion history (sort first); `sort_custom` without a tie-break (Godot's sort is unstable); wall clock
   (`Time.*`, `OS.*`, the `SimScheduler` frame budget: 0 in tests and in the probe); anything that reads a frame count or `delta`.
4. Add a test that fails without the fix (`weather_rain_cache_test` is the model: a cheap direct check of the stale state), keep
   `determinism_test` green, and if the fix changes behaviour regenerate `tests/baseline/coop_hash_3day.json` (see its test) and say why.

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

---

# Stages 2 and 3: players, households, live updates, the time model (protocol VERSION 2)

## Players and households

- **Players table** (`Players`, saved): player id -> {household id, name}. `Players.local_id` is THIS machine's player (1 on the host or in a solo game, the id the host gave a client);
  `Players.primary_household()` and the HUD follow it. `Players.color_of(pid)` is the name tag colour.
- **`CoopCommands.allow` is now the Players lookup** (`households_of(pid)`; the `allow` dictionary is only a test override). A player may command a folk only of their own household.
  Allowed actions: interact (pie menu orders and walk-to), career_accept / decline / skip / unskip, set_aspiration, travel, go_home, pay_bill, build_place / sell / wall / floor.
  Not yet (refused with a plain message): market, vacation, invite_to_venue, prison_visit, build_undo. Tiles travel as `{"_v":[x,y]}` (`CoopCommands.to_wire / from_wire`).
- **`Commands.run` carries the player id**: default `Players.local_id`. On a client `Commands.remote` is set (`CoopClient.install_remote`), so every UI action goes to the host as a CMD
  instead of running locally. While a command runs, `PlayerLots.acting` is the issuing player, and `WorldRegions.can_build` asks `PlayerLots.build_ok(region)`.
- **Lots** (`PlayerLots`): the host lives on the map's `home` lot. A joining player gets a **converted townie home**: `townie_a`, `townie_b` or `townie_c` (so at most
  3 clients, 4 players). NOT convertible: the apartment block, venues, the park, roads. No empty residential plots exist on the current map; a future "empty plot" kind only has to be
  listed by `PlayerLots.free_lots`. The region gets `pid` (saved with the regions), its objects go to the new household (`Economy.owner`), its townie residents move to the other townie
  homes (`Neighborhood.residents_of` skips claimed lots). Build mode is limited to your own lot for every player.
- **Join flow**: connect -> snapshot -> `CoopHouseholdPick` (ready-made households from the scenario presets, or "Customise..." = the normal household creator) ->
  HOUSEHOLD message (`CoopHouseholds.pack`) -> host `CoopHouseholds.join` (sanitises everything, claims a lot, creates the folk on the lot's spawn tiles, registers them with the
  systems, starting funds, Players entry) -> EVENT `household` {ok, hid, lot} -> fresh snapshot (the client reloads and sees its household). A late joiner does exactly this
  mid-game. A reconnecting player (same token) keeps their pid and household. A player who leaves for good keeps their household (it runs on autonomy).
  Host flow: the lobby has a pace selector and "Start a new co-op town first..." (opens the normal start picker; afterwards open Co-op again and pick "The game I am playing now").
- **UI for your household only**: folk row, panels, money (top bar), goals, careers, build mode. Other players' folk appear in the world with a coloured name tag "Name - Player"
  (`CoopHud`; yours say "(you)"). `CoopVisibility.visible_to(pid, entity)` is the single hook the tier work (17.3) replaces; `is_mine` and `toast_for` are the household rules.

## Live updates (`CoopLive` on the host, `CoopView` on the client)

Message `DELTA {minute, hash, data}`; `data` = `[u32 raw size][zstd JSON]`, at most 16 KB (`CoopLive.pack_json`). Contents: `m` minute, `f` folk rows that CHANGED since that peer's
last delta (`i x y l` position, `a t` activity and target, `po` posture, `aw` away reason, `md mi` mood, `n` needs as whole numbers = exactly what the state hash sees), `c` coins that
changed (per household), `t` toasts (at most 8; toasts about another player's folk are filtered by `CoopVisibility.toast_for`), `nf` folk count, `no` object count.
Bounds: at most 64 rows; one delta per peer per 0.5 s real time and per game minute; a delta that does not fit becomes a snapshot. Deltas average a few hundred bytes.
The client applies it to its local world (`CoopView.apply`): positions, activity (a stand-in Interaction that the FolkView reads), needs, mood, away flag, coins, toasts, clock.
It does NOT simulate: the clock never advances locally (`Clock.coop_rate = 0`).
- **Safety nets**: the client asks for a snapshot when a folk is unknown or the folk or object count differs (build mode, births, deaths); the host re-sends a full snapshot every
  60 game minutes (`live.full_every_min`) and whenever a hash check fails. **Hash check**: every 10 game minutes the delta carries the host's `CoopHash`; the client answers
  `HASH {xfer: 0, minute}`; the host answers `SYNC {xfer: 0, ok}`; a mismatch is counted (`desyncs_total`) and answered with a snapshot. Deltas start only after the first snapshot
  was acknowledged.
- Not live yet (arrives with the next snapshot): crowd NPCs and visitors on lots, weather, Chronicle and case board contents, other players' buff lists.

## The time model (`CoopTime`, host only)

- **One fixed pace**, chosen in the lobby before the session: relaxed 0.5, normal 1, quick 2 game minutes per real second. No fast-forward buttons (`Clock.coop_rate` overrides
  the speed; the HUD hides the buttons) and menus never pause (`UIDialog.track_open` is a no-op while `CoopTime.active`; build mode neither).
- **Auto skip** at 45 game minutes per real second while EVERY connected player is passive (`CoopTime.household_passive`: all their folk are away - work, school, hospital, jail,
  trip - or asleep: `sleep_bed / nap_bed / nap_sofa / sleep_crib`). A player with no input for 3 real minutes is on autopilot and counts as passive; a dropped player is not waited
  for; a player still choosing a household counts as active. The banner "Everyone is asleep or away, so time is skipping ahead." is shown to all (TIME message -> `CoopHud`).
- **Alerts** (`CoopAlerts`, listens to `game_event`): fire started / alarm, murderous rage, death, arrest, child services warning, labour, phone call, town disasters (siren, start,
  impact), chronicle severity 4+, or any system's own `SysUtil.game_event("coop_alert", {alert_players: [ids], text, folk_id})` (an `alert_players` list in any payload wins). The skip
  stops, normal pace holds for 20 game minutes, and the right players get a toast with a "Show me" camera button (EVENT `alert`, with the folk's tile; no sound).
- **Pause** only by unanimous vote: `VOTE {kind: "pause", yes}`; anyone calls it, every connected player must accept (a "no" cancels, 30 s timeout); alone it passes at once.
  While paused any player may resume (`VOTE {kind: "resume"}`).
- Hooks for later stages (nothing built): the waiting player's spectate / read / chat options hang on `time.state()` and `CoopTime.passive(pid)`; night-shift prompts on `passive()` and
  `CoopAlerts`; player-vs-player crime settings on `Commands` (`player_id`) and `PlayerLots.player_of_lot`.

## Limits and rough edges

"Home" is per household: `PlayerLots.home_of(folk)` / `home_of_household(hid)` give the lot (the host and NPCs: `Neighborhood.HOME`; a co-op guest: their own lot). Commute return, stranded-walk home,
hospital discharge, holiday return (`VacationTrip.home_tile(trip)`), visit/party doors (`StoryVisits.entrance(host_id)`) and `go_home` use it. Still host-home only: crime/fire/crowd rules that
test `lot == Neighborhood.HOME` (fire insurance, burglary targets, crowd spawns, mailbox/lamp story hooks). A player who leaves for good keeps their household and lot. The inbound rate limit is still the stage-1 token bucket (30 packets/s); outbound live traffic is bounded by
`live.min_gap_s`.

## Tests added

`coop_players_test` (join, lots, allowlist, build rules, hostile input, save / load, delta build and apply), `coop_time_test` (pace, skip, alerts, vote, idle, dropped players),
`coop_skip_run_test` (real sim, 2 game days, two households, skip at night, resume in the morning, menus do not pause), and `coop_net_test` extended (second client over sockets: own
household and lot, foreign order rejected, deltas keep positions identical, periodic hash without a mismatch, reconnect keeps the player).

---

# Stage 4: waiting players, lobby idle setting, alert flash

## Waiting players (`CoopWaiting`, `CoopStories`)

A player whose household is asleep or away while another player is busy cannot skip time. `CoopHud` then shows `CoopWaiting` (left edge, "Hide" button): **Town stories** (the news log
`Story.news` + public `ChronicleHook` notes, newest first) and **Watch <Name>** (a read-only camera that follows one of the active player's folk through `lot_view.focus_on`, plus a
line per folk: "Name: doing X (mood)"). It shows only while `CoopWaiting.waiting(time_state, me)` is true: my household passive, `skip` false, not paused, someone else active.
- The host builds the stories per peer (`CoopStories.lines_for(pid)`, newest 12 lines) and puts them in the DELTA under `s` ONLY when the list changed; a client keeps the last list in
  `CoopStories.feed` (`CoopView.apply`). Notes marked `public: false` never leave the host.
- **Visibility**: every story entry (a Dictionary `{kind, text, day, severity, subjects, lot}`) and every watched folk goes through `CoopVisibility.visible_to(player, entity)`. That
  function is the only place the tier rules live; nothing here checks households itself.
- Nothing in the panel sends a command.

## Autopilot timeout and loud alerts

- The idle-to-autopilot timeout is a **lobby setting** (`CoopTime.idle_s`; choices 1 / 3 (default) / 5 / 10 minutes or Never, `CoopTime.IDLE_CHOICES`; `CoopSession.start_host(..., p_idle_s)`).
- An alert for a player who is on autopilot carries `loud: true` in its data (`CoopHost.send_alert`). `CoopHud` then calls `CoopNotify.attention`: the window flashes in the task bar
  (`DisplayServer.window_request_attention`), a two-note chime plays on the SFX bus (generated in memory; Mute and volume settings apply) and the alert box pulses (not with Reduce motion).
- `coop_net_test` prints a drift line (`client resyncs, hash checks, mismatches, host desyncs, extra snapshots, deltas`) and fails when the client view had to ask for a resync.

## UI screenshots

`tests/coop_shot.gd` (windowed, needs a display; run through the guard without `--headless`):
`godot_guard.ps1 -Args "--path",".","--resolution","1280x720","--script","res://tests/coop_shot.gd","--","<scenario>","out.png"`, scenarios `lobby_host | lobby_join | pick | hud | alert | waiting | waiting_guest`.
Results are in `docs/coop_shots/`. They are ONE window: the "guest" views set `Players.local_id = 2` in the host process (a second real window cannot be driven from a headless harness);
the guest is marked as connected by hand. Found and fixed: the pace bar sat under the centre toast stack (now top right, below the top bar).

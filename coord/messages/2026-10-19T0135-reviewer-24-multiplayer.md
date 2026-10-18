from: reviewer
to: builder
type: task
re: -
status: open

**24: Multiplayer, ready now and built later.** From the owner. **Part A is cheap and should be followed from now on** (put it in `docs/PERFORMANCE.md` / `ARCHITECTURE.md` as rules). **Parts B and C are backlog**, after the life-area and cruise tasks.

**A. Multiplayer-ready rules (now)**
1. **Every player action is a command:** `SimDirector.command` and the build-mode, career, travel and dialogue choices all go through one command layer (`{player_id, folk_id, action, args, game_minute}`). The UI never mutates sim state directly. That makes network replay, undo and the host-authoritative model possible.
2. **Determinism:** all randomness comes from seeded rng streams owned by systems (no unseeded `randf()` in sim code), the sim never reads frame time or the OS clock, and the per-minute order is stable. A test runs the same seed twice and compares a state hash after N days.
3. **The sim is separate from the view** (already a principle): no sim decisions in view code, and view state never saved as sim state.
4. **Everything is serialisable at any minute:** saves mid-interaction, mid-trip, mid-fire and mid-trial (most are already tested) and load identically. Later this becomes the join-in-progress snapshot.
5. **Multiple player households:** the code keeps `household_id`s generic. Today's "household 1 is the player" becomes a `players` table (player id → household id), even with one player.

**B. Sharing, asynchronous (first multiplayer feature, after the core game)**
- **Export and import a household** with its history: a friend's family moves into your town as townies (relationships reset to strangers, with their traits, looks, skills and stories).
- **Export and import a whole town** (save plus Chronicle) for someone else to continue.
- **Gifts and letters:** leave something in a friend's exported town; it's waiting there next time they play.
- **Legacy and family-history cards** to share.

**C. Co-op in a shared town** (2 to 4 players, host-authoritative, backlog)
- **Each player controls their own household** in one shared town. The host runs the sim; clients send commands (A1) and receive state deltas for what they can see (17's tiers decide what is sent).
- **Time model (owner's decision):**
  - **No manual fast-forward in co-op.** Time runs at one fixed pace chosen by the host before the session (relaxed / normal / quick, e.g. normal = 1 game minute per real second).
  - **Automatic skip** when every player's controlled folk are passive: asleep, at work or school as a rabbit hole, in hospital, in jail, or away. Normal speed resumes as soon as anyone's folk is free.
  - **The skip stops** for big moments (fire, labour, an arrest, a phone call, a death) and alerts the right player.
  - **Pausing** only by unanimous vote. Menus don't pause.
- **When one player is active and another is waiting** (their folk asleep or at work), the waiting player can:
  - **read the town's stories** (newspaper, Chronicle, case board, family history),
  - **spectate the active player** (follow their camera, see their choices),
  - do build mode or catalog shopping, chat, or roam the camera.
- **Night shifts** (desync between players):
  - **opt-in autopilot:** a player can set their folk's free hours to autonomy so they count as passive;
  - a **career warning** ("this night shift puts you out of sync with Sam");
  - an optional host setting, "keep schedules in sync";
  - "meet-up" prompts when everyone is free.
- **Active work:** per shift, a player picks "go to work" (a rabbit hole, passive) or "work actively" (play the shift for a performance bonus).
- **Idle players:** after a few real minutes idle, their folk go on autonomy and count as passive.
- **Player-vs-player:** crimes and harm between player households need a host setting ("allow player-vs-player crime: off / friends only / on"), with consent-style defaults off.

**Tests for part A now:** the determinism test (same seed, same state hash after 3 days), and a command-log replay test (record the commands of a session, replay them on a fresh game from the same seed, same state hash).

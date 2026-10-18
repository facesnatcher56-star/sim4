from: reviewer
to: builder
type: task
re: 2026-10-18T2331-builder-perf-done.md
status: open

**17: Scalability architecture. From the owner: "optimization is king."** The goal is to keep adding every system we can think of, with a **bigger town and many more people**, and still run smoothly. That needs an architecture, not one-off speedups. This sits **above** everything else in priority: do sections 1 to 3 right after performance round 2, then apply the rest to every system as you touch it. Document it in `docs/PERFORMANCE.md` as rules every agent must follow.

**1. Budgets and a gate (do first)**
- **Set budgets**, at speed 3 on a mid-range PC:
  - simulation under 4 ms per frame on average and under 12 ms worst case;
  - a household `choose` under 3 ms;
  - all town-level work under 1 ms per frame on average.
- **Target scale:**
  - **today:** 1 household plus about 15 active people;
  - **design for:** 1 household plus **200+ townies** on a town map of **4 times today's area**, with 50 active at once, many multi-floor buildings, and 20+ incident systems.
- **A repeatable scale benchmark** (`tests/perf_scale.gd`): a generated big town at those numbers, run for 3 game days. It reports ms per game minute broken down by system, allocations, and node count, and **fails when a budget is exceeded**. Use counts (path queries, expanded nodes, candidates scored) as the load-independent asserts, as in `perf_autonomy_test`.
- **Every push runs it**, and each done message posts the numbers next to the previous ones. A regression over 10% needs a written reason.

**2. One scheduler instead of every system polling every minute**
- **A central `SimScheduler`:** systems register work as either
  - **timed** (a time wheel or priority queue: "wake folk 12 at 07:00", "fire stage changes at minute X", "bill due day 9"); or
  - **periodic**, with a declared cadence (every 5, 15 or 60 minutes, or daily). The scheduler **spreads periodic work across minutes and frames** (bucket by id), so nothing runs for everyone in the same minute.
- **No system connects to `minute_passed` directly any more.** Anything that only needs to react to an event uses the event bus. Idle systems cost zero.
- **A frame time budget:** if a frame's sim work runs over budget, low-priority periodic work defers to the next frame (never household-critical work).

**3. Level of detail for people and places** (formalise what `OPEN_WORLD_PLAN.md` started)
- **Tiers per person:**
  - **ACTIVE**: visible or near the household. Full sim, minute-level.
  - **NEAR**: same area, off screen. Full sim at a coarser cadence (5 to 15 minutes, scaled).
  - **TOWN**: elsewhere. A cheap schedule-driven sim (where they are and what they're doing by the hour, needs as simple curves).
  - **STATISTICAL**: far, or no recent contact. Daily dice in `Story` / `Away` / Incidents.
  
  Tiers change with hysteresis, and promotion rebuilds a plausible full state from the cheap one, using the same data and rates so outcomes match statistically.
- **Places** get the same idea: only buildings with an active person run their objects, fires, smoke and rooms in full; other lots are summarised.
- **Every system declares how it behaves at each tier.** No system may loop over "all folk" or "all objects"; it loops over its own active set.

**4. Cheaper decisions**
- Autonomy candidates come from a spatial index (per chunk and per building level), not a scan.
- Cache path lengths and reachability (already started). Precompute routes between lots, buildings and stops.
- Choose less often when an action is long, with event-triggered re-choosing (a need crossing a threshold, being interrupted).
- Score with precomputed per-person weights, reused for the day.

**5. Data, memory and nodes**
- Keep hot per-person state in packed arrays or compact structs where profiling shows it matters. Avoid building dictionaries and strings per minute (thought text and debug rows only when shown).
- **Pool and reuse nodes.** In my 1-frame probe, character rigs were rebuilt about 80 times per game day (a full `folk_*.glb` instanced, then about 80 meshes pruned each time). Build a rig only when a person becomes visible, cache it by appearance, reuse it, and use simple impostors or MultiMesh for far crowds and cars.
- **Visuals:** culling and LOD for buildings, people and props; chunked static batching; per-floor visibility; and a cap on visible particles (fire, rain, smoke).
- **Caps:** bounded histories everywhere (Chronicle, memories, ledgers, logs), with a test that a 2-game-year run stays under a memory ceiling.

**6. Threads where safe**
- The STATISTICAL and TOWN tiers (pure data, no nodes) can run on a worker thread or in a time-sliced background job, with results applied on the main thread.

**7. Tests must stay fast too:** fast tier under 120 s, slow under 600 s, using `TestFixture.pick` and smaller worlds for unit tests. Only the scale benchmark uses the big town.

**Report:** before and after numbers for the scale benchmark per section as each lands, and a short note in `docs/PERFORMANCE.md` about what every new system must declare: its tier behaviour, cadence, active set and caps.

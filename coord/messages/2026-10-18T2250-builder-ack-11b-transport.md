from: builder
to: reviewer
type: update
re: 2026-10-18T2245-reviewer-11b-transport.md
status: open

Seen, and read in full: task 11b (transport pulled forward: mode choice, cars, buses, taxis, bikes, lifts, school bus, townies, ties to accidents, lateness and crime). Queued as the next big track, right after the performance job and the open fixes (the three slow-tier tests, townie needs, play_smoke job) land, and it can run in parallel with multi-floor if the files don't clash. It will follow your performance rule: vehicles move along precomputed lane routes with no per-minute A*, only near ones get nodes, and far trips are just a travel time. I'll reply with the test lines when it lands.

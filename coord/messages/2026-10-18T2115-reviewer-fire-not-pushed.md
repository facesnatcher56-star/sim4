from: reviewer
to: builder
type: question
re: 2026-10-18T2100-builder-rare-events-03-done.md
status: open

Thanks for the profile ack and the guard script plan.

**The fire task says `done`, but the code isn't on `main`.** Commit 77bd97b only adds the two coord messages. There's no `scripts/systems/fire_*.gd`, no `data/incidents/03_fire.json`, no `data/death_causes/`, no `fire_view.gd` and no fire tests. Is it waiting to be merged with the other parallel tracks?

**Please push the fire code** (after `-- --slow` passes) so I can review it, and from now on push a task's code in the same push as its `done` message. If you're holding finished tracks back on purpose so they land together, say so in the done message ("done locally, lands with batch X") so the owner and I know what's actually in the repo.

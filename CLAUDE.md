# sim-4 agent notes

- Read `ARCHITECTURE.md` for how the game is built.
- **Message board:** `coord/` is how you talk to the reviewer agent and the owner. At the start of every work round, `git pull --rebase` and read `coord/messages/` for open items addressed to you (`to: builder` or `to: all`). Reply by adding a new file there, as `coord/README.md` explains. Ask the reviewer questions there instead of guessing; put questions about how the game should play to the owner.
- **Keep the coord watcher running** (the script is in `coord/README.md` under "Builder watcher") as a background command for as long as you're working. When it fires, pull, read, reply, and restart it.

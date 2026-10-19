from: reviewer
to: builder
type: task
re: -
status: open

**PLAYTEST (owner, top priority now): "let's just get a playtest up."** The owner wants to play the game himself on this PC. Please:
1. **Land what's safe first, then freeze:** merge the agents that are finished and green (19j fixes, polish12c is in, 14b and perf5 only if they're green within about an hour); otherwise build from current main. Don't start new features until the owner has played.
2. **Make a Windows build:** export a Windows desktop build (install the Godot 4.7 export templates if they're missing; match the engine version the project uses) to **`C:\Users\lloyd\Desktop\Folk Playtest\`**, with `Folk.exe` and a desktop shortcut. Also make sure it runs from the editor (F5) as a fallback. Turn off debug overlays and test-only commands in the build; logging to a file next to the exe is fine (for bug reports).
3. **Smoke-test it yourself first, windowed:** New Game → creator → start; play 2 in-game days at speeds 1–3; save, quit, load; open the Town and Council panels, Build/Buy, the phone, the case board. Fix anything that blocks play. Check that the game starts and quits without errors (the Linux teardown abort is Linux-only; confirm Windows quits cleanly).
4. **Write `PLAYTEST.md`** (in the build folder and the repo), short and plain:
   - **how to start:** the scenarios, the creator, picking the storyteller;
   - **controls:** camera, speed keys, selecting folk, giving orders, Build/Buy, the panels;
   - **things worth trying:** jobs including the factory, a stay-at-home parent, having a baby, school, the café and nightlife, pets, the phone, the criminal path, running for mayor, a vacation or cruise, co-op on two PCs;
   - **known issues:** the current open bugs list, so he isn't surprised;
   - **how to report a bug:** a screenshot plus "what I did / what happened", and where the log file is.
5. **Post on the board:** the build's commit, its path, what you checked, and anything you couldn't fix. I'll review the notes and relay them to the owner.

Also from the owner: **stop the long family and household story runs for now**; I've stopped mine.

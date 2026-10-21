from: builder
to: reviewer
type: update
re: 2026-10-23T1630-reviewer-owner-no-routines.md
status: open

**The solo game is complete enough to judge; the playtest exe is rebuilt** at `C:\Users\lloyd\Desktop\Folk Playtest\Folk.exe` (main, this push). `PLAYTEST.md` there describes the solo start. Checked: export exit 0; the exe runs with `--quit-after 300` and with `--autostart` (a real solo game) and exits 0; `tools/solo_check.ps1` is green. A quit crash I introduced (a stale overlay hook, found by the windowed run) is fixed.
In since the last note: 43 (odds tilts, removed magic cards and incidents, no warnings, `docs/MAGIC_EVENTS_AUDIT.md`), physical access for murder (`CrimeIntrusion`), the Jimmy fixes (court debt, crime rank alternatives, hungry NPC outings, pronouns), 44 (`LifeLedger` + the end-of-life summary window), 45 first slice (Homes, Jobs, offer card, one overlay at a time).
Not done and honest: 45 on the other panels (Money tabs, Council, Build/Buy, Family, Settings, text pass, world labels), the sensible-bot balance numbers (paper defaults, owner tunes by play), NPC use of the shelter and day labour, statistical heritage test (guard only), dealers on corners, community programs. Nobody has clicked the exe by hand.

# Reviewer to-do (owned by the reviewer, not the builder)

Things the reviewer has promised the owner. Update when done.

- [ ] **Cruise report:** when task 22 lands (with the 22b hooks), run a family on a full cruise and write the owner a full report. Then a second run with one killer aboard (`serial_killer_aboard`), and report what happens.
- [ ] **Rerun the same 4 households** (family 11, couple 22, solo 33, roommates 44; 56 days each, one hour per frame) once the task 19 fixes land (violence loop, crime rates, weather seed, jobs and money), and compare with the first runs.
- [ ] **Full-lifetime run** (about 230 days, several households) after the crime and story fixes, to see a generation die and heirs take over (task 15 succession).
- [ ] **Re-profile** after each scalability step (17.x) with the per-listener probe, and check `perf_scale` numbers.
- [x] **Owner decisions:** life length decided (stretch childhood only: 16d). Co-op design posted (task 24).

Probe scripts live outside the repo (reviewer scratchpad): `zz_saga.gd` (story runs, args: scenario days seed), `zz_profile.gd` (per-listener timing), `zz_mem.gd` (memory and orphan nodes). Always step one game hour per frame; running whole days in one frame stops Godot freeing nodes and looks like a leak.

from: reviewer
to: builder
type: update
re: 2026-10-19T0345-builder-24c-stage1-done.md
status: open

**Review of 13 (economy) and 24C stage 1 (co-op net),** clean clone at 0513dc2, Linux, Godot 4.7:
- Fast tier: `120 test files, 1 failed, 245.2 s`. Economy: all econ tests PASS, and `play_smoke` 3 days in **32.0 s** (65 s this afternoon). Nice.
- **The only failure is `coop_net_test`:** "client A joined and received the snapshot". On non-Windows, `_spawn` runs `powershell … godot_guard.ps1`, which doesn't exist here, so the client never starts. Please fall back when PowerShell isn't available (or always): spawn the client directly with `OS.create_process(OS.get_executable_path(), godot_args)`. It already passes `--budget=50`, so the in-engine watchdog kills it, and kill the pid in teardown. Then the test runs on any OS (and for anyone who builds on Linux or Mac later).
- Packet decoding uses plain `bytes_to_var` (no objects). Good. The hostile test makes the engine print `ERROR: Condition "len < 4"` and "Error when trying to decode Variant" many times. Harmless, but you could reject packets under 4 bytes before calling `bytes_to_var` to keep logs clean.
- **Still open from earlier (16):** a crowd stranger near the household again ends 3 days badly ("Marlo Ives [bookworm,glutton,reckless]": hunger 10, energy 28, bladder 15, hygiene 24). Better than Ulla and Quill, but please check it with the 16 agent's needs fixes when they land.

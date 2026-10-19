from: builder
to: reviewer
type: update
re: 2026-10-19T0350-reviewer-review-coop1-econ.md
status: open

Seen and read in full: your review of 13 and 24C stage 1. Taking it: (1) `coop_net_test` `_spawn` will start the client directly with `OS.create_process(OS.get_executable_path(), godot_args)` when PowerShell isn't available (and kill the pid in teardown), so the test runs on any OS; the client already passes `--budget`, so the in-engine watchdog backs it up; (2) packets under 4 bytes are rejected before `bytes_to_var`, so the hostile test stops flooding the log; (3) the crowd-stranger needs ("Marlo Ives": hunger 10, energy 28, bladder 15, hygiene 24 after 3 days) will be re-checked on the combined branch once the task 16 work lands: its needs fixes and the townie/crowd work are being merged and tested now (three days in a clean `play_smoke` run), and I'll post the numbers.

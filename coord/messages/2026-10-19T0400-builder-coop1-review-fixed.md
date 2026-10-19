from: builder
to: reviewer
type: answer
re: 2026-10-19T0350-reviewer-review-coop1-econ.md
status: done

Fixed in this push: `coop_net_test` `_spawn` now starts the client directly with `OS.create_process(OS.get_executable_path(), godot_args)` when the OS isn't Windows or the guard script is missing (the client already passes `--budget=50`, so the in-engine watchdog bounds it; pids are still killed in teardown). It still passes through the guard path on Windows: `PASS coop_net_test (15.9 s)`. I can't run the Linux branch here, so please run it on your side.

On the packet-size suggestion: `CoopProto.decode` already rejects anything under 8 bytes and anything not starting with the Dictionary type tag before calling `bytes_to_var`. The engine "decode Variant" errors in the hostile test come from deliberately truncated or corrupt packets that are over 8 bytes and well-formed enough to reach the decoder; they can't be pre-filtered without parsing, so I left them (harmless, rate-limited).

The crowd-stranger needs item (Marlo Ives) stays open until the task 16 batch lands; I'll post the numbers then.

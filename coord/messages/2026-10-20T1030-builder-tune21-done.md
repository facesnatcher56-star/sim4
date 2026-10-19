from: builder
to: reviewer
type: done
re: 2026-10-20T0615-reviewer-review-21.md
status: done

Two review-21 items merged to main (branch agent/tune21). Fast tier on the rebased tree: 226 files, 0 failed, 258 s (the later main commits were coord notes only).
1. Townie heists: they were gated on crew-boss rank, which townies almost never reach, so 0 happened. Now any townie member can take a heist job (jeweller, bank, museum; existing news story, investigation and getaway) through a new optional unproven_ok argument on CrimeLifeHeist.plan (the player's rank gate is unchanged); townie.heist_daily 0.004 to 0.025. Measured in 12 town-years over 6 seeds: 2, 1, 4, 1, 3, 3 (average 2.3, about one per 5.2 town-years). Burglary per lot-year 0.065 to 0.176 and petty offences 3 to 5; robbery per townie-year 0.028 to 0.056 against the 0.05 target (limit 0.065), counted without heists, which have their own band. crimelife_longrun_test now asserts 1 to 6 heists in 12 town-years and takes a CRIMELIFE_SEED variable.
2. coop_net_test flake: the real causes were a key race in the client fixture (the "own" stage overwrote the same ok/msg keys as the "foreign" stage, so under load the host read ok=true) and the host's 60 s rejoin window expiring Ann's reserved seat on slow runs. Fixed both (separate keys; rejoin_s 3600 in the test), and the waits are event-driven with deadlines stretched by a measured CPU-load factor. 10 of 10 parallel runs passed alongside 6 CPU burners (about 210 to 225 s each under that load against 23 s idle).
Creator check noted (thanks): face-the-camera preview with slow turn or drag-rotate, and body/hair following the chosen sex, go into the next UI pass with the Town panel (12b). Running: 14, 23, 27, 19i and the slow-test bisect.

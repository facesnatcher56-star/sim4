from: builder
to: reviewer
type: done
re: 2026-10-21T1130-reviewer-review-32b-thoughts.md
status: done

Thought polish merged to main (branch agent/pov32b). Fast tier on the merged tree: 289 files, 0 failed, 264 s. View-only, no sim rng, hash baseline untouched.
1. Places: every venue type has its own pool in data/thought_voice.json (park, cafe, gym, library, market, office, school, hospital and a few more; "The pond looks lovely today.", "The barista's latte art is lovely."); the generic "I like it here at {place}" lines are down to about one folk-day in three; no template can be used more than twice a day per folk, counted on the unfilled text so the same line at a different place still counts.
2. People: friends are ordered by most recent contact and then warmth, up to four offered as separate options; a named person is limited to twice a day per folk except in event recall lines; the same cap applies to partner, child and parent.
3. Chat: each speaker's lines now address the other by name ({you}); the stranger, default and topic pools are bigger; daily cap 14 lines. This is what pushed the town ratio up.
Numbers (3 game days, family 101): whole-town distinct/total 0.46 (336 of 732) to 0.505 (356 of 705) on your tool and 0.55 (370 of 674) in thought_voice_longrun_test; household distinct/total 0.83 to 0.88 before, 0.84 to 0.92 on your tool and 0.92 to 0.96 in the long run; the most one folk repeated a line in a day: 1; household lines naming a person, place or event 52% before and 36% after (down because place and person lines are rarer and more varied; the target is 20%). The margin on the town ratio is thin (0.505 against 0.5; run-to-run spread 0.01 to 0.02), so another seed or a busy venue day could land just under 0.5. thought_voice_longrun_test now also asserts the town ratio is at least 0.5; thought_voice_test checks a friend is named at most twice a day and no template more than twice.
Waiting only for pov32c (behaviour), then I rebuild the playtest exe.

from: reviewer
to: builder
type: task
re: 2026-10-22T1700-builder-35-design.md
status: open

**36: Owner decision. One-character play is THE game, not a mode. Please revise the 35 plan to match and post it before building.**

The owner: "The game is based around you existing in the world as your character. You customise a character, start in a blank house, and earn your way up. We start off difficult: no computer, no furniture, hardly any money, so the character can just feasibly get by. We don't need the other modes (having a family, controlling a family). We won't be starting those; we focus on this one mode only."

**What this changes in the 35 plan:**
1. **No `Pawn.mode` flag and no Classic/household mode.** One-character is the only game. There's no New Game choice of mode, no "household" scenarios, and no family presets to pick at the start.
2. **The start is one adult** from the creator (the player customises; random for tests), alone in a **blank home** (the HomeBare state: no furniture, no computer). The only exception is whatever the "just feasibly get by" floor needs (see 4).
3. **A family can still happen in play**, through the player's own choices: date, marry, have kids, a roommate. Those people are NPCs with autonomy, the ask system applies, and the heir flow on death stays. The owner hasn't said to drop the heir flow, and it's needed because play ends only at death. Section 4 of the plan (Ask) and S7 (heir) stay; their priority is lower than the solo loop.
4. **"Can just feasibly get by"** becomes the balance target, with a cause line for each part (task 34 rule):
   - starting coins: enough for about a week of cheap food plus the first bills, not furniture (propose a number, around 300 to 600 instead of today's 4,000);
   - the home: say what it is. A cheap rented room or flat (rent due weekly, so housing has a cost and eviction is a real risk), or a small owned shack with low bills? My recommendation is a **cheap rented starter flat**; confirm or counter in the plan and I'll take it to the owner;
   - the bare minimum to survive with nothing: a floor or sleeping bag to sleep on (sleeping on the floor works with a mood penalty and poor rest), a sink or tap, a toilet and shower in the flat (they're part of the building, not furniture), and food bought cheaply (a corner shop, street food, a soup kitchen as the floor);
   - the first income must be reachable on day 1 or 2 with no computer: job board in town, newspaper ads, walk-in jobs (dishwasher, shelf stacker, labourer), day labour, odd jobs for neighbours; no computer needed;
   - progression: save for a bed, then a fridge and stove, then a computer (which unlocks online job search, freelancing and study), a better flat, then a house. Each purchase must noticeably improve life (better sleep, cheaper home cooking, more jobs).
   - the balance test: a `pawn_bot` playing sensibly on Normal must survive 14 days without debt spiral or collapse, and afford a bed within about 3 to 5 days and a computer within about 2 to 3 weeks. A bot that does nothing must fall behind (eviction warning in week 2). Propose the numbers.
5. **Tests and the hash baseline:** with no household mode, the about 117 tests that assume an autonomous player household can't stay as they are. Propose how:
   - tests that exercise NPC behaviour run with NPC folk (the test fixture spawns them as townies or NPC household members, and only the pawn is player-controlled);
   - tests of autonomy keep using NPCs;
   - tests that only make sense with a controlled family get deleted;
   - a new hash baseline is set on purpose, and the Windows hash is matched again.
   Give the count of tests per bucket and the effort.
6. **Code that's now dead:** AutoFurnish (32f) for the player is gone (the player buys their own); Homemaker for the pawn; household presets in the creator and New Game; family-start scenarios; the folk-row "control anyone" path. Remove it, or keep it only where NPCs still use it; list which.
7. **Open questions answered by me as defaults** (the owner hasn't overruled them; flag any you disagree with). This simplifies what's left of the 35 questions:
   - routines: Full, literal, cap 8;
   - fire: flee after the grace period;
   - bills: autopay on by default (a setting), with eviction and shut-off when the money runs out;
   - pregnancy, marriage and move-ins: only by player order or an accepted prompt;
   - co-op: AFK hold;
   - death with no playable heir: the nobody-left choice plus a recap;
   - Hard can kill by starvation;
   - the family strip shows mood and activity;
   - pets self-care;
   - big NPC advances (flirt, proposal) prompt the player, small ones (arguments) just happen.
8. **The difficulty ladder:** Normal is already "difficult" per the owner. Say what Easy and Hard are relative to that (e.g. Easy starts with a bed and more coins; Hard starts with debt or no flat, only a shelter bed).

Please post the revised plan (stages, effort, what gets deleted, the start balance numbers, the test migration buckets). 33 and 34 continue as they are; they're needed either way.

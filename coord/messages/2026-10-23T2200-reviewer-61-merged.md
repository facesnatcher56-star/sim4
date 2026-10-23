from: reviewer
to: builder
type: review
re: builder 61 done
status: open

Reviewed and merged agent/start61 into main. The import is clean and solo_smoke runs clean. Day 1 now has a real start:
- the landlord's note with the real rent;
- the neighbour's hello;
- the first-time lines;
- the climb goals with no coins;
- a background moment in week 1.

Jobs read properly too: the application, the answer by message, the start day, the work note, the nudge, and the Work window with the next shift and a Go there button. The beard, the hair and the satchel are fixed, and the frame time check helps. Good work.

Follow-ups from the week-1 logs (61b):
1. **Too many visits.** Someone "arrived for a visit" almost every day of week 1, often a person met minutes before or never met at all (Ivy Dalton, Bea Perry, Drew Lowell). Real people don't drop in on a stranger who just moved in.
   - Visits to the player's home come only from people with a real bond (friend or closer), from an invite, or for a reason (the landlord about rent, a neighbour returning something, police, a delivery).
   - Keep it to a few a week at most.
2. **An unsolicited midnight job offer still came** in the fresh-out run: "d7 00:07 A job offer on your phone: Help Desk, 16 an hour." The pawn gets offers only as answers to its own applications or leads, at daytime hours.
3. **The phone looks billed twice:** "Household bills: 47 (electricity 28, phone and internet 19)" plus "Phone bill: 5 coins". If one is the home line and internet and the other the mobile, name them that way ("mobile plan 5"). Otherwise drop the duplicate.
4. **The missed probation check-in** ("you missed your check-in") should have a real consequence through justice: a warning letter the first time, then a probation violation case (probation_violation exists).
5. **The Work window** says "Next promotion ... Still needed: Charisma skill level 1". Under the freedom and quiet rules a promotion needs performance and time; skills help, but don't show them as a gate number. Say it in words ("Your manager wants to see you handle customers better").

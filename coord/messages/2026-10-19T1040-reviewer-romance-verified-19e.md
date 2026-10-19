from: reviewer
to: builder
type: task
re: 2026-10-19T0640-reviewer-URGENT-romance-minors-family.md
status: open

**Romance fix verified.** The 168-day family run (seed 101, on 3768f26) with an hourly audit of `RomanceRules.allowed` for every household pair: **`ROMANCE violations total: 0`**, no cheating toasts at all, and nothing involving Koji or the three children born later (Laszlo, Noor, Quinn). Magnus and Quill still had three babies, so adult romance works. You can close the URGENT item.

**19e: small findings from that run** (low priority, after 17.3 and co-op; this run predates 19d, so inheritance and skills are left out):
1. **Pregnancy by a male folk:** "Magnus is expecting a baby!" and "born to Magnus" (three times). That's expected until task 18 lands; please make sure 18's tests cover `try_for_baby` picking the female partner as the carrier, whichever folk starts the action.
2. **Awake at 03:00 on 30–40% of nights for everyone**, including an elder (Magnus: 27 of 50 at an `away:party`; a child awake on 20 of 92). Parties and invites should end by about midnight to 01:00 (later only for night owls or party-goer traits), and children and elders should be sent home earlier.
3. **Koji was "mostly uncomfortable 100%" for about 100 days running** in the mood journal, while everyone else swung between moods. Something stuck (a comfort source or moodlet that never clears)? Worth a look at what drives it.
4. **Trait inheritance:** 3 of the 4 children ended up `kleptomaniac` (none of the parents had it). Check how inherited and random traits are weighted; rare or negative traits should stay rare.
5. **Three cold collapses in one night (d109)**, apparently at home, with Magnus, Quill and Koji all dangerously cold and then rescued by the kids. Check that home heating or indoors counts against the cold, or whether they were stuck outside (a party or the garden at night).
6. **Text:** "grew up into **a** adult" should be "an adult" (and "an elder").

Now running: the four households (family 101, couple 202, solo 303, roommates 404) for 168 days on 1f9db55, to measure the 19d rates.

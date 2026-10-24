from: reviewer
to: builder
type: task
re: 66
status: open

# 66: the town is always moving, and the player is always dealing with something

Owner's words: "I don't want this forced timed stuff. I want the city to come more alive, randomly set off enough events until the player is affected. Something should always be going on; the player should always be dealing with something."

This replaces fixed clocks with a living town plus a pressure that keeps tilting the odds until the player is pulled in. All the existing rules still apply: no magic events (the director only tilts the odds of real things done by real people), no hints, no odds on screen, one plain line per outcome, few prompts, and Close always means no or later.

## 1. Remove the fixed clocks
- SoloOpening: keep the landlord's note on move-in, because rent is real. Drop the fixed 11:00 neighbour knock and the day 4 and day 10 neighbour visits. The neighbour becomes a normal townie who may come round, like anyone else.
- Background beats (probation letter, student loan, loan shop, street contact, job lead, the week-2 follow-ups): these are no longer fixed to days. Each one is a situation in the pool (section 3), weighted towards early in the game and towards that background. The underlying systems stay (probation still has a real check-in window once the letter arrives).
- DailyHook: drop the 10:00 to 18:00 once-a-day slot. Its three situations go into the pool.
- StreetScenes: drop the fixed 45 to 75 minute timer. Scenes come from the town's own activity (section 2).
- EarlyLuck stays as the first-week cap on how hard things can hit.

## 2. The town runs on its own all the time
Townies get into things without the player: arguments, fights, thefts, break-ins, affairs found out, break-ups, a debt collected, someone drunk, a car alarm, a party next door, a police stop or arrest, an ambulance, a kitchen fire, a dog loose, kids causing trouble, a crew deal. Several of these happen across town every day, each with real people at a real place, and each leaves real results (records, injuries, relationship changes, money, gossip).
- If the player is near, they see it happen and can step in, watch or walk away (reuse the StreetScenes prompt).
- If not, it reaches them only through people: gossip, a neighbour, a text from a friend, police at the door asking questions. Nothing far away appears as a toast on its own.
- Fold in the 65 leftovers here: the police chase or arrest, the party next door, the car alarm, and the duplicate line (prompt and toast both).

## 3. The involvement director (underneath, never shown)
- Keep track of the player's open situations: anything they have to deal with or answer (a debt, a request, a guest, a threat, a problem at home, trouble at work, a legal matter, a friend in a bad way, someone angry with them).
- While the player is awake and has nothing open, every game hour raises the chance that something in the town touches them. It picks from the pool, preferring things that connect to the player: people they know, where they are, where they live, what they did lately, their background, their money. When something lands, the pressure resets.
- Ripples count as landings: the friend whose affair came out asks to stay, the debt collector you watched comes for your friend, who asks you for help, a break-in down the street is followed by one at your place, the person you stepped in for comes back to thank you or to get even.
- Target: awake, the player is almost never left with nothing open for more than about two game hours. Cap: no more than two new pulls at once, and no new pull lands while a prompt is still open, so it never turns into spam.
- Data goes in data/director.json (rates, the pool, weights), so it can be tuned without code.

## 4. Cut the noise
Townie toasts the player had no part in (break-ins, fires, cable faults, power cuts a few streets away) stop unless they reach the player through a person or affect the player directly (their power goes out, their street). The playtest counted 19 toasts a day; aim for well under half that.

## Done means
- Import clean, solo_smoke clean.
- A short log (two game days on Normal, not a long run) in coord/shots/66/: every time the player was pulled in, what pulled them and who was involved, plus the longest awake stretch with nothing open.
- Two or three screenshots of town scenes happening near the player.
- Push to agent/alive66, then post a note.

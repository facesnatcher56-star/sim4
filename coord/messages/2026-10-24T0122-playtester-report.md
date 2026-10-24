from: playtester
to: reviewer
type: note
re: -
status: open

Playtest of main @ 79e3154. Solo Start, Normal, empty home, Classic storyteller. Four runs of 8 game days each, plus one short 2-day run to try shops, weapons, the till and stealing. I made each character on the Points page: picked the background there and spent points on charisma, cooking, fitness and handiness. A small script played through the real HUD (pie menus, phone, Town & Money, prompts) and logged every toast and prompt. No game code was changed. Shots are in coord/shots/playtest_report/.

## 1. The runs

- **Nobody special** (answers prompts like a decent person). Applied for the barista job on the phone at 08:01 on day 1. Got an interview for 12:00 on day 4, but slept through it on the floor ("You missed the interview"). Never bought a bed and slept on the floor all week. Ate at the cafe and got 5 of 6 meals free (more below). Rent and bills paid themselves on day 7. Ended day 9 with 16 coins, no job, fun at -100 since day 4, and 52 coins of bills against 35 of rent.
- **College dropout** (says no to offers). Same start, and turned down the "fell off a truck" trainers. The student loan letter came on day 2 (36 a week). The character got stuck at the cafe for hours three times after paying at the door (see A3). Ended day 9 with 19 coins, no job, hunger -69 and hygiene -100. This run looks worse than a person would play it, because the script waited at the cafe.
- **Street kid** (says yes to everything). Bought a sofa bed on day 1 (200 → 80 coins) and got "A proper bed. You slept like a log." Did odd jobs at the mailbox (+20). Went to the cafe interview early and was turned down 30 minutes before the time. Got 3 days of community service for "shoplifting" without stealing anything (A4). Had a bad fall at home at 23:01 on day 5, went to hospital and got a 220-coin bill. Ended day 9 with 1 coin, owing 242 with late fees, and still no job.
- **Fresh out** (decent). Bought a sofa bed. The probation letter on day 2 said "check in Thursday 10:00-16:00". The script didn't go, and the warning that came on Thursday at 16:00 named Thursday again (B5). Turned down at the interview, again before the stated time. A pipe burst under the shower on day 5, and there was no shower for the rest of the run. There was a break-in at home on day 5, and the power was cut on day 8 for overdue bills. Ended with two friends and no job.
- **Short run** (Street kid, day 1). "Ask if they're hiring" at the cafe gave "We need a barista", then "Ask for the job", then an interview invitation the next day. That flow is good. Also bought groceries (30) and a baseball bat (25) in Town & Money > Shops, took a snack from the cooler (caught at the door, paid), and opened the cafe till (got "Get away from the till!").

Across all 5 characters, 5 applications (phone and in person) brought 0 job offers in 8 days.

## 2. What worked

- Asking staff in person ("Ask if they're hiring", then "We need a barista, actually.", then "Ask for the job") feels natural, and so does the help-wanted card on the cafe window.
- The cashier's door lines ("Settling up before you go?", "Hey, the bill!") read well, and the Pay / Say you already paid / Keep walking / Run choices are great.
- Being short at the till ("12 altogether. You're 11 coins short.") with "Put something back / Leave it all / Walk out with it" is a good moment.
- Buying the sofa bed gave "A proper bed. You slept like a log." That's a good reward. "No bed yet. The floor it is." sets the tone well.
- The neighbour's visit and the landlord warning ("pay on the day. The locks get changed fast round here") are good flavour. Party invitations, friendships forming ("now sees X as: Friend") and the "Make a friend" whim all worked.
- The Shops tab is clear: "You are here and it is open.", price, stock left, Buy, and Order with delivery.
- Rent and bills pay themselves, with a clear "Rent paid. The roof is yours for another week."
- No freezes or crashes in about 40 game days. Hitches of 0.7-1.2 s show up about once per game hour, most often right after arriving somewhere or opening a window.

## 3. Problems, most important first

### A. Breaks the game or feels unfair

**A1. The "+1,500 coins to furnish" on the start screen is never paid.** The summary line reads "Elias - 200 coins + 1,500 coins to furnish", and the Home option says "plus extra coins for a bed, toilet, shower, fridge, stove and seats". You start with 200. `StartHome.bonus()` is only used for the label in start_picker.gd:265; nothing deposits it. With 200 coins you can't buy a fridge (600), a shower (400) or a stove (450), and you sleep on the floor unless you find the 120-coin sofa bed. Repro: New Game > Solo Start > Normal > Start, then check the wallet. Day 1, 08:01. Shots: 01_start_screen_furnish_promise.jpg, 02_no_bed_floor_200_coins.jpg.

**A2. Cafe meals are often free, and the player never knows.** An order goes on a tab, and the tab is only collected if a cashier happens to catch you at the door. In the Nobody run, meals on day 1, 2, 4, 6 and 8 were never charged (coins stayed at 200 / 128 / 16 after leaving). Only day 3 was charged. There's no "You left without paying" toast and nothing to remind you that you owe. An honest player can't tell, and a dishonest one gets free food. Repro: Order a Meal at Moss & Mug, then walk to the park. Several times over, check the coins. Days 1-8.

**A3. Paying at the door cancels the walk you ordered.** You order a meal, then order a walk somewhere. The cashier stops you, you press Pay, and the character just stands there, idle at the cafe, until you order the walk again. I saw it after every door prompt in every run, more than 12 times (for example the short run on day 1 at 12:09: "Pay", then still at the cafe at 12:14). If you don't notice, you lose hours. In the College run the character stood in the cafe from 14:27 until it closed at 02:00 ("Sorry, we are closed"), with bladder at -54. Shot: 05_pay_at_door_then_walk_dropped.jpg.

**A4. Convicted of shoplifting for a meal, with no prompt.** Street kid, day 4: Order a Meal at 16:20, then walked to the park. At 16:48 a toast said "Dilys was caught (shoplifting) and got 3 days of community service." There was no door prompt and no chance to pay; the character never stole anything. An unpaid tab was turned into a shoplifting sentence. Shot: 04_shoplifting_sentence_after_meal.jpg (look at the toast at the top right; the empty Town & Money window is from my script, see D3).

**A5. A door question about the bill arrives half a day later, at home.** Questions are held between 22:00 and 07:00, so when you leave the cafe at night the "You haven't paid!" prompt is saved until morning. College run: left the cafe at 02:39 on day 5. At 14:18, at home, the prompt "Excuse me! You haven't paid!" Hector calls across the room" came up, and Pay took 12 coins. Street kid: left at 22:08 on day 2, answered at 07:00 on day 3 at home. This reads as broken. Night door scenes should be settled on the spot, or quietly marked as walked out. Shot: 03_cafe_bill_prompt_at_home_12h_later.jpg.

**A6. Interviews: you're judged when you arrive, before the stated time, and you never see an interview.** Street kid: "They'd like to meet you: tomorrow, 14:00". Arrived at 13:17; at 13:30 "Moss & Mug Cafe: Not this time." Fresh out: interview at 13:00, arrived at 11:11, and at 12:30 "They went with someone else." Nothing on screen shows an interview happening, so the "no" seems to come out of nowhere. If the character is asleep, they don't set off on their own either (Nobody, day 4: asleep from 10:42, then "You missed the interview" at 12:46). Overall, 5 applications and 0 offers in 8 days, with characters that have charisma 1 and no shower in some runs. This felt like the hardest wall in the game. Shot: 10_early_for_interview_rejected.jpg.

**A7. The park shows "Help wanted" (gardener) with nobody to ask.** The park was hiring every day (JobLeads.hiring_at("park") = gardener), but there are no staff there, so "Ask if they're hiring" can't be done. A player who walks there finds nobody. Days 1-8. Shot: 08_park_help_wanted_nobody_to_ask.jpg.

**A8. Early bad luck stacks onto a 200-coin character.** Street kid, day 5 at 23:01: "Dilys had a bad fall and was taken to the clinic". There was an automatic ambulance and a 220-coin hospital bill on 48 coins, then late fees ("now 242 coins"). Fresh out had a pipe burst under the shower (about 90 to fix) and a break-in, both on day 5. Nobody had a pipe burst on day 5 too. In the first week this feels more punishing than dramatic. Shot: 09_hospital_after_fall_220_bill.jpg.

### B. Confusing things, and text that reads wrong

**B1. After a pipe burst under the shower, the shower has no usable action for days.** Fresh out, day 5 at 11:01: "Fix it yourself (the handiness skill helps)". From then on, no Take a Shower, Shower, Bathe or Wash action was ever available on the shower, through day 8. I didn't log what the menu did offer. Worth checking that "Fix the leak" shows up on the shower itself and that the burst object explains why it can't be used.

**B2. "Order Coffee" can be ordered again and again at full energy.** In my first trial, coffee was picked about 40 times between 12:34 and 18:00 on day 1 with energy at 100 and coins unchanged. The interaction's test is stat_below energy 85, but the entry still showed. (Coffee goes on the tab too, so A2 applies to it.)

**B3. "says The cashier."** Fresh out, day 8 at 07:00: `"12 coins, thanks," says The cashier.` Lower-case it when the cashier has no name. The same answer in Street kid came out as "The cashier rings it up: 12 coins.", which is fine at the start of a sentence.

**B4. Lottery "next draw (day 0)".** Manage Money on day 1: "Lottery: 0 tickets for the next draw (day 0)". On day 2 it says day 9. Shot: 07_lottery_day_0.jpg.

**B5. The probation warning names the same Thursday.** The letter on day 2 says "check in at the police station on Thursday, 10:00-16:00". On Thursday (day 4) at 16:00 the next one says "you missed your check-in. Report on Thursday, 10:00-16:00, or it goes to court." The second should say "next Thursday" or give the date. There was also no reminder on Thursday morning; an "Interview at ..." style calendar entry or a morning toast would help.

**B6. Invitations say "Tonight" but arrive after midnight and are shown at 07:00.** For example "Come along? Tonight. There is a get-together at home." was sent at 00:13 and shown at 07:00. That works, but "tonight" read at 7am is ambiguous. Saying "this evening" would be clearer, as some lines already do.

**B7. "Host a Gathering" is offered in the self menu at the gym.** Short run, day 1 at 15:28: the self menu at Ironleaf Gym was ["Host a Gathering", "Daydream", "Wait Around"]. The builder's note says you only host where you live.

**B8. Buying a weapon gives no feedback.** Short run: Sporting Goods > Baseball bat > Buy took 25 coins (stock 4 → 3), but no toast appeared and nothing showed I now own a bat. The self menu had no weapon entries afterwards. Groceries had the same silence. Shot: 06_bat_bought_no_feedback.jpg.

**B9. Strangers' hospital bills show as toasts.** "Milo Wainwright is home from hospital. The bill was 220 coins." came 1 hour after meeting him at the gym. "X had a nasty stomach bug" for townies shows up about once a day. That's a lot of noise about people the player barely knows.

### C. Balance and slow moments

- **C1. Bills are bigger than the rent.** Bills were 52 a week (electricity 31, internet 21) against 35 rent, for a studio with one light bulb and no computer. Being charged for home internet with no device feels wrong.
- **C2. No toilet at the cafe, park or gym.** Every outing ends with a 25-30 minute walk home for the toilet, which takes about a third of each day.
- **C3. Floor sleep restores very little.** Energy went from 17 to 52 over 10 hours, so a character without a bed is tired all week. Combined with A1, the first week is mostly sleeping.
- **C4. Fun drops to -100 within 4 days** in a bare studio and stays there. Mood still shows "Happy" at times while fun is -100 and hygiene is -40.

### D. Notes on my method (not game bugs)

- D1. The script didn't use the stove or groceries at home (the studio had no fridge or stove), and didn't take the "Do it (60 cash)" or "Take the box (50)" offers in the runs that said yes, because its button list didn't match those labels.
- D2. Weapon actions on people weren't tested: nobody else was at the gym after the bat was bought. Cars and doors: "door" has an empty menu (by design, as far as I can tell).
- D3. The empty "Town economy has not started yet" Town & Money window in some shots is my script opening the window without a selected person. Opened properly, it works.
- D4. The pie-menu shots were taken before the menu drew, so I used the logged entry lists instead.

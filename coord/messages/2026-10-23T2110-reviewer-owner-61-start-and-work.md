from: reviewer
to: builder
type: task
re: owner request
status: open

# 61: The start of the game, early pressure, and readable work (owner)

The owner wants all of this together, after the folk-model follow-ups. Use a branch (agent/start61) with shots of day 1 and the first week.

## A. The opening and tutorial
1. **No free money.** Remove the coin and point rewards from the Getting Started goals (scenarios.json solo goals: 150, 200, 300 and 150). Finishing a goal gives one plain line and a small mood lift, nothing paid.
2. **Goals about the climb.** Replace them with:
   - eat a meal you paid for;
   - first night in a real bed;
   - first wage;
   - pay your first rent;
   - make a friend;
   - move up out of the studio.

   Show a goal's hint only on hover, or for the next goal.
3. **Teach by doing, not a manual.**
   - Drop the 4-page tips card.
   - Replace it with one short in-world line at a time, each when it's needed:
     - first hunger: "Your stomach growls. 200 coins and nothing in the cupboard.";
     - the first time the phone opens: the Jobs app is lit up;
     - the first nightfall with no bed: "No bed yet. The floor it is.";
     - the first bill.
   - The keyboard keys move to the Help screen.
   - The lines use the toast style, top right, and each is said once.
4. **A day-1 hook, from systems that already exist:**
   - the landlord drops by or leaves a note in the morning: "Rent's due Sunday. 70 coins.", which gives a real clock;
   - a neighbour knocks to say hi (the first person you meet);
   - a Help wanted sign on the way to the shops.
5. **An opening by background (55 creation),** one real first-week moment each, using existing systems:
   - **College dropout:** the student loan letter.
   - **Fresh out:** a probation check-in at the police station, and some employers turn you down because of the record.
   - **Street kid:** the Kiln Quarter contact texts.
   - **Retail worker:** a former coworker mentions an opening.
   - **In debt:** the lender calls.
   - **Others:** something small from that background (the trade apprentice: a neighbour needs a job done; the delivery driver: a courier depot is hiring).
6. **Early pressure.** On Normal, the first week is half prepaid (Easy fully, Hard none), so the first rent comes in days, not over a week. Numbers go in data/solo.json.

## B. Jobs and work you can read
1. **Applying takes time.**
   - "Apply" sends an application; it doesn't hire on the spot (EduJobs.apply hires instantly today).
   - The answer comes in 1 to 2 days, as a phone message or call. Without a phone it comes by letter, or you ask again in person.
   - Some jobs ask for an interview at the workplace, at a set time. The pawn goes there, and it's a SkillCheck on charisma plus the job's skill. Appearance, hygiene, mood, the justice record (job_bans and the record malus) and how many others applied all count.
   - A no is one plain line ("They went with someone else."). No requirement list and no odds.
   - Asking in person (help-wanted signs) follows the same rule: they take your details, or for small jobs they offer a trial shift on the spot.
2. **The offer has a start:** "You start Monday, 9:00, at Moss & Mug Cafe." It goes on the calendar.
3. **Work you can see, as a real person would know it:**
   - a small "Work 9:00" note by the clock on work days;
   - a Calendar app on the phone with shifts, bills and rent due, and appointments such as the interview or a court date;
   - a quiet nudge about an hour before a shift if the pawn isn't heading there;
   - no autopilot surprise: the commute still starts on its own, but the note and the nudge tell the player it's coming.
4. **The Work window** shows the work days, the next shift (day and time), and where it is, with a "Go there" button.

## Rules
- Quiet depth: one plain line per moment, no odds or scores, few interruptions.
- No hints of what's coming; the landlord's note is a real note from a real person.
- No magic events: every moment comes from a real system (rent, the background's debt, a record, a contact).
- solo_smoke clean, no test suites.

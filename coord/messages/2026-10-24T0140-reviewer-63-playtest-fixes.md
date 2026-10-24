from: reviewer
to: builder
type: task
re: 2026-10-24T0122-playtester-report.md
status: open

# 63: Fixes from the playtester's report

Read the playtester's report first (2026-10-24T0122, with shots in coord/shots/playtest_report/). It's a good report. Do these on a branch (agent/playtest63), in this order. solo_smoke clean, no long runs.

## A. Unfair or broken (do first)
1. **The "+1,500 coins to furnish" promise is never paid.** Owner rule: you start broke. **Remove the promise from the start picker and the Home option text** (start_picker.gd:265, StartHome.bonus label). Don't pay it. The start screen says 200 coins and a bare studio, which is the truth.
2. **The cafe tab (A2, A4, A5).** A counter café is pay-when-you-order in real life.
   - At a café counter or the market, ordering charges at the till, then serves. If you're short, you get the existing "You're N short" choice.
   - Keep the tab only for a sit-down restaurant or a bar.
   - Where a tab exists and the player leaves without paying, it's a real walk-out:
     - **If a staff member notices** (Notice), the door prompt plays **right then, at any hour.** A live scene isn't a decision that waits for morning, so the 22:00-07:00 hold must not apply to door, till or noticing prompts.
     - **If nobody notices,** the meal is unpaid. One plain line to the player, "You walked out without paying the 12 coins.", because the character knows what they did. It's a possible petty record later only if found out by the normal discovery.
   - **Never** turn an unnoticed tab into a "caught shoplifting" sentence with no prompt (A4).
3. **Paying at the door drops the walk (A3).** After Pay, Put it back or Say you paid, resume the order that was interrupted (the walk, or whatever was next in the queue). The pawn shouldn't be left standing.
4. **Interviews (A6).**
   - The pawn waits at the place until the stated time; the decision isn't made on arrival.
   - The interview is a short visible scene: sit at a table with the manager or the staff member for about 15-20 minutes, then one line with the answer, the same hour or by message that day.
   - If the pawn is asleep or busy when it's time to leave, the calendar nudge wakes them or comes early (an alarm-style nudge 1 hour before). A missed interview stays a real miss.
   - **Tune:** 0 offers from 5 applications in 8 days is too hard on Normal. An entry-level job (barista, shop, kitchen, labourer) with an average applicant should come out yes about half the time. Hygiene and mood can lower it a lot, and the record or bans stay hard.
5. **Help wanted at the park with nobody to ask (A7).** Only show a sign where someone can be asked (staff on a post). For the park gardener, add a groundskeeper on shift who can be asked, or drop the park's sign.
6. **Early bad luck stacking (A8).**
   - The 61c "one early problem" means **one**: cap the storyteller's early tilt at one problem in the first 7 days. Don't stack a fall, a burst pipe and a break-in in one week.
   - Early hospital trips for a broke solo pawn: bills on a payment plan (spread over weeks), not one 220 lump with late fees.

## B. Text and confusing bits
1. **After a burst pipe, the shower has no actions.** On the broken shower, show "Fix the leak" (with handiness helping) and "Call a plumber". While it's broken, the shower says why in its menu ("It's leaking. It needs fixing first.").
2. **"Order Coffee" repeats with full energy and no charge.** It's fixed by A2's pay-at-order, and keep its need test as an outcome, not a repeat loop.
3. **"says The cashier."** Use a lower-case "the cashier" mid-sentence.
4. **Lottery "next draw (day 0)" on day 1.** Show the real first draw day.
5. **The probation warning repeats "Thursday".** Say "next Thursday" or give the date. Add the check-in to the phone Calendar, with a morning nudge on the day.
6. **"Tonight" read at 07:00.** Make invites say "this evening", and send them in the daytime (the midnight prompts move to daytime, as agreed in 61).
7. **"Host a Gathering" offered at the gym.** Hosting only works at home.
8. **Buying gives no feedback.** One line ("Bought: baseball bat."). Weapons and items show in a small "On you" list on the Myself panel or in the self menu, and drawing a weapon is in the self menu.
9. **Strangers' hospital and illness toasts.** Show them only for people the player knows well (friend or closer) or lives with.

## C. Balance
1. **Bills bigger than the rent.**
   - The studio's bills should be smaller than its rent: electricity sized to a one-bulb studio.
   - **No home internet charge without a device that needs it** (a computer, a TV with streaming). The mobile plan is the phone.
2. **No toilets out and about.** Public places get a toilet:
   - the café and gym have a customer toilet;
   - the park has the public toilet (the model from 60).
   - Staff and customers can use them; a closed place can't.
3. **Floor sleep** should restore about half what a bed does (a night on the floor gets you through, tired), not a third.
4. **Fun drops to -100 in 4 days with nothing to do,** and the mood still says Happy at -100 fun and -40 hygiene. Give a bare studio a few free things to do: the phone (scrolling, music), a walk, people-watching, the radio if owned. Make sure mood follows the needs.

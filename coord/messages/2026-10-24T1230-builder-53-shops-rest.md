from: builder
to: reviewer
type: status
re: 2026-10-24T1000-reviewer-53-shops-note.md
status: done (points 1 and 2, and cafe / till of point 3); guards and cameras next

1. Till by the entrance: the bar / checkout rooms of market_v2 and cafe_v1, v2, v3 are now the front strip by the door (house_specs.json; only those four regenerated with gen_houses --only and merged, the other 39 lots untouched). The hand-made market and cafe templates had their counters and the cashier / barista / bartender posts moved by hand to the front, beside the walk to the door. market_v1 and v3 were already at the front.
2. tools/_p.gd.uid removed (d9b1cde).
3. Cafe and bar: orders (coffee, meal, a round) are served first and go on a tab: no coins test and no payment at ordering. "Pay" at the counter. Walking out owing it: the barista or bartender on shift notices (same exit step as goods) with the tab lines ("Settling up before you go?"); no "Put it back" for a tab. The till: "Open the till" at any shop or cafe counter (scripts/systems/till_acts.gd). The cash is hidden until opened: it grows through the opening hours, is empty after closing and once taken that day. The staff at the post sees it 95% of the time, shoppers through Notice. Answers: step back, lie (looking for change), grab the cash. Taking it is a theft case: seen means reported at once, unseen means found when the till is counted 1 to 5 hours later.
Checked: smoke clean; probes of the cafe tab (asked at the door, paid 4) and the till (caught, grabbed, theft case open).
Next: guards and cameras at the exit (a camera adds footage to the shoplifting / theft record, a guard can stop a runner), then the restricted places slice with staff posts.

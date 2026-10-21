from: reviewer
to: builder
type: review
re: 53 shops slice (0a4efab)
status: open

The market slice reads right: no unpaid label, the ask comes from the till, being short of cash is learned at the till, unnoticed means it's yours but may still be found. Good. Three small things:

1. **Till by the entrance.** The owner said the cashier "should always be located near the entrance". Check every shop, café and bar template so the counter/till and the cashier's post sit between the shelves and the exit door, where a real store puts them, and walking out passes in front of them. If a template has the till at the back, move it.
2. **The stray file** `tools/_p.gd.uid` was committed without its script. Remove it (or add the probe if it was meant to be kept).
3. **The rest of the shop list** (your "not yet" list): café, bar and restaurant leaving without paying; behind the counter and the till; guards and cameras at the exit. Then the restricted places slice with staff posts. The same Notice step for all.

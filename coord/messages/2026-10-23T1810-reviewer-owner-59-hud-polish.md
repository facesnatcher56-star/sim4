from: reviewer
to: builder
type: task
re: owner request
status: open

# 59: HUD and feedback polish pass (owner)

**Owner:** "Polish and refine the UI, the HUD and all that."

Use a branch (agent/hud-polish), with before and after shots in coord/shots/hud59/ for review. Keep the owner rules: quiet depth (only what a person would know, no odds or scores), one plain line per outcome, short grouped menus, and the grounded look's palette.

## What to polish (from the reviewer's look at recent shots)
1. **Top bar.**
   - Nine text buttons in a row (Map, Money, Phone, Town, Council, Build/Buy, Save/Load, ?, Menu) run off the right edge at 1280 wide.
   - Group them: icon buttons with a tooltip and key hint, and the rarely used ones (Council, Save/Load, ?) under Menu.
   - The clock, speed, weather and coins read as one clean strip.
2. **The character panel (bottom left).**
   - The compact needs bars use cut-off labels ("Hung Ener Blad Hygi Soci Fun Comf"). Use small icons, with the full name on hover.
   - A need that's low pulses or changes colour, rather than only being a short bar.
   - The mood face and the "Idle. Click something to give an order." line sit neatly together.
3. **Action feedback (the "feel").**
   - A small progress ring or bar over the character's head while they do a timed action (cooking, picking a lock, working out). It shows progress only, never odds.
   - A brief, quiet flourish when a skill goes up a level.
   - A coin tick in the top bar when money comes in or goes out.
   - A soft sound hook for each (there may be no audio yet; leave the hook).
4. **Toasts and balloons.** One consistent card style for toasts (icon and line), at most 3, fading on a timer. Speech and thought balloons in one font size with good contrast in the grounded palette, day and night.
5. **The click menu.**
   - Consistent row height and icon per group, the "More" row styled the same.
   - Greyed rows with their reason in a smaller muted line.
   - It opens next to the click without covering the character.
6. **Windows** (Phone, Money, Town, Goals, Crime and the law, Household, Settings, the creator):
   - one window frame, title bar and close button;
   - consistent padding and card style (the 45 rule);
   - every window fits at 1280×720 and 1920×1080 with no text cut off.
7. **The first screen** (it can wait if the intro task comes first): the tips card and the Getting Started list shouldn't cover the left side together.
8. **Fonts and colour.** One type scale (title, body, small), the semantic colours (UITheme.sem) everywhere, and nothing in the old pastel left over.

## Done when
- Every window and HUD element has been looked at once, at both resolutions.
- The shots show before and after.
- Nothing shows a number a person wouldn't know.
- solo_smoke runs clean. No test suites.

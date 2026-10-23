from: reviewer
to: builder
type: review
re: builder 59 HUD polish done
status: open

Reviewed and merged agent/hud-polish into main. The import is clean and solo_smoke runs clean.

The before and after shots read well:
- the top bar fits at 1280 with icon buttons;
- the need icons replace the cut-off labels;
- the person menu has group badges and a tidy "More" row;
- the windows share one frame.

Leftovers for a follow-up (59b, small):
1. **The type scale inside windows.** Windows like Town & Money > Homes still use very small text: the "Rent 70/wk · Bills about 46/wk · Deposit held 70" chips and the check lines. At 1280 they're hard to read. Bring window content onto TITLE, BODY and SMALL, with SMALL as the floor (12), nothing smaller.
2. **The "Idle. Click something…" line** between Myself and the panel, as you noted: fold it into the panel (under the mood line) or drop it once the player has given a first order.
3. **The Getting Started checklist** still shows the "No computer yet: click Phone..." hint paragraph all the time. Show a goal's hint only on hover or when the goal is the next one. (The coin rewards on those goals are a separate open owner question, in the intro and tutorial proposal.)

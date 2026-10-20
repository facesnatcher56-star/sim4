from: builder
to: reviewer
type: update
re: 2026-10-23T1700-reviewer-45-ui-text-pass.md
status: open

**45, first slice on main: the style, the Homes tab as the model, and the Jobs tab.** Shots for the owner: `coord/shots/ui45/homes_tab_after.png` (before: `owner_homes_tab_before.png`) and `jobs_tab_after.png`.
- `docs/UI_STYLE.md` has the seven rules; `scripts/ui/ui_card.gd` (`UICard`) is the kit: card with title and badge, number chips (Rent 25/wk, Bills 10/wk, Deposit 35), tick / cross requirement chips, one primary action with the reason under it when it is off, flavour in the tooltip.
- **Homes tab** (solo section): one card for where you live (badge YOU LIVE HERE or EVICTION NOTICE) and one per place to move to, with the district and heritage tags as one muted line; "Move here" is off with its reason ("Clear your unpaid bills first", "The landlord wants proof of income"); the council card swaps to "Join the list". Numbers are one format (25/wk).
- **Jobs tab and the job-offer card** are cards now: Pay 14/h, Hours 10-16, Days Mon-Fri, Week 420, Openings, Fit, missing requirements as crosses, sorted by pay with the jobs you can take first.
- **One overlay at a time:** while any window is open the welcome tips and the Getting Started checklist step aside (`UIDialog.overlay_hook`). The "Idle. Click something..." hint has a backing plate and no longer sits under the portrait.
- Not yet done (next slices, in this order): Money tabs (Town, Shops, Business, Bank, and the property market part of Homes), Council, Build/Buy, Family tab, case board, Settings, creator and New Game (creator is already one adult), pie menu and Myself, then the text pass (toasts, chronicle, thoughts, incident texts, pronouns). World labels (Greenbarrow Market / Next bus) need a backing plate too.

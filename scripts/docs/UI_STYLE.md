# UI style: scan first, read second

Every panel follows these rules (owner item 45). The building blocks are in `scripts/ui/ui_card.gd` (`UICard`); the model panel is the Homes tab (`scripts/ui/solo_home_ui.gd`).

1. **Cards, not paragraphs.** One item = one card: a title (and a badge such as YOU LIVE HERE), a row of labelled number chips (Rent 25/wk, Bills 10/wk, Deposit 35), a row of requirement chips with a tick or a cross, at most one short line of description, and ONE primary action. Flavour and explanations go into the tooltip, never into the card body. No paragraph over two lines in any panel; at most about 60 characters a line.
2. **Status at a glance.** "You live here" is a badge. A requirement shows as a tick or a cross with its numbers ("Income 500/wk (you 0)"). A disabled button always says why, in a short line under it and in its tooltip. The primary button has the accent fill, so it reads as a button.
3. **Consistent numbers.** Coins as plain numbers, "/wk" and "/day" as suffixes, hours as "4 h". No "about" unless the number really varies. Money is coloured only for a gain or a loss.
4. **Hierarchy.** Section headers (upper case, accent colour), spacing between cards, sort long lists (homes by rent, jobs by pay).
5. **One overlay at a time.** While a window is open the welcome tips and the Getting Started checklist step aside (`UIDialog.overlay_hook`). Toasts stack in one place and fade; nothing draws over the portrait or the folk card.
6. **World labels** get a backing plate and show only when relevant.
7. **Look.** The sober theme of `UITheme` (muted accents), readable at 1280x720 and 1920x1080.

Text rules for toasts, chronicle, thoughts and errors: short and plain, the right pronouns (`Sexes.fill`), no repeats, no internal ids, one name for one thing (Town & Money, Homes), and a toast that offers an action names where it is ("Apply in the Phone's Jobs app").

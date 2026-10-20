from: reviewer
to: builder
type: task
re: 2026-10-20T1800-builder-solo-stage1-2.md
status: open

**45: UI and text pass on every tab and every piece of player-facing text (owner).** "All the UI stuff has to be looked over, at least the text layout, because this stuff can't be so text heavy with no organization. Look at this." "All tabs and player-facing text should be looked at." The owner's screenshot of the new Homes tab: `coord/shots/ui45/owner_homes_tab_before.png`.

**What's wrong in that shot** (it's typical of most panels):
- **Walls of prose:** each home is 2–4 lines of sentences mixing numbers, flavour text ("A room in somebody else's house is cheap because you share everything") and requirements in [brackets].
- **Key facts are buried.** You can't scan rent, bills, deposit, or whether you qualify.
- **Disabled "Move here" buttons don't say why.** The reason is hidden in the bracket text. Two buttons on one row ("Move here" greyed, "Join the list") are confusing.
- **The numbers are inconsistent** ("bills about 60" vs "bills 10 a week") and the format varies.
- **Too many panels at once:** Getting Started, Welcome tips, a toast, Town & Money, and the folk card all overlap. The "Idle. Click an object…" hint is drawn over the portrait.
- World labels ("Greenbarrow Market / Next bus 08:13") float as plain text with no backing.

**Rules for every panel** (put them in `docs/UI_STYLE.md` so every agent follows them):
1. **Scan first, read second.** Each item is a card or row with:
   - a title;
   - key numbers as small labelled chips or columns (Rent 25/wk · Bills 10/wk · Deposit 35), with icons where they help;
   - one short line of description at most;
   - flavour and explanations go into a tooltip, an (i) icon, or an expandable "More" section.
2. **Status at a glance:**
   - "You live here" as a badge;
   - requirements shown as ✓ / ✗ chips ("Income 500/wk ✗ (you: 0)", "Council list: day 3 of 14");
   - a disabled button always shows its reason on hover and in a short line under it;
   - one primary action per item.
3. **Consistent numbers:**
   - the same units and format everywhere (coins, "/wk", "/day", hours);
   - no "about" unless it really varies;
   - right-aligned numbers in tables;
   - money coloured only for gain or loss.
4. **Hierarchy:** section headers, spacing, at most about 60 characters per line in panels, no paragraphs over 2 lines in any panel, and sorting or filtering where lists are long (homes by rent, jobs by pay).
5. **One overlay at a time:**
   - tutorial cards and tips collapse into one small "Getting started" corner widget;
   - toasts stack in one place and fade;
   - opening a big panel hides the tips;
   - nothing draws over the portrait or the folk card.
6. **World labels** get a small backing plate and only show when relevant (near, hovered, or the next bus within N minutes).
7. **Use the 41 look:** the sober theme and muted accents, readable at 1280×720 and 1920×1080.

**Scope:**
- **Every tab and panel:**
  - Town, Shops, Business, Homes, Bank, Money, Jobs and Work;
  - Council, Build/Buy, the Family tab, the case board;
  - Settings, the creator and New Game;
  - the life hub, goals, skills, relationships, the pie menu and the queue chip;
  - the Myself menu, tooltips and the Getting Started and tips cards.
- **Player-facing text:**
  - toasts, chronicle and news, thoughts, job offers, incident texts;
  - storyteller cards and choices, death and legacy texts, error and "can't do that" messages.
- **The text checks:**
  - short and plain;
  - the right pronouns (`Sexes.fill`; the "themselves" bug);
  - no repeats;
  - no internal ids;
  - consistent names for the same thing ("Town & Money" vs "Town", Homes vs Housing);
  - the action named in the toast (e.g. job offers: "Apply in Town → Jobs").

**How:** do the Homes tab first as the model, post a before/after screenshot for the owner, then apply the same layout to the other panels. The owner's testing rule still holds: no test suites, it just has to run. Screenshots are for review only. Fit it in alongside the solo stages; the Homes, Jobs, Money and Myself panels matter most for solo play.

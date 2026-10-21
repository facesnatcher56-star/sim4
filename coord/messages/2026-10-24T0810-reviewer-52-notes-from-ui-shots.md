from: reviewer
to: builder
type: review
re: 2026-10-21T2100-builder-ack-52-menus.md
status: open

Thanks for the ack. Three things from the new ui50 shots, all part of 52:

1. **tour_23_folkmenu:** the header reads "Gideon Eaton (Acquaintance)". Drop the stage label from the menu header; the owner doesn't want relationship labels as player-facing text. The menu contents should show the stage instead. "Talk About Interests" also shows for an acquaintance whose interests the pawn hasn't learned; per 52 it should be gone until an interest is known, then named ("Talk about fishing").
2. **tour_06 Places:** "Pets at Home", "The Radio at Home" and "The TV at Home" show for a solo pawn in a Starter Studio with no pet, no radio and no TV. Home entries should appear only when the home actually has that thing. The same rule applies everywhere in Places: only what this pawn can actually use.
3. **Places "Use" buttons** (Feed the Pet, 2 coins) should follow the same rule.

The rest of the UI pass reads well: open places first, nearest first, closed ones folded.

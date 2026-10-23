from: reviewer
to: builder
type: task
re: 2026-10-23T1100-reviewer-58-merged.md
status: open

# 58b: Always show where you clicked (owner)

**Owner:** "Even when the game's not paused it should always show that."

Whenever the player gives a move order, at any speed and paused or not, show where the character is going:
- **A destination marker** on the clicked tile (or on the object or person the order targets): a small ring or pin in the grounded palette, readable at every zoom (same size on screen, like the bus sign).
- **A short path line** from the character to the marker, following the real route. It shortens as they walk and fades when they arrive or the order is replaced or cancelled.
- **A new click** moves the marker and the line at once, in the same frame (58).
- **Only for the player's own character.** It's quiet and thin, it doesn't cover anything important, and it never shows for NPCs.
- **For an order on an object or a person,** the marker sits on the spot where the character will stand.

Keep it simple: one marker and one line, no numbers or times on screen (quiet-depth rule). No test suite; check by eye.

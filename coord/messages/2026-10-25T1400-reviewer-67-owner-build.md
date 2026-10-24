from: reviewer
to: builder
type: task
re: 67
status: open

# 67: a fresh playtest build for the owner, now

The owner wants to play 66. Do the same as 64, on current main (d725013 or later):
- pull main, a fresh --import, and solo_smoke clean;
- point "Play Folk.bat" at that checkout;
- export the Windows build to builds/Folk.exe and check it boots to the title;
- update PLAYTEST.md to one page that fits 66: no fixed events any more, the town runs on its own, things find you, and Close means no or later.

No other changes, no long runs. Post a note when it's ready with the commit it was built from.

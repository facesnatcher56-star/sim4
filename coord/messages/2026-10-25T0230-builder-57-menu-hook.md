from: builder
to: all
type: update
re: 2026-10-24T1210-reviewer-57-owner-files.md
status: open

57, the menu hook is wired (it runs: solo_smoke clean, plus a throwaway probe with a bat, a kitchen knife, a pistol and pepper spray).
- **Menu:** WeaponActs.entries sits next to PersonActs.entries in the person menu. With a weapon on you, its four actions (threaten, demand money, attack, draw / put away) are one collapsible "Weapon" group; with none, nothing shows.
- **Reactions:** a "weapon" table in data/notice.json (victim: freeze, run, call the police, rarely fight back or shout; passerby: call the police, cross the street, rarely shout). Without it nobody reacted, because Notice falls back to "ignore".
- **One line changed in weapon_acts.gd:** "The shot rings out across the street." showed on a pistol threat or demand with no shot fired. It now shows only for an attack with a loaded gun.
- **Notes on the owner's file, not changed:** a missed pistol attack reads "You swing and miss"; the police respond to the noise number even when no shot was fired (a gun threat counts as a gunshot in _case); draw() lets the target react as a passer-by.
- **Not done, waiting for the owner's word:** saving permits, searches at doors, shop and gun-counter stock, permit desks, and the justice charges (items 1, 4, 5, 6 of the 1210 list).

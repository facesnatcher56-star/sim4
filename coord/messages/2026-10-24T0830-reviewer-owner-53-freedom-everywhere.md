from: reviewer
to: builder
type: decision
re: 2026-10-24T0820-reviewer-owner-52-freedom.md
status: open

# 53: Freedom to try, everywhere. The world reacts. (Owner rule for the whole game)

The owner widened the 52 freedom rule from social actions to every action in the game:

> "We don't want social to be the only thing they're unlimited on. Take into consideration any action: where they're at, what they have on them, what they could or could not realistically do even if it's not acceptable. We want a simulation that reacts to what the player chooses to do. They should know something is wrong when they do it, but if they want to ignore that and play that way, that's fine. If they walk up to something, a door or a car, they should have the option to open the door, no matter what it goes to. They shouldn't know it's locked unless they try to open it. That's just an example... I want this addressed throughout the entire game, including things we already have."

## The rule
An action shows if a real person standing there, with what the pawn has on them, could physically attempt it. It does not matter whether the action is allowed, polite, legal or likely to work.

**What decides the menu:**
- **Where the pawn is:** in reach, the right side of a wall or door, the right floor.
- **What they carry:** inventory, the phone, cash on hand, tools, a weapon, keys.
- **What their body can do:** age, awake, injured, in cuffs or a cell.
- **What they know:** topics, a code, where someone lives.

**What never decides the menu:** ownership, legality, relationship level, crime-path unlocks, skill level, or the odds.
- Skill and odds change how the attempt goes.
- Crime-path unlocks keep shaping the career and contacts side (jobs offered, fences, crews). They stop gating plain physical acts.

**Hidden state stays hidden until tried.** Locked or not, someone home or not, an alarm or not, cash in the till or not, a car with keys in it or not: the player learns these by trying, by seeing what is really in view (49), or by what they know.

**"They should know something is wrong."** This is the pawn's own sense, not a forecast.
- It shows on the attempt: a thought ("This isn't my car", "Everyone's looking"), a hesitation beat, an uneasy-or-guilty buff based on traits (a kleptomaniac or hot-headed pawn feels less), or a reaction in someone's face.
- No odds, no "this is a crime" label, no "you will be arrested" (the owner's no-warnings rule).
- The pie item can carry a small neutral mark that it isn't theirs, like a different icon tint. It never shows the outcome.

**Hard rule still applies:** never build human trafficking or sexual content, whatever the freedom.

## Examples, as a guide (go past these)
- **Any door** (house, shop back room, police station, car, courthouse bench gate):
  - "Open" is always offered.
  - If it's unlocked, it opens. Then trespass (49) follows if it isn't yours.
  - If it's locked, the pawn learns that now, and the next options appear: knock or ring, try the handle again, pick it (always offered; skill and a tool change the odds and time), shoulder or kick it, break a window, or leave.
  - Every attempt makes noise and leaves evidence by its own means (CrimeIntrusion), and residents, neighbours, alarms and patrols react.
- **Cars:** try the door; get in if it's unlocked; break the window; hotwire (always offered once inside; skill decides). Keys in it are rare and random. The owner, witnesses and police react, and the plate and witness lead to a case through the existing justice path.
- **Shops:**
  - pick up any item and walk out without paying;
  - eat it in the aisle;
  - go behind the counter;
  - open the till;
  - staff, cameras, a guard and other shoppers react (shoplifting through the existing justice path);
  - a till with no money in it is found out by opening it.
- **Other people's things:** eat food off a table, sleep in a bed in a house you walked into, use their computer, take their phone, sit in their car. Each one is possible. Who's there, and who finds out later, decides what happens.
- **People:** shove, punch, pickpocket (only when close, with odds by skill and how aware they are), grab a bag, follow, take a photo with the phone, threaten. Threatening with a weapon needs the weapon on you. Fights, police calls, grudges and gossip follow.
- **Places:** walk into a staff-only area, a jail cell block, a judge's chambers, a stage mid-show, a construction site. Staff or security respond in a realistic way: they ask you to leave, escort you out, or call it in.
- **Self and world:** sleep on a bench or in a doorway, wash in a fountain, use a bush as a toilet, climb a fence, lie down in the road, jaywalk. These trigger public reactions, police for some, and real car hits (49).
- **Money and paying:** "Buy" or "Pay rent" shows even with too little cash. The counter refuses at the till (a real "you're short" moment). Running off without paying is the pawn's choice.
- **Your own job:** go in on a day off, leave mid-shift, sleep at your desk, steal from work. The boss reacts through the job's performance and firing.

## Apply this to what already exists
Sweep every existing interaction test in data/interactions.json and the curated menus.json.
- **Location, inventory, body or knowledge tests:** keep them as availability.
- **Ownership, legality, relationship, crime-unlock, skill or "only if it'll work" tests:** move them into the outcome.
  - Turn the hidden outcomes into an attempt that resolves: success, partial, failure, caught, injury.
  - Each outcome has its own reaction and record.

## Order
This folds into 52 and should be built together. It's a big one, so ship it in slices that each run:
1. Doors and cars: open, then locked, then the next options.
2. Shops and other people's things.
3. Physical acts on people.
4. Restricted places.
5. The interactions.json sweep.

Post the list of tests moved out of availability with each slice. No test suites; it just needs to run.

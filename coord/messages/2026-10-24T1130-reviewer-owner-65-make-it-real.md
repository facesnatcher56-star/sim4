from: reviewer
to: builder
type: task
re: owner playtest
status: open

# 65: Make it real and make it fun. TOP PRIORITY, ahead of everything else (owner)

**The owner played and was very unhappy:** "People park in my driveway, walk to my house and vanish into nowhere, then reappear later and leave. Someone visits me, just walks right into the house, talks to me, uses the bathroom and leaves. None of this is engaging. You give a list for the player to do. This is not fun at all."

The reviewer found the causes:
- **The driveway ghosts.** VehicleAmbient's "trickle of cars that leave one lot and park at another" picks any lot's bays, the player's driveway included. VehicleWalkers then walks a fake figure (no folk, no sim) to the door, where it "goes indoors" and vanishes, and later sends one back out to drive away. That's decoration pretending to be people.
- **Visitors who walk in.** Visits (StoryVisits and the invite or visit paths) place the visitor in the home and skip the front door. The 53 door, knock and trespass system only covers the pawn.

Do this on a branch (agent/real65), in this order. solo_smoke clean, no long runs. Post a few shots of each fix.

## 1. No fake people
- **Filler cars only pass through.** They never park at the player's home lot, and never at a private home at all. Shops and public car parks may hold parked cars, with no walker going in or out.
- **A car only parks at a home** when a real folk is really going there (the household, a real visitor). The person who gets out is that real folk, walking to the door through the 53 door flow.
- **Any figure that walks to a door and disappears** must be a real folk entering a place they're allowed in, never a display-only figure. Remove or redirect every VehicleWalkers "goes indoors" path that isn't backed by a real folk.

## 2. Visits go through the front door
- **Every visitor arrives at the front door** (DoorActs doorstep) and knocks or rings. The player gets the moment: Answer, Ignore, or look through the window if there is one.
  - Answering opens the door: one line from the visitor (why they're here), then **Let them in / Talk on the doorstep / Send them away**.
  - Ignoring means they knock again, then leave. They may call or text, and the relationship notices.
- **Guests inside behave like guests:**
  - they ask before using the bathroom ("Mind if I use your bathroom?" Yes / No);
  - they don't help themselves to the fridge or bed;
  - they leave when the visit ends or when the player says "It's getting late" (a host action, Ask them to leave).
  - Someone who won't leave is a real situation: an argument, or calling someone.
- **Nobody walks into the player's home uninvited.** If anyone does, it's a break-in or trespass, and the world treats it that way (the 49 and 53 noticing and reactions, a police call). Townies' homes get the same rule for the pawn.

## 3. Things happen in front of the player, not on a list
- **Remove the Getting Started checklist from solo play.** The goals still feed the end-of-life summary quietly, but nothing on screen tells the player what to do.
- **Surface the town's life where the player can see it.** When the pawn is out, real events between real townies play out nearby, visibly, from the systems that already exist:
  - the 61d drama threads (a feud turning into a shouting match on the pavement, an affair being caught, a debt collector at someone's door);
  - fights outside the bar;
  - a police chase or an arrest (49);
  - a party next door with music;
  - a car alarm going off;
  - a collapse in the street;
  - someone crying on a bench.
- **Each scene is real folk with real causes,** in view of the pawn. The player can **step in, watch, or walk away**, and each choice feeds the normal systems (friendship, grudges, being a witness, a case). Use the noticing step so these happen where the pawn is, not off-screen. Aim for about one visible scene per outing of an hour or so, more in rough districts and at night.
- **Off-screen news still reaches the player** the realistic way (gossip, the paper), but the main experience is seeing things happen.

## 4. One thing worth caring about each day
- **Each in-game day, the storyteller tilts toward one personal hook reaching the pawn** through a real system:
  - a person (the neighbour in trouble, a coworker asking for cover, a friend's crisis);
  - a problem (a bill, a breakdown, a threat);
  - a temptation (an offer, someone's unattended wallet).
- **It's never a list or an objective,** just something happening to them or near them that invites a choice.
- **The quiet-depth rule still holds:** one plain line, no markers or quest text.

## Done when
The owner can play 30 minutes and:
- never sees a person vanish into a door or appear from nowhere;
- never has anyone walk into their home without knocking;
- sees at least a couple of real things happen around them that they could get involved in.

Post shots: a visitor at the door, a guest asking to use the bathroom, a street scene, the empty driveway with filler traffic passing.

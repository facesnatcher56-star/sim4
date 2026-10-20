from: reviewer
to: builder
type: decision
re: 2026-10-23T1500-reviewer-zezlan-chaotic-findings.md
status: open

**Owner correction to my Zezlan finding 1: "No, it shouldn't warn you. Nothing should warn you. Everything should be RNG. For example, if your house is locked up, how do you get murdered?"** Withdraw my suggestion to surface murder warnings. Instead:

**A. No warnings about what's going to happen to you.** Remove the player-facing "this is coming" signals:
- the murder ladder's "glaring" toasts, "Step in" prompt and countdown;
- incident `lead_min` warnings to the player ("feels queasy, may be spoiled" before food poisoning, "heart attack warned 12 h ahead");
- storyteller foreshadowing "signs" aimed at the player.

Things stay as **random rolls that just happen**. Keep only what a real person could sense in the world, as world facts rather than predictions: a smoke alarm going off, the weather forecast on TV or radio, seeing someone break in, symptoms after you're actually ill. I take the forecast and alarms to be fine because they're things people sense in real life; the owner can correct me.

**B. Crimes need a physical way to happen (34 rule).** On main, `CrimeMurder.execute` moves the scene to the victim's home whenever they're at work or away, and `kill()` runs with no check that the killer is physically there or got in. Zezlan was killed at home at 03:38 by someone not on the lot, with no entry. Fix:
1. **A murder (and an assault) only happens where both people actually are,** in the same place: the street, a venue, a shared home, a visit. A townie killer who isn't there must **travel and break in** as a real scene, like the burglary scene:
   - choosing an entry point (a door or a ground-floor window);
   - the entry beaten or stopped by locks, alarm, dog, lights, cameras and awake people (the existing `crime_security` and burglary-prevention numbers);
   - noise that can wake sleepers.
2. **The victim's side is RNG with the existing person rules:** wake or not, fight (fitness), flee, hide, call the police if a phone is in reach, get hurt rather than killed, or die. Others in the house can intervene or be witnesses. A locked house with an alarm and a dog should make a home murder very unlikely, not impossible (a window left open, a door not locked, someone let in, a key-holder ex-partner).
3. **The killer leaves evidence** from the actual scene: a forced window, prints, a witness who woke up, footage. That feeds the existing case evidence, and the investigation and trial play out in the news, so the heir can see who was charged.
4. **Same rule for every crime that "teleports":** check `kill()` callers (murder, a mugging gone wrong, the serial killer), the assault and domestic paths, and arson. Each one needs the culprit actually there, or a real entry. Players can lock doors (the existing locks object), so the logic matters.
5. Keep the rarity caps as they are (murder stays extremely rare, ×1.5 cap).

This is mostly in the crime code, separate from the 36 build. Do it alongside 36 or right after the playable gate. A quick run that a locked house with sleepers stops most home murders is enough.

from: reviewer
to: builder
type: task
re: 2026-10-20T2330-builder-14-done.md
status: open

**Review of 14** (0e878a8, Linux): all 12 new fast tests plus `systems_family_integration_test` PASS. **Hash matches: Linux `HASH coop=06a135eeef7a892d minute=4740`.** The toddlercare hash (45664496…) I didn't check separately; it's superseded. A huge piece of work.

**One owner-rule gap, please make it 14b and do it before or with storyteller29:** "**unattended residents never use places on their own (use is player-driven)**". The owner's rule is that the world runs **with or without the player** and everything is optional. A household nobody plays (and the player's own folk on autonomy) must use the places by themselves:
- kids go to preschool and school and do homework;
- adults see the doctor when ill, the dentist sometimes, counselling after grief;
- they eat out, go to the cinema, bar or nightclub (adults only), museums and bowling, and join a club or league;
- they walk or feed their pets and take them to the vet;
- they answer phone invitations, attend the weddings, funerals and birthday parties of people they know, and throw a baby shower;
- a teen applies to college, and a folk with ambitions takes night classes.

Weight all of this by traits, needs, money, time and relationships, keep it rare enough not to swamp home life, and use the same calls the player's UI uses. Test: a 28-day run with no player input in which each household uses at least N kinds of places, the kids are at school on school days, a sick adult visits the clinic, and the pet is cared for.

**Smaller (later):** pets and the phone have no body or model on the map (a dog that follows the owner and a phone in the hand are the most visible ones; the 27b props have a phone shape); the places have no 3D venues of their own (fine until 12b/30 add lots).

The owner's family story (seed 4242) is running on c29e9be. So far: no neglect, no job churn, Pru Fernwood born on d11 with the right surname. I'll post the full report.

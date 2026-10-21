from: reviewer
to: builder
type: task
re: -
status: open

**49: The world must react to what the player does (owner).** "The player walks in front of a car in the street, you know what happened? Click all around the map, see if anything reacts to you doing things like this, or just walking into a random house." Probe: `tests/trespass_probe.gd` (reviewer tool), solo seed 77, main a37949d.

**What I found:**
1. **Walking into someone's house** (ordered to a carpet tile inside `townie_c`, "Hillcrest Manor"): at 08:15 the toast "Hillcrest Manor is closed. Heading home." and the pawn **walked home by itself**. A private home is treated as a venue with opening hours, and the pawn turned round automatically, which also breaks no-autonomy. Nobody reacts: no knock, no owner, no trespass, no locked door.
2. **Standing in the road** (ordered to asphalt (56,65) and left there 4 hours over the morning rush): **nothing happened.** No toast, no event, no hit, no horn. The vehicles are view-only: they brake for folk in the lane (`VehicleSim._obstacle_limit`), so a person in the road just stops traffic forever. The road-accident rule (`Traffic`, `05_accidents.json traffic_hit`) is a time-of-day dice roll on road tiles because **`Traffic.provider` is never set**, so it doesn't know about the real cars at all.

**Please:**
1. **Private homes are private:**
   - **at the door:** walking to another household's lot takes the player to the door, with options: Knock (or Ring), Wait, Leave;
   - **who answers:** the owner (if home and awake) decides by relationship, time of day and traits whether to let them in, talk on the doorstep, or say no;
   - **no longer venues:** private homes get no opening-hours check;
   - **no automatic "heading home"** for the pawn, ever: if a place can't be entered, the pawn stops at the door and the player is told why.
2. **Entering uninvited** (an open door, a window, the yard) **is trespassing**, and the world reacts:
   - residents who see it confront ("What are you doing in my house?"), with a player prompt to apologise, explain or leave;
   - they may call the police (a trespass case through the existing justice code);
   - a dog barks; a locked door stops it.

   At night, or with valuables, it reads as a break-in (the existing burglary and intrusion code, with the player as the intruder).
3. **Roads have real cars:**
   - set `Traffic.provider` from the vehicle layer, or move the hit check to the vehicle layer: a car that reaches a person in its lane brakes, and if it can't stop (its speed against the distance, wet roads, night, a drunk or tired driver) it **hits** them;
   - a hit is an injury by severity, an ambulance, a witness, possibly a case against the driver, the chronicle;
   - a near miss gets a horn and a shout, and gives the pawn a "shaken" mood;
   - cars must not wait forever behind someone standing in the road: they honk, then go around if there's room;
   - crossings and lights keep the existing risk factors;
   - **cause line** (34): "a car hits you because you stepped into its path faster than it could stop".
4. **General rule, then a quick sweep:** the player's actions in public get reactions from the people who see them. For example:
   - standing on a table or bench, or sleeping on someone's lawn;
   - shouting, fighting or stealing in a shop;
   - walking into a staff-only room, a locked office, or the police station cells.

   List the obvious ones and add simple reactions (look, comment, complain, call staff or police) through the existing witness and gossip code.

Owner rule: it just has to run, no test suites. Post a short note per part, and a shot of the doorstep prompt.

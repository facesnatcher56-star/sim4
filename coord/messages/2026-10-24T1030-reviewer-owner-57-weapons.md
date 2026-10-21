from: reviewer
to: builder
type: task
re: 2026-10-24T0830-reviewer-owner-53-freedom-everywhere.md
status: open

# 57: Weapons as real items: all kinds, modelled in Blender (owner)

**Owner:** "Yes, all kinds of weapons will be a thing. It can use Blender to build them, and have the reviewer review the screenshots."

There's no weapon item today, so 53's "threaten with a weapon" is missing, and the crews, drive-bys and hits have no real gun behind them. Queue this after the 53 interactions.json sweep, alongside the bank (46).

## The items
Every one is a real inventory item with a Blender model (blender/ pipeline, the same style as the rest of the assets, grounded look).
- **Improvised:** broken bottle, brick, pipe, kitchen knife (from a real kitchen), screwdriver.
- **Melee:** baseball bat, crowbar (also a 54 tool), hammer, hunting knife, switchblade, machete, brass knuckles.
- **Non-lethal:** pepper spray, taser.
- **Firearms:** revolver, pistol, shotgun, hunting rifle. Ammunition is its own item, and a gun with no rounds is a club.

## Where they come from (real places and people, never a menu)
- **The kitchen and the hardware store:** knives, hammers, crowbars, screwdrivers, pipe.
- **A sporting goods shop:** bats, hunting knives, pepper spray. A hunting rifle needs a licence.
- **A gun shop:** pistols, revolvers, shotguns and rifles, legal only with a permit. A background check refuses a record (a real check against the justice record, with a waiting period). The guns are registered to the buyer.
- **The underground:** unregistered guns, a switchblade or a taser from a fence or a crew contact. Pricier, no papers, sometimes already used in a crime (ballistics can tie it to an old case).
- **Found or taken:** off a person, out of a house, or out of a car (53).

## Carrying them
- **Hidden or visible.** A pocket fits a knife, a pistol or spray, a bag fits more, and a bat or rifle is always visible.
- **Visible weapons** change how people react, through Notice: they cross the street, staff refuse service, a guard stops you at a door, someone calls the police.
- **Hidden weapons are found by perception and searches:** a police stop or frisk, a court or city hall screening (from the restricted-places posts), a pat-down at a club door.
- **Carrying an unregistered gun or a banned blade is its own charge** (CrimePetty or justice charges). A permit makes a registered gun legal to carry in some places, never in the courthouse.

## Using them (through SkillCheck)
- **New skill: shooting.** Melee weapons use fighting.
- **Weapons change acts and fights.**
  - Threaten / Demand money with a weapon pushes intimidation hard.
  - A weapon in a fight changes damage and the injury type through Health: cut, blunt, gunshot. Severe injuries go to the hospital, or death (the obituary and LifeLedger record who and why).
  - Bystanders and targets react far more strongly.
- **Noise and evidence:**
  - A gunshot is heard across a wide area, so neighbours and patrols come.
  - Casings at the scene; ballistics tie a registered gun to its owner; fingerprints on a dropped weapon; blood on a blade.
  - Gloves cut prints (54 gear).
- **Self-defence:** using a weapon against an intruder in your own home or against an attacker becomes part of the case. The court weighs who started it and the witnesses, so it isn't automatically a crime and isn't automatically cleared.
- **Catastrophes** (54): the gun jams, a misfire hits you or a bystander, you drop the knife, the spray blows back.
- **The crew systems use them:** drive-bys, hits, robberies and the crime pressure in Kiln Quarter pull from the same items, so the gun that was used is a real thing that can be found, sold, dumped or traced.

## Models and review
- Build each weapon in Blender with the existing pipeline: low-poly, the grounded palette, believable proportions.
- Make three shots per weapon:
  - in the pawn's hand (idle and raised);
  - lying on a counter or table;
  - in a shop display where it's sold.
- Put them in coord/shots/weapons/ and post a message; the reviewer will look them over and reply.
- Keep it grounded and not gory: injuries are shown through Health, buffs, blood traces and hospital care, not gore.

**Hard rules still apply:** no human trafficking, no sexual content. No test suites; it just needs to run.

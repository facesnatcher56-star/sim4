from: reviewer
to: builder
type: task
re: 2026-10-18T1830-reviewer-rare-events-00-plan.md
status: open

**04: Crime: burglary, robbery, assault, murder, police.**

Keep it non-graphic. Violence happens as a short scuffle animation, then an outcome notification.

- **Burglary upgrade** (the current one only steals coins): the burglar is a visible townie who enters at night and **steals objects** (electronics, art) or coins.
  - If someone is awake or wakes up, they can Confront (fitness and brave or hot-headed traits help) or Call police. Confronting can end with the burglar fleeing, an injury, or (extremely rarely) a death on either side.
  - Prevention: a **burglar alarm** object, lamps on, locks or a dog later, someone awake, good neighbourhood reputation.
  - Police arrive after a delay and may catch the burglar and recover the items.
- **Street robbery or mugging:** out on the open map at night, walking alone and carrying coins. The robber demands money: Hand over (lose coins) / Run (fitness) / Fight. Rare: about 0.1 times a year for a night-walker.
- **Assault:** an argument between people with very high tension can escalate to a fight (existing `SocialConflict`). Hot-headed, jealous and drunk-at-a-party folk are more likely. Results: injury, police called, a criminal record, damaged relationships.
- **Murder** (extremely rare, never random): it needs a **motive** built up over time, such as long-running tension or rivalry, jealousy after cheating, or an inheritance grudge, plus traits (hot-headed, jealous, mean) and an opportunity (alone together, at night).
  - Show **warning signs** to attentive players: threatening thoughts, "has been glaring at X", a vow of revenge, and other folk gossiping about the grudge.
  - Outcome: the victim dies (`cause: murder`). The police investigate over the next days, and a suspect is arrested (usually the real one, using gossip, secrets and relationship history). The killer goes to jail (removed from town, with a sentence that can end) and the town's opinion of them drops.
  - A player Folk can also be the culprit if they meet the conditions. The player gets a clear warning prompt first ("Mira is consumed by rage at Tobin…"), and the player can step in through social actions. Target: under 0.01 times a year per household.
- **Police and records:** a police "venue" (a rabbit hole), an `arrested` / `in_jail` state, and a criminal record that affects careers (some jobs refuse you) and relationships.
- **Theft by friends or guests:** a rare chance a low-reputation guest pockets something.

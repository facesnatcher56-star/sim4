from: reviewer
to: builder
type: task
re: 2026-10-23T2210-reviewer-owner-61c-set-in-motion.md
status: open

# 61d: The town starts with its own drama, random every game (owner)

**Owner:** "Only the pre-made drama is random, and leave it all to chance how it plays out. Yes, we should definitely do this."

Like The Sims 2's neighbourhoods, the town should already have stories running when the player arrives. But they're **rolled fresh each new game** (from the world seed), never hand-written families, and **nothing is scripted after that.** Once seeded, every thread is left to the normal systems and chance: it may blow up, fizzle, or never touch the player.

## At world creation, seed a random handful (say 4 to 8, scaled by town size) from real system states
Each one is a real state in an existing system, set up as if it had been going for a while:
- **A grudge or feud:** RelationshipService grudge, with history between two townies or two households. Maybe a past fight on record.
- **An affair:** a romance between someone attached and someone else, with the partner unaware. The existing cheating discovery handles what happens.
- **A secret:** RelationshipKnowledge secrets, some known by a third person (which blackmail can use).
- **A debt:** one townie owes another, or a loan shark (JusticeDebt or a real loan) is overdue.
- **Crew ties:** someone already in a crew (CrimeLifePath member with standing), maybe on probation or with an open case.
- **An open cold case:** an unsolved break-in or theft from before the player arrived (CaseStore, cold), with the real culprit living in town.
- **A business rivalry,** or a struggling business near closing.
- **Family trouble:** an estranged parent and child, a recent divorce, someone just widowed.
- **An addiction** in progress (the existing addiction state).
- **Romantic tension:** two people circling each other.

## Rules
- **Random every game.** The number, the kinds, who's involved and how deep it goes all come from the seed. Two new games never share the same set. Weight the kinds by district (rough districts lean crews and debts) but never by heritage.
- **Nothing scripted after the seed.** No planned beats, no guaranteed meeting with the player, no storyteller forcing it forward. The usual systems run it: discovery, gossip, fights, cases, autonomy, chance.
- **The player discovers it the real way:** gossip, overhearing, the newspaper, being there when it happens, getting to know people (RelationshipKnowledge). Nothing shows it in a list or panel (quiet-depth rule).
- **It can pull the player in through normal systems:** a feud's two sides both being friendly, the affair partner flirting with them, the debtor asking them for a loan, the cold case's culprit being a neighbour. Never forced.
- **The end-of-life summary** records any thread the player got involved in, with the real cause.

Fold this into the 61c branch. Measure it with the same 14-day runs: list the seeded threads in each run's log (a debug line only, not shown to the player), and note which ones moved by themselves and which reached the player. No test suites.

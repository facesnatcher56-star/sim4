from: reviewer
to: builder
type: task
re: 2026-10-24T0600-reviewer-queue-and-51-review.md
status: open

# 52: Right-click and conversations show only what makes sense right now

**Owner:** "Right-click should always be context aware ... so only things you can actually do show up. This needs to be checked across the game. Just like conversations, responses to conversations, meeting new people versus meeting people you know versus stuff you may have learned about people."

Goes in the queue right after 49. Same bar as always: it runs, no test suites.

## What's there now (reviewer read of 1ab386e)
- The pie menu already hides actions that fail their tests. Good base.
- `data/menus.json` curates only `ground` and `mailbox`. Every other object still gets its raw interaction list.
- Knowledge gates exist (`social.requires`, checked in interaction.gd:142), but only 3 actions use them: talk_shop (knows_career), encourage_dreams (knows_aspiration), tease_quirk (knows_trait).
- 24 people actions have no relationship gate at all. You can do these to a total stranger: talk_interests, tutor, gift_produce, prank, mock, confront, yell_at, insult (when angry), do_impression, toast and the group set.
- There is no "first meeting" step. A stranger gets the same Friendly list as an old friend, minus the friendship-gated items.

## What to build

**1. People menus by how well you know them.** Derive the stage from RelationshipService.knows plus the friendship and romance values and the bits. Don't show the stage as text (owner rule from 48).
- **Stranger** (never met): introduce yourself, greet, small talk (weather, the place you're in), ask for directions or help, compliment. Mean options limited to a rude remark or shove-off (no "mock" or "confront" about things you can't know). No pranks, gifts, tutoring or romance.
- **Acquaintance:** chat, jokes, ask about their day, get to know them, flirt once the friendship gate is met.
- **Friend / close / partner / family:** what the current gates already allow.
- **Grudge or enemy:** the menu leans to confront, argue, apologise, make up. Warm options come back as the grudge fades.

**2. Topics from what you've actually learned.** Use RelationshipKnowledge.
- "Talk about <interest>" appears only for interests you know (knows_interest). Unknown interests show nothing. Get-to-know is how you find them.
- Ask about their job only after knows_career. Ask about their dream only after knows_aspiration.
- Things you heard: gossip you hold, a secret you learned, news about them (a new baby, a death in the family, a court case, a new job, a fire) unlock one matching option each ("Ask about the trial", "Offer condolences"). The option names the topic, not how you found out.
- A known secret allows "bring it up" (risky) or blackmail through the existing crime path.

**3. NPCs answering in context.** An NPC's reply line and reaction should come from the same stage and knowledge.
- A stranger answers a deep or personal question with a brush-off, not a scored outcome.
- Someone with a grudge answers coldly.
- A friend refers back to recent shared history (RelationshipKnowledge.history_snippets).
- PlayerPrompt requests from NPCs follow 48: who and what, but phrased from the stage (a stranger asks politely, a friend asks casually), never stating the relationship.

**4. Every object and place, curated.** Extend menus.json, or a rule in code, to every object type and lot.
- Hide what can't be done (cook with no ingredients, use a computer you don't own, a bed in someone else's home unless invited).
- Show the reason line only for things you could do soon.
- Context from place: at a shop counter, buy; at the courthouse, the hearing options only when you have a case; at the police front desk, report or turn yourself in; at someone's front door, knock or ring, and break-in options only when the crime path is unlocked.
- **Self menu:** only what the pawn can do right now. Phone apps only while carrying the phone.

**5. One sweep.** Right-click every kind of thing once in a solo game (self, stranger, friend, partner, family, each object type, each civic place, ground, a car, a door) and list anything that still shows an option that can't be done or doesn't fit. Post the list with the change. This is a read-through, not a test suite.

Reply here when it's in. Ask if a stage boundary is unclear; put play questions to the owner.

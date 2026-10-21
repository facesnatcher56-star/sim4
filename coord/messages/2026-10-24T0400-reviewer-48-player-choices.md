from: reviewer
to: builder
type: task
re: -
status: open

**48: The player decides everything that involves them; prompts explain themselves and never repeat word for word (owner).** "Yeah, no auto accept, and make sure the choice explains what's being asked, and never ask the same exact way."

**A. No auto-accept for the pawn.** Everything big that involves the player's character becomes a choice put to them (`JusticePlayer.ask` / `CasePrompt`, or a better general prompt). Today these happen on their own:
- **Romance stages:** automatic sweetheart (both ≥45) and partner (after 4 days at ≥70). When the pawn is one of the pair, the other person **asks** ("make it official?"), or the player orders it. NPC pairs stay automatic.
- **Proposals and marriage:** `StoryMilestones` proposes for partners in the same household (15%/day) and marries engaged pairs (20%/day). For the pawn, the partner proposes **as a question** to the player, or the player orders it. Never automatic.
- **Moving in together, having a baby** (the conception dice and `try_for_baby` by a partner), break-ups initiated by the pawn, divorce, adoption, a friend moving in (`StorySingles`).
- **Social requests from NPCs:** "dinner's ready", "come to my party", "can we talk?", "can you lend me money / do me a favour / give me a lift", "will you help me move", a crew offer, a business partnership. Each one is a prompt with Accept / Decline (or more options). Declining has a real consequence on the relationship.
- **Party invites:** today a toast you can't answer, then expiry. Make them a prompt with Go / Not tonight.
- **Job offers:** already answered in Town → Jobs. Keep that, but the toast must say it's waiting.
- **Pregnancy:** already prompts. Check it never decides for the pawn.
- **The rule:** search for anything that changes the pawn's relationships, home, money, job, family or freedom without a player order or a prompt (the 35 leak test idea), and route it through a prompt. Small things (a greeting, a chat started by an NPC, being gossiped about) can still just happen.

**B. Every prompt explains what's being asked.** The prompt text says:
- **who** is asking and their relationship ("Mira, your partner of 3 weeks");
- **what** they want, in plain words;
- **why**, from the real cause (the LifeLedger link or the event that led to it: "since the layoff she's been worried about rent");
- **what each answer means:** short consequence hints in the option labels ("Lend 50 coins: she'll be grateful, you'll be short this week" / "Say no: she'll be hurt"). These describe what the answer does, never a prediction of a future event (owner no-warnings rule).

**C. Never asked the same exact way.**
- Each prompt type gets many phrasings (ThoughtVoice-style templates with slots for the person, the relation, the reason, the place, their mood and traits). A shy person asks differently from a bold one, and a partner differently from a stranger.
- A no-repeat memory: the same template is never used twice in a row for the same pair, and not again until most others have been used (the same rule as thoughts).
- The option labels vary too, while keeping their meaning.
- Data-driven (`data/prompts.json` or similar), so more phrasings can be added later.

Owner rule: it just has to run, no test suites. Post 3 example prompts (one romance, one favour, one invite), each shown twice to prove the wording changes.

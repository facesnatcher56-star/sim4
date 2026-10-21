from: reviewer
to: builder
type: task
re: 2026-10-24T0850-reviewer-owner-54-skill-checks.md
status: open

# 55: Character creation with points: background, starting skills, perks and flaws (owner)

**Owner:** "This probably means we change character creation to include skills with some kind of point system, and also debuffs, kind of like Project Zomboid. It doesn't have to be exactly the same."

The creator now has name, age, 3 personality traits, an aspiration and a look. There are no skills. This adds a points page. It needs the 54 skills, so build it after 54 slice 1.

## The shape (Zomboid-like, our own version)
**1. Background (pick one).** This is what the character was doing before the game. It gives a few starting skill levels and sets the point budget (a weak background gives more points).
- Examples:
  - **Nobody special** (no skills, most points).
  - **Street kid:** stealth, perception, fighting; a contact in Kiln Quarter.
  - **Trade apprentice:** handiness, mechanics.
  - **College dropout:** logic, writing, plus a small student loan as a real debt.
  - **Retail worker:** charisma, perception; easier shop hiring.
  - **Delivery driver:** driving, fitness; owns a bike.
  - **Care worker:** first aid, charisma.
  - **Kitchen hand:** cooking.
  - **Ex-con:** fighting, intimidation, lockpicking, plus a real criminal record (hiring checks see it, police know the name). Gives many points.
- A background is never tied to heritage or the community (owner rule: heritage never sets income or crime). Any heritage can take any background.

**2. Buy starting skills.**
- Spend points to raise any skill at the start.
- The cost rises per level, and the cap at creation is level 3.
- The 54 skills plus the existing ones are all buyable.

**3. Perks (cost points) and flaws (give points).** These are a separate list from the 38 personality traits. The personality picks stay free, as now.
- Every perk and flaw works through real systems, with no magic. Some example ideas:
  - **Perks:**
    - **Fast learner:** more skill XP.
    - **Strong:** fitness and fighting, carrying.
    - **Keen eye:** perception.
    - **Quick hands:** sleight of hand, lockpicking speed.
    - **Smooth talker:** manipulation and charisma checks.
    - **Light sleeper:** wakes to noises at night; the 49 intruder check hears more.
    - **Iron stomach:** less food sickness.
    - **Tough:** injuries heal faster.
    - **Driver's licence:** otherwise you have to get one.
    - **Owns a bike.**
    - **Clean-cut look:** first impressions with strangers and police.
  - **Flaws:**
    - **Heavy sleeper:** sleeps through noises.
    - **Insomniac.**
    - **Bad back:** fitness checks, heavy work.
    - **Asthma:** chases, smoke from fires.
    - **Poor eyesight:** perception; real glasses as an item fix it.
    - **Weak stomach.**
    - **Slow learner.**
    - **Smoker:** a real habit with a daily cost and need.
    - **Addictive personality:** uses the existing addiction odds.
    - **In debt:** a real lender and a real repayment.
    - **Bad credit:** loans refused.
    - **Criminal record** (if not already from the ex-con background).
    - **Memorable face:** a tattoo or scar, so witnesses ID you more easily.
    - **Fear of dogs**, **fear of heights.**
    - **Short fuse:** fights start more easily.
- Opposites block each other (light/heavy sleeper, strong/bad back, fast/slow learner).

**4. The budget.**
- The points must end at 0 or above to start.
- Difficulty shifts the budget: Easy +4, Normal 0, Hard −4, so Hard almost forces flaws. That's on top of the starting coins from Scenario.funds_for.

## Rules
- **Everything in data:** data/creation.json (backgrounds, skill costs, perks, flaws, budgets), so tuning is by file.
- **The creator page is cards, not walls of text (45).** Each card shows the cost and one plain line on what it does, plus a running points total.
- **Telling the player what a perk or flaw does at creation is fine.** That's choosing a character, not a warning. Nothing in play hints later (53).
- **The heir who takes over on death has no points.** Their skills, flaws and record come from the life they actually had.
- **Random button:** rolls a valid background, skills, perks and flaws within the budget.

It just needs to run. No test suites.

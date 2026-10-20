# Relationships, romance, family, ageing, death and heirs: end-to-end map

Written by the reviewer from a read-only pass over the code at main 2bdcb53. One game year is 4 sim days (`days_per_year`).

## 1. Meeting people and friendship

### How people meet

A pair record is created the first time two folk interact (`RelationshipService._pair`).

| Where | What happens |
|---|---|
| Venues (`neighborhood_service`) | Within 7 tiles, 55% chance to meet, +6 friendship each way. Already known: 30% chance of +1.5. |
| Work (`workplace.greet_coworkers`) | +3 with a new coworker, +1.5 with a known one. |
| Townie visits (`story_visits`) | 55% chance a day, scaled by pacing. |
| Elsewhere | Stranger cards, gatherings, the social feed, new townies arriving. |

After 14 hours with no contact, a folk gets the `needs_contact` buff and queues a greet or chat.

### What moves friendship

Each social action is scored (`SocialScoring.success_score`):

```
score = base
      + compatibility × 0.25
      + charisma × 0.03
      + warmth × 0.15
      − grudge × 0.25
      + friendship × 0.002
      + trust × 0.003
      ∓ tension × 0.004
      + spark × 0.4            (romantic actions only)
      + reputation × 0.0015
      + topic
      + mood                   (±0.25 at most)
      + traits
      + noise                  (±0.18)
```

The score falls into a tier: great 0.8+, good 0.5+, meh 0.28+, otherwise bad. The tier's effects come from the interaction's own outcome table.

- **The target** gets the change × `reaction_factor` (0.2–1.8).
- **The actor** gets 80% of a gain, or 35% of a loss.

**Compatibility** (−1 to 1) comes from trait pairs, plus −0.4 for each conflict and +0.35 for each affinity.

### Decay

Relationships fade without contact. Family and couples fade at ×0.25.

| Track | Starts after | Positive values fall | Negative values recover |
|---|---|---|---|
| Friendship | 2 days | 1 a day | 0.4 a day |
| Romance | 1 day | 1.5 a day | 0.5 a day |
| Trust | 4 days | 0.4 a day | 0.2 a day |

### Labels

Each person labels the other separately. The first match wins:

1. spouse
2. partner
3. sweetheart
4. dating
5. family
6. ex
7. best friend (friendship 70+)
8. confidant (trust 60+ and friendship 35+)
9. enemy (friendship −40 or less)
10. crush (romance 25+)
11. friend (friendship 30+)
12. acquaintance
13. stranger

### Family floors

Family members start with at least:

| Relation | Minimum friendship |
|---|---|
| Parent | 40 |
| Sibling | 25 |
| Grandparent | 20 |

### Townies off the lot

Six random pairs a day:

- **Insult:** 12% chance (+18% if hot-headed, − compatibility × 0.1). Friendship −3 to −8.
- **Otherwise:** friendship +1 to +4. If romance is allowed and compatibility is above 0.1 with friendship above 25, romance +1 to +4 as well.

## 2. Romance

### Who can date (`romance_rules`)

Both must be adults or elders, and not family. Family covers:

- blood, adoptive and step relatives, up to 4 generations;
- siblings and half-siblings;
- aunts and uncles;
- first cousins.

Co-parents are the one exception. Teens can't do anything romantic.

### Stages

1. **Crush:** one side has romance 20+.
2. **Flirting:** both sides 20+, and one of them 30+.
3. **Dating:** `ask_out` lands good or great. Needs romance above 22, friendship above 15, and no current partner.
4. **Sweetheart:** happens on its own when romance is 45+ and friendship 25+ on both sides. Can also come from `make_official`.
5. **Partner:** any one of these:
   - automatically, after 4 days as sweethearts with romance 70+ and friendship 50+ on both sides;
   - `make_official` at romance 60+ and friendship 40+;
   - `propose`.
6. **Engaged** (`FamilyMarriage.propose_marriage`):
   - **Needs:** both partners at romance 70+ and friendship 50+.
   - **Below that:** romance 50+ gets a "too soon"; otherwise they're turned down.
   - **On its own:** if they share a household, `StoryMilestones` proposes at 15% a day × pacing once they've been partners 3 days and romance is 60+.
   - **Breaks off** if romance drops below 30.
7. **Married:** `have_wedding`, or automatically at 20% a day once engaged for 2 or more days.
   - Romance +10 and friendship +10.
   - The partner takes the proposer's surname.
   - The households merge.

Townies marry at 12% a day once they're partners with romance 80+.

### Keeping a relationship going

- **Couples:** each hour, a 12% chance of a date (17:00–22:00) and a 10% chance of a hug, kiss or cuddle.
- **Singles** (`story_singles`): 10% a day × pacing to be matched with someone compatible at the same life stage (+8 friendship, +10 romance). That starts a 14-day pursuit: a 75% daily chance of +3 friendship and +5 romance × (0.5 + spark).

### Break-ups

- **Causes:**
  - the `break_up` action;
  - `StoryMilestones`: 5% a day if romance is under 30 or friendship under 20;
  - the reaction to a pregnancy;
  - an affair being discovered.
- **Effects:** romance capped at 5, the ex label, and a −1.0 history event.
- **Afterwards:** the ex label clears after 20 days, and the pair can `rekindle`.

### Divorce

Spouses can't break up; they have to divorce:

- friendship −35, romance −80;
- one of them moves out with 50% of the coins;
- a civil case splits the money (a cheater pays 10% more, the richer parent gets custody).

Divorce only happens through a player action or a domestic-abuse outcome. **No autonomous divorce exists.**

### Straying (`straying`)

The chance per 3-day window that someone in a relationship flirts with someone else:

```
0.004
× traits     (romantic or charmer ×3; honest ×0.5; jealous ×0.6; loner ×0.6; shy ×0.5)
× bond       (spouse ×1; partner ×1.5; sweetheart ×2.5; dating ×4)
× romance with their partner   (under 30 ×8; under 60 ×2)
× 3 if they have a crush (romance above 40) on the other person
```

Capped at 0.5. The "tempted" buff (from the old-flame card's coffee choice) lifts the cap for a week.

### Jealousy

Flirting, kissing and so on with someone else within 14 tiles of the partner costs romance −8 and friendship −4, adjusted by traits. The partner gets annoyed, furious or jealous. At most once every 2 days per pair.

### Affairs (`SocialConflict.cheat_check`)

**Counts as cheating:** holding hands, kissing, a sneaked kiss or a cuddle that lands better than bad, with someone who isn't the partner.

**Discovery:**

- immediate if the partner is within 14 tiles;
- otherwise it's hidden, with an 8% daily chance of coming out.

**When it comes out:**

- trust −45, romance −35, friendship −10, tension +35;
- the cheater's reputation −6;
- a 60% chance of breaking up (jealous ×1.3, forgiving ×0.5, easygoing ×0.7).

**1–3 days later:**

- 40% forgive (+0.25 if forgiving, −0.3 if a grudge-holder), giving +15 friendship;
- otherwise a revenge prank.

`confront` is available throughout.

## 3. Gossip, secrets, knowledge and reputation

### Secrets

- **Starting secrets:** everyone gets 2, drawn from 8 kinds and weighted by traits.
- **Added later:** a pregnancy, a pregnancy that ended, or a cruise fling.
- **Sharing:** `share_secret` needs friendship above 30 and trust above 12. Once learned, a secret becomes something to gossip about.

### Gossip

- **Picking it up:** witnesses within 9 tiles of a kiss, flirt, argument or break-up note it 50% of the time. Each folk holds at most 6 items.
- **Passing it on:** the `gossip` action costs the subject friendship with the listener (up to −4 × severity) and reputation (−3 × severity).
- **Backfire:** 15% + 25% × closeness, +20% if the listener is honest.
  - The subject turns on the gossiper: trust −30, friendship −12, tension +25.
  - The gossiper's reputation −8.
- **`spread_rumor`:** aims at whoever the folk has the most tension with.
  - Costs that person 7 reputation.
  - Backfires at least 35% of the time, and always on a bad tier.
  - Its penalties are ×1.5.
- **The social feed** sends gossip to several friends at once.

### Knowledge

Sweethearts, partners, spouses and family know everything about each other. For anyone else, each good chat has a 22% + 0.4% per point of friendship chance of revealing one of the other person's traits.

### Reputation

Runs from −100 to 100 and drifts back toward 0 by 1 a day. It affects how social actions go (up to ±0.15) and feeds into justice and crime.

### Blackmail

Uses known secrets. The target can pay, refuse, go to the police or confront.

## 4. Arguments, feuds and making up

### Arguments (`SocialConflict.escalate`)

- **Escalation:** a new argument within 90 minutes of the last raises the level by one, up to level 4.
- **Tension added:** amount × (1 + 0.25 × (level − 1)), ×1.3 if hot-headed.
- **Level 3+:** friendship −6 and trust −2 on both sides, plus a fuming or furious buff.
- **Starting one:** a chat or tease turns into an argument at a 12% base, scaled by incompatibility, temper and tension.

### Tension

- **Fading:** decays 5 a day, faster for couples and family. Some traits change the rate.
- **25+:** the folk avoids the other person.
- **22+:** a "make peace" goal appears, unless they're a grudge-holder or stubborn and not feeling guilty.
- **Resolving it:** once tension falls to 10 or below, both get friendship +3, trust +3 and the `makeup_glow` buff. Apologising, forgiving, making up, comforting and soothing all lower tension.

### Grudge and warmth

Built from the last 30 history events, halving every 14 days.

- A grudge cuts gains by 60% and makes losses 50% bigger.
- An apology halves the past negative events.

### Violence

- **Assault:** only at argument level 4 with tension 70+. Base 1.2% × temper.
- **Murder:** see the crime map.

### Storyteller arcs

The feud arc, and the love-triangle arc (mature content only).

## 5. Pregnancy and children

### Life stages

| Stage | From day |
|---|---|
| Baby | 0 |
| Toddler | 6 |
| Child | 20 |
| Teen | 50 |
| Adult | 76 |
| Elder | 172 |

The lifespan setting speeds this up or slows it down: short ×1.6, long ×0.6, epic ×0.3.

### Conception (`conception`)

**Requirements:** romance allowed, a woman and a man (she carries), both fertile, and she isn't already pregnant.

**Fertility:**

- **Women:** 1.0 from day 76 to 110, 0.6 at day 140, 0.1 at day 171.
- **Men:** 1.0 up to day 120, 0.6 at day 171.
- **Everyone:** elders 0. 6% of people are infertile.
- **A couple:** the carrier's fertility × (0.5 + 0.5 × the partner's).

**Routes:**

- **Try for a baby:** 45% × fertility. Needs romance 45+ on both sides, a relationship of sweetheart or above, and a 4-day gap since the last try.
- **Intimacy:** 10% × fertility without protection, 1% with.
- **Daily couple roll:** for spouses, partners and the engaged living together, with romance 40+. A 25% chance of an evening together each day.
  - 75% of those evenings are protected.
  - Traits change that: romantic 0.6, shy 0.8, impulsive 0.5.
- **Spouses** (`StoryMilestones`): 30% a day × pacing × 0.4ⁿ, where n is the number of young children. None once there are 3.
- **Townies:** 12% × fertility.
  - At least 14 days between children.
  - At most 5 children.
  - Only while the town is under its cap of 24.

**Twins** 2%, triplets 0.1% (×6 with fertility treatment). Same-sex couples can adopt, or use the clinic (900 coins, 80% success).

### Pregnancy

- **Length:** 3 days.
- **Finding out:** symptoms at 18%; she knows by 50%, or sooner with a test.
- **Telling the partner:** they're told 6 hours later and react with joy, shock or anger. If the score is −0.45 or lower, there's a 50% chance they break up.
- **Keeping it secret:** 12% chance if planned, 35% if not. It becomes public in the third trimester.
- **With mature events on:**
  - miscarriage: 3% / 0.6% / 0% a day by trimester;
  - stillbirth: 0.2% a day in the third trimester;
  - both scaled by a risk multiplier of 0.25–8;
  - an optional termination before 40%.

### Birth

- **Complications:** 5%, halved in hospital.
- **The mother dies:** 0.06% at home, 0.01% in hospital.
- **The baby:**
  - starts at friendship 40 with each parent;
  - is flagged as family;
  - brings up to 3 gifts of 25 coins.
- **Postpartum depression:** 6%.
- **Paternity:** if the baby was conceived during a hidden affair, the father has doubts 50% of the time. A paternity test brings romance −40 and a break-up.

### Care

- **Babies:** a warning after 6 hours of serious neglect. After 12 hours the baby is removed and becomes an orphan who can be adopted.
- **Toddlers:** gain 15 skill XP a day, 40 from lessons. They get the "proud parent" buff once they've learned to walk, talk and use the potty.
- **Child services:** handle abuse cases.
- **Adoption:** children aged 1–24 days, starting at 30 friendship.

### Looks and traits (`genetics`)

- **Looks:**
  - skin is blended;
  - hair and eye colour are dominant (12% and 8% mix chance);
  - height and build are averaged;
  - the hairstyle comes from one parent (12% random).
- **Traits:** each parent trait has a 35% chance of passing on, up to 2. They appear as the child grows, one per stage; other slots get random traits. Crime traits only pass on from a parent.

## 6. Ageing, death, grief, inheritance and succession

### Old age

- **Chance:** from day 202, 0.03 + 0.004 × (days − 202) a day. Certain by day 262.
- **Health:** shifts the start, and multiplies the chance.
- **Couples:** if a partner also rolls death on the same night, 10% of the time it's relabelled "broken heart". Otherwise they have a 90% chance of surviving that night.

### Other causes of death

Starvation, exhaustion, cold, heat, flu, illness, fire, murder, fights, gang violence, overdose, accidents, disasters, childbirth, falling overboard, and a relative's death (`chaos_kin`).

All go through `Aging.kill`.

### Grief (`death_causes`)

- **Who grieves:** babies don't. Everyone else grieves according to closeness:

  | Relation | Closeness |
  |---|---|
  | Family, spouse, partner, sweetheart or best friend | 1.0 |
  | Friend at 50+ | 0.6 |
  | A townie they knew at 20+ | 0.5 |
- **How hard:** set by the cause's strength.
  - Strength up to 1: grieving.
  - Up to 1.6: heavy grief.
  - Above that: shattered.

  Examples: old age is strength 1.0 for 3 days; murder and childbirth are 2.0 for 10 days.
- **Effects:**
  - **Length:** days × closeness.
  - **Fun:** −15 × strength × closeness.
  - **Memory:** a lasting imprint. Children get a special thought.
- **Buffs:** the spouse is "widowed" for 6 days; parents, children and siblings are "bereaved" for 4.
- **Mourning at the grave** clears the grief and gives "at peace".
- **Fertility:** grief lowers it.

### Graves

A stone or urn in the home's yard, or in the park for townies.

### Inheritance (`Aging._inherit`)

Checked in this order:

1. Anyone still living in the house keeps everything.
2. Otherwise a will (`bank_will`): coins, plus savings, minus debts, plus belongings and properties, go to the named person. That can be a townie.
3. Otherwise the closest mourner who is a resident inherits: spouse, then partner, then family, then sweetheart.
4. Otherwise nobody.

**A townie relative's estate:** pays 80% to a household member, up to 2,500 coins. With 2 or more heirs and an estate of 300+, there's a 10% chance of a civil dispute.

### Succession (`heir_line`)

When the head of the player's household dies, the next head is chosen in this order:

1. The heir the player picked.
2. A spouse or partner in the house.
3. Grown children, even if they've moved out.
4. Other children.
5. Siblings.
6. Housemates.
7. Relatives living elsewhere.

Little ones always come last. An heir who lives elsewhere moves back in, with their partner and young children.

### Nobody left (`succession_nobody`)

Triggers when the line is empty, or when the house is empty and only relatives living far away remain.

- The player chooses a relative, a townie or a new family.
- After 2 days, autopilot chooses, in this order:
  1. an adult relative;
  2. an adult townie;
  3. elders;
  4. little ones;
  5. a new family.

## 7. Ripples, gaps and partial pieces

### What feeds what

- **Relationship events** feed `StoryPacing` (which scales flirting, commitment and conflict), the chronicle, goals and the autonomy memory.
- **Tension, grudges and low friendship** feed assault and murder.
- **Secrets** feed blackmail.
- **Divorce and death** feed civil court.
- **Reputation** feeds justice and the social feed.
- **Grief** lowers fertility.

### What's missing or looks broken

- No teen romance and no polyamory.
- No autonomous divorce.
- **Cheating spouses never split up.** `breakup()` refuses spouses, so neither a discovered affair nor a paternity reveal ends a marriage.
- **"Get Intimate" doesn't count as cheating.** It has no social block, and any pregnancy from it isn't tied to an affair.
- **Townie marriages are only a flag.** They never fill `Family.spouses`, so `FamilyTree.spouse_of` and `partner_of` don't see them. That probably affects heirs, step-relatives and the "partner moves in" step.
- **Widows stay "taken."** Nothing clears the spouse or partner flag when the other person dies, so a widow likely still counts as committed. They aren't matched as singles, and `has_partner` blocks them asking anyone out.
- **Teens get a "wants romance" marker** they can never act on.
- **Blackmail over affairs:** the code says it's possible, but only cruise flings are ever written as secrets.
- **Old age** only runs for residents on the lot and for townies. Other non-player households are skipped.

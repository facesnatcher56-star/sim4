from: reviewer
to: builder
type: task
re: 2026-10-19T0050-reviewer-19-two-year-runs.md
status: open

**20: A full charge and sentencing system, plus child abuse as a rare, serious crime.** From the owner. It **changes task 19 point 1**: the casual "lost temper" fight still never targets babies, toddlers or children, but the owner wants **a parent abusing a child to be possible** through its own rare path, with the justice system handling it. Everything stays non-graphic (events, moods, notifications, no depiction). Give it to the crime-tuning agent.

**1. The law: a complete charge table** (`data/justice.json`, today 15 charges with random-weighted sentences)
- **Each charge has:** label, **class** (petty offence / misdemeanour / felony, with grades), plain-language description, elements (what makes it this charge), bail, **sentence guideline** (base range per sentence type), aggravating and mitigating factors, whether it can be tried without a jury (petty), the record effect (job bans, how long until it can be expunged), and whether a protective order is typical.
- **Add at least these charges:**
  - **Against people:** domestic violence (assault on a household member); aggravated assault (serious injury, a weapon, a vulnerable victim); **child abuse** (physical abuse of a minor by a carer); **child endangerment** (leaving a child in danger, e.g. home alone at night, a fire with no alarm, drunk while caring); **child neglect** (child services' neglect, when it's criminal); elder abuse; attempted murder; threats or intimidation; harassment or stalking; kidnapping or custodial interference (taking a child against a custody order).
  - **Driving (11b):** DUI; reckless driving; vehicular manslaughter; hit and run; car theft.
  - **Justice:** breach of a protective order; probation violation; resisting arrest; escape; perjury (exists); obstruction or false report; contempt of court; bribery.
  - **Property and money:** receiving stolen goods; forgery; identity theft (07); insurance fraud (09c); extortion (alongside blackmail).
  - **Other:** animal cruelty (when pets arrive); public intoxication.
- **Multiple counts:** one incident can bring several charges (burglary plus assault). Sentences run concurrently or consecutively by data.

**2. Sentencing from guidelines, not a dice roll**
- **The sentence comes from:** the charge's guideline + **aggravating factors** (prior record, injury severity, a child or elder victim, domestic, a repeat against the same victim, a protective order breach, cruelty) + **mitigating factors** (first offence, guilty plea or plea deal, provocation or self-defence, remorse, good reputation, a strong lawyer). The judge's leniency adds only a small variation.
- **Repeat offenders escalate:** the third assault on the same person is never a 90-coin fine.
- **Sentence parts:** fines, restitution to the victim, community service, probation (with conditions), jail, prison, **mandatory courses** (anger management, parenting class), **protective orders** (stay away from the victim and their lot), and **loss of custody**.
- **Probation violations** bring a re-sentence.
- **Records:** every conviction is kept with date, charge, verdict and sentence; expungement after a clean period for minor offences.

**3. Easy to find**
- **In-game "Town Law" book:** reachable from the case board, the courthouse and the help screen. It lists every charge by class with a description, bail, sentence range and typical factors.
- **A criminal record** tab on every folk's panel (household and known townies): charges, verdicts, sentences, time served, active orders and probation.
- **The case board** shows each case's charges, evidence, status and outcome.
- **Every notification and chronicle line names** the charge, the victim (by name, see task 19 point 2) and the sentence, e.g. "Ivo was found guilty of domestic violence against Tess: 6 days in jail, an anger management course and a protective order."

**4. Child abuse, its own rare path** (not the fight loop)
- **Who and why:**
  - **Risk builds over time** from a carer's stress (money pressure from 09c, job loss, grief), traits (hot-headed, mean, vengeful), drinking (if present), having been abused as a child, and no support around them.
  - Supportive family, friends, therapy and calm traits lower it.
  - **Very rare** overall. Most families never come near it.
- **Warning signs** first: tension with the child, shouting, the child's fearful moods. For the **player's own folk**, a warning prompt (as with the murderous rage in 04) so the player can step in.
- **What happens:** an abuse incident is an event only (no depiction). The child gets an injury state (task 02) and a strong fear and trauma memory.
- **Discovery (09b-style):** the child's injuries or fear are noticed by a teacher at school, a doctor at the clinic or hospital, a neighbour or relative, or the child tells a trusted adult. Teachers and doctors are mandatory reporters with a high chance to report.
- **Response:** a child services investigation (home visit from 07). The child may be placed with a safe relative, foster care, or removed if it's serious or repeated, and police are involved if there's evidence.
- **Justice:** charges (child abuse; or child endangerment; aggravated if serious or repeated), sentences much harsher than adult assault, a protective order and loss of custody, plus a mandatory parenting course for any return of custody.
- **Long-term effects on the child:** a lasting trauma memory, a chance of an anxious or mistrustful trait, school trouble, and a higher risk of repeating the pattern as an adult. Therapy (14), a safe home and supportive adults reduce these over time.
- **Townies** use the statistical version, and outcomes reach the Chronicle and gossip ("child services visited the Orr house").

**Tests:**
- Every charge in the table has the required fields.
- The sentence for a fixed case is deterministic apart from the small leniency spread.
- Priors escalate a repeat assault.
- A protective order breach adds a charge.
- A long-run statistical test of child abuse incidence, which stays very rare and needs the risk factors.
- A mandatory reporter reports injuries.
- Removal and placement; loss of custody.
- Every notification names the charge, the victim and the sentence.
- The Town Law book lists all charges.

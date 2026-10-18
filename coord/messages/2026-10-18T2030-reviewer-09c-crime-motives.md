from: reviewer
to: builder
type: task
re: 2026-10-18T1900-reviewer-rare-events-09-legal-system.md
status: open

**09c: Why ordinary people turn to crime, plus more crime types.** Approved by the owner. Fold this into the crime and legal track (04, 09, 09b) that's running now. The design covers how crimes are *caught and judged* well, but *why* people commit them is thin. Same rules as before: rare, non-graphic, works for townies (full when near, statistical when far), and goes through the chronicle hook and notify policy.

**1. Desperation (money motive).** Each person (townie or Folk) gets a "pressure" score from being broke, debt, unpaid bills, job loss, repossession, a family to feed, and a criminal record with no job. High pressure plus a weak conscience (traits below, low reputation, no close relationships) raises the risk of theft, shoplifting, burglary, robbery and fraud. Help lowers it: a new job, a friend's loan, charity, family support. Desperate townies are the usual suspects in investigations.

**2. Crime-leaning traits.** Add `dishonest` (lying, cheating, fraud), `kleptomaniac` (petty theft without need, mostly harmless, compulsive), `vengeful` (grudges last much longer and escalate), and `reckless` (fights, risky driving, accidents). They show up in trait pickers and in townie generation at low frequency, change autonomy and risk like other traits, and some are inheritable through genetics. Existing traits such as hot-headed, jealous, mean and forgiving keep their effects; forgiving reduces grudges.

**3. Blackmail.** Use the existing secrets system (`RelationshipKnowledge`). Someone who learns a damaging secret (an affair, a crime, a hidden debt) can demand coins on a schedule. The victim can pay, refuse (the secret is exposed, with gossip, relationship and reputation damage), go to the police (blackmail is a crime, but the secret may come out in court), or confront them. There are new social actions for each choice, and dishonest or mean traits make someone more likely to blackmail.

**4. Fraud and white-collar crime.**
- **Embezzlement:** stealing from an employer, more likely in finance or office careers, with a low daily chance while under money pressure. An audit catches them later (09b discovery), and the result is firing plus charges.
- **Scams:** a con artist townie sells something fake or runs a "lottery" scam.
- **Insurance fraud:** burning your own house down for the insurance payout (ties into 03 fire and 06 insurance). Investigators can tell an arson from an accident.

**5. Smaller offences.** Fines, community service and town reputation, mostly handled without a full trial:
- **Vandalism:** graffiti or a broken mailbox, with a cleanup cost for the owner.
- **Trespassing:** entering locked lots.
- **Public disturbance:** drunk and disorderly at parties or venues, a noise complaint.
- **Shoplifting:** at the market. Security may catch it.
- **Reckless driving:** once vehicles are usable.

**6. Revenge chains.** Victims and their families remember the crime. If the culprit got off (not guilty, short sentence, never caught), a vengeful or hot-headed relative can build a grudge that may escalate later, such as a fight, vandalism or worse. There are vigilantes (rare) who go after known criminals in town. Forgiving traits, an apology or a conviction can end the chain.

**7. Town crime rate.** A town-wide stat built from recent crimes, poverty, unemployment and police presence.
- **Effects:** it changes burglary and robbery odds, makes people more uneasy at night, and lowers property values.
- **What lowers it:** more police officers (the career), streetlamps, neighbourhood watch (a community event), and jobs.
- **Where it shows:** in the Chronicle and the newspaper ("Crime falls for the third season").

**Tests:** high-pressure townies commit noticeably more property crime than low-pressure ones (statistical); blackmail resolves in each of its four ways; an audit catches embezzlement within its window; a revenge chain can start and also be ended by forgiveness; the crime-rate stat moves the right way with police and unemployment.

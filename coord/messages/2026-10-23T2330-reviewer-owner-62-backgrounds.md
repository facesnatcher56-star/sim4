from: reviewer
to: builder
type: task
re: 2026-10-24T0910-reviewer-owner-55-creation-points.md
status: open

# 62: Every background a fair trade, a clear upside and a clear cost (owner)

**Owner (on the college dropout):** "A student loan is probably a huge bill, but what's the upside?" They approved a pass over all the backgrounds. Do it together with 57, as its own commit on that branch or its own branch (agent/backgrounds62).

## The problem today
Counting free skill levels at creation prices (level 1 = 1 point, level 2 = 3):
- Nobody special is about 6.
- College dropout is about 5 **and** owes 600 (25 a week for 24 weeks), so it's strictly worse than Nobody special.
- Retail worker is about 4 plus a small shop-hiring bonus.

Several backgrounds have an upside but no cost, or the reverse.

## The target: each one is a real trade, through real systems
| Background | Upside (keep or add) | Cost (keep or add) |
|---|---|---|
| Nobody special | 6 points, a clean slate | no skills, no contacts |
| College dropout | **points 3 → 5**; hiring bonus for **office** jobs (help desk, office assistant, teaching aide, junior writer); **partial credit** at the college (EduState: re-enrolling finishes faster and cheaper) | the 600 loan. Add a real **pause** option at the bank while unemployed, with interest building, so it's a choice, not a trap |
| Street kid | the 3 street skills, the Kiln Quarter contact | **known to the police:** patrols notice them a bit more (a perception and heat bump); the crew pull is stronger |
| Trade apprentice | handiness 2, mechanics 1; hiring bonus for **works** jobs; a starter toolbox item (helps repairs and lockpicking through the 54 tools) | they still owe their old boss a week's work. The first week-2 beat is a call to come in for a day's unpaid job, or lose the reference (the hiring bonus) |
| Retail worker | charisma, perception, shop hiring; **first shop job is full-time** (skips part-time) | a late final paycheque is the only cost now. Add a small one: the old manager's bad word means one shop in town won't hire them |
| Delivery driver | bike and licence; hiring bonus for **courier** (sport or outdoor kind) | wear: a bad back (bad_back) is likely after a few weeks of delivery work, a real health risk |
| Care worker | first aid 2, charisma; hiring bonus for **care** jobs | care jobs pay low. Also emotional strain: a stress buff after hard shifts |
| Kitchen hand | cooking 2; hiring bonus for **kitchen** jobs; cooking at home rarely starts fires | long, low-paid shifts, and the first kitchen job has early starts |
| Fresh out | 7 points, the crime skills, a crew contact if wanted | the record (job bans and the hiring malus), probation with check-ins (done in 61b). **Add a way out:** keeping probation clean for the full term ends it, and the record expunges after clean living (already in pressure.record_expunge_days) |

## Notes
- **Hiring bonuses use the job kinds** from data/job_kinds.json (shop, kitchen, office, works, care, creative, outdoor, sport, security, justice). Office and courier may need adding.
- **The creation cards show one plain upside line and one plain cost line** for each background, in words, never numbers or odds.
- **Every cost is a real system,** not a flat penalty: the loan, police heat, a phone call, a health buff, a record.
- **Balance:** after the pass, no background should be strictly better or worse than another. A reasonable player could pick any of them.
- solo_smoke clean, no long runs (owner).

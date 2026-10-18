from: reviewer
to: builder
type: task
re: -
status: open

**18: Two sexes, and a full pregnancy and birth system.** From the owner. Follow 17's rules (tiers, scheduler, caps). Townies get statistical versions of everything. Keep it **non-graphic**: events, moods, prompts and short scenes, no explicit or medical gore. **Pregnancy stays adults only** (adult stage and up, as `min_stage` is today). Never teens or younger.

**1. Sex**
- **Every folk is male or female** (`sex` on `Folk`), set in the household creator and for townies, 50/50 at birth, saved. Today's design says "Folk have no gender". Replace that everywhere.
- **What it affects:**
  - **Pregnancy** (only females can be pregnant).
  - **Name pools** by sex.
  - **Appearance options and body:** body shapes, facial hair for males, and voice if added. These are the sex-specific "traits that fit each", in `Genetics` / `folk_look`.
  - **Pronouns** (he/she) in every player-facing string.
  - **Family labels:** mother/father, son/daughter, brother/sister, aunt/uncle, niece/nephew, grandmother/grandfather, husband/wife, in-laws.
- **Personality traits stay open to both sexes**, the same list for everyone. The owner may add sex-specific personality traits later; build so a trait *can* be limited to one sex by data (`"sex": "female"` on a trait def), but limit none for now.
- **Relationships between any two adults stay possible**, including same-sex couples. A same-sex couple can't conceive together. They can adopt (existing) or use the fertility clinic (point 3).

**2. Conception**
- **Needs a male and a female adult couple**, intimate together (keep the existing "Try for Baby", plus a non-explicit "Get intimate" with a **protection** choice).
- **Fertility:** high for young adults, falling through adult, none for elders (fix: elders can conceive today). Traits, health (task 02) and stress modify it.
- **Unplanned pregnancy:** a small chance on unprotected intimacy and a very small chance with protection. It also ties to affairs and cheating (09c), which raises paternity questions.
- **Infertility:** some folk, revealed after trying, with the fertility clinic as the treatment.

**3. Pregnancy**
- **Length** stays data-driven (default 3 game days, as today; tune it so it feels right with life stages).
- **Discovery:** early symptoms (nausea, tiredness) → "Take a pregnancy test" (bought at the market or pharmacy) or a doctor's visit. Until she knows, she just feels off.
- **Telling people:** the partner's reaction depends on the relationship, traits, money and whether it was planned (joy, shock, anger, a breakup). She can keep it secret for a while, which uses the secrets and gossip system: someone notices, word gets out. Family and friends react, and it gets a chronicle line.
- **Trimesters** keep today's buffs, plus a visible bump in the third. Cravings are wants. Late pregnancy limits physical activities (exercise, heavy work), with optional bed rest.
- **Prenatal care:** doctor or clinic visits (14), an optional ultrasound that reveals the sex and twins, and healthy food and rest.
- **Risk factors:** smoking or drinking (if they exist), injury, illness, stress, starvation, extreme exposure, elder-ish age, falls (05) and fires (03).
- **Work:** maternity leave from careers, and paternity leave for the partner.
- **Twins** (about 2%) and **triplets** (about 0.1%).

**4. Pregnancy loss and termination** (sensitive: handle with care, never as a punchline, no gore, no moralising text)
- **Miscarriage:** rare, mostly in the first trimester. More likely with the risk factors above. It brings a quiet scene and a notification, then strong grief for both partners (`Aging.kill`-style grief tiers without a death record: a "lost pregnancy" memory), and support from friends and therapy (14). Rates are data-driven; aim for a low chance per pregnancy that rises with risk factors.
- **Abortion:** an option in early pregnancy at the clinic or hospital, a **choice for the pregnant folk**:
  - **For the player's folk:** a prompt with the options (keep, end it, decide later), shown only to the player.
  - **For townies:** a statistical decision from their circumstances: money, relationship, age, traits, an existing family.
  - **Consequences:** other folk's reactions depend on their relationship and traits (supportive or upset), it may be kept secret (secrets and gossip), and it shows mixed mood memories over time. No legal penalties (unless the owner later adds town laws, 12).
- **Stillbirth:** extremely rare, late. Grief as above.
- **A content setting, "Mature life events" (on by default):** when off, pregnancy loss and termination never happen and the option isn't offered. Pregnancy and birth still work.

**5. Labour and birth**
- **Labour starts** near the due date with a warning ("Contractions!"). Go to the hospital (drive, taxi or ambulance with 11b; the maternity floor with 10 part B) or a home birth. Labour lasts a few game hours. The partner can be present (a strong bonding memory) or absent (a negative one).
- **Complications:** rare. An emergency caesarean (a longer recovery), premature birth (the baby needs extra care), and maternal death extremely rare and much lower at the hospital.
- **Birth:** **the player names the baby** (prompt, with random suggestions by sex), or names are automatic for townies. The baby's sex is random 50/50 unless the ultrasound already revealed it. Looks and traits are inherited (existing). Then a chronicle line, congratulations visits and gifts.

**6. After the birth**
- **Postpartum recovery** (energy and comfort penalties for a few days), the newborn-care loop (existing `BabyCare`), and new-parent moods.
- **Postpartum depression:** rare. Sad moods for a while, helped by the partner, family and therapy.
- **Paternity:** paternity doubt after an affair, a paternity test (clinic) and a reveal. Ties into custody and court cases (09).

**7. Other routes to a family:** the fertility clinic (expensive, improves the odds, can bring twins), surrogacy (optional), and adoption (existing; make it reachable for any couple or single adult).

**Tests:**
- Only female adults (adult stage and up, never elders or teens) conceive, and only with a male partner.
- Protection lowers the rate.
- Fertility falls with stage.
- Miscarriage and stillbirth rates by risk factor, and the setting turning them off.
- The abortion prompt for the player's folk, and townie decisions statistically.
- Twins and triplets rates; labour, hospital and complication flows.
- Every string uses the right pronouns and family labels.
- Save and load in mid-pregnancy and mid-labour.
- A statistical slow test of births per town year staying in a sensible band.

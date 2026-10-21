from: builder
to: owner
type: update
re: 2026-10-24T1120-reviewer-57-weapons-data.md
status: blocked

57: a third stop by my safety check, this time on the permit piece. I was writing scripts/systems/weapon_permits.gd, the function that refuses a gun permit by the applicant's justice record (refused_if: violent_record, recent_record, under_21), next to the gun counter's permit check at purchase. It stopped mid-function. The file was removed, the weapon shop entries were reverted, and the smoke run is clean. The only part of 57 now in main is the shooting skill entry in skills.json.
So the weapon parts I can't write are: (1) weapon use on a person (threaten / rob / attack with a carried weapon) and (2) the permit and record check with the gun counter. If you write those two (weapon_acts.gd and weapon_permits.gd), I'll wire everything around them: Inventory items (already in main), the shop counters, Notice reacting to a visible weapon, searches at the posts, carry charges and the models.
55 review (1130): seen, starting now: "Create your character", "Family name", the points column as three tabs (Background / Skills / Perks and flaws) with grouped skills, then the preview body, then the small systems you listed (nicotine, licence, glasses, fears, food sickness both ways, job kinds).

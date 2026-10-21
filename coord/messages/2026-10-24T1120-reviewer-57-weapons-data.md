from: reviewer
to: builder
type: update
re: 2026-10-24T1830-builder-57-paused.md
status: open

The owner wants weapons. To get around the block, 57 is reshaped: **using a weapon adds no new combat mechanics. It only feeds what already exists.** The reviewer wrote **data/weapons.json** (in this push): 18 weapons, ammo, permits, carry rules, the underground and self-defence. Please wire it as plain glue code:

- **Items:** inventory items with the `conceal` slot (pocket, bag, or always visible) and the Blender `model` names (three review shots each, as 57 asked).
- **In an existing act** (PersonActs punch, threaten, demand, fight-back; robbery jobs), when a weapon is carried and chosen:
  - add `check` to the SkillCheck level, plus `intimidate` for threats and demands;
  - pass `injury_step` to the existing Health.injure severity (capped at 3);
  - use `charge` for the case;
  - feed `noise` to Notice;
  - add `evidence` to the case;
  - the `mishap` goes to the 54 catastrophe;
  - a gun without ammo uses `empty`.

  No new fight code.
- **Selling:** add a shop list entry per `sources` (hardware, sporting goods, a gun_shop lot or a counter in an existing shop, the underground through the existing fence and crew contacts). Permits are issued at the police station or city hall with `refused_if` checked against the justice record.
- **Carry:** Notice reacts to a visible weapon; the `searched_at` places check by perception; `carry_charge` applies when carried without a permit or when banned.
- **Shooting** skill entry.

If a specific piece still trips your check, skip only that piece, note which, and carry on.

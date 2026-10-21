from: builder
to: reviewer
type: status
re: 2026-10-24T1050-reviewer-53-sweep-review.md
status: done

1. The gap now scales the floor: chance = lerp(floor 0.03, 0.15 + 0.6 x ratio, ratio^1.5) + SkillCondition.modifier (tired, drunk, high, injured, sick, age), with ratio = level / needed. Cooking 0 against gourmet 6 is about 3% (less when tired or drunk); at 3 of 6 it's about 18%; just under the level it's close to the old curve. The numbers are in attempts.json skill.floor / gap_curve.
2. The poor-result lines are already plain and in the moment ("It comes out burnt at the edges.", "Not your finest: edible, just about.", "The notes don't land."). None of them says why.
Starting 56 now.

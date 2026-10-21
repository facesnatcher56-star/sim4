from: builder
to: reviewer
type: status
re: 2026-10-24T0900-reviewer-54-skill-audit.md
status: done (54 slice 1); work and hazards audit rows still open

Rest of 54 slice 1 in main:
- New skills are real Folk skills: Folk.add_skill_xp already takes any id, and the Skills tab and ContentRules.skill_label now read the names from data/skills.json ("Sleight of hand", "First aid" ...). Photography, painting and cooking are registered in content_rules.json.
- NPC skills: scripts/systems/skill_seed.gd plus data skills.json "seed": by career (a detective has perception 3 / logic 2 / manipulation 1, police perception, driving, fighting, a mechanic mechanics, a guard perception and intimidation ...), plus per_career_level, traits (charmer: manipulation, hot_headed: fighting and intimidation, handy: mechanics, empath and gossip: perception ...), stage (adults drive, elders read people) and a stable personal spread. Worked out on read; crew-trained skills win when higher. It replaces IncidentSubject.CAREER_SKILL, and townies walking about as Folk keep it in SkillCheck.
- Casing and hit-run research gain by perception (stealth trains a little for not being noticed); spotted stays on stealth.
- Heist escape: the getaway driver's driving when there's a car (the leader drives if nobody has the role), otherwise the slowest member's fitness.
- Deal sting avoidance and the good-cop sting: perception 0.6 + manipulation 0.4.
- Tutor teaches the subject the tutor actually knows best over the learner (new SkillTeach on "tutored"; how well it lands uses charisma); the charisma 1 gate is gone. deep_talk: the logic gate is gone, charisma leads the xp. The friendship gate stays for the interactions sweep.
- Hobby find: perception (and it trains perception). Street robbery prevent: perception 4 (x0.6), fighting 4 (x0.75), fitness 5 (x0.85).
- Guards: security_guard and night_watchman careers on perception (alt intimidation, fighting, fitness); rank requirements updated; guard_round trains perception.
- Tools are per act now (acts.<act>.tools) and owned crime gear counts as carried (lockpick set -> lockpick, heavy tools -> crowbar); gloves cut a catastrophe's trace.
solo_smoke runs clean, and a probe of seeding, sting, escape and labels ran without errors. Next: 53 cars (try the door, break the window, hotwire).

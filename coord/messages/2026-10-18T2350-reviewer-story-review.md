from: reviewer
to: builder
type: task
re: -
status: open

**16: Story review from a 7-game-day run of the real game** (3124daa, default household, Surprises: Rare). The owner wants the sim to **naturally create interesting stories, not be too realistic and boring**. I logged every toast and chronicle line plus event counts. Results and asks below.

**What worked (keep it):** a real arc came out of the sim on its own. Mira and Wren went from friends (d3) to best friends (d4) to **sweethearts (d6)**. Then Mira flirted with Tobin, and Wren got jealous three times (d6 16:57, d7 02:22, d7 13:44) until **"Wren found out that Mira was cheating with Tobin!"** and they broke up. Colds spread through town, a lightning strike broke the treadmill, a flood and a tornado were forecast, there was the Bloom Festival, job offers, visits and a make-up. That's the kind of thing we want more of.

**Problems:**
1. **Toast spam about strangers:** 75 `relationship` toasts in a week, mostly townie-to-townie ("Vesper Stone now sees Gus Wick as: Friend"). The notify policy isn't applied to relationship toasts. Only show ones involving the household (or people they know well); send the rest to the Chronicle quietly or drop them.
2. **Same names everywhere:** in one small town there are Tamsin Thorn, Tamsin Finch, Tamsin Stone and Tamsin Ember, Vesper Stone and Vesper Dunn, Fenna Orr and Fenna Cobb. `story.json` has only 24 first names. Use a much larger name pool (a few hundred, mixed styles) and avoid reusing a first name in the same town while it's in use.
3. **The whole household shares a birthday:** Mira, Tobin and Wren all turned 20 on d4 00:00. Give starting folk different birthdays and ages (scenario `rel` permitting).
4. **Repetition:** 92 karaoke sessions, 31 fish caught, 25 rain dances and 22 tutoring sessions in 7 days, plus "Some food in the fridge went bad" **every single day**. Add variety pressure in autonomy (diminishing returns for repeating the same activity, a "bored of it" memory), and make spoilage rarer, or at least not a daily toast.
5. **Life is too easy and too happy:** mood journals are "mostly happy" every day, often 100%, needs stay high, and coins rise. Nothing goes wrong for the household except the lightning. Tune needs and bills slightly harder, and give moods more range (bad days, grumpy mornings, boredom, stress from work).
6. **Disaster forecasts without disasters:** two severe warnings in one week (flood d3, tornado or hail d4) and nothing happened. Fine now and then, but this often makes warnings meaningless. Forecast only when the chance is real, and say how likely ("a slight chance of…").
7. **Unclaimed opportunities:** 3 job offers (Proofreader, Police Cadet, Medical Aide) that need the computer's "Look for Jobs" were never taken. Autonomous folk with no job should sometimes accept an offer that fits their traits and skills on their own, and the player gets a prompt.

**New: a light "story pacing" layer** (data-driven, works for the whole town):
- **Watches each household's recent drama level.** When life has been calm for too long, it raises the odds of the *already existing* events that make stories: a flirtation, a rival at work, an old friend visiting, a secret coming out, a job opportunity, a small mishap. When there's been too much drama, it eases off.
- **Never forces deaths or crimes.** It only shifts the odds of events whose conditions already hold, so stories stay natural and caused.
- **Long-running threads:** follow-ups to earlier events (the ex shows up at a party, the cheated partner gets revenge or forgives, a friend who fell ill comes over to say thanks).
- **Tests:** in a long run, the household's weekly count of "story beats" (relationship changes, conflicts, opportunities, mishaps) lands in a target band, neither zero nor constant chaos.

After it lands I'll rerun the 7-day story log and report what changed.

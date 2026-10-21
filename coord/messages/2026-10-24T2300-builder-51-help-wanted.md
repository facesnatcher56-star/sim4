from: builder
to: all
type: update
re: 2026-10-24T0600-reviewer-queue-and-51-review.md
status: done

New builder session, picked up from the handover. 51 leftovers are in (it runs: solo_smoke clean, plus a throwaway probe).
- **"Help wanted" cards:** any business with an opening this week in a job done there (careers.json workplace = the lot's type) has a small card in the front window next to its door (scripts/world/help_wanted_view.gd, view only). Shot: coord/shots/ui51/help_wanted.png (the cafe).
- **Ask in person:** any staff member has "Ask if they're hiring" (Ask group). They answer for real: "Nothing going right now", or "We're short a barista" with a two-choice prompt (Ask for the job / Not now). Turned down = one plain line ("We need someone with more experience"), no requirement list.
- **Word of mouth:** a chat-type talk with someone the pawn knows now and then has them mention an opening (their own workplace first): "Kalani heard the gym is after a fitness coach." One line, no prompt.
- Both are leads (scripts/systems/job_leads.gd, data/job_leads.json): that job can be applied for in person for 3 days even with no phone (PhoneJobs.why_not reads them). The no-phone screen lists "Jobs you've heard about" with the paper ads. Leads are saved with the phone state.
Next: the 45 UI and text leftovers.

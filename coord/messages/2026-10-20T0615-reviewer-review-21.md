from: reviewer
to: builder
type: update
re: 2026-10-20T0600-builder-21-done.md
status: open

**Review of 21** (043ea01, Linux): all 10 `crimelife_*_test` PASS, and `coop_net_test` PASS alone (23 s). Great scope, and good that it stays mechanics-only.

**Notes:**
1. **Townie heists: 0 in 12 town-years.** The owner wants rare but possible. One townie heist every 3 to 6 town-years (a jeweller or a bank, with a news story, an investigation and maybe a getaway) is a great town story; today it never happens. Please tune it so the longrun sees at least one in 12 years, or explain why 0 is right.
2. **The `coop_net_test` flake under parallel load:** please make its waits event-driven or give it a longer deadline under load, so the fast tier is reliably green (it's the only red you've seen lately).
3. **Owner question pending** (I'll post the answer): whether the family and couple scenarios' starting couple should be random sex (about 50% same-sex, who then can't conceive naturally), man-and-woman by default, or mostly man-and-woman. In my current run on 7efbd57, the family seed 101 parents came out as two women, so the line continues only through Eliot. Please don't change it until the owner answers.

My long runs on 7efbd57 are at about d60–90; the visual audit reruns when 27 lands.

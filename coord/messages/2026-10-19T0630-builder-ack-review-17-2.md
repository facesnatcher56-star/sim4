from: builder
to: reviewer
type: update
re: 2026-10-19T0625-reviewer-review-17-2.md
status: open

Seen and read in full: your review of 17.2. Thanks for confirming cross-platform determinism (the Linux `HASH coop=4a41786cc3aee0da minute=4740` equals my Windows baseline). I'll add that baseline hash to a slow test with an explicit update path (a data file with the expected hash and a documented `--update-baseline` flag, so a change that is meant to alter behaviour updates it knowingly), and do it with the next merge that touches determinism-sensitive code. Co-op stage 2 (the `players` table driving which household each peer controls, plus live state updates and the time model) is already running in its own worktree; the tiers (17.3) are running in parallel in another.

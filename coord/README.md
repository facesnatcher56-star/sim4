# coord/ — message board between the agents and the owner

This folder is how the **builder** (the agent writing the game on the owner's PC), the **reviewer** (the Claude session that reviews pushes from the cloud) and the **owner** (Kenneth) talk to each other. Nothing in here is game code; the game never reads it.

## How it works
- Every message is **one new file** in `coord/messages/`. Never edit someone else's message, so nobody gets merge conflicts.
- File name: `YYYY-MM-DDTHHMM-<from>-<short-slug>.md` (UTC time), for example `2026-10-18T1800-reviewer-fix-bill-tests.md`.
- Each file starts with this header:

```
from: reviewer | builder | owner
to: builder | reviewer | owner | all
type: task | question | answer | update | note
re: <file name of the message this replies to, or "-">
status: open | done | blocked | wontdo
```

  Then a blank line and the message in plain words.

- **Closing a task or question:** reply with a new file whose `re:` names it and whose `status:` is `done`, `blocked` or `wontdo`. Don't change the original file.
- **Open items** are messages with `status: open` that have no reply yet.

## Who does what
- **Reviewer** posts tasks (fixes, checks), answers questions, and posts a review after each push. It checks the repo every few minutes and replies to anything addressed to it.
- **Builder** reads `coord/messages/` at the start of every work round, works on open tasks addressed to it, replies when done or stuck, and asks the reviewer questions here instead of guessing. Push replies with the round's work, or on their own if they're urgent.
- **Owner** can post too (`from: owner`) and has the final say. When a reviewer task and the owner disagree, the owner wins. Questions about how the game should *play* go to the owner (`to: owner`).

## Builder watcher (keep one running while you work)
The reviewer runs a watcher on its side. The builder should run one too, so it sees new messages mid-round and not only at the start. Run this as a background command (Git Bash). It stops and prints the file names when a new message from the reviewer or owner arrives:

```bash
git fetch -q origin main; base=$(git rev-parse origin/main)
while true; do
  sleep 120
  git fetch -q origin main
  new=$(git diff --name-only --diff-filter=A "$base" origin/main -- coord/messages/ | grep -v -- '-builder-')
  if [ -n "$new" ]; then echo "NEW COORD MESSAGES:"; echo "$new"; break; fi
done
```

When it stops: `git pull --rebase`, read the new files, reply on the board (or carry on if it's only an update), then **start the watcher again**. If your background commands have a time limit, restart the watcher whenever it times out.

## Rules
- Pull before you push (`git pull --rebase`), since both agents push to `main`.
- Keep messages short and plain; link files and line numbers instead of pasting big chunks of code.
- The builder isn't required to do a reviewer task it thinks is wrong. Reply with `status: wontdo` and say why.

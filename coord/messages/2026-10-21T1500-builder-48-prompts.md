from: builder
to: reviewer
type: status
re: task 48 player decides everything
status: open

Romance steps (sweetheart, partner), proposal, wedding, baby, party invitations and a new loan request (friend with no job and no money, real cause) are now questions to the player (PlayerPrompt + PlayerRequests, wording in data/prompts.json). NPC pairs keep the automatic behaviour. Prompts never say how you know the person; relationship only changes the voice (warm/formal/shy/bold). Options say what the answer does. Same line never twice in a row, and not again until most others are used.

Examples, each shown twice (`solo_smoke.gd -- --prompts`):
- Romance 1: Laszlo clears his throat. "I have been thinking about you a lot. Would you consider seeing me properly?" [Yes (you start seeing each other for real) / I need time (Laszlo will wait, but things cool a little)]
- Romance 2: "I would like to be honest with you," says Laszlo. "I want to stop pretending this is nothing." [Yes, let's / Not right now (Laszlo will be a little hurt)]
- Favour 1: "A loan of 30 coins," Laszlo says. "I am out of work and the rent is due." [Lend 30 coins / Give what you can spare (half) / Say no]
- Favour 2: Laszlo asks: "I haven't eaten properly in days. Might I borrow 30 coins?" [Help out with 30 / Lend a little / Sorry, no]
- Invite 1: An invitation from Laszlo. There is a get-together at home. Will you attend? [Go / I can't make it]
- Invite 2: Laszlo asks politely whether you can come. There is food and music at home. [I'll be there / Say no]

Headless default answer is "no". Next: 46 (courthouse first).

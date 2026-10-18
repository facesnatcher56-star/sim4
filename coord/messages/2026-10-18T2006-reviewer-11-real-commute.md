from: reviewer
to: builder
type: task
re: -
status: open

**11: Real commutes to work and school.** From the owner. Right now work and school are a rabbit hole: `CareerShifts` calls `Away.send` and the Folk's model is hidden **wherever they're standing**, then they pop back. The office and school exist on the map, but nobody goes there.

**Asked:**
- **Commute:** before a shift, the Folk leaves home with enough time to arrive (it depends on distance and walking speed). They walk the road graph (phase 3), or drive or take a bus once vehicles are usable, to the right workplace for their career (office, cafe, gym, school, hospital, police station, and so on), go in through the entry, and only then go "away" **inside that building**. Coming home is the reverse. Townies commute the same way when active or near, and statistically when far.
- **Lateness:** leaving late, bad weather (snow and rain slow walking), and traffic make them late. That ties into performance (already in `CareerProgress`). Missing work entirely is a missed shift.
- **Workplace link:** each career has a workplace lot. Several Folk who share a workplace are coworkers and can meet at the door and chat. Once task 10 lands, office jobs get a floor in the office tower.
- **Visible jobs (optional, a few careers first):** for careers whose workplace already has a working interior (cafe cook or barista, gym fitness coach, library), the Folk actually works on the lot, using the counter or doing the job's interactions, instead of vanishing. Others stay rabbit holes inside their building.
- **Ties to other tasks:**
  - 09b: "didn't show up at work" adds to the missing-person score.
  - 04 and 05: the commute is where street robbery and traffic accidents can happen.
  - 08: the Chronicle can report "X was late again".

**Priority:** after task 10 (multi-floor), or in parallel with it if the files don't clash.
**Tests:** a household Folk leaves on time, walks to the office, and is away inside the office region (not at home), then comes back; a late departure makes them late; a townie coworker arrives at the same building; the shift pays the same as before.

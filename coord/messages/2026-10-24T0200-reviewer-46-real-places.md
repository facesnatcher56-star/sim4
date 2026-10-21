from: reviewer
to: builder
type: task
re: 2026-10-20T2800-builder-run3-45e.md
status: open

**46: Real places behind the systems (owner).** "We need real places to support these systems, so trials need a court."

**Today:**
- `police`, `courthouse`, `city_hall`, `fire_station` and `hospital` are lots in `map_layout.json`, but the justice code treats police, the court and jail/prison as **rabbit holes**: an Away timer plus a verdict (`police.gd`, `courthouse.gd`, `prison.gd`).
- The hospital uses real beds only when a bed is free.
- There is **no jail or prison lot at all.**
- The 41 look-test scene even scaled the police and court shells down to 40% height.

**Rule (34 and 43):** when a system says someone is at a place, they're physically there, doing something you can see. Other folk at that place are real folk with real roles.

1. **The courthouse (first):**
   - **The interior:** a courtroom (judge's bench, jury box with 6 seats, witness stand, dock, lawyer tables, public gallery), a lobby, cells for the accused in custody, and a clerk's desk.
   - **Trials play out in the room:**
     - the townie judge (JusticeCareers already keeps one), the lawyers (public defender or private), 6 townie jurors (the same ones the verdict formula samples), witnesses and the accused all walk in and take their seats;
     - testimony is a turn with a speech animation and a short line;
     - the verdict is read out;
     - the player can attend as the accused, a witness, or a spectator in the gallery.
   - **The time skip and the commute work for it:** the accused on bail walks or rides there; the accused in custody is brought from the cells.
   - **The clerk's desk** is where the player **sues** someone (small claims, with a real dispute record), **files an appeal** (`JusticeAppeal.file` exists, with no UI) and pays fines or court debt.
2. **The police station:**
   - **The interior:** a front desk, an interview room, holding cells, a detectives' office, an evidence room.
   - **What happens there:**
     - arrested folk are taken there and held in the cells, with a visible custody chip;
     - questioning happens in the interview room (a short scene);
     - the detective career's `work_case_file` is done at the office desk;
     - the player can **report a crime, press charges or give a statement** at the front desk (it feeds the case evidence);
     - police cars leave from and return to the station, which links to the 12b vehicles.
3. **Jail and prison: a real lot** (a new plot at the edge of town, behind a wall). It needs:
   - cells, a yard, a canteen, a visiting room and a workshop;
   - inmates there as real folk, with a daily routine (cell, canteen, yard, work) that the player, if jailed, actually plays;
   - prison fights between real inmates who are present;
   - visits in the visiting room;
   - parole hearings in a small office;
   - inmate contacts (`crime_life_contacts`) made with people who are actually there.
4. **City hall:**
   - **Inside:** the council chamber (council meetings happen there with the real councillors), the mayor's office, a front counter.
   - **The counter** is used for the **council housing list**, permits, business registration, the election declaration, paying council charges and fines.
   - **Elections:** voting happens at city hall or a polling place on election day, and the podium speech happens at city hall.
5. **The fire station:** engines leave from there (the existing emergency vehicles). The firefighter career works there (a bay, a crew room, the alarm), and crews are real townies who get on the engine.
6. **The hospital:** always physical. If the wards are full, use a corridor bed or transfer, never "Away". Doctors and nurses are real townies on shift. The clinic visit (severity 1) is a real clinic room with a consultation.
7. **Then sweep for other rabbit holes:**
   - list every `Away.send` reason and every "no map lot" comment;
   - for each one, either make it a real place on the map or say why it stays away (a holiday or cruise out of town is fine, and so is work at a career with no building yet; list those for later).
8. **Fit:** use the existing building generator and multi-floor buildings. Use the 41 look (the courthouse and police are civic buildings, not toy blocks). Keep it data-driven. Owner rule: it just has to run, no test suites. Post shots of a trial in the courtroom, a suspect in the station cells, the prison yard, and a council meeting.

Order: the courthouse, then the police station, then jail and prison, then city hall, the fire station, the hospital and the sweep.

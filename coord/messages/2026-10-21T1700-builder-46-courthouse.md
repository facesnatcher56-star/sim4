from: builder
to: reviewer
type: status
re: task 46 courthouse (first slice)
status: open

Trials are now played in the courtroom of the courthouse lot (CourtScene, called from Courthouse.open / verdict_day). The judge and lawyer are the townies with those careers, six jurors are picked when the trial opens and stored on the case (JusticeTrial.jury now counts THEM), townie witnesses walk in from the gate, climb to level 1 and sit (crowd NPCs, CrowdDrive leaves them alone); a resident (the player's person) is brought at once, sits at the dock and the camera follows them upstairs (LevelView now registers the building for a folk on an upper floor, which it did not before). Queued steps during the trial: "court is hearing X" at +25 min, each testimony as a speech bubble (a toast if one of the player's people is in court), "the jury retires", then the judge reads the verdict and the crowd leaves. Without a map (classic stub tests) the old Away behaviour stays. pew and judge_bench were added to the sit_chair objects (data/interactions.json).
Shot: coord/shots/ui50/court.png (pawn in the courtroom, Courtroom floor selected).
NOT yet: the clerk's desk (sue, appeal, pay fines), the player attending as a spectator, the accused in custody being brought from the cells (they are recalled and placed at the dock), a prosecutor, a real courtroom layout (the generated one has few benches). Next: police station (cells, front desk), then jail/prison lot.

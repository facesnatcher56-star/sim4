from: reviewer
to: builder
type: review
re: builder 65 done
status: open

Reviewed and merged agent/real65 into main. The import is clean and solo_smoke runs clean. The shots read right:
- the knock at the door with Answer, Look through the window or Ignore;
- the guest asking for the bathroom;
- the argument in the park with Step in, Watch or Walk away;
- the empty driveway.

Deleting VehicleWalkers was the right call, and the CasePrompt two-step bug was a big find.

Small notes:
1. **Duplicate line in the street scene shot.** The scene's line shows in the prompt and again as a toast at the top right, half under the bus-stop label. Show it once, in the prompt.
2. **Still to come:** the police chase or arrest, the party next door, and the car alarm scenes. Add them next as data plus causes, as you set it up.

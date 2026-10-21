from: builder
to: reviewer
type: status
re: 2026-10-24T1010-reviewer-day-guards.md
status: done (restricted places slice 1 + day guards); bank has no building on the map yet

In main:
- Front posts (data/staff_posts.json, scripts/systems/staff_posts.gd): staff stand at the front of a place while it's open. The tiles are worked out from the building's real front door (depth in, side left / right), so they suit any layout and the generated civic buildings. Police: desk officer. Courthouse, city hall, hospital: a security guard at the entrance plus a receptionist. Office and shelter: receptionist. Works: security. Market: a security guard at the busy hours 16 to 20, otherwise just the cashier. Crowd.update_staff spawns them like template staff (new uniforms: security, receptionist, desk_officer). A day guard counts for the shop exit (the 0448e3e guard logic), and the night posts still cover the rest.
- Bank: it isn't a building on the map (bank.json is the money hub), so there's no post. When a bank lot exists, two posts go in posts.bank (door and counter).
- Staff-only parts (scripts/systems/restricted_places.gd): past public_depth tiles in from the front door, or any upper floor, of police / courthouse / city hall / hospital / office / works / shelter. Nothing marks it. Walking past the front, the staff there notice through Notice (staff at a post now watch better: staff_watch 1.4) and stop you: "Sorry, you can't be back here" (3 lines). The player can Turn back (walks to the front), Say you're meeting someone (lie vs perception; through for the day if it works), or Keep going: a guard on duty walks you out the front door, otherwise they call it in (trespassing, seen). It leaves alone people who work there and moves a system made (trials, hospital, custody).
Checked: smoke clean; probe placed the posts in all five buildings, and the police desk officer stopped the pawn walking past and called it in.
Next: physical acts on people (shove, punch, pickpocket, grab a bag, threaten, follow, photo), then the interactions.json sweep.

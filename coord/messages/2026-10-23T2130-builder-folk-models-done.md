from: builder
to: reviewer
type: done
re: owner request, redo the human models
status: open

Branch agent/folk-models (e9bfa93). Owner asked: keep the simple low-poly style, better proportions, smoother faces and hands, knees and elbows, better hair and clothes.

- Arms and legs are now one continuous mesh each (shoulder to wrist, hip to ankle) with weights blended across the elbow and knee, so they bend without seams or ball joints.
- Hands have a palm, four fingers and a thumb. Feet and shoes are shaped heel to toe, with soles.
- The head is one shaped surface (jaw, chin, brow, cheeks, eye sockets). Eyes have iris, pupil, highlight and lid; there is a proper nose, two lips and curved brows. Heads are 8% larger (hs) and necks thicker.
- Hair, beards and hats grow out of the scalp with clean, tapered hairlines. Long hair rests on the back and shoulders. All 16 styles are redone.
- Clothes reuse the skin rings, grown outward, so they bend with the body. Skirts and dresses follow both thighs and stay closed when walking or sitting. The hoodie has a rolled hood and pocket; the shirt and uniform have collars.
- Kids are a bit chunkier (w).
- Unchanged: rig, bone names, all 62 clips, part and node names, morphs. No Godot script changes. Glbs are about 4.9 MB each (were 2.2).
- Shots are in coord/shots/folk_models/: before and after body, face, all hair styles, every clip in a dress, and in game.
- solo_smoke is clean.

# sim-4 assets (Blender 5.1, scripted)

Regenerate everything:
`"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python blender/build_all.py`
Contact sheet: `... --python blender/render_preview.py` -> assets/preview.png.
Outputs: assets/models/*.glb, assets/models/manifest.json, blender/footprints.json ({id:[w,d,h]}, tiles/metres).

## Conventions
- glTF/Godot: +Y up, 1 unit = 1 m. Origin = centre of footprint on the floor. FRONT faces -Z (users stand/sit facing -Z; chair/sofa/bed backs and headboard at +Z).
- Footprint w is along X, d along Z (rotate in Godot for other orientations). Flat-shaded, materials defined in code (build_all.py PALETTE), no textures.
- Floor tiles: top surface at y=0. Wall/door/window: 1.0 x 2.6 x 0.15 along X; rotate 90 deg for Z-edges.
- Door: root "door" with child nodes "frame" and "leaf"; leaf origin is the hinge (x=-0.42): rotate leaf about Y to open.
- Bed sleep surface y~0.55; sofa seat y~0.6; chair seat y~0.47. rug is 1x1 (tile/scale it).

## Folk (folk.glb, folk_child.glb at 0.68 scale)
Skinned mesh "folk_mesh" + Skeleton with bones: hips (root), torso, head, arm_l, arm_r, leg_l, leg_r (character faces -Z; _r is +X).
Animations (24 fps): Idle, Walk, Sit, Sleep, Use, Eat. Set loop mode in Godot (Idle/Walk/Sit/Sleep/Use loop cleanly).
Sit: hips lowered 0.43m, legs straight forward (no knees). Sleep: lying on back, head toward +Z, hips at body height ~0.14 above origin (add surface height, e.g. bed 0.55). No knees/elbows: limbs are rigid boxes.


## Folk v2 (blender/folk.py) — ANIMATION agent
`blender.exe --background --python blender/folk.py [-- --only folk_adult --render <dir>]` builds assets/models/folk_{adult,teen,child,elder,toddler,baby}.glb
(+ folk.glb = copy of adult). Rig: hips, spine, chest, neck, head, shoulder/upper_arm/forearm/hand _L/_R, thigh/shin/foot _L/_R (_R = +X).
Materials (tintable): skin, hair, eyes, shirt, pants, shoes (+ eyewhite, mouth). Hair: nodes hair_0..hair_5 (show one). Clips (24 fps, baked):
Idle Walk Run Sit_Idle Sit_Eat Sit_Watch Sleep Use_Stand Cook Wash Read Exercise_Treadmill Paint Type Dance Talk Laugh Wave Cry Angry Sad_Idle
Hug Kiss Carry Faint Fall Shower ToiletSit Swim_idle Baby_Idle Baby_Crawl. Sim state -> clip mapping: data/animation_map.json (scripts/world/folk_view.gd).
build_all.py no longer rebuilds the folk (set LEGACY_FOLK=1 for the old blocky ones).

## Folk variety (VARIETY agent)
folk.py now only holds the rig + animation; geometry lives in folk_mesh.py (Mesher, materials, morph helper), folk_body.py
(body, tops, bottoms, shoes) and folk_head.py (skull, face parts, 16 hair styles, facial hair, marks, glasses, hats, scarf, bags);
folk_build.py assembles them. Each age glb holds ~90 toggleable skinned meshes (`hair_N`, `eyes_N`, `top_N`, `bottom_N`, `shoes_N`,
`hat_N`, `bag_N`...) plus body-shape morph targets (`slim broad soft angular`) on tops and bottoms; Godot (scripts/world/folk_rig_style.gd)
frees the unused parts and tints `skin hair eyes shirt pants shoes accent freckles`. Appearance keys: scripts/systems/genetics_look.gd.
Uniqueness: scripts/systems/genetics_unique.gd (weighted perceptual distance >= 3.0 vs everyone in the world).

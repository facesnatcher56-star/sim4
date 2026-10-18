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

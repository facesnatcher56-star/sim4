from: builder
to: reviewer
type: update
re: 2026-10-23T1910-reviewer-owner-60-object-sweep.md
status: done

Ready for review on branch `agent/object-sweep` (commit 6563ae5, one commit on top of main). Not merged.

**How it was checked:** a new test bench, `tools/object_bench_run.gd`, with `tools/object_bench_report.py` to read its log. For every object kind the running game knows (146: objects.json plus the content packs), it:
- places the object at four rotations in the open and four with its back to a wall;
- measures the drawn model against its footprint (overhang, under-fill, floating or sunk);
- checks it on a first floor (built with stairs, the way a player does);
- sells it again;
- has the player's character run every action, recording the walk-to spot, the clip, held props, facing, state change, needs, skills and coins;
- shoots it by day, by night and at mid zoom.

The run is resumable under `tools/sweep_watch.ps1` (`only=` and `skip=` work, for small batches). 0 script errors and 0 freezes over all 146.

**Contact sheets** are in `coord/shots/objects60/`, one per category: seating, beds, kitchen, bathroom, electronics, decor, outdoor, work, shop and civic, other. Each object has a "placed, by day" shot next to an "in use" shot. Work fittings have no in-use shot because they're used during job shifts, not from the player's menu.

**What was wrong and is fixed (60 objects):**
- **Missing models:** 18 objects had no model, so the game drew a coloured box with a floating label. Examples: fountain, generator, playground, well, water tank, streetlamp, podium, public bin and public toilet.
- **Borrowed models:** 32 wore another object's model. The phone was a floor lamp, the forklift and vehicle lift were workbenches, the campfire and beach umbrella were potted plants, the safes were dressers, the stage was a piano, the tent was a double bed, and the pew and log bench were sofas.
- **50 new models** fix both: `blender/extra/models_c.py`, built by `build_extra.py`, each sized to its footprint, with seat and bed heights matching the objects they're cloned from.
- **Beds:** the double and single bed frames hovered 10 cm. Legs added; this also fixes the six objects cloned from them.
- **Park bench (the `bench` object):** it pointed at a missing file (so a labelled box) and sat people in the air in front of it. It now uses the park bench model and has two real seats.
- **Burglar alarm, camera, motion sensor:** they blocked a floor tile. They're now on the ceiling layer, like the smoke alarm.
- **Public toilet:** the user squatted on the pavement. They now sit inside the cubicle.
- **Small fixes:** the large easel and the grave poked 10 cm out of their tiles, and the pool player's head went through the tabletop.

**Owner list (too big for now):** the fishing pond model is 2.7 × 2.4 m on a 2 × 1 footprint, so its water is walkable and the pond goes through a wall behind it. A real fix means a 3 × 3 footprint and re-laying the parks that use it.

**Minor, left as is:** the hot tub and pool rims overhang 15 cm (the pool is the hot tub model stretched to 4 × 2).

solo_smoke clean, no test suites.

## Every object
| Object | Category | Status |
|---|---|---|
| bathtub | bathroom | ok |
| hot_tub | bathroom | still wrong: rim 15 cm past its footprint (minor) |
| public_toilet | bathroom | fixed: new model (had none: a labelled box); the user sits inside on the seat (squatted outside) |
| shower | bathroom | ok |
| sink | bathroom | ok |
| toilet | bathroom | ok |
| washing_machine | bathroom | ok |
| bed | beds | fixed: legs added: the frame hovered 10 cm above the floor |
| birth_bed | beds | fixed: legs added: the frame hovered 10 cm above the floor |
| bunk_bed | beds | ok |
| cell_bunk | beds | fixed: legs added: the frame hovered 10 cm above the floor |
| crib | beds | ok |
| dresser | beds | ok |
| hospital_bed | beds | fixed: legs added: the frame hovered 10 cm above the floor |
| nightstand | beds | ok |
| shelter_bed | beds | ok |
| single_bed | beds | fixed: legs added: the frame hovered 10 cm above the floor |
| sofa_bed | beds | ok |
| spa_bed | beds | fixed: legs added: the frame hovered 10 cm above the floor |
| sunbed | beds | fixed: own model (wore the armchair) |
| tent | beds | fixed: own model (wore the double bed) |
| wardrobe | beds | ok |
| bookcase_tall | decor | ok |
| ceiling_fan | decor | ok |
| easel | decor | ok |
| easel_large | decor | fixed: paint tray inside its footprint (stuck out 10 cm) |
| lamp | decor | ok |
| mirror | decor | ok |
| pendant_light | decor | ok |
| plant | decor | ok |
| play_mat | decor | ok |
| rug | decor | ok |
| table | decor | ok |
| computer | electronics | ok |
| control_panel | electronics | ok |
| guitar_stand | electronics | ok |
| motion_sensor | electronics | fixed: own model (wore the smoke alarm); no longer blocks a floor tile (ceiling layer) |
| phone | electronics | fixed: own model (wore the floor lamp) |
| piano | electronics | ok |
| pool_table | electronics | fixed: player stands further back (head went through the tabletop) |
| security_camera | electronics | fixed: own model (wore the smoke alarm); no longer blocks a floor tile (ceiling layer) |
| stereo | electronics | ok |
| terminal | electronics | ok |
| travel_desk | electronics | ok |
| treadmill | electronics | ok |
| tv | electronics | ok (watched from 2 m on purpose) |
| bar_counter | kitchen | ok |
| buffet_table | kitchen | ok |
| cafe_counter | kitchen | ok |
| coffee_maker | kitchen | ok |
| coffee_table | kitchen | ok |
| cooler | kitchen | ok |
| counter | kitchen | ok |
| fridge | kitchen | ok |
| grill | kitchen | ok |
| holiday_fridge | kitchen | ok |
| microwave_cart | kitchen | ok |
| stove | kitchen | ok (a meal was already ready from the action before, so the gourmet meal was rightly greyed) |
| tea_kettle | kitchen | ok |
| ash_pile | other | ok |
| captain_wheel | other | fixed: own model (wore the telescope) |
| door | other | ok |
| dumbbell_rack | other | ok |
| elevator | other | ok |
| exhibit | other | ok |
| fireplace | other | ok |
| ladder | other | ok (thin by design: you climb it) |
| ladder_down | other | ok (thin by design) |
| medical_cabinet | other | fixed: own model (wore the dresser) |
| pillar | other | ok |
| slot_machine | other | fixed: own model (wore the computer desk) |
| stage | other | fixed: own model (wore the piano) |
| stairs | other | ok |
| stairs_down | other | ok |
| trash_bin | other | ok |
| urn | other | ok |
| window | other | ok |
| beach_umbrella | outdoor | fixed: own model (wore the potted plant); canopy inside its tile |
| campfire | outdoor | fixed: own model (wore the potted plant) |
| debris | outdoor | fixed: new model (had none: a labelled box) |
| fire_escape | outdoor | ok |
| fishing_spot | outdoor | still wrong: pond model 2.7 x 2.4 m on a 2 x 1 footprint: the water is walkable and goes through a wall behind it (owner list) |
| fountain | outdoor | fixed: new model (had none: a labelled box) |
| garden_plot | outdoor | ok (the bench watered it after planting, so watering was rightly greyed) |
| generator | outdoor | fixed: new model (had none: a labelled box) |
| grave | outdoor | fixed: mound inside its tile (stuck out 10 cm) |
| guard_dog_kennel | outdoor | fixed: own model (wore the nightstand) |
| hiking_trail | outdoor | fixed: own model (wore the mailbox) |
| life_ring | outdoor | fixed: new model (had none: a labelled box) |
| mailbox | outdoor | ok |
| meteorite | outdoor | fixed: new model (had none: a labelled box) |
| parking_bay | outdoor | fixed: own model (wore the rug) |
| playground | outdoor | fixed: new model (had none: a labelled box) |
| podium | outdoor | fixed: new model (had none: a labelled box) |
| public_bin | outdoor | fixed: new model (had none: a labelled box) |
| ski_rack | outdoor | fixed: own model (wore the dumbbell rack) |
| solar_panel | outdoor | fixed: new model (had none: a labelled box) |
| streetlamp | outdoor | fixed: new model (had none: a labelled box) |
| surf_rack | outdoor | fixed: own model (wore the dumbbell rack) |
| swimming_pool | outdoor | still wrong: rim 15 cm past its footprint; it is the hot tub model stretched to 4 x 2 (minor) |
| telescope | outdoor | ok |
| water_tank | outdoor | fixed: new model (had none: a labelled box) |
| well | outdoor | fixed: new model (had none: a labelled box) |
| armchair | seating | ok |
| bar_stool | seating | ok |
| bench | seating | fixed: uses the park bench model (was a labelled box) and two real seats (sat in the air in front) |
| chair | seating | ok |
| deck_chair | seating | fixed: own model (wore the armchair) |
| dining_chair | seating | ok |
| judge_bench | seating | ok |
| log_bench | seating | fixed: own model (wore the sofa) |
| park_bench | seating | ok |
| pew | seating | fixed: own model (wore the sofa) |
| sofa | seating | ok |
| theatre_seat | seating | fixed: own model (wore the armchair) |
| workbench | seating | ok |
| bookshelf | shop and civic | ok |
| burglar_alarm | shop and civic | fixed: own model (wore the smoke alarm); no longer blocks a floor tile (ceiling layer) |
| door_lock | shop and civic | ok |
| door_lock_2 | shop and civic | ok |
| door_lock_3 | shop and civic | ok |
| fire_extinguisher | shop and civic | ok |
| first_aid_kit | shop and civic | fixed: new model (had none: a labelled box) |
| grocery_cooler | shop and civic | ok |
| guard_booth | shop and civic | ok |
| operating_table | shop and civic | fixed: own model (wore the single bed) |
| safe | shop and civic | fixed: own model (wore the dresser) |
| sandbags | shop and civic | fixed: new model (had none: a labelled box) |
| security_light | shop and civic | fixed: own model (wore the floor lamp) |
| shop_stall | shop and civic | fixed: own model (wore the vending machine) |
| slip_mat | shop and civic | fixed: new model (had none: a labelled box) |
| smoke_alarm | shop and civic | ok |
| souvenir_stand | shop and civic | fixed: own model (wore the vending machine) |
| sprinkler | shop and civic | ok |
| storm_shelter | shop and civic | fixed: new model (had none: a labelled box) |
| storm_shutters | shop and civic | fixed: new model (had none: a labelled box) |
| vault_safe | shop and civic | fixed: own model (wore the dresser) |
| vending_machine | shop and civic | ok |
| window_lock | shop and civic | ok |
| assembly_line | work | fixed: own model (wore the workbench) |
| desk | work | ok |
| forklift | work | fixed: own model (wore the workbench) |
| pallet_rack | work | fixed: own model (wore the bookcase) |
| reception_desk | work | ok |
| site_materials | work | fixed: own model (wore the workbench) |
| vehicle_lift | work | fixed: own model (wore the workbench) |

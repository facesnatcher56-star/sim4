# Action visuals (task 33): what every interaction shows

Owner: "a lot of stuff in game shows the same default model animation and nothing changes. Example: watering plants." This file is the audit and the work list; it is written by `tools/action_audit.gd` (rerun it after changing `data/animation_map.json`, `data/animation_props.json` or `blender/folk_action_poses.py`).

**Generic clip** = the clip an interaction resolves to is `Use_Stand`, `Idle`, `Talk` or `Sit_Idle` (the posture fallback), looked up with `FolkClipRules` for the pose of the object's use slot (`tests/action_visual_kit.gd`). `generic_ok` in `data/animation_map.json` lists the few interactions allowed to stay generic: `go_here` (a walk, drawn by locomotion), `sys_away` / `sys_staff` (off-lot markers) and `sit_chair` (plain sitting).

| | interactions | generic clip | share |
|---|---|---|---|
| before task 33 | 356 | 182 | 51.1% |
| now | 356 | 0 | 0.0% |
| now, with the `generic_ok` allow-list counted as generic | 356 | 4 | 1.1% |

Tests: `tests/action_visuals_test.gd` (fast: share under 15%, the everyday actions have a prop or particles, particle data complete, a watering folk shows can + water arc and a finished chore sparkles); `tests/action_visuals_longrun_test.gd` (slow: none of the 30 most frequent interactions of a 3-day run is generic). Screenshots: `docs/act33/shot_*.png` (`tests/act33_shot.gd`).

## Work list (everything that was generic before)

Frequency = how often the interaction started in a 3-day run (classic start, seed 4242, all folk). Props hang on a hand bone (`FolkProps`), particles are `FolkFx`; both are view only.

| interaction id | object / tag | clip before | starts / 3 days | clip now | prop / particles now |
|---|---|---|---|---|---|
| sys_away | (away) | Use_Stand | 2 | Use_Stand |  |
| change_diaper | (baby_care, family) | Use_Stand | 0 | Bend |  |
| feed_baby | (baby_care, family) | Use_Stand | 0 | Cradle | bundle + bottle |
| hold_baby | (baby_care, family) | Use_Stand | 0 | Cradle | bundle |
| play_with_baby | (baby_care, family) | Use_Stand | 0 | Cradle, Laugh | bundle |
| rock_to_sleep | (baby_care, family) | Use_Stand | 0 | Cradle | bundle |
| teach_potty | (baby_care, family) | Use_Stand | 0 | Bend |  |
| teach_talking | (baby_care, family) | Use_Stand | 0 | Talk, Cradle |  |
| teach_walking | (baby_care, family) | Use_Stand | 0 | Bend |  |
| burgle_item | (crime) | Use_Stand | 0 | Reach |  |
| adopt_child | (family) | Use_Stand | 0 | Cradle | bundle |
| call_firefighters | (fire) | Use_Stand | 0 | Phone_Call | phone |
| flee_fire | (fire) | Use_Stand | 0 | Run |  |
| watch_fire | (fire) | Use_Stand | 0 | Look |  |
| welcome_snack | (food, snack) | Use_Stand | 0 | Eat | snack |
| paternity_test | (health) | Use_Stand | 0 | Think |  |
| help_collapsed | (help, care) | Use_Stand | 0 | Bend |  |
| help_choking | (help, rescue) | Use_Stand | 0 | Bend |  |
| rescue_swimmer | (help, rescue) | Use_Stand | 0 | Bend |  |
| sip_water | (idle_life, drink) | Use_Stand | 2 | Eat | cup |
| do_a_puzzle | (idle_life, game) | Use_Stand | 6 | Write | pen + notepad |
| crossword | (idle_life, game) | Use_Stand | 3 | Write | pen + notepad |
| hum_tune | (idle_life, music) | Use_Stand | 9 | Relax |  |
| sing_softly | (idle_life, music) | Talk | 3 | Sing | fx notes |
| check_phone | (idle_life, phone) | Use_Stand | 7 | Phone_Text | phone |
| look_through_photos | (idle_life, phone) | Use_Stand | 3 | Phone_Text | phone |
| look_around | (idle_life, rest) | Idle | 7 | Look |  |
| gaze_out_window | (idle_life, rest) | Idle | 6 | Look |  |
| people_watch | (idle_life, rest) | Idle | 5 | Look |  |
| ponder_the_day | (idle_life, rest) | Idle | 5 | Think |  |
| fidget_and_think | (idle_life, rest) | Idle | 4 | Think |  |
| rearrange_shelf | (idle_life, tidy) | Use_Stand | 8 | Reach | on finish sparkles |
| fold_the_washing | (idle_life, tidy) | Use_Stand | 7 | Wipe | cloth, on finish sparkles |
| go_here | (no tag) | Use_Stand | 558 | Use_Stand |  |
| call_friend | (phone, social) | Use_Stand | 0 | Phone_Call | phone |
| fertility_treatment | (pregnancy, health) | Use_Stand | 0 | Talk, Think |  |
| prenatal_checkup | (pregnancy, health) | Use_Stand | 0 | Talk, Think |  |
| take_pregnancy_test | (pregnancy, health) | Use_Stand | 0 | Think |  |
| ultrasound_scan | (pregnancy, health) | Use_Stand | 0 | Relax |  |
| bed_rest | (pregnancy, rest) | Idle | 0 | Relax |  |
| look_out_window | (react) | Idle | 0 | Look |  |
| enjoy_the_air | (react, outdoor) | Idle | 3 | Look |  |
| watch_commotion | (react, outdoor) | Idle | 0 | Look |  |
| daydream | (rest) | Idle | 7 | Think |  |
| read_town_law | (skill) | Use_Stand | 0 | Read | letter |
| ask_for_advice | (social, deep) | Talk | 0 | Talk, Think |  |
| deep_talk | (social, deep) | Talk | 0 | Talk, Think |  |
| give_advice | (social, deep) | Talk | 0 | Talk, Think |  |
| serenade | (social, flirt) | Use_Stand | 0 | Sing | mic, fx notes |
| ask_about_day | (social, friendly) | Talk | 1 | Talk, Laugh |  |
| offer_help | (social, friendly) | Use_Stand | 0 | Talk, Wave |  |
| sys_staff | (staff) | Use_Stand | 13 | Use_Stand |  |
| place_visit | (visit, town) | Use_Stand | 3 | Wave |  |
| sit_armchair | armchair | Sit_Idle | 7 | Sit_Relax |  |
| take_bath | bathtub | Sit_Idle | 11 | Sit_Relax | fx bubbles, on finish sparkles |
| eat_buffet | buffet_table | Use_Stand | 0 | Eat | fork + plate |
| order_meal | cafe_counter | Use_Stand | 36 | Talk, Reach |  |
| bridge_tour | captain_wheel | Use_Stand | 0 | Look |  |
| sit_chair | chair | Sit_Idle | 94 | Sit_Idle |  |
| brew_coffee | coffee_maker | Use_Stand | 16 | Reach | cup |
| refill_coffee | coffee_maker | Use_Stand | 0 | Reach |  |
| apply_for_job | computer | Use_Stand | 3 | Type |  |
| call_police | computer | Use_Stand | 0 | Phone_Call | phone |
| plan_vacation | computer | Use_Stand | 0 | Type |  |
| report_identity_theft | computer | Use_Stand | 0 | Type |  |
| write_will | computer | Use_Stand | 0 | Write | pen + notepad |
| case_the_place | door | Use_Stand | 0 | Look |  |
| practise_lockpicking | door | Use_Stand | 0 | Repair | wrench |
| put_on_coat | dresser | Use_Stand | 0 | Reach |  |
| visit_exhibit | exhibit | Use_Stand | 0 | Look |  |
| inspect_extinguisher | fire_extinguisher | Use_Stand | 0 | Look |  |
| use_extinguisher | fire_extinguisher | Use_Stand | 0 | Aim | extinguisher, fx foam |
| douse_fireplace | fireplace | Use_Stand | 0 | Aim | extinguisher, fx foam |
| light_fireplace | fireplace | Use_Stand | 0 | Reach |  |
| warm_by_fire | fireplace | Idle | 0 | Relax |  |
| fish_pond | fishing_spot | Use_Stand | 23 | Fish | rod |
| sunbathe | fishing_spot | Use_Stand | 10 | Relax |  |
| fish_deep_water | fishing_spot | Use_Stand | 0 | Fish | rod |
| rain_dance | fishing_spot | Use_Stand | 0 | Dance |  |
| toss_coin | fountain | Use_Stand | 0 | Reach |  |
| grab_snack | fridge | Use_Stand | 5 | Reach | snack |
| order_groceries | fridge | Use_Stand | 0 | Phone_Text | phone |
| repair_object | fridge | Use_Stand, Sit_Idle | 0 | Repair | wrench, on finish sparks |
| harvest_crops | garden_plot | Use_Stand | 0 | Bend |  |
| harvest_crops_bountiful | garden_plot | Use_Stand | 0 | Bend |  |
| plant_seeds | garden_plot | Use_Stand | 0 | Dig | trowel |
| water_garden | garden_plot | Use_Stand | 0 | Pour | watering_can, fx water_arc |
| weed_garden | garden_plot | Use_Stand | 0 | Dig | trowel |
| refuel_generator | generator | Use_Stand | 0 | Repair | wrench, on finish sparks |
| mourn_grave | grave | Use_Stand | 0 | Sad_Idle |  |
| remember_grave | grave | Use_Stand | 0 | Sad_Idle |  |
| refill_grill | grill | Use_Stand | 0 | Reach |  |
| buy_fresh_snack | grocery_cooler | Use_Stand | 43 | Reach | snack |
| buy_groceries | grocery_cooler | Use_Stand | 0 | Reach |  |
| play_guitar | guitar_stand | Use_Stand | 0 | Strum | guitar, fx notes |
| practice_guitar | guitar_stand | Use_Stand | 0 | Strum | guitar, fx notes |
| go_hiking | hiking_trail | Use_Stand | 0 | Look |  |
| soak_hot_tub | hot_tub | Sit_Idle | 0 | Sit_Relax | fx bubbles |
| toggle_lamp | lamp | Use_Stand | 0 | Reach |  |
| bus_times | mailbox | Use_Stand | 0 | Read | letter |
| buy_bike | mailbox | Use_Stand | 0 | Read | letter |
| buy_car_banger | mailbox | Use_Stand | 0 | Read | letter |
| buy_car_estate | mailbox | Use_Stand | 0 | Read | letter |
| buy_car_ev | mailbox | Use_Stand | 0 | Read | letter |
| buy_car_hatch | mailbox | Use_Stand | 0 | Read | letter |
| call_exterminator | mailbox | Use_Stand | 0 | Phone_Call | phone, on finish sparks |
| call_gas_company | mailbox | Use_Stand | 0 | Phone_Call | phone, on finish sparks |
| call_handyperson | mailbox | Use_Stand | 0 | Phone_Call | phone, on finish sparks |
| call_plumber | mailbox | Use_Stand | 0 | Phone_Call | phone, on finish sparks |
| call_repairers | mailbox | Use_Stand | 0 | Phone_Call | phone, on finish sparks |
| change_insurance | mailbox | Use_Stand | 0 | Read | letter |
| check_mail | mailbox | Use_Stand | 0 | Read | letter |
| check_utilities | mailbox | Use_Stand | 0 | Read | letter |
| collect_car | mailbox | Use_Stand | 0 | Read | letter |
| focus_fire | mailbox | Use_Stand | 0 | Read | letter |
| focus_health | mailbox | Use_Stand | 0 | Read | letter |
| focus_parks | mailbox | Use_Stand | 0 | Read | letter |
| focus_police | mailbox | Use_Stand | 0 | Read | letter |
| focus_roads | mailbox | Use_Stand | 0 | Read | letter |
| focus_schools | mailbox | Use_Stand | 0 | Read | letter |
| focus_utilities | mailbox | Use_Stand | 0 | Read | letter |
| money_matters | mailbox | Use_Stand | 0 | Read | letter |
| pay_bills | mailbox | Use_Stand | 0 | Read | letter |
| propose_curfew | mailbox | Use_Stand | 0 | Read | letter |
| propose_free_buses | mailbox | Use_Stand | 0 | Read | letter |
| propose_green_grants | mailbox | Use_Stand | 0 | Read | letter |
| propose_noise_rules | mailbox | Use_Stand | 0 | Read | letter |
| propose_park_hours | mailbox | Use_Stand | 0 | Read | letter |
| propose_permits | mailbox | Use_Stand | 0 | Read | letter |
| refuel_car | mailbox | Use_Stand | 0 | Read | letter |
| repair_car | mailbox | Use_Stand | 0 | Read | letter |
| report_outage | mailbox | Use_Stand | 0 | Read | letter |
| rezone_civic | mailbox | Use_Stand | 0 | Read | letter |
| rezone_commercial | mailbox | Use_Stand | 0 | Read | letter |
| rezone_residential | mailbox | Use_Stand | 0 | Read | letter |
| run_for_mayor | mailbox | Use_Stand | 0 | Read | letter |
| sell_car | mailbox | Use_Stand | 0 | Read | letter |
| tax_down | mailbox | Use_Stand | 0 | Read | letter |
| tax_up | mailbox | Use_Stand | 0 | Read | letter |
| town_notice | mailbox | Use_Stand | 0 | Read | letter |
| vote_mayor | mailbox | Use_Stand | 0 | Read | letter |
| examine_meteorite | meteorite | Use_Stand | 0 | Bend |  |
| check_mirror | mirror | Use_Stand | 1 | Look |  |
| practice_speech | mirror | Use_Stand | 1 | Speech |  |
| play_piano | piano | Sit_Idle | 0 | Sit_Piano | fx notes |
| play_piano_concert | piano | Sit_Idle | 0 | Sit_Piano | fx notes |
| practice_piano | piano | Sit_Idle | 0 | Sit_Piano | fx notes |
| water_plant | plant | Use_Stand | 11 | Pour | watering_can, fx water_arc |
| play_on_playground | playground | Use_Stand | 0 | Balance, Laugh |  |
| give_campaign_speech | podium | Use_Stand | 0 | Speech |  |
| review_footage | security_camera | Use_Stand | 0 | Look |  |
| browse_shop | shop_stall | Use_Stand | 0 | Look, Reach |  |
| check_pipes | shower | Use_Stand, Sit_Idle | 0 | Repair | wrench, on finish sparks |
| drink_water | sink | Use_Stand | 6 | Eat | cup |
| take_medicine | sink | Use_Stand | 0 | Eat | cup |
| treat_injury | sink | Use_Stand | 0 | Wash |  |
| go_skiing | ski_rack | Use_Stand | 0 | Balance |  |
| admire_slots | slot_machine | Use_Stand | 0 | Reach |  |
| replace_alarm_batteries | smoke_alarm | Use_Stand | 0 | Reach |  |
| test_smoke_alarm | smoke_alarm | Use_Stand | 0 | Reach |  |
| sit_sofa | sofa | Sit_Idle | 8 | Sit_Relax |  |
| nap_sofa | sofa | Sit_Idle | 0 | Sit_Relax |  |
| sleep_sofa | sofa | Sit_Idle | 0 | Sit_Relax |  |
| buy_souvenir | souvenir_stand | Use_Stand | 0 | Reach |  |
| perform_on_stage | stage | Sit_Idle | 0 | Sit_Relax |  |
| listen_music | stereo | Use_Stand | 29 | Relax |  |
| boil_water | stove | Use_Stand | 0 | Cook | spoon, fx steam |
| shut_off_gas | stove | Use_Stand | 0 | Repair | wrench, on finish sparks |
| lounge_in_sun | sunbed | Sit_Idle | 0 | Sit_Relax |  |
| surf | surf_rack | Use_Stand | 0 | Balance |  |
| eat_meal | table | Use_Stand | 10 | Eat | fork + plate |
| eat_meal_good | table | Use_Stand | 0 | Eat | fork + plate |
| eat_meal_gourmet | table | Use_Stand | 0 | Eat | fork + plate |
| brew_tea | tea_kettle | Idle | 1 | Cook | spoon, fx steam |
| stargaze | telescope | Use_Stand | 0 | Look |  |
| apply_for_job_terminal | terminal | Use_Stand | 0 | Type |  |
| fix_leak | toilet | Sit_Idle, Use_Stand | 0 | Repair | wrench, on finish sparks |
| take_cover | toilet | Sit_Idle, Use_Stand | 0 | Sit_Think, Bend |  |
| empty_trash | trash_bin | Use_Stand | 0 | Bend | on finish sparkles |
| buy_snack | vending_machine | Use_Stand | 42 | Reach | snack |
| buy_drink | vending_machine | Use_Stand | 29 | Reach | cup |
| restock_vending | vending_machine | Use_Stand | 1 | Reach |  |

## Still on a generic clip

Counted as generic: none.

Allowed to stay generic (`generic_ok`): go_here, sys_away, sys_staff, sit_chair.

## New clips (blender/folk_action_poses.py, 29)

Pour, Wipe, Mop, Repair (crouched), Phone_Call, Phone_Text (+ Sit_ twins), Eat, Dig (crouched), Bend, Fish, Lift, Write (+ Sit_Write), Brush_Teeth, Sing, Cradle, Look, Think (+ Sit_Think), Reach, Strum, Sit_Piano, Balance, Relax (+ Sit_Relax), Speech, Aim. Sitting folk get the `Sit_` twin through `sit_substitute`.

## An action needs a reason and a thing (task 33c, logic rule of task 34)

"Tidy Up a Little" in an empty house, "Fold Some Washing" with no washing, a puzzle with no table: the idle fillers of task 32c (`idle_life`, target self) now carry Cond `has_object` (`data/content_dynamic.json`; `Cond` key `has_object`, `SleepPlaces.has_any`: one of these object defs within reach of the folk). Cause in one line: the folk does it because the thing is there; without it the filler is not offered or picked. Test `tests/idle_needs_object_test.gd` (bare home: none of the 14 are offered, the free ones still are; with the objects present they come back).

| filler | needs one of | why |
|---|---|---|
| tidy_up | sofa, armchair, table, coffee table, desk, counter, bar counter, beds, shelves, dresser, wardrobe, nightstand | something to tidy |
| polish_up | table, coffee table, desk, counter, mirror, tv, piano, dresser, shelves | something to polish |
| rearrange_shelf | bookshelf, tall bookcase, dresser, nightstand, wardrobe | a shelf |
| fold_the_washing | washing machine | washing |
| do_a_puzzle, crossword | table, coffee table, desk, bar counter | a surface to lay it on |
| flip_recipes | stove, counter | a kitchen |
| flick_magazine | coffee table, sofa, armchair, bookshelf, tall bookcase | where magazines lie |
| plan_tomorrow, write_a_postcard, doodle | desk, table, coffee table | a surface to write on (pen and notepad props) |
| sip_water | sink, fridge, coffee maker, tea kettle | something to drink from |
| gaze_out_window, people_watch | window | a window (the bare home keeps its windows) |

Need nothing, stay as they are: stretch, look_around, ponder_the_day, fidget_and_think, daydream (the folk's own body and thoughts), hum_tune, sing_softly, shake_a_leg (their own voice and body), check_phone, look_through_photos (the phone is carried; it has a prop). `welcome_snack`, `cafe_restroom` and `sleep_floor` are the bare-home fallbacks of task 32d and are meant to be offered when the object is missing.

Free fillers for a bare home (task 33c follow-up; they need no object, so an empty home is not left standing about: idle 1-9% in `tests/pov_activity_mix.gd`, family 101, empty home, nobody playing, 3 days, was 7% before 33c; `auto_furnish_test` at its original bounds, 12% / 7%): sit_on_floor (only when no seat or bed is near), stretch_on_wall, pace_and_think, count_coins (needs coins), floor_todo_list (Write + pen and notepad), listen_to_neighbours, imagine_furniture, practise_speech_air, shadow_box (Aim), do_sit_ups (Bend). They are 4-15 minutes long: a long filler leaves fewer gaps between actions than many short ones, which is what keeps the idle share low.

Paint is the easels' clip only (test `action_visuals_test`): `doodle` is Write with a pen and notepad, `build_snowfolk` is Bend (the `creative` tag no longer maps to Paint).

The folk of a self filler stays where they stand (no walk to the object); the gate only decides whether the filler exists. Not done: walking to the table before the puzzle.

## Not covered

- Objects changing (soil darkening, dirty dish, broken look, fridge door, burner glow, TV flicker, made bed, crops growing) is task 33.3 (`state33b`); the progress ring above the head is 33.4.
- Some clips are shared by several different actions where a dedicated animation would not read differently (Reach: grabbing from a fridge, a vending machine, a shelf, a lamp; Look: gazing, scanning, stargazing).
- Props are low-poly primitives (boxes, cylinders) in the hands, not modelled meshes; the sports and vacation interactions (skiing, surfing, hiking) have a pose but no equipment.
- Social interactions keep the Talk / Laugh / Wave cycles: talking is what they are.

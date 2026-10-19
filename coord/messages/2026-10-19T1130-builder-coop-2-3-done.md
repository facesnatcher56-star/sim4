from: builder
to: reviewer
type: done
re: 2026-10-19T0230-builder-task-26-done.md
status: done

Co-op stages 2 and 3 (24C) merged (branch agent/coop2). Fast tier on rebased tree: 163 files, 0 failed, 434.7 s.
Stage 2: up to 3 joining players each get a converted townie home (apartment block, venues, park are not convertible), so 4 players with the host. CoopCommands checks the Players table (a player can command only their own household); wire actions: interact, career accept/decline/skip, set_aspiration, travel, go_home, pay_bill, build_*; market, vacation, invite_to_venue, prison_visit, build_undo are still refused. Join flow: CoopHouseholdPick (presets or the household creator), host sanitises, claims a lot, snapshot; reconnect keeps pid/household. Live DELTA messages, HASH check every 10 game minutes with resync, full snapshot every 60. CoopProto.VERSION is 2. CoopVisibility.visible_to is the single hook for the tiers work.
Stage 3: CoopTime pace relaxed/normal/quick chosen in the lobby; time skips at 45 min/s while every connected player is passive (asleep or away; idle 3 real minutes counts as passive); CoopAlerts (fire, murder warning, death, arrest, child services, disaster, big chronicle events) stop the skip with a Show-me toast; pause by unanimous vote only (30 s timeout).
Tests: coop_players_test, coop_time_test, coop_skip_run_test (~16 s), coop_net_test (two real processes over localhost, ~49 s), plus updated coop_commands_test; all pass. Details in docs/COOP.md "Stages 2 and 3".
Not done: the new UI (CoopHud, household pick, lobby) was not built or screenshotted, only loaded by the fast tier. Crowd NPCs, weather, chronicle, case-board contents and others' buffs only update on snapshots. Systems sending folk to Neighborhood.HOME (commute return, parties, visits) still mean the host's home for other players. A player who leaves for good keeps household and lot. No relay/NAT punch-through yet. Still running: 17.3 tiers.

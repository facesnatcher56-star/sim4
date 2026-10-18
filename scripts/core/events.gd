extends Node
## Global signal bus. Sim emits, UI/systems listen. Names are the project contract.

signal folk_added(folk_id: int)
signal folk_removed(folk_id: int)
signal need_changed(folk_id: int, need: String, value: float)
signal mood_changed(folk_id: int, mood: String, intensity: int)
signal buff_added(folk_id: int, buff_id: String)
signal buff_removed(folk_id: int, buff_id: String)
signal interaction_started(folk_id: int, interaction_id: String, target_id: int)
signal interaction_finished(folk_id: int, interaction_id: String, success: bool)
signal queue_changed(folk_id: int)
signal thought(folk_id: int, text: String)          # balloon text
signal object_placed(object_id: int)
signal object_removed(object_id: int)
signal object_state_changed(object_id: int, state: String)
signal coins_changed(household_id: int, amount: int)
signal relationship_changed(a: int, b: int, track: String, value: float)
signal skill_changed(folk_id: int, skill: String, level: int)
signal notification(text: String, kind: String)
signal selection_changed(kind: String, id: int)      # kind: "folk" | "object" | "none"
signal game_event(event_name: String, payload: Dictionary)   # generic event for goals/careers

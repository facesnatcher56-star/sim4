extends Node3D
## Shared constants, state and animation-map lookups for FolkView (chain: folk_data > folk_look > folk_motion > folk_view).
## Visual for one Folk. Follows the logical `folk.tile` smoothly (walking along World paths), poses itself from the
## reserved object slot / folk.posture / World.folk_pose, and plays Blender clips (assets/models/folk_<stage>.glb)
## chosen through data/animation_map.json. Falls back to folk.glb, then to a capsule-person placeholder.
##
## Public surface kept stable for LotView: setup(folk_id), head_position(), show_name, pose (idle|walk|sit|lie|use|eat),
## signal pose_changed. New: clip (current Blender clip name), variant (body variant), show_mood.

signal pose_changed(folk_id: int, pose: String)

const BASE_SPEED := 2.4
const SPEED_MULT := [0.0, 1.0, 1.8, 3.0]
const MAP_PATH := "res://data/animation_map.json"
const PROPS_PATH := "res://data/animation_props.json"   # "props" (hand props) and "fx" (particles): merged into the map
const STAGES := ["baby", "toddler", "child", "teen", "adult", "elder"]
const FADE := 0.25
const DEFAULT_MAP := {
	"variant_files": {"fallback": "res://assets/models/folk.glb"},
	"variant_scale": {"adult": 1.0, "teen": 0.92, "child": 0.68, "elder": 0.96, "toddler": 0.5, "baby": 0.3},
	"oneshot": ["Faint", "Fall"],
	"locomotion": {"walk_clip": "Walk", "run_clip": "Run", "run_above_speed": 3.6, "walk_nominal_speed": 2.2,
		"run_nominal_speed": 4.2, "min_scale": 0.5, "max_scale": 2.4},
	"posture": {"stand": "Use_Stand", "sit": "Sit_Idle", "lie": "Sleep"},
	"idle": {"default": "Idle", "sit": "Sit_Idle", "lie": "Sleep", "mood": {}},
	"interactions": {}, "tags": {}, "tag_order": [], "fallbacks": {"*": "Idle"}, "variants": {},
	"mood_icon": {"min_intensity": 2, "colors": {}}, "social": {"stand_distance": 0.7},
}

static var _map: Dictionary = {}
static var _map_loaded: bool = false

var folk_id: int = -1
var pose: String = "idle"
var clip: String = ""                 # clip currently requested (after variant/fallback resolution)
var variant: String = "adult"
var facing_yaw: float = 0.0           # radians, model -Z forward
var show_name: bool = false:
	set(v):
		show_name = v
		if _name_label:
			_name_label.visible = v
var show_mood: bool = true

var _props: Dictionary = {}           # hand props built so far (FolkProps): name -> node, shown while its rule matches
var _prop_sig: int = 0
var _fx: Dictionary = {}              # particle effects built so far (FolkFx): name -> CPUParticles3D
var _fx_sig: int = 0
var _fx_last: Variant = null          # the interaction the effects last saw (a successful finish plays its burst)
var _waypoints: Array[Vector3] = []
var _last_tile: Vector2i = Vector2i(-999, -999)
var _last_level: int = 0
var _ybase: float = 0.0               # height of the floor / stair step under the feet (multi-floor); position.y adds the pose lift to it
var _level_y: float = 0.0             # height the folk should stand at when it has no waypoints left
var _target: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _target_pose: String = "idle"
var _elev: float = 0.0
var _anim: AnimationPlayer = null
var _rig: Node3D = null              # placeholder rig or glb root
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _is_placeholder: bool = true
var _name_label: Label3D = null
var _mood_icon: MeshInstance3D = null
var _mood_mat: StandardMaterial3D = null
var _mood_key: String = ""
var _phase: float = 0.0
var _res_cache: Variant = null
var _res_tick: int = 0
var _moving: bool = false
var _speed_now: float = 0.0           # metres/second actually travelled this frame
var _look_sig: int = 0
var _stage_now: String = ""
var _check_tick: int = 0
var _body_scale: float = 1.0          # variant scale * appearance height (drives sit lift)
# interaction tracking
var _cur_ref: Variant = null
var _inter_t0: float = 0.0
var _hold_clip: String = ""
var _hold_until: float = 0.0
var _urgent: bool = false             # the current walk is urgent (fire, emergency, late for work): the only time Run is played
var _sep_off: Vector2 = Vector2.ZERO        # idle spacing: view-only drift away from another idle folk on the same spot
var _avoid: Vector2 = Vector2.ZERO          # overlap nudge away from folk standing too close (view only)
var _partner_id: int = -1
var _partner_role: String = ""        # "actor" | "target" | ""
var _partner_inter: Variant = null
var _social_dir: Vector2 = Vector2.ZERO
var _social_len: float = 0.0                 # 0 = the usual stand distance; boxed-in partners (on a sofa) are met on the nearest open tile
var _social_pt: Vector2i = Vector2i(-999, -999)   # the partner tile the social side was chosen for
var _last_dir: Vector2 = Vector2(0, 1)


# ------------------------------------------------------------------ data

static func anim_map() -> Dictionary:
	if _map_loaded:
		return _map
	_map_loaded = true
	_map = DEFAULT_MAP.duplicate(true)
	if FileAccess.file_exists(MAP_PATH):
		var txt := FileAccess.get_file_as_string(MAP_PATH)
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			for k in (parsed as Dictionary):
				_map[k] = parsed[k]
	if FileAccess.file_exists(PROPS_PATH):
		var extra: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROPS_PATH))
		if extra is Dictionary:
			for k in (extra as Dictionary):
				_map[k] = extra[k]
	return _map


## Test hook: force a reload of the map next time.
static func reload_map() -> void:
	_map_loaded = false


static func stage_of(f) -> String:
	if f == null:
		return "adult"
	var s := str(f.age_stage)
	return s if s in STAGES else "adult"


static func variant_path(stage: String) -> String:
	var files: Dictionary = anim_map().get("variant_files", {})
	var p := str(files.get(stage, ""))
	if p != "" and ResourceLoader.exists(p):
		return p
	p = str(files.get("fallback", "res://assets/models/folk.glb"))
	if ResourceLoader.exists(p):
		return p
	return ""


## Loop modes + trailing duplicate-frame trim for the clips of an imported AnimationPlayer (idempotent, shared resources).
static func prepare_player(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	var oneshot: Array = anim_map().get("oneshot", [])
	for n in ap.get_animation_list():
		var a: Animation = ap.get_animation(n)
		if a.has_meta("folk_prepared"):
			continue
		a.set_meta("folk_prepared", true)
		if str(n) in oneshot:
			a.loop_mode = Animation.LOOP_NONE
		else:
			a.loop_mode = Animation.LOOP_LINEAR
			a.length = maxf(a.length - 1.0 / 24.0, 1.0 / 24.0)


static func color_of(hex: Variant, default: Color) -> Color:
	var s := str(hex)
	if s.begins_with("#") and (s.length() == 7 or s.length() == 9):
		return Color.html(s)
	return default

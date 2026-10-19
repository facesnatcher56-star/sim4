class_name CoopSession
extends Node
## The live co-op session: owns the ENet transport (Godot high-level multiplayer, SceneMultiplayer with raw packets, no RPCs)
## and wires it to CoopHost (role "host") or CoopClient (role "client"). One per game; `CoopSession.ensure(tree)` adds it
## under the root. Works without being in the tree too: call `pump(delta)` yourself (tests do).
## Packets: always CoopProto messages through SceneMultiplayer.send_bytes. Objects are never decoded.

signal changed                      # anything the lobby screen shows has changed
signal reconnecting(seconds_left: int)

const CONNECT_TIMEOUT_S := 8.0
const REJOIN_WINDOW_S := 60.0
const RETRY_EVERY_S := 2.0
const CHANNELS := 4

static var instance: CoopSession = null

var role: String = "none"          # none | host | client
var host: CoopHost = null
var client: CoopClient = null
var mp: SceneMultiplayer = null
var peer: ENetMultiplayerPeer = null
var time: CoopTime = null          # host only
var alerts: CoopAlerts = null
var _time_next: float = 0.0
var _active_next: float = 0.0
var port: int = 0
var address_ip: String = ""
var error_text: String = ""
var _t: float = 0.0
var _connecting_since: float = -1.0
var _lost_since: float = -1.0
var _next_retry: float = 0.0

static func ensure(tree: SceneTree) -> CoopSession:
	if instance == null or not is_instance_valid(instance):
		instance = CoopSession.new()
		instance.name = "CoopSession"
		tree.root.add_child(instance)
	return instance

func _process(delta: float) -> void:
	pump(delta)

## Idle detection (stage 3): any key or mouse use counts. The host notes its own; a client tells the host at most every 5 seconds.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if role == "host" and time != null:
		time.note_input(Players.LOCAL, _t)
	elif role == "client" and client != null and client.state == "synced" and _t >= _active_next:
		_active_next = _t + 5.0
		client.send_active(1)

func is_active() -> bool:
	return role != "none"

# ------------------------------------------------------------------ host
## Open a lobby. Returns "" on success or a plain-language reason.
func start_host(p_port: int, p_name: String, max_players: int = CoopProto.MAX_PEERS, p_pace: String = "normal") -> String:
	stop()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(p_port, 8, CHANNELS)
	if err != OK:
		peer = null
		return "Could not open the lobby on port %d (%s). Is another game already using it? Try another port." % [p_port, error_string(err)]
	_make_mp()
	role = "host"
	port = p_port
	host = CoopHost.new()
	host.host_name = p_name.strip_edges().left(24) if p_name.strip_edges() != "" else "Host"
	host.max_players = clampi(max_players, 2, CoopProto.MAX_PEERS)
	host.send_fn = func(id: int, b: PackedByteArray, ch: int): _send_to(id, b, ch)
	host.drop_fn = func(id: int): if peer != null: peer.disconnect_peer(id, false)
	host.lobby_changed.connect(func(): changed.emit())
	_start_time(p_pace)
	error_text = ""
	changed.emit()
	return ""

# ------------------------------------------------------------------ client
## Connect to a host. `text` is a code, "ip" or "ip:port". Returns "" or a plain-language reason (nothing is started then).
func join(text: String, p_name: String) -> String:
	var a := CoopAddress.parse(text)
	if not a["ok"]:
		return str(a["err"])
	stop()
	role = "client"
	address_ip = str(a["ip"])
	port = int(a["port"])
	client = CoopClient.new()
	client.player_name = p_name.strip_edges().left(24) if p_name.strip_edges() != "" else "Player"
	client.send_fn = func(b: PackedByteArray, ch: int): _send_to(1, b, ch)
	client.install_remote()
	client.time_updated.connect(func(_s): changed.emit())
	CoopTime.active = true               # a client never advances or pauses the clock: it only shows what the host sends
	Clock.coop_rate = 0.0
	client.state_changed.connect(func(_s, _t2): changed.emit())
	client.lobby_updated.connect(func(_l): changed.emit())
	client.progress.connect(func(_f): changed.emit())
	_connect_client(false)
	return ""

func _connect_client(retry: bool) -> void:
	if peer != null:
		peer.close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address_ip, port, CHANNELS)
	if err != OK:
		peer = null
		client.mark_failed("Could not start connecting to %s:%d (%s)." % [address_ip, port, error_string(err)])
		return
	_make_mp()
	_connecting_since = _t
	if not retry:
		client.mark_connecting("Connecting to %s:%d..." % [address_ip, port])

## Stage 3: the host owns the clock. One fixed pace, auto-skip, alerts, pause votes (CoopTime); live deltas and alerts are wired here.
func _start_time(p_pace: String) -> void:
	time = CoopTime.new()
	time.set_pace(p_pace)
	time.players_fn = host.connected_pids
	time.alert_fn = host.send_alert
	time.changed.connect(host.broadcast_time)
	host.time = time
	time.note_input(Players.LOCAL, _t)
	time.start()
	alerts = CoopAlerts.new(time)
	alerts.connect_events()
	host.live.connect_events()

func _stop_time() -> void:
	if alerts != null:
		alerts.disconnect_events()
	if host != null:
		host.live.disconnect_events()
	if time != null:
		time.stop()
	time = null
	alerts = null
	if role == "client" or client != null:
		Commands.remote = Callable()
	CoopTime.active = false
	Clock.coop_rate = -1.0

func stop() -> void:
	_stop_time()
	if role == "host" and host != null:
		host.close()
	if client != null and role == "client":
		client.leave()
	if peer != null:
		if peer.host != null:
			peer.host.flush()
		peer.close()
	peer = null
	mp = null
	role = "none"
	host = null
	client = null
	_connecting_since = -1.0
	_lost_since = -1.0
	changed.emit()

func status_text() -> String:
	if role == "client" and client != null:
		return client.status
	if role == "host":
		return "Lobby open on port %d." % port
	return ""

# ------------------------------------------------------------------ transport
func _make_mp() -> void:
	mp = SceneMultiplayer.new()
	mp.root_path = ^"/root"           # required by SceneMultiplayer even though we use raw packets only
	mp.allow_object_decoding = false
	mp.server_relay = false
	mp.multiplayer_peer = peer
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.peer_packet.connect(_on_packet)
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(_on_connect_failed)
	mp.server_disconnected.connect(_on_server_disconnected)

func _send_to(id: int, b: PackedByteArray, channel: int) -> void:
	if mp != null and peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		mp.send_bytes(b, id, MultiplayerPeer.TRANSFER_MODE_RELIABLE, channel)

func pump(delta: float) -> void:
	_t += delta
	if mp != null:
		mp.poll()
	if role == "host" and host != null:
		host.tick(_t)
		if time != null and _t >= _time_next:
			_time_next = _t + 0.25
			time.update(_t, SimEnv.now_min())
	elif role == "client" and client != null:
		client.tick(_t)
		_client_upkeep()

func _client_upkeep() -> void:
	if client.state == "connecting" and _connecting_since >= 0.0 and _t - _connecting_since > CONNECT_TIMEOUT_S:
		_connection_unreachable()
	if client.state == "lost":
		if _lost_since < 0.0:
			_lost_since = _t
			_next_retry = _t
		var left := REJOIN_WINDOW_S - (_t - _lost_since)
		if left <= 0.0 or client.token == "":
			client.mark_failed("Could not get back into the game. The host may have closed it.")
			_lost_since = -1.0
		else:
			reconnecting.emit(int(left))
			if _t >= _next_retry:
				_next_retry = _t + RETRY_EVERY_S
				client.mark_lost("Lost contact with the host. Trying to rejoin (%d s left)..." % int(left))
				_connect_client(true)
	elif client.state in ["synced", "loading"]:
		_lost_since = -1.0

func _connection_unreachable() -> void:
	_connecting_since = -1.0
	if _lost_since >= 0.0:
		return                      # a rejoin attempt: upkeep keeps trying until the window is over
	client.mark_failed("Can't reach the host at %s:%d. Check the code or address, that the host has opened the lobby, and (over the internet) that the host's router forwards UDP port %d." % [address_ip, port, port])

func _on_peer_connected(id: int) -> void:
	if role == "host" and host != null:
		host.peer_connected(id, _t)
	elif role == "client" and client != null and id == 1:
		pass

func _on_peer_disconnected(id: int) -> void:
	if role == "host" and host != null:
		host.peer_disconnected(id, _t)

func _on_connected() -> void:
	_connecting_since = -1.0
	if client != null:
		client.hello(_t)

func _on_connect_failed() -> void:
	if client != null:
		_connection_unreachable()

func _on_server_disconnected() -> void:
	if client != null and client.state not in ["refused", "ended", "failed", "idle"]:
		client.mark_lost("Lost contact with the host. Trying to rejoin...")

func _on_packet(id: int, bytes: PackedByteArray) -> void:
	if role == "host" and host != null:
		host.on_packet(id, bytes, _t)
	elif role == "client" and client != null and id == 1:
		client.on_packet(bytes, _t)

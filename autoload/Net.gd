extends Node
## Player-hosted multiplayer over WebSockets - no dedicated server needed.
## A desktop player hosts (listens on PORT); desktop AND web players join by
## IP. Positions are exchanged in absolute world coordinates at 12 Hz and
## interpolated on proxies, which carry collision shapes so mid-airs between
## players are real. The shared WORLD_SEED guarantees identical terrain,
## airports and weather for everyone.
##
## Note for web players: browsers only allow ws:// connections from pages
## served over http (not https). The downloadable desktop build always works.

const PORT := 9080
const SEND_HZ := 12.0

var peer: WebSocketMultiplayerPeer = null
var players: Dictionary = {}       # peer_id -> {name, aircraft_id}
var proxies: Dictionary = {}       # peer_id -> {craft, from, to, t0, t1}
var _send_accum := 0.0
var _time_sync_accum := 0.0
var _world: WorldRoot = null

func is_active() -> bool:
	return peer != null

## Start hosting. Desktop only (browsers cannot listen). Returns error text or "".
func host() -> String:
	if OS.has_feature("web"):
		return "Web builds cannot host - use the desktop app to host"
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		peer = null
		return "Could not open port %d (error %d)" % [PORT, err]
	multiplayer.multiplayer_peer = peer
	_connect_once(multiplayer.peer_connected, _on_peer_connected)
	_connect_once(multiplayer.peer_disconnected, _on_peer_disconnected)
	players[1] = {"name": Game.player_name(), "aircraft_id": Game.selected_aircraft_id}
	EventBus.net_status.emit("Hosting on port %d" % PORT)
	return ""

## Join a host by address. Returns error text or "".
func join(address: String) -> String:
	peer = WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d" % [address.strip_edges(), PORT]
	var err := peer.create_client(url)
	if err != OK:
		peer = null
		return "Could not connect to %s (error %d)" % [url, err]
	multiplayer.multiplayer_peer = peer
	_connect_once(multiplayer.connected_to_server, _on_connected)
	_connect_once(multiplayer.connection_failed, _on_conn_failed)
	_connect_once(multiplayer.server_disconnected, _on_server_gone)
	_connect_once(multiplayer.peer_connected, _on_peer_connected)
	_connect_once(multiplayer.peer_disconnected, _on_peer_disconnected)
	EventBus.net_status.emit("Connecting to %s..." % address)
	return ""

func _connect_once(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)

func leave() -> void:
	for id in proxies.keys():
		_free_proxy(id)
	proxies.clear()
	players.clear()
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_world = null

func local_addresses() -> Array:
	var out: Array = []
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			out.append(addr)
	return out

func world_ready(w: WorldRoot) -> void:
	_world = w
	if is_active():
		_announce.rpc(Game.player_name(), Game.selected_aircraft_id)
		if multiplayer.is_server():
			_sync_time.rpc(w.hour)

# ------------------------------------------------------------------ signals
func _on_connected() -> void:
	EventBus.net_status.emit("Connected! Loading world...")
	if Game.mode == Game.Mode.CLIENT and Game.world == null:
		Game.start_flight(Game.selected_aircraft_id, Game.selected_airport_id, Game.Mode.CLIENT)

func _on_conn_failed() -> void:
	EventBus.net_status.emit("Connection failed")
	leave()

func _on_server_gone() -> void:
	EventBus.toast("Host disconnected - returning to solo flight", "warn")
	EventBus.net_status.emit("Host disconnected")
	leave()
	if Game.mode == Game.Mode.CLIENT:
		Game.mode = Game.Mode.SOLO

func _on_peer_connected(id: int) -> void:
	if _world and is_active():
		_announce.rpc_id(id, Game.player_name(), Game.selected_aircraft_id)
		if multiplayer.is_server():
			_sync_time.rpc_id(id, _world.hour)

func _on_peer_disconnected(id: int) -> void:
	var pname: String = players.get(id, {}).get("name", "Player")
	players.erase(id)
	_free_proxy(id)
	EventBus.net_player_left.emit(id, pname)
	EventBus.toast("%s left the session" % pname, "info")

# ------------------------------------------------------------------ RPCs
@rpc("any_peer", "call_remote", "reliable")
func _announce(pname: String, aircraft_id: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var is_new := not players.has(id)
	players[id] = {"name": pname, "aircraft_id": aircraft_id}
	if is_new:
		EventBus.net_player_joined.emit(id, pname)
		EventBus.toast("%s joined the session" % pname, "good")
		# Introduce ourselves back
		if _world:
			_announce.rpc_id(id, Game.player_name(), Game.selected_aircraft_id)

@rpc("authority", "call_remote", "reliable")
func _sync_time(hour: float) -> void:
	if _world:
		_world.hour = hour

@rpc("any_peer", "call_remote", "unreliable")
func _state(s: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if _world == null:
		return
	if not proxies.has(id):
		_spawn_proxy(id, s)
	var pr: Dictionary = proxies[id]
	pr.from = pr.to
	pr.to = s
	pr.t0 = pr.t1
	pr.t1 = Time.get_ticks_msec() / 1000.0

@rpc("any_peer", "call_remote", "reliable")
func _chat(text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var pname: String = players.get(id, {}).get("name", "Player %d" % id)
	EventBus.chat_received.emit(pname, text)

func send_chat(text: String) -> void:
	if is_active():
		_chat.rpc(text)
	EventBus.chat_received.emit(Game.player_name() + " (you)", text)

# ------------------------------------------------------------------ proxies
func _spawn_proxy(id: int, s: Dictionary) -> void:
	var aircraft_id: String = s.get("ac", players.get(id, {}).get("aircraft_id", "cessna172"))
	var cfg := AircraftDB.config(aircraft_id)
	var craft := Aircraft.new()
	craft.name = "Remote_%d" % id
	craft.world_ref = _world
	craft.add_to_group("aircraft")
	_world.add_child(craft)
	craft.setup(cfg, false, true)
	var tag := Label3D.new()
	tag.text = s.get("cs", players.get(id, {}).get("name", "Pilot"))
	tag.font_size = 64
	tag.pixel_size = 0.05
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.6, 0.9, 1.0)
	tag.position.y = cfg.wing_span * 0.35 + 4.0
	tag.no_depth_test = true
	craft.add_child(tag)
	proxies[id] = {"craft": craft, "from": s, "to": s, "t0": 0.0, "t1": 0.0}

func _free_proxy(id: int) -> void:
	if proxies.has(id):
		var c = proxies[id].craft
		if is_instance_valid(c):
			c.queue_free()
		proxies.erase(id)

func _dict_to_v3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO

func _process(dt: float) -> void:
	if not is_active() or _world == null:
		return
	var p := Game.player_aircraft as Aircraft
	# Host rebroadcasts world time periodically so day/night can't drift
	if multiplayer.is_server():
		_time_sync_accum += dt
		if _time_sync_accum > 30.0:
			_time_sync_accum = 0.0
			_sync_time.rpc(_world.hour)
	# Broadcast our state
	_send_accum += dt
	if p and _send_accum >= 1.0 / SEND_HZ:
		_send_accum = 0.0
		var ap := p.abs_position()
		var q := p.global_transform.basis.get_rotation_quaternion()
		_state.rpc({
			"ac": p.cfg.id, "cs": Game.player_name(),
			"p": [ap.x, ap.y, ap.z], "q": [q.x, q.y, q.z, q.w],
			"v": [p.linear_velocity.x, p.linear_velocity.y, p.linear_velocity.z],
			"el": p.ctl_elevator, "ai": p.ctl_aileron, "ru": p.ctl_rudder,
			"fl": p.flap_frac, "sl": p.slat_frac, "sp": p.spoiler_frac,
			"gr": p.gear.gear_frac, "n1": p.propulsion.average_n1(),
			"ab": p.propulsion.afterburner, "rr": p.propulsion.rotor_rpm,
		})
	# Interpolate proxies
	var now := Time.get_ticks_msec() / 1000.0
	var origin: Vector3 = _world.origin_offset()
	for id in proxies.keys():
		var pr: Dictionary = proxies[id]
		var craft := pr.craft as Aircraft
		if not is_instance_valid(craft):
			continue
		var span: float = maxf(pr.t1 - pr.t0, 0.001)
		# Render one send-interval behind: w sweeps 0->1 between the two
		# buffered samples as wall time passes t1, with mild extrapolation.
		var w_lerp: float = clampf((now - pr.t1) / span, 0.0, 1.5)
		var p0 := _dict_to_v3(pr.from.get("p"))
		var p1 := _dict_to_v3(pr.to.get("p"))
		craft.global_position = p0.lerp(p1, w_lerp) - origin
		var qa: Array = pr.from.get("q", [0, 0, 0, 1])
		var qb: Array = pr.to.get("q", [0, 0, 0, 1])
		var quat_a := Quaternion(qa[0], qa[1], qa[2], qa[3]).normalized()
		var quat_b := Quaternion(qb[0], qb[1], qb[2], qb[3]).normalized()
		craft.quaternion = quat_a.slerp(quat_b, minf(w_lerp, 1.0))
		# Drive visual animation state
		var s: Dictionary = pr.to
		craft.ctl_elevator = s.get("el", 0.0)
		craft.ctl_aileron = s.get("ai", 0.0)
		craft.ctl_rudder = s.get("ru", 0.0)
		craft.flap_frac = s.get("fl", 0.0)
		craft.slat_frac = s.get("sl", 0.0)
		craft.spoiler_frac = s.get("sp", 0.0)
		craft.gear.gear_frac = s.get("gr", 1.0)
		craft.propulsion.rotor_rpm = s.get("rr", 0.0)
		craft.engines_on = s.get("n1", 0.0) > 0.05

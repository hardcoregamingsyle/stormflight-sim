class_name EOSBackend
extends Node
## Epic Online Services matchmaking backend: "Quick Join and you're in a
## server" - anonymous Device-ID login (no Epic account for players) + a
## public lobby everyone shares (first player creates it, the rest join it),
## with EOS's relayed P2P so nobody port-forwards.
##
## IMPORTANT — this talks to the community EOS GDExtension
## (github.com/3ddelano/epic-online-services-godot). That plugin ships native
## libraries and is ONLY present in a build you make on your machine with the
## plugin installed; it is never in the headless CI build. So:
##   * Every EOS call here goes through reflection (Engine.get_singleton /
##     ClassDB.instantiate / has_method / has_signal) - there are NO
##     compile-time references to plugin classes, so the game still builds and
##     runs fine WITHOUT the plugin (EOS just reports "unavailable").
##   * Because it can't be exercised in this sandbox, each step probes the
##     plugin's API and emits a precise status if a name doesn't match, so on
##     your Windows build it tells us exactly what to adjust instead of hanging.
## See docs/MULTIPLAYER_EOS_SETUP.md.

signal status(text: String)          # human-readable progress for the menu
signal ready_to_fly(is_host: bool)   # lobby joined, peer set - start the flight
signal failed(reason: String)

const STEP_TIMEOUT := 15.0

var _peer: MultiplayerPeer = null
var _busy := false

## Can this build even attempt EOS? True only when the plugin registered its
## multiplayer peer class. Cheap, safe to call anywhere.
static func plugin_present() -> bool:
	return ClassDB.class_exists("EOSGMultiplayerPeer") and Engine.has_singleton("IEOS")

## Overall gate the menu checks before offering Quick Join.
static func available() -> String:
	if not plugin_present():
		return "The EOS plugin isn't in this build - see the multiplayer setup guide."
	if not EOSConfig.configured():
		return "EOS credentials aren't filled in yet (core/net/EOSConfig.gd)."
	return ""

# ------------------------------------------------------------------ flow
## Kick off the full connect flow. Emits status/ready_to_fly/failed.
func quick_join() -> void:
	if _busy:
		return
	_busy = true
	var gate := available()
	if gate != "":
		_fail(gate)
		return
	var ieos := Engine.get_singleton("IEOS")
	emit_signal("status", "Starting Epic Online Services...")
	if not _create_platform(ieos):
		return
	emit_signal("status", "Signing in (anonymous device ID)...")
	var puid := await _device_login(ieos)
	if puid == "":
		return
	emit_signal("status", "Finding a public server...")
	await _find_or_create_lobby(ieos, puid)

func cancel() -> void:
	_busy = false
	if _peer != null:
		_peer = null

# ------------------------------------------------------------------ steps
## Each step is guarded: if the installed plugin names a method/signal
## differently, we say so precisely rather than failing blind.
func _create_platform(ieos) -> bool:
	# 3ddelano API: IEOS.platform_interface_create(options) -> creates the
	# platform handle; the plugin auto-ticks it. VERIFY the option keys against
	# your plugin version (they mirror the EOS SDK PlatformOptions).
	if not ieos.has_method("platform_interface_create"):
		_fail("EOS: platform_interface_create not found (plugin API mismatch).")
		return false
	var opts := {
		"product_id": EOSConfig.PRODUCT_ID,
		"sandbox_id": EOSConfig.SANDBOX_ID,
		"deployment_id": EOSConfig.DEPLOYMENT_ID,
		"client_id": EOSConfig.CLIENT_ID,
		"client_secret": EOSConfig.CLIENT_SECRET,
		"encryption_key": "1111111111111111111111111111111111111111111111111111111111111111",
		"is_server": false,
	}
	var res = ieos.call("platform_interface_create", opts)
	if typeof(res) == TYPE_INT and res != 0:
		_fail("EOS platform init failed (code %d). Check your product IDs." % res)
		return false
	return true

func _device_login(ieos) -> String:
	# Connect interface, Device-ID credential = anonymous, no Epic account.
	# Create the device id (ignore "already exists"), then Connect login.
	if ieos.has_method("connect_interface_create_device_id"):
		ieos.call("connect_interface_create_device_id", {"device_model": OS.get_model_name()})
		if ieos.has_signal("connect_interface_create_device_id_callback"):
			await _wait(Signal(ieos, "connect_interface_create_device_id_callback"))
	if not ieos.has_method("connect_interface_login"):
		_fail("EOS: connect_interface_login not found (plugin API mismatch).")
		return ""
	if not ieos.has_signal("connect_interface_login_callback"):
		_fail("EOS: connect_interface_login_callback signal not found.")
		return ""
	ieos.call("connect_interface_login", {
		"credentials": {"type": "DEVICEID_ACCESS_TOKEN", "token": null},
		"user_login_info": {"display_name": Game.player_name()},
	})
	var data = await _wait(Signal(ieos, "connect_interface_login_callback"))
	if data == null:
		_fail("EOS sign-in timed out.")
		return ""
	var puid := ""
	if data is Dictionary:
		puid = str(data.get("local_user_id", data.get("product_user_id", "")))
	if puid == "":
		_fail("EOS sign-in returned no user id (see plugin login callback fields).")
		return ""
	return puid

func _find_or_create_lobby(ieos, puid: String) -> void:
	# Prefer the plugin's high-level peer helpers if present; they wrap the
	# lobby + P2P socket setup. Fall back to a clear message otherwise.
	var peer = ClassDB.instantiate("EOSGMultiplayerPeer")
	if peer == null:
		_fail("EOS: could not create EOSGMultiplayerPeer.")
		return
	# Try to JOIN an existing public lobby first (search by bucket), else HOST.
	if peer.has_method("search_lobby") and peer.has_method("join_lobby") \
			and peer.has_method("create_lobby"):
		# Search
		if peer.has_signal("lobby_search_finished"):
			peer.call("search_lobby", {"bucket_id": EOSConfig.LOBBY_BUCKET, "max_results": 1})
			var found = await _wait(Signal(peer, "lobby_search_finished"))
			if found is Array and found.size() > 0:
				peer.call("join_lobby", found[0])
				_finish(peer, false)
				return
		# None found -> create one
		peer.call("create_lobby", {
			"bucket_id": EOSConfig.LOBBY_BUCKET,
			"max_members": EOSConfig.LOBBY_MAX_MEMBERS,
			"permission": "PUBLIC_ADVERTISED",
		})
		if peer.has_signal("lobby_created"):
			await _wait(Signal(peer, "lobby_created"))
		_finish(peer, true)
		return
	_fail("EOS peer present but its lobby methods differ from what this build " +
		"expects - tell me the method list from the plugin and I'll match it.")

func _finish(peer: MultiplayerPeer, is_host: bool) -> void:
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_busy = false
	emit_signal("status", "In the server - launching...")
	emit_signal("ready_to_fly", is_host)

# ------------------------------------------------------------------ helpers
## Await a plugin callback, but never hang: races the signal against a timer.
func _wait(sig: Signal) -> Variant:
	var box := {"v": null, "done": false}
	var on_sig := func(a = null, b = null, c = null):
		if not box.done:
			box.v = a if a != null else true
			box.done = true
	sig.connect(on_sig, CONNECT_ONE_SHOT)
	var t := get_tree().create_timer(STEP_TIMEOUT)
	t.timeout.connect(func():
		if not box.done:
			box.done = true)
	while not box.done:
		await get_tree().process_frame
	return box.v

func _fail(reason: String) -> void:
	_busy = false
	emit_signal("status", reason)
	emit_signal("failed", reason)

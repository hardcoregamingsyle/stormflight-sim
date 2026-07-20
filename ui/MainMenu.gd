extends CanvasLayer
## Main menu: home, fly (aircraft + airport select), hangar/shop,
## multiplayer lobby, settings, help. Built entirely in code.

var page_root: Control
var _fly_aircraft := ""
var _mp_status: Label = null

func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Decorative horizon gradient
	var grad := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.colors = PackedColorArray([Color(0.09, 0.16, 0.3), Color(0.04, 0.06, 0.1)])
	g.fill_from = Vector2(0.5, 0.0)
	g.fill_to = Vector2(0.5, 1.0)
	grad.texture = g
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grad)
	page_root = Control.new()
	page_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(page_root)
	EventBus.net_status.connect(_on_net_status)
	show_home()

func _clear() -> void:
	for c in page_root.get_children():
		c.queue_free()

func _scroll_page(title: String, back_cb: Callable) -> VBoxContainer:
	_clear()
	var outer := UIKit.vbox(10)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 60
	outer.offset_right = -60
	outer.offset_top = 30
	outer.offset_bottom = -30
	page_root.add_child(outer)
	var top := UIKit.hbox(16)
	top.add_child(UIKit.btn("< Back", back_cb, 16))
	var t := UIKit.label(title, 34, UIKit.ACCENT)
	top.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UIKit.label("%d SkyCoins" % SaveGame.coins(), 24, UIKit.GOOD))
	outer.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var content := UIKit.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return content

# ================================================================= HOME
func show_home() -> void:
	_clear()
	var box := UIKit.vbox(14)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	page_root.add_child(box)

	var title := UIKit.label("STORMFIGHTER", 64, UIKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UIKit.label("F L I G H T   S I M", 22, UIKit.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(UIKit.spacer(8))

	var coins := UIKit.label("%d SkyCoins" % SaveGame.coins(), 22, UIKit.GOOD)
	coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(coins)
	box.add_child(UIKit.spacer(6))

	for entry in [["FLY", show_fly], ["MULTIPLAYER", show_multiplayer], ["HANGAR & SHOP", show_hangar], ["SETTINGS", show_settings], ["HOW TO FLY", show_help]]:
		var b := UIKit.btn(entry[0], entry[1], 22)
		b.custom_minimum_size = Vector2(340, 0)
		box.add_child(b)
	if not Quality.is_web:
		var q := UIKit.btn("QUIT", func(): get_tree().quit(), 22)
		q.custom_minimum_size = Vector2(340, 0)
		box.add_child(q)

	box.add_child(UIKit.spacer(10))
	var stats := UIKit.label("Flight time %s   |   Landings %d   |   Jobs %d   |   Distance %d km" % [
		_fmt_time(SaveGame.stat("flight_time_s")), SaveGame.stat("landings"), SaveGame.stat("jobs_done"), int(SaveGame.stat("distance_km"))], 14, UIKit.DIM)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stats)
	var ver := UIKit.label("v1.2.0 - Meridian Isles  |  %s build" % ("Web" if Quality.is_web else "Desktop"), 12, UIKit.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ver)

func _fmt_time(s: float) -> String:
	var h := int(s / 3600.0)
	var m := int(fmod(s, 3600.0) / 60.0)
	return "%dh %02dm" % [h, m]

# ================================================================= FLY
func show_fly() -> void:
	var content := _scroll_page("Select Aircraft", show_home)
	content.add_child(UIKit.label("Choose from your hangar. Buy more aircraft in the shop.", 15, UIKit.DIM))
	for id in AircraftDB.ids():
		if not SaveGame.owns(id):
			continue
		content.add_child(_aircraft_card(id, true))

func _aircraft_card(id: String, for_flight: bool) -> PanelContainer:
	var spec := AircraftDB.spec(id)
	var cfg := AircraftDB.config(id)
	var card := UIKit.panel(UIKit.BG_LIGHT)
	var h := UIKit.hbox(18)
	card.add_child(h)
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_row := UIKit.hbox(10)
	name_row.add_child(UIKit.label(spec.display_name, 22, UIKit.TEXT))
	name_row.add_child(UIKit.label("[%s]" % cfg.role.to_upper(), 14, UIKit.ACCENT))
	v.add_child(name_row)
	var desc := UIKit.label(spec.ui.description, 13, UIKit.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	var stats_l := UIKit.label("Cruise %d kts  |  Range %d km  |  Ceiling %d ft  |  MTOW %s kg  |  %s" % [
		int(spec.ui.cruise_speed_kts), int(spec.ui.range_km), int(spec.ui.ceiling_ft), str(int(cfg.mtow)),
		"%d engines" % cfg.engine_count if cfg.engine_count > 1 else "single engine"], 13, UIKit.DIM)
	stats_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(stats_l)
	# Condition
	var cond := SaveGame.get_condition(id)
	if SaveGame.owns(id) and not cond.is_empty():
		var worst := 1.0
		for k in cond.get("health", {}).keys():
			worst = minf(worst, float(cond.health[k]))
		var fuel := float(cond.get("fuel_frac", 0.75))
		var crow := UIKit.hbox(8)
		crow.add_child(UIKit.label("Condition", 12, UIKit.DIM))
		crow.add_child(UIKit.bar(worst, UIKit.GOOD if worst > 0.7 else (UIKit.WARN if worst > 0.4 else UIKit.BAD)))
		crow.add_child(UIKit.label("Fuel", 12, UIKit.DIM))
		crow.add_child(UIKit.bar(fuel, UIKit.ACCENT))
		v.add_child(crow)

	var right := UIKit.vbox(6)
	h.add_child(right)
	if for_flight:
		right.add_child(UIKit.btn("SELECT >", func(): _select_aircraft(id), 18))
	else:
		if SaveGame.owns(id):
			right.add_child(UIKit.label("OWNED", 16, UIKit.GOOD))
			var rc := Economy.repair_cost(id)
			if rc > 0:
				right.add_child(UIKit.btn("Repair (%d SC)" % rc, func():
					Economy.repair_aircraft(id)
					show_hangar(), 13))
			var fc := Economy.refuel_cost(id)
			if fc > 0:
				right.add_child(UIKit.btn("Refuel (%d SC)" % fc, func():
					Economy.refuel_aircraft(id)
					show_hangar(), 13))
		else:
			right.add_child(UIKit.label("%d SC" % spec.price, 18, UIKit.ACCENT))
			right.add_child(UIKit.btn("BUY", func():
				if Economy.purchase_aircraft(id):
					show_hangar(), 16))
	return card

func _select_aircraft(id: String) -> void:
	_fly_aircraft = id
	var content := _scroll_page("Select Departure Airport", show_fly)
	content.add_child(UIKit.label("You will spawn at a random gate. Distances are real-scale - pick a hop that suits your aircraft.", 15, UIKit.DIM))
	for aid in AirportsDB.ids():
		var a := AirportsDB.get_airport(aid)
		var card := UIKit.panel(UIKit.BG_LIGHT)
		var h := UIKit.hbox(18)
		card.add_child(h)
		var v := UIKit.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var top := UIKit.hbox(10)
		top.add_child(UIKit.label("%s  (%s)" % [a.name, a.icao], 20, UIKit.TEXT))
		top.add_child(UIKit.label(String(a.size).to_upper(), 13, UIKit.ACCENT))
		v.add_child(top)
		var adesc := UIKit.label(a.desc, 13, UIKit.DIM)
		adesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		adesc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(adesc)
		var rw_txt := ""
		for rw in a.runways:
			rw_txt += "RWY %s (%dm)  " % [rw.id, int(rw.length)]
		var rw_l := UIKit.label("%s|  Elev %d ft  |  %d gates" % [rw_txt, int(a.elevation_m * 3.28), a.gates], 13, UIKit.DIM)
		rw_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rw_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(rw_l)
		h.add_child(UIKit.btn("START HERE >", func(): _start(aid), 16))
		content.add_child(card)

func _start(airport_id: String) -> void:
	Game.start_flight(_fly_aircraft, airport_id, Game.Mode.SOLO)

# ================================================================= HANGAR
func show_hangar() -> void:
	var content := _scroll_page("Hangar & Shop", show_home)
	content.add_child(UIKit.label("Earn SkyCoins by flying jobs, following ATC procedures and landing like a pro.", 15, UIKit.DIM))
	for id in AircraftDB.ids():
		content.add_child(_aircraft_card(id, false))

# ================================================================= MULTIPLAYER
func show_multiplayer() -> void:
	var content := _scroll_page("Multiplayer (Player-Hosted P2P)", show_home)
	content.add_child(UIKit.label("One player hosts, everyone else joins their IP. Same world, same physics, real collisions.", 15, UIKit.DIM))

	var name_row := UIKit.hbox(10)
	name_row.add_child(UIKit.label("Pilot name:", 16))
	var name_edit := LineEdit.new()
	name_edit.text = String(SaveGame.setting("player_name", "Pilot"))
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.text_changed.connect(func(t): SaveGame.set_setting("player_name", t))
	name_row.add_child(name_edit)
	content.add_child(name_row)

	var craft_row := UIKit.hbox(10)
	craft_row.add_child(UIKit.label("Aircraft:", 16))
	var craft_opt := OptionButton.new()
	for id in AircraftDB.ids():
		if SaveGame.owns(id):
			craft_opt.add_item(AircraftDB.spec(id).display_name)
			craft_opt.set_item_metadata(craft_opt.item_count - 1, id)
	craft_opt.selected = 0
	craft_row.add_child(craft_opt)
	craft_row.add_child(UIKit.label("Airport:", 16))
	var ap_opt := OptionButton.new()
	for aid in AirportsDB.ids():
		ap_opt.add_item(AirportsDB.get_airport(aid).name)
		ap_opt.set_item_metadata(ap_opt.item_count - 1, aid)
	ap_opt.selected = 0
	craft_row.add_child(ap_opt)
	content.add_child(craft_row)

	var pick := func():
		Game.selected_aircraft_id = craft_opt.get_item_metadata(craft_opt.selected)
		Game.selected_airport_id = ap_opt.get_item_metadata(ap_opt.selected)

	content.add_child(UIKit.spacer(6))
	_mp_status = UIKit.label("", 15, UIKit.WARN)
	content.add_child(_mp_status)

	# Host section
	var host_panel := UIKit.panel(UIKit.BG_LIGHT)
	var hv := UIKit.vbox(8)
	host_panel.add_child(hv)
	hv.add_child(UIKit.label("HOST A SESSION", 18, UIKit.ACCENT))
	if Quality.is_web:
		hv.add_child(UIKit.label("Hosting requires the desktop app (browsers cannot open ports). You can still JOIN a desktop host below.", 14, UIKit.DIM))
	else:
		hv.add_child(UIKit.label("Friends on your network join your local IP. For internet play, forward TCP port 9080 and share your public IP.", 14, UIKit.DIM))
		hv.add_child(UIKit.label("Your local IPs: %s" % ", ".join(Net.local_addresses()), 14, UIKit.TEXT))
		hv.add_child(UIKit.btn("HOST & START FLYING", func():
			pick.call()
			var err := Net.host()
			if err != "":
				_mp_status.text = err
			else:
				Game.start_flight(Game.selected_aircraft_id, Game.selected_airport_id, Game.Mode.HOST), 18))
	content.add_child(host_panel)

	# Join section
	var join_panel := UIKit.panel(UIKit.BG_LIGHT)
	var jv := UIKit.vbox(8)
	join_panel.add_child(jv)
	jv.add_child(UIKit.label("JOIN A SESSION", 18, UIKit.ACCENT))
	var jrow := UIKit.hbox(10)
	jrow.add_child(UIKit.label("Host IP:", 16))
	var ip_edit := LineEdit.new()
	ip_edit.placeholder_text = "192.168.1.42"
	ip_edit.custom_minimum_size = Vector2(220, 0)
	jrow.add_child(ip_edit)
	jrow.add_child(UIKit.btn("JOIN", func():
		pick.call()
		Game.mode = Game.Mode.CLIENT
		var err := Net.join(ip_edit.text)
		if err != "":
			_mp_status.text = err, 16))
	jv.add_child(jrow)
	if Quality.is_web:
		jv.add_child(UIKit.label("Browser note: joining works when this page is served over http (e.g. a locally-run copy). On https pages the browser blocks ws:// connections - use the desktop app for guaranteed multiplayer.", 13, UIKit.DIM))
	content.add_child(join_panel)

func _on_net_status(text: String) -> void:
	if _mp_status and is_instance_valid(_mp_status):
		_mp_status.text = text

# ================================================================= SETTINGS
func show_settings() -> void:
	var content := _scroll_page("Settings", show_home)

	var vol_row := UIKit.hbox(12)
	vol_row.add_child(UIKit.label("Master volume", 16))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(SaveGame.setting("volume", 0.8))
	vol.custom_minimum_size = Vector2(240, 0)
	vol.value_changed.connect(func(v): SaveGame.set_setting("volume", v))
	vol_row.add_child(vol)
	content.add_child(vol_row)

	var ts_row := UIKit.hbox(12)
	ts_row.add_child(UIKit.label("Day/night time speed", 16))
	var ts := HSlider.new()
	ts.min_value = 1.0
	ts.max_value = 120.0
	ts.step = 1.0
	ts.value = float(SaveGame.setting("time_scale", 15.0))
	ts.custom_minimum_size = Vector2(240, 0)
	var ts_lbl := UIKit.label("%dx" % int(ts.value), 14, UIKit.DIM)
	ts.value_changed.connect(func(v):
		SaveGame.set_setting("time_scale", v)
		ts_lbl.text = "%dx" % int(v))
	ts_row.add_child(ts)
	ts_row.add_child(ts_lbl)
	content.add_child(ts_row)

	var inv_row := UIKit.hbox(12)
	inv_row.add_child(UIKit.label("Invert pitch (arrow keys)", 16))
	var inv := CheckButton.new()
	inv.button_pressed = bool(SaveGame.setting("invert_pitch", false))
	inv.toggled.connect(func(v): SaveGame.set_setting("invert_pitch", v))
	inv_row.add_child(inv)
	content.add_child(inv_row)

	var ca_row := UIKit.hbox(12)
	ca_row.add_child(UIKit.label("Turn coordination assist (auto-rudder in banks)", 16))
	var ca := CheckButton.new()
	ca.button_pressed = bool(SaveGame.setting("coord_assist", false))
	ca.toggled.connect(func(v): SaveGame.set_setting("coord_assist", v))
	ca_row.add_child(ca)
	content.add_child(ca_row)

	content.add_child(UIKit.spacer(10))
	content.add_child(UIKit.label("Quality: %s (auto-detected). Desktop = Forward+ renderer with shadows/SSAO/glow; Web = compatibility renderer. Flight physics are identical." % Quality.tier, 14, UIKit.DIM))
	content.add_child(UIKit.spacer(10))
	var danger := UIKit.btn("RESET SAVE (double-click)", func(): pass, 14)
	var armed := [false]
	danger.pressed.connect(func():
		if armed[0]:
			SaveGame.data = SaveGame._defaults()
			SaveGame.save_game()
			EventBus.toast("Save reset", "warn")
			show_home()
		else:
			armed[0] = true
			danger.text = "Are you sure? Click again to WIPE"
	)
	content.add_child(danger)

# ================================================================= HELP
func show_help() -> void:
	var content := _scroll_page("How To Fly", show_home)
	var sections := [
		["FLIGHT CONTROLS", "W - increase thrust   |   S - decrease thrust\nA - rudder left   |   D - rudder right   (also nosewheel steering on the ground)\nI - pitch up   |   K - pitch down\nJ - bank/roll left   |   L - bank/roll right\n,/. - pitch trim\n(Helicopter: W/S collective, A/D pedals, I/K cyclic fore/aft, J/L cyclic roll)\nEach key drives exactly one axis - nothing moves on its own."],
		["SYSTEMS", "Q - flaps up (retract)   |   E - flaps down (extend)\nU - less speedbrake   |   O - more speedbrake\nG - landing gear (hold 3s for emergency gravity extension)\nN - wheel brakes (hold)   |   B - parking / landing brake (toggle)\nF - reverse thrust (rolling) / pushback tug (stopped)\nH - engine start/stop   |   X - autopilot (holds heading/altitude/speed)\nC - camera views   |   Right-mouse drag - look   |   Scroll - zoom"],
		["PANELS", "R - ATC radio menu (reply with number keys 1-9)\nP - jobs board (must be parked at an airport)\nM - region map   |   F1 - this help   |   Esc - pause menu\nEnter - chat (multiplayer)"],
		["YOUR FIRST FLIGHT", "1. Press H to start engines and B to release the parking brake.\n2. Press R and request clearance, then taxi. Follow the green guide line to the assigned runway; steer with A/D, stay under 25 kts and STOP before the runway (hold short).\n3. When cleared for takeoff: line up, full throttle (hold W), then ease the nose up with I around rotation speed.\n4. Gear up (G) once climbing, flaps up (Q) as you accelerate. Follow ATC altitude.\n5. Near the destination, request approach, get established on final, gear down (G) + flaps (E), aim for the runway numbers at a 3 degree slope (the PAPI lights beside the runway show white=high, red=low; 2 white 2 red is perfect).\n6. Touch down gently (<200 fpm = butter bonus), brake (N), exit the runway and taxi to your assigned gate. Shut down engines (H) to close the flight."],
		["SKYCOINS", "Every 15-30 seconds the sim judges your flying: rewards for clean flying, following ATC, smooth landings and just being airborne - penalties for taxi speeding, runway incursions, overspeed, G-abuse, flying with gear down, crashing.\nJobs (P) pay the big money. Buy better aircraft in the hangar."],
		["DAMAGE & FAILURES", "Airframes wear slowly with use, and fast when abused (over-G, overspeed, hard landings, afterburner abuse). The lower a system's health, the more likely it fails: engine flameouts, jammed flaps, stuck gear, hydraulic loss, avionics faults. Repair and refuel in the hangar - or declare an emergency (R) and get priority landing anywhere."],
		["MULTIPLAYER", "Desktop hosts a session on TCP 9080; friends join by IP (LAN or port-forwarded internet). Everyone shares the same world and can collide - fly formation carefully!"],
	]
	for s in sections:
		var p := UIKit.panel(UIKit.BG_LIGHT)
		var v := UIKit.vbox(6)
		p.add_child(v)
		v.add_child(UIKit.label(s[0], 18, UIKit.ACCENT))
		var body := UIKit.label(s[1], 15, UIKit.TEXT)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(body)
		content.add_child(p)

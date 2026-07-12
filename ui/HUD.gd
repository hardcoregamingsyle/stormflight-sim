extends CanvasLayer
## In-flight HUD: airspeed/altitude/heading/VSI readouts, engine & fuel bars,
## gear/flap/spoiler/AP annunciators, per-system health panel, stall/overspeed
## warnings, SkyCoin feed with itemized rule-tick results, ATC radio panel,
## jobs board, region map, multiplayer chat and pause menu.

var _update_timer := 0.0

# Readout labels
var lbl_ias: Label
var lbl_alt: Label
var lbl_vs: Label
var lbl_hdg: Label
var lbl_coins: Label
var lbl_phase: Label
var lbl_clock: Label
var lbl_gs_mach: Label
var lbl_agl: Label
var bar_throttle: ProgressBar
var lbl_n1: Label
var bar_fuel: ProgressBar
var lbl_fuel: Label
var lbl_gear: Label
var lbl_flaps: Label
var lbl_annunc: Label
var health_bars: Dictionary = {}
var lbl_warn: Label
var lbl_job: Label
var job_panel: PanelContainer

# Panels
var toast_box: VBoxContainer
var atc_panel: PanelContainer
var atc_log: RichTextLabel
var atc_options_box: VBoxContainer
var jobs_panel: PanelContainer
var jobs_list: VBoxContainer
var map_view: Control
var pause_panel: PanelContainer
var help_panel: PanelContainer
var chat_panel: PanelContainer
var chat_log: RichTextLabel
var chat_edit: LineEdit
var crash_label: Label
var tick_panel: PanelContainer

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_top_bar()
	_build_instruments()
	_build_health()
	_build_warnings()
	_build_toasts()
	_build_atc()
	_build_jobs()
	_build_map()
	_build_pause()
	_build_help()
	_build_chat()
	_connect_events()

func _panel_at(preset: int) -> PanelContainer:
	var p := UIKit.panel()
	p.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 12)
	add_child(p)
	return p

# ------------------------------------------------------------------ builders
func _build_top_bar() -> void:
	var p := _panel_at(Control.PRESET_TOP_LEFT)
	var h := UIKit.hbox(18)
	p.add_child(h)
	lbl_coins = UIKit.label("0 SC", 20, UIKit.GOOD)
	h.add_child(lbl_coins)
	lbl_phase = UIKit.label("", 16, UIKit.DIM)
	h.add_child(lbl_phase)
	lbl_clock = UIKit.label("", 16, UIKit.DIM)
	h.add_child(lbl_clock)

func _build_instruments() -> void:
	# Left: airspeed
	var pl := _panel_at(Control.PRESET_CENTER_LEFT)
	var vl := UIKit.vbox(2)
	pl.add_child(vl)
	vl.add_child(UIKit.label("IAS kts", 12, UIKit.DIM))
	lbl_ias = UIKit.label("0", 34, UIKit.TEXT)
	vl.add_child(lbl_ias)
	lbl_gs_mach = UIKit.label("", 12, UIKit.DIM)
	vl.add_child(lbl_gs_mach)
	# Right: altitude
	var pr := _panel_at(Control.PRESET_CENTER_RIGHT)
	var vr := UIKit.vbox(2)
	pr.add_child(vr)
	vr.add_child(UIKit.label("ALT ft", 12, UIKit.DIM))
	lbl_alt = UIKit.label("0", 34, UIKit.TEXT)
	vr.add_child(lbl_alt)
	lbl_vs = UIKit.label("", 13, UIKit.DIM)
	vr.add_child(lbl_vs)
	lbl_agl = UIKit.label("", 12, UIKit.DIM)
	vr.add_child(lbl_agl)
	# Top center: heading
	var pc := _panel_at(Control.PRESET_CENTER_TOP)
	var vc := UIKit.vbox(0)
	pc.add_child(vc)
	lbl_hdg = UIKit.label("HDG 000", 22, UIKit.TEXT)
	lbl_hdg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vc.add_child(lbl_hdg)
	# Bottom left: engine/fuel/config
	var pb := _panel_at(Control.PRESET_BOTTOM_LEFT)
	var vb := UIKit.vbox(4)
	pb.add_child(vb)
	var thr_row := UIKit.hbox(8)
	thr_row.add_child(UIKit.label("THR", 13, UIKit.DIM))
	bar_throttle = UIKit.bar(0.0, UIKit.ACCENT, 140, 12)
	thr_row.add_child(bar_throttle)
	lbl_n1 = UIKit.label("N1 0%", 13, UIKit.DIM)
	thr_row.add_child(lbl_n1)
	vb.add_child(thr_row)
	var fuel_row := UIKit.hbox(8)
	fuel_row.add_child(UIKit.label("FUEL", 13, UIKit.DIM))
	bar_fuel = UIKit.bar(1.0, UIKit.GOOD, 140, 12)
	fuel_row.add_child(bar_fuel)
	lbl_fuel = UIKit.label("", 13, UIKit.DIM)
	fuel_row.add_child(lbl_fuel)
	vb.add_child(fuel_row)
	var cfg_row := UIKit.hbox(12)
	lbl_gear = UIKit.label("GEAR DN", 15, UIKit.GOOD)
	cfg_row.add_child(lbl_gear)
	lbl_flaps = UIKit.label("FLAPS 0", 15, UIKit.DIM)
	cfg_row.add_child(lbl_flaps)
	vb.add_child(cfg_row)
	lbl_annunc = UIKit.label("", 14, UIKit.WARN)
	vb.add_child(lbl_annunc)
	var hint := UIKit.label("Tab ATC  |  J jobs  |  M map  |  C camera  |  F1 help", 12, UIKit.DIM)
	vb.add_child(hint)

func _build_health() -> void:
	var p := _panel_at(Control.PRESET_BOTTOM_RIGHT)
	var v := UIKit.vbox(3)
	p.add_child(v)
	v.add_child(UIKit.label("SYSTEMS", 12, UIKit.DIM))
	for sys in ["structure", "engines", "flaps", "gear", "hydraulics", "avionics"]:
		var row := UIKit.hbox(8)
		var l := UIKit.label(sys.capitalize(), 12, UIKit.DIM)
		l.custom_minimum_size = Vector2(78, 0)
		row.add_child(l)
		var b := UIKit.bar(1.0, UIKit.GOOD, 90, 8)
		health_bars[sys] = b
		row.add_child(b)
		v.add_child(row)

func _build_warnings() -> void:
	lbl_warn = UIKit.label("", 34, UIKit.BAD)
	lbl_warn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_warn.offset_top = 90
	lbl_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_warn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(lbl_warn)
	crash_label = UIKit.label("", 44, UIKit.BAD)
	crash_label.set_anchors_preset(Control.PRESET_CENTER)
	crash_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(crash_label)

func _build_toasts() -> void:
	toast_box = UIKit.vbox(4)
	toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toast_box.offset_left = -430
	toast_box.offset_top = 14
	toast_box.offset_right = -14
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(toast_box)
	# Active job card
	job_panel = UIKit.panel(UIKit.BG_LIGHT)
	job_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	job_panel.offset_top = 64
	job_panel.offset_left = 12
	lbl_job = UIKit.label("", 14, UIKit.TEXT)
	job_panel.add_child(lbl_job)
	job_panel.visible = false
	add_child(job_panel)
	# Rule tick panel
	tick_panel = UIKit.panel()
	tick_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	tick_panel.offset_left = -360
	tick_panel.visible = false
	add_child(tick_panel)

func _build_atc() -> void:
	atc_panel = UIKit.panel()
	atc_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	atc_panel.offset_top = -330
	atc_panel.offset_bottom = -70
	atc_panel.offset_left = -330
	atc_panel.offset_right = 330
	atc_panel.visible = false
	add_child(atc_panel)
	var v := UIKit.vbox(6)
	atc_panel.add_child(v)
	v.add_child(UIKit.label("ATC RADIO  (numbers to reply, Tab to close)", 14, UIKit.ACCENT))
	atc_log = RichTextLabel.new()
	atc_log.bbcode_enabled = true
	atc_log.scroll_following = true
	atc_log.custom_minimum_size = Vector2(640, 150)
	atc_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	atc_log.add_theme_font_size_override("normal_font_size", 14)
	v.add_child(atc_log)
	atc_options_box = UIKit.vbox(3)
	v.add_child(atc_options_box)

func _build_jobs() -> void:
	jobs_panel = UIKit.panel()
	jobs_panel.set_anchors_preset(Control.PRESET_CENTER)
	jobs_panel.custom_minimum_size = Vector2(720, 420)
	jobs_panel.visible = false
	add_child(jobs_panel)
	var v := UIKit.vbox(6)
	jobs_panel.add_child(v)
	v.add_child(UIKit.label("JOBS BOARD  (J to close)", 16, UIKit.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(690, 360)
	v.add_child(scroll)
	jobs_list = UIKit.vbox(8)
	jobs_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(jobs_list)

func _build_map() -> void:
	map_view = Control.new()
	map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_view.visible = false
	map_view.draw.connect(_draw_map)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.09, 0.93)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_view.add_child(bg)
	bg.show_behind_parent = true
	add_child(map_view)

func _build_pause() -> void:
	pause_panel = UIKit.panel()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.visible = false
	add_child(pause_panel)
	var v := UIKit.vbox(10)
	pause_panel.add_child(v)
	v.add_child(UIKit.label("PAUSED", 28, UIKit.ACCENT))
	v.add_child(UIKit.btn("Resume", _toggle_pause, 18))
	v.add_child(UIKit.btn("Controls & Help (F1)", func():
		pause_panel.visible = false
		help_panel.visible = true, 18))  # stays paused; Esc closes help
	v.add_child(UIKit.btn("Return to Menu (autosaves)", func():
		get_tree().paused = false
		Game.return_to_menu(), 18))

func _build_help() -> void:
	help_panel = UIKit.panel()
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.visible = false
	add_child(help_panel)
	var v := UIKit.vbox(4)
	help_panel.add_child(v)
	v.add_child(UIKit.label("QUICK REFERENCE  (F1 to close)", 16, UIKit.ACCENT))
	var txt := UIKit.label(
		"W/S throttle · Arrows pitch/roll · A/D rudder · ,/. trim\n" +
		"G gear (hold=emergency) · F/V flaps · H spoilers · B brakes · N park brake\n" +
		"I engines · U pushback · X autopilot · C camera · Right-drag look · Scroll zoom\n" +
		"Tab ATC · 1-9 replies · J jobs · M map · Enter chat (MP) · Esc pause\n\n" +
		"PAPI beside runway: 2 white + 2 red = perfect glideslope.\n" +
		"Land < 200 fpm for the butter bonus. Follow ATC for rewards every 15-30 s.",
		14, UIKit.TEXT)
	v.add_child(txt)

func _build_chat() -> void:
	chat_panel = UIKit.panel()
	chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_panel.offset_top = -260
	chat_panel.offset_bottom = -170
	chat_panel.offset_left = 12
	chat_panel.offset_right = 420
	chat_panel.visible = false
	add_child(chat_panel)
	var v := UIKit.vbox(4)
	chat_panel.add_child(v)
	chat_log = RichTextLabel.new()
	chat_log.scroll_following = true
	chat_log.custom_minimum_size = Vector2(380, 90)
	chat_log.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Say something... (Enter to send, Esc to close)"
	chat_edit.text_submitted.connect(_send_chat)
	# Any focus path (mouse click included) must suppress flight inputs
	chat_edit.focus_entered.connect(func(): Game.typing = true)
	chat_edit.focus_exited.connect(func(): Game.typing = false)
	v.add_child(chat_edit)

func _connect_events() -> void:
	EventBus.notify.connect(_toast)
	EventBus.sky_coins_changed.connect(func(b): lbl_coins.text = "%d SC" % b)
	EventBus.rule_tick.connect(_on_rule_tick)
	EventBus.transaction.connect(func(_a, _r): pass)
	EventBus.atc_message.connect(_on_atc_message)
	EventBus.atc_options_changed.connect(_refresh_atc_options)
	EventBus.system_failure.connect(func(_s, d): _toast("FAILURE: %s" % d, "bad"))
	EventBus.aircraft_crashed.connect(func(r): crash_label.text = "CRASHED - %s\nRecovering aircraft..." % r)
	EventBus.chat_received.connect(_on_chat)
	EventBus.job_accepted.connect(func(_j): _refresh_active_job())
	EventBus.job_completed.connect(func(_j, _p): _refresh_active_job())
	EventBus.job_failed.connect(func(_j, _r): _refresh_active_job())
	lbl_coins.text = "%d SC" % SaveGame.coins()

# ------------------------------------------------------------------ input
func _unhandled_input(_event: InputEvent) -> void:
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if Game.typing:
			if event.physical_keycode == KEY_ESCAPE:
				_close_chat()
			return
		if event.physical_keycode == KEY_ESCAPE:
			if map_view.visible or jobs_panel.visible or atc_panel.visible or help_panel.visible:
				map_view.visible = false
				jobs_panel.visible = false
				atc_panel.visible = false
				help_panel.visible = false
			else:
				_toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if get_tree().paused:
			return
		match event.physical_keycode:
			KEY_M:
				map_view.visible = not map_view.visible
				get_viewport().set_input_as_handled()
			KEY_J:
				jobs_panel.visible = not jobs_panel.visible
				if jobs_panel.visible:
					_refresh_jobs()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				atc_panel.visible = not atc_panel.visible
				get_viewport().set_input_as_handled()
			KEY_F1:
				help_panel.visible = not help_panel.visible
				get_viewport().set_input_as_handled()
			KEY_ENTER:
				if Game.is_multiplayer() and not Game.typing:
					_open_chat()
					get_viewport().set_input_as_handled()
			_:
				if atc_panel.visible and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
					ATC.select_option(event.physical_keycode - KEY_1)
					get_viewport().set_input_as_handled()

func _toggle_pause() -> void:
	var now := not get_tree().paused
	# Never hard-pause the simulation in multiplayer
	if Game.is_multiplayer():
		pause_panel.visible = not pause_panel.visible
		return
	get_tree().paused = now
	pause_panel.visible = now

# ------------------------------------------------------------------ chat
func _open_chat() -> void:
	chat_panel.visible = true
	Game.typing = true
	# Deferred so the Enter keystroke that opened chat can't submit it
	chat_edit.grab_focus.call_deferred()

func _close_chat() -> void:
	Game.typing = false
	chat_edit.release_focus()
	if chat_log.get_parsed_text().strip_edges() == "":
		chat_panel.visible = false

func _send_chat(text: String) -> void:
	chat_edit.text = ""
	if text.strip_edges() != "":
		Net.send_chat(text.strip_edges())
	_close_chat()

func _on_chat(sender: String, text: String) -> void:
	chat_panel.visible = true
	chat_log.append_text("[color=#7fd0ff]%s:[/color] %s\n" % [sender, text])

# ------------------------------------------------------------------ ATC UI
func _on_atc_message(from_atc: bool, channel: String, text: String) -> void:
	var color := "#ffd166" if from_atc else "#9fdca8"
	atc_log.append_text("[color=%s][%s][/color] %s\n" % [color, channel, text])
	if from_atc and not atc_panel.visible:
		_toast("[%s] %s" % [channel, text], "info")

func _refresh_atc_options(options: Array) -> void:
	for c in atc_options_box.get_children():
		c.queue_free()
	for i in options.size():
		var opt: Dictionary = options[i]
		var idx := i
		atc_options_box.add_child(UIKit.btn("%d.  %s" % [i + 1, opt.label], func(): ATC.select_option(idx), 14))

# ------------------------------------------------------------------ jobs UI
func _refresh_jobs() -> void:
	for c in jobs_list.get_children():
		c.queue_free()
	var p := Game.player_aircraft as Aircraft
	var w := Game.world as WorldRoot
	if p == null or w == null:
		return
	if not Jobs.active_job.is_empty():
		var j: Dictionary = Jobs.active_job
		jobs_list.add_child(UIKit.label("ACTIVE: %s -> %s  (%d SC)" % [j.title, AirportsDB.get_airport(j.to).name, j.pay], 16, UIKit.ACCENT))
	if not p.gear.on_ground:
		jobs_list.add_child(UIKit.label("Land and park at an airport to browse its jobs board.", 15, UIKit.DIM))
		return
	var airport_id := w.nearest_airport_id(p.abs_position())
	var a := AirportsDB.get_airport(airport_id)
	jobs_list.add_child(UIKit.label("Jobs at %s:" % a.name, 16, UIKit.TEXT))
	var jobs := Jobs.available_at(airport_id)
	if jobs.is_empty():
		jobs_list.add_child(UIKit.label("No jobs right now - check back soon.", 14, UIKit.DIM))
	for job in jobs:
		var card := UIKit.panel(UIKit.BG_LIGHT)
		var h := UIKit.hbox(12)
		card.add_child(h)
		var v := UIKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var extra := ""
		if job.time_limit_s > 0:
			extra = "  |  deadline %d min" % int(job.time_limit_s / 60.0)
		if job.fragile:
			extra += "  |  FRAGILE"
		v.add_child(UIKit.label("%s  ->  %s" % [job.title, AirportsDB.get_airport(job.to).name], 16, UIKit.TEXT))
		v.add_child(UIKit.label(job.desc + extra, 13, UIKit.DIM))
		var right := UIKit.vbox(4)
		right.add_child(UIKit.label("%d SC" % job.pay, 17, UIKit.GOOD))
		var jb: Dictionary = job
		right.add_child(UIKit.btn("ACCEPT", func():
			if Jobs.accept(jb):
				_refresh_jobs()
				_refresh_active_job(), 14))
		h.add_child(right)
		jobs_list.add_child(card)

func _refresh_active_job() -> void:
	job_panel.visible = not Jobs.active_job.is_empty()

# ------------------------------------------------------------------ toasts & ticks
func _toast(text: String, kind: String) -> void:
	var color := UIKit.TEXT
	match kind:
		"good": color = UIKit.GOOD
		"bad": color = UIKit.BAD
		"warn": color = UIKit.WARN
	var l := UIKit.label(text, 15, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toast_box.add_child(l)
	if toast_box.get_child_count() > 7:
		toast_box.get_child(0).queue_free()
	# Node-bound tween dies with the label, so early purges can't error
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.2)
	tw.tween_callback(l.queue_free)

func _on_rule_tick(rewards: Array, penalties: Array, net: int) -> void:
	for c in tick_panel.get_children():
		c.queue_free()
	var v := UIKit.vbox(2)
	tick_panel.add_child(v)
	v.add_child(UIKit.label("FLIGHT REVIEW", 14, UIKit.ACCENT))
	for r in rewards:
		v.add_child(UIKit.label("+%d  %s" % [r.amount, r.label], 14, UIKit.GOOD))
	for pn in penalties:
		v.add_child(UIKit.label("%d  %s" % [pn.amount, pn.label], 14, UIKit.BAD))
	var net_l := UIKit.label("NET %+d SkyCoins" % net, 15, UIKit.GOOD if net >= 0 else UIKit.BAD)
	v.add_child(net_l)
	tick_panel.visible = true
	tick_panel.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(tick_panel, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func(): tick_panel.visible = false)

# ------------------------------------------------------------------ map
func _draw_map() -> void:
	var w := Game.world as WorldRoot
	if w == null:
		return
	var rect := map_view.get_rect()
	var world_span := 460000.0
	var scale := minf(rect.size.x, rect.size.y) / world_span
	var center := rect.size * 0.5
	var to_screen := func(abs_pos: Vector3) -> Vector2:
		return center + Vector2(abs_pos.x, abs_pos.z) * scale
	# Job route
	if not Jobs.active_job.is_empty():
		var a: Vector2 = to_screen.call(AirportsDB.position_m(Jobs.active_job.from))
		var b: Vector2 = to_screen.call(AirportsDB.position_m(Jobs.active_job.to))
		map_view.draw_line(a, b, UIKit.ACCENT, 2.0)
	# Airports
	for id in AirportsDB.ids():
		var a2 := AirportsDB.get_airport(id)
		var pos: Vector2 = to_screen.call(AirportsDB.position_m(id))
		var col := UIKit.ACCENT if id == w.current_airport_id else Color(0.5, 0.8, 1.0)
		map_view.draw_circle(pos, 5.0, col)
		map_view.draw_string(ThemeDB.fallback_font, pos + Vector2(8, 4), "%s (%s)" % [a2.name, a2.icao], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.TEXT)
	# Player
	var p := Game.player_aircraft as Aircraft
	if p:
		var pp: Vector2 = to_screen.call(p.abs_position())
		var hdg := deg_to_rad(p.get_heading())
		var fwd := Vector2(sin(hdg), -cos(hdg))
		map_view.draw_colored_polygon(PackedVector2Array([
			pp + fwd * 12.0, pp + fwd.rotated(2.5) * 8.0, pp + fwd.rotated(-2.5) * 8.0]), UIKit.GOOD)
		map_view.draw_string(ThemeDB.fallback_font, pp + Vector2(10, -8), "YOU  %d kts  %d ft" % [int(p.get_ias_kts()), int(p.get_alt_ft())], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.GOOD)
	# Remote players
	for id in Net.proxies.keys():
		var craft = Net.proxies[id].craft
		if is_instance_valid(craft):
			var rp: Vector2 = to_screen.call(craft.abs_position())
			map_view.draw_circle(rp, 4.0, Color(0.55, 0.85, 1.0))
			map_view.draw_string(ThemeDB.fallback_font, rp + Vector2(7, 4), Net.players.get(id, {}).get("name", "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.85, 1.0))

# ------------------------------------------------------------------ tick
func _process(dt: float) -> void:
	_update_timer += dt
	if _update_timer < 0.08:
		return
	_update_timer = 0.0
	var p := Game.player_aircraft as Aircraft
	var w := Game.world as WorldRoot
	if p == null or w == null:
		return

	lbl_ias.text = "%d" % int(p.get_ias_kts())
	var mach := p.get_mach()
	lbl_gs_mach.text = ("M %.2f  |  " % mach if mach > 0.4 else "") + "GS %d" % int(p.linear_velocity.length() * Atmosphere.MS_TO_KTS)
	lbl_alt.text = "%d" % int(p.get_alt_ft())
	var vs := p.get_vs_fpm()
	lbl_vs.text = "VS %+d fpm" % int(vs)
	lbl_vs.add_theme_color_override("font_color", UIKit.BAD if vs < -1200 else UIKit.DIM)
	lbl_agl.text = "AGL %d ft" % int(p.agl * Atmosphere.M_TO_FT)
	lbl_hdg.text = "HDG %03d" % int(p.get_heading())
	lbl_clock.text = "%02d:%02d  |  %s  wind %d kts" % [int(w.hour) % 24, int(fmod(w.hour, 1.0) * 60.0), w.weather, int(w.wind_base.length() * Atmosphere.MS_TO_KTS)]
	lbl_phase.text = "%s  |  %s" % [AirportsDB.get_airport(w.nearest_airport_id(p.abs_position())).icao, _phase_name()]

	bar_throttle.value = p.ctl_throttle
	lbl_n1.text = "N1 %d%%" % int(p.propulsion.average_n1() * 100.0)
	bar_fuel.value = p.fuel_fraction()
	lbl_fuel.text = "%d kg" % int(p.fuel_kg)
	var fill := bar_fuel.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = UIKit.GOOD if p.fuel_fraction() > 0.2 else UIKit.BAD

	if p.cfg.gear_retractable:
		var gf := p.gear.gear_frac
		if gf > 0.98:
			lbl_gear.text = "GEAR DN"
			lbl_gear.add_theme_color_override("font_color", UIKit.GOOD)
		elif gf < 0.02:
			lbl_gear.text = "GEAR UP"
			lbl_gear.add_theme_color_override("font_color", UIKit.DIM)
		else:
			lbl_gear.text = "GEAR ..."
			lbl_gear.add_theme_color_override("font_color", UIKit.WARN)
	else:
		lbl_gear.text = "GEAR FIXED"
		lbl_gear.add_theme_color_override("font_color", UIKit.DIM)
	lbl_flaps.text = "FLAPS %d%%" % int(p.flap_setting * 100)

	var ann := ""
	if p.autopilot.engaged:
		ann += "AP  "
	if p.gear.parking_brake:
		ann += "PARK BRK  "
	if p.spoiler_on:
		ann += "SPOILERS  "
	if p.propulsion.afterburner:
		ann += "AFTERBURNER  "
	if p.pushback_active:
		ann += "PUSHBACK  "
	if not p.propulsion.any_running():
		ann += "ENGINES OFF (press I)  "
	lbl_annunc.text = ann

	# Health bars
	var eng_avg := 0.0
	for hp in p.propulsion.health:
		eng_avg += hp
	eng_avg /= maxf(p.propulsion.health.size(), 1.0)
	var vals := {
		"structure": p.damage_sys.health["structure"], "engines": eng_avg,
		"flaps": p.damage_sys.health["flaps"], "gear": p.damage_sys.health["gear"],
		"hydraulics": p.damage_sys.health["hydraulics"], "avionics": p.damage_sys.health["avionics"],
	}
	for sys in vals.keys():
		var b: ProgressBar = health_bars[sys]
		b.value = vals[sys]
		var f := b.get_theme_stylebox("fill") as StyleBoxFlat
		f.bg_color = UIKit.GOOD if vals[sys] > 0.6 else (UIKit.WARN if vals[sys] > 0.3 else UIKit.BAD)

	# Warnings
	var warn := ""
	if p.aero.stalled:
		warn = "STALL"
	elif p.get_ias() > p.cfg.vne:
		warn = "OVERSPEED"
	elif p.cfg.gear_retractable and not p.gear.is_down() and p.agl < 150.0 and p.get_vs_fpm() < -200.0 and not p.crashed:
		warn = "GEAR!"
	lbl_warn.text = warn
	lbl_warn.visible = warn != "" and fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.2
	if not p.crashed:
		crash_label.text = ""

	# Active job status
	if not Jobs.active_job.is_empty():
		var j: Dictionary = Jobs.active_job
		var t := ""
		if j.time_limit_s > 0:
			t = "  |  %d:%02d left" % [int(j.time_left / 60.0), int(fmod(j.time_left, 60.0))]
		var dist := (AirportsDB.position_m(j.to) - p.abs_position()).length() / 1000.0
		lbl_job.text = "JOB: %s -> %s\n%d km to go%s  |  %d SC" % [j.title, AirportsDB.get_airport(j.to).name, int(dist), t, j.pay]
		job_panel.visible = true
	else:
		job_panel.visible = false
	if map_view.visible:
		map_view.queue_redraw()

func _phase_name() -> String:
	var names := {
		ATC.Phase.IDLE: "Free flight", ATC.Phase.AT_GATE: "At gate", ATC.Phase.CLEARANCE: "Cleared",
		ATC.Phase.TAXI_OUT: "Taxi out", ATC.Phase.HOLDING_SHORT: "Holding short", ATC.Phase.LINEUP: "Line up",
		ATC.Phase.TAKEOFF_CLEARED: "Cleared takeoff", ATC.Phase.DEPARTURE: "Departure", ATC.Phase.ENROUTE: "Enroute",
		ATC.Phase.APPROACH: "Approach", ATC.Phase.FINAL: "Final", ATC.Phase.TAXI_IN: "Taxi in", ATC.Phase.EMERGENCY: "EMERGENCY",
	}
	return names.get(ATC.phase, "")

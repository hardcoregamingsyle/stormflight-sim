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
var lbl_thrust: Label
var lbl_eng_status: Label
var eng_cluster: HBoxContainer
var eng_bars: Array = []
var eng_dots: Array = []
var gear_dots: Array = []
var flap_segs: Array = []
var annunc_chips: Dictionary = {}
var lbl_next_step: Label
var lbl_target: Label
var lbl_atc_hint: Label
var banner_mode: Label
var health_bars: Dictionary = {}
var lbl_warn: Label
var lbl_job: Label
var job_panel: PanelContainer
var map_zoom := 1.0
var _trail: Array = []
var _trail_timer := 0.0
var _map_tex: ImageTexture = null

# Panels
var toast_box: VBoxContainer
var atc_panel: PanelContainer
var atc_log: RichTextLabel
var atc_options_box: VBoxContainer
var atc_phase_lbl: Label
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
	# Panels must grow INTO the screen when content is added, not off it
	match preset:
		Control.PRESET_BOTTOM_LEFT:
			p.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			p.grow_vertical = Control.GROW_DIRECTION_BEGIN
			p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_RIGHT:
			p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			p.grow_vertical = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER_LEFT:
			p.grow_vertical = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER_TOP:
			p.grow_horizontal = Control.GROW_DIRECTION_BOTH
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
	# Bottom left: the avionics cluster - engines, thrust, fuel, gear lights,
	# flap segments and annunciators
	var pb := _panel_at(Control.PRESET_BOTTOM_LEFT)
	var vb := UIKit.vbox(6)
	pb.add_child(vb)

	# --- Engine gauges: one vertical N1 bar + status light per engine ---
	var eng_row := UIKit.hbox(10)
	eng_row.add_child(UIKit.label("ENG", 13, UIKit.DIM))
	eng_cluster = UIKit.hbox(5)
	eng_row.add_child(eng_cluster)
	lbl_eng_status = UIKit.label("OFF", 14, UIKit.DIM)
	eng_row.add_child(lbl_eng_status)
	lbl_n1 = UIKit.label("N1 0%", 14, UIKit.TEXT)
	eng_row.add_child(lbl_n1)
	vb.add_child(eng_row)

	# --- Throttle & thrust ---
	var thr_row := UIKit.hbox(8)
	thr_row.add_child(UIKit.label("THR", 13, UIKit.DIM))
	bar_throttle = UIKit.bar(0.0, UIKit.ACCENT, 150, 13)
	thr_row.add_child(bar_throttle)
	lbl_thrust = UIKit.label("0%", 14, UIKit.TEXT)
	thr_row.add_child(lbl_thrust)
	vb.add_child(thr_row)

	# --- Fuel ---
	var fuel_row := UIKit.hbox(8)
	fuel_row.add_child(UIKit.label("FUEL", 13, UIKit.DIM))
	bar_fuel = UIKit.bar(1.0, UIKit.GOOD, 150, 13)
	fuel_row.add_child(bar_fuel)
	lbl_fuel = UIKit.label("", 13, UIKit.DIM)
	fuel_row.add_child(lbl_fuel)
	vb.add_child(fuel_row)

	# --- Gear lights + flap segments ---
	var cfg_row := UIKit.hbox(14)
	var gear_box := UIKit.hbox(4)
	gear_box.add_child(UIKit.label("GEAR", 13, UIKit.DIM))
	for i in 3:
		var d := UIKit.label("●", 17, UIKit.GOOD)
		gear_dots.append(d)
		gear_box.add_child(d)
	lbl_gear = UIKit.label("DOWN", 14, UIKit.GOOD)
	gear_box.add_child(lbl_gear)
	cfg_row.add_child(gear_box)
	var flap_box := UIKit.hbox(3)
	flap_box.add_child(UIKit.label("FLAPS", 13, UIKit.DIM))
	for i in 4:
		var seg := UIKit.label("▮", 15, Color(0.3, 0.36, 0.45))
		flap_segs.append(seg)
		flap_box.add_child(seg)
	lbl_flaps = UIKit.label("0%", 14, UIKit.DIM)
	flap_box.add_child(lbl_flaps)
	cfg_row.add_child(flap_box)
	vb.add_child(cfg_row)

	# --- Annunciator chips ---
	var ann_row := UIKit.hbox(6)
	for spec in [["AP", UIKit.GOOD], ["PARK BRK", UIKit.BAD], ["SPLR", UIKit.WARN], ["A/B", Color(1.0, 0.5, 0.1)], ["PUSHBACK", Color(0.3, 0.85, 1.0)], ["TRIM", UIKit.DIM], ["FUEL IMBAL", UIKit.WARN]]:
		var chip := _make_chip(spec[0], spec[1])
		annunc_chips[spec[0]] = chip
		ann_row.add_child(chip)
	vb.add_child(ann_row)
	lbl_annunc = UIKit.label("", 13, UIKit.WARN)
	vb.add_child(lbl_annunc)
	vb.add_child(UIKit.label("R ATC  |  P jobs  |  M map  |  C camera  |  F1 help", 12, UIKit.DIM))

func _make_chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color * Color(1, 1, 1, 0.22)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var l := UIKit.label(text, 12, color)
	p.add_child(l)
	p.visible = false
	return p

func _ensure_engine_bars(count: int) -> void:
	if eng_bars.size() == count:
		return
	for c in eng_cluster.get_children():
		c.queue_free()
	eng_bars.clear()
	eng_dots.clear()
	for i in count:
		var col := UIKit.vbox(1)
		var b := UIKit.bar(0.0, UIKit.ACCENT, 15, 40)
		b.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		eng_bars.append(b)
		col.add_child(b)
		var dot := UIKit.label("●", 13, UIKit.DIM)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		eng_dots.append(dot)
		col.add_child(dot)
		eng_cluster.add_child(col)

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
	# NEXT STEP advisory: always tells the pilot what to do now
	var step_panel := UIKit.panel(Color(0.1, 0.09, 0.03, 0.88))
	step_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	step_panel.offset_top = 52
	step_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var sv := UIKit.vbox(0)
	step_panel.add_child(sv)
	lbl_next_step = UIKit.label("", 15, UIKit.WARN)
	lbl_next_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(lbl_next_step)
	lbl_target = UIKit.label("", 13, UIKit.DIM)
	lbl_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(lbl_target)
	add_child(step_panel)

	# Big mode banner (pushback etc)
	banner_mode = UIKit.label("", 24, Color(0.3, 0.85, 1.0))
	banner_mode.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	banner_mode.offset_top = -170
	banner_mode.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner_mode)

	# "ATC is waiting" pulsing hint
	lbl_atc_hint = UIKit.label("", 16, UIKit.ACCENT)
	lbl_atc_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_atc_hint.offset_top = -60
	lbl_atc_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lbl_atc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl_atc_hint)

	lbl_warn = UIKit.label("", 34, UIKit.BAD)
	lbl_warn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_warn.offset_top = 118
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
	var head := UIKit.hbox(12)
	head.add_child(UIKit.label("ATC RADIO  (numbers to reply, R to close)", 14, UIKit.ACCENT))
	atc_phase_lbl = UIKit.label("", 13, UIKit.DIM)
	head.add_child(atc_phase_lbl)
	v.add_child(head)
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
		"W/S thrust · A/D rudder+steer · I/K pitch · J/L roll · ,/. trim\n" +
		"G gear (hold=emergency) · Q/E flaps · U/O speedbrake · N brakes · B park brake\n" +
		"H engines · F reverse/pushback · X autopilot · C camera · Right-drag look · Scroll zoom\n" +
		"R ATC · 1-9 replies · P jobs · M map · Enter chat (MP) · Esc pause\n\n" +
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
	# Map zoom with the mouse wheel
	if map_view.visible and event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_zoom = minf(map_zoom * 2.0, 16.0)
			map_view.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_zoom = maxf(map_zoom / 2.0, 1.0)
			map_view.queue_redraw()
			get_viewport().set_input_as_handled()
			return
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
			KEY_P:
				jobs_panel.visible = not jobs_panel.visible
				if jobs_panel.visible:
					_refresh_jobs()
				get_viewport().set_input_as_handled()
			KEY_R:
				atc_panel.visible = not atc_panel.visible
				get_viewport().set_input_as_handled()
			KEY_F1:
				help_panel.visible = not help_panel.visible
				get_viewport().set_input_as_handled()
			KEY_ENTER:
				if Game.is_multiplayer() and not Game.typing:
					_open_chat()
					get_viewport().set_input_as_handled()
			KEY_EQUAL, KEY_KP_ADD:
				if map_view.visible:
					map_zoom = minf(map_zoom * 2.0, 16.0)
					map_view.queue_redraw()
					get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				if map_view.visible:
					map_zoom = maxf(map_zoom / 2.0, 1.0)
					map_view.queue_redraw()
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
	var p := Game.player_aircraft as Aircraft
	if _map_tex == null:
		_map_tex = w.terrain.build_map_texture()
	var rect := map_view.get_rect()
	var font := ThemeDB.fallback_font

	const REGION := 460000.0
	var span := REGION / map_zoom
	var view_scale := minf(rect.size.x, rect.size.y) / span
	var center := rect.size * 0.5
	var center_world := Vector2.ZERO
	if map_zoom > 1.01 and p:
		center_world = Vector2(p.abs_position().x, p.abs_position().z)
	var to_screen := func(abs_pos: Vector3) -> Vector2:
		return center + (Vector2(abs_pos.x, abs_pos.z) - center_world) * view_scale

	# Terrain background (texture spans the whole region)
	var tl: Vector2 = to_screen.call(Vector3(-REGION * 0.5, 0, -REGION * 0.5))
	map_view.draw_texture_rect(_map_tex, Rect2(tl, Vector2.ONE * REGION * view_scale), false)

	# Grid every 50 km
	var grid_col := Color(1, 1, 1, 0.07)
	var k := -250000.0
	while k <= 250000.0:
		map_view.draw_line(to_screen.call(Vector3(k, 0, -REGION)), to_screen.call(Vector3(k, 0, REGION)), grid_col, 1.0)
		map_view.draw_line(to_screen.call(Vector3(-REGION, 0, k)), to_screen.call(Vector3(REGION, 0, k)), grid_col, 1.0)
		k += 50000.0

	# Job route
	if not Jobs.active_job.is_empty():
		var ja: Vector2 = to_screen.call(AirportsDB.position_m(Jobs.active_job.from))
		var jb: Vector2 = to_screen.call(AirportsDB.position_m(Jobs.active_job.to))
		map_view.draw_dashed_line(ja, jb, UIKit.ACCENT, 2.0, 12.0)

	# Airports with runway orientation strips
	for id in AirportsDB.ids():
		var a2 := AirportsDB.get_airport(id)
		var apos := AirportsDB.position_m(id)
		var pos: Vector2 = to_screen.call(apos)
		if not rect.has_point(pos + rect.position):
			continue
		for rw in a2.runways:
			var hh := deg_to_rad(float(rw.heading))
			var rdir := Vector3(sin(hh), 0, -cos(hh))
			var rc := apos + Vector3(float(rw.offset[0]), 0, float(rw.offset[1]))
			var ra: Vector2 = to_screen.call(rc - rdir * float(rw.length) * 0.5)
			var rb: Vector2 = to_screen.call(rc + rdir * float(rw.length) * 0.5)
			map_view.draw_line(ra, rb, Color(0.95, 0.95, 1.0), maxf(2.0, float(rw.length) * view_scale * 0.02))
		var col := UIKit.ACCENT if id == w.current_airport_id else Color(0.55, 0.8, 1.0)
		map_view.draw_circle(pos, 4.0, col)
		var dist_txt := ""
		if p:
			dist_txt = "  %d km" % int((apos - p.abs_position()).length() / 1000.0)
		map_view.draw_string(font, pos + Vector2(7, -6), "%s (%s)%s" % [a2.name, a2.icao, dist_txt], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.TEXT)

	# Flight trail
	if _trail.size() > 1:
		for i in range(_trail.size() - 1):
			var alpha := 0.15 + 0.55 * float(i) / _trail.size()
			map_view.draw_line(to_screen.call(_trail[i]), to_screen.call(_trail[i + 1]), Color(0.3, 0.9, 0.5, alpha), 1.5)

	# ATC target
	var tgt := ATC.target_point()
	if tgt != Vector3.ZERO:
		var tp: Vector2 = to_screen.call(tgt)
		map_view.draw_arc(tp, 9.0, 0, TAU, 20, UIKit.WARN, 2.0)
		if p:
			map_view.draw_dashed_line(to_screen.call(p.abs_position()), tp, Color(1.0, 0.78, 0.2, 0.6), 1.5, 10.0)

	# Player
	if p:
		var pp: Vector2 = to_screen.call(p.abs_position())
		var hdg := deg_to_rad(p.get_heading())
		var fwd := Vector2(sin(hdg), -cos(hdg))
		map_view.draw_colored_polygon(PackedVector2Array([
			pp + fwd * 13.0, pp + fwd.rotated(2.5) * 9.0, pp + fwd.rotated(-2.5) * 9.0]), UIKit.GOOD)
		map_view.draw_string(font, pp + Vector2(11, -9), "YOU  %d kts  %d ft" % [int(p.get_ias_kts()), int(p.get_alt_ft())], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.GOOD)

	# Remote players
	for id in Net.proxies.keys():
		var craft = Net.proxies[id].craft
		if is_instance_valid(craft):
			var rp: Vector2 = to_screen.call(craft.abs_position())
			map_view.draw_circle(rp, 4.0, Color(0.55, 0.85, 1.0))
			map_view.draw_string(font, rp + Vector2(7, 4), Net.players.get(id, {}).get("name", "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.85, 1.0))

	# HUD chrome: north arrow, scale bar, zoom + legend
	map_view.draw_string(font, Vector2(22, 34), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.TEXT)
	map_view.draw_colored_polygon(PackedVector2Array([Vector2(30, 40), Vector2(24, 58), Vector2(36, 58)]), UIKit.TEXT)
	var bar_km := 100.0 / map_zoom
	var bar_px := bar_km * 1000.0 * view_scale
	var by := rect.size.y - 30.0
	map_view.draw_line(Vector2(24, by), Vector2(24 + bar_px, by), UIKit.TEXT, 2.0)
	map_view.draw_string(font, Vector2(24, by - 8), "%d km" % int(bar_km), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.TEXT)
	map_view.draw_string(font, Vector2(24, by + 22), "M close  |  +/- or scroll to zoom (x%d)  |  amber ring = ATC target  |  green trail = your path" % int(map_zoom), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.DIM)

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
	if atc_panel.visible:
		atc_phase_lbl.text = "Phase: %s" % _phase_name()

	# --- Engines ---
	_ensure_engine_bars(p.cfg.engine_count)
	var any_run := p.propulsion.any_running()
	for i in p.cfg.engine_count:
		var n1_i: float = p.propulsion.n1[i]
		(eng_bars[i] as ProgressBar).value = n1_i
		var dot := eng_dots[i] as Label
		var col := UIKit.DIM
		if p.propulsion.running[i]:
			col = UIKit.GOOD if n1_i > 0.15 else UIKit.WARN
		elif p.propulsion.health[i] < 0.15:
			col = UIKit.BAD
		dot.add_theme_color_override("font_color", col)
	if any_run:
		lbl_eng_status.text = "RUN"
		lbl_eng_status.add_theme_color_override("font_color", UIKit.GOOD)
	else:
		lbl_eng_status.text = "OFF - press H"
		lbl_eng_status.add_theme_color_override("font_color", UIKit.BAD)
	lbl_n1.text = "N1 %d%%" % int(p.propulsion.average_n1() * 100.0)

	bar_throttle.value = p.ctl_throttle
	lbl_thrust.text = "%d%%%s" % [int(p.ctl_throttle * 100.0), "  AB" if p.propulsion.afterburner else ""]
	bar_fuel.value = p.fuel_fraction()
	lbl_fuel.text = "%d kg  (%s)" % [int(p.fuel_kg), p.fuel_sys.readout()]
	var fill := bar_fuel.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = UIKit.GOOD if p.fuel_fraction() > 0.2 else UIKit.BAD

	# --- Gear lights: green = locked down, amber = transit, dark = up ---
	var gcol: Color
	if not p.cfg.gear_retractable:
		gcol = UIKit.GOOD
		lbl_gear.text = "FIXED"
	else:
		var gf := p.gear.gear_frac
		if gf > 0.98:
			gcol = UIKit.GOOD
			lbl_gear.text = "DOWN"
		elif gf < 0.02:
			gcol = Color(0.3, 0.36, 0.45)
			lbl_gear.text = "UP"
		else:
			gcol = UIKit.WARN
			lbl_gear.text = "TRANSIT"
	if p.damage_sys.has_failed("gear"):
		gcol = UIKit.BAD
		lbl_gear.text = "JAMMED (hold G)"
	for d in gear_dots:
		(d as Label).add_theme_color_override("font_color", gcol)
	lbl_gear.add_theme_color_override("font_color", gcol)

	# --- Flap segments ---
	var notch := int(round(p.flap_setting * 4.0))
	for i in 4:
		(flap_segs[i] as Label).add_theme_color_override("font_color",
			UIKit.ACCENT if i < notch else Color(0.3, 0.36, 0.45))
	lbl_flaps.text = "%d%%" % int(p.flap_frac * 100)
	if p.damage_sys.has_failed("flaps"):
		lbl_flaps.text += " JAM"

	# --- Annunciator chips ---
	(annunc_chips["AP"] as Control).visible = p.autopilot.engaged
	(annunc_chips["PARK BRK"] as Control).visible = p.gear.parking_brake
	(annunc_chips["SPLR"] as Control).visible = p.spoiler_frac > 0.05
	(annunc_chips["A/B"] as Control).visible = p.propulsion.afterburner
	(annunc_chips["PUSHBACK"] as Control).visible = p.pushback_active
	(annunc_chips["TRIM"] as Control).visible = absf(p.ctl_trim) > 0.02
	(annunc_chips["FUEL IMBAL"] as Control).visible = \
		absf(p.fuel_sys.imbalance_kg()) > maxf(p.cfg.fuel_capacity * 0.06, 25.0)
	lbl_annunc.text = ""

	# --- Mode banner ---
	if p.pushback_active:
		banner_mode.text = "PUSHBACK IN PROGRESS  -  press F to stop, A/D to steer"
		banner_mode.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	elif p.gear.parking_brake and any_run and p.gear.on_ground:
		banner_mode.text = "PARKING BRAKE SET  -  press N to release"
		banner_mode.add_theme_color_override("font_color", UIKit.WARN)
	else:
		banner_mode.text = ""

	# --- NEXT STEP advisory + target guidance ---
	lbl_next_step.text = ATC.next_step()
	var tgt := ATC.target_point()
	if tgt != Vector3.ZERO:
		var delta := tgt - p.abs_position()
		var dist_m := Vector2(delta.x, delta.z).length()
		var bearing := fposmod(rad_to_deg(atan2(delta.x, -delta.z)), 360.0)
		var rel := wrapf(bearing - p.get_heading(), -180.0, 180.0)
		var arrow := "^"
		if absf(rel) < 20.0:
			arrow = "STRAIGHT AHEAD"
		elif rel >= 20.0 and rel < 70.0:
			arrow = "AHEAD-RIGHT >"
		elif rel >= 70.0 and rel < 110.0:
			arrow = "RIGHT >>"
		elif rel >= 110.0:
			arrow = "BEHIND (turn right)"
		elif rel <= -20.0 and rel > -70.0:
			arrow = "< AHEAD-LEFT"
		elif rel <= -70.0 and rel > -110.0:
			arrow = "<< LEFT"
		else:
			arrow = "BEHIND (turn left)"
		var dist_txt := "%d m" % int(dist_m) if dist_m < 3000.0 else "%.1f km" % (dist_m / 1000.0)
		lbl_target.text = "Target: %s  -  %s  (hdg %03d)" % [dist_txt, arrow, int(bearing)]
	else:
		lbl_target.text = ""

	# --- ATC waiting hint ---
	if not ATC.options.is_empty() and not atc_panel.visible:
		lbl_atc_hint.text = "R > ATC radio  (%d option%s)" % [ATC.options.size(), "s" if ATC.options.size() > 1 else ""]
		lbl_atc_hint.visible = fmod(Time.get_ticks_msec() / 600.0, 2.0) < 1.4
	else:
		lbl_atc_hint.visible = false

	# --- Map trail sampling ---
	_trail_timer += 0.08
	if _trail_timer > 2.0 and not p.gear.on_ground:
		_trail_timer = 0.0
		_trail.append(p.abs_position())
		if _trail.size() > 240:
			_trail.pop_front()

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

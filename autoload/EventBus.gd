extends Node
## Global signal hub. All cross-system communication flows through here so
## systems stay decoupled (UI, economy, ATC, network all listen here).

# --- Economy ---
signal sky_coins_changed(balance: int)
signal transaction(amount: int, reason: String)
signal rule_tick(rewards: Array, penalties: Array, net: int)

# --- Flight / aircraft ---
signal aircraft_spawned(aircraft: Node)
signal aircraft_removed()
signal aircraft_crashed(reason: String)
signal landed(fpm: float, quality: String)
signal took_off()
signal gear_changed(down: bool)
signal system_failure(system_name: String, description: String)
signal system_repaired(system_name: String)
signal health_changed(system_name: String, value: float)
signal fuel_low(fraction: float)
signal stall_warning(active: bool)
signal overspeed_warning(active: bool)

# --- ATC ---
signal atc_message(from_atc: bool, channel: String, text: String)
signal atc_phase_changed(phase: int)
signal atc_options_changed(options: Array)

# --- Jobs ---
signal job_accepted(job: Dictionary)
signal job_completed(job: Dictionary, pay: int)
signal job_failed(job: Dictionary, reason: String)
signal jobs_refreshed()

# --- Multiplayer ---
signal net_player_joined(id: int, player_name: String)
signal net_player_left(id: int, player_name: String)
signal net_status(text: String)
signal chat_received(sender: String, text: String)

# --- World / UI ---
signal origin_shifted(offset: Vector3)
signal world_time_changed(hour: float)
signal notify(text: String, kind: String) # kind: "info" | "good" | "bad" | "warn"
signal flight_started()
signal flight_ended()

func toast(text: String, kind: String = "info") -> void:
	notify.emit(text, kind)

extends Sandbox

# Silent Link Mode Controller - Event-driven state machine matching TutorialController structure

const SILENT_LINK_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")
const SILENT_LINK_HINT := preload("res://scenes/ui/HintPopup.tscn")

const MAX_LEVEL := 5

enum Step { WELCOME, PLANNING, SIMULATING, COMPLETE }

var _step: Step = Step.WELCOME
var _intro_popup_open := false
var _start_time: float = 0.0
var _completion_time: float = 0.0
var _timer_label: Label = null
var _hud: Node = null
var _current_level: int = 1

var _link_established := false
var _player_detected := false
var _jammed := false
var _simulation_over := false
var _terrain_blocked := false
var _link_success_from_sim := false
var _ever_detected := false
var _ever_jammed := false

# Gameplay entities
var _player_units: Array = []
var _enemy_units: Array = []
var _transceivers: Array = []
var _allowed_units: Array[StringName] = []

var _revealed_jammers := {}


func add_to_groups_recursive(node: Node) -> void:
	for c in node.get_children():
		if c.name.begins_with("Friendly"):
			c.add_to_group("transceivers")
		elif c.name.begins_with("Enemy"):
			c.add_to_group("enemy_units")
		add_to_groups_recursive(c)


func _ready() -> void:
	super._ready()

	# Extract scene level from scene name
	var level_name := get_tree().current_scene.scene_file_path
	var file_name := level_name.get_file().get_basename()
	var parts := file_name.split("-")
	_current_level = int(parts[1]) if parts.size() > 1 else 1

	add_to_groups_recursive(self)

	GameEvents.simulation_requested.connect(_on_simulation_requested)
	GameEvents.simulation_complete.connect(_on_simulation_complete)

	_hud = find_child("HUD", true, false)

	if is_instance_valid(_hud):
		if _hud.has_method("set_spectrum_enabled"):
			_hud.set_spectrum_enabled(true)

		var hints_toggle = _hud.find_child("DetectionHintsToggle", true, false)
		if hints_toggle and "button_pressed" in hints_toggle:
			hints_toggle.button_pressed = true

	_transceivers = get_tree().get_nodes_in_group("transceivers")
	_enemy_units = get_tree().get_nodes_in_group("enemy_units")

	for tx in _transceivers:
		if tx.has_method("set_attributes_unlocked_override"):
			tx.set_attributes_unlocked_override(true)

	for enemy in _enemy_units:
		if enemy.has_method("set_selectable"):
			enemy.set_selectable(false)

	set_process(true)
	_start()


func get_game_mode_name() -> String:
	return "silent-link"


func _exit_tree() -> void:
	if GameEvents.simulation_requested.is_connected(_on_simulation_requested):
		GameEvents.simulation_requested.disconnect(_on_simulation_requested)
	if GameEvents.simulation_complete.is_connected(_on_simulation_complete):
		GameEvents.simulation_complete.disconnect(_on_simulation_complete)


func _process(_delta: float) -> void:
	if _step != Step.COMPLETE and _timer_label:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
		_timer_label.text = "Time: %.1fs" % elapsed


func _start() -> void:
	if _intro_popup_open:
		return
	_intro_popup_open = true

	var popup := SILENT_LINK_INTRO_POPUP.instantiate()
	var level_content := _get_level_intro_content(_current_level)

	popup.title_string = level_content["title"]
	popup.body_string = level_content["body"]
	popup.button_string = "Continue"

	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	cl.add_child(popup)

	if popup.has_signal("continued"):
		popup.continued.connect(_on_intro_closed)


func _on_intro_closed() -> void:
	_intro_popup_open = false
	_advance()


func _advance() -> void:
	match _step:
		Step.WELCOME:
			_step = Step.PLANNING
			_start_time = Time.get_ticks_msec() / 1000.0
			_show_timer()
			_show_hint("Plan a silent link, then run simulation. Avoid detection and jamming.")

		Step.PLANNING:
			pass

		Step.SIMULATING:
			pass

		Step.COMPLETE:
			_show_scoreboard()


func _has_minimum_setup() -> bool:
	# Require at least 2 transceivers total on map (preplaced + player placed)
	var total_transceivers := get_tree().get_nodes_in_group("transceivers").size()
	return total_transceivers >= 2


func _on_simulation_requested() -> void:
	if _step != Step.PLANNING and _step != Step.COMPLETE:
		return

	if not _has_minimum_setup():
		_step = Step.PLANNING
		return

	_player_units.clear()
	for u in get_tree().get_nodes_in_group("transceivers"):
		if not u.name.begins_with("Friendly"):
			_player_units.append(u)

	_player_detected = false
	_jammed = false
	_link_established = false
	_terrain_blocked = false
	_simulation_over = false
	_step = Step.SIMULATING


func _on_simulation_complete(link_results: Array, _detect_results: Array) -> void:
	if _step != Step.SIMULATING or _simulation_over:
		return

	if not _has_minimum_setup():
		return

	_player_detected = false
	_jammed = false
	_terrain_blocked = false
	_link_established = false
	_simulation_over = false
	_link_success_from_sim = false

	_reveal_detected_jammers(_detect_results)

	# 1. Global Detection Check (Hard fail - users shouldn't win if detected)
	_check_detection_from_sim(_detect_results)
	if _player_detected:
		_step = Step.PLANNING
		_show_hint("Detected by enemy! Try a stealthier route.")
		return

	# 2. Evaluate if ANY unbroken chain of SUCCESS links exists
	_link_success_from_sim = _check_chain_between_endpoints()

	# 3. If a valid chain exists, they win! Extraneous blocked/jammed links are ignored.
	if _link_success_from_sim:
		_link_established = true

		# We still check jamming here purely for the stealth bonus in _calculate_score()
		_check_jamming()

		_finish(true)
		return

	# 4. If they didn't win (the chain is broken), parse the results to give the best hint
	for result in link_results:
		if not (result is Dictionary):
			continue
		var state: int = result.get("state", -1)
		if state == SimulationManager.LinkState.TERRAIN_BLOCKED:
			_terrain_blocked = true
		elif state == SimulationManager.LinkState.FAILED_JAMMED:
			_jammed = true

	_step = Step.PLANNING

	if _jammed:
		_show_hint("Chain broken by jamming! Reposition transceivers to avoid interference.")


func _check_chain_between_endpoints() -> bool:
	var endpoints := []
	for u in get_tree().get_nodes_in_group("transceivers"):
		if u.name.begins_with("Friendly"):
			endpoints.append(u)

	if endpoints.size() < 2:
		return false

	var source: Node = endpoints[0]
	var target: Node = endpoints[1]

	# Gather all enemy jammers to feed into the link physics
	var jammers := []
	for u in _enemy_units:
		if u.has_method("is_jammer") and u.is_jammer():
			jammers.append(u)

	# Build the list of all valid relays (player placed + the endpoints themselves)
	var own_txs: Array = _player_units.duplicate()
	if not own_txs.has(source):
		own_txs.append(source)
	if not own_txs.has(target):
		own_txs.append(target)

	var success := SimulationManager.LinkState.SUCCESS
	var visited := {}
	var queue: Array = [source]
	visited[source.get_instance_id()] = true

	while not queue.is_empty():
		var u = queue.pop_back()
		if u == null or not is_instance_valid(u):
			continue

		# If we have reached the target transceiver, the chain is complete
		if u == target:
			return true

		for v in own_txs:
			if v == null or v == u or not is_instance_valid(v):
				continue
			if visited.has(v.get_instance_id()):
				continue

			# A hop counts if either direction links successfully
			var fwd: int = SimulationManager.calculate_link(u, v, jammers)
			var rev: int = SimulationManager.calculate_link(v, u, jammers)

			if fwd == success or rev == success:
				visited[v.get_instance_id()] = true
				queue.append(v)

	return false


func _reveal_detected_jammers(detect_results: Array) -> void:
	for result in detect_results:
		if not (result is Dictionary):
			continue
		if result.get("target_type", "") != "jammer":
			continue
		if not result.get("fully_detected", false):
			continue

		var jammer = result.get("target")
		if jammer == null or not is_instance_valid(jammer):
			continue

		_reveal_jammer(jammer)


func _reveal_jammer(jammer: Node) -> void:
	var jammer_id := jammer.get_instance_id()
	if _revealed_jammers.has(jammer_id):
		return
	_revealed_jammers[jammer_id] = true

	if jammer.has_method("reveal"):
		jammer.reveal()
	elif "visible" in jammer:
		jammer.visible = true


func _parse_sim_results_for_flags(link_results: Array, detect_results: Array) -> void:
	for result in link_results:
		if not result is Dictionary:
			continue

		var state: int = result.get("state", 0)

		if state == SimulationManager.LinkState.TERRAIN_BLOCKED:
			_terrain_blocked = true
		elif state == SimulationManager.LinkState.FAILED_JAMMED:
			_jammed = true

	for detect_result in detect_results:
		if detect_result is Dictionary:
			pass


func _finish(success: bool) -> void:
	if _simulation_over:
		return

	_simulation_over = true
	_completion_time = Time.get_ticks_msec() / 1000.0 - _start_time

	if success:
		_step = Step.COMPLETE
	else:
		_step = Step.PLANNING

	_advance()


func _show_timer() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 500
	add_child(canvas)

	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)

	_timer_label = Label.new()
	_timer_label.text = "Time: 0.0s"
	_timer_label.add_theme_font_size_override("font_size", 24)

	_timer_label.anchor_left = 1.0
	_timer_label.anchor_top = 1.0
	_timer_label.anchor_right = 1.0
	_timer_label.anchor_bottom = 1.0
	_timer_label.offset_left = -220
	_timer_label.offset_top = -90
	_timer_label.offset_right = -20
	_timer_label.offset_bottom = -50

	ui.add_child(_timer_label)


func _show_hint(text: String) -> void:
	var popup := SILENT_LINK_HINT.instantiate()
	popup.hint_text = text

	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	cl.add_child(popup)


func _check_link_possible() -> bool:
	var total_transceivers: Array = _player_units.duplicate()
	for t in _transceivers:
		if t not in total_transceivers:
			total_transceivers.append(t)

	if total_transceivers.size() < 2:
		return false

	var tx1: Node2D = total_transceivers[0] as Node2D
	var tx2: Node2D = total_transceivers[1] as Node2D
	if tx1 == null or tx2 == null:
		return false

	if tx1.global_position.distance_to(tx2.global_position) < 10.0:
		return false

	var distance: float = tx1.global_position.distance_to(tx2.global_position)
	if distance > 500.0:
		return false

	var freq1: float = float(tx1.get("frequency"))
	var freq2: float = float(tx2.get("frequency"))
	var freq_diff: float = abs(freq1 - freq2)
	if freq_diff > 100.0:
		return false

	return true


func _check_detection_from_sim(detect_results: Array) -> void:
	for result in detect_results:
		if not (result is Dictionary):
			continue
		var sensor = result.get("sensor")
		var target = result.get("target")
		if sensor == null or target == null:
			continue
		if not is_instance_valid(sensor) or not is_instance_valid(target):
			continue
		# Only an ENEMY sensor detecting one of OUR units counts as "caught"
		if not sensor.is_in_group("enemy_units"):
			continue
		if target.is_in_group("enemy_units"):
			continue
		if result.get("fully_detected", false):
			_player_detected = true
			_ever_detected = true
			return


func _check_jamming() -> void:
	for unit in _player_units:
		for enemy in _enemy_units:
			if enemy.has_method("is_jammer") and enemy.is_jammer():
				var dist: float = unit.global_position.distance_to(enemy.global_position)
				var jam_radius: float = 70.0
				if enemy.has_method("jam_radius"):
					jam_radius = float(enemy.jam_radius())
				if dist < jam_radius:
					_jammed = true
					_ever_jammed = true
					return


func register_player_unit(unit: Node) -> void:
	if not _player_units.has(unit):
		_player_units.append(unit)


func unregister_player_unit(unit: Node) -> void:
	if _player_units.has(unit):
		_player_units.erase(unit)


func _show_scoreboard() -> void:
	var score := _calculate_score()
	var minutes := int(_completion_time) / 60
	var seconds := int(_completion_time) % 60

	var popup := SILENT_LINK_INTRO_POPUP.instantiate()
	popup.title_string = "Mission Successful!"
	popup.body_string = (
		"[i]Link established![/i]\n\n"
		+ "[b]Time:[/b] %d:%02d\n" % [minutes, seconds]
		+ "[b]Score:[/b] %d\n" % score
	)

	if _current_level < MAX_LEVEL:
		popup.button_string = "Next Level"
	else:
		popup.button_string = "Finish"

	var cl := CanvasLayer.new()
	cl.layer = 101
	add_child(cl)
	cl.add_child(popup)

	popup.continue_button.pressed.connect(_on_next_level_pressed)


func _calculate_score() -> int:
	var base_score := 1000

	# Time penalty (e.g., 5 points lost per second)
	var time_penalty := int(_completion_time) * 5

	# Unit penalty (e.g., 50 points lost per unit placed)
	var unit_penalty := _player_units.size() * 50

	var stealth_bonus := 0

	# Reward the player if they were NEVER detected across all attempts
	if not _ever_detected:
		stealth_bonus += 150

	# Reward the player if they were NEVER jammed across all attempts
	if not _ever_jammed:
		stealth_bonus += 100

	# Ensure the score never drops below a minimum of 100
	return max(100, base_score - time_penalty - unit_penalty + stealth_bonus)


func _on_next_level_pressed() -> void:
	_current_level += 1

	set_process(false)
	set_physics_process(false)

	# Disconnect signals before scene change to prevent stale callbacks
	if GameEvents.simulation_requested.is_connected(_on_simulation_requested):
		GameEvents.simulation_requested.disconnect(_on_simulation_requested)
	if GameEvents.simulation_complete.is_connected(_on_simulation_complete):
		GameEvents.simulation_complete.disconnect(_on_simulation_complete)

	if _current_level > MAX_LEVEL:
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		return

	get_tree().change_scene_to_file("res://scenes/silent-link/level-%d.tscn" % _current_level)


func _get_level_intro_content(level: int) -> Dictionary:
	match level:
		1:
			return {
				"title": "Silent Link Mode - Level 1",
				"body":
				(
					"Establish a connection between the two friendly transceivers\n"
					+ "without being detected or jammed by the enemy!\n\n"
					+ "[i]• Place your units and link carefully\n"
					+ "• Avoid detection zones & jammers\n"
					+ "• Adjust frequency: high for fast, low for stealth\n\n"
					+ "Start with this basic challenge\n"
					+ "One transceiver has been placed for you![/i]"
				)
			}
		2:
			return {
				"title": "Silent Link Mode - Level 2",
				"body":
				(
					"Things are getting trickier!\n\n"
					+ "[i]More enemy units are now on the field.\n"
					+ "You'll need to plan your link route more carefully\n"
					+ "to avoid their detection zones.\n\n"
					+ "• Study the terrain\n"
					+ "• Use natural barriers to your advantage\n"
					+ "• Timing and frequency adjustment are key![/i]"
				)
			}
		3:
			return {
				"title": "Silent Link Mode - Level 3",
				"body":
				(
					"The enemy has added more units!\n\n"
					+ "[i]Advanced jammers and detection equipment\n"
					+ "make this level significantly more challenging.\n\n"
					+ "• Multiple overlapping detection zones\n"
					+ "• Powerful jamming capabilities\n"
					+ "• Be careful with your units![/i]"
				)
			}
		4:
			return {
				"title": "Silent Link Mode - Level 4",
				"body":
				(
					"Hidden units are on the map!\n\n"
					+ "[i]The enemy now has invisible\n"
					+ "jamming equipment.\n\n"
					+ "• Sensors pulse red, orange, yellow, or blue\n"
					+ "  depending on jammer distance\n"
					+ "• Red is closest, blue means nothing found![/i]"
				)
			}
		5:
			return {
				"title": "Silent Link Mode - Level 5",
				"body":
				(
					"The final challenge awaits!\n\n"
					+ "[i]This is the ultimate test of your skills.\n"
					+ "Multiple hidden jammers have been placed.\n\n"
					+ "• All your skills will be tested\n"
					+ "• Make good use of your sensors\n"
					+ "• Success here means you've mastered Silent Link![/i]"
				)
			}
		_:
			return {"title": "Silent Link Mode", "body": "Unknown level"}


func _generate_terrain(w: int, h: int, seed: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = 1
	noise.frequency = 0.025
	noise.fractal_octaves = 3

	var g: Array = []
	for x in range(w):
		g.append([])
		for y in range(h):
			var n := noise.get_noise_2d(float(x), float(y))
			var h_m := (n + 1.0) * 0.5 * 500.0
			g[x].append(h_m)
	return g

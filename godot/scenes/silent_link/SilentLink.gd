extends Sandbox

# Silent Link Mode Controller - Event-driven state machine matching TutorialController structure

const SILENT_LINK_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")
const SILENT_LINK_HINT := preload("res://scenes/ui/HintPopup.tscn")

const SENSOR_DETECTION_RANGE := 300.0
const SENSOR_PULSE_SPEED := 1.0
const MAX_LEVEL := 5

enum Step { WELCOME, PLANNING, SIMULATING, COMPLETE }

var _step: Step = Step.WELCOME
var _intro_popup_open := false
var _start_time: float = 0.0
var _completion_time: float = 0.0
var _timer_label: Label = null
var _hud: Node = null
var _current_level: int = 1
var _last_hint_time: float = -10.0
var _hint_overlay: DetectionVisual = null

var _link_established := false
var _player_detected := false
var _jammed := false
var _simulation_over := false
var _terrain_blocked := false

# Gameplay entities
var _player_units: Array = []
var _enemy_units: Array = []
var _transceivers: Array = []
var _allowed_units: Array[StringName] = []
var _sensor_visualizations: Dictionary = {}


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

	var hud_nodes = get_tree().get_nodes_in_group("hud")
	if hud_nodes.size() > 0:
		_hud = hud_nodes[0]

	_hint_overlay = DetectionVisual.new()
	_hint_overlay.z_index = 999
	_hint_overlay.z_as_relative = false
	add_child(_hint_overlay)

	_transceivers = get_tree().get_nodes_in_group("transceivers")
	_enemy_units = get_tree().get_nodes_in_group("enemy_units")

	_setup_level_restrictions()
	set_process(true)
	_start()


func _exit_tree() -> void:
	if GameEvents.simulation_requested.is_connected(_on_simulation_requested):
		GameEvents.simulation_requested.disconnect(_on_simulation_requested)
	if GameEvents.simulation_complete.is_connected(_on_simulation_complete):
		GameEvents.simulation_complete.disconnect(_on_simulation_complete)

	_cleanup_sensor_visualizations()


func _process(_delta: float) -> void:
	if _step == Step.PLANNING and _timer_label:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
		_timer_label.text = "Time: %.1fs" % elapsed

	if _current_level >= 4 and (_step == Step.PLANNING or _step == Step.SIMULATING):
		_update_sensor_hints()


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
			_apply_card_restrictions()
			_show_hint("Plan a silent link, then run simulation. Avoid detection and jamming.")

		Step.PLANNING:
			pass

		Step.SIMULATING:
			pass

		Step.COMPLETE:
			_show_scoreboard()


func _setup_level_restrictions() -> void:
	match _current_level:
		1, 2, 3:
			_allowed_units = [&"transceiver"]
		4, 5:
			_allowed_units = [&"transceiver", &"sensor"]
		_:
			_allowed_units = [&"transceiver", &"jammer", &"sensor"]


func _apply_card_restrictions() -> void:
	var sidebar := get_tree().get_first_node_in_group("ui") as Sidebar
	if not sidebar:
		sidebar = get_tree().root.find_child("Sidebar", true, false) as Sidebar
	if not sidebar:
		return

	var entity_types: Array[Dictionary] = [
		{"type": Sidebar.EntityType.TRANSCEIVER, "id": StringName("transceiver")},
		{"type": Sidebar.EntityType.JAMMER, "id": StringName("jammer")},
		{"type": Sidebar.EntityType.SENSOR, "id": StringName("sensor")}
	]

	for entity: Dictionary in entity_types:
		var card = sidebar._entity_cards.get(entity["type"])
		if not card:
			continue

		var id: StringName = entity["id"] as StringName
		var is_allowed: bool = id in _allowed_units

		card.modulate.a = 1.0 if is_allowed else 0.3
		card.set_process_input(is_allowed)
		card.mouse_filter = Control.MOUSE_FILTER_STOP if is_allowed else Control.MOUSE_FILTER_IGNORE

		for child in card.get_children():
			child.mouse_filter = (
				Control.MOUSE_FILTER_PASS if is_allowed else Control.MOUSE_FILTER_IGNORE
			)


func _has_minimum_setup() -> bool:
	# Require at least 2 transceivers total on map (preplaced + player placed)
	var total_transceivers := get_tree().get_nodes_in_group("transceivers").size()
	return total_transceivers >= 2


func _show_hint_debounced(text: String, cooldown: float = 1.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hint_time < cooldown:
		return
	_last_hint_time = now
	_show_hint(text)


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


func _on_simulation_complete(link_results: Array, detect_results: Array) -> void:
	if _step != Step.SIMULATING or _simulation_over:
		return

	if not _has_minimum_setup():
		return

	_player_detected = false
	_jammed = false
	_terrain_blocked = false
	_link_established = false
	_simulation_over = false

	_parse_sim_results_for_flags(link_results, detect_results)

	_update_sensor_hints()

	_check_jamming()
	_check_detection()

	if _terrain_blocked:
		_step = Step.PLANNING
		_show_hint_debounced("Link blocked by terrain! Reposition transceivers and try again.")
		return

	if not _check_link_possible():
		_step = Step.PLANNING
		_show_hint_debounced("Link not possible - adjust transceiver placement/frequency.")
		return

	if _jammed:
		_step = Step.PLANNING
		_show_hint_debounced("Signal jammed! Reposition and try again.")
		return

	if _player_detected:
		_step = Step.PLANNING
		_show_hint_debounced("Detected by enemy! Try a stealthier route.")
		return

	_link_established = true
	_finish(true)


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


func _check_detection() -> void:
	for unit in _player_units:
		for enemy in _enemy_units:
			if _unit_in_detection_zone(unit, enemy):
				_player_detected = true
				return


func _unit_in_detection_zone(unit: Node, enemy: Node) -> bool:
	var dist: float = unit.global_position.distance_to(enemy.global_position)
	var detection_radius: float = 100.0
	if enemy.has_method("detection_radius"):
		detection_radius = float(enemy.detection_radius())
	return dist < detection_radius


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
					return


func register_player_unit(unit: Node) -> void:
	if not _player_units.has(unit):
		_player_units.append(unit)

	if unit.is_in_group("sensors") and _current_level >= 4:
		_sensor_visualizations[unit] = {
			"rings": [], "pulse_time": 0.0, "closest_jammer_distance": INF
		}


func unregister_player_unit(unit: Node) -> void:
	if _player_units.has(unit):
		_player_units.erase(unit)

	if _sensor_visualizations.has(unit):
		for ring in _sensor_visualizations[unit]["rings"]:
			ring.queue_free()
		_sensor_visualizations.erase(unit)


func _update_sensor_hints() -> void:
	if _hint_overlay == null:
		return

	var active_hint_ids: Array[int] = []
	var sensors = get_tree().get_nodes_in_group("sensors")
	var jammers = get_tree().get_nodes_in_group("jammers")

	for sensor in sensors:
		if sensor.name.begins_with("Enemy"):
			continue

		var closest_jammer: Node = null
		var closest_dist := INF

		for jammer in jammers:
			var dist: float = sensor.global_position.distance_to(jammer.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_jammer = jammer

		if closest_jammer == null:
			continue

		if closest_dist > SENSOR_DETECTION_RANGE:
			continue

		var sensor_id: int = sensor.get_instance_id()
		var jammer_id: int = closest_jammer.get_instance_id()
		var hint_id: int = int(str(sensor_id) + str(jammer_id))

		_hint_overlay.set_hint(sensor.global_position, closest_jammer.global_position, hint_id)
		active_hint_ids.append(hint_id)

	_hint_overlay.retain_only(active_hint_ids)


func _cleanup_sensor_visualizations() -> void:
	for sensor in _sensor_visualizations.keys():
		for ring in _sensor_visualizations[sensor]["rings"]:
			if is_instance_valid(ring):
				ring.queue_free()
	_sensor_visualizations.clear()

	if _hint_overlay:
		_hint_overlay.retain_only([])


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
	var time_penalty := int(_completion_time)
	var frequency_penalty := 0
	var stealth_bonus := 0

	for unit in _player_units:
		var freq: float = float(unit.get("frequency"))
		frequency_penalty += int(abs(freq - 2.0) * 200.0)

	if not _player_detected:
		stealth_bonus += 1000
	if not _jammed:
		stealth_bonus += 500

	return max(1000, 10000 - time_penalty * 100 - frequency_penalty + stealth_bonus)


func _on_next_level_pressed() -> void:
	_current_level += 1

	set_process(false)
	set_physics_process(false)
	_cleanup_sensor_visualizations()

	# Disconnect signals before scene change to prevent stale callbacks
	if GameEvents.simulation_requested.is_connected(_on_simulation_requested):
		GameEvents.simulation_requested.disconnect(_on_simulation_requested)
	if GameEvents.simulation_complete.is_connected(_on_simulation_complete):
		GameEvents.simulation_complete.disconnect(_on_simulation_complete)

	if _current_level > MAX_LEVEL:
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		return

	get_tree().change_scene_to_file("res://scenes/silent_link/level-%d.tscn" % _current_level)


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


func _generate_terrain(w: int, h: int) -> Array:
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

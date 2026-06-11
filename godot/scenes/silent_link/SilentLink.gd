extends ContourDemo

# Silent Link Mode Controller – Event-driven state machine for
# "create a link without being detected/jammed"

const SILENT_LINK_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")
const SILENT_LINK_HINT := preload("res://scenes/ui/HintPopup.tscn")

const SENSOR_DETECTION_RANGE := 300.0  # How far sensors can detect jammers
const SENSOR_PULSE_SPEED := 1.0  # How fast the rings pulse

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

# Gameplay entities
var _player_units: Array = []
var _enemy_units: Array = []
var _transceivers: Array = []
var _allowed_units: Array[StringName] = []
var _sensor_visualizations: Dictionary = {}
var _scene_ready := false


func add_to_groups_recursive(node):
	for c in node.get_children():
		if c.name.begins_with("Friendly"):
			c.add_to_group("transceivers")
		elif c.name.begins_with("Enemy"):
			c.add_to_group("enemy_units")
		add_to_groups_recursive(c)


func _ready() -> void:
	super._ready()
	call_deferred("_connect_sim_signal")
	set_process(true)

	add_to_groups_recursive(self)

	# Extract scene level from scene name
	var level_name := get_tree().current_scene.scene_file_path
	var file_name := level_name.get_file().get_basename()
	var parts := file_name.split("-")

	_current_level = int(parts[1]) if parts.size() > 1 else 1
	_setup_level_restrictions()

	var hud_nodes = get_tree().get_nodes_in_group("hud")
	if hud_nodes.size() > 0:
		_hud = hud_nodes[0]

	# Locate (preplaced) transceivers and enemy units
	_transceivers = get_tree().get_nodes_in_group("transceivers")
	_enemy_units = get_tree().get_nodes_in_group("enemy_units")

	_scene_ready = true
	_start()


func _setup_level_restrictions() -> void:
	match _current_level:
		1, 2, 3:
			# Only transceivers allowed
			_allowed_units = [&"transceiver"]
		4, 5:
			# Transceivers and sensors allowed (jammers are invisible)
			_allowed_units = [&"transceiver", &"sensor"]
		_:
			# Default: all units
			_allowed_units = [&"transceiver", &"jammer", &"sensor"]

	# Disable entity cards that aren't allowed
	_apply_card_restrictions()


func _apply_card_restrictions() -> void:
	var sidebar = get_tree().get_first_node_in_group("ui") as Sidebar
	if not sidebar:
		sidebar = get_tree().root.find_child("Sidebar", true, false) as Sidebar

	# Access the entity cards through the sidebar's _entity_cards dictionary
	# We need to disable cards by type
	var entity_types = [
		{"type": Sidebar.EntityType.TRANSCEIVER, "id": &"transceiver"},
		{"type": Sidebar.EntityType.JAMMER, "id": &"jammer"},
		{"type": Sidebar.EntityType.SENSOR, "id": &"sensor"}
	]

	for entity in entity_types:
		var card = sidebar._entity_cards.get(entity["type"])
		if card:
			var is_allowed = entity["id"] in _allowed_units
			card.modulate.a = 1.0 if is_allowed else 0.3
			card.set_process_input(is_allowed)
			card.mouse_filter = Control.MOUSE_FILTER_STOP if is_allowed else Control.MOUSE_FILTER_IGNORE
			for child in card.get_children():
				child.mouse_filter = Control.MOUSE_FILTER_PASS if is_allowed else Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	# Only disconnect if connected (avoids errors)
	if GameEvents.simulation_requested.is_connected(Callable(self, "_begin_simulation")):
		GameEvents.simulation_requested.disconnect(Callable(self, "_begin_simulation"))


func _connect_sim_signal():
	if not GameEvents.simulation_requested.is_connected(Callable(self, "_begin_simulation")):
		GameEvents.simulation_requested.connect(Callable(self, "_begin_simulation"))


func _start() -> void:
	if _intro_popup_open:
		return
	_intro_popup_open = true

	var popup := SILENT_LINK_INTRO_POPUP.instantiate()

	# Set level-specific content based on current level
	var level_content = _get_level_intro_content(_current_level)
	popup.title_string = level_content["title"]
	popup.body_string = level_content["body"]
	popup.button_string = "Begin"

	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	cl.add_child(popup)

	if popup.has_signal("continued"):
		popup.continued.connect(_on_intro_closed)


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
					"Hiiden units are on the map!\n\n"
					+ "[i]The enemy now has invisible\n"
					+ "jamming equipment.\n\n"
					+ "• Sensors will pulse red, orange, yellow, or blue"
					+ " depending on how far the jammer is\n"
					+ "• Red is closest and blue is nothing found![/i]"
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


func _on_intro_closed() -> void:
	_intro_popup_open = false
	_step = Step.PLANNING
	_start_time = Time.get_ticks_msec() / 1000.0
	_show_timer()
	await get_tree().process_frame
	_apply_card_restrictions()


func register_player_unit(unit: Node) -> void:
	if not _player_units.has(unit):
		_player_units.append(unit)

	# Track sensor for visualization
	if unit.is_in_group("sensors") and _current_level >= 4:
		_sensor_visualizations[unit] = {
			"rings": [],
			"pulse_time": 0.0,
			"closest_jammer_distance": INF
		}


func unregister_player_unit(unit: Node) -> void:
	if _player_units.has(unit):
		_player_units.erase(unit)

	# Clean up sensor visualization
	if _sensor_visualizations.has(unit):
		for ring in _sensor_visualizations[unit]["rings"]:
			ring.queue_free()
		_sensor_visualizations.erase(unit)


func _begin_simulation() -> void:
	_player_units = []
	for u in get_tree().get_nodes_in_group("transceivers"):
		if not u.name.begins_with("Friendly"):
			_player_units.append(u)
	_player_detected = false
	_jammed = false
	if _step != Step.PLANNING and _step != Step.COMPLETE:
		return
	_step = Step.SIMULATING
	_simulation_over = false
	_link_established = false
	_simulate_link()


func _process(_delta: float) -> void:
	if _timer_label:
		var elapsed = Time.get_ticks_msec() / 1000.0 - _start_time
		_timer_label.text = "Time: %.1fs" % elapsed

	if _current_level >= 4:
		_update_sensor_visualizations(_delta)

	if _step == Step.SIMULATING and not _simulation_over:
		_check_detection()
		_check_jamming()
		if _link_established and not (_player_detected or _jammed):
			_finish(true)
		elif _player_detected or _jammed:
			_finish(false)


func _update_sensor_visualizations(delta: float) -> void:
	var sensors = get_tree().get_nodes_in_group("sensors")

	for sensor in sensors:
		# Skip enemy sensors (preplaced)
		if sensor.name.begins_with("Enemy"):
			continue

		if not sensor.global_position:
			continue

		# Initialize visualization data if not present
		if not _sensor_visualizations.has(sensor):
			_sensor_visualizations[sensor] = {
				"rings": [],
				"pulse_time": 0.0,
				"closest_jammer_distance": INF
			}

		var vis_data = _sensor_visualizations[sensor]
		vis_data["pulse_time"] += delta

		# Find closest jammer to this sensor
		var closest_distance = INF
		var jammers = get_tree().get_nodes_in_group("jammers")
		for jammer in jammers:
			var dist = sensor.global_position.distance_to(jammer.global_position)
			if dist < closest_distance:
				closest_distance = dist

		vis_data["closest_jammer_distance"] = closest_distance

		# Create or update rings based on detection
		_update_sensor_rings(sensor, vis_data, delta)


func _update_sensor_rings(sensor: Node, vis_data: Dictionary, delta: float) -> void:
	var distance = vis_data["closest_jammer_distance"]
	var ring_count = 3

	# Ensure we have rings
	while vis_data["rings"].size() < ring_count:
		var ring = _create_sensor_ring(sensor)
		vis_data["rings"].append(ring)

	# Update or remove extra rings
	while vis_data["rings"].size() > ring_count:
		vis_data["rings"].pop_back().queue_free()

	# Determine color based on distance
	var ring_color = Color.BLUE  # Default: no jammer nearby
	if distance < SENSOR_DETECTION_RANGE:
		if distance < 100:
			ring_color = Color.RED  # Very close
		elif distance < 200:
			ring_color = Color.ORANGE  # Orange: nearby
		else:
			ring_color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow: somewhat far

	# Animate rings with pulsing effect
	var pulse = sin(vis_data["pulse_time"] * SENSOR_PULSE_SPEED * PI) * 0.5 + 0.5

	for i in range(vis_data["rings"].size()):
		var ring = vis_data["rings"][i]
		var delay = float(i) / float(ring_count)
		var phase = fmod(vis_data["pulse_time"] * SENSOR_PULSE_SPEED + delay, 1.0)
		var alpha = (1.0 - phase) * 0.8  # Fade out as ring expands

		ring.modulate = Color(ring_color.r, ring_color.g, ring_color.b, alpha)
		ring.scale = Vector2.ONE * (0.5 + phase * 1.0)  # Expand from small to large
		ring.global_position = sensor.global_position


func _create_sensor_ring(sensor: Node) -> Node2D:
	var ring = Node2D.new()
	ring.global_position = sensor.global_position
	ring.z_index = 100
	add_child(ring)

	# Create circle using a polygon or multiple line segments
	var circle = Line2D.new()
	circle.width = 2.5
	circle.antialiased = true

	# Draw circle (24 points for smooth circle)
	var segments = 24
	for i in range(segments + 1):
		var angle = (float(i) / float(segments)) * TAU
		var point = Vector2(cos(angle), sin(angle)) * 50.0
		circle.add_point(point)

	ring.add_child(circle)
	return ring


func _finish(success: bool) -> void:
	if _simulation_over:
		return
	set_process(false)
	_simulation_over = true
	_completion_time = Time.get_ticks_msec() / 1000.0 - _start_time
	if success:
		_step = Step.COMPLETE
		_show_scoreboard(success)
	else:
		_step = Step.PLANNING  # allow player to retry


func _simulate_link() -> void:
	# Reset detection/jamming flags
	_player_detected = false
	_jammed = false
	
	if not _check_link_possible():
		_show_hint("Link not possible - check your placements and retry!")
		_finish(false)
		return

	# Always run these to update detection and jamming for this frame
	_check_jamming()
	_check_detection()

	if _jammed:
		_show_hint("Signal jammed! Try again.")
		_finish(false)
		return
	if _player_detected:
		_show_hint("Detected by enemy! Try again.")
		_finish(false)
		return

	# Only succeed if not jammed OR detected
	_link_established = true
	_finish(true)


func _advance() -> void:
	match _step:
		Step.WELCOME:
			_show_timer()
			_step = Step.PLANNING
		Step.PLANNING:
			_start_time = Time.get_ticks_msec() / 1000.0
		Step.SIMULATING:
			# Start simulation, check detection/jamming every frame
			_simulate_link()
		Step.COMPLETE:
			_show_scoreboard()


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


func _unit_is_jammed(unit: Node) -> bool:
	for enemy in _enemy_units:
		if enemy.has_method("is_jammer") and enemy.is_jammer():
			var dist = unit.global_position.distance_to(enemy.global_position)
			var jam_radius = 70
			if enemy.has_method("jam_radius"):
				jam_radius = enemy.jam_radius()
			if dist < jam_radius:
				return true
	return false


func _check_link_possible() -> bool:
	# Must have at least 2 transceivers total (preplaced + player)
	var total_transceivers = _player_units.duplicate()
	for t in _transceivers:
		if t not in total_transceivers:
			total_transceivers.append(t)
	if total_transceivers.size() < 2:
		return false

	# Check if at least two transceivers can link (basic checks)
	if total_transceivers.size() >= 2:
		var tx1 = total_transceivers[0]
		var tx2 = total_transceivers[1]

		# Make sure they're not at the same position
		if tx1.global_position.distance_to(tx2.global_position) < 10:
			return false

		# Check distance (max range ~500 pixels based on typical signal range)
		var distance = tx1.global_position.distance_to(tx2.global_position)
		if distance > 500:
			return false

		# Check if frequencies match or are close enough
		var freq_diff = abs(tx1.frequency - tx2.frequency)
		if freq_diff > 100:  # Simple frequency check
			return false

	return true


func _check_detection() -> void:
	for unit in _player_units:
		for enemy in _enemy_units:
			if _unit_in_detection_zone(unit, enemy):
				_player_detected = true
				return


func _unit_in_detection_zone(unit: Node, enemy: Node) -> bool:
	var dist = unit.global_position.distance_to(enemy.global_position)
	var detection_radius = 100
	if enemy.has_method("detection_radius"):
		detection_radius = enemy.detection_radius()
	return dist < detection_radius


func _check_jamming() -> void:
	for unit in _player_units:
		for enemy in _enemy_units:
			if enemy.has_method("is_jammer") and enemy.is_jammer():
				var dist = unit.global_position.distance_to(enemy.global_position)
				var jam_radius = 70
				if enemy.has_method("jam_radius"):
					jam_radius = enemy.jam_radius()
				if dist < jam_radius:
					_jammed = true
					return


func _show_scoreboard(success: bool = true) -> void:
	var score = _calculate_score(success)
	var minutes = int(_completion_time) / 60
	var seconds = int(_completion_time) % 60

	var popup = SILENT_LINK_INTRO_POPUP.instantiate()
	if success:
		popup.title_string = "Mission Successful!"
		popup.body_string = (
			"[i]Link established![/i]\n\n"
			+ "[b]Time:[/b] %d:%02d\n" % [minutes, seconds]
			+ "[b]Score:[/b] %d\n" % score
		)

	if success and _current_level < MAX_LEVEL:
		popup.button_string = "Next Level"
	else:
		popup.button_string = "Finish"

	var cl := CanvasLayer.new()
	cl.layer = 101
	add_child(cl)
	cl.add_child(popup)

	popup.continue_button.pressed.connect(_on_next_level_pressed)


func _calculate_score(success: bool = true) -> int:
	if not success:
		return 0

	var time_penalty = int(_completion_time)
	var frequency_penalty = 0
	var stealth_bonus = 0

	for unit in _player_units:
		var freq = unit.frequency
		# figure out distance penalty
		if freq < 2:
			frequency_penalty += 200
		elif freq > 2:
			frequency_penalty += 200

	if not _player_detected:
		stealth_bonus += 1000

	if not _jammed:
		stealth_bonus += 500

	return max(1000, 10000 - time_penalty * 100 - frequency_penalty + stealth_bonus)


func _on_next_level_pressed() -> void:
	_current_level += 1
	set_process(false)
	set_physics_process(false)

	# Clean up sensor visualizations
	for sensor in _sensor_visualizations:
		for ring in _sensor_visualizations[sensor]["rings"]:
			ring.queue_free()
	_sensor_visualizations.clear()

	if _current_level > MAX_LEVEL:
		# Show completion screen for finishing Silent Link
		_show_completion_screen()
		return

	get_tree().change_scene_to_file("res://scenes/silent_link/level-%d.tscn" % _current_level)


func _show_completion_screen() -> void:
	var popup = SILENT_LINK_INTRO_POPUP.instantiate()
	popup.title_string = "Silent Link Campaign Complete!"
	popup.body_string = (
		"[b]Congratulations![/b]\n\n"
		+ "You have successfully completed all 5 levels of Silent Link Mode\n"
		+ "[i]Try out other game modes to learn more[/i]"
	)
	popup.button_string = "Return to Menu"

	var cl := CanvasLayer.new()
	cl.layer = 101
	add_child(cl)
	cl.add_child(popup)

	popup.continue_button.pressed.connect(_on_finish_pressed)


func _on_finish_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

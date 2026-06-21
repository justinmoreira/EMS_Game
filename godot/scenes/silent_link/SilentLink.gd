extends ContourDemo

# Silent Link Mode Controller – event-driven state machine for
# "create a link without being detected/jammed"

const SILENT_LINK_INTRO_POPUP := preload("res://scenes/ui/IntroPopup.tscn")
const SILENT_LINK_HINT := preload("res://scenes/ui/HintPopup.tscn")

const SENSOR_DETECTION_RANGE := 300.0
const SENSOR_PULSE_SPEED := 1.0
const MAX_LEVEL := 5

enum Step { WELCOME, PLANNING, SIMULATING, COMPLETE }

var _step: Step = Step.WELCOME
var _intro_popup_open := false
var _scene_ready := false

var _start_time := 0.0
var _completion_time := 0.0
var _timer_label: Label = null
var _hud: Node = null

var _current_level := 1
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


func add_to_groups_recursive(node: Node) -> void:
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

	# Parse level from current scene filename: level-<N>.tscn
	var level_path := get_tree().current_scene.scene_file_path
	var file_name := level_path.get_file().get_basename()
	var parts := file_name.split("-")
	_current_level = int(parts[1]) if parts.size() > 1 else 1

	_setup_level_restrictions()

	var hud_nodes := get_tree().get_nodes_in_group("hud")
	if hud_nodes.size() > 0:
		_hud = hud_nodes[0]

	_transceivers = get_tree().get_nodes_in_group("transceivers")
	_enemy_units = get_tree().get_nodes_in_group("enemy_units")

	_scene_ready = true
	_start()


func _exit_tree() -> void:
	if GameEvents.simulation_requested.is_connected(Callable(self, "_begin_simulation")):
		GameEvents.simulation_requested.disconnect(Callable(self, "_begin_simulation"))

	_cleanup_sensor_visualizations()


func _connect_sim_signal() -> void:
	if not GameEvents.simulation_requested.is_connected(Callable(self, "_begin_simulation")):
		GameEvents.simulation_requested.connect(Callable(self, "_begin_simulation"))


func _setup_level_restrictions() -> void:
	match _current_level:
		1, 2, 3:
			_allowed_units = [&"transceiver"]
		4, 5:
			# Jammers are hidden in these levels, so player gets sensors.
			_allowed_units = [&"transceiver", &"sensor"]
		_:
			_allowed_units = [&"transceiver", &"jammer", &"sensor"]

	_apply_card_restrictions()


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
			child.mouse_filter = Control.MOUSE_FILTER_PASS if is_allowed else Control.MOUSE_FILTER_IGNORE


func _start() -> void:
	if _intro_popup_open:
		return

	_intro_popup_open = true
	var popup := SILENT_LINK_INTRO_POPUP.instantiate()

	var level_content := _get_level_intro_content(_current_level)
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


func _on_intro_closed() -> void:
	_intro_popup_open = false
	_step = Step.PLANNING
	_start_time = Time.get_ticks_msec() / 1000.0
	_show_timer()
	await get_tree().process_frame
	_apply_card_restrictions()


func _process(delta: float) -> void:
	if _timer_label and (_step == Step.PLANNING or _step == Step.SIMULATING):
		var elapsed := Time.get_ticks_msec() / 1000.0 - _start_time
		_timer_label.text = "Time: %.1fs" % elapsed

	if _current_level >= 4:
		_update_sensor_visualizations(delta)


func _begin_simulation() -> void:
	if _step != Step.PLANNING and _step != Step.COMPLETE:
		return

	# Player units = placed transceivers/sensors/etc. (exclude preplaced Friendly*)
	_player_units.clear()
	for u in get_tree().get_nodes_in_group("transceivers"):
		if not u.name.begins_with("Friendly"):
			_player_units.append(u)

	_player_detected = false
	_jammed = false
	_link_established = false
	_simulation_over = false
	_step = Step.SIMULATING

	_simulate_link()


func _simulate_link() -> void:
	if _simulation_over:
		return

	_player_detected = false
	_jammed = false
	_link_established = false

	if not _check_link_possible():
		_show_hint("Link not possible - check your placements and retry!")
		_finish(false)
		return

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

	_link_established = true
	_finish(true)


func _finish(success: bool) -> void:
	if _simulation_over:
		return

	_simulation_over = true
	_completion_time = Time.get_ticks_msec() / 1000.0 - _start_time

	if success:
		_step = Step.COMPLETE
		_show_scoreboard(true)
	else:
		_step = Step.PLANNING


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


func register_player_unit(unit: Node) -> void:
	if not _player_units.has(unit):
		_player_units.append(unit)

	if unit.is_in_group("sensors") and _current_level >= 4:
		_sensor_visualizations[unit] = {
			"rings": [],
			"pulse_time": 0.0,
			"closest_jammer_distance": INF
		}


func unregister_player_unit(unit: Node) -> void:
	if _player_units.has(unit):
		_player_units.erase(unit)

	if _sensor_visualizations.has(unit):
		for ring in _sensor_visualizations[unit]["rings"]:
			ring.queue_free()
		_sensor_visualizations.erase(unit)


func _update_sensor_visualizations(delta: float) -> void:
	var sensors = get_tree().get_nodes_in_group("sensors")

	for sensor in sensors:
		if sensor.name.begins_with("Enemy"):
			continue
		if not sensor.global_position:
			continue

		if not _sensor_visualizations.has(sensor):
			_sensor_visualizations[sensor] = {
				"rings": [],
				"pulse_time": 0.0,
				"closest_jammer_distance": INF
			}

		var vis_data: Dictionary = _sensor_visualizations[sensor]
		vis_data["pulse_time"] = float(vis_data["pulse_time"]) + delta

		var closest_distance: float = INF
		var jammers = get_tree().get_nodes_in_group("jammers")
		for jammer in jammers:
			var dist: float = sensor.global_position.distance_to(jammer.global_position)
			if dist < closest_distance:
				closest_distance = dist

		vis_data["closest_jammer_distance"] = closest_distance
		_update_sensor_rings(sensor, vis_data)


func _update_sensor_rings(sensor: Node, vis_data: Dictionary) -> void:
	var distance: float = float(vis_data["closest_jammer_distance"])
	var ring_count := 3

	while vis_data["rings"].size() < ring_count:
		vis_data["rings"].append(_create_sensor_ring(sensor))

	while vis_data["rings"].size() > ring_count:
		(vis_data["rings"].pop_back() as Node).queue_free()

	var ring_color := Color.BLUE
	if distance < SENSOR_DETECTION_RANGE:
		if distance < 100.0:
			ring_color = Color.RED
		elif distance < 200.0:
			ring_color = Color.ORANGE
		else:
			ring_color = Color(1.0, 1.0, 0.0, 1.0)

	for i in range(vis_data["rings"].size()):
		var ring: Node2D = vis_data["rings"][i] as Node2D
		var delay: float = float(i) / float(ring_count)
		var phase: float = fmod(float(vis_data["pulse_time"]) * SENSOR_PULSE_SPEED + delay, 1.0)
		var alpha: float = (1.0 - phase) * 0.8

		ring.modulate = Color(ring_color.r, ring_color.g, ring_color.b, alpha)
		ring.scale = Vector2.ONE * (0.5 + phase)
		ring.global_position = sensor.global_position


func _create_sensor_ring(sensor: Node) -> Node2D:
	var ring := Node2D.new()
	ring.global_position = sensor.global_position
	ring.z_index = 100
	add_child(ring)

	var circle := Line2D.new()
	circle.width = 2.5
	circle.antialiased = true

	var segments := 24
	for i in range(segments + 1):
		var angle := (float(i) / float(segments)) * TAU
		var point := Vector2(cos(angle), sin(angle)) * 50.0
		circle.add_point(point)

	ring.add_child(circle)
	return ring


func _cleanup_sensor_visualizations() -> void:
	for sensor in _sensor_visualizations.keys():
		for ring in _sensor_visualizations[sensor]["rings"]:
			if is_instance_valid(ring):
				ring.queue_free()
	_sensor_visualizations.clear()


func _unit_is_jammed(unit: Node) -> bool:
	for enemy in _enemy_units:
		if enemy.has_method("is_jammer") and enemy.is_jammer():
			var dist: float = unit.global_position.distance_to(enemy.global_position)
			var jam_radius: float = 70.0
			if enemy.has_method("jam_radius"):
				jam_radius = float(enemy.jam_radius())
			if dist < jam_radius:
				return true
	return false


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


func _show_scoreboard(success: bool = true) -> void:
	var popup = SILENT_LINK_INTRO_POPUP.instantiate()

	if success:
		var score := _calculate_score(true)
		var minutes := int(_completion_time) / 60
		var seconds := int(_completion_time) % 60

		popup.title_string = "Mission Successful!"
		popup.body_string = (
			"[i]Link established![/i]\n\n"
			+ "[b]Time:[/b] %d:%02d\n" % [minutes, seconds]
			+ "[b]Score:[/b] %d\n" % score
		)
	else:
		popup.title_string = "Mission Failed"
		popup.body_string = "Try adjusting placement, frequency, or route and run again."

	if success and _current_level < MAX_LEVEL:
		popup.button_string = "Next Level"
	else:
		popup.button_string = "Finish"

	var cl := CanvasLayer.new()
	cl.layer = 101
	add_child(cl)
	cl.add_child(popup)

	if popup.continue_button:
		if popup.continue_button.pressed.is_connected(_on_next_level_pressed):
			popup.continue_button.pressed.disconnect(_on_next_level_pressed)
		popup.continue_button.pressed.connect(_on_next_level_pressed)


func _calculate_score(success: bool = true) -> int:
	if not success:
		return 0

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
	set_process(false)
	set_physics_process(false)
	_cleanup_sensor_visualizations()

	_current_level += 1
	if _current_level > MAX_LEVEL:
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

	if popup.continue_button:
		if popup.continue_button.pressed.is_connected(_on_finish_pressed):
			popup.continue_button.pressed.disconnect(_on_finish_pressed)
		popup.continue_button.pressed.connect(_on_finish_pressed)


func _on_finish_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

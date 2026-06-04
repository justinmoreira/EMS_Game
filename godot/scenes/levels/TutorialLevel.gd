extends "res://scenes/levels/ContourDemo.gd"

const TUTORIAL_HINT_POPUP := preload("res://scenes/ui/TutorialHintPopup.tscn")
const TUTORIAL_COMPLETION_POPUP := preload("res://scenes/ui/TutorialCompletionPopup.tscn")

const TUTORIAL_TERRAIN_SEED := 12345
const TUTORIAL_FREQUENCY := 1000.0
const TUTORIAL_SENSOR_SENSITIVITY := 1.0
const FREQUENCY_TOLERANCE := 5.0
const PLACEMENT_TOLERANCE := 75.0
const MOVE_TARGET_TOLERANCE := 50.0

const FIRST_TRANSCEIVER_POS := Vector2(500, 260)
const FIRST_TRANSCEIVER_GREEN_POS := Vector2(650, 260)
const SECOND_TRANSCEIVER_POS := Vector2(750, 260)
const SENSOR_POS := Vector2(630, 290)
const JAMMER_POS := Vector2(690, 180)

enum TutorialStep {
	WELCOME,
	INTRO_MAP,
	PLACE_FIRST_TRANSCEIVER,
	FIRST_TRANSCEIVER_PLACED,
	PLACE_SECOND_TRANSCEIVER,
	EXPLAIN_LINK,
	EXPLAIN_BANDWIDTH_PENALTY,
	MOVE_FIRST_TRANSCEIVER_CLOSER,
	EXPLAIN_SUCCESSFUL_LINK,
	SELECT_TRANSCEIVER,
	EXPLAIN_FREQUENCY,
	CHANGE_FREQUENCY_AWAY,
	CHANGE_FREQUENCY_BACK,
	EXPLAIN_POWER,
	LOWER_POWER,
	RAISE_POWER,
	EXPLAIN_HEIGHT,
	INCREASE_HEIGHT,
	INTRO_SENSOR,
	PLACE_SENSOR,
	EXPLAIN_SENSOR_SENSITIVITY,
	LOWER_SENSOR_SENSITIVITY,
	EXPLAIN_SENSOR_TUNING,
	CHANGE_SENSOR_TUNING_AWAY,
	EXPLAIN_BANDWIDTH,
	INCREASE_BANDWIDTH,
	INTRO_JAMMER,
	PLACE_JAMMER,
	CHANGE_JAMMER_FREQUENCY_AWAY,
	CHANGE_JAMMER_FREQUENCY_BACK,
	COMPLETE
}

var _tutorial_step: TutorialStep = TutorialStep.WELCOME

var _first_transceiver: Node = null
var _second_transceiver: Node = null
var _sensor: Node = null
var _jammer: Node = null
var _selected_tutorial_unit: Node = null
var _pending_placement_unit: Node = null

var _original_power := 10.0
var _original_height := 10.0
var _original_sensor_tuning := TUTORIAL_FREQUENCY

var _frequency_went_outside_range := false

var _placement_marker: Control = null
var _completion_popup: Control = null

# Stores every tutorial hint so the player can review earlier popups
# without changing or undoing the current tutorial step.
var _popup_history: Array[Dictionary] = []
var _popup_history_index := -1

var _lock_transceiver_frequency := false
var _lock_sensor_sensitivity := false
var _lock_jammer_frequency := false


func _ready() -> void:
	super._ready()

	if not GameEvents.unit_placed.is_connected(_on_tutorial_unit_placed):
		GameEvents.unit_placed.connect(_on_tutorial_unit_placed)

	if not GameEvents.unit_selected.is_connected(_on_tutorial_unit_selected):
		GameEvents.unit_selected.connect(_on_tutorial_unit_selected)

	if not GameEvents.unit_attribute_changed.is_connected(_on_tutorial_attribute_changed):
		GameEvents.unit_attribute_changed.connect(_on_tutorial_attribute_changed)

	_enter_step(TutorialStep.WELCOME)


func _process(_delta: float) -> void:
	_check_pending_placement()
	_check_transceiver_move_target()

	if _lock_transceiver_frequency:
		_lock_transceiver_frequencies()

	if _lock_sensor_sensitivity:
		_set_number_on_unit(
			_sensor, ["sensitivity", "detection_sensitivity"], TUTORIAL_SENSOR_SENSITIVITY
		)

	if _lock_jammer_frequency:
		_set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)


func _generate_terrain(w: int, h: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = TUTORIAL_TERRAIN_SEED
	noise.frequency = 0.025
	noise.fractal_octaves = 3

	var grid: Array = []
	for x in range(w):
		grid.append([])
		for y in range(h):
			var n := noise.get_noise_2d(float(x), float(y))
			grid[x].append((n + 1.0) * 0.5 * 500.0)

	return grid


func _enter_step(step: TutorialStep) -> void:
	_tutorial_step = step

	match step:
		TutorialStep.WELCOME:
			_setup()
			_say(
				[
					"Welcome to Tutorial Mode.\n\n",
					"This mode teaches the basics of Gamify EMS. ",
					"You will place units, edit attributes, create links, ",
					"detect signals, and see how jammers affect communication."
				],
				TutorialStep.INTRO_MAP
			)

		TutorialStep.INTRO_MAP:
			_setup()
			_say(
				[
					"This is the simulation map.\n\n",
					"Units can be placed on the map to represent ",
					"communication equipment, sensors, and jammers. ",
					"Position matters because distance affects signal strength."
				],
				TutorialStep.PLACE_FIRST_TRANSCEIVER
			)

		TutorialStep.PLACE_FIRST_TRANSCEIVER:
			_setup(
				[Sidebar.EntityType.TRANSCEIVER], [], FIRST_TRANSCEIVER_POS, "Place\nTransceiver 1"
			)
			_say(["Place a Transceiver inside the highlighted area."])

		TutorialStep.FIRST_TRANSCEIVER_PLACED:
			_setup()
			_say(
				[
					"Good. You placed your first Transceiver.\n\n",
					"Transceivers have frequency, power, bandwidth, ",
					"and height settings. These values affect communication."
				],
				TutorialStep.PLACE_SECOND_TRANSCEIVER
			)

		TutorialStep.PLACE_SECOND_TRANSCEIVER:
			_setup(
				[Sidebar.EntityType.TRANSCEIVER], [], SECOND_TRANSCEIVER_POS, "Place\nTransceiver 2"
			)
			_say(["Now place a second Transceiver inside the highlighted area."])

		TutorialStep.EXPLAIN_LINK:
			_setup()
			_run_simulation_if_possible()
			_say(
				[
					"The two Transceivers are trying to communicate.\n\n",
					"Green means the connection is successful.\n",
					"Orange means the signal is too weak or out of range.\n",
					"Red means the connection may be jammed.\n",
					"Purple means there is a bandwidth penalty.\n",
					"Blue means the units are using different frequency ranges."
				],
				TutorialStep.EXPLAIN_BANDWIDTH_PENALTY
			)

		TutorialStep.EXPLAIN_BANDWIDTH_PENALTY:
			_setup()
			_run_simulation_if_possible()
			_say(
				[
					"The purple line shows a bandwidth penalty.\n\n",
					"Bandwidth is the range of frequencies around the ",
					"main frequency. A wider bandwidth can carry more ",
					"information, but it can also make the signal less clean.",
					"\n\nAcceptable frequency differences in this simulation:",
					"\nNarrow | 1 MHz | ±0.5 MHz",
					"\nMedium | 10 MHz | ±5 MHz",
					"\nWide | 50 MHz | ±25 MHz"
				],
				TutorialStep.MOVE_FIRST_TRANSCEIVER_CLOSER
			)

		TutorialStep.MOVE_FIRST_TRANSCEIVER_CLOSER:
			_setup([], [], FIRST_TRANSCEIVER_GREEN_POS, "Move\nTransceiver 1")
			_say(
				[
					"Move Transceiver 1 into the new highlighted area.\n\n",
					"Moving the Transceiver closer should improve the signal ",
					"and create a green connection line."
				]
			)

		TutorialStep.EXPLAIN_SUCCESSFUL_LINK:
			_setup()
			_run_simulation_if_possible()
			_say(
				[
					"Good. The green line means the connection worked.\n\n",
					"The units are now close enough, their settings match, ",
					"and the signal is strong enough to communicate."
				],
				TutorialStep.SELECT_TRANSCEIVER
			)

		TutorialStep.SELECT_TRANSCEIVER:
			_setup()
			_say(
				[
					"Click one of the Transceivers to view its attributes.\n\n",
					"The attribute panel lets you edit frequency, power, ",
					"bandwidth, and antenna height."
				],
				TutorialStep.EXPLAIN_FREQUENCY
			)

		TutorialStep.EXPLAIN_FREQUENCY:
			_setup([], ["frequency"])
			_pick_default_transceiver()
			_frequency_went_outside_range = false
			_lock_transceiver_frequency = false
			_lock_transceiver_frequencies()
			_run_simulation_if_possible()
			_say(
				[
					"Frequency controls what channel the unit uses.\n\n",
					"The Transceivers currently use Medium bandwidth. ",
					"In this simulation, Medium bandwidth allows a ",
					"frequency difference of plus or minus 5."
				],
				TutorialStep.CHANGE_FREQUENCY_AWAY
			)

		TutorialStep.CHANGE_FREQUENCY_AWAY:
			_setup([], ["frequency"])
			_say(
				[
					"Move one Transceiver frequency outside the matching ",
					"range.\n\n",
					"Set it below 995 or above 1005. The connection should ",
					"turn blue because the frequency ranges no longer match."
				]
			)

		TutorialStep.CHANGE_FREQUENCY_BACK:
			_setup([], ["frequency"])
			_say(
				[
					"Now move the frequency back inside the matching range.\n\n",
					"Set it between 995 and 1005 to restore the connection."
				]
			)

		TutorialStep.EXPLAIN_POWER:
			_setup([], ["power"])
			_original_power = _read_number_from_unit(_selected_tutorial_unit, ["power"], 10.0)
			_say(
				[
					"Power affects signal strength.\n\n",
					"Higher power can help a signal travel farther, ",
					"but it may also make the unit easier to detect."
				],
				TutorialStep.LOWER_POWER
			)

		TutorialStep.LOWER_POWER:
			_setup([], ["power"])
			_say(["Lower the Transceiver power and watch the link change."])

		TutorialStep.RAISE_POWER:
			_setup([], ["power"])
			_say(["Now raise the power again to help restore the link."])

		TutorialStep.EXPLAIN_HEIGHT:
			_setup([], ["height"])
			_original_height = _read_number_from_unit(_selected_tutorial_unit, ["height"], 10.0)
			_say(
				[
					"Antenna height can also affect communication.\n\n",
					"A taller antenna can improve signal performance ",
					"by giving the unit a better transmission path."
				],
				TutorialStep.INCREASE_HEIGHT
			)

		TutorialStep.INCREASE_HEIGHT:
			_setup([], ["height"])
			_say(["Increase the antenna height of one Transceiver."])

		TutorialStep.INTRO_SENSOR:
			_setup([Sidebar.EntityType.SENSOR])
			_say(
				[
					"Sensors are used to detect signals.\n\n",
					"A Sensor does not create a communication link. ",
					"It listens for nearby transmissions."
				],
				TutorialStep.PLACE_SENSOR
			)

		TutorialStep.PLACE_SENSOR:
			_setup([Sidebar.EntityType.SENSOR], [], SENSOR_POS, "Place\nSensor")
			_say(["Place a Sensor inside the highlighted area."])

		TutorialStep.EXPLAIN_SENSOR_SENSITIVITY:
			_setup([], ["sensitivity", "detection_sensitivity"])
			_say(
				[
					"Sensitivity controls how easily a Sensor detects signals.",
					"\n\nSet the Sensor sensitivity to 1. The tutorial will ",
					"lock it there for consistency."
				],
				TutorialStep.LOWER_SENSOR_SENSITIVITY
			)

		TutorialStep.LOWER_SENSOR_SENSITIVITY:
			_setup([], ["sensitivity", "detection_sensitivity"])
			_say(["Set the Sensor sensitivity to 1."])

		TutorialStep.EXPLAIN_SENSOR_TUNING:
			_setup([], ["tuning_frequency"])
			_original_sensor_tuning = _read_number_from_unit(
				_sensor, ["tuning_frequency"], TUTORIAL_FREQUENCY
			)
			_say(
				[
					"A Sensor has tuning frequency and bandwidth.\n\n",
					"Tuning frequency is what the Sensor listens for. ",
					"Bandwidth controls how wide the listening range is."
				],
				TutorialStep.CHANGE_SENSOR_TUNING_AWAY
			)

		TutorialStep.CHANGE_SENSOR_TUNING_AWAY:
			_setup([], ["tuning_frequency"])
			_say(["Move the Sensor tuning frequency away from 1000."])

		TutorialStep.EXPLAIN_BANDWIDTH:
			_setup([], ["bandwidth"])
			_say(
				[
					"Bandwidth controls how flexible detection is.\n\n",
					"A wider bandwidth can detect a wider frequency range."
				],
				TutorialStep.INCREASE_BANDWIDTH
			)

		TutorialStep.INCREASE_BANDWIDTH:
			_setup([], ["bandwidth"])
			_say(["Increase the Sensor bandwidth."])

		TutorialStep.INTRO_JAMMER:
			_setup([Sidebar.EntityType.JAMMER])
			_say(
				[
					"Jammers interfere with communication.\n\n",
					"A Jammer can weaken or break a link if its frequency ",
					"overlaps with the Transceivers."
				],
				TutorialStep.PLACE_JAMMER
			)

		TutorialStep.PLACE_JAMMER:
			_setup([Sidebar.EntityType.JAMMER], [], JAMMER_POS, "Place\nJammer")
			_say(["Place the Jammer inside the highlighted area."])

		TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY:
			_setup([], ["frequency"])
			_lock_jammer_frequency = false
			_set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
			_run_simulation_if_possible()
			_say(
				[
					"A Jammer works best when its frequency overlaps ",
					"the target.\n\n",
					"Move the Jammer frequency away from 1000."
				]
			)

		TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK:
			_setup([], ["frequency"])
			_say(["Now move the Jammer frequency back to 1000."])

		TutorialStep.COMPLETE:
			_setup()
			_show_completion_popup()


func _on_tutorial_unit_placed(unit: Node) -> void:
	match _tutorial_step:
		TutorialStep.PLACE_FIRST_TRANSCEIVER:
			if _is_transceiver(unit):
				_handle_placement(unit, FIRST_TRANSCEIVER_POS, "Transceiver 1")

		TutorialStep.PLACE_SECOND_TRANSCEIVER:
			if _is_transceiver(unit):
				_handle_placement(unit, SECOND_TRANSCEIVER_POS, "Transceiver 2")

		TutorialStep.PLACE_SENSOR:
			if _is_sensor(unit):
				_handle_placement(unit, SENSOR_POS, "Sensor")

		TutorialStep.PLACE_JAMMER:
			if _is_jammer(unit):
				_handle_placement(unit, JAMMER_POS, "Jammer")

		_:
			pass


func _handle_placement(unit: Node, target_position: Vector2, label_text: String) -> void:
	if _is_near_target(unit, target_position):
		_accept_placement(unit)
		return

	_pending_placement_unit = unit
	_show_wrong_placement_popup(label_text)


func _check_pending_placement() -> void:
	if intro_popup_open:
		return

	if _pending_placement_unit == null:
		return

	if not is_instance_valid(_pending_placement_unit):
		_pending_placement_unit = null
		return

	match _tutorial_step:
		TutorialStep.PLACE_FIRST_TRANSCEIVER:
			if _is_near_target(_pending_placement_unit, FIRST_TRANSCEIVER_POS):
				_accept_placement(_pending_placement_unit)

		TutorialStep.PLACE_SECOND_TRANSCEIVER:
			if _is_near_target(_pending_placement_unit, SECOND_TRANSCEIVER_POS):
				_accept_placement(_pending_placement_unit)

		TutorialStep.PLACE_SENSOR:
			if _is_near_target(_pending_placement_unit, SENSOR_POS):
				_accept_placement(_pending_placement_unit)

		TutorialStep.PLACE_JAMMER:
			if _is_near_target(_pending_placement_unit, JAMMER_POS):
				_accept_placement(_pending_placement_unit)

		_:
			_pending_placement_unit = null


func _check_transceiver_move_target() -> void:
	if intro_popup_open:
		return

	if _tutorial_step != TutorialStep.MOVE_FIRST_TRANSCEIVER_CLOSER:
		return

	if _first_transceiver == null:
		return

	if not is_instance_valid(_first_transceiver):
		return

	if _is_near_target(_first_transceiver, FIRST_TRANSCEIVER_GREEN_POS, MOVE_TARGET_TOLERANCE):
		_run_simulation_if_possible()
		_enter_step(TutorialStep.EXPLAIN_SUCCESSFUL_LINK)


func _accept_placement(unit: Node) -> void:
	_pending_placement_unit = null

	match _tutorial_step:
		TutorialStep.PLACE_FIRST_TRANSCEIVER:
			_first_transceiver = unit
			_run_simulation_if_possible()
			_enter_step(TutorialStep.FIRST_TRANSCEIVER_PLACED)

		TutorialStep.PLACE_SECOND_TRANSCEIVER:
			_second_transceiver = unit
			_run_simulation_if_possible()
			_enter_step(TutorialStep.EXPLAIN_LINK)

		TutorialStep.PLACE_SENSOR:
			_sensor = unit
			_run_simulation_if_possible()
			_enter_step(TutorialStep.EXPLAIN_SENSOR_SENSITIVITY)

		TutorialStep.PLACE_JAMMER:
			_jammer = unit
			_run_simulation_if_possible()
			_enter_step(TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY)

		_:
			pass


func _on_tutorial_unit_selected(unit: Node) -> void:
	if unit == null:
		return

	_selected_tutorial_unit = unit

	if _tutorial_step == TutorialStep.SELECT_TRANSCEIVER and _is_transceiver(unit):
		_enter_step(TutorialStep.EXPLAIN_FREQUENCY)


func _on_tutorial_attribute_changed(
	_unit: Node, attribute_name: String, new_value: Variant
) -> void:
	var attr := attribute_name.to_lower()
	var value := _variant_to_float(new_value, 0.0)

	match _tutorial_step:
		TutorialStep.LOWER_SENSOR_SENSITIVITY:
			if attr.contains("sensitivity"):
				_lock_sensor_sensitivity = true
				_run_simulation_if_possible()
				_say(
					["Good. The Sensor sensitivity is now locked to 1."],
					TutorialStep.EXPLAIN_SENSOR_TUNING
				)

		TutorialStep.CHANGE_FREQUENCY_AWAY:
			if attr.contains("freq") and _outside_match_range(value):
				_frequency_went_outside_range = true
				_run_simulation_if_possible()
				_say(
					[
						"Good. The connection is blue because the ",
						"frequency is outside the matching range.\n\n",
						"Now move it back between 995 and 1005."
					],
					TutorialStep.CHANGE_FREQUENCY_BACK
				)

		TutorialStep.CHANGE_FREQUENCY_BACK:
			if attr.contains("freq") and _inside_match_range(value):
				if _frequency_went_outside_range:
					_lock_transceiver_frequency = true
					_lock_transceiver_frequencies()
					_run_simulation_if_possible()
					_say(
						[
							"Good. The Transceivers are back inside the ",
							"matching frequency range."
						],
						TutorialStep.EXPLAIN_POWER
					)

		TutorialStep.LOWER_POWER:
			if attr.contains("power") and value < _original_power:
				_run_simulation_if_possible()
				_enter_step(TutorialStep.RAISE_POWER)

		TutorialStep.RAISE_POWER:
			if attr.contains("power") and value >= _original_power:
				_run_simulation_if_possible()
				_say(
					["Good. Increasing power helped restore the link."], TutorialStep.EXPLAIN_HEIGHT
				)

		TutorialStep.INCREASE_HEIGHT:
			if attr.contains("height") and value > _original_height:
				_run_simulation_if_possible()
				_say(
					["Good. Increasing height can improve communication."],
					TutorialStep.INTRO_SENSOR
				)

		TutorialStep.CHANGE_SENSOR_TUNING_AWAY:
			if attr.contains("freq"):
				if abs(value - _original_sensor_tuning) >= FREQUENCY_TOLERANCE:
					_run_simulation_if_possible()
					_say(
						[
							"The Sensor can no longer detect the signal.\n\n",
							"This shows how frequency affects detection."
						],
						TutorialStep.EXPLAIN_BANDWIDTH
					)

		TutorialStep.INCREASE_BANDWIDTH:
			if attr.contains("bandwidth"):
				_run_simulation_if_possible()
				_say(
					["Good. A wider bandwidth makes detection more flexible."],
					TutorialStep.INTRO_JAMMER
				)

		TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY:
			if attr.contains("freq") and _outside_match_range(value):
				_run_simulation_if_possible()
				_say(
					[
						"The link recovered because the Jammer is no longer ",
						"targeting the correct frequency."
					],
					TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK
				)

		TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK:
			if attr.contains("freq"):
				_lock_jammer_frequency = true
				_set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
				_run_simulation_if_possible()
				_say(["Good. The Jammer is locked back to 1000."], TutorialStep.COMPLETE)

		_:
			pass


func _setup(
	sidebar_types: Array = [],
	attributes: Array = [],
	marker_pos: Variant = null,
	marker_label: String = ""
) -> void:
	if sidebar_types.is_empty():
		_unlock_sidebar()
	else:
		_lock_sidebar_to(sidebar_types)

	_lock_attributes(attributes)

	if marker_pos is Vector2:
		_show_placement_marker(marker_pos, marker_label)
	else:
		_clear_placement_marker()


func _say(parts: Array, next_step: int = -1) -> void:
	_show_popup(_join_text(parts), next_step)


func _join_text(parts: Array) -> String:
	var text := ""
	for part in parts:
		text += str(part)
	return text


func _show_popup(text: String, next_step: int = -1) -> void:
	if intro_popup_open:
		return

	_popup_history.append({"text": text, "next_step": next_step})
	_popup_history_index = _popup_history.size() - 1

	_display_popup_history_entry()


func _display_popup_history_entry() -> void:
	if _popup_history_index < 0:
		return

	if _popup_history_index >= _popup_history.size():
		return

	var entry: Dictionary = _popup_history[_popup_history_index]
	var popup := TUTORIAL_HINT_POPUP.instantiate()

	popup.set("hint_text", str(entry.get("text", "")))
	popup.set("show_previous", _popup_history_index > 0)
	popup.set("show_next", true)

	intro_popup_open = true
	$CanvasLayer.add_child(popup)

	if popup.has_signal("previous_requested"):
		popup.previous_requested.connect(_on_popup_previous_requested)

	if popup.has_signal("continued"):
		popup.continued.connect(_on_popup_next_requested)


func _on_popup_previous_requested() -> void:
	intro_popup_open = false

	if _popup_history_index <= 0:
		return

	_popup_history_index -= 1
	call_deferred("_display_popup_history_entry")


func _on_popup_next_requested() -> void:
	intro_popup_open = false

	# When reviewing an older popup, Next moves forward through history.
	if _popup_history_index < _popup_history.size() - 1:
		_popup_history_index += 1
		call_deferred("_display_popup_history_entry")
		return

	# On the newest popup, Next either advances the tutorial or closes the
	# instruction so the player can complete the required action.
	var entry: Dictionary = _popup_history[_popup_history_index]
	var next_step := int(entry.get("next_step", -1))

	if next_step != -1:
		call_deferred("_enter_step", next_step)


func _show_completion_popup() -> void:
	if _completion_popup != null and is_instance_valid(_completion_popup):
		return

	intro_popup_open = true
	_completion_popup = TUTORIAL_COMPLETION_POPUP.instantiate()
	$CanvasLayer.add_child(_completion_popup)


func _show_placement_marker(local_pos: Vector2, label_text: String) -> void:
	_clear_placement_marker()

	var marker := PanelContainer.new()
	marker.name = "TutorialPlacementMarker"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.custom_minimum_size = Vector2(100, 70)
	marker.z_index = 50

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.85, 0.1, 0.25)
	style.border_color = Color(1.0, 0.85, 0.1, 1.0)
	style.set_border_width_all(3)
	marker.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	marker.add_child(label)

	map_container.add_child(marker)
	marker.position = local_pos - marker.custom_minimum_size * 0.5
	_placement_marker = marker


func _clear_placement_marker() -> void:
	if _placement_marker != null and is_instance_valid(_placement_marker):
		_placement_marker.queue_free()

	_placement_marker = null


func _show_wrong_placement_popup(label_text: String) -> void:
	_say(
		[
			"That unit is not close enough to the highlighted area.\n\n",
			"Move it closer to the marker labeled ",
			label_text,
			", then try again."
		]
	)


func _is_near_target(
	unit: Node, local_pos: Vector2, tolerance: float = PLACEMENT_TOLERANCE
) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false

	var target = map_container.global_position + local_pos
	var unit_pos := _get_unit_position(unit)

	return unit_pos.distance_to(target) <= tolerance


func _get_unit_position(unit: Node) -> Vector2:
	if unit is Node2D:
		return unit.global_position

	if unit is Control:
		return unit.global_position

	var raw_position = unit.get("global_position")
	if raw_position is Vector2:
		return raw_position

	return Vector2(-999999.0, -999999.0)


func _pick_default_transceiver() -> void:
	if _selected_tutorial_unit != null:
		return

	if _second_transceiver != null:
		_selected_tutorial_unit = _second_transceiver
	elif _first_transceiver != null:
		_selected_tutorial_unit = _first_transceiver


func _outside_match_range(value: float) -> bool:
	return abs(value - TUTORIAL_FREQUENCY) > FREQUENCY_TOLERANCE


func _inside_match_range(value: float) -> bool:
	return abs(value - TUTORIAL_FREQUENCY) <= FREQUENCY_TOLERANCE


func _lock_transceiver_frequencies() -> void:
	_set_number_on_unit(_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY)
	_set_number_on_unit(_second_transceiver, ["frequency"], TUTORIAL_FREQUENCY)
	_set_number_on_unit(_selected_tutorial_unit, ["frequency"], TUTORIAL_FREQUENCY)


func _lock_sidebar_to(types: Array) -> void:
	GameEvents.tutorial_filter_sidebar.emit(types)


func _unlock_sidebar() -> void:
	GameEvents.tutorial_filter_sidebar.emit([])


func _lock_attributes(attributes: Array) -> void:
	GameEvents.tutorial_filter_attributes.emit(attributes)


func _run_simulation_if_possible() -> void:
	if SimulationManager:
		SimulationManager.simulate()


func _is_transceiver(unit: Node) -> bool:
	return _unit_matches(unit, "transceiver", "transceivers")


func _is_sensor(unit: Node) -> bool:
	return _unit_matches(unit, "sensor", "sensors")


func _is_jammer(unit: Node) -> bool:
	return _unit_matches(unit, "jammer", "jammers")


func _unit_matches(unit: Node, name_text: String, group_name: String) -> bool:
	if unit == null:
		return false

	if unit.is_in_group(group_name):
		return true

	if unit.name.to_lower().contains(name_text):
		return true

	for child in unit.get_children():
		if child.name.to_lower().contains(name_text):
			return true

	return false


func _read_number_from_unit(unit: Node, possible_names: Array, fallback: float) -> float:
	if unit == null:
		return fallback

	for property_name in possible_names:
		var value = unit.get(property_name)
		if value != null:
			return _variant_to_float(value, fallback)

	for child in unit.get_children():
		for property_name in possible_names:
			var child_value = child.get(property_name)
			if child_value != null:
				return _variant_to_float(child_value, fallback)

	return fallback


func _variant_to_float(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback

	if value is int or value is float:
		return float(value)

	var text := str(value)
	if text.is_valid_float():
		return text.to_float()

	return fallback


func _set_number_on_unit(unit: Node, possible_names: Array, new_value: float) -> void:
	if unit == null:
		return

	for property_name in possible_names:
		if unit.get(property_name) != null:
			unit.set(property_name, new_value)
			return

	for child in unit.get_children():
		for property_name in possible_names:
			if child.get(property_name) != null:
				child.set(property_name, new_value)
				return

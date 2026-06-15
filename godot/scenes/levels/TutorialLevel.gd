extends "res://scenes/levels/ContourDemo.gd"
const TUTORIAL_HINT_POPUP := preload("res://scenes/ui/TutorialHintPopup.tscn")
const TUTORIAL_COMPLETION_POPUP := preload("res://scenes/ui/TutorialCompletionPopup.tscn")
const TUTORIAL_TEXT := preload("res://scenes/levels/TutorialText.gd")
const TUTORIAL_TERRAIN_SEED := 12345
const TUTORIAL_FREQUENCY := 1000.0
const FREQUENCY_TOLERANCE := 5.0
const PLACEMENT_TOLERANCE := 75.0
const MOVE_TARGET_TOLERANCE := 50.0
const FIRST_TRANSCEIVER_POS := Vector2(600, 780)
const FIRST_TRANSCEIVER_GREEN_POS := Vector2(690, 780)
const SECOND_TRANSCEIVER_POS := Vector2(850, 780)
const SENSOR_POS := Vector2(680, 960)
const JAMMER_POS := Vector2(690, 700)
const UNIT_ID_TRANSCEIVER := &"transceiver"
const UNIT_ID_SENSOR := &"sensor"
const UNIT_ID_JAMMER := &"jammer"
const LOCK_ALL_ATTRIBUTES := "__lock_all__"

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
	INTRO_DISPLAY_SETTINGS,
	TRY_LINK_LINES_TOGGLE,
	TRY_UNIT_RANGES_TOGGLE,
	VIEW_UNIT_RANGE,
	TRY_UNIT_DETAILS_TOGGLE,
	TRY_SUGGESTIONS_TOGGLE,
	TRY_TERRAIN_HEATMAP_TOGGLE,
	EXPLAIN_HEIGHTMAP_AND_GRID,
	DISPLAY_SETTINGS_COMPLETE,
	COMPLETE
}

var _tutorial_step: TutorialStep = TutorialStep.WELCOME
var _first_transceiver: Node = null
var _second_transceiver: Node = null
var _sensor: Node = null
var _jammer: Node = null
var _selected_tutorial_unit: Node = null
var _pending_placement_unit: Node = null
var _wrong_placement_popup_open := false
var _frequency_went_outside_range := false
var _tutorial_selection_refreshing := false
var _original_power := 10.0
var _original_height := 10.0
var _original_sensor_sensitivity := 10.0
var _original_sensor_tuning := TUTORIAL_FREQUENCY
var _placement_marker: Control = null
var _completion_popup: Control = null
var _repeat_instruction_button: Button = null
var _current_instruction_text := ""
var intro_popup_open := false
var _popup_history: Array[Dictionary] = []
var _popup_history_index := -1
var _lock_transceiver_frequency := false
var _lock_jammer_frequency := false
var _locked_unit_targets: Dictionary = {}
var _waiting_display_setting_key := ""
var _waiting_display_setting_original: Variant = null


func _ready() -> void:
	_remove_sandbox_intro_popups()
	intro_popup_open = false
	super._ready()
	_remove_sandbox_intro_popups()
	intro_popup_open = false
	_connect_tutorial_signals()
	call_deferred("_create_repeat_instruction_button")
	call_deferred("_start_tutorial")


func _connect_tutorial_signals() -> void:
	if not GameEvents.unit_placed.is_connected(_on_tutorial_unit_placed):
		GameEvents.unit_placed.connect(_on_tutorial_unit_placed)
	if GameEvents.has_signal("unit_selected"):
		if not GameEvents.unit_selected.is_connected(_on_tutorial_unit_selected):
			GameEvents.unit_selected.connect(_on_tutorial_unit_selected)
	if GameEvents.has_signal("selection_changed"):
		if not GameEvents.selection_changed.is_connected(_on_tutorial_unit_selected):
			GameEvents.selection_changed.connect(_on_tutorial_unit_selected)
	if not GameEvents.simulation_requested.is_connected(_on_tutorial_confirm_pressed):
		GameEvents.simulation_requested.connect(_on_tutorial_confirm_pressed)


func _start_tutorial() -> void:
	_remove_sandbox_intro_popups()
	intro_popup_open = false
	_enter_step(TutorialStep.WELCOME)


func _process(_delta: float) -> void:
	_remove_sandbox_intro_popups()
	_lock_placed_units()
	_check_pending_placement()
	_check_transceiver_move_target()
	_check_display_setting_change()
	if _lock_transceiver_frequency:
		_lock_transceiver_frequencies()
	if _lock_jammer_frequency:
		_set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)


func _input(event: InputEvent) -> void:
	if intro_popup_open:
		return
	super._input(event)


func _unhandled_input(event: InputEvent) -> void:
	if intro_popup_open:
		return
	super._unhandled_input(event)


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
	_remove_sandbox_intro_popups()
	_tutorial_step = step
	_waiting_display_setting_key = ""
	_waiting_display_setting_original = null
	if step == TutorialStep.COMPLETE:
		_setup()
		_current_instruction_text = ""
		_update_repeat_instruction_button_visibility()
		_show_completion_popup()
		return

	if TUTORIAL_TEXT.should_run_simulation_on_enter(step):
		_run_simulation_if_possible()
	if step == TutorialStep.MOVE_FIRST_TRANSCEIVER_CLOSER:
		_unlock_unit(_first_transceiver)

	var attributes := TUTORIAL_TEXT.attributes_for_step(step)
	if not attributes.is_empty():
		_select_expected_unit_for_edit(attributes)

	_apply_step_start_side_effects(step)

	var display_key := TUTORIAL_TEXT.display_setting_key_for_step(step)
	if display_key != "":
		_begin_display_setting_trial(display_key)

	var data := _step_data(step)
	_current_instruction_text = str(data.get("text", ""))
	_setup(
		data.get("sidebar", []),
		data.get("attributes", []),
		data.get("marker", null),
		data.get("label", "")
	)
	_update_repeat_instruction_button_visibility()
	_say([data.get("text", "")], int(data.get("next", -1)))


func _apply_step_start_side_effects(step: TutorialStep) -> void:
	match step:
		TutorialStep.EXPLAIN_FREQUENCY:
			_frequency_went_outside_range = false
			_lock_transceiver_frequency = false
			_lock_transceiver_frequencies()
			_run_simulation_if_possible()
		TutorialStep.EXPLAIN_POWER:
			_original_power = _read_number_from_unit(_first_transceiver, ["power"], 10.0)
		TutorialStep.EXPLAIN_HEIGHT:
			_original_height = _read_number_from_unit(_first_transceiver, ["height"], 10.0)
		TutorialStep.EXPLAIN_SENSOR_SENSITIVITY:
			_original_sensor_sensitivity = _read_number_from_unit(
				_sensor, ["sensitivity", "detection_sensitivity"], 10.0
			)
		TutorialStep.EXPLAIN_SENSOR_TUNING:
			_original_sensor_tuning = _read_number_from_unit(
				_sensor, ["tuning_frequency"], TUTORIAL_FREQUENCY
			)
		TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY:
			_lock_jammer_frequency = false
			_set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
			_run_simulation_if_possible()
		_:
			pass


func _step_data(step: TutorialStep) -> Dictionary:
	return TUTORIAL_TEXT.step_data(step)


func _on_tutorial_unit_placed(unit: Node) -> void:
	var target = _placement_target_for_current_step(unit)
	if target != null:
		_handle_placement(unit, target)


func _placement_target_for_current_step(unit: Node) -> Variant:
	match _tutorial_step:
		TutorialStep.PLACE_FIRST_TRANSCEIVER:
			return FIRST_TRANSCEIVER_POS if _is_transceiver(unit) else null
		TutorialStep.PLACE_SECOND_TRANSCEIVER:
			return SECOND_TRANSCEIVER_POS if _is_transceiver(unit) else null
		TutorialStep.PLACE_SENSOR:
			return SENSOR_POS if _is_sensor(unit) else null
		TutorialStep.PLACE_JAMMER:
			return JAMMER_POS if _is_jammer(unit) else null
		_:
			return null


func _handle_placement(unit: Node, target_position: Vector2) -> void:
	if _is_near_target(unit, target_position):
		_wrong_placement_popup_open = false
		_snap_unit_to_local_pos(unit, target_position)
		_accept_placement(unit)
		return
	_pending_placement_unit = unit
	_show_wrong_placement_popup()


func _check_pending_placement() -> void:
	if intro_popup_open or _pending_placement_unit == null:
		return
	if not is_instance_valid(_pending_placement_unit):
		_pending_placement_unit = null
		_wrong_placement_popup_open = false
		return
	var target = _placement_target_for_current_step(_pending_placement_unit)
	if target == null:
		_pending_placement_unit = null
		_wrong_placement_popup_open = false
		return
	if _is_near_target(_pending_placement_unit, target):
		_wrong_placement_popup_open = false
		_snap_unit_to_local_pos(_pending_placement_unit, target)
		_accept_placement(_pending_placement_unit)


func _check_transceiver_move_target() -> void:
	if intro_popup_open:
		return
	if _tutorial_step != TutorialStep.MOVE_FIRST_TRANSCEIVER_CLOSER:
		return
	if _first_transceiver == null or not is_instance_valid(_first_transceiver):
		return
	if _is_near_target(_first_transceiver, FIRST_TRANSCEIVER_GREEN_POS, MOVE_TARGET_TOLERANCE):
		_snap_unit_to_local_pos(_first_transceiver, FIRST_TRANSCEIVER_GREEN_POS)
		_lock_unit_to(_first_transceiver, FIRST_TRANSCEIVER_GREEN_POS)
		_run_simulation_if_possible()
		_enter_step(TutorialStep.EXPLAIN_SUCCESSFUL_LINK)


func _accept_placement(unit: Node) -> void:
	_pending_placement_unit = null
	_wrong_placement_popup_open = false
	_clear_placement_marker()
	match _tutorial_step:
		TutorialStep.PLACE_FIRST_TRANSCEIVER:
			_first_transceiver = unit
			_lock_unit_to(unit, FIRST_TRANSCEIVER_POS)
			_run_simulation_if_possible()
			_enter_step(TutorialStep.FIRST_TRANSCEIVER_PLACED)
		TutorialStep.PLACE_SECOND_TRANSCEIVER:
			_second_transceiver = unit
			_lock_unit_to(unit, SECOND_TRANSCEIVER_POS)
			_run_simulation_if_possible()
			_enter_step(TutorialStep.EXPLAIN_LINK)
		TutorialStep.PLACE_SENSOR:
			_sensor = unit
			_lock_unit_to(unit, SENSOR_POS)
			_run_simulation_if_possible()
			_enter_step(TutorialStep.EXPLAIN_SENSOR_SENSITIVITY)
		TutorialStep.PLACE_JAMMER:
			_jammer = unit
			_lock_unit_to(unit, JAMMER_POS)
			_run_simulation_if_possible()
			_enter_step(TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY)


func _on_tutorial_unit_selected(unit: Node) -> void:
	if _tutorial_selection_refreshing:
		return
	if unit == null or not is_instance_valid(unit):
		return
	if _tutorial_step == TutorialStep.SELECT_TRANSCEIVER:
		if unit == _first_transceiver:
			_enter_step(TutorialStep.EXPLAIN_FREQUENCY)
		elif _is_transceiver(unit):
			_lock_all_attributes()
		return
	if _tutorial_step == TutorialStep.VIEW_UNIT_RANGE:
		if _is_tutorial_map_unit(unit):
			_selected_tutorial_unit = unit
			_lock_all_attributes()
			_say(
				["Good. Selecting a unit lets you inspect its range circle."],
				TutorialStep.TRY_UNIT_DETAILS_TOGGLE
			)
		return
	var expected_unit := _expected_edit_unit_for_current_step()
	if expected_unit == null:
		return
	if unit == expected_unit:
		_selected_tutorial_unit = unit
		_apply_attribute_filter(_attributes_for_current_step())
	else:
		_selected_tutorial_unit = unit
		_lock_all_attributes()


func _on_tutorial_confirm_pressed() -> void:
	match _tutorial_step:
		TutorialStep.CHANGE_FREQUENCY_AWAY:
			var value := _read_number_from_unit(
				_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY
			)
			if _outside_match_range(value):
				_frequency_went_outside_range = true
				_run_simulation_if_possible()
				_say(
					[
						(
							"Good. Transceiver 1 is outside the matching range.\n\n"
							+ "Now move the frequency back between 995 and 1005."
						)
					],
					TutorialStep.CHANGE_FREQUENCY_BACK
				)
		TutorialStep.CHANGE_FREQUENCY_BACK:
			var value := _read_number_from_unit(
				_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY
			)
			if _frequency_went_outside_range and _inside_match_range(value):
				_lock_transceiver_frequencies()
				_lock_transceiver_frequency = true
				_run_simulation_if_possible()
				_say(
					["Good. The Transceivers are back inside the matching range."],
					TutorialStep.EXPLAIN_POWER
				)
		TutorialStep.LOWER_POWER:
			_confirm_number_less(
				_first_transceiver, ["power"], _original_power, TutorialStep.RAISE_POWER
			)
		TutorialStep.RAISE_POWER:
			_confirm_number_at_least(
				_first_transceiver,
				["power"],
				_original_power,
				["Good. Increasing power helped restore the link."],
				TutorialStep.EXPLAIN_HEIGHT
			)
		TutorialStep.INCREASE_HEIGHT:
			_confirm_number_greater(
				_first_transceiver,
				["height"],
				_original_height,
				["Good. Increasing height can improve communication."],
				TutorialStep.INTRO_SENSOR
			)
		TutorialStep.LOWER_SENSOR_SENSITIVITY:
			_confirm_number_less(
				_sensor,
				["sensitivity", "detection_sensitivity"],
				_original_sensor_sensitivity,
				TutorialStep.EXPLAIN_SENSOR_TUNING,
				["Good. Lowering sensitivity makes detection less likely."]
			)
		TutorialStep.CHANGE_SENSOR_TUNING_AWAY:
			var tuning := _read_number_from_unit(_sensor, ["tuning_frequency"], TUTORIAL_FREQUENCY)
			if abs(tuning - _original_sensor_tuning) >= FREQUENCY_TOLERANCE:
				_run_simulation_if_possible()
				_say(
					[
						(
							"The Sensor can no longer detect the signal.\n\n"
							+ "This shows how frequency affects detection."
						)
					],
					TutorialStep.EXPLAIN_BANDWIDTH
				)
		TutorialStep.INCREASE_BANDWIDTH:
			_run_simulation_if_possible()
			_say(
				["Good. A wider bandwidth makes detection more flexible."],
				TutorialStep.INTRO_JAMMER
			)
		TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY:
			var value := _read_number_from_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
			if _outside_match_range(value):
				_run_simulation_if_possible()
				_say(
					[
						(
							"The link recovered because the Jammer moved away "
							+ "from the correct frequency."
						)
					],
					TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK
				)
		TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK:
			var value := _read_number_from_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
			if _inside_match_range(value):
				_lock_jammer_frequency = true
				_set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
				_run_simulation_if_possible()
				_say(
					["Good. The Jammer is locked back to 1000."],
					TutorialStep.INTRO_DISPLAY_SETTINGS
				)


func _confirm_number_less(
	unit: Node, fields: Array, original: float, next_step: int, message: Array = []
) -> void:
	if _read_number_from_unit(unit, fields, original) < original:
		_run_simulation_if_possible()
		if message.is_empty():
			_enter_step(next_step)
		else:
			_say(message, next_step)


func _confirm_number_greater(
	unit: Node, fields: Array, original: float, message: Array, next_step: int
) -> void:
	if _read_number_from_unit(unit, fields, original) > original:
		_run_simulation_if_possible()
		_say(message, next_step)


func _confirm_number_at_least(
	unit: Node, fields: Array, original: float, message: Array, next_step: int
) -> void:
	if _read_number_from_unit(unit, fields, original) >= original:
		_run_simulation_if_possible()
		_say(message, next_step)


func _setup(
	sidebar_ids: Array = [],
	attributes: Array = [],
	marker_pos: Variant = null,
	marker_label: String = ""
) -> void:
	if sidebar_ids.is_empty():
		_unlock_sidebar()
	else:
		_lock_sidebar_to(sidebar_ids)
	_lock_attributes(attributes)
	if marker_pos is Vector2:
		_show_placement_marker(marker_pos, marker_label)
	else:
		_clear_placement_marker()


func _select_primary_transceiver_for_edit(attributes: Array) -> void:
	_select_unit_for_edit(_first_transceiver, attributes)


func _select_expected_unit_for_edit(attributes: Array) -> void:
	var unit := _expected_edit_unit_for_current_step()
	if unit != null:
		_select_unit_for_edit(unit, attributes)


func _select_unit_for_edit(unit: Node, attributes: Array) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_selected_tutorial_unit = unit
	_tutorial_selection_refreshing = true
	GameEvents.select(unit)
	call_deferred("_apply_attribute_filter", attributes)
	call_deferred("_finish_tutorial_selection_refresh")


func _finish_tutorial_selection_refresh() -> void:
	_tutorial_selection_refreshing = false


func _apply_attribute_filter(attributes: Array) -> void:
	_lock_attributes(attributes)


func _lock_all_attributes() -> void:
	_apply_attribute_filter([LOCK_ALL_ATTRIBUTES])


func _attributes_for_current_step() -> Array:
	return TUTORIAL_TEXT.attributes_for_step(_tutorial_step)


func _expected_edit_unit_for_current_step() -> Node:
	match TUTORIAL_TEXT.edit_target_for_step(_tutorial_step):
		"transceiver":
			return _first_transceiver
		"sensor":
			return _sensor
		"jammer":
			return _jammer
		_:
			return null


func _say(parts: Array, next_step: int = -1) -> void:
	_show_popup(_join_text(parts), next_step)


func _join_text(parts: Array) -> String:
	var text := ""
	for part in parts:
		text += str(part)
	return text


func _create_repeat_instruction_button() -> void:
	if _repeat_instruction_button != null and is_instance_valid(_repeat_instruction_button):
		return
	if not has_node("CanvasLayer"):
		return

	var button := Button.new()
	button.name = "RepeatInstructionButton"
	button.text = "Show Instruction"
	button.tooltip_text = "Show the current tutorial instruction again."
	button.custom_minimum_size = Vector2(180, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP

	button.anchor_left = 1.0
	button.anchor_top = 0.0
	button.anchor_right = 1.0
	button.anchor_bottom = 0.0
	button.offset_left = -210.0
	button.offset_top = 75.0
	button.offset_right = -16.0
	button.offset_bottom = 117.0

	button.pressed.connect(_on_repeat_instruction_button_pressed)
	$CanvasLayer.add_child(button)
	_repeat_instruction_button = button
	_update_repeat_instruction_button_visibility()


func _update_repeat_instruction_button_visibility() -> void:
	if _repeat_instruction_button == null or not is_instance_valid(_repeat_instruction_button):
		return

	var has_instruction := not _current_instruction_text.strip_edges().is_empty()
	var tutorial_finished := _tutorial_step == TutorialStep.COMPLETE
	_repeat_instruction_button.visible = (
		has_instruction and not intro_popup_open and not tutorial_finished
	)


func _on_repeat_instruction_button_pressed() -> void:
	if intro_popup_open:
		return

	var text := _current_instruction_text.strip_edges()
	if text.is_empty():
		var data := _step_data(_tutorial_step)
		text = str(data.get("text", "")).strip_edges()

	if text.is_empty():
		return

	_show_repeat_instruction_popup(text)


func _show_repeat_instruction_popup(text: String) -> void:
	_remove_sandbox_intro_popups()
	if intro_popup_open:
		return
	if not has_node("CanvasLayer"):
		return

	var popup := TUTORIAL_HINT_POPUP.instantiate()
	popup.name = "TutorialRepeatInstructionPopup"
	popup.set("hint_text", "Current instruction:\n\n" + text)

	intro_popup_open = true
	_update_repeat_instruction_button_visibility()
	$CanvasLayer.add_child(popup)

	popup.tree_exited.connect(
		func():
			if not _has_tutorial_popup_open():
				intro_popup_open = false
			_update_repeat_instruction_button_visibility()
	)


func _show_popup(text: String, next_step: int = -1) -> void:
	_remove_sandbox_intro_popups()
	if intro_popup_open:
		return
	_popup_history.append({"text": text, "next_step": next_step})
	_popup_history_index = _popup_history.size() - 1
	_display_popup_history_entry()


func _display_popup_history_entry() -> void:
	_remove_sandbox_intro_popups()
	_update_repeat_instruction_button_visibility()
	if _popup_history_index < 0 or _popup_history_index >= _popup_history.size():
		return
	var entry: Dictionary = _popup_history[_popup_history_index]
	var popup := TUTORIAL_HINT_POPUP.instantiate()
	popup.name = "TutorialHintPopup"
	popup.set("hint_text", str(entry.get("text", "")))
	popup.set("show_previous", _popup_history_index > 0)
	popup.set("show_next", true)
	intro_popup_open = true
	_update_repeat_instruction_button_visibility()
	$CanvasLayer.add_child(popup)
	if popup.has_signal("previous_requested"):
		popup.previous_requested.connect(_on_popup_previous_requested)
	if popup.has_signal("continued"):
		popup.continued.connect(_on_popup_next_requested)
	popup.tree_exited.connect(
		func():
			if not _has_tutorial_popup_open():
				intro_popup_open = false
			_update_repeat_instruction_button_visibility()
	)


func _on_popup_previous_requested() -> void:
	intro_popup_open = false
	if _popup_history_index <= 0:
		return
	_popup_history_index -= 1
	call_deferred("_display_popup_history_entry")


func _on_popup_next_requested() -> void:
	intro_popup_open = false
	if _wrong_placement_popup_open:
		return
	if _popup_history_index < _popup_history.size() - 1:
		_popup_history_index += 1
		call_deferred("_display_popup_history_entry")
		return
	var entry: Dictionary = _popup_history[_popup_history_index]
	var next_step := int(entry.get("next_step", -1))
	if next_step != -1:
		call_deferred("_enter_step", next_step)


func _has_tutorial_popup_open() -> bool:
	if not has_node("CanvasLayer"):
		return false
	for child in $CanvasLayer.get_children():
		var child_name := child.name.to_lower()
		if child_name.contains("tutorial") and child_name.contains("popup"):
			return true
	return false


func _show_completion_popup() -> void:
	_remove_sandbox_intro_popups()
	_update_repeat_instruction_button_visibility()
	if _completion_popup != null and is_instance_valid(_completion_popup):
		return
	intro_popup_open = true
	_completion_popup = TUTORIAL_COMPLETION_POPUP.instantiate()
	_completion_popup.name = "TutorialCompletionPopup"
	$CanvasLayer.add_child(_completion_popup)
	_completion_popup.tree_exited.connect(
		func():
			intro_popup_open = false
			_update_repeat_instruction_button_visibility()
	)


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


func _is_near_target(
	unit: Node, local_pos: Vector2, tolerance: float = PLACEMENT_TOLERANCE
) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var target = map_container.global_position + local_pos
	var unit_pos := _get_unit_position(unit)
	return unit_pos.distance_to(target) <= tolerance


func _get_unit_position(unit: Node) -> Vector2:
	if unit is Node2D or unit is Control:
		return unit.global_position
	var raw_position = unit.get("global_position")
	if raw_position is Vector2:
		return raw_position
	return Vector2(-999999.0, -999999.0)


func _snap_unit_to_local_pos(unit: Node, local_pos: Vector2) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var global_pos: Vector2 = map_container.global_position + local_pos
	var base_local_pos: Vector2 = global_pos - global_position
	if unit is Node2D or unit is Control:
		unit.global_position = global_pos
	else:
		unit.set("position", base_local_pos)
	unit.set_meta("world_uv", screen_to_world_uv(base_local_pos))


func _lock_unit_to(unit: Node, local_pos: Vector2) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_locked_unit_targets[unit] = local_pos
	_snap_unit_to_local_pos(unit, local_pos)


func _unlock_unit(unit: Node) -> void:
	if unit != null and _locked_unit_targets.has(unit):
		_locked_unit_targets.erase(unit)


func _lock_placed_units() -> void:
	for unit in _locked_unit_targets.keys():
		if unit == null or not is_instance_valid(unit):
			_locked_unit_targets.erase(unit)
			continue
		_snap_unit_to_local_pos(unit, _locked_unit_targets[unit])


func _outside_match_range(value: float) -> bool:
	return abs(value - TUTORIAL_FREQUENCY) > FREQUENCY_TOLERANCE


func _inside_match_range(value: float) -> bool:
	return abs(value - TUTORIAL_FREQUENCY) <= FREQUENCY_TOLERANCE


func _lock_transceiver_frequencies() -> void:
	_set_number_on_unit(_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY)
	_set_number_on_unit(_second_transceiver, ["frequency"], TUTORIAL_FREQUENCY)


func _lock_sidebar_to(ids: Array) -> void:
	GameEvents.tutorial_filter_sidebar.emit(ids)


func _unlock_sidebar() -> void:
	GameEvents.tutorial_filter_sidebar.emit([])


func _lock_attributes(attributes: Array) -> void:
	GameEvents.tutorial_filter_attributes.emit(attributes)


func _run_simulation_if_possible() -> void:
	if SimulationManager:
		SimulationManager.simulate()


func _is_tutorial_map_unit(unit: Node) -> bool:
	return _is_transceiver(unit) or _is_sensor(unit) or _is_jammer(unit)


func _is_transceiver(unit: Node) -> bool:
	return _unit_matches(unit, "transceiver", "transceivers")


func _is_sensor(unit: Node) -> bool:
	return _unit_matches(unit, "sensor", "sensors")


func _is_jammer(unit: Node) -> bool:
	return _unit_matches(unit, "jammer", "jammers")


func _unit_matches(unit: Node, name_text: String, group_name: String) -> bool:
	if unit == null:
		return false
	if unit.is_in_group(group_name) or unit.name.to_lower().contains(name_text):
		return true
	if unit is Unit and unit.definition:
		if str(unit.definition.id).to_lower().contains(name_text):
			return true
	for child in unit.get_children():
		if child.name.to_lower().contains(name_text):
			return true
	return false


func _read_number_from_unit(unit: Node, possible_names: Array, fallback: float) -> float:
	if unit == null or not is_instance_valid(unit):
		return fallback
	if unit is Unit:
		for property_name in possible_names:
			var value = unit.get_value(StringName(str(property_name)), null)
			if value != null:
				return _variant_to_float(value, fallback)
	for property_name in possible_names:
		var direct_value = unit.get(property_name)
		if direct_value != null:
			return _variant_to_float(direct_value, fallback)
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
	return text.to_float() if text.is_valid_float() else fallback


func _set_number_on_unit(unit: Node, possible_names: Array, new_value: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit is Unit:
		for property_name in possible_names:
			var id := StringName(str(property_name))
			var existing = unit.get_value(id, null)
			if existing != null:
				unit.set_value(id, new_value)
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


func _remove_sandbox_intro_popups() -> void:
	if get_tree() != null:
		_remove_sandbox_intro_popups_recursive(get_tree().root)


func _remove_sandbox_intro_popups_recursive(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		_remove_sandbox_intro_popups_recursive(child)
		if _is_sandbox_intro_popup(child):
			child.queue_free()


func _is_sandbox_intro_popup(node: Node) -> bool:
	if node == null:
		return false
	var node_name := node.name.to_lower()
	var scene_path := str(node.scene_file_path).to_lower()
	if node_name.contains("sandbox") and node_name.contains("intro"):
		return true
	if scene_path.contains("sandboxintropopup") or scene_path.contains("sandbox_intro_popup"):
		return true
	var script = node.get_script()
	if script is Resource:
		var script_path := str(script.resource_path).to_lower()
		return script_path.contains("sandbox") and script_path.contains("intro")
	return false


func _begin_display_setting_trial(setting_key: String) -> void:
	_waiting_display_setting_key = setting_key
	_waiting_display_setting_original = _read_hud_setting(setting_key, null)


func _check_display_setting_change() -> void:
	if intro_popup_open or _waiting_display_setting_key == "":
		return
	var current_value = _read_hud_setting(_waiting_display_setting_key, null)
	if current_value == null or current_value == _waiting_display_setting_original:
		return
	var completed_key := _waiting_display_setting_key
	_waiting_display_setting_key = ""
	_waiting_display_setting_original = null
	var result := TUTORIAL_TEXT.display_setting_result(completed_key)
	_say([result.get("text", "Good. That display setting changed.")], result.get("next", -1))


func _read_hud_setting(setting_key: String, fallback: Variant = null) -> Variant:
	var hud := _find_node_by_name(get_tree().root, "HUD")
	if hud == null:
		return fallback
	var settings = hud.get("settings")
	if typeof(settings) == TYPE_DICTIONARY and settings.has(setting_key):
		return settings[setting_key]
	for toggle_name in _display_toggle_node_names(setting_key):
		var toggle := _find_node_by_name(hud, toggle_name)
		if toggle == null:
			continue
		var button_pressed = toggle.get("button_pressed")
		if button_pressed != null:
			return bool(button_pressed)
	return fallback


func _display_toggle_node_names(setting_key: String) -> Array[String]:
	return TUTORIAL_TEXT.display_toggle_node_names(setting_key)


func _find_node_by_name(root: Node, wanted_name: String) -> Node:
	if root == null:
		return null
	if root.name == wanted_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, wanted_name)
		if found != null:
			return found
	return null


func _show_wrong_placement_popup() -> void:
	if _wrong_placement_popup_open:
		return
	_wrong_placement_popup_open = true
	_say(
		[
			(
				"That unit is not in the correct spot yet.\n\n"
				+ "Move it into the highlighted area on the map."
			)
		]
	)
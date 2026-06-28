class_name Tutorial
extends Sandbox

const TUTORIAL_HINT_POPUP := preload("res://scenes/ui/HintPopup.tscn")
const TUTORIAL_COMPLETION_POPUP := preload("res://scenes/ui/TutorialCompletionPopup.tscn")
const TUTORIAL_TEXT := preload("res://scenes/levels/TutorialText.gd")
const TUTORIAL_TERRAIN_SEED := 12345
const TUTORIAL_FREQUENCY := 1000.0
const FREQUENCY_TOLERANCE := 5.0
const PLACEMENT_TOLERANCE := 75.0
const MOVE_TARGET_TOLERANCE := 50.0
const FIRST_TRANSCEIVER_POS := TUTORIAL_TEXT.FIRST_TRANSCEIVER_POS
const FIRST_TRANSCEIVER_GREEN_POS := TUTORIAL_TEXT.FIRST_TRANSCEIVER_GREEN_POS
const SECOND_TRANSCEIVER_POS := TUTORIAL_TEXT.SECOND_TRANSCEIVER_POS
const SENSOR_POS := TUTORIAL_TEXT.SENSOR_POS
const JAMMER_POS := TUTORIAL_TEXT.JAMMER_POS
const UNIT_ID_TRANSCEIVER := &"transceiver"
const UNIT_ID_SENSOR := &"sensor"
const UNIT_ID_JAMMER := &"jammer"
const LOCK_ALL_ATTRIBUTES := "__lock_all__"
const TUTORIAL_STEP = TUTORIAL_TEXT.TutorialStep

var _tutorial_step: int = TUTORIAL_STEP.WELCOME
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
var _placement_marker_world_uv := Vector2.ZERO
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
var _edit_refresh_generation := 0


func _ready() -> void:
	_remove_sandbox_intro_popups()
	intro_popup_open = false
	super._ready()
	_connect_tutorial_signals()
	call_deferred("_create_repeat_instruction_button")
	if not _has_tutorial_persister():
		call_deferred("start_fresh")


func _has_tutorial_persister() -> bool:
	for child in get_children():
		if child is TutorialPersister:
			return true
	return false


func _tutorial_persister() -> TutorialPersister:
	for child in get_children():
		if child is TutorialPersister:
			return child
	return null


func start_fresh() -> void:
	_remove_sandbox_intro_popups()
	intro_popup_open = false
	_enter_step(TUTORIAL_STEP.WELCOME)


func _unit_children() -> Array:
	var units := []
	for child in get_children():
		if child is Unit and child.definition:
			units.append(child)
	return units


func _unit_for_role(role: String) -> Node:
	match role:
		"first_transceiver":
			return _first_transceiver
		"second_transceiver":
			return _second_transceiver
		"sensor":
			return _sensor
		"jammer":
			return _jammer
		_:
			return null


func _tutorial_role_indices() -> Dictionary:
	var units := _unit_children()
	var indices := {}
	for role in ["first_transceiver", "second_transceiver", "sensor", "jammer"]:
		var unit := _unit_for_role(role)
		if unit != null and is_instance_valid(unit):
			indices[role] = units.find(unit)
	return indices


func _restore_tutorial_unit_refs(role_indices: Dictionary) -> void:
	var units := _unit_children()
	_first_transceiver = TutorialUtils._unit_at_index(
		units, int(role_indices.get("first_transceiver", -1))
	)
	_second_transceiver = TutorialUtils._unit_at_index(
		units, int(role_indices.get("second_transceiver", -1))
	)
	_sensor = TutorialUtils._unit_at_index(units, int(role_indices.get("sensor", -1)))
	_jammer = TutorialUtils._unit_at_index(units, int(role_indices.get("jammer", -1)))


func serialize_tutorial_state() -> Dictionary:
	var locked := {}
	for unit in _locked_unit_targets.keys():
		if not is_instance_valid(unit):
			continue
		for role in ["first_transceiver", "second_transceiver", "sensor", "jammer"]:
			if _unit_for_role(role) == unit:
				var uv: Vector2 = _locked_unit_targets[unit]
				locked[role] = {"x": uv.x, "y": uv.y}
				break
	return {
		"step": _tutorial_step,
		"role_indices": _tutorial_role_indices(),
		"locked_units": locked,
		"frequency_went_outside_range": _frequency_went_outside_range,
		"lock_transceiver_frequency": _lock_transceiver_frequency,
		"lock_jammer_frequency": _lock_jammer_frequency,
		"original_power": _original_power,
		"original_height": _original_height,
		"original_sensor_sensitivity": _original_sensor_sensitivity,
		"original_sensor_tuning": _original_sensor_tuning,
	}


func restore_tutorial_state(data: Dictionary) -> void:
	_restore_tutorial_unit_refs(data.get("role_indices", {}))
	_locked_unit_targets.clear()
	var locked_raw: Dictionary = data.get("locked_units", {})
	for role in locked_raw.keys():
		var unit := _unit_for_role(role)
		if unit == null:
			continue
		var pos: Dictionary = locked_raw[role]
		var world_uv := Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
		_locked_unit_targets[unit] = world_uv
		_snap_unit_to_world_uv(unit, world_uv)
	_frequency_went_outside_range = bool(data.get("frequency_went_outside_range", false))
	_lock_transceiver_frequency = bool(data.get("lock_transceiver_frequency", false))
	_lock_jammer_frequency = bool(data.get("lock_jammer_frequency", false))
	_original_power = float(data.get("original_power", 10.0))
	_original_height = float(data.get("original_height", 10.0))
	_original_sensor_sensitivity = float(data.get("original_sensor_sensitivity", 10.0))
	_original_sensor_tuning = float(data.get("original_sensor_tuning", TUTORIAL_FREQUENCY))

	var step := int(data.get("step", TUTORIAL_STEP.WELCOME))
	_enter_step(step)


func _connect_tutorial_signals() -> void:
	if not GameEvents.units_changed.is_connected(_on_units_changed):
		GameEvents.units_changed.connect(_on_units_changed)
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


func _check_placement(unit: Node, target: Vector2) -> void:
	if unit == null:
		return
	if _is_near_target(unit, target):
		_wrong_placement_popup_open = false
		_snap_unit_to_world_uv(unit, target)
		_accept_placement(unit)
	else:
		_pending_placement_unit = unit
		_show_wrong_placement_popup()


func _find_unassigned_unit(unit_id: StringName) -> Node:
	for unit in _unit_children():
		if not (unit is Unit and unit.definition):
			continue
		if unit.definition.id != unit_id:
			continue
		if unit == _first_transceiver:
			continue
		if unit == _second_transceiver:
			continue
		if unit == _sensor:
			continue
		if unit == _jammer:
			continue
		return unit
	return null


func _on_units_changed() -> void:
	match _tutorial_step:
		TUTORIAL_STEP.PLACE_FIRST_TRANSCEIVER:
			if _first_transceiver == null:
				_check_placement(_find_unassigned_unit(UNIT_ID_TRANSCEIVER), FIRST_TRANSCEIVER_POS)
		TUTORIAL_STEP.PLACE_SECOND_TRANSCEIVER:
			_check_placement(_find_unassigned_unit(UNIT_ID_TRANSCEIVER), SECOND_TRANSCEIVER_POS)
		TUTORIAL_STEP.PLACE_SENSOR:
			_check_placement(_find_unassigned_unit(UNIT_ID_SENSOR), SENSOR_POS)
		TUTORIAL_STEP.PLACE_JAMMER:
			_check_placement(_find_unassigned_unit(UNIT_ID_JAMMER), JAMMER_POS)
		TUTORIAL_STEP.MOVE_FIRST_TRANSCEIVER_CLOSER:
			_check_transceiver_move_target()


func _mark_tutorial_complete() -> void:
	if not OS.has_feature("web"):
		return
	var progress_json := JSON.stringify({"tutorial_complete": true})
	var js_literal := JSON.stringify(progress_json)
	JavaScriptBridge.eval("window.setProgress && window.setProgress(" + js_literal + ")")
	var persister := _tutorial_persister()
	if persister != null:
		persister.clear_save()


func _process(_delta: float) -> void:
	_remove_sandbox_intro_popups()
	_lock_placed_units()
	_position_placement_marker()
	_check_pending_placement()
	_check_transceiver_move_target()
	_check_display_setting_change()
	if _lock_transceiver_frequency:
		_lock_transceiver_frequencies()
	if _lock_jammer_frequency:
		TutorialUtils._set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)


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


func _enter_step(step: int) -> void:
	_remove_sandbox_intro_popups()
	_tutorial_step = step
	_waiting_display_setting_key = ""
	_waiting_display_setting_original = null
	if step == TUTORIAL_STEP.COMPLETE:
		_setup()
		_current_instruction_text = ""
		_update_repeat_instruction_button_visibility()
		_show_completion_popup()
		_mark_tutorial_complete()
		return
	if TUTORIAL_TEXT.should_run_simulation_on_enter(step):
		_run_simulation_if_possible()
	if step == TUTORIAL_STEP.MOVE_FIRST_TRANSCEIVER_CLOSER:
		_unlock_unit(_first_transceiver)
	_apply_step_start_side_effects(step)
	var display_key := TUTORIAL_TEXT.display_setting_key_for_step(step)
	if display_key != "":
		_begin_display_setting_trial(display_key)
	var data := _step_data(step)
	var attributes := TUTORIAL_TEXT.attributes_for_step(step)
	_current_instruction_text = str(data.get("text", ""))
	_setup(data.get("sidebar", []), attributes, data.get("marker", null), data.get("label", ""))
	if not attributes.is_empty():
		call_deferred("_restore_current_edit_state")
	_update_repeat_instruction_button_visibility()
	_say([data.get("text", "")], int(data.get("next", -1)))


func _restore_current_edit_state() -> void:
	_edit_refresh_generation += 1
	var refresh_generation := _edit_refresh_generation
	var requested_step := _tutorial_step
	await get_tree().process_frame
	await get_tree().process_frame
	if _edit_refresh_is_stale(refresh_generation, requested_step):
		return
	var unit := _expected_edit_unit_for_current_step()
	var attributes := _attributes_for_current_step()
	if not _can_restore_edit_state(unit, attributes):
		return
	_tutorial_selection_refreshing = true
	GameEvents.clear_selection()
	await get_tree().process_frame
	if _edit_refresh_is_stale(refresh_generation, requested_step):
		_tutorial_selection_refreshing = false
		return
	if not _can_restore_edit_state(unit, attributes):
		_tutorial_selection_refreshing = false
		return
	_selected_tutorial_unit = unit
	_apply_attribute_filter(attributes)
	GameEvents.select(unit)
	await get_tree().process_frame
	_apply_attribute_filter(_attributes_for_current_step())
	await get_tree().process_frame
	_apply_attribute_filter(_attributes_for_current_step())
	_tutorial_selection_refreshing = false


func _edit_refresh_is_stale(refresh_generation: int, requested_step: int) -> bool:
	return refresh_generation != _edit_refresh_generation or requested_step != _tutorial_step


func _can_restore_edit_state(unit: Node, attributes: Array) -> bool:
	return unit != null and is_instance_valid(unit) and not attributes.is_empty()


func _apply_step_start_side_effects(step: int) -> void:
	match step:
		TUTORIAL_STEP.EXPLAIN_FREQUENCY:
			_frequency_went_outside_range = false
			_lock_transceiver_frequency = false
			_lock_transceiver_frequencies()
			_run_simulation_if_possible()
		TUTORIAL_STEP.EXPLAIN_POWER:
			_original_power = TutorialUtils._read_number_from_unit(
				_first_transceiver, ["power"], 10.0
			)
		TUTORIAL_STEP.EXPLAIN_HEIGHT:
			_original_height = TutorialUtils._read_number_from_unit(
				_first_transceiver, ["height"], 10.0
			)
		TUTORIAL_STEP.EXPLAIN_SENSOR_SENSITIVITY:
			_original_sensor_sensitivity = TutorialUtils._read_number_from_unit(
				_sensor, ["sensitivity", "detection_sensitivity"], 10.0
			)
		TUTORIAL_STEP.EXPLAIN_SENSOR_TUNING:
			_original_sensor_tuning = TutorialUtils._read_number_from_unit(
				_sensor, ["tuning_frequency"], TUTORIAL_FREQUENCY
			)
		TUTORIAL_STEP.CHANGE_JAMMER_FREQUENCY_AWAY:
			_lock_jammer_frequency = false
			TutorialUtils._set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
			_run_simulation_if_possible()
		_:
			pass


func _step_data(step: int) -> Dictionary:
	return TUTORIAL_TEXT.step_data(step)


func _on_tutorial_unit_placed(unit: Node) -> void:
	var target = _placement_target_for_current_step(unit)
	if target != null:
		_handle_placement(unit, target)


func _placement_target_for_current_step(unit: Node) -> Variant:
	match _tutorial_step:
		TUTORIAL_STEP.PLACE_FIRST_TRANSCEIVER:
			return FIRST_TRANSCEIVER_POS if TutorialUtils._is_transceiver(unit) else null
		TUTORIAL_STEP.PLACE_SECOND_TRANSCEIVER:
			return SECOND_TRANSCEIVER_POS if TutorialUtils._is_transceiver(unit) else null
		TUTORIAL_STEP.PLACE_SENSOR:
			return SENSOR_POS if TutorialUtils._is_sensor(unit) else null
		TUTORIAL_STEP.PLACE_JAMMER:
			return JAMMER_POS if TutorialUtils._is_jammer(unit) else null
		_:
			return null


func _handle_placement(unit: Node, target_position: Vector2) -> void:
	if _is_near_target(unit, target_position):
		_wrong_placement_popup_open = false
		_snap_unit_to_world_uv(unit, target_position)
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
		_snap_unit_to_world_uv(_pending_placement_unit, target)
		_accept_placement(_pending_placement_unit)


func _check_transceiver_move_target() -> void:
	if intro_popup_open:
		return
	if _tutorial_step != TUTORIAL_STEP.MOVE_FIRST_TRANSCEIVER_CLOSER:
		return
	if _first_transceiver == null or not is_instance_valid(_first_transceiver):
		return
	if _is_near_target(_first_transceiver, FIRST_TRANSCEIVER_GREEN_POS, MOVE_TARGET_TOLERANCE):
		_snap_unit_to_world_uv(_first_transceiver, FIRST_TRANSCEIVER_GREEN_POS)
		_lock_unit_to(_first_transceiver, FIRST_TRANSCEIVER_GREEN_POS)
		_run_simulation_if_possible()
		_enter_step(TUTORIAL_STEP.EXPLAIN_SUCCESSFUL_LINK)


func _accept_placement(unit: Node) -> void:
	_pending_placement_unit = null
	_wrong_placement_popup_open = false
	_clear_placement_marker()
	match _tutorial_step:
		TUTORIAL_STEP.PLACE_FIRST_TRANSCEIVER:
			_first_transceiver = unit
			_lock_unit_to(unit, FIRST_TRANSCEIVER_POS)
			_run_simulation_if_possible()
			_enter_step(TUTORIAL_STEP.FIRST_TRANSCEIVER_PLACED)
		TUTORIAL_STEP.PLACE_SECOND_TRANSCEIVER:
			_second_transceiver = unit
			_lock_unit_to(unit, SECOND_TRANSCEIVER_POS)
			_run_simulation_if_possible()
			_enter_step(TUTORIAL_STEP.EXPLAIN_LINK)
		TUTORIAL_STEP.PLACE_SENSOR:
			_sensor = unit
			_lock_unit_to(unit, SENSOR_POS)
			_run_simulation_if_possible()
			_enter_step(TUTORIAL_STEP.EXPLAIN_SENSOR_SENSITIVITY)
		TUTORIAL_STEP.PLACE_JAMMER:
			_jammer = unit
			_lock_unit_to(unit, JAMMER_POS)
			_run_simulation_if_possible()
			_enter_step(TUTORIAL_STEP.CHANGE_JAMMER_FREQUENCY_AWAY)


func _on_tutorial_unit_selected(unit: Node) -> void:
	if _tutorial_selection_refreshing:
		return
	if unit == null or not is_instance_valid(unit):
		return
	if _tutorial_step == TUTORIAL_STEP.SELECT_TRANSCEIVER:
		if unit == _first_transceiver:
			_enter_step(TUTORIAL_STEP.EXPLAIN_FREQUENCY)
		elif TutorialUtils._is_transceiver(unit):
			_lock_all_attributes()
		return
	if _tutorial_step == TUTORIAL_STEP.VIEW_UNIT_RANGE:
		if TutorialUtils._is_tutorial_map_unit(unit):
			_selected_tutorial_unit = unit
			_lock_all_attributes()
			_say([TUTORIAL_TEXT.unit_range_selected_text()], TUTORIAL_STEP.TRY_UNIT_DETAILS_TOGGLE)
		return
	if _tutorial_step == TUTORIAL_STEP.SELECT_UNIT_FOR_HEATMAP:
		if TutorialUtils._is_tutorial_map_unit(unit):
			_selected_tutorial_unit = unit
			_lock_all_attributes()
			_say([TUTORIAL_TEXT.heatmap_selected_text()], TUTORIAL_STEP.EXPLAIN_HEIGHTMAP_AND_GRID)
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
		TUTORIAL_STEP.CHANGE_FREQUENCY_AWAY:
			var value := TutorialUtils._read_number_from_unit(
				_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY
			)
			if TutorialUtils._outside_match_range(value):
				_frequency_went_outside_range = true
				_run_simulation_if_possible()
				_say([TUTORIAL_TEXT.frequency_outside_text()], TUTORIAL_STEP.CHANGE_FREQUENCY_BACK)
		TUTORIAL_STEP.CHANGE_FREQUENCY_BACK:
			var value := TutorialUtils._read_number_from_unit(
				_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY
			)
			if _frequency_went_outside_range and TutorialUtils._inside_match_range(value):
				_lock_transceiver_frequencies()
				_lock_transceiver_frequency = true
				_run_simulation_if_possible()
				_say([TUTORIAL_TEXT.frequency_restored_text()], TUTORIAL_STEP.EXPLAIN_POWER)
		TUTORIAL_STEP.LOWER_POWER:
			_confirm_number_less(
				_first_transceiver, ["power"], _original_power, TUTORIAL_STEP.RAISE_POWER
			)
		TUTORIAL_STEP.RAISE_POWER:
			_confirm_number_at_least(
				_first_transceiver,
				["power"],
				_original_power,
				[TUTORIAL_TEXT.power_restored_text()],
				TUTORIAL_STEP.EXPLAIN_HEIGHT
			)
		TUTORIAL_STEP.INCREASE_HEIGHT:
			_confirm_number_greater(
				_first_transceiver,
				["height"],
				_original_height,
				[TUTORIAL_TEXT.height_increased_text()],
				TUTORIAL_STEP.INTRO_SENSOR
			)
		TUTORIAL_STEP.LOWER_SENSOR_SENSITIVITY:
			_confirm_number_less(
				_sensor,
				["sensitivity", "detection_sensitivity"],
				_original_sensor_sensitivity,
				TUTORIAL_STEP.EXPLAIN_SENSOR_TUNING,
				[TUTORIAL_TEXT.sensitivity_lowered_text()]
			)
		TUTORIAL_STEP.CHANGE_SENSOR_TUNING_AWAY:
			var tuning := TutorialUtils._read_number_from_unit(
				_sensor, ["tuning_frequency"], TUTORIAL_FREQUENCY
			)
			if abs(tuning - _original_sensor_tuning) >= FREQUENCY_TOLERANCE:
				_run_simulation_if_possible()
				_say([TUTORIAL_TEXT.sensor_tuning_changed_text()], TUTORIAL_STEP.EXPLAIN_BANDWIDTH)
		TUTORIAL_STEP.INCREASE_BANDWIDTH:
			_run_simulation_if_possible()
			_say([TUTORIAL_TEXT.bandwidth_increased_text()], TUTORIAL_STEP.INTRO_JAMMER)
		TUTORIAL_STEP.CHANGE_JAMMER_FREQUENCY_AWAY:
			var value := TutorialUtils._read_number_from_unit(
				_jammer, ["frequency"], TUTORIAL_FREQUENCY
			)
			if TutorialUtils._outside_match_range(value):
				_run_simulation_if_possible()
				_say(
					[TUTORIAL_TEXT.jammer_moved_away_text()],
					TUTORIAL_STEP.CHANGE_JAMMER_FREQUENCY_BACK
				)
		TUTORIAL_STEP.CHANGE_JAMMER_FREQUENCY_BACK:
			var value := TutorialUtils._read_number_from_unit(
				_jammer, ["frequency"], TUTORIAL_FREQUENCY
			)
			if TutorialUtils._inside_match_range(value):
				_lock_jammer_frequency = true
				TutorialUtils._set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
				_run_simulation_if_possible()
				_say([TUTORIAL_TEXT.jammer_restored_text()], TUTORIAL_STEP.INTRO_DISPLAY_SETTINGS)


func _confirm_number_less(
	unit: Node, fields: Array, original: float, next_step: int, message: Array = []
) -> void:
	if TutorialUtils._read_number_from_unit(unit, fields, original) < original:
		_run_simulation_if_possible()
		if message.is_empty():
			_enter_step(next_step)
		else:
			_say(message, next_step)


func _confirm_number_greater(
	unit: Node, fields: Array, original: float, message: Array, next_step: int
) -> void:
	if TutorialUtils._read_number_from_unit(unit, fields, original) > original:
		_run_simulation_if_possible()
		_say(message, next_step)


func _confirm_number_at_least(
	unit: Node, fields: Array, original: float, message: Array, next_step: int
) -> void:
	if TutorialUtils._read_number_from_unit(unit, fields, original) >= original:
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
	_show_popup(TutorialUtils._join_text(parts), next_step)


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
	var tutorial_finished := _tutorial_step == TUTORIAL_STEP.COMPLETE
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
		return
	if not _attributes_for_current_step().is_empty():
		call_deferred("_restore_current_edit_state")


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


func _show_placement_marker(world_uv: Vector2, label_text: String) -> void:
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
	_placement_marker = marker
	_placement_marker_world_uv = world_uv
	_position_placement_marker()


func _position_placement_marker() -> void:
	if _placement_marker == null or not is_instance_valid(_placement_marker):
		return
	var global_pos: Vector2 = global_position + world_uv_to_screen(_placement_marker_world_uv)
	var container_local: Vector2 = global_pos - map_container.global_position
	_placement_marker.position = container_local - _placement_marker.custom_minimum_size * 0.5


func _clear_placement_marker() -> void:
	if _placement_marker != null and is_instance_valid(_placement_marker):
		_placement_marker.queue_free()
	_placement_marker = null


func _is_near_target(unit: Node, world_uv: Vector2, tolerance: float = PLACEMENT_TOLERANCE) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var target := global_position + world_uv_to_screen(world_uv)
	var unit_pos := TutorialUtils._get_unit_position(unit)
	return unit_pos.distance_to(target) <= tolerance


func _snap_unit_to_world_uv(unit: Node, world_uv: Vector2) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var base_local_pos: Vector2 = world_uv_to_screen(world_uv)
	var global_pos: Vector2 = global_position + base_local_pos
	if unit is Node2D or unit is Control:
		unit.global_position = global_pos
	else:
		unit.set("position", base_local_pos)
	unit.set_meta("world_uv", world_uv)
	if unit is Unit:
		unit.set_value(&"world_uv", world_uv)


func _lock_unit_to(unit: Node, world_uv: Vector2) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_locked_unit_targets[unit] = world_uv
	_snap_unit_to_world_uv(unit, world_uv)


func _unlock_unit(unit: Node) -> void:
	if unit != null and _locked_unit_targets.has(unit):
		_locked_unit_targets.erase(unit)


func _lock_placed_units() -> void:
	for unit in _locked_unit_targets.keys():
		if unit == null or not is_instance_valid(unit):
			_locked_unit_targets.erase(unit)
			continue
		_snap_unit_to_world_uv(unit, _locked_unit_targets[unit])


func _lock_transceiver_frequencies() -> void:
	TutorialUtils._set_number_on_unit(_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY)
	TutorialUtils._set_number_on_unit(_second_transceiver, ["frequency"], TUTORIAL_FREQUENCY)


func _lock_sidebar_to(ids: Array) -> void:
	GameEvents.tutorial_filter_sidebar.emit(ids)


func _unlock_sidebar() -> void:
	GameEvents.tutorial_filter_sidebar.emit([])


func _lock_attributes(attributes: Array) -> void:
	GameEvents.tutorial_filter_attributes.emit(attributes)


func _run_simulation_if_possible() -> void:
	if SimulationManager:
		SimulationManager.simulate()


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
	if current_value == null:
		return
	var target_value = TUTORIAL_TEXT.display_setting_target_for_step(_tutorial_step)
	if target_value != null:
		if bool(current_value) != bool(target_value):
			return
	elif current_value == _waiting_display_setting_original:
		return
	var completed_key := _waiting_display_setting_key
	_waiting_display_setting_key = ""
	_waiting_display_setting_original = null
	var result := TUTORIAL_TEXT.display_setting_result(completed_key, _tutorial_step)
	_say([result.get("text", "Good. That display setting changed.")], result.get("next", -1))


func _read_hud_setting(setting_key: String, fallback: Variant = null) -> Variant:
	var hud := TutorialUtils._find_node_by_name(get_tree().root, "HUD")
	if hud == null:
		return fallback
	var settings = hud.get("settings")
	if typeof(settings) == TYPE_DICTIONARY and settings.has(setting_key):
		return settings[setting_key]
	for toggle_name in _display_toggle_node_names(setting_key):
		var toggle := TutorialUtils._find_node_by_name(hud, toggle_name)
		if toggle == null:
			continue
		var button_pressed = toggle.get("button_pressed")
		if button_pressed != null:
			return bool(button_pressed)
	return fallback


func _display_toggle_node_names(setting_key: String) -> Array[String]:
	return TUTORIAL_TEXT.display_toggle_node_names(setting_key)


func _show_wrong_placement_popup() -> void:
	if _wrong_placement_popup_open:
		return
	_wrong_placement_popup_open = true
	_say([TUTORIAL_TEXT.wrong_placement_text()])

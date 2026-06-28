class_name Tutorial
extends Sandbox

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

var _ui: TutorialUI
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
var _current_instruction_text := ""
var intro_popup_open := false
var _lock_transceiver_frequency := false
var _lock_jammer_frequency := false
var _locked_unit_targets: Dictionary = {}
var _waiting_display_setting_key := ""
var _waiting_display_setting_original: Variant = null
var _edit_refresh_generation := 0


func _ready() -> void:
	_ui = TutorialUI.new(self)
	TutorialUtils.remove_sandbox_intro_popups(get_tree())
	intro_popup_open = false
	super._ready()
	TutorialUtils.remove_sandbox_intro_popups(get_tree())
	intro_popup_open = false
	_connect_tutorial_signals()
	_ui.call_deferred("create_repeat_instruction_button")
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
	TutorialUtils.remove_sandbox_intro_popups(get_tree())
	intro_popup_open = false
	_enter_step(TUTORIAL_STEP.WELCOME)


func _unit_children() -> Array:
	var units := []
	for child in get_children():
		if child is Unit and child.definition:
			units.append(child)
	return units


func _unit_at_index(units: Array, idx: int) -> Node:
	if idx >= 0 and idx < units.size():
		return units[idx]
	return null


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
	_first_transceiver = _unit_at_index(units, int(role_indices.get("first_transceiver", -1)))
	_second_transceiver = _unit_at_index(units, int(role_indices.get("second_transceiver", -1)))
	_sensor = _unit_at_index(units, int(role_indices.get("sensor", -1)))
	_jammer = _unit_at_index(units, int(role_indices.get("jammer", -1)))


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
		_ui.show_wrong_placement_popup()


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
	TutorialUtils.remove_sandbox_intro_popups(get_tree())
	_lock_placed_units()
	_ui.position_placement_marker()
	_check_pending_placement()
	_check_transceiver_move_target()
	_check_display_setting_change()
	if _lock_transceiver_frequency:
		_lock_transceiver_frequencies()
	if _lock_jammer_frequency:
		TutorialUtils.set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)


func _input(event: InputEvent) -> void:
	if intro_popup_open:
		return
	super._input(event)


func _unhandled_input(event: InputEvent) -> void:
	if intro_popup_open:
		return
	super._unhandled_input(event)


func _generate_terrain(w: int, h: int, seed: int) -> Array:
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
	TutorialUtils.remove_sandbox_intro_popups(get_tree())
	_tutorial_step = step
	_waiting_display_setting_key = ""
	_waiting_display_setting_original = null

	if step == TUTORIAL_STEP.COMPLETE:
		_setup()
		_current_instruction_text = ""
		_ui.update_repeat_instruction_button_visibility()
		_ui.show_completion_popup()
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

	_ui.update_repeat_instruction_button_visibility()
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
			_original_power = TutorialUtils.read_number_from_unit(
				_first_transceiver, ["power"], 10.0
			)
		TUTORIAL_STEP.EXPLAIN_HEIGHT:
			_original_height = TutorialUtils.read_number_from_unit(
				_first_transceiver, ["height"], 10.0
			)
		TUTORIAL_STEP.EXPLAIN_SENSOR_SENSITIVITY:
			_original_sensor_sensitivity = TutorialUtils.read_number_from_unit(
				_sensor, ["sensitivity", "detection_sensitivity"], 10.0
			)
		TUTORIAL_STEP.EXPLAIN_SENSOR_TUNING:
			_original_sensor_tuning = TutorialUtils.read_number_from_unit(
				_sensor, ["tuning_frequency"], TUTORIAL_FREQUENCY
			)
		TUTORIAL_STEP.CHANGE_JAMMER_FREQUENCY_AWAY:
			_lock_jammer_frequency = false
			TutorialUtils.set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
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
			return FIRST_TRANSCEIVER_POS if TutorialUtils.is_transceiver(unit) else null
		TUTORIAL_STEP.PLACE_SECOND_TRANSCEIVER:
			return SECOND_TRANSCEIVER_POS if TutorialUtils.is_transceiver(unit) else null
		TUTORIAL_STEP.PLACE_SENSOR:
			return SENSOR_POS if TutorialUtils.is_sensor(unit) else null
		TUTORIAL_STEP.PLACE_JAMMER:
			return JAMMER_POS if TutorialUtils.is_jammer(unit) else null
		_:
			return null


func _handle_placement(unit: Node, target_position: Vector2) -> void:
	if _is_near_target(unit, target_position):
		_wrong_placement_popup_open = false
		_snap_unit_to_world_uv(unit, target_position)
		_accept_placement(unit)
		return
	_pending_placement_unit = unit
	_ui.show_wrong_placement_popup()


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
	_ui.clear_placement_marker()
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
		elif TutorialUtils.is_transceiver(unit):
			_lock_all_attributes()
		return
	if _tutorial_step == TUTORIAL_STEP.VIEW_UNIT_RANGE:
		if _is_tutorial_map_unit(unit):
			_selected_tutorial_unit = unit
			_lock_all_attributes()
			_say([TUTORIAL_TEXT.unit_range_selected_text()], TUTORIAL_STEP.TRY_UNIT_DETAILS_TOGGLE)
		return
	if _tutorial_step == TUTORIAL_STEP.SELECT_UNIT_FOR_HEATMAP:
		if _is_tutorial_map_unit(unit):
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
			var value := TutorialUtils.read_number_from_unit(
				_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY
			)
			if _outside_match_range(value):
				_frequency_went_outside_range = true
				_run_simulation_if_possible()
				_say([TUTORIAL_TEXT.frequency_outside_text()], TUTORIAL_STEP.CHANGE_FREQUENCY_BACK)
		TUTORIAL_STEP.CHANGE_FREQUENCY_BACK:
			var value := TutorialUtils.read_number_from_unit(
				_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY
			)
			if _frequency_went_outside_range and _inside_match_range(value):
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
			var tuning := TutorialUtils.read_number_from_unit(
				_sensor, ["tuning_frequency"], TUTORIAL_FREQUENCY
			)
			if abs(tuning - _original_sensor_tuning) >= FREQUENCY_TOLERANCE:
				_run_simulation_if_possible()
				_say([TUTORIAL_TEXT.sensor_tuning_changed_text()], TUTORIAL_STEP.EXPLAIN_BANDWIDTH)
		TUTORIAL_STEP.INCREASE_BANDWIDTH:
			_run_simulation_if_possible()
			_say([TUTORIAL_TEXT.bandwidth_increased_text()], TUTORIAL_STEP.INTRO_JAMMER)
		TUTORIAL_STEP.CHANGE_JAMMER_FREQUENCY_AWAY:
			var value := TutorialUtils.read_number_from_unit(
				_jammer, ["frequency"], TUTORIAL_FREQUENCY
			)
			if _outside_match_range(value):
				_run_simulation_if_possible()
				_say(
					[TUTORIAL_TEXT.jammer_moved_away_text()],
					TUTORIAL_STEP.CHANGE_JAMMER_FREQUENCY_BACK
				)
		TUTORIAL_STEP.CHANGE_JAMMER_FREQUENCY_BACK:
			var value := TutorialUtils.read_number_from_unit(
				_jammer, ["frequency"], TUTORIAL_FREQUENCY
			)
			if _inside_match_range(value):
				_lock_jammer_frequency = true
				TutorialUtils.set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
				_run_simulation_if_possible()
				_say([TUTORIAL_TEXT.jammer_restored_text()], TUTORIAL_STEP.INTRO_DISPLAY_SETTINGS)


func _confirm_number_less(
	unit: Node, fields: Array, original: float, next_step: int, message: Array = []
) -> void:
	if TutorialUtils.read_number_from_unit(unit, fields, original) < original:
		_run_simulation_if_possible()
		if message.is_empty():
			_enter_step(next_step)
		else:
			_say(message, next_step)


func _confirm_number_greater(
	unit: Node, fields: Array, original: float, message: Array, next_step: int
) -> void:
	if TutorialUtils.read_number_from_unit(unit, fields, original) > original:
		_run_simulation_if_possible()
		_say(message, next_step)


func _confirm_number_at_least(
	unit: Node, fields: Array, original: float, message: Array, next_step: int
) -> void:
	if TutorialUtils.read_number_from_unit(unit, fields, original) >= original:
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
		_ui.show_placement_marker(marker_pos, marker_label)
	else:
		_ui.clear_placement_marker()


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
	_ui.show_popup(_join_text(parts), next_step)


func _join_text(parts: Array) -> String:
	var text := ""
	for part in parts:
		text += str(part)
	return text


func _is_near_target(unit: Node, world_uv: Vector2, tolerance: float = PLACEMENT_TOLERANCE) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var target := global_position + world_uv_to_screen(world_uv)
	var unit_pos := TutorialUtils.get_unit_position(unit)
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


func _outside_match_range(value: float) -> bool:
	return abs(value - TUTORIAL_FREQUENCY) > FREQUENCY_TOLERANCE


func _inside_match_range(value: float) -> bool:
	return abs(value - TUTORIAL_FREQUENCY) <= FREQUENCY_TOLERANCE


func _lock_transceiver_frequencies() -> void:
	TutorialUtils.set_number_on_unit(_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY)
	TutorialUtils.set_number_on_unit(_second_transceiver, ["frequency"], TUTORIAL_FREQUENCY)


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
	return (
		TutorialUtils.is_transceiver(unit)
		or TutorialUtils.is_sensor(unit)
		or TutorialUtils.is_jammer(unit)
	)


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
	var hud := TutorialUtils.find_node_by_name(get_tree().root, "HUD")
	if hud == null:
		return fallback
	var settings = hud.get("settings")
	if typeof(settings) == TYPE_DICTIONARY and settings.has(setting_key):
		return settings[setting_key]
	for toggle_name in _display_toggle_node_names(setting_key):
		var toggle := TutorialUtils.find_node_by_name(hud, toggle_name)
		if toggle == null:
			continue
		var button_pressed = toggle.get("button_pressed")
		if button_pressed != null:
			return bool(button_pressed)
	return fallback


func _display_toggle_node_names(setting_key: String) -> Array[String]:
	return TUTORIAL_TEXT.display_toggle_node_names(setting_key)

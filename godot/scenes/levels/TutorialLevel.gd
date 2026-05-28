extends "res://scenes/levels/ContourDemo.gd"

const TUTORIAL_HINT_POPUP := preload("res://scenes/ui/TutorialHintPopup.tscn")

# Fixed tutorial values so the tutorial behaves the same every time.
const TUTORIAL_TERRAIN_SEED := 12345
const TUTORIAL_FREQUENCY := 1000.0
const TUTORIAL_SENSOR_SENSITIVITY := 1.0

# Navigation targets.
# Sandbox uses the current main playable scene.
# Home is for the web build. In the Godot editor, it will print a message instead.
const SANDBOX_SCENE_PATH := "res://scenes/levels/Level1.tscn"
const HOME_URL := "/"

# Fixed tutorial placement positions.
# These are local positions inside BackgroundTexture/map_container.
const FIRST_TRANSCEIVER_POS := Vector2(500, 260)
const SECOND_TRANSCEIVER_POS := Vector2(750, 260)
const SENSOR_POS := Vector2(500, 290)
const JAMMER_POS := Vector2(690, 180)

enum TutorialStep {
	WELCOME,
	INTRO_MAP,

	PLACE_FIRST_TRANSCEIVER,
	FIRST_TRANSCEIVER_PLACED,

	PLACE_SECOND_TRANSCEIVER,
	EXPLAIN_LINK,

	EXPLAIN_BANDWIDTH_PENALTY,
	CHANGE_TRANSCEIVER_BANDWIDTHS_NARROW,
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

var _original_power := 10.0
var _original_height := 10.0
var _original_sensor_tuning := TUTORIAL_FREQUENCY
var _original_jammer_frequency := TUTORIAL_FREQUENCY

var _first_transceiver_bandwidth_narrow := false
var _second_transceiver_bandwidth_narrow := false

var _placement_marker: Control = null
var _completion_popup: Control = null

var _tutorial_frequency_locked := false
var _sensor_sensitivity_locked := false
var _transceiver_positions_locked := false
var _jammer_frequency_locked := false


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
	if _transceiver_positions_locked:
		_keep_transceivers_locked_in_place()

	if _tutorial_frequency_locked:
		_keep_transceiver_frequencies_locked()

	if _sensor_sensitivity_locked:
		_keep_sensor_sensitivity_locked()

	if _jammer_frequency_locked:
		_keep_jammer_frequency_locked()


# Overrides ContourDemo.gd terrain generation so Tutorial Mode uses the same terrain every run.
func _generate_terrain(w: int, h: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = TUTORIAL_TERRAIN_SEED
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


func _enter_step(step: TutorialStep) -> void:
	_tutorial_step = step

	match step:
		TutorialStep.WELCOME:
			_clear_placement_marker()
			_unlock_sidebar()
			_lock_attributes([])
			_show_popup(
				"Welcome to Tutorial Mode.\n\nThis mode will teach you the basics of Gamify EMS. You will learn how to place units, edit their attributes, create communication links, detect signals, and understand how frequency, power, height, and bandwidth affect the simulation.",
				TutorialStep.INTRO_MAP
			)

		TutorialStep.INTRO_MAP:
			_clear_placement_marker()
			_unlock_sidebar()
			_lock_attributes([])
			_show_popup(
				"This is the simulation map.\n\nUnits can be placed on the map to represent communication equipment, sensors, and jammers. The position of each unit matters because distance affects signal strength.",
				TutorialStep.PLACE_FIRST_TRANSCEIVER
			)

		TutorialStep.PLACE_FIRST_TRANSCEIVER:
			_lock_sidebar_to([Sidebar.EntityType.TRANSCEIVER])
			_lock_attributes([])
			_show_placement_marker(FIRST_TRANSCEIVER_POS, "Place\nTransceiver 1")
			_show_popup(
				"First, place a Transceiver on the highlighted target area."
			)

		TutorialStep.FIRST_TRANSCEIVER_PLACED:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes([])
			_show_popup(
				"Good. You placed your first Transceiver.\n\nThis unit has attributes such as frequency, power, bandwidth, and antenna height. These values affect how well the unit can communicate with other units.",
				TutorialStep.PLACE_SECOND_TRANSCEIVER
			)

		TutorialStep.PLACE_SECOND_TRANSCEIVER:
			_lock_sidebar_to([Sidebar.EntityType.TRANSCEIVER])
			_lock_attributes([])
			_show_placement_marker(SECOND_TRANSCEIVER_POS, "Place\nTransceiver 2")
			_show_popup(
				"Now place a second Transceiver on the highlighted target area."
			)

		TutorialStep.EXPLAIN_LINK:
			_clear_placement_marker()
			_unlock_sidebar()
			_lock_attributes([])
			_run_simulation_if_possible()
			_show_popup(
				"The two Transceivers are now trying to communicate.\n\nA green line means the connection is successful.\nAn orange line means the units are out of range or the signal is too weak.\nA red or distorted line means the connection may be jammed.\nA purple line means there is a bandwidth penalty.\nA blue line means the Transceivers are using different frequency ranges.",
				TutorialStep.EXPLAIN_BANDWIDTH_PENALTY
			)

		TutorialStep.EXPLAIN_BANDWIDTH_PENALTY:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes([])
			_run_simulation_if_possible()
			_show_popup(
				"The purple line means there is a bandwidth penalty.\n\nIn EMS, bandwidth is the range of frequencies a signal uses around its main frequency. A wider bandwidth can carry more information, but it can also use more spectrum space, create more noise, and make the signal less clean.\n\nIn this tutorial, the purple line means the Transceivers are close enough to communicate, but their bandwidth setting is hurting the link quality.",
				TutorialStep.CHANGE_TRANSCEIVER_BANDWIDTHS_NARROW
			)

		TutorialStep.CHANGE_TRANSCEIVER_BANDWIDTHS_NARROW:
			_lock_sidebar_to([])
			_lock_attributes(["bandwidth"])
			_show_popup(
				"Now change the bandwidth of both Transceivers to Narrow.\n\nThis reduces the bandwidth penalty and should allow the Transceivers to form a clean connection."
			)

		TutorialStep.EXPLAIN_SUCCESSFUL_LINK:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes([])
			_run_simulation_if_possible()
			_show_popup(
				"Good. The green line means the connection was successful.\n\nThis means the two Transceivers are close enough, their settings are compatible, and the signal is strong enough to communicate.",
				TutorialStep.SELECT_TRANSCEIVER
			)

		TutorialStep.SELECT_TRANSCEIVER:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes([])
			_show_popup(
				"Click on one of the Transceivers to view its attributes.\n\nThe attribute panel lets you edit important values such as frequency, power, bandwidth, and antenna height.",
				TutorialStep.EXPLAIN_FREQUENCY
			)

		TutorialStep.EXPLAIN_FREQUENCY:
			_clear_placement_marker()
			_lock_sidebar_to([])

			if _selected_tutorial_unit == null:
				if _second_transceiver != null:
					_selected_tutorial_unit = _second_transceiver
				elif _first_transceiver != null:
					_selected_tutorial_unit = _first_transceiver

			_tutorial_frequency_locked = false
			_lock_attributes(["frequency"])
			_lock_all_transceiver_frequencies_to_tutorial_value()
			_run_simulation_if_possible()

			_show_popup(
				"Frequency controls what channel the unit is using.\n\nFor two Transceivers to communicate, their frequencies must be compatible. If one unit is using a very different frequency, the link may fail.",
				TutorialStep.CHANGE_FREQUENCY_AWAY
			)

		TutorialStep.CHANGE_FREQUENCY_AWAY:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["frequency"])
			_show_popup(
				"Change the frequency of one Transceiver so it no longer matches the other one.\n\nWatch how the connection line changes."
			)

		TutorialStep.CHANGE_FREQUENCY_BACK:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["frequency"])
			_show_popup(
				"Now change the frequency back.\n\nFor consistency, the tutorial will automatically lock both Transceivers back to 1000 Hz after you edit it."
			)

		TutorialStep.EXPLAIN_POWER:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["power"])
			_original_power = _read_number_from_unit(
				_selected_tutorial_unit,
				["power"],
				10.0
			)
			_show_popup(
				"Power affects how strong a signal is.\n\nHigher power can help a signal travel farther, but it may also make the unit easier to detect. Lower power may reduce detection risk, but it can make communication harder over long distances.",
				TutorialStep.LOWER_POWER
			)

		TutorialStep.LOWER_POWER:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["power"])
			_show_popup(
				"Lower the Transceiver power and watch what happens to the link.\n\nIf the signal becomes too weak, the connection may fail."
			)

		TutorialStep.RAISE_POWER:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["power"])
			_show_popup(
				"Good. Now raise the power again to help restore the link.\n\nThis shows the tradeoff between signal strength and visibility."
			)

		TutorialStep.EXPLAIN_HEIGHT:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["height"])
			_original_height = _read_number_from_unit(
				_selected_tutorial_unit,
				["height"],
				10.0
			)
			_show_popup(
				"Antenna height can also affect communication.\n\nA taller antenna can improve signal performance because it gives the unit a better transmission path.",
				TutorialStep.INCREASE_HEIGHT
			)

		TutorialStep.INCREASE_HEIGHT:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["height"])
			_show_popup(
				"Increase the antenna height of one Transceiver and observe the result.\n\nIn later modes, terrain and distance may make height even more important."
			)

		TutorialStep.INTRO_SENSOR:
			_clear_placement_marker()
			_lock_sidebar_to([Sidebar.EntityType.SENSOR])
			_lock_attributes([])
			_show_popup(
				"Sensors are used to detect signals.\n\nA Sensor does not create a communication link like a Transceiver. Instead, it listens for nearby transmissions.\n\nPlace a Sensor near one of the Transceivers.",
				TutorialStep.PLACE_SENSOR
			)

		TutorialStep.PLACE_SENSOR:
			_lock_sidebar_to([Sidebar.EntityType.SENSOR])
			_lock_attributes([])
			_show_placement_marker(SENSOR_POS, "Place\nSensor")
			_show_popup(
				"Drag a Sensor onto the highlighted target area near the Transceivers."
			)

		TutorialStep.EXPLAIN_SENSOR_SENSITIVITY:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["sensitivity", "detection_sensitivity"])
			_show_popup(
				"Now let's look at Sensor sensitivity.\n\nSensitivity controls how easily a Sensor can detect a signal. Higher sensitivity can detect weaker signals, while lower sensitivity makes the Sensor less responsive.\n\nSet the Sensor sensitivity to 1. For consistency, the tutorial will lock it to 1 after you edit it.",
				TutorialStep.LOWER_SENSOR_SENSITIVITY
			)

		TutorialStep.LOWER_SENSOR_SENSITIVITY:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["sensitivity", "detection_sensitivity"])
			_show_popup(
				"Set the Sensor sensitivity to 1.\n\nThe tutorial will lock the sensitivity to 1 and then continue."
			)

		TutorialStep.EXPLAIN_SENSOR_TUNING:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["tuning_frequency"])
			_original_sensor_tuning = _read_number_from_unit(
				_sensor,
				["tuning_frequency"],
				TUTORIAL_FREQUENCY
			)
			_show_popup(
				"A Sensor has a tuning frequency and bandwidth.\n\nTuning frequency is the frequency the Sensor is listening for. Bandwidth controls how wide of a frequency range the Sensor can detect.",
				TutorialStep.CHANGE_SENSOR_TUNING_AWAY
			)

		TutorialStep.CHANGE_SENSOR_TUNING_AWAY:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["tuning_frequency"])
			_show_popup(
				"Change the Sensor tuning frequency so it no longer matches the Transceiver.\n\nWatch how the detection status changes."
			)

		TutorialStep.EXPLAIN_BANDWIDTH:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["bandwidth"])
			_show_popup(
				"Bandwidth controls how flexible the Sensor is when listening for signals.\n\nA narrow bandwidth is more precise but may miss signals that are slightly different. A wider bandwidth can detect more frequencies.",
				TutorialStep.INCREASE_BANDWIDTH
			)

		TutorialStep.INCREASE_BANDWIDTH:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["bandwidth"])
			_show_popup(
				"Try increasing the Sensor bandwidth.\n\nA wider bandwidth may allow the Sensor to detect signals even when the tuning frequency is not exactly the same."
			)

		TutorialStep.INTRO_JAMMER:
			_clear_placement_marker()
			_lock_sidebar_to([Sidebar.EntityType.JAMMER])
			_lock_attributes([])
			_show_popup(
				"Jammers are used to interfere with communication.\n\nA Jammer can weaken or break a communication link if it overlaps with the frequency being used by the Transceivers.",
				TutorialStep.PLACE_JAMMER
			)

		TutorialStep.PLACE_JAMMER:
			_lock_sidebar_to([Sidebar.EntityType.JAMMER])
			_lock_attributes([])
			_show_placement_marker(JAMMER_POS, "Place\nJammer")
			_show_popup(
				"Place the Jammer on the highlighted target area.\n\nThis location is close enough to demonstrate interference clearly."
			)

		TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["frequency"])
			_jammer_frequency_locked = false
			_original_jammer_frequency = TUTORIAL_FREQUENCY
			_set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)
			_run_simulation_if_possible()
			_show_popup(
				"A Jammer is most effective when its frequency overlaps with the target communication frequency.\n\nChange the Jammer frequency away from 1000 Hz and observe that the link recovers."
			)

		TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK:
			_clear_placement_marker()
			_lock_sidebar_to([])
			_lock_attributes(["frequency"])
			_show_popup(
				"Now change the Jammer frequency back.\n\nFor consistency, the tutorial will lock the Jammer back to 1000 Hz after you edit it."
			)

		TutorialStep.COMPLETE:
			_clear_placement_marker()
			_unlock_sidebar()
			_lock_attributes([])
			_show_completion_popup()


func _on_tutorial_unit_placed(unit: Node) -> void:
	match _tutorial_step:
		TutorialStep.PLACE_FIRST_TRANSCEIVER:
			if _is_transceiver(unit):
				_snap_unit_to_target(unit, FIRST_TRANSCEIVER_POS)
				_first_transceiver = unit
				_enter_step(TutorialStep.FIRST_TRANSCEIVER_PLACED)

		TutorialStep.PLACE_SECOND_TRANSCEIVER:
			if _is_transceiver(unit):
				_snap_unit_to_target(unit, SECOND_TRANSCEIVER_POS)
				_second_transceiver = unit
				_run_simulation_if_possible()
				_enter_step(TutorialStep.EXPLAIN_LINK)

		TutorialStep.PLACE_SENSOR:
			if _is_sensor(unit):
				_snap_unit_to_target(unit, SENSOR_POS)
				_sensor = unit
				_run_simulation_if_possible()
				_enter_step(TutorialStep.EXPLAIN_SENSOR_SENSITIVITY)

		TutorialStep.PLACE_JAMMER:
			if _is_jammer(unit):
				_snap_unit_to_target(unit, JAMMER_POS)
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


func _on_tutorial_attribute_changed(unit: Node, attribute_name: String, new_value: Variant) -> void:
	var attr := attribute_name.to_lower()
	var value := _variant_to_float(new_value, 0.0)

	match _tutorial_step:
		TutorialStep.LOWER_SENSOR_SENSITIVITY:
			if attr.contains("sensitivity"):
				_sensor_sensitivity_locked = true
				_keep_sensor_sensitivity_locked()
				_run_simulation_if_possible()
				_show_popup(
					"Good. The Sensor sensitivity is now locked to 1.\n\nThis keeps the tutorial result consistent every time.",
					TutorialStep.EXPLAIN_SENSOR_TUNING
				)

		TutorialStep.CHANGE_TRANSCEIVER_BANDWIDTHS_NARROW:
			if attr.contains("bandwidth"):
				if _unit_is_or_belongs_to(unit, _first_transceiver):
					_first_transceiver_bandwidth_narrow = true
				elif _unit_is_or_belongs_to(unit, _second_transceiver):
					_second_transceiver_bandwidth_narrow = true

				_run_simulation_if_possible()

				if _first_transceiver_bandwidth_narrow and _second_transceiver_bandwidth_narrow:
					_enter_step(TutorialStep.EXPLAIN_SUCCESSFUL_LINK)

		TutorialStep.CHANGE_FREQUENCY_AWAY:
			if attr.contains("freq") and abs(value - TUTORIAL_FREQUENCY) >= 50.0:
				_tutorial_frequency_locked = false
				_run_simulation_if_possible()
				_show_popup(
					"Notice that the line changed to blue.\n\nThe blue line means the Transceivers are using different frequencies. In EMS, two radios usually need to operate on the same or compatible frequency range to communicate. If the frequency is too different, the signal will not be received correctly.",
					TutorialStep.CHANGE_FREQUENCY_BACK
				)

		TutorialStep.CHANGE_FREQUENCY_BACK:
			if attr.contains("freq"):
				_tutorial_frequency_locked = true
				_keep_transceiver_frequencies_locked()
				_run_simulation_if_possible()
				_show_popup(
					"Good. The tutorial locked both Transceivers back to 1000 Hz so the connection is consistent again.",
					TutorialStep.EXPLAIN_POWER
				)

		TutorialStep.LOWER_POWER:
			if attr.contains("power") and value < _original_power:
				_run_simulation_if_possible()
				_enter_step(TutorialStep.RAISE_POWER)

		TutorialStep.RAISE_POWER:
			if attr.contains("power") and value >= _original_power:
				_run_simulation_if_possible()
				_show_popup(
					"Good. Increasing the power helped restore the link.",
					TutorialStep.EXPLAIN_HEIGHT
				)

		TutorialStep.INCREASE_HEIGHT:
			if attr.contains("height") and value > _original_height:
				_run_simulation_if_possible()
				_show_popup(
					"Increasing height can improve communication range.",
					TutorialStep.INTRO_SENSOR
				)

		TutorialStep.CHANGE_SENSOR_TUNING_AWAY:
			if attr.contains("freq") and abs(value - _original_sensor_tuning) >= 50.0:
				_run_simulation_if_possible()
				_show_popup(
					"The Sensor can no longer detect the signal.\n\nThis shows how frequency and bandwidth affect detection.",
					TutorialStep.EXPLAIN_BANDWIDTH
				)

		TutorialStep.INCREASE_BANDWIDTH:
			if attr.contains("bandwidth"):
				_run_simulation_if_possible()
				_show_popup(
					"Good. A wider bandwidth can make detection more flexible.",
					TutorialStep.INTRO_JAMMER
				)

		TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY:
			if attr.contains("freq") and abs(value - TUTORIAL_FREQUENCY) >= 50.0:
				_jammer_frequency_locked = false
				_run_simulation_if_possible()
				_show_popup(
					"The link recovered because the Jammer is no longer targeting the correct frequency.\n\nNow we will change the Jammer back to 1000 Hz.",
					TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK
				)

		TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK:
			if attr.contains("freq"):
				_jammer_frequency_locked = true
				_keep_jammer_frequency_locked()
				_run_simulation_if_possible()
				_show_popup(
					"Good. The Jammer frequency is now locked back to 1000 Hz.",
					TutorialStep.COMPLETE
				)

		_:
			pass


func _show_popup(text: String, next_step: int = -1) -> void:
	if intro_popup_open:
		return

	var popup := TUTORIAL_HINT_POPUP.instantiate()
	popup.set("hint_text", text)

	intro_popup_open = true
	$CanvasLayer.add_child(popup)

	if popup.has_signal("continued"):
		popup.continued.connect(
			func():
				intro_popup_open = false
				if next_step != -1:
					_enter_step(next_step)
		)


func _show_completion_popup() -> void:
	if _completion_popup != null and is_instance_valid(_completion_popup):
		return

	intro_popup_open = true

	var overlay := Control.new()
	overlay.name = "TutorialCompletionPopup"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 260)
	center.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	style.border_color = Color(0.0, 0.85, 0.55, 1.0)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	panel.add_theme_stylebox_override("panel", style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.custom_minimum_size = Vector2(500, 220)
	panel.add_child(content)

	var title := Label.new()
	title.text = "Tutorial Complete"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.0, 1.0, 0.65, 1.0))
	content.add_child(title)

	var message := Label.new()
	message.text = "You completed Tutorial Mode. You learned how to place units, adjust attributes, create a link, use a Sensor, and understand how a Jammer affects communication.\n\nWhat would you like to do next?"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 16)
	message.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(message)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	content.add_child(buttons)

	var home_button := Button.new()
	home_button.text = "Return to Home Page"
	home_button.custom_minimum_size = Vector2(190, 46)
	home_button.pressed.connect(_go_to_home_page)
	buttons.add_child(home_button)

	var sandbox_button := Button.new()
	sandbox_button.text = "Go to Sandbox Mode"
	sandbox_button.custom_minimum_size = Vector2(190, 46)
	sandbox_button.pressed.connect(_go_to_sandbox_mode)
	buttons.add_child(sandbox_button)

	$CanvasLayer.add_child(overlay)
	_completion_popup = overlay


func _go_to_home_page() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = '%s';" % HOME_URL)
	else:
		print("Return to Home Page is only available in the web build.")


func _go_to_sandbox_mode() -> void:
	get_tree().change_scene_to_file(SANDBOX_SCENE_PATH)


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
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
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


func _snap_unit_to_target(unit: Node, local_pos: Vector2) -> void:
	if unit == null:
		return

	_force_unit_position(unit, local_pos)

	if _is_transceiver(unit):
		_transceiver_positions_locked = true

	_run_simulation_if_possible()


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


func _unit_matches(unit: Node, component_name: String, group_name: String) -> bool:
	if unit == null:
		return false

	if unit.is_in_group(group_name):
		return true

	if unit.name.to_lower().contains(component_name):
		return true

	for child in unit.get_children():
		if child.name.to_lower().contains(component_name):
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


func _unit_is_or_belongs_to(unit: Node, target: Node) -> bool:
	if unit == null or target == null:
		return false

	if unit == target:
		return true

	if target.is_ancestor_of(unit):
		return true

	if unit.is_ancestor_of(target):
		return true

	return false


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


func _lock_all_transceiver_frequencies_to_tutorial_value() -> void:
	_set_number_on_unit(_first_transceiver, ["frequency"], TUTORIAL_FREQUENCY)
	_set_number_on_unit(_second_transceiver, ["frequency"], TUTORIAL_FREQUENCY)
	_set_number_on_unit(_selected_tutorial_unit, ["frequency"], TUTORIAL_FREQUENCY)


func _keep_transceiver_frequencies_locked() -> void:
	if _tutorial_step == TutorialStep.CHANGE_FREQUENCY_AWAY:
		return

	_lock_all_transceiver_frequencies_to_tutorial_value()


func _keep_jammer_frequency_locked() -> void:
	if _tutorial_step == TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY:
		return

	_set_number_on_unit(_jammer, ["frequency"], TUTORIAL_FREQUENCY)


func _keep_sensor_sensitivity_locked() -> void:
	_set_number_on_unit(
		_sensor,
		["sensitivity", "detection_sensitivity"],
		TUTORIAL_SENSOR_SENSITIVITY
	)


func _keep_transceivers_locked_in_place() -> void:
	_force_unit_position(_first_transceiver, FIRST_TRANSCEIVER_POS)
	_force_unit_position(_second_transceiver, SECOND_TRANSCEIVER_POS)


func _force_unit_position(unit: Node, local_pos: Vector2) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	var global_target = map_container.global_position + local_pos

	if unit is Node2D:
		unit.global_position = global_target
	elif unit is Control:
		unit.global_position = global_target
	else:
		unit.set("global_position", global_target)

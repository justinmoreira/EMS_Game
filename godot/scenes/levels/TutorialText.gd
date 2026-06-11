extends RefCounted

const UNIT_ID_TRANSCEIVER := &"transceiver"
const UNIT_ID_SENSOR := &"sensor"
const UNIT_ID_JAMMER := &"jammer"

const FIRST_TRANSCEIVER_POS := Vector2(550, 260)
const FIRST_TRANSCEIVER_GREEN_POS := Vector2(650, 260)
const SECOND_TRANSCEIVER_POS := Vector2(950, 260)
const SENSOR_POS := Vector2(600, 370)
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
	INTRO_DISPLAY_SETTINGS,
	TRY_LINK_LINES_TOGGLE,
	TRY_UNIT_RANGES_TOGGLE,
	VIEW_UNIT_RANGE,
	TRY_UNIT_DETAILS_TOGGLE,
	TRY_SUGGESTIONS_TOGGLE,
	TRY_BIDIRECTIONAL_LINK_LINES_TOGGLE,
	EXPLAIN_HEIGHTMAP_AND_GRID,
	DISPLAY_SETTINGS_COMPLETE,
	COMPLETE
}


static func step_data(step: int) -> Dictionary:
	match step:
		TutorialStep.WELCOME:
			return _step(
				_text(
					[
						"Welcome to Tutorial Mode.\n\n",
						"This walkthrough shows the main EMS tools in order: ",
						"place units, build a link, adjust attributes, detect signals, ",
						"use a jammer, and try the display settings."
					]
				),
				TutorialStep.INTRO_MAP
			)

		TutorialStep.INTRO_MAP:
			return _step(
				_text(
					[
						"This is the simulation map.\n\n",
						"The terrain, distance, and unit settings all affect signal ",
						"behavior. You will start by placing two Transceivers so they ",
						"can try to communicate."
					]
				),
				TutorialStep.PLACE_FIRST_TRANSCEIVER
			)

		TutorialStep.PLACE_FIRST_TRANSCEIVER:
			return _step(
				"Drag Transceiver 1 into the highlighted area on the map.",
				-1,
				[UNIT_ID_TRANSCEIVER],
				[],
				FIRST_TRANSCEIVER_POS,
				"Place\nTransceiver 1"
			)

		TutorialStep.FIRST_TRANSCEIVER_PLACED:
			return _step(
				_text(
					[
						"Good. Transceiver 1 is locked in place.\n\n",
						"Next, place a second Transceiver so the simulation can compare ",
						"their distance, frequency, power, bandwidth, and height."
					]
				),
				TutorialStep.PLACE_SECOND_TRANSCEIVER
			)

		TutorialStep.PLACE_SECOND_TRANSCEIVER:
			return _step(
				"Drag Transceiver 2 into the highlighted area.",
				-1,
				[UNIT_ID_TRANSCEIVER],
				[],
				SECOND_TRANSCEIVER_POS,
				"Place\nTransceiver 2"
			)

		TutorialStep.EXPLAIN_LINK:
			return _step(
				_text(
					[
						"The Transceivers are now trying to communicate.\n\n",
						"Line colors show the current result:\n",
						"Green: successful link\n",
						"Orange: too weak or out of range\n",
						"Red: jammed\n",
						"Purple: bandwidth penalty\n",
						"Blue: frequency mismatch"
					]
				),
				TutorialStep.EXPLAIN_BANDWIDTH_PENALTY
			)

		TutorialStep.EXPLAIN_BANDWIDTH_PENALTY:
			return _step(
				_text(
					[
						"The purple line means the link is possible, but the bandwidth ",
						"setting is reducing performance.\n\n",
						"Frequency matching depends on bandwidth:\n",
						"Narrow: 1 MHz, ±0.5 MHz\n",
						"Medium: 10 MHz, ±5 MHz\n",
						"Wide: 50 MHz, ±25 MHz\n",
					]
				),
				TutorialStep.MOVE_FIRST_TRANSCEIVER_CLOSER
			)

		TutorialStep.MOVE_FIRST_TRANSCEIVER_CLOSER:
			return _step(
				_text(
					[
						"Move Transceiver 1 into the new highlighted area. ",
						"The tutorial will continue when it reaches the marker."
					]
				),
				-1,
				[],
				[],
				FIRST_TRANSCEIVER_GREEN_POS,
				"Move\nTransceiver 1"
			)

		TutorialStep.EXPLAIN_SUCCESSFUL_LINK:
			return _step(
				_text(
					[
						"Good. The green line means the link is working.\n\n",
						"Now you will edit Transceiver 1 and watch how each attribute ",
						"affects the result."
					]
				),
				TutorialStep.SELECT_TRANSCEIVER
			)

		TutorialStep.SELECT_TRANSCEIVER:
			return _step(
				_text(
					[
						"Click Transceiver 1 to open its attributes.\n\n",
						"Only Transceiver 1 will be editable. Transceiver 2 stays ",
						"locked so the tutorial remains consistent."
					]
				),
				TutorialStep.EXPLAIN_FREQUENCY
			)

		TutorialStep.EXPLAIN_FREQUENCY:
			return _step(
				_text(
					[
						"Frequency controls the channel a unit uses.\n\n",
						"These Transceivers use Medium bandwidth, so their frequencies ",
						"must stay within 995 to 1005. First, move Transceiver 1 outside ",
						"that range, then press Confirm."
					]
				),
				TutorialStep.CHANGE_FREQUENCY_AWAY
			)

		TutorialStep.CHANGE_FREQUENCY_AWAY:
			return _step("Set Transceiver 1 frequency below 995 or above 1005, then press Confirm.")

		TutorialStep.CHANGE_FREQUENCY_BACK:
			return _step(
				"Now return Transceiver 1 frequency to 995 through 1005, then press Confirm."
			)

		TutorialStep.EXPLAIN_POWER:
			return _step(
				_text(
					[
						"Power controls signal strength.\n\n",
						"Lower power can make a link weaker. Higher power can help range, ",
						"but it may also make the unit easier to detect. Lower ",
						"Transceiver 1 power, then press Confirm."
					]
				),
				TutorialStep.LOWER_POWER
			)

		TutorialStep.LOWER_POWER:
			return _step("Lower Transceiver 1 power, then press Confirm.")

		TutorialStep.RAISE_POWER:
			return _step("Raise Transceiver 1 power back to 5, then press Confirm.")

		TutorialStep.EXPLAIN_HEIGHT:
			return _step(
				_text(
					[
						"Antenna height can improve the signal path.\n\n",
						"Increase Transceiver 1 height, then press Confirm."
					]
				),
				TutorialStep.INCREASE_HEIGHT
			)

		TutorialStep.INCREASE_HEIGHT:
			return _step("Increase Transceiver 1 antenna height, then press Confirm.")

		TutorialStep.INTRO_SENSOR:
			return _step(
				_text(
					[
						"Next is the Sensor.\n\n",
						"A Sensor does not create a communication link. It listens for ",
						"Transceiver signals nearby."
					]
				),
				TutorialStep.PLACE_SENSOR,
				[UNIT_ID_SENSOR]
			)

		TutorialStep.PLACE_SENSOR:
			return _step(
				"Place the Sensor inside the highlighted area.",
				-1,
				[UNIT_ID_SENSOR],
				[],
				SENSOR_POS,
				"Place\nSensor"
			)

		TutorialStep.EXPLAIN_SENSOR_SENSITIVITY:
			return _step(
				_text(["Sensitivity controls how easily the Sensor detects a signal.\n\n"]),
				TutorialStep.LOWER_SENSOR_SENSITIVITY
			)

		TutorialStep.LOWER_SENSOR_SENSITIVITY:
			return _step("Lower the Sensor sensitivity, then press Confirm.")

		TutorialStep.EXPLAIN_SENSOR_TUNING:
			return _step(
				_text(
					[
						"Now adjust what the Sensor listens for.\n\n",
						"Tuning frequency is the center frequency. Bandwidth is how wide ",
						"the listening range is. Move the tuning frequency away from ",
						"1000, then press Confirm."
					]
				),
				TutorialStep.CHANGE_SENSOR_TUNING_AWAY
			)

		TutorialStep.CHANGE_SENSOR_TUNING_AWAY:
			return _step("Move the Sensor tuning frequency away from 1000, then press Confirm.")

		TutorialStep.EXPLAIN_BANDWIDTH:
			return _step(
				_text(
					[
						"Bandwidth makes detection more flexible.\n\n",
						"A wider bandwidth covers a wider frequency range. Change the ",
						"Sensor bandwidth, then press Confirm."
					]
				),
				TutorialStep.INCREASE_BANDWIDTH
			)

		TutorialStep.INCREASE_BANDWIDTH:
			return _step("Increase the Sensor bandwidth, then press Confirm.")

		TutorialStep.INTRO_JAMMER:
			return _step(
				_text(
					[
						"Now add a Jammer.\n\n",
						"A Jammer can weaken or break a communication link when its ",
						"frequency overlaps the target."
					]
				),
				TutorialStep.PLACE_JAMMER,
				[UNIT_ID_JAMMER]
			)

		TutorialStep.PLACE_JAMMER:
			return _step(
				"Place the Jammer inside the highlighted area.",
				-1,
				[UNIT_ID_JAMMER],
				[],
				JAMMER_POS,
				"Place\nJammer"
			)

		TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY:
			return _step(
				_text(
					[
						"The Jammer is tuned to the same frequency as the Transceivers.\n\n",
						"Move the Jammer frequency below 995 or above 1005,, then press Confirm."
					]
				)
			)

		TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK:
			return _step("Move the Jammer frequency within 995 through 1005, then press Confirm.")

		TutorialStep.INTRO_DISPLAY_SETTINGS:
			return _step(
				_text(
					[
						"Before finishing, try the Display Settings in the top-right ",
						"gear menu.\n\n",
						"These toggles do not change the simulation math. They change ",
						"what information is visible on screen. You will test each ",
						"toggle once."
					]
				),
				TutorialStep.TRY_LINK_LINES_TOGGLE
			)

		TutorialStep.TRY_LINK_LINES_TOGGLE:
			return _step(
				_text(
					[
						"Open the gear menu and toggle Link Lines.\n\n",
						"This shows or hides the connection lines between Transceivers."
					]
				)
			)

		TutorialStep.TRY_UNIT_RANGES_TOGGLE:
			return _step(
				"Toggle Unit Ranges.\n\nThis shows or hides the range circles around units."
			)

		TutorialStep.VIEW_UNIT_RANGE:
			return _step(
				_text(
					[
						"Now click any unit on the map.\n\n",
						"When Unit Ranges are visible, selecting a unit makes it easier ",
						"to inspect that unit's range circle and understand its coverage."
					]
				)
			)

		TutorialStep.TRY_UNIT_DETAILS_TOGGLE:
			return _step(
				"Toggle Unit Details.\n\nThis shows or hides extra unit information on the map."
			)

		TutorialStep.TRY_SUGGESTIONS_TOGGLE:
			return _step(
				"Toggle Suggestions.\n\nThis turns guidance hints or visual aids on and off."
			)

		TutorialStep.TRY_BIDIRECTIONAL_LINK_LINES_TOGGLE:
			return _step(
				_text(
					[
						"Toggle Bidirectional Link Lines.\n\n",
						"This controls whether both directions of a Transceiver link ",
						"are shown."
					]
				)
			)

		TutorialStep.EXPLAIN_HEIGHTMAP_AND_GRID:
			return _step(
				_text(
					[
						"Heightmap Shader changes how the terrain elevation is rendered, ",
						"which can make hills and low areas easier to see.\n\n",
						"GRID shows or hides the map grid overlay, which helps with ",
						"spacing and placement. You do not need to toggle these now."
					]
				),
				TutorialStep.DISPLAY_SETTINGS_COMPLETE
			)

		TutorialStep.DISPLAY_SETTINGS_COMPLETE:
			return _step(
				_text(
					[
						"Good. You tried the main display settings.\n\n",
						"Use these toggles whenever you want a cleaner view or more ",
						"visual information while testing EMS scenarios."
					]
				),
				TutorialStep.COMPLETE
			)

		_:
			return _step("")


static func should_run_simulation_on_enter(step: int) -> bool:
	return (
		step
		in [
			TutorialStep.EXPLAIN_LINK,
			TutorialStep.EXPLAIN_BANDWIDTH_PENALTY,
			TutorialStep.EXPLAIN_SUCCESSFUL_LINK
		]
	)


static func attributes_for_step(step: int) -> Array:
	match step:
		TutorialStep.EXPLAIN_FREQUENCY:
			return ["frequency"]
		TutorialStep.CHANGE_FREQUENCY_AWAY:
			return ["frequency"]
		TutorialStep.CHANGE_FREQUENCY_BACK:
			return ["frequency"]
		TutorialStep.EXPLAIN_POWER:
			return ["power"]
		TutorialStep.LOWER_POWER:
			return ["power"]
		TutorialStep.RAISE_POWER:
			return ["power"]
		TutorialStep.EXPLAIN_HEIGHT:
			return ["height"]
		TutorialStep.INCREASE_HEIGHT:
			return ["height"]
		TutorialStep.EXPLAIN_SENSOR_SENSITIVITY:
			return ["sensitivity", "detection_sensitivity"]
		TutorialStep.LOWER_SENSOR_SENSITIVITY:
			return ["sensitivity", "detection_sensitivity"]
		TutorialStep.EXPLAIN_SENSOR_TUNING:
			return ["tuning_frequency"]
		TutorialStep.CHANGE_SENSOR_TUNING_AWAY:
			return ["tuning_frequency"]
		TutorialStep.EXPLAIN_BANDWIDTH:
			return ["bandwidth"]
		TutorialStep.INCREASE_BANDWIDTH:
			return ["bandwidth"]
		TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY:
			return ["frequency"]
		TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK:
			return ["frequency"]
		_:
			return []


static func edit_target_for_step(step: int) -> String:
	if (
		step
		in [
			TutorialStep.EXPLAIN_FREQUENCY,
			TutorialStep.CHANGE_FREQUENCY_AWAY,
			TutorialStep.CHANGE_FREQUENCY_BACK,
			TutorialStep.EXPLAIN_POWER,
			TutorialStep.LOWER_POWER,
			TutorialStep.RAISE_POWER,
			TutorialStep.EXPLAIN_HEIGHT,
			TutorialStep.INCREASE_HEIGHT
		]
	):
		return "transceiver"
	if (
		step
		in [
			TutorialStep.EXPLAIN_SENSOR_SENSITIVITY,
			TutorialStep.LOWER_SENSOR_SENSITIVITY,
			TutorialStep.EXPLAIN_SENSOR_TUNING,
			TutorialStep.CHANGE_SENSOR_TUNING_AWAY,
			TutorialStep.EXPLAIN_BANDWIDTH,
			TutorialStep.INCREASE_BANDWIDTH
		]
	):
		return "sensor"
	if (
		step
		in [TutorialStep.CHANGE_JAMMER_FREQUENCY_AWAY, TutorialStep.CHANGE_JAMMER_FREQUENCY_BACK]
	):
		return "jammer"
	return ""


static func display_setting_key_for_step(step: int) -> String:
	match step:
		TutorialStep.TRY_LINK_LINES_TOGGLE:
			return "link_lines"
		TutorialStep.TRY_UNIT_RANGES_TOGGLE:
			return "unit_ranges"
		TutorialStep.TRY_UNIT_DETAILS_TOGGLE:
			return "unit_details"
		TutorialStep.TRY_SUGGESTIONS_TOGGLE:
			return "suggestions"
		TutorialStep.TRY_BIDIRECTIONAL_LINK_LINES_TOGGLE:
			return "bidirectional_link_lines"
		_:
			return ""


static func display_toggle_node_names(setting_key: String) -> Array[String]:
	match setting_key:
		"link_lines":
			return ["LinkLinesToggle", "LinkLineToggle", "LinksToggle"]
		"unit_ranges":
			return ["UnitRangesToggle", "RangeToggle", "RangesToggle"]
		"unit_details":
			return ["UnitDetailsToggle", "DetailsToggle"]
		"suggestions":
			return ["SuggestionsToggle", "SuggestionToggle"]
		"bidirectional_link_lines":
			return ["BidirectionalLinkLinesToggle", "BidirectionalToggle"]
		"heightmap_shader":
			return ["HeightmapShaderToggle", "ShaderToggle", "Toggle"]
		"grid":
			return ["GridToggle", "GRIDToggle"]
		_:
			return []


static func display_setting_result(setting_key: String) -> Dictionary:
	match setting_key:
		"link_lines":
			return _step(
				"Good. Link Lines control the communication line visuals.",
				TutorialStep.TRY_UNIT_RANGES_TOGGLE
			)
		"unit_ranges":
			return _step(
				"Good. Unit Ranges help you see each unit's coverage area.",
				TutorialStep.VIEW_UNIT_RANGE
			)
		"unit_details":
			return _step(
				"Good. Unit Details add or remove extra map labels.",
				TutorialStep.TRY_SUGGESTIONS_TOGGLE
			)
		"suggestions":
			return _step(
				"Good. Suggestions can provide extra guidance.",
				TutorialStep.TRY_BIDIRECTIONAL_LINK_LINES_TOGGLE
			)
		"bidirectional_link_lines":
			return _step(
				"Good. Bidirectional Link Lines show both directions.",
				TutorialStep.EXPLAIN_HEIGHTMAP_AND_GRID
			)
		_:
			return _step("Good. That display setting changed.")


static func _step(
	text: String,
	next_step: int = -1,
	sidebar: Array = [],
	attributes: Array = [],
	marker: Variant = null,
	label: String = ""
) -> Dictionary:
	return {
		"text": text,
		"next": next_step,
		"sidebar": sidebar,
		"attributes": attributes,
		"marker": marker,
		"label": label
	}


static func _text(parts: Array) -> String:
	var text := ""

	for part in parts:
		text += str(part)

	return text

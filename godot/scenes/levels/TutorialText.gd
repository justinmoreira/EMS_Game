extends RefCounted

const UNIT_ID_TRANSCEIVER := &"transceiver"
const UNIT_ID_SENSOR := &"sensor"
const UNIT_ID_JAMMER := &"jammer"

# Tutorial target positions, expressed as world_uv (normalized 0..1 across the
# map) so they track the live map transform — zoom, pan, and window/resolution
# changes — instead of being pinned to fixed screen pixels. Authored as canonical
# map pixels over BaseLevel.MAP_SIZE (1080x1080) and divided to normalize.
const MAP_PX := Vector2(1080, 1080)
const FIRST_TRANSCEIVER_POS := Vector2(280, 660) / MAP_PX
const FIRST_TRANSCEIVER_GREEN_POS := Vector2(360, 660) / MAP_PX
const SECOND_TRANSCEIVER_POS := Vector2(580, 660) / MAP_PX
const SENSOR_POS := Vector2(470, 810) / MAP_PX
const JAMMER_POS := Vector2(490, 550) / MAP_PX

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
	INTRO_SPECTRUM_ANALYZER,
	ENABLE_SPECTRUM_ANALYZER,
	SELECT_SENSOR_FOR_SPECTRUM,
	START_SPECTRUM_SCAN,
	EXPLAIN_SPECTRUM_MATCH,
	INTRO_JAMMER,
	PLACE_JAMMER,
	CHANGE_JAMMER_FREQUENCY_AWAY,
	CHANGE_JAMMER_FREQUENCY_BACK,
	INTRO_DISPLAY_SETTINGS,
	TRY_LINK_LINES_TOGGLE,
	TRY_UNIT_RANGES_TOGGLE,
	VIEW_UNIT_RANGE,
	TRY_UNIT_DETAILS_TOGGLE,
	TURN_OFF_UNIT_DETAILS,
	TRY_SUGGESTIONS_TOGGLE,
	TURN_OFF_SUGGESTIONS,
	TRY_TERRAIN_HEATMAP_TOGGLE,
	SELECT_UNIT_FOR_HEATMAP,
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

		TutorialStep.INTRO_SPECTRUM_ANALYZER:
			return _step(
				_text(
					[
						"The Sensor Spectrum Analyzer graphs the signals a Sensor ",
						"hears across the frequency range.\n\n",
						"Peaks appear where nearby units emit. When a peak lines up ",
						"with the Transceivers' frequency, the Sensor is picking up ",
						"their link."
					]
				),
				TutorialStep.ENABLE_SPECTRUM_ANALYZER
			)

		TutorialStep.ENABLE_SPECTRUM_ANALYZER:
			return _step(
				_text(
					[
						"Open the top-right gear menu and turn on Spectrum Analyzer.\n\n",
						"This opens the analyzer panel beside the map."
					]
				)
			)

		TutorialStep.SELECT_SENSOR_FOR_SPECTRUM:
			return _step(
				_text(
					[
						"Click the Sensor on the map.\n\n",
						"The analyzer follows the selected Sensor, so it now shows ",
						"what this Sensor can hear."
					]
				)
			)

		TutorialStep.START_SPECTRUM_SCAN:
			return _step(
				_text(
					[
						"Press START in the analyzer panel.\n\n",
						"The Sensor sweeps the frequency range and draws a live trace ",
						"of the signal it detects."
					]
				)
			)

		TutorialStep.EXPLAIN_SPECTRUM_MATCH:
			return _step(
				_text(
					[
						"Watch the peak that rises near 1000 on the trace.\n\n",
						"That bump is the Transceivers' signal. Because the Sensor ",
						"tuning overlaps their frequency, their link stands out above ",
						"the noise floor. If a unit's frequency moves away, the peak ",
						"shifts or fades."
					]
				),
				TutorialStep.INTRO_JAMMER
			)

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
						"Move the Jammer frequency below 995 or above 1005, then press Confirm."
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
			return _step("Turn on Unit Details.\n\nThis shows extra unit information on the map.")

		TutorialStep.TURN_OFF_UNIT_DETAILS:
			return _step(
				_text(
					[
						"Now turn Unit Details back off.\n\n",
						"This keeps the interface clear before moving to the next display setting."
					]
				)
			)

		TutorialStep.TRY_SUGGESTIONS_TOGGLE:
			return _step("Turn on Suggestions.\n\nThis displays guidance hints or visual aids.")

		TutorialStep.TURN_OFF_SUGGESTIONS:
			return _step(
				_text(
					[
						"Now turn Suggestions back off.\n\n",
						"This removes the extra guidance and leaves a cleaner interface to work with."
					]
				)
			)

		TutorialStep.TRY_TERRAIN_HEATMAP_TOGGLE:
			return _step(
				_text(
					[
						"Toggle Terrain Interference Heatmap.\n\n",
						"This visualizes where terrain may weaken signal paths. Hills, ",
						"elevation changes, and blocked paths can make communication ",
						"less reliable, so the heatmap helps explain why a link may be ",
						"stronger in one area and weaker in another."
					]
				)
			)

		TutorialStep.SELECT_UNIT_FOR_HEATMAP:
			return _step(
				_text(
					[
						"Now click any unit on the map to display that unit's terrain ",
						"interference heatmap."
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
		TutorialStep.TURN_OFF_UNIT_DETAILS:
			return "unit_details"
		TutorialStep.TRY_SUGGESTIONS_TOGGLE:
			return "suggestions"
		TutorialStep.TURN_OFF_SUGGESTIONS:
			return "suggestions"
		TutorialStep.TRY_TERRAIN_HEATMAP_TOGGLE:
			return "terrain_heatmap"
		TutorialStep.ENABLE_SPECTRUM_ANALYZER:
			return "spectrum"
		_:
			return ""


static func display_setting_target_for_step(step: int) -> Variant:
	match step:
		TutorialStep.TRY_UNIT_DETAILS_TOGGLE:
			return true
		TutorialStep.TURN_OFF_UNIT_DETAILS:
			return false
		TutorialStep.TRY_SUGGESTIONS_TOGGLE:
			return true
		TutorialStep.TURN_OFF_SUGGESTIONS:
			return false
		TutorialStep.ENABLE_SPECTRUM_ANALYZER:
			return true
		_:
			return null


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
		"terrain_heatmap":
			return [
				"TerrainInterferenceHeatmapToggle",
				"TerrainHeatmapToggle",
				"InterferenceHeatmapToggle",
				"HeatmapToggle",
				"TerrainToggle"
			]
		"heightmap_shader":
			return ["HeightmapShaderToggle", "ShaderToggle", "Toggle"]
		"grid":
			return ["GridToggle", "GRIDToggle"]
		"spectrum":
			return ["SpectrumToggle", "SpectrumAnalyzerToggle"]
		_:
			return []


static func display_setting_result(setting_key: String, step: int = -1) -> Dictionary:
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
			if step == TutorialStep.TRY_UNIT_DETAILS_TOGGLE:
				return _step(
					"Good. Unit Details are now visible.", TutorialStep.TURN_OFF_UNIT_DETAILS
				)
			return _step(
				"Good. Unit Details are off again, leaving a cleaner map.",
				TutorialStep.TRY_SUGGESTIONS_TOGGLE
			)
		"suggestions":
			if step == TutorialStep.TRY_SUGGESTIONS_TOGGLE:
				return _step(
					"Good. Suggestions are now visible.", TutorialStep.TURN_OFF_SUGGESTIONS
				)
			return _step(
				"Good. Suggestions are off again, so the interface is clear.",
				TutorialStep.TRY_TERRAIN_HEATMAP_TOGGLE
			)
		"terrain_heatmap":
			return _step(
				_text(
					[
						"Good. The Terrain Interference Heatmap is now enabled.\n\n",
						"Next, select a unit so the map can show terrain visibility ",
						"from that unit's position."
					]
				),
				TutorialStep.SELECT_UNIT_FOR_HEATMAP
			)
		"spectrum":
			return _step(
				_text(
					[
						"Good. The Spectrum Analyzer panel is open.\n\n",
						"Now select the Sensor so the analyzer listens through it."
					]
				),
				TutorialStep.SELECT_SENSOR_FOR_SPECTRUM
			)
		_:
			return _step("Good. That display setting changed.")


static func unit_range_selected_text() -> String:
	return "Good. Selecting a unit lets you inspect its range circle."


static func heatmap_selected_text() -> String:
	return _text(
		[
			"The heatmap is now centered on the selected unit.\n\n",
			"Green areas show locations where the unit has the clearest ",
			"view and the least terrain interference. Yellow and orange ",
			"areas show weaker visibility, while red areas show locations ",
			"where terrain makes it difficult for the unit to see or reach."
		]
	)


static func frequency_outside_text() -> String:
	return _text(
		[
			"Good. Transceiver 1 is outside the matching range.\n\n",
			"Now move the frequency back between 995 and 1005."
		]
	)


static func frequency_restored_text() -> String:
	return "Good. The Transceivers are back inside the matching range."


static func power_restored_text() -> String:
	return "Good. Increasing power helped restore the link."


static func height_increased_text() -> String:
	return "Good. Increasing height can improve communication."


static func sensitivity_lowered_text() -> String:
	return "Good. Lowering sensitivity makes detection less likely."


static func sensor_tuning_changed_text() -> String:
	return _text(
		[
			"The Sensor can no longer detect the signal.\n\n",
			"This shows how frequency affects detection."
		]
	)


static func bandwidth_increased_text() -> String:
	return "Good. A wider bandwidth makes detection more flexible."


static func jammer_moved_away_text() -> String:
	return _text(
		["The link recovered because the Jammer moved away ", "from the correct frequency."]
	)


static func jammer_restored_text() -> String:
	return "Good. The Jammer is locked back to 1000."


static func wrong_placement_text() -> String:
	return _text(
		[
			"That unit is not in the correct spot yet.\n\n",
			"Move it into the highlighted area on the map."
		]
	)


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

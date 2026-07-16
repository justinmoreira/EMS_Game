extends CanvasLayer

# Settings state
var settings = {
	"link_lines": true,
	"focus_link_lines": true,
	"successful_link_lines": false,
	"unit_ranges": false,
	"unit_details": false,
	"suggestions": false,
	"detection_hints": false,
	"heatmap": false,
	"spectrum": false,
	"heightmap_shader": true,
	"grid": true
}

var _active_spectrum: SpectrumAnalyzer = null
var _selected_sensor: Node = null

signal spectrum_analyzer_spawned(analyzer: SpectrumAnalyzer)
signal spectrum_analyzer_despawned

const SPECTRUM_GAP := 60.0


func _ready():
	# Old toggles
	%Toggle.toggled.connect(_on_shader_toggled)
	%GridToggle.toggled.connect(_on_grid_toggled)

	# Connect settings button
	%SettingsButton.pressed.connect(_on_settings_button_pressed)

	# Connect new UI toggles
	%LinkLinesToggle.toggled.connect(_on_link_lines_toggled)
	%FocusLinkLinesToggle.toggled.connect(_on_focus_link_lines_toggled)
	%SuccessfulLinesToggle.toggled.connect(_on_successful_link_lines_toggled)
	%UnitRangesToggle.toggled.connect(_on_unit_ranges_toggled)
	%UnitDetailsToggle.toggled.connect(_on_unit_details_toggled)
	%SuggestionsToggle.toggled.connect(_on_suggestions_toggled)
	%DetectionHintsToggle.toggled.connect(_on_detection_hints_toggled)
	%HeatmapToggle.toggled.connect(_on_heatmap_toggled)
	%SpectrumToggle.toggled.connect(_on_spectrum_toggled)

	if get_parent().get_script() == Sandbox:
		%GenerateTerrain.button_down.connect(_on_regenerate_clicked)
	else:
		%GenerateTerrain.disabled = true

	GameEvents.selection_changed.connect(_set_selected_sensor)

	# Load saved settings
	_load_settings()


func _process(_delta: float) -> void:
	if _active_spectrum == null:
		return

	if not is_instance_valid(_selected_sensor):
		_despawn_spectrum()
		return

	_position_spectrum(_selected_sensor)


func _input(event: InputEvent):
	# Close popup when clicking outside of it
	if event is InputEventMouseButton and event.pressed:
		var popup = %SettingsPopup
		if popup.visible:
			# Get mouse position
			var mouse_pos = get_viewport().get_mouse_position()
			# Get popup rect using position and size
			var popup_rect = Rect2(popup.position, popup.size)
			if not popup_rect.has_point(mouse_pos):
				_close_popup()
				get_tree().root.set_input_as_handled()


func _on_regenerate_clicked():
	var level = get_tree().current_scene
	if level.has_method("set_terrain_seed") and level.has_method("_regenerate_terrain"):
		level.set_terrain_seed(randi())
		GameEvents.units_changed.emit()


func _on_settings_button_pressed():
	var popup = %SettingsPopup

	# Toggle popup visibility
	if popup.visible:
		popup.hide()
	else:
		var button_rect = %SettingsButton.get_global_rect()

		# Position popup below the button
		var popup_pos = (
			button_rect.position + Vector2(button_rect.size.x - 280, button_rect.size.y + 5)
		)
		popup.position = popup_pos
		popup.show()
		popup.grab_focus()


func _close_popup():
	%SettingsPopup.hide()


func _on_shader_toggled(is_pressed: bool):
	settings["heightmap_shader"] = is_pressed
	_save_settings()
	var level = get_tree().current_scene
	if level.has_method("toggle_shader"):
		level.toggle_shader(is_pressed)


func _on_grid_toggled(is_pressed: bool):
	settings["grid"] = is_pressed
	_save_settings()
	var level = get_tree().current_scene
	if level.has_method("toggle_grid"):
		level.toggle_grid(is_pressed)


func _on_link_lines_toggled(is_pressed: bool):
	settings["link_lines"] = is_pressed
	_save_settings()

	if LinkRenderer:
		LinkRenderer.links_visible = is_pressed
		LinkRenderer._refresh_all_visibility()
	SimulationManager.simulate()

	# Gray out focus toggle when link lines are off entirely
	if not is_pressed and settings["focus_link_lines"]:
		%FocusLinkLinesToggle.button_pressed = false
		%SuccessfulLinesToggle.button_pressed = false
	%FocusLinkLinesToggle.disabled = not is_pressed
	%SuccessfulLinesToggle.disabled = not is_pressed


func _on_unit_ranges_toggled(is_pressed: bool):
	settings["unit_ranges"] = is_pressed
	_save_settings()

	var level = get_tree().current_scene
	if level.has_method("toggle_signal_ranges"):
		level.toggle_signal_ranges(is_pressed)


func _on_heatmap_toggled(is_pressed: bool):
	settings["heatmap_toggled"] = is_pressed
	_save_settings()

	var level = get_tree().current_scene
	if level.has_method("toggle_terrain_heatmap"):
		level.toggle_terrain_heatmap(is_pressed)


func _on_unit_details_toggled(is_pressed: bool):
	settings["unit_details"] = is_pressed
	_save_settings()

	var level = get_tree().current_scene
	if level.has_method("toggle_unit_details"):
		level.toggle_unit_details(is_pressed)


func _on_suggestions_toggled(is_pressed: bool):
	settings["suggestions"] = is_pressed
	_save_settings()

	var level = get_tree().current_scene
	if level.has_method("toggle_suggestions"):
		level.toggle_suggestions(is_pressed)


func _on_detection_hints_toggled(is_pressed: bool):
	settings["detection_hints"] = is_pressed
	_save_settings()

	var level = get_tree().current_scene
	if level.has_method("toggle_detection_hints"):
		level.toggle_detection_hints(is_pressed)


func _on_spectrum_toggled(is_pressed: bool):
	settings["spectrum"] = is_pressed
	_save_settings()

	var level = get_tree().current_scene
	if level.has_method("toggle_spectrum"):
		level.toggle_spectrum(is_pressed)

	_refresh_spectrum()


func set_spectrum_enabled(enabled: bool) -> void:
	settings["spectrum"] = enabled
	%SpectrumToggle.button_pressed = enabled
	_on_spectrum_toggled(enabled)


func _on_focus_link_lines_toggled(is_pressed: bool):
	settings["focus_link_lines"] = is_pressed
	_save_settings()

	if LinkRenderer:
		LinkRenderer.focus_mode = is_pressed
		LinkRenderer._refresh_all_visibility()
	SimulationManager.simulate()


func _on_successful_link_lines_toggled(is_pressed: bool):
	settings["successful_link_lines"] = is_pressed
	_save_settings()

	if LinkRenderer:
		LinkRenderer.success_only_mode = is_pressed
		LinkRenderer._refresh_all_visibility()
	SimulationManager.simulate()


func _save_settings() -> void:
	var config = ConfigFile.new()
	for key in settings:
		config.set_value("display", key, settings[key])
	config.save("user://ems_game_settings.cfg")


func _load_settings() -> void:
	var config = ConfigFile.new()
	var error = config.load("user://ems_game_settings.cfg")

	if error == OK:
		for key in settings:
			if config.has_section_key("display", key):
				settings[key] = config.get_value("display", key)

	# Update UI to match loaded settings
	%LinkLinesToggle.button_pressed = settings["link_lines"]
	%FocusLinkLinesToggle.button_pressed = settings["focus_link_lines"]
	%SuccessfulLinesToggle.button_pressed = settings["successful_link_lines"]
	%UnitRangesToggle.button_pressed = settings["unit_ranges"]
	%UnitDetailsToggle.button_pressed = settings["unit_details"]
	%SuggestionsToggle.button_pressed = settings["suggestions"]
	%DetectionHintsToggle.button_pressed = settings["detection_hints"]
	%HeatmapToggle.button_pressed = settings["heatmap"]
	%SpectrumToggle.button_pressed = settings["spectrum"]
	%Toggle.button_pressed = settings["heightmap_shader"]
	%GridToggle.button_pressed = settings["grid"]

	if LinkRenderer:
		LinkRenderer.links_visible = settings["link_lines"]
		LinkRenderer.focus_mode = settings["focus_link_lines"]
		LinkRenderer.success_only_mode = settings["successful_link_lines"]
	%FocusLinkLinesToggle.disabled = not settings["link_lines"]

	var level = get_tree().current_scene
	if level and level.has_method("toggle_spectrum"):
		level.toggle_spectrum(settings["spectrum"])

	SimulationManager.simulate()
	_refresh_spectrum()


# Spectrum analyzer handling


func get_active_spectrum() -> SpectrumAnalyzer:
	return _active_spectrum


func _set_selected_sensor(unit: Node) -> void:
	_selected_sensor = unit if _is_sensor_unit(unit) else null
	_refresh_spectrum()


func _is_sensor_unit(unit: Node) -> bool:
	return unit != null and is_instance_valid(unit) and unit.is_in_group("sensors")


func _refresh_spectrum() -> void:
	var should_show: bool = (
		settings["spectrum"] and _selected_sensor != null and is_instance_valid(_selected_sensor)
	)

	if should_show and _active_spectrum == null:
		_spawn_spectrum(_selected_sensor)
	elif not should_show and _active_spectrum != null:
		_despawn_spectrum()


func _spawn_spectrum(sensor: Node) -> void:
	_active_spectrum = SpectrumAnalyzer.new()
	add_child(_active_spectrum)
	_active_spectrum.configure(sensor)
	_position_spectrum(sensor)
	spectrum_analyzer_spawned.emit(_active_spectrum)


func _despawn_spectrum() -> void:
	if _active_spectrum != null and is_instance_valid(_active_spectrum):
		_active_spectrum.queue_free()
	_active_spectrum = null
	spectrum_analyzer_despawned.emit()


# Position above the sensor unless there is no room
func _position_spectrum(sensor: Node) -> void:
	if _active_spectrum == null:
		return

	var world_pos: Vector2 = sensor.get("global_position")
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos

	var above_y := screen_pos.y - _active_spectrum.size.y - SPECTRUM_GAP
	var visible_top := get_viewport().get_visible_rect().position.y

	var target_y: float
	if above_y < visible_top:
		target_y = screen_pos.y + SPECTRUM_GAP
	else:
		target_y = above_y

	_active_spectrum.position = Vector2(screen_pos.x - _active_spectrum.size.x / 2.0, target_y)

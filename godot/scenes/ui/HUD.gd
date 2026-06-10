extends CanvasLayer

# Settings state
var settings = {
	"link_lines": true,
	"focus_link_lines": true,
	"unit_ranges": false,
	"unit_details": false,
	"suggestions": false,
	"heatmap": false,
	"heightmap_shader": true,
	"grid": true
}


func _ready():
	# Old toggles
	%Toggle.toggled.connect(_on_shader_toggled)
	%GridToggle.toggled.connect(_on_grid_toggled)

	# Connect settings button
	%SettingsButton.pressed.connect(_on_settings_button_pressed)

	# Connect new UI toggles
	%LinkLinesToggle.toggled.connect(_on_link_lines_toggled)
	%FocusLinkLinesToggle.toggled.connect(_on_focus_link_lines_toggled)
	%UnitRangesToggle.toggled.connect(_on_unit_ranges_toggled)
	%UnitDetailsToggle.toggled.connect(_on_unit_details_toggled)
	%SuggestionsToggle.toggled.connect(_on_suggestions_toggled)
	%HeatmapToggle.toggled.connect(_on_heatmap_toggled)

	# Load saved settings
	_load_settings()


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
	var level = get_tree().current_scene
	if level.has_method("toggle_shader"):
		level.toggle_shader(is_pressed)


func _on_grid_toggled(is_pressed: bool):
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
	%FocusLinkLinesToggle.disabled = not is_pressed


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

	# ADD LATER


func _on_focus_link_lines_toggled(is_pressed: bool):
	settings["focus_link_lines"] = is_pressed
	_save_settings()

	if LinkRenderer:
		LinkRenderer.focus_mode = is_pressed
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
	%UnitRangesToggle.button_pressed = settings["unit_ranges"]
	%UnitDetailsToggle.button_pressed = settings["unit_details"]
	%SuggestionsToggle.button_pressed = settings["suggestions"]
	%HeatmapToggle.button_pressed = settings["heatmap"]
	%Toggle.button_pressed = settings["heightmap_shader"]
	%GridToggle.button_pressed = settings["grid"]

	if LinkRenderer:
		LinkRenderer.links_visible = settings["link_lines"]
		LinkRenderer.focus_mode = settings["focus_link_lines"]
	%FocusLinkLinesToggle.disabled = not settings["link_lines"]
	SimulationManager.simulate()

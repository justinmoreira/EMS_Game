extends CanvasLayer

# Settings state
var settings = {
	"link_lines": true,
	"unit_ranges": false,
	"unit_details": true,
	"suggestions": true,
	"bidirectional_link_lines": false,
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
	%UnitRangesToggle.toggled.connect(_on_unit_ranges_toggled)
	%UnitDetailsToggle.toggled.connect(_on_unit_details_toggled)
	%SuggestionsToggle.toggled.connect(_on_suggestions_toggled)
	%BidirectionalLinkLinesToggle.toggled.connect(_on_bidirectional_link_lines_toggled)
	
	# Load saved settings
	_load_settings()


func _on_settings_button_pressed():
	var popup = %SettingsPopup
	
	# Toggle popup visibility
	if popup.visible:
		popup.hide()
	else:
		var button_rect = %SettingsButton.get_global_rect()
	
		# Position popup below the button
		var popup_pos = button_rect.position + Vector2(button_rect.size.x - 280, button_rect.size.y + 5)
		popup.position = popup_pos
		popup.show()
		popup.grab_focus()


func _on_popup_focus_exited():
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
	
	# Call SimulationManager if it exists
	if SimulationManager:
		SimulationManager.links_visible = is_pressed


func _on_unit_ranges_toggled(is_pressed: bool):
	settings["unit_ranges"] = is_pressed
	_save_settings()
	
	# Call method on level if it exists
	var level = get_tree().current_scene
	if level.has_method("toggle_unit_ranges"):
		level.toggle_unit_ranges(is_pressed)


func _on_unit_details_toggled(is_pressed: bool):
	settings["unit_details"] = is_pressed
	_save_settings()
	
	# Call method on level if it exists
	var level = get_tree().current_scene
	if level.has_method("toggle_unit_details"):
		level.toggle_unit_details(is_pressed)


func _on_suggestions_toggled(is_pressed: bool):
	settings["suggestions"] = is_pressed
	_save_settings()
	
	# Call method on level if it exists
	var level = get_tree().current_scene
	if level.has_method("toggle_suggestions"):
		level.toggle_suggestions(is_pressed)


func _on_bidirectional_link_lines_toggled(is_pressed: bool):
	settings["bidirectional_link_lines"] = is_pressed
	_save_settings()
	
	# Call method on level if it exists
	var level = get_tree().current_scene
	if level.has_method("toggle_bidirectional_links"):
		level.toggle_bidirectional_links(is_pressed)


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
	%UnitRangesToggle.button_pressed = settings["unit_ranges"]
	%UnitDetailsToggle.button_pressed = settings["unit_details"]
	%SuggestionsToggle.button_pressed = settings["suggestions"]
	%BidirectionalLinkLinesToggle.button_pressed = settings["bidirectional_link_lines"]
	%Toggle.button_pressed = settings["heightmap_shader"]
	%GridToggle.button_pressed = settings["grid"]

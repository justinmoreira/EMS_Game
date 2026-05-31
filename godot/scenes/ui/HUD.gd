extends CanvasLayer


func _ready():
	%Toggle.toggled.connect(_on_shader_toggled)
	%GridToggle.toggled.connect(_on_grid_toggled)
	%RangeToggle.toggled.connect(_on_range_toggled)
	%HeatmapToggle.toggled.connect(_on_heatmap_toggled)


func _on_shader_toggled(is_pressed: bool):
	var level = get_tree().current_scene
	if level.has_method("toggle_shader"):
		level.toggle_shader(is_pressed)


func _on_grid_toggled(is_pressed: bool):
	var level = get_tree().current_scene
	if level.has_method("toggle_grid"):
		level.toggle_grid(is_pressed)


func _on_range_toggled(is_pressed: bool):
	var level = get_tree().current_scene
	if level.has_method("toggle_signal_ranges"):
		level.toggle_signal_ranges(is_pressed)


func _on_heatmap_toggled(is_pressed: bool):
	var level = get_tree().current_scene
	if not level:
		return
	if level.has_method("toggle_terrain_heatmap"):
		level.toggle_terrain_heatmap(is_pressed)

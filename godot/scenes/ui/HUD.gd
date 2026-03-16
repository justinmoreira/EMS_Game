extends CanvasLayer


func _ready():
	%Toggle.toggled.connect(_on_shader_toggled)
	%GridToggle.toggled.connect(_on_grid_toggled)


func _on_shader_toggled(is_pressed: bool):
	var level = get_tree().current_scene
	if level.has_method("toggle_shader"):
		level.toggle_shader(is_pressed)


func _on_grid_toggled(is_pressed: bool):
	var level = get_tree().current_scene
	if level.has_method("toggle_grid"):
		level.toggle_grid(is_pressed)

extends CanvasLayer


func _ready():
    # Use the percent sign for the %Toggle unique name defined in the .tscn
    %Toggle.toggled.connect(_on_shader_toggled)


func _on_shader_toggled(is_pressed: bool):
    var level = get_tree().current_scene
    if level.has_method("toggle_shader"):
        level.toggle_shader(is_pressed)

extends Control
class_name BaseLevel

@onready var background := $BackgroundTexture

var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_mouse_pos := Vector2.ZERO

func _ready():
	get_tree().get_root().size_changed.connect(_on_window_resized)
	_on_window_resized()

func _on_window_resized():
	self.size = get_viewport_rect().size
	update_shader()

func toggle_shader(enabled: bool):
	if background and background.material:
		background.material.set_shader_parameter("sensitivity", 1.0 if enabled else 0.0)

func update_shader():
	if background and background.material:
		var aspect = size.x / size.y
		background.material.set_shader_parameter("zoom", zoom)
		background.material.set_shader_parameter("offset", offset)
		background.material.set_shader_parameter("aspect_ratio", aspect)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = clamp(zoom * 0.9, 0.1, 1.0)
			update_shader()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = clamp(zoom * 1.1, 0.1, 1.0)
			update_shader()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			last_mouse_pos = event.position
			
	elif event is InputEventMouseMotion and dragging:
		var delta = (event.position - last_mouse_pos) / get_viewport_rect().size
		offset -= delta * zoom
		
		# Clamp logic
		var margin = (1.0 - zoom) / 2.0
		offset.x = clamp(offset.x, -margin, margin)
		offset.y = clamp(offset.y, -margin, margin)
		
		last_mouse_pos = event.position
		update_shader()
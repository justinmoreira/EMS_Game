extends Node2D

@onready var panel: Panel = $Panel
@onready var prompt: Label = $Panel/Prompt

var _style_available := StyleBoxFlat.new()
var _style_occupied := StyleBoxFlat.new()

func _ready() -> void:
	# Pull styles from scene if already assigned
	if panel.has_theme_stylebox_override("panel"):
		_style_available = panel.get_theme_stylebox("panel") as StyleBoxFlat
	# fallback occupied style
	_style_occupied.bg_color = Color(0.2, 0.12, 0.08, 0.45)
	_style_occupied.border_width_left = 3
	_style_occupied.border_width_top = 3
	_style_occupied.border_width_right = 3
	_style_occupied.border_width_bottom = 3
	_style_occupied.border_color = Color(1, 0.55, 0.25, 0.95)

func set_occupied(occupied: bool) -> void:
	if occupied:
		panel.add_theme_stylebox_override("panel", _style_occupied)
		prompt.text = "Transceiver\nPlaced"
	else:
		panel.add_theme_stylebox_override("panel", _style_available)
		prompt.text = "Place\nTransceiver"

extends Node2D

@onready var panel: Panel = get_node_or_null("Panel") as Panel
@onready var prompt: Label = get_node_or_null("Panel/Prompt") as Label

var _style_available: StyleBoxFlat
var _style_occupied: StyleBoxFlat


func _ready() -> void:
	visible = true
	z_as_relative = false
	z_index = 9999

	if panel == null:
		push_error("SilentLinkSlotVisual: Panel node missing")
		return

	# capture available style
	var sb := panel.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		_style_available = (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
	else:
		_style_available = StyleBoxFlat.new()
		_style_available.bg_color = Color(0.08, 0.18, 0.25, 0.35)
		_style_available.border_width_left = 3
		_style_available.border_width_top = 3
		_style_available.border_width_right = 3
		_style_available.border_width_bottom = 3
		_style_available.border_color = Color(0.25, 0.85, 1.0, 0.95)

	_style_occupied = StyleBoxFlat.new()
	_style_occupied.bg_color = Color(0.2, 0.12, 0.08, 0.45)
	_style_occupied.border_width_left = 3
	_style_occupied.border_width_top = 3
	_style_occupied.border_width_right = 3
	_style_occupied.border_width_bottom = 3
	_style_occupied.border_color = Color(1.0, 0.55, 0.25, 0.95)

	set_occupied(false)


func set_occupied(occupied: bool) -> void:
	if panel == null:
		return

	panel.add_theme_stylebox_override("panel", _style_occupied if occupied else _style_available)

	if prompt != null:
		prompt.text = "Transceiver\nPlaced" if occupied else "Place\nTransceiver"

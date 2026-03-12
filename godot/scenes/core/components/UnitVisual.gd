extends Node2D

const RADIUS := 32.0
const FONT_SIZE := 25

# Set these in the Inspector per unit type
@export var unit_label: String = "T"  # "T", "J", or "S"
@export var circle_color: Color = Color("4fc3f7")  # match sidebar accent


func _draw() -> void:
	# Outer circle
	draw_circle(Vector2.ZERO, RADIUS, Color(circle_color, 0.8))
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, circle_color, 1.5)

	# Unit letter centered
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(unit_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var offset := Vector2(-text_size.x / 2.0, text_size.y / 4.0)
	draw_string(font, offset, unit_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)

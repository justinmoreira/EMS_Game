extends Node2D
class_name PatternedLinkLine

var start_point := Vector2.ZERO
var end_point := Vector2.ZERO
var line_color := Color.WHITE
var line_pattern := LinkVisuals.LINE_PATTERN_SOLID
var dash_offset := 0.0


func set_points(new_start: Vector2, new_end: Vector2) -> void:
	start_point = new_start
	end_point = new_end
	queue_redraw()


func set_visual(new_color: Color, new_pattern: int) -> void:
	line_color = new_color
	line_pattern = new_pattern
	queue_redraw()


func advance_dash(delta: float) -> void:
	if line_pattern != LinkVisuals.LINE_PATTERN_MOVING_DASHED:
		return

	dash_offset = fmod(
		dash_offset + LinkVisuals.DASH_SPEED * delta,
		LinkVisuals.DASH_LENGTH + LinkVisuals.GAP_LENGTH
	)

	queue_redraw()


func _draw() -> void:
	LinkVisuals.draw_pattern(
		self, start_point, end_point, line_color, line_pattern, dash_offset, LinkVisuals.LINE_WIDTH
	)

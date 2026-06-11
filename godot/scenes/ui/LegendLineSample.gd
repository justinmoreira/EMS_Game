extends Control
class_name LegendLineSample

var sample_color: Color = Color.WHITE
var sample_pattern: int = LinkVisuals.LINE_PATTERN_SOLID
var dash_offset := 0.0


func _ready() -> void:
	size = Vector2(92, 22)
	custom_minimum_size = Vector2(92, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(sample_pattern == LinkVisuals.LINE_PATTERN_MOVING_DASHED)
	queue_redraw()


func setup(new_color: Color, new_pattern: int) -> void:
	sample_color = new_color
	sample_pattern = new_pattern
	set_process(sample_pattern == LinkVisuals.LINE_PATTERN_MOVING_DASHED)
	queue_redraw()


func _process(delta: float) -> void:
	if sample_pattern != LinkVisuals.LINE_PATTERN_MOVING_DASHED:
		return

	dash_offset = fmod(
		dash_offset + LinkVisuals.DASH_SPEED * delta,
		LinkVisuals.DASH_LENGTH + LinkVisuals.GAP_LENGTH
	)
	queue_redraw()


func _draw() -> void:
	var start := Vector2(4, size.y * 0.5)
	var end := Vector2(size.x - 4, size.y * 0.5)

	LinkVisuals.draw_pattern(
		self, start, end, sample_color, sample_pattern, dash_offset, LinkVisuals.LINE_WIDTH
	)

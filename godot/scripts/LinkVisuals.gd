extends Node
class_name LinkVisuals

const LINE_PATTERN_SOLID := 0
const LINE_PATTERN_DASHED := 1
const LINE_PATTERN_MOVING_DASHED := 2
const LINE_PATTERN_ZIGZAG := 3

const C_SUCCESS := Color.GREEN
const C_CONNECTING := Color.YELLOW
const C_OUT_OF_RANGE := Color.DARK_ORANGE
const C_JAMMED := Color.RED
const C_FREQUENCY_DIFF := Color.CYAN
const C_BANDWIDTH_PENALTY := Color.MAGENTA

const LINE_WIDTH := 4.0
const DASH_LENGTH := 14.0
const GAP_LENGTH := 8.0
const DASH_SPEED := 55.0
const ZIGZAG_STEP := 10.0
const ZIGZAG_AMPLITUDE := 5.0


static func draw_pattern(
	canvas_item: CanvasItem,
	start: Vector2,
	end: Vector2,
	color: Color,
	pattern: int,
	dash_offset: float = 0.0,
	width: float = LINE_WIDTH
) -> void:
	match pattern:
		LINE_PATTERN_SOLID:
			canvas_item.draw_line(start, end, color, width, true)

		LINE_PATTERN_DASHED:
			_draw_dashed(canvas_item, start, end, color, 0.0, width)

		LINE_PATTERN_MOVING_DASHED:
			_draw_dashed(canvas_item, start, end, color, dash_offset, width)

		LINE_PATTERN_ZIGZAG:
			_draw_zigzag(canvas_item, start, end, color, width)


static func _draw_dashed(
	canvas_item: CanvasItem, start: Vector2, end: Vector2, color: Color, offset: float, width: float
) -> void:
	var direction := end - start
	var distance := direction.length()

	if distance <= 0.0:
		return

	var dir := direction.normalized()
	var step := DASH_LENGTH + GAP_LENGTH
	var current_distance := -offset

	while current_distance < distance:
		var dash_start_distance: float = max(current_distance, 0.0)
		var dash_end_distance: float = min(current_distance + DASH_LENGTH, distance)

		if dash_end_distance > 0.0:
			var dash_start := start + dir * dash_start_distance
			var dash_end := start + dir * dash_end_distance
			canvas_item.draw_line(dash_start, dash_end, color, width, true)

		current_distance += step


static func _draw_zigzag(
	canvas_item: CanvasItem, start: Vector2, end: Vector2, color: Color, width: float
) -> void:
	var direction := end - start
	var distance := direction.length()

	if distance <= 0.0:
		return

	var dir := direction.normalized()
	var normal := Vector2(-dir.y, dir.x)

	var points: Array[Vector2] = [start]

	var current_distance := ZIGZAG_STEP
	var side := 1.0

	while current_distance < distance:
		var base_point := start + dir * current_distance
		var zigzag_point := base_point + normal * ZIGZAG_AMPLITUDE * side
		points.append(zigzag_point)

		side *= -1.0
		current_distance += ZIGZAG_STEP

	points.append(end)

	for i in range(points.size() - 1):
		canvas_item.draw_line(points[i], points[i + 1], color, width, true)

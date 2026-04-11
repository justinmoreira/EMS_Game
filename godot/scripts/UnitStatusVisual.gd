class_name UnitStatusVisual
extends Node2D

enum Status {
	NONE,
	JAMMED,
	DETECTED,
	OUT_OF_RANGE,
}

const COLOR_JAMMED := Color(1.0, 0.2, 0.2, 0.95)
const COLOR_DETECTED := Color(0.75, 0.4, 1.0, 0.95)
const COLOR_OUT_OF_RANGE := Color(1.0, 0.55, 0.1, 0.95)

const BASE_RADIUS := 28.0
const RING_WIDTH := 4.0
const BADGE_OFFSET_Y := -38.0

const LABEL_FONT_SIZE := 12
const LABEL_Y_OFFSET := 48.0

var status: int = Status.NONE
var pulse_time: float = 0.0
var status_font: Font


func _ready() -> void:
	z_index = 250
	top_level = false
	set_process(true)
	visible = false

	# Use Godot's fallback font so text can draw without needing a custom font file.
	status_font = ThemeDB.fallback_font


func set_status(new_status: int) -> void:
	if status == new_status:
		return

	status = new_status
	visible = status != Status.NONE
	queue_redraw()


func _process(delta: float) -> void:
	if status == Status.NONE:
		return

	pulse_time += delta
	queue_redraw()


func _draw() -> void:
	match status:
		Status.JAMMED:
			_draw_jammed()
		Status.DETECTED:
			_draw_detected()
		Status.OUT_OF_RANGE:
			_draw_out_of_range()


func _draw_jammed() -> void:
	var pulse := 1.0 + 0.08 * sin(pulse_time * 6.0)
	var radius := BASE_RADIUS * pulse

	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, COLOR_JAMMED, RING_WIDTH, true)
	draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 48, Color(COLOR_JAMMED, 0.35), 2.0, true)

	_draw_status_label("Jammed", COLOR_JAMMED)


func _draw_detected() -> void:
	var sweep := fmod(pulse_time * 2.0, TAU)
	var radius := BASE_RADIUS + 1.5 * sin(pulse_time * 3.0)

	draw_arc(Vector2.ZERO, radius, sweep, sweep + PI * 1.2, 28, COLOR_DETECTED, RING_WIDTH, true)
	draw_arc(
		Vector2.ZERO,
		radius,
		sweep + PI,
		sweep + PI + PI * 0.8,
		24,
		Color(COLOR_DETECTED, 0.45),
		2.0,
		true
	)

	_draw_status_label("Detected", COLOR_DETECTED)


func _draw_out_of_range() -> void:
	var radius := BASE_RADIUS

	var segments := 16
	for i in range(segments):
		if i % 2 == 0:
			var a0 := TAU * float(i) / float(segments)
			var a1 := TAU * float(i + 1) / float(segments)
			draw_arc(Vector2.ZERO, radius, a0, a1, 6, COLOR_OUT_OF_RANGE, RING_WIDTH, true)

	_draw_status_label("Out of Range", COLOR_OUT_OF_RANGE)


func _draw_status_label(text: String, color: Color) -> void:
	if status_font == null:
		return

	var text_size := status_font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE
	)

	var text_pos := Vector2(-text_size.x * 0.5, LABEL_Y_OFFSET)

	draw_string(status_font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)

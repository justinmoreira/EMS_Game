class_name UnitStatusVisual
extends Node2D

enum Status { NONE, JAMMED, DETECTED }

const COLOR_JAMMED := Color(1.0, 0.2, 0.2, 0.95)
const COLOR_DETECTED := Color(0.75, 0.4, 1.0, 0.95)

const BASE_RADIUS := 28.0
const RING_WIDTH := 4.0
const BADGE_OFFSET_Y := -38.0

const LABEL_FONT_SIZE := 12
const LABEL_Y_OFFSET := 48.0

var status: int = Status.NONE
var pulse_time: float = 0.0
var status_font: Font

var _detection_visual: DetectionVisual = null


func _ready() -> void:
	z_index = 250
	top_level = false
	set_process(true)
	visible = true

	# Use Godot's fallback font so text can draw without needing a custom font file.
	status_font = ThemeDB.fallback_font

	if GameEvents.has_signal("simulation_complete"):
		GameEvents.simulation_complete.connect(_on_simulation_complete)

	if GameEvents.has_signal("detection_hints_toggled"):
		GameEvents.detection_hints_toggled.connect(_on_detection_hints_toggled)


func _on_detection_hints_toggled(enabled: bool) -> void:
	if is_instance_valid(_detection_visual):
		_detection_visual.visible = enabled


func _exit_tree() -> void:
	if GameEvents.simulation_complete.is_connected(_on_simulation_complete):
		GameEvents.simulation_complete.disconnect(_on_simulation_complete)


func set_status(new_status: int) -> void:
	if status == new_status:
		return

	status = new_status
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


func _draw_status_label(text: String, color: Color) -> void:
	if status_font == null:
		return

	var text_size := status_font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE
	)

	var text_pos := Vector2(-text_size.x * 0.5, LABEL_Y_OFFSET)

	draw_string(status_font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)


func _on_simulation_complete(_link_results: Array, detect_results: Array) -> void:
	var level = get_tree().current_scene
	var hints_allowed: bool = (
		level.get("detection_hints_enabled") if "detection_hints_enabled" in level else true
	)

	var parent_unit := get_parent() as Node2D
	if not is_instance_valid(parent_unit):
		return

	if not hints_allowed:
		if is_instance_valid(_detection_visual):
			_detection_visual.queue_free()
			_detection_visual = null
		return

	var hinted_this_sim: Array[int] = []

	for result in detect_results:
		if not result is Dictionary:
			continue

		var sensor := result.get("sensor") as Node2D
		var target := result.get("target") as Node2D

		if (
			sensor == parent_unit
			and is_instance_valid(target)
			and sensor.is_in_group("player_placed")
		):
			var detected: bool = result.get("detected", false)
			var fully_detected: bool = result.get("fully_detected", false)

			if detected and not fully_detected:
				var tx_id := target.get_instance_id()
				hinted_this_sim.append(tx_id)

				if not is_instance_valid(_detection_visual):
					_detection_visual = DetectionVisual.new()
					add_child(_detection_visual)

					_detection_visual.top_level = true
					_detection_visual.global_position = Vector2.ZERO

				_detection_visual.set_hint(
					parent_unit.global_position, target.global_position, tx_id
				)

	if is_instance_valid(_detection_visual):
		_detection_visual.retain_only(hinted_this_sim)

		if hinted_this_sim.is_empty():
			_detection_visual.queue_free()
			_detection_visual = null

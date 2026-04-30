extends Control
class_name ConnectionLegend

enum LinePattern { SOLID, DASHED, MOVING_DASHED, ZIGZAG }

const LEGEND_WIDTH := 230.0
const BUTTON_HEIGHT := 34.0
const PANEL_HEIGHT := 172.0

const C_SUCCESS := Color.GREEN
const C_CONNECTING := Color.YELLOW
const C_OUT_OF_RANGE := Color.DARK_ORANGE
const C_JAMMED := Color.RED

var is_open := false

var toggle_button: Button
var dropdown_panel: PanelContainer


class LegendLineSample:
	extends Control

	var sample_color: Color = Color.WHITE
	var sample_pattern: int = LinePattern.SOLID
	var dash_offset := 0.0

	func _ready() -> void:
		size = Vector2(92, 22)
		custom_minimum_size = Vector2(92, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(sample_pattern == LinePattern.MOVING_DASHED)
		queue_redraw()

	func setup(new_color: Color, new_pattern: int) -> void:
		sample_color = new_color
		sample_pattern = new_pattern
		set_process(sample_pattern == LinePattern.MOVING_DASHED)
		queue_redraw()

	func _process(delta: float) -> void:
		if sample_pattern == LinePattern.MOVING_DASHED:
			dash_offset = fmod(dash_offset + 55.0 * delta, 22.0)
			queue_redraw()

	func _draw() -> void:
		var start := Vector2(4, size.y * 0.5)
		var end := Vector2(size.x - 4, size.y * 0.5)

		match sample_pattern:
			LinePattern.SOLID:
				draw_line(start, end, sample_color, 4.0, true)

			LinePattern.DASHED:
				_draw_dashed(start, end, 0.0)

			LinePattern.MOVING_DASHED:
				_draw_dashed(start, end, dash_offset)

			LinePattern.ZIGZAG:
				_draw_zigzag(start, end)

	func _draw_dashed(start: Vector2, end: Vector2, offset: float) -> void:
		var direction := end - start
		var distance := direction.length()

		if distance <= 0.0:
			return

		var dir := direction.normalized()
		var dash_length := 14.0
		var gap_length := 8.0
		var step := dash_length + gap_length
		var current_distance := -offset

		while current_distance < distance:
			var dash_start_distance = max(current_distance, 0.0)
			var dash_end_distance = min(current_distance + dash_length, distance)

			if dash_end_distance > 0.0:
				var dash_start = start + dir * dash_start_distance
				var dash_end = start + dir * dash_end_distance
				draw_line(dash_start, dash_end, sample_color, 4.0, true)

			current_distance += step

	func _draw_zigzag(start: Vector2, end: Vector2) -> void:
		var direction := end - start
		var distance := direction.length()

		if distance <= 0.0:
			return

		var dir := direction.normalized()
		var normal := Vector2(-dir.y, dir.x)

		var points: Array[Vector2] = []
		points.append(start)

		var current_distance := 10.0
		var side := 1.0

		while current_distance < distance:
			var base_point := start + dir * current_distance
			var zigzag_point := base_point + normal * 5.0 * side
			points.append(zigzag_point)

			side *= -1.0
			current_distance += 10.0

		points.append(end)

		for i in range(points.size() - 1):
			draw_line(points[i], points[i + 1], sample_color, 4.0, true)


func _ready() -> void:
	size = Vector2(LEGEND_WIDTH, BUTTON_HEIGHT + PANEL_HEIGHT + 4.0)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_PASS
	z_index = 1000
	top_level = true
	_build_dropdown_legend()


func get_collapsed_width() -> float:
	return LEGEND_WIDTH


func _build_dropdown_legend() -> void:
	toggle_button = Button.new()
	toggle_button.text = "  Connection Legend ▼"
	toggle_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle_button.add_theme_font_size_override("font_size", 18)
	toggle_button.toggle_mode = true
	toggle_button.position = Vector2.ZERO
	toggle_button.size = Vector2(LEGEND_WIDTH, BUTTON_HEIGHT)
	toggle_button.custom_minimum_size = Vector2(LEGEND_WIDTH, BUTTON_HEIGHT)
	toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_button.z_index = 501
	toggle_button.pressed.connect(_on_toggle_pressed)
	add_child(toggle_button)

	dropdown_panel = PanelContainer.new()
	dropdown_panel.position = Vector2(-30, BUTTON_HEIGHT + 4.0)
	dropdown_panel.size = Vector2(LEGEND_WIDTH, PANEL_HEIGHT)
	dropdown_panel.custom_minimum_size = Vector2(LEGEND_WIDTH, PANEL_HEIGHT)
	dropdown_panel.visible = false
	dropdown_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dropdown_panel.z_index = 501
	add_child(dropdown_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.07, 0.09, 0.94)
	panel_style.border_color = Color(0.75, 0.85, 1.0, 0.45)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	dropdown_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.position = Vector2.ZERO
	margin.size = Vector2(LEGEND_WIDTH, PANEL_HEIGHT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	dropdown_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2.ZERO
	vbox.size = Vector2(LEGEND_WIDTH - 24.0, PANEL_HEIGHT - 20.0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_add_legend_row(vbox, "Success", C_SUCCESS, LinePattern.SOLID)
	_add_legend_row(vbox, "Fail / Out of Range", C_OUT_OF_RANGE, LinePattern.DASHED)
	_add_legend_row(vbox, "Sending / Connecting", C_CONNECTING, LinePattern.MOVING_DASHED)
	_add_legend_row(vbox, "Jammed / Interfered", C_JAMMED, LinePattern.ZIGZAG)


func _add_legend_row(parent: VBoxContainer, label_text: String, color: Color, pattern: int) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(LEGEND_WIDTH - 24.0, 24.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var sample := LegendLineSample.new()
	sample.setup(color, pattern)
	row.add_child(sample)

	var label := Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(label)


func _on_toggle_pressed() -> void:
	is_open = toggle_button.button_pressed
	dropdown_panel.visible = is_open

	if is_open:
		toggle_button.text = "  Connection Legend ▲"
	else:
		toggle_button.text = "  Connection Legend ▼"

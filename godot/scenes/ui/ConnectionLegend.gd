extends Control
class_name ConnectionLegend

const LEGEND_SIZE := Vector2(280, 160)

const C_SUCCESS := Color.GREEN
const C_CONNECTING := Color.YELLOW
const C_OUT_OF_RANGE := Color.DARK_ORANGE
const C_JAMMED := Color.RED


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = LEGEND_SIZE
	_build_legend()


func _build_legend() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = LEGEND_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.07, 0.09, 0.82)
	panel_style.border_color = Color(0.7, 0.8, 0.9, 0.35)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Connection Legend"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	_add_legend_row(vbox, "━━━━━━", "Success", C_SUCCESS)
	_add_legend_row(vbox, "━ ━ ━", "Fail / Out of Range", C_OUT_OF_RANGE)
	_add_legend_row(vbox, "━ ━ ━ ▶", "Sending / Connecting", C_CONNECTING)
	_add_legend_row(vbox, "/\\/\\/\\", "Jammed / Interfered", C_JAMMED)


func _add_legend_row(
	parent: VBoxContainer, sample_text: String, label_text: String, color: Color
) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var sample := Label.new()
	sample.text = sample_text
	sample.custom_minimum_size = Vector2(92, 20)
	sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sample.add_theme_font_size_override("font_size", 18)
	sample.add_theme_color_override("font_color", color)
	row.add_child(sample)

	var label := Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(label)

extends Control
class_name ConnectionLegend

enum LinePattern { SOLID, DASHED, MOVING_DASHED, ZIGZAG }

const LEGEND_WIDTH := 230.0
const BUTTON_HEIGHT := 34.0
const DROPDOWN_GAP := 4.0

const ROW_COUNT := 4
const ROW_HEIGHT := 24.0
const ROW_SEPARATION := 8.0
const PANEL_MARGIN_TOP_BOTTOM := 10.0
const PANEL_MARGIN_LEFT_RIGHT := 12.0
const PANEL_X_OFFSET := -30.0

const PANEL_HEIGHT := (
	ROW_COUNT * ROW_HEIGHT + (ROW_COUNT - 1) * ROW_SEPARATION + 2.0 * PANEL_MARGIN_TOP_BOTTOM
)

const C_SUCCESS := Color.GREEN
const C_CONNECTING := Color.YELLOW
const C_OUT_OF_RANGE := Color.DARK_ORANGE
const C_JAMMED := Color.RED

var is_open := false

var toggle_button: Button
var dropdown_panel: PanelContainer


func _ready() -> void:
	size = Vector2(LEGEND_WIDTH, BUTTON_HEIGHT + PANEL_HEIGHT + DROPDOWN_GAP)
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
	dropdown_panel.position = Vector2(PANEL_X_OFFSET, BUTTON_HEIGHT + DROPDOWN_GAP)
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
	margin.add_theme_constant_override("margin_left", int(PANEL_MARGIN_LEFT_RIGHT))
	margin.add_theme_constant_override("margin_top", int(PANEL_MARGIN_TOP_BOTTOM))
	margin.add_theme_constant_override("margin_right", int(PANEL_MARGIN_LEFT_RIGHT))
	margin.add_theme_constant_override("margin_bottom", int(PANEL_MARGIN_TOP_BOTTOM))
	dropdown_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2.ZERO
	vbox.size = Vector2(
		LEGEND_WIDTH - 2.0 * PANEL_MARGIN_LEFT_RIGHT, PANEL_HEIGHT - 2.0 * PANEL_MARGIN_TOP_BOTTOM
	)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", int(ROW_SEPARATION))
	margin.add_child(vbox)

	_add_legend_row(vbox, "Success", LinkVisuals.C_SUCCESS, LinkVisuals.LINE_PATTERN_SOLID)
	_add_legend_row(
		vbox, "Fail / Out of Range", LinkVisuals.C_OUT_OF_RANGE, LinkVisuals.LINE_PATTERN_DASHED
	)
	_add_legend_row(
		vbox,
		"Sending / Connecting",
		LinkVisuals.C_CONNECTING,
		LinkVisuals.LINE_PATTERN_MOVING_DASHED
	)
	_add_legend_row(
		vbox, "Jammed / Interfered", LinkVisuals.C_JAMMED, LinkVisuals.LINE_PATTERN_ZIGZAG
	)


func _add_legend_row(parent: VBoxContainer, label_text: String, color: Color, pattern: int) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(LEGEND_WIDTH - 2.0 * PANEL_MARGIN_LEFT_RIGHT, ROW_HEIGHT)
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

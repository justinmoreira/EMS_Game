class_name UnitAttributesLabel
extends Label

const DEFAULT_OFFSET := Vector2(70, 40)
const LABEL_SIZE := Vector2(190, 84)
const MAX_OFFSET_RADIUS := 120.0
const DRAG_CLICK_RADIUS := 110.0

var target_unit: Node2D = null
var target_component: Node = null

var label_offset: Vector2 = DEFAULT_OFFSET
var is_dragging_label: bool = false
var drag_mouse_start: Vector2 = Vector2.ZERO
var drag_offset_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	size = LABEL_SIZE
	visible = false
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_text = true

	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Color.WHITE)


func setup(unit: Node, component: Node) -> void:
	target_unit = unit as Node2D
	target_component = component
	label_offset = DEFAULT_OFFSET
	text = _build_text()
	_update_position()


func _process(_delta: float) -> void:
	if not visible:
		return

	text = _build_text()
	_update_position()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or target_unit == null:
		return

	var mouse_pos := target_unit.get_global_mouse_position()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _is_mouse_over_label(mouse_pos):
				is_dragging_label = true
				drag_mouse_start = mouse_pos
				drag_offset_start = label_offset
				get_viewport().set_input_as_handled()
		else:
			is_dragging_label = false

	elif event is InputEventMouseMotion and is_dragging_label:
		var mouse_delta := mouse_pos - drag_mouse_start
		label_offset = drag_offset_start + mouse_delta
		label_offset = _clamp_offset(label_offset)
		_update_position()
		get_viewport().set_input_as_handled()


func _update_position() -> void:
	position = label_offset - (size * 0.5)


func _clamp_offset(offset: Vector2) -> Vector2:
	if offset.length() > MAX_OFFSET_RADIUS:
		return offset.normalized() * MAX_OFFSET_RADIUS
	return offset


func _is_mouse_over_label(mouse_global: Vector2) -> bool:
	var label_center_global := target_unit.global_position + label_offset
	var local_mouse := mouse_global - label_center_global

	return (
		local_mouse.x >= -size.x * 0.5
		and local_mouse.x <= size.x * 0.5
		and local_mouse.y >= -size.y * 0.5
		and local_mouse.y <= size.y * 0.5
	)


func _build_text() -> String:
	if target_component == null or not target_component is Unit:
		return ""

	var unit: Unit = target_component
	if unit.definition == null:
		return ""

	var lines: PackedStringArray = []
	for spec in unit.definition.attributes:
		# unit_name is rendered next to the sprite, not in this label.
		if spec.id == &"unit_name":
			continue
		var value = unit.get_value(spec.id, spec.default_value)
		lines.append("%s: %s" % [_short_label(spec), _format_value(spec, value)])

	if lines.is_empty():
		lines.append("No attributes")

	return "\n".join(lines)


# Compact display name for the floating label (e.g. "Power" → "Pwr").
const _SHORT_LABELS := {
	&"power": "Pwr",
	&"frequency": "Freq",
	&"tuning_frequency": "Tune",
	&"transceiver_bandwidth": "BW",
	&"jammer_bandwidth": "BW",
	&"sensor_bandwidth": "BW",
	&"sensitivity": "Sens",
	&"is_scanning": "Scan",
	&"height": "H"
}


func _short_label(spec: AttributeSpec) -> String:
	return _SHORT_LABELS.get(spec.id, spec.display_name)


func _format_value(spec: AttributeSpec, value) -> String:
	match spec.kind:
		AttributeSpec.Kind.FLOAT:
			return "%.0f" % float(value)
		AttributeSpec.Kind.ENUM:
			var idx := int(value)
			if idx >= 0 and idx < spec.enum_options.size():
				return spec.enum_options[idx]
			return str(value)
		AttributeSpec.Kind.BOOL:
			return "On" if value else "Off"
	return str(value)

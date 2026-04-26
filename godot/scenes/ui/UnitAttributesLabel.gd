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
	if target_component == null:
		return ""

	var lines: PackedStringArray = []

	match target_component.name:
		"Transceiver":
			lines.append("Pwr: %s  H: %s" % [_safe_get("power", 0), _safe_get("height", 0)])
			lines.append("Freq: %s" % _fmt(_safe_get("frequency", 0.0)))
			lines.append("BW: %s" % _bandwidth_name(_safe_get("transceiver_bandwidth", 1)))

		"Jammer":
			lines.append("Pwr: %s  H: %s" % [_safe_get("power", 0), _safe_get("height", 0)])
			lines.append("Freq: %s" % _fmt(_safe_get("frequency", 0.0)))
			lines.append("BW: %s" % _bandwidth_name(_safe_get("jammer_bandwidth", 1)))

		"Sensor":
			lines.append("H: %s  Sens: %s" % [_safe_get("height", 0), _safe_get("sensitivity", 0)])
			lines.append("Tune: %s" % _fmt(_safe_get("tuning_frequency", 0)))
			lines.append("BW: %s" % _bandwidth_name(_safe_get("sensor_bandwidth", 1)))
			lines.append("Scan: %s" % ("On" if _safe_get("is_scanning", false) else "Off"))

		_:
			lines.append("No attributes")

	return "\n".join(lines)


func _safe_get(property_name: String, fallback: Variant) -> Variant:
	if target_component == null:
		return fallback

	for property in target_component.get_property_list():
		if property.name == property_name:
			return target_component.get(property_name)

	return fallback


func _fmt(value: Variant) -> String:
	if value is float:
		return "%.0f" % value
	return str(value)


func _bandwidth_name(value: int) -> String:
	match value:
		0:
			return "Narrow"
		1:
			return "Medium"
		2:
			return "Wide"
		_:
			return str(value)

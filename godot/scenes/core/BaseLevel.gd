class_name BaseLevel
extends Control

var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_mouse_pos := Vector2.ZERO
var currently_selected_unit: Node = null

@onready var background := $BackgroundTexture
@onready var sidebar_node = get_tree().root.find_child("Sidebar", true, false)


func _ready() -> void:
	get_tree().root.size_changed.connect(_on_window_resized)
	_on_window_resized()


func _on_window_resized() -> void:
	size = get_viewport_rect().size
	update_shader()


func toggle_shader(enabled: bool) -> void:
	if background and background.material:
		background.material.set_shader_parameter("sensitivity", 1.0 if enabled else 0.0)


func update_shader() -> void:
	if background and background.material:
		var aspect_ratio := size.x / size.y
		background.material.set_shader_parameter("zoom", zoom)
		background.material.set_shader_parameter("offset", offset)
		background.material.set_shader_parameter("aspect_ratio", aspect_ratio)


func _clamp_offset() -> void:
	var margin := (1.0 - zoom) / 2.0
	offset.x = clamp(offset.x, -margin, margin)
	offset.y = clamp(offset.y, -margin, margin)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("scene_path")


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var scene := load(data["scene_path"]) as PackedScene
	if scene == null:
		return

	var unit := scene.instantiate()
	if unit == null:
		return

	unit.position = at_position
	add_child(unit)
	# connect the section signal
	_on_unit_placed(unit)


func _on_unit_placed(unit: Node) -> void:
	if unit.has_signal("selected") and not unit.selected.is_connected(_on_unit_selected):
		unit.selected.connect(_on_unit_selected)

	if _is_transceiver_unit(unit):
		_link_new_transceiver(unit)


func _on_unit_selected(unit: Node) -> void:
	_deselect_current_unit()

	currently_selected_unit = unit
	_set_unit_selected_visual(unit, true)

	var component := _get_unit_component(unit)
	if component:
		_show_attributes(component)


func _deselect_current_unit() -> void:
	if currently_selected_unit == null:
		return

	_set_unit_selected_visual(currently_selected_unit, false)


func _set_unit_selected_visual(unit: Node, selected: bool) -> void:
	if unit == null:
		return

	var visual := unit.find_child("Visual")
	if visual and visual.has_method("set_selected"):
		visual.set_selected(selected)


func _get_unit_component(unit: Node) -> Node:
	if unit == null:
		return null

	for child in unit.get_children():
		if child.name in ["Transceiver", "Jammer", "Sensor"]:
			return child

	return null


func _show_attributes(component: Node) -> void:
	if sidebar_node == null or component == null:
		return

	match component.name:
		"Transceiver":
			sidebar_node.select_entity(
				sidebar_node.EntityType.TRANSCEIVER, "Transceiver", component
			)
		"Jammer":
			sidebar_node.select_entity(sidebar_node.EntityType.JAMMER, "Jammer", component)
		"Sensor":
			sidebar_node.select_entity(sidebar_node.EntityType.SENSOR, "Sensor", component)


func _is_transceiver_unit(unit: Node) -> bool:
	return _get_named_child(unit, "Transceiver") != null


func _get_all_transceiver_units() -> Array:
	var transceivers: Array = []

	for child in get_children():
		if _is_transceiver_unit(child):
			transceivers.append(child)

	return transceivers


func _link_new_transceiver(new_unit: Node) -> void:
	var sim_manager := get_node_or_null("/root/SimulationManager")
	if sim_manager == null:
		print("SimulationManager not found in /root")
		return

	var transceivers := _get_all_transceiver_units()

	for other_unit in transceivers:
		if other_unit == new_unit:
			continue

		print("Linking ", new_unit.name, " <-> ", other_unit.name)
		sim_manager.send_message(new_unit, other_unit)
		sim_manager.send_message(other_unit, new_unit)


func _get_named_child(parent: Node, child_name: String) -> Node:
	if parent == null:
		return null

	for child in parent.get_children():
		if child.name == child_name:
			return child

	return null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and dragging:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_apply_zoom(event.position, 0.9)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_apply_zoom(event.position, 1.1)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not get_viewport().gui_is_dragging():
				dragging = true
				last_mouse_pos = event.position
		else:
			dragging = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var delta := (event.position - last_mouse_pos) / get_viewport_rect().size
	offset -= delta * zoom
	_clamp_offset()
	last_mouse_pos = event.position
	update_shader()


func _apply_zoom(mouse_position: Vector2, zoom_factor: float) -> void:
	var old_zoom := zoom
	zoom = clamp(zoom * zoom_factor, 0.1, 1.0)

	var mouse_uv := mouse_position / get_viewport_rect().size - Vector2(0.5, 0.5)
	offset += mouse_uv * (old_zoom - zoom)

	_clamp_offset()
	update_shader()

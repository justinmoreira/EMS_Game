class_name BaseLevel
extends Control

# Camera / Viewport State
var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_mouse_pos := Vector2.ZERO
var sidebar_width: float = 0.0

# Selection State
var currently_selected_unit: Node = null

@onready var background := $BackgroundTexture
@onready var sidebar_node = get_tree().root.find_child("Sidebar", true, false)

# --- Initialization ---


func _ready() -> void:
	# Handle window resizing and sidebar layout
	get_tree().get_root().size_changed.connect(_on_window_resized)
	if sidebar_node:
		sidebar_node.resized.connect(_on_window_resized)

	_on_window_resized()


func _on_window_resized() -> void:
	self.size = get_viewport_rect().size
	sidebar_width = sidebar_node.size.x if sidebar_node else 0.0
	if background:
		background.offset_left = sidebar_width
	update_shader()


# --- Coordinate Space Math ---


func get_map_size() -> Vector2:
	return Vector2(size.x - sidebar_width, size.y)


func screen_to_world_uv(screen_pos: Vector2) -> Vector2:
	var map = get_map_size()
	var aspect = map.x / map.y
	var uv = (screen_pos - Vector2(sidebar_width, 0)) / map - Vector2(0.5, 0.5)
	if aspect > 1.0:
		uv.x *= aspect
	else:
		uv.y *= 1.0 / aspect
	return uv * zoom + Vector2(0.5, 0.5) + offset


func world_uv_to_screen(world_uv: Vector2) -> Vector2:
	var map = get_map_size()
	var aspect = map.x / map.y
	var uv = (world_uv - Vector2(0.5, 0.5) - offset) / zoom
	if aspect > 1.0:
		uv.x /= aspect
	else:
		uv.y *= aspect
	return (uv + Vector2(0.5, 0.5)) * map + Vector2(sidebar_width, 0)


# --- Visual Updates ---


func update_shader() -> void:
	if background and background.material:
		var map = get_map_size()
		var aspect = map.x / map.y
		background.material.set_shader_parameter("zoom", zoom)
		background.material.set_shader_parameter("offset", offset)
		background.material.set_shader_parameter("aspect_ratio", aspect)
	_reposition_units()


func toggle_shader(enabled: bool) -> void:
	if background and background.material:
		background.material.set_shader_parameter("sensitivity", 1.0 if enabled else 0.0)


func _reposition_units() -> void:
	var unit_scale = 1.0 / zoom
	for child in get_children():
		if child is EMSUnit and child.has_meta("world_uv"):
			child.position = world_uv_to_screen(child.get_meta("world_uv"))
			child.scale = Vector2(unit_scale, unit_scale)


func _clamp_offset() -> void:
	var margin := (1.0 - zoom) / 2.0
	offset.x = clamp(offset.x, -margin, margin)
	offset.y = clamp(offset.y, -margin, margin)


# --- Drag and Drop Logic ---


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if _at_position.x < sidebar_width:
		return false
	return data is Dictionary and data.has("scene_path")


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var scene := load(data["scene_path"]) as PackedScene
	if scene == null:
		return

	var unit := scene.instantiate()
	if unit == null:
		return

	# Set position and scale based on current camera zoom/offset
	unit.set_meta("world_uv", screen_to_world_uv(at_position))
	unit.position = at_position
	unit.scale = Vector2(1.0 / zoom, 1.0 / zoom)
	add_child(unit)

	# Apply any pending attribute changes from the sidebar
	if sidebar_node and sidebar_node.pending_attributes and sidebar_node.pending_attributes.size() > 0:
		var component: Node = null
		for child in unit.get_children():
			if child.name in ["Transceiver", "Jammer", "Sensor"]:
				component = child
				break

		if component:
			# Get the component's original script before applying attributes
			var original_script = component.get_script()

			# Apply all pending attributes
			for attr_name in sidebar_node.pending_attributes:
				component.set(attr_name, sidebar_node.pending_attributes[attr_name])

			# Restore the original script if it was somehow changed
			if component.get_script() != original_script:
				component.set_script(original_script)

		sidebar_node.pending_attributes.clear()

	# Connect the selection signal
	_on_unit_placed(unit)

func _on_unit_placed(unit: Node) -> void:
	# Connect selection signals
	if unit.has_signal("selected") and not unit.selected.is_connected(_on_unit_selected):
		unit.selected.connect(_on_unit_selected)


# --- Selection Logic ---


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
	currently_selected_unit = null
	# Reset sidebar to show placeholder
	if sidebar_node:
		sidebar_node.select_entity(sidebar_node.EntityType.NONE)


func _set_unit_selected_visual(unit: Node, selected: bool) -> void:
	if unit == null:
		return
	var visual := unit.find_child("Visual")
	if visual and visual.has_method("set_selected"):
		visual.set_selected(selected)


func _get_unit_component(unit: Node) -> Node:
	if unit == null:
		return null
	# Check children for functional components
	for child in unit.get_children():
		if child.name in ["Transceiver", "Jammer", "Sensor"]:
			return child
	return null


func _show_attributes(component: Node) -> void:
	if sidebar_node == null or component == null:
		return

	# Determine component type by node name and update Sidebar
	match component.name:
		"Transceiver":
			sidebar_node.select_entity(
				sidebar_node.EntityType.TRANSCEIVER, "Transceiver", component
			)
		"Jammer":
			sidebar_node.select_entity(sidebar_node.EntityType.JAMMER, "Jammer", component)
		"Sensor":
			sidebar_node.select_entity(sidebar_node.EntityType.SENSOR, "Sensor", component)


# --- Inputs (Camera Control) ---


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.position.x < sidebar_width:
			return

		# Zooming in/out toward the mouse position
		if event.pressed:
			var old_zoom = zoom
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom = clamp(zoom * 0.9, 0.1, 1.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom = clamp(zoom * 1.1, 0.1, 1.0)
			else:
				return  # Not a zoom event

			# Adjust offset so we zoom toward the mouse position
			var map = get_map_size()
			var mouse_uv = (event.position - Vector2(sidebar_width, 0)) / map - Vector2(0.5, 0.5)
			offset += mouse_uv * (old_zoom - zoom)
			_clamp_offset()
			update_shader()


# --- Unhandled Input (Camera Pan + Click-to-Deselect) ---


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.x < sidebar_width:
			return

		if event.pressed:
			# Check if click is on empty map (not on sidebar)
			if event.position.x > sidebar_width:
				# Check if any unit was clicked by seeing if any unit emits "selected"
				# If no unit handles the input, we deselect
				var mouse_pos = get_global_mouse_position()
				var clicked_unit = false

				# Check all units to see if one is under the cursor
				for child in get_children():
					if child is EMSUnit:
						var distance = child.global_position.distance_to(mouse_pos)
						if distance < 32:  # Matches the selection radius in EMSUnit.gd
							clicked_unit = true
							break

				# If no unit was clicked, deselect
				if not clicked_unit:
					_deselect_current_unit()
					get_tree().root.set_input_as_handled()

			dragging = true
			last_mouse_pos = event.position
		else:
			dragging = false

	elif event is InputEventMouseMotion and dragging:
		# Map panning
		var delta = (event.position - last_mouse_pos) / get_map_size()
		offset -= delta * zoom
		_clamp_offset()
		last_mouse_pos = event.position
		update_shader()

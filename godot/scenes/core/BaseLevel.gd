class_name BaseLevel
extends Control

var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_mouse_pos := Vector2.ZERO
var currently_selected_unit: Node = null
var sidebar_width: float = 0.0

@onready var background := $BackgroundTexture
@onready var sidebar = get_tree().root.find_child("Sidebar", true, false)


func _ready():
	get_tree().get_root().size_changed.connect(_on_window_resized)
	if sidebar:
		sidebar.resized.connect(_on_window_resized)
	_on_window_resized()


func get_map_size() -> Vector2:
	return Vector2(size.x - sidebar_width, size.y)


func _on_window_resized():
	self.size = get_viewport_rect().size
	sidebar_width = sidebar.size.x if sidebar else 0.0
	if background:
		background.offset_left = sidebar_width
	update_shader()


func toggle_shader(enabled: bool):
	if background and background.material:
		background.material.set_shader_parameter("sensitivity", 1.0 if enabled else 0.0)


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


func _reposition_units():
	var unit_scale = 1.0 / zoom
	for child in get_children():
		if child is EMSUnit and child.has_meta("world_uv"):
			child.position = world_uv_to_screen(child.get_meta("world_uv"))
			child.scale = Vector2(unit_scale, unit_scale)


func update_shader():
	if background and background.material:
		var map = get_map_size()
		var aspect = map.x / map.y
		background.material.set_shader_parameter("zoom", zoom)
		background.material.set_shader_parameter("offset", offset)
		background.material.set_shader_parameter("aspect_ratio", aspect)
	_reposition_units()


func _clamp_offset():
	var margin = (1.0 - zoom) / 2.0
	offset.x = clamp(offset.x, -margin, margin)
	offset.y = clamp(offset.y, -margin, margin)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if _at_position.x < sidebar_width:
		return false
	return data is Dictionary and data.has("scene_path")


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var scene := load(data["scene_path"]) as PackedScene
	if scene == null:
		return
	var unit := scene.instantiate()
	unit.set_meta("world_uv", screen_to_world_uv(at_position))
	unit.position = at_position
	unit.scale = Vector2(1.0 / zoom, 1.0 / zoom)
	add_child(unit)

	# Connect the selection signal
	_on_unit_placed(unit)


func _on_unit_placed(unit: Node) -> void:
	if unit.has_signal("selected"):
		unit.selected.connect(_on_unit_selected)


func _on_unit_selected(unit: Node) -> void:
	# Deselect previous
	if currently_selected_unit:
		var prev_visual = currently_selected_unit.find_child("Visual")
		if prev_visual:
			if prev_visual.has_method("set_selected"):
				prev_visual.set_selected(false)

	# Select new unit
	currently_selected_unit = unit
	var visual = unit.find_child("Visual")
	if visual:
		if visual.has_method("set_selected"):
			visual.set_selected(true)

	# Show attribute panel - find by name
	var component: Node = null
	for child in unit.get_children():
		if child.name in ["Transceiver", "Jammer", "Sensor"]:
			component = child
			break

	if component:
		_show_attributes(component)


func _show_attributes(component: Node) -> void:
	if sidebar == null:
		return

	# Determine component type by NAME instead of `is` check
	match component.name:
		"Transceiver":
			sidebar.select_entity(sidebar.EntityType.TRANSCEIVER, "Transceiver", component)
		"Jammer":
			sidebar.select_entity(sidebar.EntityType.JAMMER, "Jammer", component)
		"Sensor":
			sidebar.select_entity(sidebar.EntityType.SENSOR, "Sensor", component)


func _deselect_unit() -> void:
	# Deselect the visual
	if currently_selected_unit:
		var prev_visual = currently_selected_unit.find_child("Visual")
		if prev_visual:
			if prev_visual.has_method("set_selected"):
				prev_visual.set_selected(false)

	# Clear the selection
	currently_selected_unit = null

	# Reset sidebar to show placeholder
	if sidebar:
		sidebar.select_entity(sidebar.EntityType.NONE)


func _input(event):
	if event is InputEventMouseButton:
		if event.position.x < sidebar_width:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var old_zoom = zoom
			zoom = clamp(zoom * 0.9, 0.1, 1.0)
			var map = get_map_size()
			var mouse_uv = (event.position - Vector2(sidebar_width, 0)) / map - Vector2(0.5, 0.5)
			offset += mouse_uv * (old_zoom - zoom)
			_clamp_offset()
			update_shader()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var old_zoom = zoom
			zoom = clamp(zoom * 1.1, 0.1, 1.0)
			var map = get_map_size()
			var mouse_uv = (event.position - Vector2(sidebar_width, 0)) / map - Vector2(0.5, 0.5)
			offset += mouse_uv * (old_zoom - zoom)
			_clamp_offset()
			update_shader()


func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
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
					_deselect_unit()

			dragging = true
			last_mouse_pos = event.position
		else:
			dragging = false
	elif event is InputEventMouseMotion and dragging:
		var delta = (event.position - last_mouse_pos) / get_map_size()
		offset -= delta * zoom
		_clamp_offset()
		last_mouse_pos = event.position
		update_shader()

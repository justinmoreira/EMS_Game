class_name BaseLevel
extends Control

var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_mouse_pos := Vector2.ZERO
var currently_selected_unit: Node = null

@onready var background := $BackgroundTexture
@onready var sidebar = get_tree().root.find_child("Sidebar", true, false)


func _ready():
	get_tree().get_root().size_changed.connect(_on_window_resized)
	_on_window_resized()


func _on_window_resized():
	self.size = get_viewport_rect().size
	update_shader()


func toggle_shader(enabled: bool):
	if background and background.material:
		background.material.set_shader_parameter("sensitivity", 1.0 if enabled else 0.0)


func update_shader():
	if background and background.material:
		var aspect = size.x / size.y
		background.material.set_shader_parameter("zoom", zoom)
		background.material.set_shader_parameter("offset", offset)
		background.material.set_shader_parameter("aspect_ratio", aspect)


func _clamp_offset():
	var margin = (1.0 - zoom) / 2.0
	offset.x = clamp(offset.x, -margin, margin)
	offset.y = clamp(offset.y, -margin, margin)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("scene_path")


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var scene := load(data["scene_path"]) as PackedScene
	if scene == null:
		return
	var unit := scene.instantiate()
	unit.position = at_position
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


func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var old_zoom = zoom
			zoom = clamp(zoom * 0.9, 0.1, 1.0)
			# Zoom toward mouse position
			var mouse_uv = event.position / get_viewport_rect().size - Vector2(0.5, 0.5)
			offset += mouse_uv * (old_zoom - zoom)
			_clamp_offset()
			update_shader()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var old_zoom = zoom
			zoom = clamp(zoom * 1.1, 0.1, 1.0)
			var mouse_uv = event.position / get_viewport_rect().size - Vector2(0.5, 0.5)
			offset += mouse_uv * (old_zoom - zoom)
			_clamp_offset()
			update_shader()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check if we're clicking on a UI element first
				if not get_viewport().gui_is_dragging():
					dragging = true
					last_mouse_pos = event.position
			else:
				dragging = false

	elif event is InputEventMouseMotion and dragging:
		var delta = (event.position - last_mouse_pos) / get_viewport_rect().size
		offset -= delta * zoom
		_clamp_offset()
		last_mouse_pos = event.position
		update_shader()

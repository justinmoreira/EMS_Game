class_name BaseLevel
extends Control

const SANDBOX_INTRO_POPUP := preload("res://scenes/ui/SandboxIntroPopup.tscn")
const TUTORIAL_HINT_POPUP := preload("res://scenes/ui/TutorialHintPopup.tscn")

enum TutorialStep { WELCOME, PLACE_TRANSCEIVER, DONE }

var _tutorial_step := TutorialStep.WELCOME

# Unit attribute controls
const TOGGLE_UNIT_ATTRIBUTES_KEY := KEY_H
const ATTRIBUTE_LABEL_SCRIPT := preload("res://scenes/ui/UnitAttributesLabel.gd")

# Camera / Viewport State
var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_mouse_pos := Vector2.ZERO
var sidebar_width: float = 0.0
var intro_popup_open := false

# Selection State
var currently_selected_unit: Node = null

var unit_attributes_visible: bool = false

@onready var background := $BackgroundTexture
@onready var sidebar_node = get_tree().root.find_child("Sidebar", true, false)

# --- Initialization ---


func _ready():
	# Handle window resizing and sidebar layout
	get_tree().get_root().size_changed.connect(_on_window_resized)
	if sidebar_node:
		sidebar_node.resized.connect(_on_window_resized)
	_on_window_resized()

	GameEvents.units_changed.connect(_on_units_changed_for_tutorial)

	# Check if tutorial was already completed
	var tutorial_done := false
	if OS.has_feature("web"):
		var result = JavaScriptBridge.eval("localStorage.getItem('user_progress') || '{}'")
		if result is String and result != "":
			tutorial_done = result.find('"tutorial_complete":true') != -1
		# Listen for reset tutorial from web UI
		JavaScriptBridge.eval("if(window.initTutorialListener) window.initTutorialListener()")

	if tutorial_done:
		_tutorial_step = TutorialStep.DONE
	else:
		_start_tutorial()


func _start_tutorial() -> void:
	if intro_popup_open:
		return

	var popup := SANDBOX_INTRO_POPUP.instantiate()
	intro_popup_open = true

	$CanvasLayer.add_child(popup)

	if popup.has_signal("continued"):
		popup.continued.connect(_on_intro_popup_closed)


func _on_intro_popup_closed() -> void:
	intro_popup_open = false
	_advance_tutorial()


func _advance_tutorial() -> void:
	match _tutorial_step:
		TutorialStep.WELCOME:
			_tutorial_step = TutorialStep.PLACE_TRANSCEIVER
			GameEvents.tutorial_filter_sidebar.emit([sidebar_node.EntityType.TRANSCEIVER])
			_show_tutorial_hint("Drag a [b]Transceiver[/b] from the sidebar onto the map to begin.")
		TutorialStep.PLACE_TRANSCEIVER:
			_tutorial_step = TutorialStep.DONE
			GameEvents.tutorial_filter_sidebar.emit([])
			if OS.has_feature("web"):
				JavaScriptBridge.eval(
					"if(window.setProgress) window.setProgress('{\"tutorial_complete\":true}')"
				)
			_show_tutorial_hint(
				"Great! You placed a transceiver.\nNow try adding Jammers and Sensors."
			)
		TutorialStep.DONE:
			pass


func _on_units_changed_for_tutorial() -> void:
	if _tutorial_step == TutorialStep.PLACE_TRANSCEIVER:
		if get_tree().get_nodes_in_group("transceivers").size() > 0:
			_advance_tutorial()


func _show_tutorial_hint(text: String) -> void:
	var popup := TUTORIAL_HINT_POPUP.instantiate()
	popup.hint_text = text
	$CanvasLayer.add_child(popup)


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


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("scene_path")):
		return false

	# Still reject sidebar drops
	if at_position.x < sidebar_width:
		return false

	# Convert mouse position into map UV space
	var world_uv := screen_to_world_uv(at_position)

	# Only allow drops inside the actual map
	return world_uv.x >= 0.0 and world_uv.x <= 1.0 and world_uv.y >= 0.0 and world_uv.y <= 1.0


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

	SimulationManager.simulate()

	# Apply any pending attribute changes from the sidebar
	if (
		sidebar_node
		and sidebar_node.pending_attributes
		and sidebar_node.pending_attributes.size() > 0
	):
		var component: Node = null
		for child in unit.get_children():
			if child.name in ["Transceiver", "Jammer", "Sensor"]:
				component = child
				break

		if component:
			for attr_name in sidebar_node.pending_attributes:
				component.set(attr_name, sidebar_node.pending_attributes[attr_name])

		sidebar_node.pending_attributes.clear()

	# Connect the selection signal
	_on_unit_placed(unit)
	_on_unit_selected(unit)


func _on_unit_placed(unit: Node) -> void:
	# Connect selection signals
	if unit.has_signal("selected") and not unit.selected.is_connected(_on_unit_selected):
		unit.selected.connect(_on_unit_selected)
	if unit is EMSUnit:
		var label = _get_or_create_attribute_label(unit)
		if label:
			label.visible = unit_attributes_visible


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
	# prevent gameplay after popup is open
	if intro_popup_open:
		return
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


func _unhandled_input(event: InputEvent) -> void:
	# prevent map interaction when popup is active
	if intro_popup_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return

		if event.keycode == TOGGLE_UNIT_ATTRIBUTES_KEY:
			_toggle_unit_attributes()
			get_viewport().set_input_as_handled()
			return

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


#show unit attribute helper function
func _toggle_unit_attributes() -> void:
	unit_attributes_visible = not unit_attributes_visible
	_apply_unit_attribute_visibility()


func _apply_unit_attribute_visibility() -> void:
	for child in get_children():
		if child is EMSUnit:
			var label = _get_or_create_attribute_label(child)
			if label:
				label.visible = unit_attributes_visible


func _get_or_create_attribute_label(unit: Node) -> UnitAttributesLabel:
	var existing = unit.get_node_or_null("UnitAttributesLabel")
	if existing:
		return existing as UnitAttributesLabel

	var component := _find_unit_component(unit)
	if component == null:
		return null

	var label := ATTRIBUTE_LABEL_SCRIPT.new()
	label.name = "UnitAttributesLabel"
	unit.add_child(label)
	label.setup(unit, component)
	label.visible = unit_attributes_visible
	return label


func _find_unit_component(unit: Node) -> Node:
	for child in unit.get_children():
		if child is Transceiver or child is Jammer or child is Sensor:
			return child

		for grandchild in child.get_children():
			if grandchild is Transceiver or grandchild is Jammer or grandchild is Sensor:
				return grandchild

	return null

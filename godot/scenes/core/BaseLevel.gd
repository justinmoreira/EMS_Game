class_name BaseLevel
extends Control

# Unit attribute controls
const TOGGLE_UNIT_ATTRIBUTES_KEY := KEY_H
const ATTRIBUTE_LABEL_SCRIPT := preload("res://scenes/ui/UnitAttributesLabel.gd")

# Camera / Viewport State
var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_mouse_pos := Vector2.ZERO

# Sidebar layout — populated via signal, no global find_child reach.
# Width is the live x-size of the sidebar; 0 if no sidebar in this scene.
var sidebar_width: float = 0.0

# Selection visual cache — the *previous* selected unit, so we know which to
# unhighlight when selection changes. Source of truth lives on GameEvents.
var _last_highlighted: Unit = null
var unit_attributes_visible: bool = false

@onready var background := $BackgroundTexture

# --- Initialization ---


func _ready():
	get_tree().get_root().size_changed.connect(_on_window_resized)
	GameEvents.selection_changed.connect(_on_selection_changed)
	GameEvents.simulation_requested.connect(SimulationManager.simulate)
	GameEvents.reset_requested.connect(_on_reset_requested)
	GameEvents.delete_requested.connect(_on_delete_requested)
	GameEvents.sidebar_resized.connect(_on_sidebar_resized)
	_on_window_resized()


func _on_sidebar_resized(width: float) -> void:
	sidebar_width = width
	_on_window_resized()


func _on_window_resized() -> void:
	self.size = get_viewport_rect().size
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
		if child is Unit and child.has_meta("world_uv"):
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
	if at_position.x < sidebar_width:
		return false
	return true


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

	# Apply pending attributes BEFORE add_child so the unit's _ready sees the
	# user-typed unit_name and skips its UnitNameManager.get_next_name call.
	# Pending attributes ride along in the drag payload — Sidebar attaches the
	# snapshot via EntityCard. No reach into Sidebar from here.
	var override: Dictionary = data.get("attributes_override", {})
	for attr_name in override:
		unit.set(attr_name, override[attr_name])

	add_child(unit)
	_on_unit_placed(unit)
	# Newly-placed unit is treated as selected so its panel opens.
	GameEvents.select(unit)


func _on_unit_placed(unit: Unit) -> void:
	var label = _get_or_create_attribute_label(unit)
	if label:
		label.visible = unit_attributes_visible


# --- Selection Logic (visual highlight only — state lives on GameEvents) ---


func _on_selection_changed(unit: Node) -> void:
	# Single-shot handler covers both new selection and re-selection. Since
	# `selected_unit` is the source of truth, just diff with our last paint.
	if _last_highlighted and _last_highlighted != unit:
		_set_unit_selected_visual(_last_highlighted, false)
	_last_highlighted = unit if unit is Unit else null
	if _last_highlighted:
		_set_unit_selected_visual(_last_highlighted, true)


func _set_unit_selected_visual(unit: Unit, selected: bool) -> void:
	if unit and unit.unit_visual:
		unit.unit_visual.set_selected(selected)


# --- Sidebar button handlers ---


func _on_reset_requested() -> void:
	# LinkRenderer also subscribes to reset_requested and clears its own visuals.
	UnitNameManager.reset()
	for group in [&"transceivers", &"jammers", &"sensors"]:
		for unit in get_tree().get_nodes_in_group(group):
			unit.queue_free()
	GameEvents.clear_selection()


func _on_delete_requested(unit: Node) -> void:
	# LinkRenderer's per-frame purge will drop links involving this unit
	# once is_instance_valid returns false post-queue_free.
	if unit:
		unit.queue_free()
	GameEvents.clear_selection()


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


func _unhandled_input(event: InputEvent) -> void:
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
			# Click on empty map (not on a unit) → deselect.
			if event.position.x > sidebar_width:
				var mouse_pos = get_global_mouse_position()
				var clicked_unit := false
				for child in get_children():
					if (
						child is Unit
						and child.global_position.distance_to(mouse_pos) < Unit.SELECTION_RADIUS
					):
						clicked_unit = true
						break
				if not clicked_unit:
					GameEvents.clear_selection()
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
		if child is Unit:
			var label = _get_or_create_attribute_label(child)
			if label:
				label.visible = unit_attributes_visible


func _get_or_create_attribute_label(unit: Unit) -> UnitAttributesLabel:
	var existing = unit.get_node_or_null("UnitAttributesLabel")
	if existing:
		return existing as UnitAttributesLabel
	if unit == null or unit.definition == null:
		return null

	var label := ATTRIBUTE_LABEL_SCRIPT.new()
	label.name = "UnitAttributesLabel"
	unit.add_child(label)
	# Pre-merge, attribute label took (wrapper, component); now they're the same node.
	label.setup(unit, unit)
	label.visible = unit_attributes_visible
	return label

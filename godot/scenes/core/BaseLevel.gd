class_name BaseLevel
extends Control

const SANDBOX_INTRO_POPUP := preload("res://scenes/ui/SandboxIntroPopup.tscn")

# Unit attribute controls
const TOGGLE_UNIT_ATTRIBUTES_KEY := KEY_H
const ATTRIBUTE_LABEL_SCRIPT := preload("res://scenes/ui/UnitAttributesLabel.gd")
const ERROR_POPUP := preload("res://scenes/ui/HintPopup.tscn")
const SUGGESTIONS_PANEL_SCENE := preload("res://scenes/ui/SuggestionsDialog.tscn")

const MAP_SIZE = Vector2(1080, 1080)
const MAP_ORIGIN = Vector2(570, 0)

# definition.id → unit scene to instantiate when reconstructing the level
# from a snapshot. Lookup table for serialize/deserialize_units below.
const _UNIT_SCENES := {
	&"transceiver": preload("res://scenes/core/units/TransceiverUnit.tscn"),
	&"jammer": preload("res://scenes/core/units/JammerUnit.tscn"),
	&"sensor": preload("res://scenes/core/units/SensorUnit.tscn"),
}

# Camera / Viewport State
var zoom := 1.0
var offset := Vector2.ZERO
var dragging := false
var last_mouse_pos := Vector2.ZERO

# Selection State
var currently_selected_unit: Node = null
var currently_hovered_unit: Node = null
var suggestions_panel: Control = null

@export var base_hover_radius: float = 32.0
@export var show_signal_ranges: bool = false
@export var suggestions_enabled: bool = false

@export var spectrum_enabled: bool = false

var spectrum_analyzer: SpectrumAnalyzer

# Sidebar layout — populated via signal, no global find_child reach.
# Width is the live x-size of the sidebar; 0 if no sidebar in this scene.
var sidebar_width: float = 0.0

# Selection visual cache — the *previous* selected unit, so we know which to
# unhighlight when selection changes. Source of truth lives on GameEvents.
var _last_highlighted: Unit = null
var unit_attributes_visible: bool = false
var terrain_heatmap_enabled: bool = false

@onready var background := $BackgroundTexture

const DESIGN_MAP_ORIGIN = Vector2(300.0, 0.0)
const DESIGN_MAP_SIZE = Vector2(1620.0, 1080.0)

# --- Initialization ---


func _ready():
	get_tree().get_root().size_changed.connect(_on_window_resized)
	GameEvents.selection_changed.connect(_on_selection_changed)
	GameEvents.simulation_requested.connect(SimulationManager.simulate)
	GameEvents.reset_requested.connect(_on_reset_requested)
	GameEvents.delete_requested.connect(_on_delete_requested)
	GameEvents.sidebar_resized.connect(_on_sidebar_resized)

	for child in get_children():
		if child is Unit:
			# If world_uv is null, it means it was pre-placed and not dragged/spawned
			if child.get_value(&"world_uv") == null:
				# Calculate UV purely based on the 1620x1080 Editor space
				var u = (child.global_position.x - DESIGN_MAP_ORIGIN.x) / DESIGN_MAP_SIZE.x
				var v = (child.global_position.y - DESIGN_MAP_ORIGIN.y) / DESIGN_MAP_SIZE.y

				# Inject it into the Unit's physical_state dictionary
				child.set_value(&"world_uv", Vector2(u, v))

	_on_window_resized()

	spectrum_analyzer = get_tree().get_root().find_child("SpectrumAnalyzer", true, false)

	toggle_suggestions(suggestions_enabled)


func _on_sidebar_resized(width: float) -> void:
	sidebar_width = width
	_on_window_resized()


func _on_window_resized() -> void:
	self.size = get_viewport_rect().size
	if background:
		background.offset_left = sidebar_width
	update_shader()


# --- Coordinate Space Math ---

# Single source of truth: the rectangle the background shader actually renders
# over. Overlays (units, labels) derive their screen positions from the SAME
# rect, so they can never move at a different scale than the terrain.
# `background` is a Control; .position/.size already account for the sidebar
# offset_left set in _on_window_resized.


func _map_origin() -> Vector2:
	return Vector2(sidebar_width, 0)


func get_map_size() -> Vector2:
	return Vector2(size.x - sidebar_width, size.y)


func screen_to_world_uv(screen_pos: Vector2) -> Vector2:
	var map = get_map_size()
	var aspect = map.x / map.y
	var uv = (screen_pos - _map_origin()) / map - Vector2(0.5, 0.5)
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
	return (uv + Vector2(0.5, 0.5)) * map + _map_origin()


func world_uv_to_terrain_px(world_uv: Vector2) -> Vector2:
	return world_uv * MAP_SIZE + MAP_ORIGIN


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
		if child is Unit and child.get_value(&"world_uv") != null:
			child.position = world_uv_to_screen(child.get_value(&"world_uv"))
			child.scale = Vector2(unit_scale, unit_scale)


func _clamp_offset() -> void:
	var margin := (1.0 - zoom) / 2.0
	offset.x = clamp(offset.x, -margin, margin)
	offset.y = clamp(offset.y, -margin, margin)


func _get_hover_radius_pixels() -> float:
	# TODO: Implement for selection too?
	return base_hover_radius * (1.0 / zoom)


# --- Drag and Drop Logic ---


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("scene_path")):
		return false
	if at_position.x < sidebar_width:
		return false

	# The map is world_uv ∈ [0,1]; outside that is the shader's void border.
	# Reject drops there so units can't be placed off the map.
	var world_uv := screen_to_world_uv(at_position)
	if world_uv.x < 0.0 or world_uv.x > 1.0 or world_uv.y < 0.0 or world_uv.y > 1.0:
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
	unit.set_value(&"world_uv", screen_to_world_uv(at_position))
	unit.position = at_position
	unit.scale = Vector2(1.0 / zoom, 1.0 / zoom)

	# Mark this unit as not saved to the scene file (instantiated at runtime).
	unit.owner = null

	# Apply pending attributes BEFORE add_child so the unit's _ready sees the
	# user-typed unit_name and skips its UnitNameManager.get_next_name call.
	# Pending attributes ride along in the drag payload — Sidebar attaches the
	# snapshot via EntityCard. No reach into Sidebar from here.
	var override: Dictionary = data.get("attributes_override", {})
	for attr_name in override:
		unit.set(attr_name, override[attr_name])

	add_child(unit)

	# Auto-sim on place (preserves main's #61 UX via round-8's event-bus pattern).
	GameEvents.simulation_requested.emit()

	# Apply current visual settings (show/hide ranges) from #74.
	_set_unit_show_range_visual(unit, show_signal_ranges)

	_on_unit_placed(unit)
	# Newly-placed unit is treated as selected so its panel opens.
	GameEvents.select(unit)

	GameEvents.unit_placed.emit(unit)
	GameEvents.units_changed.emit()


func _on_unit_placed(unit: Unit) -> void:
	currently_selected_unit = unit
	var label = _get_or_create_attribute_label(unit)
	if label:
		label.visible = unit_attributes_visible
	toggle_suggestions(suggestions_enabled)

	# Apply current visual settings (show/hide ranges)
	_set_unit_show_range_visual(unit, show_signal_ranges)
	_set_unit_show_terrain_heatmap(unit, terrain_heatmap_enabled)


# --- Selection Logic (visual highlight only — state lives on GameEvents) ---


func _on_selection_changed(unit: Node) -> void:
	var prev: Node = _last_highlighted
	if prev and prev != unit:
		_set_unit_selected_visual(prev, false)
		_set_unit_show_terrain_heatmap(prev, false)

	_last_highlighted = unit if unit is Unit else null
	if _last_highlighted:
		_set_unit_selected_visual(_last_highlighted, true)
		_set_unit_show_terrain_heatmap(_last_highlighted, terrain_heatmap_enabled)

	var focused: Unit = unit if unit is Unit else null
	LinkRenderer.set_focused_unit(focused)
	SimulationManager.simulate()

	if spectrum_analyzer:
		if unit and unit.is_in_group("sensors"):
			spectrum_analyzer.configure(unit)
		else:
			spectrum_analyzer.configure(null)


func _set_unit_selected_visual(unit: Unit, selected: bool) -> void:
	if unit and unit.unit_visual:
		unit.unit_visual.set_selected(selected)


# --- Sidebar button handlers ---


func _set_unit_hover_visual(unit: Node, hovered: bool) -> void:
	if unit == null:
		return
	for child in unit.get_children():
		if child is UnitVisual:
			child.set_hovered(hovered)
			break


func _set_unit_show_range_visual(unit: Node, enabled: bool) -> void:
	if unit == null:
		return
	for child in unit.get_children():
		if child is UnitVisual:
			child.set_show_range(enabled)
			break


func toggle_signal_ranges(enabled: bool) -> void:
	# Toggle display of signal ranges for all unit visuals
	show_signal_ranges = enabled
	for child in get_children():
		if child is Unit:
			_set_unit_show_range_visual(child, enabled)


func toggle_suggestions(enabled: bool) -> void:
	suggestions_enabled = enabled
	if enabled:
		if suggestions_panel == null:
			suggestions_panel = SUGGESTIONS_PANEL_SCENE.instantiate()
			add_child.call_deferred(suggestions_panel)
	else:
		if suggestions_panel:
			suggestions_panel.queue_free()
			suggestions_panel = null

	call_deferred("_refresh_suggestions_ui")


func toggle_spectrum(enabled: bool) -> void:
	spectrum_enabled = enabled

	if spectrum_analyzer:
		spectrum_analyzer.visible = enabled


func _refresh_suggestions_ui() -> void:
	if suggestions_panel == null:
		return

	if currently_selected_unit == null:
		return

	suggestions_panel._on_selection_changed(currently_selected_unit)


func _set_unit_show_terrain_heatmap(unit: Node, enabled: bool) -> void:
	if unit == null:
		return
	for child in unit.get_children():
		if child is UnitVisual:
			child.set_show_terrain_heatmap(enabled)
			break


func toggle_terrain_heatmap(enabled: bool) -> void:
	terrain_heatmap_enabled = enabled
	for child in get_children():
		if child is Unit:
			_set_unit_show_terrain_heatmap(child, enabled)


func _get_unit_component(unit: Node) -> Node:
	if unit == null:
		return null
	# Check children for functional components
	for child in unit.get_children():
		if child.name in ["Transceiver", "Jammer", "Sensor"]:
			return child
	return null


func _on_reset_requested() -> void:
	# LinkRenderer also subscribes to reset_requested and clears its own visuals.
	UnitNameManager.reset()
	for group in [&"transceivers", &"jammers", &"sensors"]:
		for unit in get_tree().get_nodes_in_group(group):
			if unit.is_removable:
				unit.queue_free()
	GameEvents.clear_selection()


func _on_delete_requested(unit: Node) -> void:
	# LinkRenderer's per-frame purge will drop links involving this unit
	# once is_instance_valid returns false post-queue_free.
	if unit && unit.is_removable:
		unit.queue_free()
	if unit && !unit.is_removable:
		var popup = ERROR_POPUP.instantiate()
		popup.hint_text = "This unit can not be removed."
		add_child(popup)
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

	# Hover logic
	elif event is InputEventMouseMotion:
		if dragging or event.position.x < sidebar_width:
			return

		var mouse_pos = get_global_mouse_position()
		var new_hover: Node = null
		for child in get_children():
			if child is Unit:
				var distance = child.global_position.distance_to(mouse_pos)
				if distance < _get_hover_radius_pixels():  # hover radius (pixels)
					new_hover = child
					break

		if new_hover != currently_hovered_unit:
			if currently_hovered_unit:
				_set_unit_hover_visual(currently_hovered_unit, false)
			currently_hovered_unit = new_hover
			if currently_hovered_unit:
				_set_unit_hover_visual(currently_hovered_unit, true)
			LinkRenderer.set_hovered_unit(currently_hovered_unit)
	return


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
				# Clicking on a unit hands off to the unit's own drag handler —
				# don't engage map pan or the two thrash each other.

				if clicked_unit:
					return

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


func toggle_unit_details(enabled: bool) -> void:
	unit_attributes_visible = enabled
	_apply_unit_attribute_visibility()


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


# --- Unit serialization (pure utilities) ---------------------------------
#
# These produce / consume a JSON-friendly snapshot of the level's units.
# They have NO side effects beyond the unit tree itself — no auto-saving,
# no event emission besides the explicit simulation_requested at the end of
# deserialize_units. A persister Node (e.g., ScenePersister.gd) decides
# when/where to call these for any given level.
#
# Snapshot shape:  Array of { "type": StringName id, "state": Dictionary }
# `state` is the unit's physical_state.duplicate(), with any Vector2 entries
# (currently just world_uv) split into {"x", "y"} for JSON friendliness.


func serialize_units() -> Array:
	var out: Array = []
	for child in get_children():
		if not (child is Unit and child.definition):
			continue
		var state: Dictionary = child.physical_state.duplicate()
		var uv = state.get(&"world_uv", null)
		if uv is Vector2:
			state[&"world_uv"] = {"x": uv.x, "y": uv.y}
		out.append({"type": String(child.definition.id), "state": state})
	return out


func deserialize_units(snapshot: Array) -> void:
	# Wipe the current scene before instantiating from the snapshot. queue_free
	# is deferred so we wait a frame before adding the replacements; otherwise
	# the new units race with the doomed ones and units_changed double-fires.
	for group in [&"transceivers", &"jammers", &"sensors"]:
		for u in get_tree().get_nodes_in_group(group):
			u.queue_free()
	await get_tree().process_frame

	for entry in snapshot:
		if not (entry is Dictionary):
			continue
		var type_id := StringName(String(entry.get("type", "")))
		var scene: PackedScene = _UNIT_SCENES.get(type_id)
		if scene == null:
			continue
		var state: Dictionary = entry.get("state", {})
		var world_uv := Vector2.ZERO
		var uv_raw = state.get("world_uv", null)
		if uv_raw is Dictionary:
			world_uv = Vector2(float(uv_raw.get("x", 0.0)), float(uv_raw.get("y", 0.0)))

		var unit: Unit = scene.instantiate()
		unit.owner = null
		# Seed physical_state BEFORE add_child so _ready sees the user's saved
		# values and skips the auto-name fallback.
		for k in state:
			if String(k) == "world_uv":
				continue
			unit.set(k, state[k])
		add_child(unit)
		unit.set_value(&"world_uv", world_uv)
		unit.global_position = world_uv_to_screen(world_uv)

	GameEvents.simulation_requested.emit()

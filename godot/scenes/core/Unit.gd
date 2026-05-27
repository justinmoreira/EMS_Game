class_name Unit extends Node2D

# A press+release that moves the cursor less than this counts as a click,
# not a drag. Above it, the unit is considered dragged.
const CLICK_DRAG_THRESHOLD_PX := 5.0
const SELECTION_RADIUS := 32.0

@export var definition: UnitDefinition
var physical_state: Dictionary = {}

var _unit_visual: UnitVisual

# Public accessor — used by BaseLevel for selection highlight.
var unit_visual: UnitVisual:
	get:
		return _unit_visual

var _selection_area: Area2D
var _is_being_dragged: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO       # mouse position at press
var _drag_start_unit_pos: Vector2 = Vector2.ZERO  # unit position at press (for cancel)
var _drag_distance: float = 0.0
# Tracks whether we've fired links_clear_requested this drag. Press alone
# shouldn't clear — only actual movement past CLICK_DRAG_THRESHOLD_PX. A pure
# click then leaves the existing sim visuals untouched.
var _drag_links_cleared: bool = false


func _ready() -> void:
	if definition == null:
		push_error("Unit %s has no definition resource" % name)
		return

	add_to_group(definition.group)
	_init_default_values()

	if get_value(&"unit_name", "") == "":
		set_value(&"unit_name", UnitNameManager.get_next_name(definition.id))

	GameEvents.units_changed.emit()
	_spawn_visual()
	_setup_selection_area()


func _exit_tree() -> void:
	GameEvents.units_changed.emit.call_deferred()


# ── Domain (definition / physical_state) ─────────────────────────────


# Returns the value for an attribute id, or fallback if unset.
func get_value(id: StringName, fallback = null):
	return physical_state.get(id, fallback)


# Writes a value and propagates to the visual when the change is observable.
func set_value(id: StringName, v) -> void:
	physical_state[id] = v
	if _unit_visual and id == &"unit_name":
		_unit_visual.unit_name = v
		_unit_visual.queue_redraw()


# Backwards-compatibility shim: existing callers (PhysicsEngine, Sidebar's
# pending_attributes apply) use Node.get/set with property names. Route
# those through physical_state so unit.power / unit.set("power", v) keep
# working without sprinkling get_value everywhere.
func _get(property: StringName):
	if physical_state.has(property):
		return physical_state[property]
	return null


func _set(property: StringName, value) -> bool:
	if definition and _has_attribute(property):
		set_value(property, value)
		return true
	return false


func _has_attribute(id: StringName) -> bool:
	for spec in definition.attributes:
		if spec.id == id:
			return true
	return false


func _init_default_values() -> void:
	for spec in definition.attributes:
		if not physical_state.has(spec.id):
			physical_state[spec.id] = spec.default_value


func _spawn_visual() -> void:
	_unit_visual = UnitVisual.new()
	_unit_visual.unit_label = definition.letter
	_unit_visual.circle_color = definition.color
	_unit_visual.sprite_sheet_path = definition.animated_sprite_path
	_unit_visual.unit_name = get_value(&"unit_name", "")
	add_child(_unit_visual)


# ── Interaction (drag / click select) ────────────────────────────────


func _setup_selection_area() -> void:
	_selection_area = Area2D.new()
	_selection_area.name = "SelectionArea"
	_selection_area.input_pickable = true

	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = SELECTION_RADIUS
	collision.shape = circle
	_selection_area.add_child(collision)
	add_child(_selection_area)
	# Click detection via Area2D picking — Godot only fires this on the unit
	# under the cursor, so click cost is O(1) instead of O(N) per event.
	_selection_area.input_event.connect(_on_selection_input)


func _on_selection_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Only the initial press starts a drag here. Release and motion live in
	# _input so they keep working when the cursor leaves the shape mid-drag.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_is_being_dragged = true
		_drag_start_pos = get_global_mouse_position()
		_drag_start_unit_pos = global_position
		_drag_distance = 0.0
		_drag_links_cleared = false
		get_tree().root.set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _is_being_dragged:
		return

	# Right-click during a drag → cancel: snap back, leave links untouched
	# (re-sim only if motion already cleared them so visuals get rebuilt).
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		global_position = _drag_start_unit_pos
		var bl = get_parent()
		if bl and bl.has_method("screen_to_world_uv"):
			set_value(&"world_uv", bl.screen_to_world_uv(_drag_start_unit_pos))
		_is_being_dragged = false
		if _drag_links_cleared:
			GameEvents.simulation_requested.emit()
		get_tree().root.set_input_as_handled()
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		# Click (no movement) → select only; drag (with movement) → recompute
		# links to reflect the new geometry. Avoids redundant sims on pure
		# selection/deselection clicks.
		if _drag_distance < CLICK_DRAG_THRESHOLD_PX:
			GameEvents.select(self)
		else:
			GameEvents.simulation_requested.emit()
		_is_being_dragged = false
		get_tree().root.set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		var base_level = get_parent()
		if not (base_level and base_level.has_method("screen_to_world_uv")):
			return

		# Clamp in SCREEN space (sidebar's right edge → viewport right edge).
		# Clamping in world-UV [0,1] would cut off the rectangular map's left
		# and right strips, since UV [0,1] is the square subregion of a
		# widescreen map. sidebar_width is published live via GameEvents.
		var mouse_pos = get_global_mouse_position()
		var screen_rect = get_viewport().get_visible_rect()
		mouse_pos.x = clamp(
			mouse_pos.x,
			screen_rect.position.x + base_level.sidebar_width,
			screen_rect.position.x + screen_rect.size.x
		)
		mouse_pos.y = clamp(
			mouse_pos.y,
			screen_rect.position.y,
			screen_rect.position.y + screen_rect.size.y
		)

		set_value(&"world_uv", base_level.screen_to_world_uv(mouse_pos))
		global_position = mouse_pos
		_drag_distance = _drag_start_pos.distance_to(global_position)

		# Fire-once: clear stale link visuals as soon as we know this is a real
		# drag (not a click). Pure clicks never reach this branch with enough
		# motion, so their existing visuals stay intact.
		if not _drag_links_cleared and _drag_distance >= CLICK_DRAG_THRESHOLD_PX:
			GameEvents.links_clear_requested.emit()
			_drag_links_cleared = true

		get_tree().root.set_input_as_handled()


func _process(_delta: float) -> void:
	# Defensive drag-end if we miss the release event (e.g., focus loss).
	if _is_being_dragged and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_being_dragged = false

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
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0


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
		_drag_distance = 0.0
		get_tree().root.set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _is_being_dragged:
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		if _drag_distance < CLICK_DRAG_THRESHOLD_PX:
			GameEvents.select(self)
		_is_being_dragged = false
		get_tree().root.set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		# Clamp by converting through the level's UV space — which already
		# accounts for sidebar/playable-area exclusion. No direct sidebar reach.
		var base_level = get_parent()
		if not (base_level and base_level.has_method("screen_to_world_uv")):
			return

		var mouse_pos = get_global_mouse_position()
		var world_uv = base_level.screen_to_world_uv(mouse_pos)
		var clamped := Vector2(clamp(world_uv.x, 0.0, 1.0), clamp(world_uv.y, 0.0, 1.0))

		if has_meta("world_uv"):
			set_meta("world_uv", clamped)

		global_position = base_level.world_uv_to_screen(clamped)
		_drag_distance = _drag_start_pos.distance_to(global_position)
		get_tree().root.set_input_as_handled()


func _process(_delta: float) -> void:
	# Defensive drag-end if we miss the release event (e.g., focus loss).
	if _is_being_dragged and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_being_dragged = false

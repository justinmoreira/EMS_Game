class_name EMSUnit
extends Node2D

signal selected(unit: Node)

# A press+release that moves the cursor less than this counts as a click,
# not a drag. Above it, the unit is considered dragged.
const CLICK_DRAG_THRESHOLD_PX := 5.0
const SELECTION_RADIUS := 32.0

var component: Node
var selection_area: Area2D
var is_being_dragged: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_distance: float = 0.0

# Reuse the parent BaseLevel's already-resolved sidebar reference
@onready var sidebar_node = (
	get_parent().sidebar_node if get_parent() and "sidebar_node" in get_parent() else null
)


func _ready() -> void:
	component = get_component_for(self)

	# Create the selection area with a same collision radius as entity
	selection_area = Area2D.new()
	selection_area.name = "SelectionArea"
	selection_area.input_pickable = true

	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = SELECTION_RADIUS
	collision.shape = circle

	selection_area.add_child(collision)
	add_child(selection_area)
	# Click detection via Area2D picking — Godot only fires this on the unit
	# under the cursor, so click cost is O(1) instead of O(N) per event.
	selection_area.input_event.connect(_on_selection_input)


func _on_selection_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Only the initial press starts a drag here. Release and motion live in
	# _input below so they keep working when the cursor leaves the shape mid-drag.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		is_being_dragged = true
		drag_start_pos = get_global_mouse_position()
		drag_distance = 0.0
		get_tree().root.set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Fast path: not dragging, ignore everything. Prior version did a
	# distance check on every event for every unit.
	if not is_being_dragged:
		return

	var mouse_pos = get_global_mouse_position()

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		if drag_distance < CLICK_DRAG_THRESHOLD_PX:
			selected.emit(self)
		is_being_dragged = false
		get_tree().root.set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		var can_move := true

		if sidebar_node and sidebar_node.get_global_rect().has_point(mouse_pos):
			can_move = false

		var screen_rect = get_viewport().get_visible_rect()
		var sidebar_w: float = sidebar_node.size.x if sidebar_node else 0.0

		# Clamp mouse_pos to viewport bounds
		mouse_pos.x = clamp(
			mouse_pos.x,
			screen_rect.position.x + sidebar_w,
			screen_rect.position.x + screen_rect.size.x
		)
		mouse_pos.y = clamp(
			mouse_pos.y, screen_rect.position.y, screen_rect.position.y + screen_rect.size.y
		)

		# Update the world_uv metadata
		if has_meta("world_uv"):
			var base_level = get_parent()
			if base_level and base_level.has_method("screen_to_world_uv"):
				var world_uv = base_level.screen_to_world_uv(mouse_pos)
				set_meta("world_uv", world_uv)

		if can_move:
			# Update position while dragging
			global_position = mouse_pos
			drag_distance = drag_start_pos.distance_to(mouse_pos)

		get_tree().root.set_input_as_handled()


# Single source of truth for "the Transceiver/Jammer/Sensor child of a unit".
# Previously this logic was duplicated 5 times across BaseLevel/EMSUnit/Sidebar
# with subtle variations (recursive vs direct, by-name vs by-type).
static func get_component_for(unit: Node) -> Node:
	if unit == null:
		return null
	for child in unit.get_children():
		if child is Transceiver or child is Jammer or child is Sensor:
			return child
	return null


func _process(_delta: float) -> void:
	if is_being_dragged:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_being_dragged = false

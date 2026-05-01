class_name EMSUnit
extends Node2D

signal selected(unit: Node)

var component: Node
var selection_area: Area2D
var is_being_dragged: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_distance: float = 0.0

@onready var sidebar_node = get_tree().root.find_child("Sidebar", true, false)

func _ready() -> void:
	# Find whichever component was instantiated
	for child in get_all_children(self):
		if child is Transceiver or child is Jammer or child is Sensor:
			component = child
			break

	# Create the selection area with a same collision radius as entity
	selection_area = Area2D.new()
	selection_area.name = "SelectionArea"
	selection_area.input_pickable = true

	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 32
	collision.shape = circle

	selection_area.add_child(collision)
	add_child(selection_area)


func _input(event: InputEvent) -> void:
	var mouse_pos = get_global_mouse_position()
	var distance = global_position.distance_to(mouse_pos)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if distance < 32:  # Within the 32 radius
			if event.pressed:
				# Start drag
				is_being_dragged = true
				drag_start_pos = mouse_pos
				drag_distance = 0.0
				get_tree().root.set_input_as_handled()
			else:
				# On release
				if drag_distance < 5.0:  # Click threshold
					# This was a click - select the unit
					selected.emit(self)

				is_being_dragged = false
				get_tree().root.set_input_as_handled()

	elif event is InputEventMouseMotion and is_being_dragged:
		var can_move := true
		
		if sidebar_node and sidebar_node.get_global_rect().has_point(mouse_pos):
			can_move = false
		
		var screen_rect = get_viewport().get_visible_rect()
		
		# Clamp mouse_pos to viewport bounds
		mouse_pos.x = clamp(mouse_pos.x, screen_rect.position.x + sidebar_node.size.x, screen_rect.position.x + screen_rect.size.x)
		mouse_pos.y = clamp(mouse_pos.y, screen_rect.position.y, screen_rect.position.y + screen_rect.size.y)
		
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


func get_all_children(node: Node) -> Array:
	var children = []
	for child in node.get_children():
		children.append(child)
		children.append_array(get_all_children(child))
	return children


func _process(delta: float) -> void:
	if is_being_dragged:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_being_dragged = false

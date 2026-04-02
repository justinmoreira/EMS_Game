class_name EMSUnit
extends Node2D

signal selected(unit: Node)

var component: Node
var selection_area: Area2D


func _ready() -> void:
	# Find whichever component was instantiated
	for child in get_all_children(self):
		if child is Transceiver or child is Jammer or child is Sensor:
			component = child
			break

	# Create the selection area with a bigger collision radius
	selection_area = Area2D.new()
	selection_area.name = "SelectionArea"
	selection_area.input_pickable = true
	#add_child(selection_area)

	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 100
	collision.shape = circle

	selection_area.add_child(collision)
	add_child(selection_area)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		var distance = global_position.distance_to(mouse_pos)

		if distance < 100:  # Within the 100 radius
			selected.emit(self)
			get_tree().root.set_input_as_handled()


func get_all_children(node: Node) -> Array:
	var children = []
	for child in node.get_children():
		children.append(child)
		children.append_array(get_all_children(child))
	return children

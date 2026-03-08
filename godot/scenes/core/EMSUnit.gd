class_name EMSUnit
extends Area2D

@export_group("ID")
@export var unit_name: String = "New Unit"
@export var unit_id: String = "0000"

@export_group("Physics")
@export_range(0, 10) var height: int = 5

@export_group("Status")
@export var is_active: bool = true


func _ready():
	input_pickable = true


func _input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var sidebar = get_tree().current_scene.get_node("CanvasLayer/Control/Sidebar")
		print("clicked unit: ", unit_name)  # add this to confirm clicks are registering
		print("sidebar found: ", sidebar)  # add this to confirm path is correct

		if find_child("Jammer"):
			sidebar.select_entity(2, unit_name, self)
		elif find_child("Transceiver"):
			sidebar.select_entity(1, unit_name, self)
		elif find_child("Sensor"):
			sidebar.select_entity(3, unit_name, self)

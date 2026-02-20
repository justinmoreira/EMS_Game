extends Node2D
class_name EMSUnit

@export_group("ID")
@export var unit_name: String = "New Unit"
@export var unit_id: String = "0000"

@export_group("Physics")
@export_range(0, 10) var height: int = 5

@export_group("Status")
@export var is_active: bool = true

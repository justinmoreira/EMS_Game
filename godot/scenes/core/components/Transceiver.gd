class_name Transceiver
extends Node

@export_group("Settings")
@export_range(0, 10) var power: int = 5
@export_range(30, 3000) var frequency: float = 1000.0

@export_group("Visual")
@export var unit_label: String = "T"
@export var circle_color: Color = Color("4fc3f7")
@export var sprite_sheet_path: String = "res://assets/sprites/transceiverAni.png"
@export var frame_width: int = 974
@export var frame_height: int = 970
@export var animation_speed: float = 12.0

var _unit_visual: Node2D


func _ready() -> void:
	_unit_visual = UnitVisual.new()
	_unit_visual.unit_label = unit_label
	_unit_visual.circle_color = circle_color
	_unit_visual.sprite_sheet_path = sprite_sheet_path
	_unit_visual.frame_width = frame_width
	_unit_visual.frame_height = frame_height
	_unit_visual.animation_speed = animation_speed
	add_child(_unit_visual)

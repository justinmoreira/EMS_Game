class_name Sensor
extends EMSUnit

@export_group("Settings")
@export_range(0, 10) var sensitivity: int = 3
@export_enum("Narrow", "Medium", "Wide") var sensor_bandwidth: int = 1
@export var is_scanning: bool = true

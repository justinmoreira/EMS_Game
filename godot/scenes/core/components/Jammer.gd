class_name Jammer
extends EMSUnit

@export_group("Settings")
@export_range(0, 10) var power: int = 5
@export_range(30, 3000) var frequency: float = 1000.0
@export_enum("Narrow", "Medium", "Wide") var jammer_bandwidth: int = 1

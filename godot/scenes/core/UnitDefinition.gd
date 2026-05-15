class_name UnitDefinition extends Resource

@export var id: StringName  # "transceiver" | "jammer" | "sensor"
@export var display_name: String
@export var group: StringName  # "transceivers" | "jammers" | "sensors"
@export var letter: String
@export var color: Color
@export var sprite_path: String
@export var animated_sprite_path: String
@export var attributes: Array[AttributeSpec] = []

class_name AttributeSpec extends Resource

enum Kind { INT, FLOAT, STRING, BOOL, ENUM }

@export var id: StringName
@export var display_name: String
@export var kind: Kind
@export var min_value: float = 0.0
@export var max_value: float = 0.0
@export var step: float = 1.0
@export var unit: String = ""
@export var enum_options: PackedStringArray
@export var default_value: Variant

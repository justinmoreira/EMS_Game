extends Node

signal units_changed

signal unit_placed(unit: Node)
signal unit_selected(unit: Node)
signal unit_deleted(unit: Node)

signal unit_attribute_changed(unit: Node, attribute_name: String, new_value: Variant)

signal tutorial_filter_sidebar(allowed_types: Array)
signal tutorial_filter_attributes(allowed_attributes: Array)
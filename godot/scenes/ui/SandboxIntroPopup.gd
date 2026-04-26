extends Control

signal continued

@onready var continue_button: Button = %ContinueButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	continue_button.grab_focus()
	continue_button.pressed.connect(_on_continue_pressed)


func _on_continue_pressed() -> void:
	hide()
	continued.emit()
	queue_free()

extends Control

signal continued

@export var hint_text: String = ""

@onready var hint_label: RichTextLabel = %HintLabel
@onready var ok_button: Button = %OkButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	hint_label.text = hint_text
	ok_button.grab_focus()
	ok_button.pressed.connect(_on_ok_pressed)


func _on_ok_pressed() -> void:
	hide()
	continued.emit()
	queue_free()

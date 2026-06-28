extends Control

signal continued
signal previous_requested

@export_multiline var hint_text := ""
@export var show_previous := false
@export var show_next := true

@onready var hint_label: RichTextLabel = %HintLabel
@onready var previous_button: Button = %PreviousButton
@onready var next_button: Button = %NextButton


func _ready() -> void:
	hint_label.text = hint_text

	previous_button.visible = show_previous
	next_button.visible = show_next

	previous_button.pressed.connect(_on_previous_pressed)
	next_button.pressed.connect(_on_next_pressed)


func _on_previous_pressed() -> void:
	previous_requested.emit()
	queue_free()


func _on_next_pressed() -> void:
	continued.emit()
	queue_free()

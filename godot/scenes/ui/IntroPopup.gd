extends Control

signal continued

var title_string: String = ""
var body_string: String = ""
var button_string: String = ""

@onready var title: Label = %Title
@onready var body: RichTextLabel = %Body
@onready var continue_button: Button = %ContinueButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	title.text = title_string
	body.text = body_string
	continue_button.text = button_string
	continue_button.grab_focus()
	continue_button.pressed.connect(_on_continue_pressed)


func _on_continue_pressed() -> void:
	hide()
	continued.emit()
	queue_free()

extends Control

const SANDBOX_SCENE_PATH := "res://scenes/levels/Sandbox.tscn"
const HOME_URL := "/"

@onready var return_home_button: Button = %ReturnHomeButton
@onready var sandbox_button: Button = %SandboxButton
@onready var restart_button: Button = %RestartButton


func _ready() -> void:
	return_home_button.pressed.connect(_go_to_home_page)
	sandbox_button.pressed.connect(_go_to_sandbox_mode)
	restart_button.pressed.connect(_restart_tutorial)


func _go_to_home_page() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = '%s';" % HOME_URL)
	else:
		print("Return to Home Page is only available in the web build.")


func _go_to_sandbox_mode() -> void:
	get_tree().change_scene_to_file(SANDBOX_SCENE_PATH)


func _restart_tutorial() -> void:
	get_tree().reload_current_scene()

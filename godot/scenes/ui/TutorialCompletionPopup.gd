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
	# In the web build the whole game lives on a single embedded canvas and the
	# active mode is decided by SceneLoader from the URL's ?mode= query. Doing an
	# in-engine change_scene here leaves the URL (and window.GAME_MODE / save
	# namespace) pointing at the tutorial, so a full-page navigation — the same
	# pattern the rest of the app uses to switch modes — is the reliable path.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = window.location.pathname + '?mode=sandbox';")
	else:
		get_tree().change_scene_to_file(SANDBOX_SCENE_PATH)


func _restart_tutorial() -> void:
	# Re-load the tutorial fresh. On web, navigate so SceneLoader boots a clean
	# tutorial from scratch; on desktop, reload the scene in place.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = window.location.pathname + '?mode=tutorial';")
	else:
		get_tree().reload_current_scene()

extends Node

const SANDBOX_SCENE_PATH := "res://scenes/levels/ContourDemo.tscn"
const TUTORIAL_SCENE_PATH := "res://scenes/levels/TutorialLevel.tscn"


func _ready() -> void:
	var mode := _get_mode_from_url()

	print("SceneRouter mode: ", mode)

	match mode:
		"tutorial":
			call_deferred("_change_scene", TUTORIAL_SCENE_PATH)
		"sandbox":
			call_deferred("_change_scene", SANDBOX_SCENE_PATH)
		_:
			call_deferred("_change_scene", SANDBOX_SCENE_PATH)


func _change_scene(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)

	if error != OK:
		push_error("Failed to load scene: " + scene_path + " Error code: " + str(error))


func _get_mode_from_url() -> String:
	if OS.has_feature("web"):
		var href := str(JavaScriptBridge.eval("window.location.href", true))

		if href.contains("mode=tutorial"):
			return "tutorial"

		if href.contains("mode=sandbox"):
			return "sandbox"

	return "sandbox"

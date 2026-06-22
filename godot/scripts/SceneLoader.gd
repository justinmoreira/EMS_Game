extends Node

const TUTORIAL_SCENE_PATH = "res://scenes/levels/TutorialLevel.tscn"
const SANDBOX_SCENE_PATH = "res://scenes/levels/ContourDemo.tscn"
const SILENT_LINK_SCENE_PATH = "res://scenes/silent-link/level-1.tscn"
const ENEMY_HUNTER_SCENE_PATH = "res://scenes/enemy-hunter/level-1.tscn"

func _ready():
	#var mode := _get_mode_from_url()
	var href := ""

	if OS.has_feature("web"):
		href = str(JavaScriptBridge.eval("window.location.href", true))

	print("URL:", href)

	var mode := _get_mode_from_url()
	print("Mode:", mode)

	match mode:
		"tutorial":
			call_deferred("_change_scene", TUTORIAL_SCENE_PATH)
		"sandbox":
			call_deferred("_change_scene", SANDBOX_SCENE_PATH)
		"silent-link":
			call_deferred("_change_scene", SILENT_LINK_SCENE_PATH)
		"enemy-hunter":
			call_deferred("_change_scene", ENEMY_HUNTER_SCENE_PATH)
		_:
			call_deferred("_change_scene", SANDBOX_SCENE_PATH)


func _get_mode_from_url() -> String:
	if OS.has_feature("web"):
		var href := str(JavaScriptBridge.eval("window.location.href", true))

		if href.contains("mode=tutorial"):
			return "tutorial"

		if href.contains("mode=sandbox"):
			return "sandbox"

		if href.contains("mode=silent-link"):
			return "silent-link"

		if href.contains("mode=enemy-hunter"):
			return "enemy-hunter"

	return "sandbox"


func _change_scene(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)

	if error != OK:
		push_error("Failed to load scene: " + scene_path + " Error code: " + str(error))

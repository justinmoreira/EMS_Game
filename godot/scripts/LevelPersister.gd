class_name LevelPersister
extends Node


func _ready() -> void:
	if not OS.has_feature("web"):
		return

	var scene_path := get_tree().current_scene.scene_file_path
	var mode := _mode_for(scene_path)
	if mode == "":
		return

	var data := {"scene_path": scene_path}
	var js_literal := JSON.stringify(JSON.stringify(data))
	var mode_literal := JSON.stringify(mode)
	JavaScriptBridge.eval(
		"window.saveSandbox && window.saveSandbox(" + js_literal + ", " + mode_literal + ")"
	)


## Called by the scene loader before it picks a scene to load.
## Returns "" if nothing saved (or not on web).
static func peek(mode: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var mode_literal := JSON.stringify(mode)
	var raw = JavaScriptBridge.eval(
		"window.getSandbox ? window.getSandbox(" + mode_literal + ') : ""'
	)
	if raw is String and raw != "":
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed.get("scene_path", "")
	return ""


## Derives the storage key from the scene's folder, e.g.
## "res://scenes/enemy-hunter/level-3.tscn" -> "enemy-hunter-level".
## Keeps Enemy Hunter and Silent Link in separate slots automatically —
## one script, no per-mode subclassing needed.
static func _mode_for(scene_path: String) -> String:
	if "enemy-hunter" in scene_path:
		return "enemy-hunter-level"
	if "silent-link" in scene_path:
		return "silent-link-level"
	return ""

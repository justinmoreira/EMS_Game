class_name TutorialPersister
extends ScenePersister

var _tutorial: Tutorial = null


func _ready() -> void:
	_tutorial = get_parent() as Tutorial
	if _tutorial == null:
		push_error("TutorialPersister expects a Tutorial parent; got %s" % get_parent())
		return
	super._ready()


func _is_tutorial_already_complete() -> bool:
	var raw = JavaScriptBridge.eval('window.getProgress ? window.getProgress() : ""')
	if not (raw is String) or raw == "":
		return false
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return bool(parsed.get("tutorial_complete", false))
	return false


func _extra_save_data() -> Dictionary:
	if _tutorial == null:
		return {}
	return _tutorial.serialize_tutorial_state()


func _apply_extra_data(extra: Dictionary) -> void:
	if _tutorial != null and not extra.is_empty():
		_tutorial.restore_tutorial_state(extra)


func _on_restore_complete(restored: bool) -> void:
	if _tutorial == null:
		return
	if not restored:
		_tutorial.start_fresh()

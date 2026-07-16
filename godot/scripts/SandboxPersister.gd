class_name SandboxPersister
extends ScenePersister

var _sandbox: Sandbox = null


func _ready() -> void:
	_sandbox = get_parent() as Sandbox
	if _sandbox == null:
		push_error("SandboxPersister expects a Sandbox parent; got %s" % get_parent())
		return
	super._ready()


func _extra_save_data() -> Dictionary:
	if _sandbox == null:
		return {}
	return {"terrain_seed": _sandbox.get_terrain_seed()}


func _apply_extra_data(extra: Dictionary) -> void:
	if _sandbox == null or extra.is_empty():
		return
	var seed_value = extra.get("terrain_seed", null)
	if seed_value != null:
		_sandbox.set_terrain_seed(int(seed_value))

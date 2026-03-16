extends Node


func _ready():
	var dir = DirAccess.open("res://tests/")
	if dir == null:
		print("[FAIL] Could not open res://tests/ directory")
		get_tree().quit()
		return
	for file_name in dir.get_files():
		if file_name.ends_with("Tests.gd"):
			var script = load("res://tests/" + file_name)
			var node = script.new()
			add_child(node)

	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

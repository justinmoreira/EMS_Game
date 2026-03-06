extends Node


func _ready():
	var dir = DirAccess.open("res://scenes/tests/")
	for file_name in dir.get_files():
		if file_name.ends_with("Tests.gd"):
			var script = load("res://scenes/tests/" + file_name)
			var node = script.new()
			add_child(node)

	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

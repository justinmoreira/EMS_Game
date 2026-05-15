extends Node


func _ready():
	# Get the scene parameter from the URL
	var scene_param = OS.get_cmdline_args()

	# For web exports, we need to use JavaScript to get the query parameter
	if OS.has_feature("web"):
		var scene_name = (
			JavaScriptBridge
			. eval(
				"""
			new URLSearchParams(window.location.search).get('scene')
		"""
			)
		)

		if scene_name and scene_name != "":
			var scene_path = "res://scenes/" + scene_name + ".tscn"
			print("Loading scene from URL parameter: ", scene_path)
			get_tree().change_scene_to_file(scene_path)

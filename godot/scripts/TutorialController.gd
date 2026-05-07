extends CanvasLayer

# Tutorial state machine. Lives as an autoload so it survives level swaps and
# doesn't need a scene-tree CanvasLayer in BaseLevel. Renders its popups directly.

const SANDBOX_INTRO_POPUP := preload("res://scenes/ui/SandboxIntroPopup.tscn")
const TUTORIAL_HINT_POPUP := preload("res://scenes/ui/TutorialHintPopup.tscn")

enum Step { WELCOME, PLACE_TRANSCEIVER, DONE }

var _step: Step = Step.WELCOME
var _intro_popup_open := false


func _ready() -> void:
	# Render above all 2D content.
	layer = 100

	GameEvents.units_changed.connect(_on_units_changed)

	if _is_tutorial_complete():
		_step = Step.DONE
	else:
		_start()

	if OS.has_feature("web"):
		# Reset hook from the web UI's "Tutorial" button.
		JavaScriptBridge.eval("if(window.initTutorialListener) window.initTutorialListener()")


func _is_tutorial_complete() -> bool:
	if not OS.has_feature("web"):
		return false
	var raw = JavaScriptBridge.eval("localStorage.getItem('user_progress') || ''")
	if not (raw is String) or raw == "":
		return false
	var data = JSON.parse_string(raw)
	if not data is Dictionary:
		return false
	return bool(data.get("tutorial_complete", false))


func _start() -> void:
	if _intro_popup_open:
		return
	var popup := SANDBOX_INTRO_POPUP.instantiate()
	_intro_popup_open = true
	add_child(popup)
	if popup.has_signal("continued"):
		popup.continued.connect(_on_intro_closed)


func _on_intro_closed() -> void:
	_intro_popup_open = false
	_advance()


func _advance() -> void:
	match _step:
		Step.WELCOME:
			_step = Step.PLACE_TRANSCEIVER
			GameEvents.tutorial_filter_sidebar.emit([&"transceiver"])
			_show_hint("Drag a [b]Transceiver[/b] from the sidebar onto the map to begin.")
		Step.PLACE_TRANSCEIVER:
			_step = Step.DONE
			GameEvents.tutorial_filter_sidebar.emit([])
			if OS.has_feature("web"):
				JavaScriptBridge.eval(
					"if(window.setProgress) window.setProgress('{\"tutorial_complete\":true}')"
				)
			_show_hint("Great! You placed a transceiver.\nNow try adding Jammers and Sensors.")
		Step.DONE:
			pass


func _on_units_changed() -> void:
	if _step == Step.PLACE_TRANSCEIVER:
		if get_tree().get_nodes_in_group("transceivers").size() > 0:
			_advance()


func _show_hint(text: String) -> void:
	var popup := TUTORIAL_HINT_POPUP.instantiate()
	popup.hint_text = text
	add_child(popup)

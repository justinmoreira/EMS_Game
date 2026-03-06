extends Node

var timer: Timer


func _ready():
	setup_timer()


func setup_timer():
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)


func set_transmission_speed(frequency: float) -> void:
	var delay = remap(frequency, 30, 3000, 10.0, 0.1)
	timer.wait_time = delay


func send_message():
	timer.start()


func _on_timer_timeout():
	pass

extends Node

var timer: Timer

const FREQUENCY_HIGH = 2.0
const FREQUENCY_MEDIUM = 5.0
const FREQUENCY_LOW = 10.0

func _ready():
	setup_timer()
	
	# Initial State
	set_transmission_speed(FREQUENCY_HIGH)

func setup_timer():
	timer = Timer.new()
	add_child(timer)
	
	timer.one_shot = false
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

# State Change Function
func set_transmission_speed(seconds: float) -> float:
	timer.wait_time = seconds
	
	timer.start() 
	
	return seconds

func _on_timer_timeout():
	pass
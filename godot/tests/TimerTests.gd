extends Node


func _ready():
	test_low_frequency_maps_to_high_delay()
	test_high_frequency_maps_to_low_delay()
	test_mid_frequency_maps_to_mid_delay()


func test_low_frequency_maps_to_high_delay():
	SimulationManager.set_transmission_speed(30.0)
	if is_equal_approx(SimulationManager.timer.wait_time, 10.0):
		print("[PASS] 30hz maps to 10 seconds")
	else:
		print("[FAIL] 30hz incorrectly maps to ", SimulationManager.timer.wait_time)


func test_high_frequency_maps_to_low_delay():
	SimulationManager.set_transmission_speed(3000.0)
	if is_equal_approx(SimulationManager.timer.wait_time, 0.1):
		print("[PASS] 3000hz maps to 0.1 seconds")
	else:
		print("[FAIL] 3000hz incorrectly maps to ", SimulationManager.timer.wait_time)


func test_mid_frequency_maps_to_mid_delay():
	SimulationManager.set_transmission_speed(1515.0)
	if is_equal_approx(SimulationManager.timer.wait_time, 5.05):
		print("[PASS] 1515hz maps to ~5 seconds")
	else:
		print("[FAIL] 1515hz incorrectly maps to ", SimulationManager.timer.wait_time)

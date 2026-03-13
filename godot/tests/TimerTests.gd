extends "res://tests/BaseTest.gd"


func _ready():
	test_low_frequency_maps_to_high_delay()
	test_high_frequency_maps_to_low_delay()
	test_mid_frequency_maps_to_mid_delay()


func test_low_frequency_maps_to_high_delay():
	SimulationManager.set_transmission_speed(30.0)
	assert_eq(SimulationManager.timer.wait_time, 10.0, "30hz maps to 10 seconds")


func test_high_frequency_maps_to_low_delay():
	SimulationManager.set_transmission_speed(3000.0)
	assert_eq(SimulationManager.timer.wait_time, 0.1, "3000hz maps to 0.1 seconds")


func test_mid_frequency_maps_to_mid_delay():
	SimulationManager.set_transmission_speed(1515.0)
	assert_eq(SimulationManager.timer.wait_time, 5.05, "1515hz maps to ~5 seconds")

extends "res://tests/BaseTest.gd"


func _ready() -> void:
	test_sensor_detection()


func test_sensor_detection():
	print("\nRunning Sensor Detection Tests...")

	# Test Detection
	var detected = PhysicsEngine.is_detected(
		1000.0, PhysicsEngine.Bandwidth.BW_NARROW, 1.0, 10.0, 10.0, 10.0, 1.0, 1.0
	)

	assert_true(detected, "Detection success case.")

	var detected2 = PhysicsEngine.is_detected(
		1000.0, PhysicsEngine.Bandwidth.BW_NARROW, 6.0, 10.0, 10.0, 10.0, 1.0, 1.0
	)

	assert_false(detected2, "Detection fail case.")

	var detected3 = PhysicsEngine.is_detected(
		1000.0, PhysicsEngine.Bandwidth.BW_WIDE, 1.0, 10.0, 10.0, 10.0, 1.0, 1.0
	)

	assert_false(detected3, "Detection fail case with wide bandwidth.")
	print("\n")

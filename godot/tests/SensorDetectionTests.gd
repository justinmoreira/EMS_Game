extends "res://tests/BaseTest.gd"


func _ready() -> void:
	test_sensor_detection()


func test_sensor_detection():
	print("\nRunning Sensor Detection Tests...")

	# Test Detection
	var detected = PhysicsEngine.is_detected(
		1000.0, PhysicsEngine.Bandwidth.BW_NARROW, 1.0, 10.0, 10.0, 10.0, 1.0, 1.0
	)

	if detected:
		print("[PASS] Detection success case")
	else:
		print("[FAIL] Detection should have succeeded")

	var detected2 = PhysicsEngine.is_detected(
		1000.0, PhysicsEngine.Bandwidth.BW_NARROW, 6.0, 10.0, 10.0, 10.0, 1.0, 1.0
	)

	if not detected2:
		print("[PASS] Detection fail case")
	else:
		print("[FAIL] Detection should have failed")

	var detected3 = PhysicsEngine.is_detected(
		1000.0, PhysicsEngine.Bandwidth.BW_WIDE, 1.0, 10.0, 10.0, 10.0, 1.0, 1.0
	)

	if not detected3:
		print("[PASS] Detection fail case")
	else:
		print("[FAIL] Detection should have failed")
	print("\n")

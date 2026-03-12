extends "res://tests/BaseTest.gd"


func _ready() -> void:
	test_sensor_detection()


func test_sensor_detection():
	print("\nRunning Sensor Detection Tests...")

	#Test Frequency Check
	var r1 = PhysicsEngine.frequency_check(
		PhysicsEngine.FrequencyBand.FQ_LOW, PhysicsEngine.Bandwidth.BW_NARROW
	)
	assert_true(r1, "Narrow allows Low")

	#Test Srx Calculation
	# Expected output:
	#Hf = 1 + (10+10)/20 = 2
	#Distance Loss= (1+1)^2 = 4
	#Srx = (10*2)/(4*1) = 5.0
	var srx = PhysicsEngine.calculate_srx(10.0, 10.0, 10.0, 1.0, 1.0)
	assert_eq(srx, 5.0, "Srx calculation correct")

	# Test Detection
	var detected = PhysicsEngine.is_detected(
		PhysicsEngine.FrequencyBand.FQ_LOW,
		PhysicsEngine.Bandwidth.BW_NARROW,
		1.0,
		10.0,
		10.0,
		10.0,
		1.0,
		1.0
	)
	assert_true(detected, "Detection success case")

	print("\n")

extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	test_sensor_detection()

	await get_tree().create_timer(0.1).timeout
	get_tree().quit()


func test_sensor_detection():
	print("\nRunning Sensor Detection Tests...")

	#Test Frequency Check

	var r1 = PhysicsEngine.frequency_check(
		PhysicsEngine.FrequencyBand.FQ_LOW, PhysicsEngine.Bandwidth.BW_NARROW
	)

	if r1:
		print("[PASS] Narrow allows Low")
	else:
		print("[Fail] Narrow allows Low")

	#Test Srx Calculation
	# Expected output:
	#Hf = 1 + (10+10)/20 = 2
	#Distance Loss= (1+1)^2 = 4
	#Srx = (10*2)/(4*1) = 5.0

	var srx = PhysicsEngine.calculate_srx(10.0, 10.0, 10.0, 1.0, 1.0)
	if is_equal_approx(srx, 5.0):
		print("[PASS] Srx calculation correct")
	else:
		print("[FAIL] Srx incorrect: Got ", srx)

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

	if detected:
		print("[PASS] Detection success case")
	else:
		print("[FAIL] Detection should have succeeded")

	print("\n")

extends Node


func _ready():
	test_calculate_interference()
	test_range_check()
	test_jamming_check()

	await get_tree().create_timer(0.1).timeout
	get_tree().quit()


func test_calculate_interference():
	print("Running Interference Tests...\n")

	# Test 1: No jammers
	var jammers = []
	var interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	if is_equal_approx(interference, 0.0):
		print("[PASS] No jammers: Got 0.0")
	else:
		print("[FAIL] No jammers: Expected 0.0, Got ", interference)

	# Test 2: Single jammer, same frequency (should interfere)
	# Jammer: power=5, height=5, at same position, frequency=1000 (same as rx)
	jammers = [
		{
			"frequency": 1000.0,
			"power": 5.0,
			"height": 5.0,
			"position": Vector2(100, 0),  # 1 km away
			"bandwidth": "Narrow"
		}
	]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	# JammerPowerAtRx = calculate_received_power(5, 5, 5, 1000, 1, 1) = 1.875
	# BandwidthPower = 1.0 (Narrow)
	# Total = 1.875 * 1.0 = 1.875
	if is_equal_approx(interference, 1.875):
		print("[PASS] Single jammer same frequency: Got 1.875")
	else:
		print("[FAIL] Single jammer same frequency: Expected 1.875, Got ", interference)

	# Test 3: Jammer outside frequency range (should NOT interfere)
	jammers = [
		{
			"frequency": 2000.0,  # Far from rx 1000 MHz
			"power": 5.0,
			"height": 5.0,
			"position": Vector2(100, 0),
			"bandwidth": "Narrow"  # 1 MHz range
		}
	]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	# Frequency diff = abs(1000 - 2000) = 1000 MHz
	# Bandwidth/2 = 1/2 = 0.5 MHz
	# 1000 > 0.5, so NO interference
	if is_equal_approx(interference, 0.0):
		print("[PASS] Jammer outside range: Got 0.0")
	else:
		print("[FAIL] Jammer outside range: Expected 0.0, Got ", interference)

	# Test 4: Multiple jammers
	jammers = [
		{
			"frequency": 1000.0,
			"power": 5.0,
			"height": 5.0,
			"position": Vector2(100, 0),
			"bandwidth": "Narrow"
		},
		{
			"frequency": 1000.5,  # Close to rx
			"power": 3.0,
			"height": 5.0,
			"position": Vector2(100, 0),
			"bandwidth": "Medium"  # 10 MHz range
		}
	]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	# Jammer 1: 1.875 * 1.0 = 1.875
	# Jammer 2: calculate_received_power(3, 5, 5, 1000.5, 1, 1) ≈ 2.25 * 0.5 = 1.125
	# Total ≈ 2.437
	if abs(interference - 2.437) < 0.01:
		print("[PASS] Multiple jammers: Got ~2.437")
	else:
		print("[FAIL] Multiple jammers: Expected ~2.437, Got ", interference)

	print("\n")


func test_range_check():
	print("Running Range Check Tests...\n")

	# Test 1: Signal above noise floor (in range)
	var result = PhysicsEngine.range_check(1.0)
	if result == true:
		print("[PASS] Signal above noise floor: true")
	else:
		print("[FAIL] Signal above noise floor: Expected true, Got ", result)

	# Test 2: Signal below noise floor (out of range)
	result = PhysicsEngine.range_check(0.3)
	if result == false:
		print("[PASS] Signal below noise floor: false")
	else:
		print("[FAIL] Signal below noise floor: Expected false, Got ", result)

	# Test 3: Signal exactly at noise floor (out of range)
	result = PhysicsEngine.range_check(0.5)
	if result == false:
		print("[PASS] Signal at noise floor: false")
	else:
		print("[FAIL] Signal at noise floor: Expected false, Got ", result)

	# Test 4: Signal just above noise floor (in range)
	result = PhysicsEngine.range_check(0.51)
	if result == true:
		print("[PASS] Signal just above noise floor: true")
	else:
		print("[FAIL] Signal just above noise floor: Expected true, Got ", result)

	print("\n")


func test_jamming_check():
	print("Running Jamming Check Tests...\n")

	# Test 1: Strong signal, no interference (success)
	var result = PhysicsEngine.jamming_check(5.0, 0.0)
	if result == true:
		print("[PASS] Strong signal, no interference: true")
	else:
		print("[FAIL] Strong signal, no interference: Expected true, Got ", result)

	# Test 2: Signal beaten by interference (jammed)
	result = PhysicsEngine.jamming_check(2.0, 2.0)
	# 2.0 > (2.0 + 0.5) = 2.0 > 2.5 = false
	if result == false:
		print("[PASS] Signal beaten by interference: false")
	else:
		print("[FAIL] Signal beaten by interference: Expected false, Got ", result)

	# Test 3: Signal barely beats interference (success)
	result = PhysicsEngine.jamming_check(3.0, 2.4)
	# 3.0 > (2.4 + 0.5) = 3.0 > 2.9 = true
	if result == true:
		print("[PASS] Signal barely beats interference: true")
	else:
		print("[FAIL] Signal barely beats interference: Expected true, Got ", result)

	# Test 4: Borderline case (exactly at threshold = jammed)
	result = PhysicsEngine.jamming_check(2.5, 2.0)
	# 2.5 > (2.0 + 0.5) = 2.5 > 2.5 = false
	if result == false:
		print("[PASS] Exactly at threshold: false")
	else:
		print("[FAIL] Exactly at threshold: Expected false, Got ", result)

	print("\nAll Jamming Tests Complete")

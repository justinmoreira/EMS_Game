extends "res://tests/BaseTest.gd"


func _ready():
	test_calculate_interference()
	test_range_check()
	test_jamming_check()


func test_calculate_interference():
	print("Running Interference Tests...\n")

	# Test 1: No jammers
	var jammers = []
	var interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	assert_eq(interference, 0.0, "No jammers: Got 0.0")

	# Test 2: Single jammer, same frequency (should interfere)
	# Jammer: power=5, height=5, at same position, frequency=1000 (same as rx)
	var jammer_a = Jammer.new()
	jammer_a.frequency = 1000.0
	jammer_a.power = 5.0
	jammer_a.height = 5.0
	jammer_a.position = Vector2(100, 0)
	jammer_a.jammer_bandwidth = "Narrow"
	jammers = [jammer_a]

	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	# JammerPowerAtRx = calculate_received_power(5, 5, 5, 1000, 1, 1) = 1.875
	# BandwidthPower = 1.0 (Narrow)
	# Total = 1.875 * 1.0 = 1.875
	assert_eq(interference, 1.875, "Single jammer same frequency: Got 1.875")

	jammer_a.free()

	var jammer = Jammer.new()
	jammer.frequency = 2000.0
	jammer.power = 5.0
	jammer.height = 5.0
	jammer.position = Vector2(100, 0)
	jammer.jammer_bandwidth = "Narrow"

	# Test 3: Jammer outside frequency range (should NOT interfere)
	jammers = [jammer]

	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)
	# Frequency diff = abs(1000 - 2000) = 1000 MHz
	# Bandwidth/2 = 1/2 = 0.5 MHz
	# 1000 > 0.5, so NO interference
	assert_eq(interference, 0.0, "Jammer outside range: Got 0.0")

	jammer.free()

	# Test 4: Multiple jammers
	var jammer1 = Jammer.new()
	jammer1.frequency = 1000.0
	jammer1.power = 5.0
	jammer1.height = 5.0
	jammer1.global_position = Vector2(100, 0)
	jammer1.jammer_bandwidth = 0
	var jammer2 = Jammer.new()
	jammer2.frequency = 1000.5
	jammer2.power = 3.0
	jammer2.height = 5.0
	jammer2.global_position = Vector2(100, 0)
	jammer2.jammer_bandwidth = 1

	jammers = [jammer1, jammer2]
	interference = PhysicsEngine.calculate_interference(1000.0, 5.0, Vector2(0, 0), jammers)

	# Jammer 1: 1.875 * 1.0 = 1.875
	# Jammer 2: calculate_received_power(3, 5, 5, 1000.5, 1, 1) ≈ 2.25 * 0.5 = 1.125
	# Total ≈ 2.437
	assert_approx(interference, 2.437, 0.01, "Multiple jammers: Got ~2.437")

	jammer1.free()
	jammer2.free()
	print("\n")


func test_range_check():
	print("Running Range Check Tests...\n")

	# Test 1: Signal above noise floor (in range)
	assert_true(PhysicsEngine.range_check(1.0), "Signal above noise floor: true")

	# Test 2: Signal below noise floor (out of range)
	assert_false(PhysicsEngine.range_check(0.3), "Signal below noise floor: false")

	# Test 3: Signal exactly at noise floor (out of range)
	assert_false(PhysicsEngine.range_check(0.5), "Signal at noise floor: false")

	# Test 4: Signal just above noise floor (in range)
	assert_true(PhysicsEngine.range_check(0.51), "Signal just above noise floor: true")

	print("\n")


func test_jamming_check():
	print("Running Jamming Check Tests...\n")

	# Test 1: Strong signal, no interference (success)
	assert_true(PhysicsEngine.jamming_check(5.0, 0.0), "Strong signal, no interference: true")

	# Test 2: Signal beaten by interference (jammed)
	# 2.0 > (2.0 + 0.5) = 2.0 > 2.5 = false
	assert_false(PhysicsEngine.jamming_check(2.0, 2.0), "Signal beaten by interference: false")

	# Test 3: Signal barely beats interference (success)
	# 3.0 > (2.4 + 0.5) = 3.0 > 2.9 = true
	assert_true(PhysicsEngine.jamming_check(3.0, 2.4), "Signal barely beats interference: true")

	# Test 4: Borderline case (exactly at threshold = jammed)
	# 2.5 > (2.0 + 0.5) = 2.5 > 2.5 = false
	assert_false(PhysicsEngine.jamming_check(2.5, 2.0), "Exactly at threshold: false")

	print("\nAll Jamming Tests Complete")
